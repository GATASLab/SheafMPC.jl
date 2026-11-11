# direct.jl: solve any graph program as one conic QP with Clarabel.
#
# Clarabel solves  min (1/2) x'Px + q'x  s.t.  A x + s = b, s in K,  and returns
# the dual z in K* with  P x + q + A'z = 0.  We write every hard edge row as
# (delta x)_e = b_e, i.e. A = delta_e, b = b_e, in a zero cone. Then the
# Lagrangian is J(x) + z_e'((delta x)_e - b_e), so the optimal value p moves
# with the target as dp/db_e = -z_e. THEORY Thm 2.7 defines the multiplier of a
# hardened row by -mu in the subdifferential of p(s), where p(s) is the value
# with (delta x)_e = b_e + s_e; hence mu_e = z_e exactly, with this row
# orientation. The finite-difference test in test/runtests.jl checks it.

"""
    SolverOptions(; tol = 1e-10, max_iter = 400, verbose = false, ...)

Clarabel settings. `tol` sets the absolute and relative duality gap and the
feasibility tolerances; the checks run at 1e-10. `presolve = false` keeps every
row so the duals map one to one onto edges and node cones.
"""
Base.@kwdef struct SolverOptions
    tol::Float64 = 1e-10
    infeas_tol::Float64 = 1e-10
    ktratio::Float64 = 1e-8
    max_iter::Int = 400
    verbose::Bool = false
    presolve::Bool = false
    equilibrate::Bool = true
    static_reg::Float64 = 1e-8
    direct_solve_method::Symbol = :qdldl
    polish::Bool = true
end

const DEFAULT_SOLVER = SolverOptions()

function _clarabel_cones(cones::Vector{ConeBlock})
    out = Clarabel.SupportedCone[]
    for cb in cones
        cb.dim == 0 && continue
        if cb.kind == ZERO_CONE
            push!(out, Clarabel.ZeroConeT(cb.dim))
        elseif cb.kind == NONNEG_CONE
            push!(out, Clarabel.NonnegativeConeT(cb.dim))
        else
            push!(out, Clarabel.SecondOrderConeT(cb.dim))
        end
    end
    return out
end

_status_rank(st::Symbol) = st in (:optimal, :infeasible, :unbounded) ? 3 : (st == :almost_optimal ? 2 : 1)

function _status_symbol(st)
    st == Clarabel.SOLVED && return :optimal
    st == Clarabel.ALMOST_SOLVED && return :almost_optimal
    (st == Clarabel.PRIMAL_INFEASIBLE || st == Clarabel.ALMOST_PRIMAL_INFEASIBLE) && return :infeasible
    (st == Clarabel.DUAL_INFEASIBLE || st == Clarabel.ALMOST_DUAL_INFEASIBLE) && return :unbounded
    return Symbol(lowercase(string(st)))
end

"""
    QPResult

Raw result of `solve_qp`: primal `x`, slack `s`, dual `z`, status, objective
(with the constant), Clarabel's accuracy report, whether the active-set polish
was accepted, and the KKT residual before and after it.
"""
struct QPResult
    status::Symbol
    x::Vector{Float64}
    s::Vector{Float64}
    z::Vector{Float64}
    obj::Float64
    obj_dual::Float64
    iterations::Int
    solve_time::Float64
    r_prim::Float64
    r_dual::Float64
    gap_abs::Float64
    gap_rel::Float64
    polished::Bool
    kkt_ipm::Float64
    kkt::Float64
    attempts::Int
end

