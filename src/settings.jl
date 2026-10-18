# settings.jl: solver settings and the result record.

"""
    Settings(; kwargs...)

Solver settings (defaults follow OSQP where the option exists there):

ADMM
* `rho = 0.03` (OSQP uses 0.1; 0.03 was faster on the fleet MPC family), `sigma = 1e-6`,
  `alpha = 1.6` (over-relaxation);
* `rho_eq_scale = 1e3`: equality rows get `rho_eq_scale * rho`, free rows `rho_min`;
* `adaptive_rho = true`, `adaptive_rho_interval = 25`, `adaptive_rho_tolerance = 5`:
  every `adaptive_rho_interval` iterations rho is re-estimated from the ratio of
  the normalized primal and dual residuals and the KKT matrix is refactored
  only if the estimate moved by more than the tolerance factor;
  `adaptive_rho_first > 0` adds one early estimate at that iteration;
* `max_iter = 4000`, `time_limit = Inf` (seconds).

Termination (OSQP's unscaled criteria)
* `eps_abs = 1e-3`, `eps_rel = 1e-3`, checked every `check_termination = 25` iterations;
* `eps_prim_inf = 1e-4`, `eps_dual_inf = 1e-4`: infeasibility certificates.

Scaling
* `scaling = 10` rounds of modified Ruiz equilibration (0 disables).

Polishing (active-set refinement)
* `polish = true`: once ADMM has converged, guess the active set, solve the
  equality-constrained QP on it exactly (one LDLt of a matrix with the KKT
  pattern, `polish_refine_iter` steps of iterative refinement) and accept the
  result only if it satisfies the KKT conditions to the termination tolerance
  (primal and dual residuals and the signs of the multipliers);
* `polish_corrections = 1`: if not, correct the active set from the polished
  point (a primal-dual active-set step) and try again, up to this many times;
* `polish_soc_newton = 6`: Newton steps of the polish for second-order cone
  blocks on their boundary (see polish.jl);
* `polish_restart = true`: after a rejected polish, restart ADMM from the
  polished point (its primal, and the Moreau decomposition of `A x + y / rho`
  for the constraint and dual iterates), which carries the active-set
  correction into the iterations;
* `polish_interval = 10`: also attempt the polish during the iterations, as soon
  as the active set guess has been the same for `polish_interval` iterations
  (0 disables these early attempts); after a failed early attempt the wait
  before the next one doubles, so failed attempts cost a bounded fraction of
  the run;
* `polish_warm = true`: when a solve starts warm, attempt the polish before the
  first iteration (in steady receding horizon the active set of the shifted
  plan is usually the right one); after a failed warm polish it is tried only
  every 4th solve until it succeeds again;
* `warm_reset_rho = true`: `warm_start!` puts rho back to `rho` if the last
  solve adapted it beyond the tolerance factor (one refactorization);
* `polish_delta = 1e-6`: regularization of the polish system.

Linear algebra
* `linsys = :auto`: the engine (`:qdldl`, simplicial, or `:blockldl`,
  multifrontal) and the elimination order picked by BlockLDL's cost model from
  elimination-tree statistics of the candidate orders, factored once (the same
  as `:model`); `:timed` instead times solves with QDLDL (orders AMD, MMD,
  AMF) and CliqueTrees in `setup` and keeps the fastest; or one backend:
  `:qdldl`, `:cliquetrees`, `:blockldl`;
* `ordering = :amd`: the fill-reducing ordering when `linsys = :qdldl`
  (`:amd`, `:mmd`, `:amf`, `:mf`).

Structured KKT kernel (`linsys = :blockldl`, see `BlockLDL`; `linsys = :model`
picks the engine, QDLDL or BlockLDL, and the order by BlockLDL's cost model
without trial factorizations)
* `kkt_ordering = :auto`: picked by the cost model among `:amd`, `:amf`,
  `:metis` (with Metis.jl loaded) and, given `kkt_structure`, the
  structure-given `:stage` (time-major, Riccati-like), `:chain` (per-agent
  chain condensing, then the agent coupling) and `:nd2`, `:nd4`, `:nd8`,
  `:nd16` (nested dissection of the agent graph, leaves of that many agents);
* `kkt_threads = 1`: threads for the factorization and the solves (subtrees
  of the elimination tree in parallel);
* `kkt_relax = :exact`: supernode relaxation (`:exact` no explicit zeros,
  `:light`, `:cholmod`);
* `kkt_structure = nothing`: `(agent = ..., block = ...)` labels of the
  variables (agent index, time instant or block).
"""
Base.@kwdef mutable struct Settings
    rho::Float64 = 0.03
    sigma::Float64 = 1e-6
    alpha::Float64 = 1.6
    rho_eq_scale::Float64 = 1e3
    rho_min::Float64 = 1e-6
    rho_max::Float64 = 1e6
    adaptive_rho::Bool = true
    adaptive_rho_interval::Int = 25
    adaptive_rho_first::Int = 0
    adaptive_rho_tolerance::Float64 = 5.0
    max_iter::Int = 4000
    time_limit::Float64 = Inf
    eps_abs::Float64 = 1e-3
    eps_rel::Float64 = 1e-3
    eps_prim_inf::Float64 = 1e-4
    eps_dual_inf::Float64 = 1e-4
    check_termination::Int = 25
    scaling::Int = 10
    polish::Bool = true
    polish_corrections::Int = 1
    polish_restart::Bool = true
    polish_soc_newton::Int = 6
    polish_interval::Int = 10
    polish_gate::Float64 = 0.0
    polish_warm::Bool = true
    polish_delta::Float64 = 1e-6
    polish_refine_iter::Int = 3
    warm_start::Bool = true
    warm_reset_rho::Bool = true
    linsys::Symbol = :auto
    ordering::Symbol = :amd
    kkt_ordering::Symbol = :auto
    kkt_threads::Int = 1
    kkt_relax::Symbol = :exact
    kkt_structure::Any = nothing
    verbose::Bool = false
end

"""
    Info

Outcome of the last `solve!`: `status` (`:solved`, `:max_iter`, `:time_limit`,
`:primal_infeasible`, `:dual_infeasible`), objective `obj` (with the constant),
ADMM iterations `iter`, unscaled residuals `prim_res`, `dual_res`, `rho` at the
end and the number of rho updates (refactorizations), the polish outcome
(`:success`, `:failed`, `:skipped`, `:none`), the number of polish solves
attempted and of polish refactorizations (a cached polish factorization is
reused when the active set repeats), and times in seconds.
"""
Base.@kwdef mutable struct Info
    status::Symbol = :unsolved
    obj::Float64 = NaN
    iter::Int = 0
    prim_res::Float64 = NaN
    dual_res::Float64 = NaN
    rho::Float64 = NaN
    rho_updates::Int = 0
    polish::Symbol = :none
    polish_attempts::Int = 0
    polish_factorizations::Int = 0
    polish_iter::Int = -1               # ADMM iteration at which the accepted polish ran
    setup_time::Float64 = 0.0
    solve_time::Float64 = 0.0
    polish_time::Float64 = 0.0
    linsys::Symbol = :none
end
