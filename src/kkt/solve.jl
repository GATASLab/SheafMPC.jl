# solve.jl: the triangular solves L D L' x = b on the supernodal factor, in the
# permuted index space, without allocation. The forward sweep scales by D^{-1}
# as soon as a supernode's entries are final, so one forward and one backward
# pass over L do the whole solve.
#
# The off-diagonal block L21 of a supernode is applied by row: x_R -= L21 x_s
# with the (up to 4) entries of x_s in registers, one gather and one scatter
# per row, so that the narrow supernodes of very sparse KKT matrices cost
# about one indexed access per row instead of one per entry; wider supernodes
# go through a dense accumulator, 4 columns at a time.

using Base.Cartesian: @nexprs

# x[R[i]] -= sum_k L[i, k] x_s[k] for the W columns starting at column k0 of the block
@generated function _fwd_rows!(::Val{W}, x::Vector{Float64}, Lx::Vector{Float64}, si::AbstractVector{<:Integer}, rb::Int, r::Int,
                               base::Int, h::Int, fo::Int, k0::Int) where {W}
    quote
        @nexprs $W j -> (xs_j = x[fo+k0+j-1]; c_j = base + (k0 + j - 2) * h)
        @inbounds for i in 1:r
            v = 0.0
            @nexprs $W j -> (v = muladd(Lx[c_j+i], xs_j, v))
            ri = si[rb+i]
            x[ri] -= v
        end
        return nothing
    end
end

# tmp[i] += sum_k L[i, k] x_s[k], 4 columns from k0
@inline function _fwd_acc4!(x, Lx, tmp, r, base, h, fo, k0)
    @inbounds begin
        x1 = x[fo+k0]; x2 = x[fo+k0+1]; x3 = x[fo+k0+2]; x4 = x[fo+k0+3]
        c1 = base + (k0 - 1) * h; c2 = c1 + h; c3 = c2 + h; c4 = c3 + h
        @simd for i in 1:r
            tmp[i] = muladd(Lx[c1+i], x1, muladd(Lx[c2+i], x2, muladd(Lx[c3+i], x3, muladd(Lx[c4+i], x4, tmp[i]))))
        end
    end
    return nothing
end

# x_s[k] -= sum_i L[i, k] x[R[i]] for the W columns from k0 (row-wise, gather once)
@generated function _bwd_rows!(::Val{W}, x::Vector{Float64}, Lx::Vector{Float64}, si::AbstractVector{<:Integer}, rb::Int, r::Int,
                               base::Int, h::Int, fo::Int, k0::Int) where {W}
    quote
        @nexprs $W j -> (a_j = 0.0; c_j = base + (k0 + j - 2) * h)
        @inbounds for i in 1:r
            g = x[si[rb+i]]
            @nexprs $W j -> (a_j = muladd(Lx[c_j+i], g, a_j))
        end
        @inbounds @nexprs $W j -> (x[fo+k0+j-1] -= a_j)
        return nothing
    end
end

# x_s[k] -= dot(L[:, k], tmp), 4 columns from k0
@inline function _bwd_dot4!(x, Lx, tmp, r, base, h, fo, k0)
    @inbounds begin
        c1 = base + (k0 - 1) * h; c2 = c1 + h; c3 = c2 + h; c4 = c3 + h
        a1 = 0.0; a2 = 0.0; a3 = 0.0; a4 = 0.0
        @simd for i in 1:r
            t = tmp[i]
            a1 = muladd(Lx[c1+i], t, a1); a2 = muladd(Lx[c2+i], t, a2)
            a3 = muladd(Lx[c3+i], t, a3); a4 = muladd(Lx[c4+i], t, a4)
        end
        x[fo+k0] -= a1; x[fo+k0+1] -= a2; x[fo+k0+2] -= a3; x[fo+k0+3] -= a4
    end
    return nothing
end

"Diagonal block: x_s = L11^{-1} x_s (unit lower, w x w at offset o, leading dimension h)."
@inline function _diag_fwd!(x, Lx, o, h, fo, w)
    @inbounds for k in 1:(w-1)
        xk = x[fo+k]
        ck = o + (k - 1) * h
        for i in (k+1):w
            x[fo+i] = muladd(-Lx[ck+i], xk, x[fo+i])
        end
    end
    return nothing
end

@inline function _diag_bwd!(x, Lx, o, h, fo, w)
    @inbounds for k in (w-1):-1:1
        ck = o + (k - 1) * h
        acc = x[fo+k]
        for i in (k+1):w
            acc = muladd(-Lx[ck+i], x[fo+i], acc)
        end
        x[fo+k] = acc
    end
    return nothing
