# method.jl: `solve!`, choosing between the ADMM (solver.jl, polish.jl) and the
# interior-point method (ipm.jl), and the crossover from one to the other.
#
# The two methods share the scaled problem, the KKT sparsity pattern and its
# symbolic factorization. They have complementary costs: an ADMM iteration is
# one solve with a fixed factorization, and a polished ADMM solve is cheapest
# when the iterations identify the active set fast (box constraints, warm
# starts in receding horizon); an IPM iteration is one numerical factorization
# and a few solves, and its iteration count (10 to 20) hardly depends on the
# conditioning or on how many cones are active, which is where ADMM is slow
# (second-order cones on their boundary, pushed-forward programs with large
# cancelling costs). With `method = :auto`:
#
#   * a cold solve of a problem with second-order cones at a tolerance
#     `<= ipm_eps_direct` goes to the IPM directly, and so does a cold solve
#     whose estimated IPM cost is below that of an ADMM solve of a prior
#     iteration count (`_ipm_first`: large problems at loose tolerances);
#   * otherwise ADMM runs with a budget of iterations worth `crossover` times
#     the estimated cost of an IPM solve (the cost model: seconds per ADMM
#     iteration, per ADMM solve and per IPM solve, measured in `setup` and
#     refreshed by every solve); when the budget runs out, the IPM solves the
#     problem from scratch (interior-point methods gain little from a warm
#     start). The work lost to a crossover is bounded by `crossover` times an
#     IPM solve;
#   * when the ADMM solves of this solver cost more on average than its IPM
#     solves (a crossover counts as twice its ADMM time) and the last two
#     crossed over, the next solves go to
#     the IPM directly, warm solves after the cheap warm polish, with an ADMM
#     probe every `PROBE_EVERY` solves (`update!` keeps the structure, so the
#     experience of the last solves is a good predictor of the next).
#
# The IPM falls back on a stall (its KKT solves losing the accuracy the
# tolerance needs): the active-set polish from its last iterate, then ADMM
# warm started from that iterate. With `ipm_polish` its solution is polished
# on the active set it identifies (exact, at the price of a few factorizations).

"""
The cost model at setup, with no timing and no factorization: seconds per ADMM
iteration and per IPM solve estimated by the kernel's cost model (src/kkt)
from the statistics of the ADMM system's own factor (nnz(L) and flops of its
ordering), see `_ipm_cost_estimate`. Both estimates are replaced by
measured times as solves run. The IPM system itself is built on the first
crossover (`_run_ipm!`); `method = :ipm` builds it here, since every solve
needs it.
"""
function _cost_setup!(s)
    st = s.settings
    (s.m == 0 || st.method == :admm) && return nothing
    st.method == :ipm && (s.ipm = _ipm_work(s))
    t_ipm, t_it, tf = _ipm_cost_estimate(s)
    s.cost.t_ipm = t_ipm
    s.cost.t_admm_iter = t_it
    s.cost.t_factor = tf
    return nothing
end

"Elimination statistics (nnz(L), flops) and engine of a factored system, in the kernel's cost-model terms."
function _factor_stats(S::QDLDLSystem)
    fl = 0.0; nl = S.Ln
    @inbounds for j in 1:S.Ln
        c = S.Lp[j+1] - S.Lp[j]
        fl += c * (c + 1) / 2 + 1
        nl += c
    end
    return (nnzL = nl, flops = fl, critical = fl), :simplicial
end
function _factor_stats(S::BlockLDLSystem)
    st = BlockLDL.order_stats(S.K, S.F.S.perm)
    return (nnzL = st.nnzL, flops = st.flops, critical = st.critical), :multifrontal
end
function _factor_stats(S::LinearSystem)
    st = BlockLDL.order_stats(S.K, S.perm)
    return (nnzL = st.nnzL, flops = st.flops, critical = st.critical), :multifrontal
end

"""
Interior-point iterations to the tolerance `eps` (Mehrotra predictor-corrector
from the homogeneous starting point, measured on the benchmark families):
with second-order cones about 5 at 1e-3, 8 at 1e-6 and 11 at 1e-9;
polyhedral problems (box constraints, many of them active) two more.
"""
_ipm_iters(eps::Float64, cones::Bool) = clamp((cones ? 2.5 : 4.0) + 0.9 * log10(1 / max(eps, 1e-16)), 4.0, 16.0)

