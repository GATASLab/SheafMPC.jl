# scaling.jl: modified Ruiz equilibration (OSQP, Stellato et al. 2020, Sec. 5.1).
#
# The solver works on the scaled problem
#
#   Phat = c D P D,  qhat = c D q,  Ahat = E A D,  lhat = E l,  uhat = E u,
#
# with D, E positive diagonal and c > 0 a cost scale, chosen by a few rounds of
# Ruiz equilibration of the KKT matrix [P A'; A 0] (every column's infinity
# norm driven toward 1) followed by a cost normalization. A second-order cone is
# invariant only under a uniform scaling, so the row scales of every SOC block
# are replaced by their mean (as COSMO does).

const MIN_SCALING = 1e-4
const MAX_SCALING = 1e4

@inline _fmax(a::Float64, b::Float64) = ifelse(a > b, a, b)     # max without the NaN branch
@inline _limit_scaling(v::Float64) = v < MIN_SCALING ? 1.0 : (v > MAX_SCALING ? MAX_SCALING : v)

struct Scaling
    D::Vector{Float64}
    Dinv::Vector{Float64}
    E::Vector{Float64}
    Einv::Vector{Float64}
    c::Float64
    cinv::Float64
end

"""
Scale `P` (full symmetric), `A`, `q` in place; returns the `Scaling`.

The iterates `D`, `E`, `c` are accumulated without rewriting the matrices:
each round reads `P` once (the column norms of `c D P D`, which serve both the
cost scaling of this round and the column norms of the next) and `A` once (the
row and column norms of `E A D`); the scaling is applied at the end. This is
the same sequence of scalings as rescaling the matrices every round, at a
third of the memory traffic.
"""
function ruiz_scale!(P::SpMat, q::Vector{Float64}, A::SpMat, socs::Vector{UnitRange{Int}}, iters::Int)
    n = size(P, 1); m = size(A, 1)
    D = ones(n); E = ones(m); c = 1.0
    Dt = zeros(n); Et = zeros(m); Pn = zeros(n)
    Prow = rowvals(P); Pval = nonzeros(P)
    Arow = rowvals(A); Aval = nonzeros(A)
    @inbounds for j in 1:n
        v = 0.0
        for k in nzrange(P, j)
            v = _fmax(v, abs(Pval[k]))
        end
        Pn[j] = v
    end
    for _ in 1:iters
        fill!(Et, 0.0)
        @inbounds for j in 1:n
            v = Pn[j]
            dj = D[j]
            for k in nzrange(A, j)
                i = Arow[k]
                a = abs(Aval[k]) * E[i] * dj
                v = _fmax(v, a)
                Et[i] = _fmax(Et[i], a)
            end
            Dt[j] = v
        end
        @inbounds for j in 1:n
            Dt[j] = 1.0 / sqrt(_limit_scaling(Dt[j]))
        end
        @inbounds for i in 1:m
            Et[i] = 1.0 / sqrt(_limit_scaling(Et[i]))
        end
        for B in socs
            s = 0.0
            for i in B
                s += Et[i]
            end
            s /= length(B)
            for i in B
                Et[i] = s
            end
        end
        @inbounds for j in 1:n
            q[j] *= Dt[j]
            D[j] *= Dt[j]
        end
        @inbounds for i in 1:m
            E[i] *= Et[i]
        end
        # column norms of c D P D, then the cost scaling
        pn = 0.0
        @inbounds for j in 1:n
            v = 0.0
            for k in nzrange(P, j)
                v = _fmax(v, abs(Pval[k]) * D[Prow[k]])
            end
            v *= c * D[j]
            Pn[j] = v
            pn += v
        end
        pn = n > 0 ? pn / n : 0.0
        qn = isempty(q) ? 0.0 : maximum(abs, q)
        ct = 1.0 / _limit_scaling(max(pn, qn))
        q .*= ct
        Pn .*= ct
        c *= ct
    end
    @inbounds for j in 1:n, k in nzrange(P, j)
        Pval[k] *= c * D[Prow[k]] * D[j]
    end
    @inbounds for j in 1:n, k in nzrange(A, j)
        Aval[k] *= E[Arow[k]] * D[j]
    end
    return Scaling(D, 1.0 ./ D, E, 1.0 ./ E, c, 1.0 / c)
end

identity_scaling(n::Int, m::Int) = Scaling(ones(n), ones(n), ones(m), ones(m), 1.0, 1.0)
