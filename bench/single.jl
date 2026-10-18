# single.jl: one QP at a time, on exactly the fleet QPs of the paper's
# centralized benchmark (bench/central/qp.jl): n agents, horizon N = 24, the
# pushforward along a blocking of the horizon into blocks of b instants, input
# constraints |u| <= ABAR per component (box) or ||u_t|| <= ABAR (soc).
#
#   BENCH_N=1,4,16,32,64 BENCH_B=1,8 BENCH_CONE=box julia --project=bench bench/single.jl
#
# Solvers (equal tolerances eps_abs = eps_rel = EPS, polishing on):
#   sheafmpc          cold start: zero iterate, rho reset, no cached polish
#                     factorization; only the ordering, symbolic analysis and
#                     KKT factorization from setup are reused
#   sheafmpc_resolve  the same QP solved again from the previous solution
#   osqp              cold start (warm_start = false), default rho 0.1
#   osqp_rho0.03      cold start with SheafMPC's default rho
#   osqp_nopolish     cold, no polish (its per-iteration cost)
#   osqp_paper        the settings of the paper's run_julia.jl, which in effect
#                     re-solve from the previous solution (see run_osqp)
#   clarabel          interior point at 1e-8 Timing: setup once; solve as min and
# median over REPS repeats after a warm-up. Accuracy: the objective against a
# Clarabel solve of the time-expanded program (b = 1) at 1e-10, untimed.

include(joinpath(@__DIR__, "common.jl"))