end

"Off-diagonal forward update of one supernode: x[R] -= L21 x_s (all rows, scattered into x)."
@inline function _fwd_offdiag!(x, Lx, tmp, si, rb, r, base, h, fo, w)
    if w == 1
        _fwd_rows!(Val(1), x, Lx, si, rb, r, base, h, fo, 1)
    elseif w == 2
        _fwd_rows!(Val(2), x, Lx, si, rb, r, base, h, fo, 1)
    elseif w == 3
        _fwd_rows!(Val(3), x, Lx, si, rb, r, base, h, fo, 1)
    elseif w == 4
        _fwd_rows!(Val(4), x, Lx, si, rb, r, base, h, fo, 1)
    else
        _fwd_acc!(x, Lx, tmp, r, base, h, fo, w)
        @inbounds for i in 1:r
            x[si[rb+i]] -= tmp[i]
        end
    end
    return nothing
end

"tmp[1:r] = L21 x_s (dense accumulator, 4 columns at a time)."
@inline function _fwd_acc!(x, Lx, tmp, r, base, h, fo, w)
    @inbounds for i in 1:r
        tmp[i] = 0.0
    end
    k0 = 1
    while k0 + 3 <= w
        _fwd_acc4!(x, Lx, tmp, r, base, h, fo, k0)
        k0 += 4
    end
    @inbounds while k0 <= w
        xk = x[fo+k0]; ck = base + (k0 - 1) * h
        @simd for i in 1:r
            tmp[i] = muladd(Lx[ck+i], xk, tmp[i])
        end
        k0 += 1
    end
    return nothing
end

"Off-diagonal backward update of one supernode: x_s -= L21' x[R]."
@inline function _bwd_offdiag!(x, Lx, tmp, si, rb, r, base, h, fo, w)
    if w == 1
        _bwd_rows!(Val(1), x, Lx, si, rb, r, base, h, fo, 1)
    elseif w == 2
        _bwd_rows!(Val(2), x, Lx, si, rb, r, base, h, fo, 1)
    elseif w == 3
        _bwd_rows!(Val(3), x, Lx, si, rb, r, base, h, fo, 1)
    elseif w == 4
        _bwd_rows!(Val(4), x, Lx, si, rb, r, base, h, fo, 1)
    else
        @inbounds for i in 1:r
            tmp[i] = x[si[rb+i]]
        end
        k0 = 1
        while k0 + 3 <= w
            _bwd_dot4!(x, Lx, tmp, r, base, h, fo, k0)
            k0 += 4
        end
        @inbounds while k0 <= w
            ck = base + (k0 - 1) * h
            a = 0.0
            @simd for i in 1:r
                a = muladd(Lx[ck+i], tmp[i], a)
            end
            x[fo+k0] -= a
            k0 += 1
        end
    end
    return nothing
end

"Forward solve with L and scaling by D^{-1}, supernodes `s1:s2` (in place on the permuted `x`)."
function _forward_range!(F::Factor, x::Vector{Float64}, tmp::Vector{Float64}, s1::Int, s2::Int)
    S = F.S; Lx = F.Lx; dinv = F.dinv; si = S.sidx; snd = S.snd
    @inbounds for s in s1:s2
        nd = snd[s]
        fo = Int(nd.fo); w = Int(nd.w); r = Int(nd.r); rb = Int(nd.rb); o = nd.o
        h = w + r
        if w == 1
            xk = x[fo+1] * dinv[fo+1]
            _fwd_rows1!(x, Lx, si, rb, r, o + 1, x[fo+1])
            x[fo+1] = xk
        else
            _diag_fwd!(x, Lx, o, h, fo, w)
            r > 0 && _fwd_offdiag!(x, Lx, tmp, si, rb, r, o + w, h, fo, w)
            for k in 1:w
                x[fo+k] *= dinv[fo+k]
            end
        end
    end
    return x
end

"Backward solve with L', supernodes `s2:-1:s1`."
function _backward_range!(F::Factor, x::Vector{Float64}, tmp::Vector{Float64}, s1::Int, s2::Int)
    S = F.S; Lx = F.Lx; si = S.sidx; snd = S.snd
    @inbounds for s in s2:-1:s1
        nd = snd[s]
        fo = Int(nd.fo); w = Int(nd.w); r = Int(nd.r); rb = Int(nd.rb); o = nd.o
        h = w + r
        if w == 1
            acc = 0.0
            c = o + 1
            for i in 1:r
                acc = muladd(Lx[c+i], x[si[rb+i]], acc)
            end
            x[fo+1] -= acc
        else
            r > 0 && _bwd_offdiag!(x, Lx, tmp, si, rb, r, o + w, h, fo, w)
            _diag_bwd!(x, Lx, o, h, fo, w)
        end
    end
    return x