"""
Estimated seconds of an IPM solve, of an ADMM iteration and of a factorization from the kernel's
estimates of one factorization `tf` and one solve `ts` and the vector work
`v = N + nnz(A) + nnz(P)` (relative least-squares fits of measured solves
of the benchmark families, n = 4 to 1024 fleets, random MPC, chains, reduced
programs, against the kernel's estimates, EPYC 7702, one thread):

    IPM   (k + 1) 0.85 tf + k (21 ts + 22e-9 v),   k = `_ipm_iters(eps, cones)`
          (a factorization per iteration and one for the starting point; three
          Newton systems per iteration with about 1.2 refinement steps each,
          every refinement a product with K; the cone scalings and step lengths;
          the solves of large factors run slower than the kernel's estimate,
          which the solve coefficient absorbs)
    ADMM  1.6 ts + 5e-10 v per iteration.
"""
function _ipm_cost_estimate(s)
    S = s.kkt
    N = size(S.K, 1)
    stats, eng = _factor_stats(S)
    tf = BlockLDL.estimate(BlockLDL.CostModel(factors = 1.0, solves = 0.0), stats, N, eng)
    ts = BlockLDL.estimate(BlockLDL.CostModel(factors = 0.0, solves = 1.0), stats, N, eng)
    v = N + nnz(s.A) + nnz(s.P)
    k = _ipm_iters(min(s.settings.eps_abs, s.settings.eps_rel), !isempty(s.socs))
    return (k + 1) * 0.85 * tf + k * (21 * ts + 22e-9 * v), 1.6 * ts + 5e-10 * v, tf
end

"""
Prior iteration count of a cold, polished ADMM solve with `m` rows. On the
benchmark families it grows slowly with the size: about 20 at m = 160, 55 at
2600, 80 at 10^4, 100 to 250 at 4 10^4 to 1.7 10^5 (grid couplings at the
top of the range).
"""
_admm_prior_iters(m::Int) = max(20.0, 12 * log2(m / 100))

"""
Whether a cold solve should start with the IPM: its estimated cost is below
that of an ADMM solve of `_admm_prior_iters` iterations and two
factorizations (a rho update and the polish). Large problems at loose
tolerances, where the IPM needs 5 or 6 iterations and ADMM over a hundred.
"""
function _ipm_first(s)
    c = s.cost
    (isfinite(c.t_ipm) && isfinite(c.t_admm_iter) && isfinite(c.t_factor)) || return false
    return c.t_ipm < _admm_prior_iters(s.m) * c.t_admm_iter + 2 * c.t_factor
end

_has_warm(s) = s.settings.warm_start && s.has_iterate

const PROBE_EVERY = 8

"""
`(method, budget)`: `:ipm`, or `:admm` with a budget of iterations after which
the solve crosses over to the IPM (`typemax(Int)`: none; 0: only the warm
polish).
"""
function _choose_method(s)
    st = s.settings
    st.method == :ipm && return :ipm, 0
    (st.method == :admm || s.m == 0) && return :admm, typemax(Int)
    st.method == :auto || throw(ArgumentError("unknown method $(st.method) (use :admm, :ipm or :auto)"))
    warm = _has_warm(s)
    if !warm && !isempty(s.socs) && min(st.eps_abs, st.eps_rel) <= st.ipm_eps_direct
        return :ipm, 0
    end
    !warm && !s.cost.prefer_ipm && _ipm_first(s) && return :ipm, 0
    c = s.cost
    if c.prefer_ipm
        c.since += 1
        c.since % PROBE_EVERY == 0 && return :admm, _admm_budget(s)       # probe: is ADMM fast again?
        return warm && st.polish && st.polish_warm ? (:admm, 0) : (:ipm, 0)
    end
    return :admm, _admm_budget(s)
end

function _admm_budget(s)
    st = s.settings
    (st.method != :auto || st.crossover <= 0 || !isfinite(s.cost.t_ipm) || !isfinite(s.cost.t_admm_iter)) && return typemax(Int)
    b = st.crossover * s.cost.t_ipm / s.cost.t_admm_iter
    return b >= typemax(Int) / 2 ? typemax(Int) : max(st.check_termination, ceil(Int, b))
end

"IPM solve of `s` (cold), the polish on its active set, the unscaled solution."
function _run_ipm!(s, t0::UInt64)
    st = s.settings
    info = s.info
    # the IPM system is built on first use; its construction is not part of
    # the IPM's cost (nor of the ADMM's: the ADMM time was taken before)
    s.ipm === nothing && (s.ipm = _ipm_work(s))
    t1 = time_ns()
    status = _ipm_solve!(s, t0)
    info.ipm_iter = s.ipm.iter
    s.has_iterate = true
    s.warm_pending = false
    if status == :solved_polished
        status = :solved
    elseif status == :solved && st.ipm_polish && st.polish && s.m > 0 && st.ipm_polish_final
        _guess_active!(s, s.z, s.y)
        _try_polish!(s; restart = false) || (info.polish = :failed)
    elseif status == :stalled || status == :max_iter
        # fallback: the active set of the last iterate (an exact solve when it
        # is right), then ADMM warm started from the iterate, with its polish
        status = :max_iter
        if st.polish && s.m > 0
            _guess_active!(s, s.z, s.y)
            _try_polish!(s; restart = false) && (status = :solved)
        end
        if status != :solved && st.method == :auto
            info.polish = :none
            status = _admm_solve!(s, t0, typemax(Int))
            info.method = :ipm_admm
            _finalize_cost!(s, t1)
            return status
        end
    end
    _finalize!(s, status)
    _finalize_cost!(s, t1)
    return status
