# numeric.jl: the multifrontal LDLt on a `Symbolic`, sequential and over
# independent subtrees in parallel.
#
# Supernode s (postorder): its panel in Lx already holds the entries of K
# (assembly through `amap`); the update matrices of its children are added
# into the panel and into the new update matrix U_s (extend-add through the
# relative indices), the panel is factored (dense LDLt without pivoting), and
# U_s -= L21 D L21' is left for the parent. Update matrices live on a stack in
# postorder (`upd_off`); with threads, every parallel subtree has a stack of
# its own and the update of a subtree root goes to a buffer of its own.

"""
    Factor

Numeric LDLt on a `Symbolic`: `Lx` (supernode panels), pivots `d` and their
inverses `dinv`, the update stack, scratch, and the regularization count.
"""
mutable struct Factor
    S::Symbolic
    Lx::Vector{Float64}
    d::Vector{Float64}
    dinv::Vector{Float64}
    U::Vector{Float64}
    T::Vector{Vector{Float64}}          # per task scratch
    W::Vector{Vector{Float64}}          # per task scratch for an update matrix
    delta::Float64
    nreg::Int
    sched::Any                          # parallel schedule (or nothing)
    nthreads::Int
    leafL::Vector{Float64}              # L entry of every leaf pivot (contiguous copy for the solves)
end

function Factor(S::Symbolic; delta::Float64 = 1e-12, nthreads::Int = 1)
    maxw = 0
    for s in 1:S.nsup
        maxw = max(maxw, S.sup_ptr[s+1] - S.sup_ptr[s])
    end
    tsz = max(S.max_front * 32, S.max_r * maxw, 1)
    nt = max(nthreads, 1)
    sched = nt > 1 ? schedule_tree(S, nt) : nothing
    nu = sched === nothing ? S.nupd : sched.nupd
    Ts = sched === nothing ? [zeros(tsz)] : [[zeros(t) for t in sched.tsz]; [zeros(tsz)]]
    Ws = sched === nothing ? [zeros(max(S.max_r^2, 1))] : [[zeros(t) for t in sched.wsz]; [zeros(max(S.max_r^2, 1))]]
    return Factor(S, zeros(S.nlx), zeros(S.N), zeros(S.N), zeros(nu), Ts, Ws,
                  delta, 0, sched, nt, zeros(S.nleaf))
end

"Copy the stored entries of `K` (the matrix analysed by `symbolic`) into the panels."
function assemble!(F::Factor, K::SparseMatrixCSC)
    Lx = F.Lx
    fill!(Lx, 0.0)
    amap = F.S.amap
    nz = nonzeros(K)
    @inbounds for k in eachindex(amap)
        Lx[amap[k]] += nz[k]
    end
    return F
end

"Factor supernode s; its update matrix goes to `F.U[uo .+ (1:r^2)]` (`uo < 0`: a root, none). Returns the number of regularized pivots."
@inline function _factor_supernode!(F::Factor, s::Int, uo::Int, uoffs::Vector{Int}, T::Vector{Float64},
                                    W::Vector{Float64})
    S = F.S
    Lx = F.Lx; U = F.U
    @inbounds begin
        f = S.sup_ptr[s]; w = S.sup_ptr[s+1] - f
        r = S.str_ptr[s+1] - S.str_ptr[s]
        h = w + r
        off = S.lx_ptr[s]
        o = off - 1
        c1 = S.child_ptr[s]; c2 = S.child_ptr[s+1] - 1
        # where U_s is built: in place for a leaf, in scratch otherwise (the
        # children's updates occupy its final place until they are added)
        inplace = c1 > c2
        Ub = inplace ? U : W
        ub = inplace ? uo : 0
        rel = S.rel_idx
        # children's entries in the panel (their first columns, rel <= w)
        for c in c1:c2
            ch = S.child_idx[c]
            rc = S.str_ptr[ch+1] - S.str_ptr[ch]
            co = uoffs[ch]
            rb = S.str_ptr[ch] - 1
            for jj in 1:rc
                pj = rel[rb+jj]
                pj > w && break
                cj = co + (jj - 1) * rc
                tgt = o + (pj - 1) * h
                for ii in jj:rc
                    Lx[tgt+rel[rb+ii]] += U[cj+ii]
                end
            end
        end
        nreg = _ldlt_front!(Lx, off, h, w, F.d, f, S.signs, F.delta, T)
        if r > 0 && uo >= 0
            # U_s = -L21 D L21' (written, not accumulated), then the children's trailing entries
            _front_update!(Ub, ub, r, Lx, off, h, w, F.d, f, T; overwrite = true)
            for c in c1:c2
                ch = S.child_idx[c]
                rc = S.str_ptr[ch+1] - S.str_ptr[ch]
                co = uoffs[ch]
                rb = S.str_ptr[ch] - 1
                j0 = 1
                while j0 <= rc && rel[rb+j0] <= w
                    j0 += 1
                end
                for jj in j0:rc
                    pj = rel[rb+jj]
                    cj = co + (jj - 1) * rc
                    tgt = ub + (pj - w - 1) * r - w
                    for ii in jj:rc
                        Ub[tgt+rel[rb+ii]] += U[cj+ii]
                    end
                end
            end
            if !inplace
                copyto!(U, uo + 1, W, 1, r * r)
            end
        end
    end
    return nreg
end

"""
    factor!(F, K) -> F

Numeric factorization of `K` (same pattern as the analysed matrix) on the
symbolic analysis of `F`. Sequential, or over the parallel schedule when
`F.nthreads > 1`.
"""
function factor!(F::Factor, K::SparseMatrixCSC)
    assemble!(F, K)
    F.nreg = _factor_leaves!(F)
    if F.sched === nothing
        S = F.S
        T = F.T[1]; W = F.W[1]
        for s in (S.nleaf+1):S.nsup
            uo = S.parent[s] == 0 ? -1 : S.upd_off[s]
            F.nreg += _factor_supernode!(F, s, uo, S.upd_off, T, W)
        end
    else
        _factor_parallel!(F)
    end
    d = F.d; di = F.dinv
    @inbounds for i in eachindex(d)
        di[i] = 1.0 / d[i]
    end
    return F
end

"""
Leaf pivots (columns 1:nleaf, one off-diagonal entry each): pivot, L entry, and
the Schur complement update of the neighbour's diagonal, in one pass.
"""
function _factor_leaves!(F::Factor)
    S = F.S; Lx = F.Lx; d = F.d; L = F.leafL
    delta = F.delta; nreg = 0
    @inbounds for j in 1:S.nleaf
        o = S.lx_ptr[j]
        dj = Lx[o]
        sg = S.signs[j]
        if !(sg * dj > delta)
            dj = sg * delta; nreg += 1
        end
        t = Lx[o+1]
        l = t / dj
        d[j] = dj; Lx[o+1] = l; L[j] = l
        Lx[S.leaf_dpos[j]] -= t * l
    end
    return nreg
end

"Inertia check: number of pivots whose sign differs from the expected one (0 for a quasi-definite matrix)."
wrong_signs(F::Factor) = count(i -> F.S.signs[i] * F.d[i] <= 0, eachindex(F.d))