end

"x[R[i]] -= L[i] xk for one column (entries at Lx[c+1:c+r])."
@inline function _fwd_rows1!(x, Lx, si, rb, r, c, xk)
    @inbounds for i in 1:r
        ri = si[rb+i]
        x[ri] = muladd(-Lx[c+i], xk, x[ri])
    end
    return nothing
end

"""
    ldiv_permuted!(F, x) -> x

Solve `L D L' x = x` in the permuted index space (`x` is overwritten).
"""
function ldiv_permuted!(F::Factor, x::Vector{Float64})
    _forward_leaves!(F, x)
    if !F.par_solve
        tmp = F.T[1]
        nl = F.S.nleaf
        _forward_range!(F, x, tmp, nl + 1, F.S.nsup)
        _backward_range!(F, x, tmp, nl + 1, F.S.nsup)
    else
        _solve_parallel!(F, x)
    end
    _backward_leaves!(F, x)
    return x
end

"Leaf pivots, forward: x[parent] -= l x_j, x_j /= d_j."
@inline function _forward_leaves!(F::Factor, x::Vector{Float64})
    S = F.S; L = F.leafL; par = S.leaf_par; di = F.dinv
    @inbounds for j in 1:S.nleaf
        xj = x[j]
        x[par[j]] = muladd(-L[j], xj, x[par[j]])
        x[j] = xj * di[j]
    end
    return nothing
end

"Leaf pivots, backward: x_j -= l x[parent]."
@inline function _backward_leaves!(F::Factor, x::Vector{Float64})
    S = F.S; L = F.leafL; par = S.leaf_par
    @inbounds for j in 1:S.nleaf
        x[j] = muladd(-L[j], x[par[j]], x[j])
    end
    return nothing
end

"""
    ldiv!(F, b, work) -> b

Solve `K x = b` for the original (unpermuted) `b`, in place; `work` has length N.
"""
function ldiv!(F::Factor, b::AbstractVector{Float64}, work::Vector{Float64})
    p = F.S.perm
    @inbounds for i in eachindex(p)
        work[i] = b[p[i]]
    end
    ldiv_permuted!(F, work)
    @inbounds for i in eachindex(p)
        b[p[i]] = work[i]
    end
    return b
end

"y = K x for the symmetric K given by its upper triangle (CSC)."
function symv_upper!(y::Vector{Float64}, K::SparseMatrixCSC{Float64,Int}, x::AbstractVector{Float64})
    fill!(y, 0.0)
    rv = rowvals(K); nz = nonzeros(K)
    @inbounds for c in 1:size(K, 2)
        xc = x[c]
        acc = 0.0
        for k in nzrange(K, c)
            r = rv[k]; v = nz[k]
            if r == c
                acc = muladd(v, xc, acc)
            else
                acc = muladd(v, x[r], acc)
                y[r] = muladd(v, xc, y[r])
            end
        end
        y[c] += acc
    end
    return y
end

"""
    solve_refined!(F, K, x, b, r, work; iters = 3, rtol = 1e-14) -> (x, relres, steps)

x = K \\ b with iterative refinement on the matrix `K` (upper triangle) that
`F` factors, up to `iters` steps or until ||b - K x|| <= rtol ||b|| (inf-norms).
`r` and `work` are scratch of length N.
"""
function solve_refined!(F::Factor, K::SparseMatrixCSC{Float64,Int}, x::Vector{Float64}, b::AbstractVector{Float64},
                        r::Vector{Float64}, work::Vector{Float64}; iters::Int = 3, rtol::Float64 = 1e-14)
    copyto!(x, b)
    ldiv!(F, x, work)
    nb = max(norm(b, Inf), 1e-300)
    rel = Inf; k = 0
    while true
        symv_upper!(r, K, x)
        @inbounds for i in eachindex(r)
            r[i] = b[i] - r[i]
        end
        rel = norm(r, Inf) / nb
        (rel <= rtol || k >= iters) && break
        ldiv!(F, r, work)
        @inbounds for i in eachindex(x)
            x[i] += r[i]
        end
        k += 1
    end
    return x, rel, k
end
