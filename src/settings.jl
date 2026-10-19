# settings.jl: solver settings and the result record.

"""
    Settings(; kwargs...)

Solver settings (defaults follow OSQP where the option exists there):

ADMM
* `rho = 0.03` (OSQP uses 0.1), the penalty when `rho_spectral = false` or
  the problem has no inequality rows, `sigma = 1e-6`, `alpha = 1.6`
  (over-relaxation);
* `rho_eq_scale = 1e3`: equality rows get `rho_eq_scale * rho`, free rows `rho_min`;
* `rho_spectral = true`: replace `rho` by `rho_spectral_scale / sqrt(lmin lmax)`,
  the extreme eigenvalues of the inequality and cone rows' operator on the
  null space of the equality rows, `A_I (P restricted)^{-1} A_I'`, estimated
  by `rho_spectral_iter` Lanczos steps in `setup` (the optimal ADMM penalty of
  Ghadimi et al. 2015 for a QP; see rho.jl), `rho_spectral_scale = 1.0`,
  `rho_spectral_iter = 25`; on the fleet MPC family it halves the iterations
  of a fixed rho = 0.03 and of the adaptive rule, which drifts away from it;
* `adaptive_rho = true`, `adaptive_rho_interval = 25`, `adaptive_rho_tolerance = 25`:
  every `adaptive_rho_interval` iterations rho is re-estimated from the ratio of
  the normalized primal and dual residuals and the KKT matrix is refactored
  only if the estimate moved by more than the tolerance factor (OSQP uses 5;
  with the spectral rho the residual-balancing estimate is a safeguard against
  a badly wrong rho, not a tuning rule: it moves a good rho away from the
  fastest active-set identification);
  `adaptive_rho_tolerance_soc = 5`: the tolerance for problems with
  second-order cones, where ADMM finishes by a slow linear tail rather than
  by identifying an active set, and a residual imbalance of 5 or more costs
  more iterations than the refactorization (on grid fleets with input balls
  it halves the iterations);
  `adaptive_rho_first > 0` adds one early estimate at that iteration;
* `max_iter = 4000`, `time_limit = Inf` (seconds);
* `anderson = 0`: memory of the safeguarded type-II Anderson acceleration of
  the iteration (0 disables; see anderson.jl), `anderson_safeguard = 1.0`: an
  accelerated point is rejected when its fixed-point residual exceeds this
  factor times the residual it was computed from.

Termination (OSQP's unscaled criteria)
* `eps_abs = 1e-3`, `eps_rel = 1e-3`, checked every `check_termination = 25` iterations;
* `eps_prim_inf = 1e-4`, `eps_dual_inf = 1e-4`: infeasibility certificates;
* `check_gap = true`: also require the duality gap test of termination.jl,
  `|f_p - f_d| <= eps_abs + eps_rel min(|f_p|, |f_d|)` (objectives with the
  constant), of every ADMM iterate and polished point that is accepted. Without
  it a problem whose `P x` and `q` are large and cancel can meet the residual
  tests with an objective far less accurate than eps.

Method (see method.jl)
* `method = :auto`: `:admm`, `:ipm` (the interior-point method of ipm.jl on the
  same KKT pattern) or `:auto`: ADMM with a budget of iterations, crossing over
  to the IPM when the budget runs out, and the IPM directly once this solver's
  ADMM solves have cost more than its IPM solves; the IPM directly for
  problems with second-order cones solved cold at `eps <= ipm_eps_direct`;
* `ipm_eps_direct = 1e-10`: tolerance at or below which `:auto` starts with the IPM;
* `crossover = 1.0`: ADMM budget as a multiple of the estimated cost of an IPM
  solve (in ADMM iterations; 0 disables the crossover);
* `ipm_polish = false`: polish on the active set the IPM identifies (an exact
  solution, and the iterate of the next warm-started ADMM solve): during the
  iterations, up to `ipm_polish_tries = 2` times, once the duality gap is below
  `ipm_polish_gap = 1e-5` (relative) and the residuals below the square roots
  of their tolerances, with at most `ipm_polish_newton = 3` Newton steps;
  an accepted polish ends the solve. With
  `ipm_polish_final = false` a converged IPM point is returned as it is;
* `ipm_max_iter = 100`, `ipm_reg = 1e-8` (static regularization of the
  interior-point KKT matrix; iterative refinement removes it),
  `ipm_step_fraction = 0.99`, `ipm_eps_infeas = 1e-8` (infeasibility certificates).

Scaling
* `scaling = 10` rounds of modified Ruiz equilibration (0 disables).

Polishing (active-set refinement)
* `polish = true`: once ADMM has converged, guess the active set, solve the
  equality-constrained QP on it exactly (one LDLt of a matrix with the KKT
  pattern, `polish_refine_iter` steps of iterative refinement) and accept the
  result only if it satisfies the KKT conditions to the termination tolerance
  (primal and dual residuals and the signs of the multipliers);
* `polish_corrections = 3`: if not, correct the active set from the polished
  point (a primal-dual active-set step) and try again, up to this many times,
  as long as every correction at least halves the KKT merit of the polished
  point (a correction that does not is not converging, and each costs a
  factorization);
* `polish_soc_newton = 6`: Newton steps of the polish for second-order cone
  blocks on their boundary (see polish.jl);
* `polish_soc_band = 1e-6`: hysteresis of the classification of SOC blocks
  (inactive, boundary, apex) read off the ADMM iterates: a block keeps its
  class while it is within this relative band of the boundary (a wider band
  settles the guess, and so enters the polish, earlier, from a less accurate
  iterate that then needs more Newton factorizations: worth it only where
  factorizations are cheap against ADMM iterations);
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
  every `polish_warm_retry`-th solve until it succeeds again (1: every solve);
* `polish_warm_last = 3`: before that, a warm solve tries the active set of
  the last accepted polish, unshifted (in steady tracking the active set stays
  put in index space, and its polish factorization is still cached, so the
  attempt costs one solve), with up to this many active-set corrections
  (-1 disables); after a failure it is retried every `polish_warm_retry`-th
  solve, like the shifted one;
* `warm_reset_rho = true`: `warm_start!` puts rho back to `rho` if the last
  solve adapted it beyond the tolerance factor (one refactorization);
* `polish_delta = 1e-6`: regularization of the polish system.

Dense active-set path (small polyhedral problems, see dual.jl)
* `dual = :auto`: for problems without second-order cones and with at most
  `dual_max_rows = 400` inequality rows, `setup` also factors the KKT matrix
  of the equality rows alone (K11) and builds the Schur complement Z of the
  inequality rows; solves then try primal-dual active-set iterations on the
  dense Z first (cold: from the equality-only solution; warm: from the last
  accepted active set, then from the warm iterate's), and ADMM seeds them
  with its own guess every `dual_interval = 5` iterations, before the sparse
  polish (`:on` ignores the size limits, `:off` disables the path);
* `dual_setup_budget = 1e-3`: seconds of K11 solves (by the factor's
  operation count) allowed in `setup` to build all of Z; beyond it a column of
  Z is computed when its row first enters an active set, and kept. Building Z
  in `setup` moves its cost out of the solves (receding horizon pays it once);
  for a problem solved once, `dual_setup_budget = 0` (Z always lazy) gives the
  smaller setup plus solve time;
* `dual_iter = 12` iterations per attempt, and `dual_budget = 1.0`: the work
  of an attempt (dense updates and new columns of Z, by operation count) is
  bounded by this many sparse factorizations of K11 plus 20 solves, and all
  the attempts of a solve by twice that; an attempt that stops (no
  convergence, the budget) costs no factorization, and once an attempt seeded
  by a guess runs out of budget the solve continues with the sparse polish;
  after a solve in which the path failed it is retried after 4, 8, 16, ...
  solves;
* `dual_delta = 1e-8`: regularization of K11 and of the dense factor
  (iterative refinement against the exact system removes it).

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
* `kkt_relax = :light`: supernode relaxation (`:exact` no explicit zeros,
  `:light` a few, `:cholmod` CHOLMOD's rules); the KKT matrices of fleets have
  mostly one-column fundamental supernodes, and merging them halves the
  supernode count and the time of a factorization for a few percent more
  entries of L;
* `kkt_structure = nothing`: `(agent = ..., block = ...)` labels of the
  variables (agent index, time instant or block).
"""
Base.@kwdef mutable struct Settings
    rho::Float64 = 0.03
    sigma::Float64 = 1e-6
    alpha::Float64 = 1.6
    rho_eq_scale::Float64 = 1e3
    rho_spectral::Bool = true
    rho_spectral_scale::Float64 = 1.0
    rho_spectral_iter::Int = 25
    rho_min::Float64 = 1e-6
    rho_max::Float64 = 1e6
    adaptive_rho::Bool = true
    adaptive_rho_interval::Int = 25
    adaptive_rho_first::Int = 0
    adaptive_rho_tolerance::Float64 = 25.0
    adaptive_rho_tolerance_soc::Float64 = 5.0
    max_iter::Int = 4000
    anderson::Int = 0
    anderson_safeguard::Float64 = 1.0
    time_limit::Float64 = Inf
    eps_abs::Float64 = 1e-3
    eps_rel::Float64 = 1e-3
    eps_prim_inf::Float64 = 1e-4
    eps_dual_inf::Float64 = 1e-4
    check_gap::Bool = true
    check_termination::Int = 25
    scaling::Int = 10
    polish::Bool = true
    polish_corrections::Int = 3
    polish_restart::Bool = true
    polish_soc_newton::Int = 6
    polish_soc_band::Float64 = 1e-6
    polish_interval::Int = 10
    polish_gate::Float64 = 0.0
    polish_settle::Float64 = 0.0
    polish_warm::Bool = true
    polish_warm_retry::Int = 4
    polish_warm_last::Int = 3
    polish_delta::Float64 = 1e-6
    polish_refine_iter::Int = 3
    warm_start::Bool = true
    warm_reset_rho::Bool = true
    linsys::Symbol = :auto
    ordering::Symbol = :amd
    kkt_ordering::Symbol = :auto
    kkt_threads::Int = 1
    kkt_relax::Symbol = :light
    kkt_structure::Any = nothing
    verbose::Bool = false
    method::Symbol = :auto
    ipm_eps_direct::Float64 = 1e-10
    crossover::Float64 = 1.0
    ipm_polish::Bool = false
    ipm_polish_tries::Int = 2
    ipm_polish_newton::Int = 3
    ipm_polish_gap::Float64 = 1e-5
    ipm_polish_final::Bool = false
    ipm_max_iter::Int = 100
    ipm_reg::Float64 = 1e-8
    ipm_step_fraction::Float64 = 0.99
    ipm_eps_infeas::Float64 = 1e-8
    dual::Symbol = :auto
    dual_max_rows::Int = 400
    dual_setup_budget::Float64 = 1e-3
    dual_iter::Int = 12
    dual_interval::Int = 5
    dual_budget::Float64 = 1.0
    dual_delta::Float64 = 1e-8
end

"""
    Info

Outcome of the last `solve!`: `status` (`:solved`, `:max_iter`, `:time_limit`,
`:primal_infeasible`, `:dual_infeasible`), objective `obj` (with the constant),
ADMM iterations `iter`, unscaled residuals `prim_res`, `dual_res`, `rho` at the
end and the number of rho updates (refactorizations), the polish outcome
(`:success`, `:failed`, `:skipped`, `:none`), the number of polish solves
attempted and of polish refactorizations (a cached polish factorization is
reused when the active set repeats), times in seconds, the duality gap `gap`
of the returned point, the `method` that produced it (`:admm`, `:ipm`, or
`:admm_ipm` after a crossover) and the interior-point iterations `ipm_iter`.
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
    gap::Float64 = NaN
    method::Symbol = :none
    ipm_iter::Int = 0
end