end

function _finalize_cost!(s, t1::UInt64)
    dt = (time_ns() - t1) / 1e9
    c = s.cost
    c.t_ipm = isfinite(c.t_ipm) ? 0.5 * (c.t_ipm + dt) : dt
    c.ipm_runs += 1
    return nothing
end

"""
    solve!(solver) -> Info

Solve the problem: ADMM from the current iterate (a warm start if
`settings.warm_start` and there is one, zero otherwise) with the polish
described in `Settings`, the interior-point method, or ADMM crossing over to
the IPM, as `settings.method` says (method.jl). The unscaled solution is in
`solver.xsol`, `solver.ysol`, `solver.zsol`.
"""
function solve!(s::Solver)
    t0 = time_ns()
    info = s.info
    info.status = :unsolved
    info.iter = 0
    info.rho_updates = 0
    info.polish = :none
    info.polish_attempts = 0
    info.polish_factorizations = 0
    info.polish_iter = -1
    info.polish_time = 0.0
    info.gap = NaN
    info.ipm_iter = 0
    info.method = :none
    method, budget = _choose_method(s)
    if method == :admm
        status = _admm_solve!(s, t0, budget)
        if info.iter >= 50
            # refresh the cost of an iteration (polish time excluded)
            t = ((time_ns() - t0) / 1e9 - info.polish_time) / info.iter
            c = s.cost
            c.t_admm_iter = isfinite(c.t_admm_iter) ? 0.5 * (c.t_admm_iter + t) : t
        end
        c = s.cost
        if info.iter > 0 || status != :budget
            # the ADMM solve time (censored at twice the budget spent on a crossover)
            ta = (time_ns() - t0) / 1e9
            status == :budget && (ta *= 2)
            c.t_admm_solve = isfinite(c.t_admm_solve) ? 0.7 * c.t_admm_solve + 0.3 * ta : ta
            was = c.prefer_ipm
            if was && status != :budget && info.iter > 0
                # a probe that converged within its budget: ADMM works again
                c.prefer_ipm = false
                c.t_admm_solve = ta
                c.ncross = 0
            else
                c.ncross = status == :budget ? c.ncross + 1 : 0
                c.prefer_ipm = status == :budget && isfinite(c.t_ipm) ? (c.ncross >= 2 && c.t_admm_solve > c.t_ipm) :
                               (c.prefer_ipm && c.t_admm_solve > c.t_ipm)
            end
            c.prefer_ipm && !was && (c.since = 0)
        end
        if status == :budget
            method = info.iter == 0 ? :ipm : :admm_ipm
            info.polish = :none
            _run_ipm!(s, t0)
        end
    else
        _run_ipm!(s, t0)
    end
    info.method == :ipm_admm || (info.method = method)
    info.solve_time = (time_ns() - t0) / 1e9
    return info
end

# Compile the interior-point path while the package image is generated: it
# runs only on a crossover, and its first call would otherwise compile inside
# a timed solve (about a second on the grid fleet).
if ccall(:jl_generating_output, Cint, ()) == 1
    let
        P = sparse([2.0 0.5 0.0; 0.5 1.0 0.0; 0.0 0.0 1.0])
        A = sparse([1.0 1.0 1.0; 0.0 -1.0 0.0; 0.0 0.0 -1.0; 1.0 0.0 0.0])
        p = ConicQP(P, [1.0, -1.0, 0.5], A, [1.0, 0.0, 0.0, 2.0], [(:zero, 1), (:soc, 2), (:nonneg, 1)])
        for ls in (:qdldl, :cliquetrees, :blockldl, :auto), meth in (:ipm, :auto, :admm)
            try
                s = setup(p; linsys = ls, method = meth, eps_abs = 1e-8, eps_rel = 1e-8)
                solve!(s); update!(s; q = [1.0, -1.0, 0.4], c = 0.1); solve!(s)
                # every pair (ADMM backend, IPM backend) the IPM's choice can produce
                K = s.kkt.K; di = s.kkt.diag_idx; n = s.n
                for mk in (() -> _ipm_qdldl(copy(K), di, copy(di), n, nothing), () -> ChordalSystem(copy(K), di, n),
                           () -> _ipm_system(make_system(:blockldl, copy(K), di, n; settings = s.settings), copy(K), n))
                    s.ipm = _ipm_work(s; sys = mk())
                    reset!(s); _run_ipm!(s, time_ns())
                end
            catch
            end
        end
    end
end
