# problem.jl: the conic QP that the solver works on.
#
#     minimize    (1/2) x'Px + q'x + c
#     subject to  z = A x,  z in C,
#
# with C a product of
#   * intervals  l_i <= z_i <= u_i  (one row each; l_i = u_i is an equality row,
#     an infinite bound is a one-sided row), and
#   * translated second-order cones  { z_B : b_B - z_B in SOC }  over blocks of
#     consecutive rows (the convention b - A x in K of Clarabel and of sheaf
#     programs).
#
# This is the form of OSQP (Stellato et al. 2020) with second-order cones added
# as in COSMO (Garstka, Cannon and Goulart 2021).

const SpMat = SparseMatrixCSC{Float64,Int}

"How a row was specified, so that `update!` can read a right-hand side `b`."
@enum RowKind::UInt8 begin
    ROW_INTERVAL = 0   # l <= a'x <= u, given as an interval
    ROW_EQ = 1         # a'x = b      (zero cone: b - a'x = 0)
    ROW_LEQ = 2        # a'x <= b     (nonnegative cone: b - a'x >= 0)
    ROW_SOC = 3        # a row of a second-order cone block, b - A_B x in SOC
end

"""
    ConicQP(P, q, A, l, u; c = 0.0, socs = UnitRange{Int}[], socb = nothing, kinds = nothing)

The problem `min (1/2) x'Px + q'x + c` subject to `l <= A x <= u` on the interval
rows and `b_B - A_B x in SOC` on each block `B in socs` (with `b = socb`; the
bounds `l, u` of SOC rows are ignored). `P` may be given full (symmetric) or as
its upper triangle.
"""
struct ConicQP
    P::SpMat                     # full symmetric
    q::Vector{Float64}
    c::Float64
    A::SpMat
    l::Vector{Float64}
    u::Vector{Float64}
    socs::Vector{UnitRange{Int}}
    socb::Vector{Float64}
    kinds::Vector{RowKind}
end

function _symmetric_full(P::AbstractMatrix)
    S = SpMat(sparse(P))
    if istriu(S) && !issymmetric(S)
        S = SpMat(S + transpose(triu(S, 1)))
    elseif istril(S) && !issymmetric(S)
        S = SpMat(S + transpose(tril(S, -1)))
    end
    S = SpMat((S + transpose(S)) / 2)
    return S
end

function ConicQP(P::AbstractMatrix, q::AbstractVector, A::AbstractMatrix, l::AbstractVector, u::AbstractVector;
                 c::Real = 0.0, socs::Vector{UnitRange{Int}} = UnitRange{Int}[], socb = nothing, kinds = nothing)
    n = length(q)
    m = size(A, 1)
    size(P) == (n, n) || throw(DimensionMismatch("P is $(size(P)), q has length $n"))
    size(A, 2) == n || throw(DimensionMismatch("A has $(size(A, 2)) columns, q has length $n"))
    length(l) == m && length(u) == m || throw(DimensionMismatch("l and u must have $m entries"))
    sb = socb === nothing ? zeros(m) : Vector{Float64}(socb)
    length(sb) == m || throw(DimensionMismatch("socb must have $m entries"))
    ks = kinds === nothing ? fill(ROW_INTERVAL, m) : Vector{RowKind}(kinds)
    for B in socs
        (first(B) >= 1 && last(B) <= m && length(B) >= 1) || throw(ArgumentError("SOC block $B outside 1:$m"))
        for i in B
            ks[i] = ROW_SOC
        end
    end
    lv = Vector{Float64}(l); uv = Vector{Float64}(u)
    for i in 1:m
        ks[i] == ROW_SOC && continue
        lv[i] <= uv[i] || throw(ArgumentError("row $i: l > u"))
    end
    return ConicQP(_symmetric_full(P), Vector{Float64}(q), Float64(c), SpMat(sparse(A)), lv, uv,
                   copy(socs), sb, ks)
end

