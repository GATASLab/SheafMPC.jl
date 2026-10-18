# qp.jl: the canonical problem every solver receives, its optional stage-wise
# (optimal control) form, and the one shared accuracy checker.
#
# Canonical form (unscaled, exactly what the shared checker evaluates):
#
#     minimize    (1/2) x'Px + q'x + c
#     subject to  l_i <= (A x)_i <= u_i         for every interval row i
#                 socb[B] - A[B,:] x in SOC     for every block B in socs
#
# l_i == u_i is an equality row; an infinite bound is a one-sided row. SOC
# rows carry l = -Inf, u = Inf (ignored). SOC(t, s) = { ||s||_2 <= t }, the
# first row of a block is t.
#
# Multiplier convention (used for the dual residual): P x + q + A' y = 0, with
# y_i >= 0 on rows at their upper bound and y_i <= 0 at their lower bound, and
# y_B in SOC on the cone blocks (Clarabel's z for b - A x in K).

using SparseArrays, LinearAlgebra

const SpMat = SparseMatrixCSC{Float64,Int}

"""
    StageOCP

Stage-wise form of a linear MPC problem, for structure-exploiting solvers
(HPIPM). Stages k = 0..N (Julia index k+1):

    min  sum_{k=0}^{N} (1/2) x_k'Q_k x_k + u_k'S_k x_k + (1/2) u_k'R_k u_k + q_k'x_k + r_k'u_k
    s.t. x_{k+1} = A_k x_k + B_k u_k + b_k            k = 0..N-1
         x_0 = x0                                     (fixed, eliminated by the solver wrapper)
         lbx_k <= x_k[idxbx_k] <= ubx_k,  lbu_k <= u_k[idxbu_k] <= ubu_k
         lg_k <= C_k x_k + D_k u_k <= ug_k

nu[N+1] = 0. Indices idxbx/idxbu are 1-based. `cmap[j] = (k, kind, i)` says
that canonical variable j is component i of x_k (kind 1, k = 0 means the
fixed x0, a constant) or of u_k (kind 2). The canonical objective and the
stage objective agree up to a constant, which the checker does not need:
it evaluates the canonical problem on the mapped point.
"""
struct StageOCP
    N::Int
    nx::Vector{Int}
    nu::Vector{Int}
    A::Vector{Matrix{Float64}}
    B::Vector{Matrix{Float64}}
    b::Vector{Vector{Float64}}
    Q::Vector{Matrix{Float64}}
    S::Vector{Matrix{Float64}}
    R::Vector{Matrix{Float64}}
    qx::Vector{Vector{Float64}}
    ru::Vector{Vector{Float64}}
    idxbx::Vector{Vector{Int}}
    lbx::Vector{Vector{Float64}}
    ubx::Vector{Vector{Float64}}
    idxbu::Vector{Vector{Int}}
    lbu::Vector{Vector{Float64}}
    ubu::Vector{Vector{Float64}}
    C::Vector{Matrix{Float64}}
    D::Vector{Matrix{Float64}}
    lg::Vector{Vector{Float64}}
    ug::Vector{Vector{Float64}}
    x0::Vector{Float64}
    cmap::Vector{NTuple{3,Int}}
end

"Canonical x from stage-wise trajectories xs[k+1] (k = 1..N used; x_0 = ocp.x0) and us[k+1]."
function canonical_from_stages(ocp::StageOCP, xs::Vector{Vector{Float64}}, us::Vector{Vector{Float64}})
    x = zeros(length(ocp.cmap))
    for (j, (k, kind, i)) in enumerate(ocp.cmap)
        x[j] = kind == 1 ? (k == 0 ? ocp.x0[i] : xs[k+1][i]) : us[k+1][i]
    end
    return x
end

"""
    QP

One benchmark instance. `stage` is the stage-wise form when the problem has
one (`nothing` otherwise). `meta` records family, size and generator settings.
"""
struct QP
    name::String
    P::SpMat
    q::Vector{Float64}
    c::Float64
    A::SpMat
    l::Vector{Float64}
    u::Vector{Float64}
    socs::Vector{UnitRange{Int}}
    socb::Vector{Float64}
    stage::Union{Nothing,StageOCP}
    meta::Dict{String,Any}
end

