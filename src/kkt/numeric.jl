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
    par_solve::Bool                     # solves over the schedule (else sequential)
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
    # threaded solves pay only on large factors (task start-up is 0.1 to 0.7 ms)
    par_solve = sched !== nothing && S.nnzL >= PAR_SOLVE_NNZ[]
    nu = sched === nothing ? S.nupd : sched.nupd
    Ts = sched === nothing ? [zeros(tsz)] : [[zeros(t) for t in sched.tsz]; [zeros(tsz)]]
    Ws = sched === nothing ? [zeros(max(S.max_r^2, 1))] : [[zeros(t) for t in sched.wsz]; [zeros(max(S.max_r^2, 1))]]
    return Factor(S, zeros(S.nlx), zeros(S.N), zeros(S.N), zeros(nu), Ts, Ws,
                  delta, 0, sched, par_solve, nt, zeros(S.nleaf))
end

"nnz(L) from which solves use the parallel schedule (EPYC 7702 measurements: below about 5e5 threaded solves are slower)."
const PAR_SOLVE_NNZ = Ref(500_000)

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
                                    W::Vector{Float64}; nt::Int = 1)
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
            j1 = 0
            while j1 < rc && rel[rb+j1+1] <= w
                j1 += 1
            end
            _extend_add!(Lx, U, rel, rb, co, rc, 1, j1, o, h, Ub, ub, r, w, nt)
        end
        nreg = _ldlt_front!(Lx, off, h, w, F.d, f, S.signs, F.delta, T; nt = nt)
        _flush_subnormals!(Lx, off, off + h * w - 1)        # while the panel is in cache
        if r > 0 && uo >= 0
            # U_s = -L21 D L21' (written, not accumulated), then the children's trailing entries
            _front_update!(Ub, ub, r, Lx, off, h, w, F.d, f, T; overwrite = true, nt = nt)
            for c in c1:c2
                ch = S.child_idx[c]
                rc = S.str_ptr[ch+1] - S.str_ptr[ch]
                co = uoffs[ch]
                rb = S.str_ptr[ch] - 1
                j0 = 1
                while j0 <= rc && rel[rb+j0] <= w
                    j0 += 1
                end
                _extend_add!(Lx, U, rel, rb, co, rc, j0, rc, o, h, Ub, ub, r, w, nt)
            end
            if !inplace
                _pcopy!(U, uo, W, r * r, nt)
            end
        end
    end
    return nreg
end

"""
Extend-add of the columns `j0:j1` of a child's update matrix (at `U[co+1]`,
r_c x r_c, relative indices `rel[rb+1:rb+rc]`) into the parent's panel (columns
mapping to positions <= w) or its update matrix `Ub`. Distinct child columns map
to distinct parent columns, so column ranges go to tasks when large.
"""
function _extend_add!(Lx, U, rel, rb, co, rc, j0, j1, o, h, Ub, ub, r, w, nt)
    j1 < j0 && return nothing
    function cols!(a, b)
        @inbounds for jj in a:b
            pj = rel[rb+jj]
            cj = co + (jj - 1) * rc
            if pj <= w
                tgt = o + (pj - 1) * h
                for ii in jj:rc
                    Lx[tgt+rel[rb+ii]] += U[cj+ii]
                end
            else
                tgt = ub + (pj - w - 1) * r - w
                for ii in jj:rc
                    Ub[tgt+rel[rb+ii]] += U[cj+ii]
                end
            end
        end
        return nothing
    end
    n = j1 - j0 + 1
    if nt > 1 && n * (rc - j0) >= 2 * PAR_THRESHOLD[] ÷ 64
        # chunks of about equal work (column jj carries rc - jj + 1 entries)
        nb = min(nt, n ÷ 16 + 1)
        tot = sum(rc - jj + 1 for jj in j0:j1)
        cuts = [j0]; acc = 0
        for jj in j0:j1
            acc += rc - jj + 1
            length(cuts) < nb && acc >= tot * length(cuts) / nb && push!(cuts, jj + 1)
        end
        push!(cuts, j1 + 1)
        @sync for k in 1:(length(cuts)-1)
            a = cuts[k]; b = cuts[k+1] - 1
            b >= a && Threads.@spawn cols!(a, b)
        end
    else
        cols!(j0, j1)
    end
    return nothing
end

"U[uo+1:uo+n] = W[1:n], in chunks over tasks when large."
function _pcopy!(U, uo, W, n, nt)
    if nt > 1 && n >= 1 << 18
        ch = cld(n, nt)
        @sync for k in 1:nt
            a = (k - 1) * ch + 1; b = min(k * ch, n)
            b >= a && Threads.@spawn copyto!(U, uo + a, W, a, b - a + 1)
        end
    else
        copyto!(U, uo + 1, W, 1, n)
    end
    return nothing
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
Set the subnormal entries of `v[i1:i2]` to zero (every panel right after its
factorization, while it is in cache). Entries of L below `floatmin` carry
no information at working precision against the unit diagonal, but every
solve that touches them runs at microcode speed (10 to 100 times slower per
operation on x86); flushing them here keeps the factor normal without changing
the thread's floating-point state, which belongs to the caller.
"""
function _flush_subnormals!(v::Vector{Float64}, i1::Int = 1, i2::Int = length(v))
    fm = floatmin(Float64)
    @inbounds @simd for i in i1:i2
        x = v[i]
        v[i] = ifelse(abs(x) < fm, 0.0, x)
    end
    return v
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
        l = ifelse(abs(l) < floatmin(Float64), 0.0, l)
        d[j] = dj; Lx[o+1] = l; L[j] = l
        Lx[S.leaf_dpos[j]] -= t * l
    end
    return nreg
end

"Inertia check: number of pivots whose sign differs from the expected one (0 for a quasi-definite matrix)."
wrong_signs(F::Factor) = count(i -> F.S.signs[i] * F.d[i] <= 0, eachindex(F.d))
