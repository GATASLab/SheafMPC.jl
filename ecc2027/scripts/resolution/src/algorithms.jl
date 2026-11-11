# algorithms.jl: three solver families that run on ANY graph program, fine or
# coarse.
#
# 1. Primal-dual graph diffusion (Condat 2013, Vu 2013): gradient steps on the
#    smooth part (vertex quadratics plus spring energies; one exchange per spring
#    per iteration), zero-cone rows by projection, the other vertex cones by
#    local dual variables with closed-form cone projections. It needs every rod
#    to be internal to a vertex (no hard edge between two vertices).
# 2. ADMM with edge splitting (Boyd et al. 2011, Sec. 7): every vertex solves a
#    small conic prox, every edge a closed-form update (a spring) or a projection
#    (a rod); two messages of d_e floats per edge per iteration.
# 3. Direct: the whole program in Clarabel, timed.
#
# The iterative methods stop when the objective is within `tol_obj` (relative)
# of the direct optimum of the SAME program and the plan within `tol_plan`
# (relative 2-norm), and report iterations and floats exchanged.

"""
    IterativeResult

Outcome of `graph_diffusion` or `graph_admm`: `converged`, `iterations`,
`floats` exchanged over the surviving edges (both directions, all iterations),
`floats_per_iteration`, loop and setup time in seconds, final iterate `x`,
its objective `J`, relative objective and plan errors against the reference,
and the method's parameters.
"""
struct IterativeResult
    method::Symbol
    converged::Bool
    iterations::Int
    floats::Int
    floats_per_iteration::Int
    time::Float64
    setup_time::Float64
    x::Vector{Float64}
    J::Float64
    obj_err::Float64
    plan_err::Float64
    params::Dict{String,Any}
end

"""Largest eigenvalue of a symmetric positive semidefinite operator by power iteration (deterministic start)."""
function power_iteration(apply!, n::Int; iters::Int = 500, rtol::Real = 1e-7)
    n == 0 && return 0.0
    v = ones(n) ./ sqrt(n) .+ 1e-3 .* sin.(1:n)
    v ./= norm(v)
    w = similar(v)
    lam = 0.0
    for k in 1:iters
        apply!(w, v)
        lnew = dot(v, w)
        nw = norm(w)
        nw == 0 && return 0.0
        v .= w ./ nw
        abs(lnew - lam) <= rtol * max(abs(lnew), 1e-300) && return lnew
        lam = lnew
    end
    return lam
end

"""Projection onto a cone block (in place on a view)."""
function _project_cone!(z::AbstractVector, kind::ConeKind)
    if kind == NONNEG_CONE
        @inbounds for i in eachindex(z)
            z[i] = max(z[i], 0.0)
        end
    elseif kind == SOC_CONE
        t = z[1]
        nz = norm(view(z, 2:length(z)))
        if nz <= t
            return z
        elseif nz <= -t
            fill!(z, 0.0)
        else
            a = (t + nz) / 2
            z[1] = a
            @views z[2:end] .*= a / nz
        end
    else
        fill!(z, 0.0)
    end
    return z
end

"""Hard edges joining two different vertices (rods between vertices)."""
rods_between_vertices(P::GraphProgram) = [e for (e, E) in enumerate(P.edges) if E.hard && edgedim(E) > 0]

"""Floats exchanged per iteration by an edge-local method: `d_e` each way on every edge."""
floats_per_iteration(P::GraphProgram) = 2 * sum((edgedim(E) for E in P.edges); init = 0)