"""
    ConicQP(P, q, A, b, cones; c = 0.0)

Clarabel's convention: `b - A x in K`, `K` the product of the cones in `cones`,
each a pair `(kind, dim)` with `kind in (:zero, :nonneg, :soc)`, in row order.
"""
function ConicQP(P::AbstractMatrix, q::AbstractVector, A::AbstractMatrix, b::AbstractVector,
                 cones::AbstractVector{<:Tuple{Symbol,Integer}}; c::Real = 0.0)
    m = size(A, 1)
    length(b) == m || throw(DimensionMismatch("b must have $m entries"))
    sum((d for (_, d) in cones); init = 0) == m || throw(DimensionMismatch("cone dimensions do not add up to $m rows"))
    l = fill(-Inf, m); u = fill(Inf, m); socb = zeros(m)
    kinds = fill(ROW_INTERVAL, m)
    socs = UnitRange{Int}[]
    r = 0
    for (kind, d) in cones
        rr = (r+1):(r+d)
        if kind == :zero
            l[rr] .= b[rr]; u[rr] .= b[rr]; kinds[rr] .= ROW_EQ
        elseif kind == :nonneg
            u[rr] .= b[rr]; kinds[rr] .= ROW_LEQ
        elseif kind == :soc
            d >= 1 || throw(ArgumentError("empty SOC block"))
            push!(socs, rr); socb[rr] .= b[rr]
        else
            throw(ArgumentError("unknown cone kind $kind (use :zero, :nonneg, :soc)"))
        end
        r += d
    end
    return ConicQP(P, q, A, l, u; c = c, socs = socs, socb = socb, kinds = kinds)
end

nvars(p::ConicQP) = length(p.q)
nrows(p::ConicQP) = length(p.l)

"`(1/2) x'Px + q'x + c`."
objective(p::ConicQP, x::AbstractVector) = 0.5 * dot(x, p.P * x) + dot(p.q, x) + p.c

"""
    violation(p, x)

Largest violation of the constraints by `x`: interval rows by their distance to
`[l, u]`, SOC blocks by `max(0, ||s_1|| - s_0)` with `s = b - A x`.
"""
function violation(p::ConicQP, x::AbstractVector)
    z = p.A * x
    v = 0.0
    for i in eachindex(z)
        p.kinds[i] == ROW_SOC && continue
        v = max(v, p.l[i] - z[i], z[i] - p.u[i])
    end
    for B in p.socs
        s = p.socb[B] - z[B]
        v = max(v, norm(view(s, 2:length(s))) - s[1])
    end
    return max(v, 0.0)
end

"""
    dedup_rows(p::ConicQP) -> (p2, keep)

Drop exact duplicate constraints: interval rows with the same row of `A` and
the same bounds (the tightest bounds are kept when only the row repeats), and
second-order cone blocks with the same rows and shift. A pushforward along
rigid teams repeats every member's identical input cone; duplicates make the
active constraint gradients linearly dependent (the polish system singular,
the multipliers non-unique). `keep` lists the kept rows of `p`.
"""
function dedup_rows(p::ConicQP)
    m = nrows(p)
    At = SpMat(sparse(transpose(p.A)))
    rowkey(i) = (rowvals(At)[nzrange(At, i)], nonzeros(At)[nzrange(At, i)])
    insoc = falses(m)
    for B in p.socs
        insoc[B] .= true
    end
    keep = trues(m)
    l = copy(p.l); u = copy(p.u)
    seen = Dict{Any,Int}()
    for i in 1:m
        insoc[i] && continue
        k = rowkey(i)
        isempty(k[1]) && continue
        j = get(seen, k, 0)
        if j == 0
            seen[k] = i
        elseif p.kinds[i] == p.kinds[j]
            l[j] = max(l[j], l[i]); u[j] = min(u[j], u[i])        # same row: intersect the intervals
            keep[i] = false
        end
    end
    seenb = Dict{Any,Int}()
    for B in p.socs
        k = ([rowkey(i) for i in B], p.socb[B])
        if haskey(seenb, k)
            keep[B] .= false
        else
            seenb[k] = first(B)
        end
    end
    all(keep) && return p, collect(1:m)
    idx = findall(keep)
    newpos = cumsum(keep)
    socs = [newpos[first(B)]:newpos[last(B)] for B in p.socs if keep[first(B)]]
    return ConicQP(p.P, p.q, p.A[idx, :], l[idx], u[idx]; c = p.c, socs = socs, socb = p.socb[idx],
                   kinds = p.kinds[idx]), idx
end
