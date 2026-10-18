# lowrank.jl: updating the factorization when a few diagonal entries change.
#
# When rho changes on a few rows only (rows turning into equalities or back in
# `update!`, an active set that differs in a few rows in the polish), K changes
# by sum_k delta_k e_{j_k} e_{j_k}'. Each term is a rank-one modification
# L D L' + alpha w w' with w = e_j, done in place by method C1 of Gill, Golub,
# Murray and Saunders (1974) in the sparse form of Davis and Hager (1999): the
# nonzeros of w stay on the path from j to the root of the elimination tree,
# so one update costs the entries of L in the columns of that path, not a
# refactorization. On the supernodal layout the path is walked supernode by
# supernode (the next column after a supernode is the first row below it).

"""
    rank1_diagonal!(F, j, alpha, w) -> F

L D L' += alpha e_j e_j' for the permuted index `j`; `w` is a zero scratch
vector of length N (left zero).
"""
function rank1_diagonal!(F::Factor, j::Int, alpha::Float64, w::Vector{Float64})
    S = F.S; Lx = F.Lx; d = F.d; dinv = F.dinv
    sp = S.sup_ptr; stp = S.str_ptr; si = S.str_idx
    w[j] = 1.0
    k = j
    s = S.sup_of[j]
    @inbounds while true
        f = sp[s]; l = sp[s+1] - 1; wc = l - f + 1
        rb = stp[s] - 1; r = stp[s+1] - stp[s]; h = wc + r
        o = S.lx_ptr[s] - 1
        for kk in k:l
            p = w[kk]
            p == 0.0 && continue
            w[kk] = 0.0
            dk = d[kk]
            dn = dk + alpha * p * p
            beta = p * alpha / dn
            alpha = alpha * dk / dn
            d[kk] = dn; dinv[kk] = 1.0 / dn
            c = kk - f + 1
            ck = o + (c - 1) * h
            for i in (c+1):wc
                gi = f + i - 1
                wi = muladd(-p, Lx[ck+i], w[gi]); w[gi] = wi
                Lx[ck+i] = muladd(beta, wi, Lx[ck+i])
            end
            cb = ck + wc
            for i in 1:r
                gi = si[rb+i]
                wi = muladd(-p, Lx[cb+i], w[gi]); w[gi] = wi
                Lx[cb+i] = muladd(beta, wi, Lx[cb+i])
            end
            kk <= S.nleaf && (F.leafL[kk] = Lx[cb+1])          # the contiguous copy of a leaf's entry
        end
        (r == 0 || alpha == 0.0) && break
        k = si[rb+1]
        s = S.sup_of[k]
    end
    # entries of w past an early exit (alpha == 0) are cleared
    if alpha == 0.0
        fill!(w, 0.0)
    end
    return F
end

"""
    update_diagonal!(F, idx, delta, w) -> F

The factorization of K + Diagonal(delta on the original indices `idx`), by
`length(idx)` rank-one updates.
"""
function update_diagonal!(F::Factor, idx::AbstractVector{<:Integer}, delta::AbstractVector{<:Real}, w::Vector{Float64})
    ip = F.S.iperm
    for (j, dl) in zip(idx, delta)
        dl == 0 && continue
        rank1_diagonal!(F, ip[j], Float64(dl), w)
    end
    return F
end

"Entries of L read and written by a rank-one update at the original index `j` (its path cost)."
function path_cost(F::Factor, j::Int)
    S = F.S
    k = S.iperm[j]; s = S.sup_of[k]
    c = 0
    while true
        f = S.sup_ptr[s]; l = S.sup_ptr[s+1] - 1; wc = l - f + 1
        r = S.str_ptr[s+1] - S.str_ptr[s]
        for kk in k:l
            c += (l - kk) + r
        end
        r == 0 && break
        k = S.str_idx[S.str_ptr[s]]; s = S.sup_of[k]
    end
    return c
end