ints(k, d) = parse.(Int, split(get(ENV, k, d), ","))
const NS = ints("BENCH_N", "1,4,16,32,64")
const BS = ints("BENCH_B", "1,8")
const CONE = get(ENV, "BENCH_CONE", "box")
const REPS = parse(Int, get(ENV, "BENCH_REPS", "15"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const N = 24

function run_sheafmpc(p; eps = EPS, resolve = false, kw...)
    s = setup(p; eps_abs = eps, eps_rel = eps, kw...)
    # per-iteration and per-factorization costs (min over repeats)
    SheafMPC.admm_step!(s)
    t_iter = minimum(@elapsed(SheafMPC.admm_step!(s)) for _ in 1:30)
    t_fact = minimum(@elapsed(SheafMPC.refactor!(s.pol)) for _ in 1:5)
    reset!(s); solve!(s)                                   # warm-up (compilation)
    ts = Float64[]; info = s.info
    for _ in 1:REPS
        resolve || reset!(s)                               # resolve: start from the previous solution
        info = solve!(s)
        push!(ts, info.solve_time)
    end
    return (obj = info.obj, x = copy(s.xsol), status = string(info.status), iters = info.iter, t_setup = info.setup_time,
            t = minimum(ts), tmed = median(ts), polish = string(info.polish), polish_attempts = info.polish_attempts,
            polish_factorizations = info.polish_factorizations, linsys = string(info.linsys), rho_updates = info.rho_updates,
            t_iter = t_iter, t_fact = t_fact, nnz_L = SheafMPC.factor_nnz(s.kkt))
end

# OSQP 0.6.2 through OSQP.jl. `warm_start = false`: a cold start every solve
# (rho as left by the previous solve, as OSQP does). `paper = true`: the
# settings of the paper's bench/central/run_julia.jl, whose `warm_starting =
# false` is not an OSQP option and is ignored, so OSQP's default warm start is
# on and every timed solve starts from the previous solve's solution.
function run_osqp(p; eps = EPS, paper = false, rho = 0.1, polish = true)
    P = SparseMatrixCSC(triu(p.P))
    m = OSQP.Model()
    kw = paper ? (warm_starting = false,) : (warm_start = false,)
    t_setup = @elapsed OSQP.setup!(m; P = P, q = p.q, A = p.A, l = p.l, u = p.u, verbose = false, eps_abs = eps,
                                   eps_rel = eps, polish = polish, max_iter = 400_000, adaptive_rho = true, rho = rho, kw...)
    r = OSQP.solve!(m)
    ts = Float64[]
    for _ in 1:REPS
        r = OSQP.solve!(m)
        push!(ts, r.info.solve_time)
    end
    return (obj = SheafMPC.objective(p, r.x), x = r.x, status = string(r.info.status), iters = r.info.iter,
            t_setup = t_setup, t = minimum(ts), tmed = median(ts), polish = string(r.info.status_polish),
            t_iter = r.info.solve_time / max(r.info.iter, 1))
end

function main()
    rows = Dict{String,Any}[]
    @printf("%-5s %3s %3s %-16s %-8s %6s %10s %10s %10s %9s %9s  %s\n", "cone", "n", "b", "solver", "status", "iters",
            "setup ms", "min ms", "med ms", "rel gap", "viol", "notes")
    for n in NS
        pref = fleet_conic(blocked_qp(n, N, 1); cone = CONE)
        ref = clarabel_solve(pref; tol = 1e-10)
        for b in BS
            N % b == 0 || continue
            p = fleet_conic(blocked_qp(n, N, b); cone = CONE)
            res = Dict{String,Any}()
            res["sheafmpc"] = run_sheafmpc(p)
            res["sheafmpc_resolve"] = run_sheafmpc(p; resolve = true)
            if CONE == "box"
                res["osqp"] = run_osqp(p)
                res["osqp_rho0.03"] = run_osqp(p; rho = 0.03)
                res["osqp_nopolish"] = run_osqp(p; polish = false)
                res["osqp_paper"] = run_osqp(p; paper = true)
            end
            c = clarabel_solve(p; tol = 1e-8, reps = REPS)
            res["clarabel"] = (obj = c.obj, x = c.x, status = c.status, iters = c.iters, t_setup = NaN, t = c.t, tmed = c.tmed)
            for name in ("sheafmpc", "sheafmpc_resolve", "osqp", "osqp_rho0.03", "osqp_nopolish", "osqp_paper", "clarabel")
                haskey(res, name) || continue
                r = res[name]
                gap = relgap(r.obj, ref.obj); viol = violation(p, r.x)
                note = startswith(name, "sheafmpc") ? @sprintf("polish %s (%d tries, %d fact.) %s rho+%d, it %.1f us, fact %.0f us, nnzL %d",
                                                     r.polish, r.polish_attempts, r.polish_factorizations, r.linsys, r.rho_updates,
                                                     1e6 * r.t_iter, 1e6 * r.t_fact, r.nnz_L) :
                       startswith(name, "osqp") ? @sprintf("polish %s, %.1f us/it", r.polish, 1e6 * r.t_iter) : ""
                @printf("%-5s %3d %3d %-16s %-8s %6d %10.3f %10.3f %10.3f %9.1e %9.1e  %s\n", CONE, n, b, name,
                        first(r.status, 8), r.iters, 1e3 * r.t_setup, 1e3 * r.t, 1e3 * r.tmed, gap, viol, note)
                d = Dict{String,Any}("cone" => CONE, "n" => n, "N" => N, "b" => b, "solver" => name, "eps" => EPS,
                                     "abar" => ABAR, "ref_obj" => ref.obj, "ref_status" => ref.status, "rel_gap" => gap,
                                     "viol" => viol, "vars" => nvars(p), "rows" => nrows(p))
                for (k, v) in pairs(r)
                    k == :x && continue
                    d[string(k)] = v isa AbstractFloat && !isfinite(v) ? string(v) : v
                end
                push!(rows, d)
            end
            flush(stdout)
        end
    end
    out = joinpath(@__DIR__, "results", "single_$(CONE).json")
    open(io -> JSON.print(io, Dict("rows" => rows, "host" => gethostname(), "cpu" => Sys.cpu_info()[1].model,
                                   "threads" => Threads.nthreads()), 1), out, "w")
    println("wrote ", out)
end

BLAS.set_num_threads(1)
main()