"""
    graph_diffusion(P; xref, Jref, tol_obj = 1e-4, tol_plan = 1e-3, maxit, time_limit, beta = 0.3)

Primal-dual graph diffusion (Condat-Vu) on `P`, which must have no rod between
two vertices. With `f(x) = (1/2)x'Hq x + g'x` the vertex quadratics plus the
spring energies (Lipschitz constant `L`), the zero-cone rows of the vertex sets
as an affine projection, and the remaining rows `b - A x in K` through local
duals `y in K*`:

    x+ = Proj_aff( x - tau (grad f(x) + A'y) )
    y+ = Proj_{K*}( y + sigma A(2x+ - x) - sigma b )

with `L` and `||A||^2` estimated by power iteration, `sigma = beta L / (2||A||^2)`
and `tau = 0.99 / (L/2 + sigma ||A||^2)`, so `tau (L/2 + sigma ||A||^2) < 1`.
Each iteration needs the neighbours' restricted values once (`d_e` floats each
way per spring); the duals and projections are vertex-local.
"""
function graph_diffusion(P::GraphProgram; xref::AbstractVector, Jref::Real, tol_obj::Real = 1e-4,
                         tol_plan::Real = 1e-3, maxit::Integer = 200_000, time_limit::Real = 120.0,
                         beta::Real = 0.3)
    rods = rods_between_vertices(P)
    isempty(rods) || throw(ArgumentError("graph_diffusion: $(length(rods)) rods join two vertices; collapse them first"))
    ts = time()
    n = c0dim(P)
    Hq, g, c = quadratic_form(P)
    A, b, cones, roff = node_constraints(P)
    # zero-cone rows: an affine projection per vertex; the other rows: local duals
    zrows = Int[]; irows = Int[]; icones = ConeBlock[]
    r = 0
    for cb in cones
        rr = (r+1):(r+cb.dim)
        cb.kind == ZERO_CONE ? append!(zrows, rr) : (append!(irows, rr); push!(icones, cb))
        r += cb.dim
    end
    projs = Tuple{UnitRange{Int},Matrix{Float64},Vector{Float64},Matrix{Float64}}[]   # (vertex range, M^+, m, M)
    zmask = falses(size(A, 1))
    zmask[zrows] .= true
    for v in 1:nvertices(P)
        rows_v = [i for i in (roff[v]+1):roff[v+1] if zmask[i]]
        isempty(rows_v) && continue
        vr = vrange(P, v)
        M = Matrix(A[rows_v, vr])
        push!(projs, (vr, pinv(M), b[rows_v], M))
    end
    Aineq = A[irows, :]
    bI = b[irows]
    Aineqt = SparseMatrixCSC(Aineq')
    L = 1.02 * power_iteration((w, v) -> mul!(w, Hq, v), n)
    nA2 = size(Aineq, 1) == 0 ? 0.0 : 1.02 * power_iteration((w, v) -> (w .= Aineqt * (Aineq * v)), n)
    sigma = nA2 > 0 ? beta * L / (2 * nA2) : 0.0
    tau = 0.99 / (L / 2 + sigma * nA2)
    project!(x) = begin
        for (vr, Mp, m, M) in projs
            xv = view(x, vr)
            xv .-= Mp * (M * xv - m)
        end
        x
    end
    x = project!(zeros(n))
    y = zeros(length(bI))
    Hx = similar(x); xn = similar(x); tmp = similar(x); ext = similar(x); Ay = zeros(length(bI))
    xr = Vector{Float64}(xref)
    nref = max(norm(xr), 1e-300)
    Jr = Float64(Jref)
    setup = time() - ts
    t0 = time()
    it = 0
    converged = false
    J = NaN; oe = Inf; pe = Inf
    while it < maxit
        mul!(Hx, Hq, x)
        J = 0.5 * dot(x, Hx) + dot(g, x) + c
        oe = abs(J - Jr) / max(abs(Jr), 1e-300)
        pe = norm(x - xr) / nref
        if oe <= tol_obj && pe <= tol_plan
            converged = true
            break
        end
        (time() - t0) > time_limit && break
        # primal step
        tmp .= Hx .+ g
        if !isempty(y)
            mul!(tmp, Aineqt, y, 1.0, 1.0)
        end
        xn .= x .- tau .* tmp
        project!(xn)
        # dual step
        if !isempty(y)
            ext .= 2 .* xn .- x
            mul!(Ay, Aineq, ext)
            y .+= sigma .* Ay .- sigma .* bI
            rr = 0
            for cb in icones
                _project_cone!(view(y, (rr+1):(rr+cb.dim)), cb.kind)
                rr += cb.dim
            end
        end
        x .= xn
        it += 1
    end
    fpi = floats_per_iteration(P)
    return IterativeResult(:diffusion, converged, it, fpi * it, fpi, time() - t0, setup, copy(x), J, oe, pe,
                           Dict{String,Any}("L" => L, "normA2" => nA2, "sigma" => sigma, "tau" => tau, "beta" => beta))
end

# ---------------------------------------------------------------------------
# ADMM with edge splitting
# ---------------------------------------------------------------------------

"""The prox of one vertex: min (1/2)x'Pv x + lin'x over Omega_v, with a cached equality KKT and a Clarabel fallback."""
mutable struct VertexProx
    d::Int
    rhs::Vector{Float64}
    sol::Vector{Float64}
    Pv::Matrix{Float64}
    A0::Matrix{Float64}
    b0::Vector{Float64}
    Kfac::Any
    Aineq::SpMat
    bI::Vector{Float64}
    conesI::Vector{ConeBlock}
    Aall::SpMat
    ball::Vector{Float64}
    conesall::Vector{ConeBlock}
    solver::Any
    nslow::Int
end

function VertexProx(Pv::Matrix{Float64}, nd::NodeData)
    d = size(Pv, 1)
    zr = Int[]; ir = Int[]; ic = ConeBlock[]
    r = 0
    for cb in nd.cones
        rr = (r+1):(r+cb.dim)
        cb.kind == ZERO_CONE ? append!(zr, rr) : (append!(ir, rr); push!(ic, cb))
        r += cb.dim
    end
    A0 = Matrix(nd.A[zr, :]); b0 = nd.b[zr]
    m0 = length(zr)
    K = [Pv A0'; A0 zeros(m0, m0)]
    Kfac = try
        lu(K)
    catch
        lu(K + 1e-12 * I)
    end
    return VertexProx(d, zeros(d + m0), zeros(d + m0), Pv, A0, b0, Kfac, SpMat(sparse(nd.A[ir, :])), nd.b[ir], ic,
                      nd.A, nd.b, nd.cones, nothing, 0)
end

function prox!(vp::VertexProx, lin::Vector{Float64})
    d = vp.d
    @inbounds for i in 1:d
        vp.rhs[i] = -lin[i]
    end
    @inbounds for i in eachindex(vp.b0)
        vp.rhs[d+i] = vp.b0[i]
    end
    ldiv!(vp.sol, vp.Kfac, vp.rhs)
    x = view(vp.sol, 1:d)
    isempty(vp.bI) && return x
    s = vp.bI - vp.Aineq * x
    ok = true
    r = 0
    tol = 1e-12 * max(1.0, maximum(abs, vp.bI))
    for cb in vp.conesI
        cone_violation(cb.kind, view(s, (r+1):(r+cb.dim))) > tol && (ok = false; break)
        r += cb.dim
    end
    ok && return x
    # an inequality binds: the conic prox, structure reused through update_q!
    vp.nslow += 1
    if vp.solver === nothing
        settings = Clarabel.Settings(verbose = false, tol_gap_abs = 1e-10, tol_gap_rel = 1e-10, tol_feas = 1e-10,
                                     presolve_enable = false, max_iter = 200)
        vp.solver = Clarabel.Solver()
        Clarabel.setup!(vp.solver, SpMat(sparse(triu(vp.Pv))), copy(lin), vp.Aall, vp.ball,
                        _clarabel_cones(vp.conesall), settings)
    else
        Clarabel.update_q!(vp.solver, lin)
    end
    res = Clarabel.solve!(vp.solver)
    return copy(res.x)
end

"""
    graph_admm(P; xref, Jref, tol_obj = 1e-4, tol_plan = 1e-3, maxit, time_limit, rho_scale = 0.03)

ADMM with edge splitting (Boyd et al. 2011, Sec. 7). Each edge `e` keeps a copy
`w_{e,v}` of the restricted value `F_{v <| e} x_v` at each endpoint, with scaled
duals `u_{e,v}` and penalty `rho_e = rho_scale max(1, lambda_max(W_e))` (the
mean of the springs' for a rod). Iteration: every vertex solves
`min f_v(x) + sum_e (rho_e/2)||F x - w + u||^2` over `Omega_v` (a cached equality
KKT solve, or Clarabel when an inequality binds); every edge solves in closed
form `min phi_e(w_h - w_t) + (rho_e/2)(||a_h - w_h||^2 + ||a_t - w_t||^2)`,
`a = F x + u`: with `p = a_h + a_t`, `m = a_h - a_t`, the sum is `p` and the
difference `d = (W + rho_e/2 I)^{-1}(W b + rho_e m / 2)` for a spring, `d = b`
for a rod (the projection); then `u += F x - w`. Two messages of `d_e` floats per
edge per iteration.
"""
function graph_admm(P::GraphProgram; xref::AbstractVector, Jref::Real, tol_obj::Real = 1e-4,
                    tol_plan::Real = 1e-3, maxit::Integer = 50_000, time_limit::Real = 120.0,
                    rho_scale::Real = 0.03)
    ts = time()
    nv, ne = nvertices(P), nedges(P)
    soft_rhos = [max(1.0, eigmax(Symmetric(E.W))) for E in P.edges if !E.hard && edgedim(E) > 0]
    rod_rho = isempty(soft_rhos) ? 1.0 : sum(soft_rhos) / length(soft_rhos)
    rho = [edgedim(E) == 0 ? 0.0 : rho_scale * (E.hard ? rod_rho : max(1.0, eigmax(Symmetric(E.W)))) for E in P.edges]
    inc = [Tuple{Int,Bool}[] for _ in 1:nv]          # (edge, is_tail)
    for (e, E) in enumerate(P.edges)
        edgedim(E) == 0 && continue
        push!(inc[E.tail], (e, true)); push!(inc[E.head], (e, false))
    end
    Ftl = [Matrix(E.Ft) for E in P.edges]; Fhd = [Matrix(E.Fh) for E in P.edges]
    proxes = Vector{VertexProx}(undef, nv)
    for v in 1:nv
        nd = P.nodes[v]
        Pv = Matrix(nd.Q)
        for (e, istail) in inc[v]
            F = istail ? Ftl[e] : Fhd[e]
            Pv .+= rho[e] .* (F' * F)
        end
        proxes[v] = VertexProx((Pv + Pv') / 2, nd)
    end
    Dinv = [(edgedim(E) == 0 || E.hard) ? zeros(0, 0) : inv(E.W + (rho[e] / 2) * I) for (e, E) in enumerate(P.edges)]
    Wb = [(edgedim(E) == 0 || E.hard) ? copy(E.b) : E.W * E.b for E in P.edges]
    wt = [zeros(edgedim(E)) for E in P.edges]; wh = [zeros(edgedim(E)) for E in P.edges]
    ut = [zeros(edgedim(E)) for E in P.edges]; uh = [zeros(edgedim(E)) for E in P.edges]
    ft = [zeros(edgedim(E)) for E in P.edges]; fh = [zeros(edgedim(E)) for E in P.edges]
    tmpe = [zeros(edgedim(E)) for E in P.edges]
    lin = [zeros(P.dims[v]) for v in 1:nv]
    x = zeros(c0dim(P))
    Hq, g, c = quadratic_form(P)
    Hx = similar(x)
    xr = Vector{Float64}(xref); nref = max(norm(xr), 1e-300); Jr = Float64(Jref)
    setup = time() - ts
    t0 = time()
    it = 0; converged = false; J = NaN; oe = Inf; pe = Inf
    while it < maxit
        # vertex proxes: lin = q_v - sum rho_e F'(w - u)
        for v in 1:nv
            lv = lin[v]
            lv .= P.nodes[v].q
            for (e, istail) in inc[v]
                te = tmpe[e]
                if istail
                    te .= wt[e] .- ut[e]; mul!(lv, Ftl[e]', te, -rho[e], 1.0)
                else
                    te .= wh[e] .- uh[e]; mul!(lv, Fhd[e]', te, -rho[e], 1.0)
                end
            end
            x[vrange(P, v)] .= prox!(proxes[v], lv)
        end
        # edge updates and scaled duals
        for (e, E) in enumerate(P.edges)
            edgedim(E) == 0 && continue
            mul!(ft[e], Ftl[e], view(x, vrange(P, E.tail))); mul!(fh[e], Fhd[e], view(x, vrange(P, E.head)))
            te = tmpe[e]
            if E.hard
                te .= Wb[e]                                   # the rod: d = b
            else
                te .= Wb[e] .+ (rho[e] / 2) .* ((fh[e] .+ uh[e]) .- (ft[e] .+ ut[e]))
                te .= Dinv[e] * te
            end
            # w_h = (p + d)/2, w_t = (p - d)/2 with p = a_h + a_t
            wh[e] .= ((fh[e] .+ uh[e]) .+ (ft[e] .+ ut[e]) .+ te) ./ 2
            wt[e] .= ((fh[e] .+ uh[e]) .+ (ft[e] .+ ut[e]) .- te) ./ 2
            ut[e] .+= ft[e] .- wt[e]; uh[e] .+= fh[e] .- wh[e]
        end
        it += 1
        mul!(Hx, Hq, x)
        J = 0.5 * dot(x, Hx) + dot(g, x) + c
        oe = abs(J - Jr) / max(abs(Jr), 1e-300)
        pe = norm(x - xr) / nref
        if oe <= tol_obj && pe <= tol_plan
            converged = true
            break
        end
        (time() - t0) > time_limit && break
    end
    fpi = floats_per_iteration(P)
    return IterativeResult(:admm, converged, it, fpi * it, fpi, time() - t0, setup, copy(x), J, oe, pe,
                           Dict{String,Any}("rho_scale" => rho_scale, "rod_rho" => rod_rho,
                                            "slow_prox_calls" => sum(p.nslow for p in proxes)))
end

# ---------------------------------------------------------------------------
# direct, timed
# ---------------------------------------------------------------------------

"""
    direct_timing(P; reps = 5, opts) -> NamedTuple

Clarabel on the whole program: one warm-up solve, then `reps` timed solves of
setup plus solve (no polish); returns the median wall time, the median of
Clarabel's own solve time, and the iteration count.
"""
function direct_timing(P::GraphProgram; reps::Integer = 5, opts::SolverOptions = DEFAULT_SOLVER)
    Hq, g, c = quadratic_form(P)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    A = [edge_operator(P, hard); node_constraints(P)[1]]
    b = [targets(P, hard); node_constraints(P)[2]]
    cones = ConeBlock[]
    nh = edgedims(P, hard)
    nh > 0 && push!(cones, zero_cone(nh))
    append!(cones, node_constraints(P)[3])
    settings = Clarabel.Settings(verbose = false, max_iter = opts.max_iter, tol_gap_abs = opts.tol, tol_gap_rel = opts.tol,
                                 tol_feas = opts.tol, presolve_enable = false)
    Pt = SpMat(triu(Hq)); Ac = _clarabel_cones(cones)
    run() = (s = Clarabel.Solver(); Clarabel.setup!(s, Pt, g, SpMat(A), b, Ac, settings); Clarabel.solve!(s))
    run()
    walls = Float64[]; inner = Float64[]; its = 0
    for _ in 1:reps
        t = @elapsed (res = run())
        push!(walls, t); push!(inner, res.solve_time); its = Int(res.iterations)
    end
    return (wall = median(walls), solve_time = median(inner), iterations = its,
            kkt_nnz = nnz(Pt) + nnz(A), nvars = length(g), nrows = size(A, 1))
end