function QP(name, P, q, A, l, u; c = 0.0, socs = UnitRange{Int}[], socb = nothing, stage = nothing,
            meta = Dict{String,Any}())
    m, n = size(A)
    Pf = SpMat(sparse(P))
    Pf = SpMat((Pf + Pf') / 2)
    dropzeros!(Pf)
    sb = socb === nothing ? zeros(m) : Vector{Float64}(socb)
    lv = Vector{Float64}(l); uv = Vector{Float64}(u)
    for B in socs
        lv[B] .= -Inf; uv[B] .= Inf
    end
    @assert length(q) == n && length(lv) == m && length(uv) == m && length(sb) == m
    return QP(String(name), Pf, Vector{Float64}(q), Float64(c), SpMat(sparse(A)), lv, uv, socs, sb, stage, meta)
end

nvars(p::QP) = length(p.q)
ncons(p::QP) = length(p.l)
issocrow(p::QP) = (r = falses(ncons(p)); for B in p.socs; r[B] .= true; end; r)
has_soc(p::QP) = !isempty(p.socs)
"Same P, A, row pattern and cones: only q, c, l, u, socb differ (a sequence step)."
same_structure(a::QP, b::QP) = a.P == b.P && a.A == b.A && a.socs == b.socs &&
                               all(isfinite.(a.l) .== isfinite.(b.l)) && all(isfinite.(a.u) .== isfinite.(b.u)) &&
                               all((a.l .== a.u) .== (b.l .== b.u))

objective(p::QP, x) = 0.5 * dot(x, p.P * x) + dot(p.q, x) + p.c
"Objective without the constant: what the solver optimizes."
objective0(p::QP, x) = 0.5 * dot(x, p.P * x) + dot(p.q, x)

"""
    check(p, x, y, ref) -> NamedTuple

The shared accuracy checker, on the unscaled canonical problem:

* `obj_err`: |f0(x) - f0(x*)| / max(1, |f0(x*)|), f0 the objective without the
  constant c, x* the reference;
* `prim_abs`: max over interval rows of the distance of (Ax)_i to [l_i, u_i]
  and over cone blocks of max(0, ||s_1|| - s_0), s = socb - A x;
  `prim_rel` = prim_abs / max(1, ||A x||_inf, max finite |bound|);
* `dual_abs`, `dual_rel`: ||P x + q + A'y||_inf, relative to
  max(1, ||Px||_inf, ||q||_inf, ||A'y||_inf); NaN when `y` is not available.

The success rule of the protocol uses `obj_err` and `prim_rel` only, the same
for every solver (several solvers do not return multipliers in a mappable
form); `dual_rel` is reported where available.
"""
function check(p::QP, x::AbstractVector, y, refobj0::Float64)
    if length(x) != nvars(p) || any(!isfinite, x)
        return (obj_err = Inf, prim_abs = Inf, prim_rel = Inf, dual_abs = NaN, dual_rel = NaN, obj = NaN)
    end
    Ax = p.A * x
    soc = issocrow(p)
    v = 0.0; bnd = 0.0
    for i in eachindex(Ax)
        soc[i] && continue
        v = max(v, p.l[i] - Ax[i], Ax[i] - p.u[i])
        isfinite(p.l[i]) && (bnd = max(bnd, abs(p.l[i])))
        isfinite(p.u[i]) && (bnd = max(bnd, abs(p.u[i])))
    end
    for B in p.socs
        s = p.socb[B] .- Ax[B]
        v = max(v, norm(view(s, 2:length(s))) - s[1])
        bnd = max(bnd, maximum(abs, p.socb[B]))
    end
    v = max(v, 0.0)
    prel = v / max(1.0, norm(Ax, Inf), bnd)
    f0 = objective0(p, x)
    oerr = abs(f0 - refobj0) / max(1.0, abs(refobj0))
    da = NaN; dr = NaN
    if y !== nothing && length(y) == ncons(p) && all(isfinite, y)
        Px = p.P * x; Aty = p.A' * y
        r = Px .+ p.q .+ Aty
        da = norm(r, Inf)
        dr = da / max(1.0, norm(Px, Inf), norm(p.q, Inf), norm(Aty, Inf))
    end
    return (obj_err = oerr, prim_abs = v, prim_rel = prel, dual_abs = da, dual_rel = dr, obj = f0 + p.c)
end

"The protocol's success rule at accuracy tier eps."
meets(chk, eps) = chk.obj_err <= eps && chk.prim_rel <= eps

# ---------------------------------------------------------------------------
# Binary exchange format (for problems generated in other environments and for
# the Python runners): a JSON header plus raw little-endian arrays.
# ---------------------------------------------------------------------------

function write_qp(path::AbstractString, p::QP)
    hdr = Dict{String,Any}("name" => p.name, "n" => nvars(p), "m" => ncons(p), "c" => p.c,
                           "socs" => [[first(B), last(B)] for B in p.socs], "meta" => p.meta,
                           "nnzP" => nnz(p.P), "nnzA" => nnz(p.A))
    open(path, "w") do io
        h = Vector{UInt8}(JSON.json(hdr))
        write(io, Int64(length(h))); write(io, h)
        for M in (p.P, p.A)
            write(io, Int64.(M.colptr)); write(io, Int64.(M.rowval)); write(io, M.nzval)
        end
        write(io, p.q); write(io, p.l); write(io, p.u); write(io, p.socb)
    end
end

function read_qp(path::AbstractString)
    open(path, "r") do io
        nh = read(io, Int64)
        hdr = JSON.parse(String(read(io, nh)))
        n = hdr["n"]; m = hdr["m"]
        rd(T, k) = (v = Vector{T}(undef, k); read!(io, v); v)
        function rdmat(r, cdim, nz)
            cp = rd(Int64, cdim + 1); rv = rd(Int64, nz); nv = rd(Float64, nz)
            SparseMatrixCSC(r, cdim, Int.(cp), Int.(rv), nv)
        end
        P = rdmat(n, n, hdr["nnzP"]); A = rdmat(m, n, hdr["nnzA"])
        q = rd(Float64, n); l = rd(Float64, m); u = rd(Float64, m); sb = rd(Float64, m)
        socs = UnitRange{Int}[a:b for (a, b) in hdr["socs"]]
        return QP(hdr["name"], P, q, A, l, u; c = hdr["c"], socs = socs, socb = sb,
                  meta = Dict{String,Any}(hdr["meta"]))
    end
end