"""
KKT residual of `(x, s, z)` for `min (1/2)x'Hx + g'x s.t. Ax + s = b, s in K`:
the largest of the scaled stationarity, primal and cone residuals and the
complementarity `|s'z|`.
"""
function kkt_residual(H, g, A, b, cones::Vector{ConeBlock}, x, s, z)
    stat = norm(H * x + g + A' * z, Inf) / (1 + norm(g, Inf))
    prim = norm(A * x + s - b, Inf) / (1 + norm(b, Inf))
    cv = 0.0; dv = 0.0
    r = 0
    for cb in cones
        rr = (r+1):(r+cb.dim)
        cv = max(cv, cone_violation(cb.kind, view(s, rr)))
        cb.kind == ZERO_CONE || (dv = max(dv, cone_violation(cb.kind, view(z, rr))))
        r += cb.dim
    end
    comp = abs(dot(s, z)) / (1 + abs(dot(x, H * x) / 2 + dot(g, x)))
    return max(stat, prim, cv, dv, comp)
end

"""
    _polish(H, g, A, b, cones, x, s, z)

Active-set Newton polish of an interior-point solution. From the IPM iterate,
classify every cone row: zero rows and active half-spaces become equalities;
an SOC block with its slack on the boundary (and away from the apex) keeps the
curved constraint `(1/2)(s0^2 - ||s1||^2) = 0` with the dual `z = eta (s0, -s1)`;
everything else is inactive. Newton's method on these KKT conditions converges
in one step for a polyhedral active set and quadratically otherwise. Returns
`nothing` if the classification is ambiguous (an SOC at its apex) or the linear
solves fail; the caller accepts the result only if it lowers the KKT residual.
"""
function _polish(H::SpMat, g::Vector{Float64}, A::SpMat, b::Vector{Float64},
                 cones::Vector{ConeBlock}, x0::Vector{Float64}, s0::Vector{Float64}, z0::Vector{Float64};
                 maxit::Int = 6)
    n = length(x0)
    eq = Int[]
    socb = UnitRange{Int}[]
    inactive_nn = Int[]
    inactive_soc = UnitRange{Int}[]
    r = 0
    for cb in cones
        rr = (r+1):(r+cb.dim)
        if cb.kind == ZERO_CONE
            append!(eq, rr)
        elseif cb.kind == NONNEG_CONE
            for i in rr
                s0[i] < z0[i] ? push!(eq, i) : push!(inactive_nn, i)
            end
        else
            st, zt = s0[rr[1]], z0[rr[1]]
            ss = norm(view(s0, rr[2:end]))
            gap_s = st - ss                        # distance of the slack to the boundary
            if zt < gap_s
                push!(inactive_soc, rr)            # dual small: constraint inactive
            elseif st < 1e-6 * max(1.0, zt)
                return nothing                     # slack near the apex: degenerate
            else
                push!(socb, rr)                    # both on their boundaries
            end
        end
        r += cb.dim
    end
    Aeq = A[eq, :]; beq = b[eq]
    ne, nk = length(eq), length(socb)
    x = copy(x0)
    zeq = z0[eq]
    eta = [z0[rr[1]] / max(s0[rr[1]], eps()) for rr in socb]
    Jm(v) = [v[1]; -v[2:end]]
    for it in 1:maxit
        sk = [b[rr] - A[rr, :] * x for rr in socb]
        F1 = H * x + g + Aeq' * zeq
        for (k, rr) in enumerate(socb)
            F1 .+= eta[k] * (A[rr, :]' * Jm(sk[k]))
        end
        F2 = Aeq * x - beq
        F3 = [-0.5 * (sk[k][1]^2 - sum(abs2, sk[k][2:end])) for k in 1:nk]
        res = max(norm(F1, Inf), norm(F2, Inf; ), isempty(F3) ? 0.0 : norm(F3, Inf))
        res < 1e-15 * (1 + norm(g, Inf) + norm(b, Inf)) && break
        Hn = copy(H)
        C = spzeros(n, nk)
        for (k, rr) in enumerate(socb)
            Ak = A[rr, :]
            Jd = sparse(Diagonal([1.0; -ones(length(rr) - 1)]))
            Hn -= eta[k] * (Ak' * Jd * Ak)
            C[:, k] = Ak' * Jm(sk[k])
        end
        K = [Hn Aeq' C; Aeq spzeros(ne, ne) spzeros(ne, nk); C' spzeros(nk, ne) spzeros(nk, nk)]
        rhs = -[F1; F2; F3]
        d = try
            lu(K) \ rhs
        catch
            nothing
        end
        if d === nothing || !all(isfinite, d) || norm(K * d - rhs, Inf) > 1e-9 * (1 + norm(rhs, Inf))
            # singular (dependent equality rows): regularized solve with refinement
            delta = 1e-11
            Kr = K - blockdiag(spzeros(n, n), delta * sparse(I, ne + nk, ne + nk))
            F = try
                lu(Kr)
            catch
                return nothing
            end
            d = F \ rhs
            for _ in 1:20
                rr_ = rhs - K * d
                norm(rr_, Inf) <= 1e-14 * (1 + norm(rhs, Inf)) && break
                d .+= F \ rr_
            end
            all(isfinite, d) || return nothing
        end
        x .+= d[1:n]
        zeq .+= d[(n+1):(n+ne)]
        eta .+= d[(n+ne+1):end]
    end
    s = b - A * x
    s[eq] .= 0.0
    z = zeros(length(b))
    z[eq] = zeq
    for (k, rr) in enumerate(socb)
        z[rr] = eta[k] * Jm(s[rr])
    end
    return x, s, z
end

"""
    solve_qp(H, g, c, A, b, cones; opts) -> QPResult

`min (1/2) x'Hx + g'x + c  s.t.  b - A x in K` with Clarabel.
"""
function solve_qp(H::AbstractMatrix, g::AbstractVector, c::Real, A::AbstractMatrix,
                  b::AbstractVector, cones::Vector{ConeBlock}; opts::SolverOptions = DEFAULT_SOLVER)
    n = length(g)
    Hs = SpMat(sparse(H))
    Hs = SpMat((Hs + Hs') / 2)
    As = SpMat(sparse(A))
    if size(As, 1) == 0
        # Clarabel needs at least one row; add an empty nonnegative row 0 <= 1
        As = spzeros(1, n); bb = [1.0]; cc = [nonneg_cone(1)]
        nrow = 0
    else
        bb = Vector{Float64}(b); cc = cones
        nrow = size(As, 1)
    end
    # Clarabel occasionally stops with a factorization failure on a coarse
    # program (constant rows of the input cones after substitution). An
    # inconclusive status is retried with a small ladder of settings; the
    # number of attempts is recorded.
    ladder = [(opts.static_reg, opts.equilibrate), (1e-7, opts.equilibrate), (opts.static_reg, false), (1e-6, false)]
    res = nothing; solver = nothing; st = :unsolved; attempts = 0
    for (reg, equil) in ladder
        attempts += 1
        settings = Clarabel.Settings(verbose = opts.verbose, max_iter = opts.max_iter,
                                     tol_gap_abs = opts.tol, tol_gap_rel = opts.tol, tol_feas = opts.tol,
                                     tol_infeas_abs = opts.infeas_tol, tol_infeas_rel = opts.infeas_tol,
                                     tol_ktratio = opts.ktratio, presolve_enable = opts.presolve,
                                     equilibrate_enable = equil,
                                     static_regularization_constant = reg,
                                     direct_solve_method = opts.direct_solve_method)
        solver_k = Clarabel.Solver()
        Clarabel.setup!(solver_k, SpMat(triu(Hs)), Vector{Float64}(g), As, bb, _clarabel_cones(cc), settings)
        res_k = Clarabel.solve!(solver_k)
        st_k = _status_symbol(res_k.status)
        if res === nothing || _status_rank(st_k) > _status_rank(st)
            res, solver, st = res_k, solver_k, st_k
        end
        st in (:optimal, :infeasible, :unbounded) && break
    end
    info = solver.info
    x = copy(res.x); s = copy(res.s); z = copy(res.z)
    ok = st in (:optimal, :almost_optimal)
    kkt0 = ok ? kkt_residual(Hs, g, As, bb, cc, x, s, z) : NaN
    kkt1 = kkt0
    polished = false
    if opts.polish && ok && nrow > 0
        pol = _polish(Hs, Vector{Float64}(g), As, bb, cc, x, s, z)
        if pol !== nothing
            xp, sp, zp = pol
            k1 = kkt_residual(Hs, g, As, bb, cc, xp, sp, zp)
            if k1 < kkt0
                x, s, z, kkt1, polished = xp, sp, zp, k1, true
            end
        end
    end
    obj = ok ? 0.5 * dot(x, Hs * x) + dot(g, x) + c : (st == :infeasible ? Inf : NaN)
    objd = ok ? res.obj_val_dual + c : NaN
    z = nrow == 0 ? Float64[] : z
    s = nrow == 0 ? Float64[] : s
    return QPResult(st, x, s, z, obj, objd, Int(res.iterations), res.solve_time,
                    res.r_prim, res.r_dual, info.gap_abs, info.gap_rel, polished, kkt0, kkt1, attempts)
end

"""
    DirectSolution

The solution of a graph program by `solve_direct`:

* `status` (`:optimal`, `:almost_optimal`, `:infeasible`, ...), `x` (flat vector);
* `J`: the objective evaluated from the data at `x` (`objective(P, x)`), `+Inf`
  when infeasible; `J_solver`: Clarabel's primal objective plus the constant;
  `J_dual`: the dual objective;
* `edge_duals[e]`: the multiplier `mu_e` of hard edge `e` (empty for soft edges),
  with the sign convention of THEORY Thm 2.7;
* `node_duals[v]`, `node_slacks[v]`: dual and slack of vertex `v`'s cone rows;
* accuracy: iterations, time, Clarabel residuals, whether the active-set polish
  was accepted, the KKT residual before and after it, and the residuals of `x`
  recomputed from the data (`feas`).
"""
struct DirectSolution
    status::Symbol
    x::Vector{Float64}
    J::Float64
    J_solver::Float64
    J_dual::Float64
    edge_duals::Vector{Vector{Float64}}
    node_duals::Vector{Vector{Float64}}
    node_slacks::Vector{Vector{Float64}}
    iterations::Int
    solve_time::Float64
    r_prim::Float64
    r_dual::Float64
    gap_abs::Float64
    gap_rel::Float64
    polished::Bool
    kkt_ipm::Float64
    kkt::Float64
    attempts::Int
    feas::NamedTuple
end

isoptimal(sol::DirectSolution) = sol.status in (:optimal, :almost_optimal)
isinfeasible(sol::DirectSolution) = sol.status == :infeasible

"""
    solve_direct(P; opts) -> DirectSolution

Assemble the whole program as one Clarabel problem: the
objective `quadratic_form(P)`, the hard edge rows first (one zero cone, in edge
order), then every node's cone rows in vertex order. Returns the primal
solution, the objective with its constant, and the duals of every hard edge row
and every node cone.
"""
function solve_direct(P::GraphProgram; opts::SolverOptions = DEFAULT_SOLVER)
    Hq, g, c = quadratic_form(P)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    Dh = edge_operator(P, hard)
    bh = targets(P, hard)
    An, bn, cn, roff = node_constraints(P)
    A = [Dh; An]
    b = [bh; bn]
    cones = ConeBlock[]
    length(bh) > 0 && push!(cones, zero_cone(length(bh)))
    append!(cones, cn)
    res = solve_qp(Hq, g, c, A, b, cones; opts = opts)
    ne, nv = nedges(P), nvertices(P)
    edge_duals = [Float64[] for _ in 1:ne]
    node_duals = [Float64[] for _ in 1:nv]
    node_slacks = [Float64[] for _ in 1:nv]
    ok = res.status in (:optimal, :almost_optimal)
    if !isempty(res.z)
        row = 0
        for e in hard
            d = edgedim(P.edges[e])
            edge_duals[e] = res.z[(row+1):(row+d)]
            row += d
        end
        nh = length(bh)
        for v in 1:nv
            rr = (nh+roff[v]+1):(nh+roff[v+1])
            node_duals[v] = res.z[rr]
            node_slacks[v] = res.s[rr]
        end
    end
    J = ok ? objective(P, res.x) : (res.status == :infeasible ? Inf : NaN)
    feas = feasibility(P, res.x)
    return DirectSolution(res.status, res.x, J, res.obj, res.obj_dual, edge_duals, node_duals,
                          node_slacks, res.iterations, res.solve_time, res.r_prim, res.r_dual,
                          res.gap_abs, res.gap_rel, res.polished, res.kkt_ipm, res.kkt, res.attempts, feas)
end

"""
    solve_hardened(P, S; opts) -> (sol, mu)

Solve the fine representation `P[S]` with the rows of `S` as
explicit equality rows, and return the multipliers `mu[k]` of the hardened rows
of `S[k]` (sign convention of THEORY Thm 2.7: `-mu` is a subgradient of the
optimal value in the targets of `S`).
"""
function solve_hardened(P::GraphProgram, S; opts::SolverOptions = DEFAULT_SOLVER)
    sol = solve_direct(harden(P, S); opts = opts)
    mu = [sol.edge_duals[e] for e in S]
    return sol, mu
end

"""`(1/2) sum_{e in S} ||mu_e||^2_{W_e^{-1}}`, the upper bound of THEORY Thm 2.7(a) (weights from `P`)."""
function price_upper_bound(P::GraphProgram, S, mu)
    tot = 0.0
    for (k, e) in enumerate(S)
        m = mu[k]
        isempty(m) && continue
        tot += 0.5 * dot(m, P.edges[e].W \ m)
    end
    return tot
end

"""`(1/2) sum_{e in S} ||s_e||^2_{W_e}` at `x`, the lower bound of THEORY Thm 2.7(b)."""
function price_lower_bound(P::GraphProgram, S, x::AbstractVector)
    tot = 0.0
    for e in S
        edgedim(P.edges[e]) == 0 && continue
        s = edge_defect(P, e, x)
        tot += 0.5 * dot(s, P.edges[e].W * s)
    end
    return tot
end
