# single.jl: one QP at a time, on exactly the fleet QPs of the paper's
# centralized benchmark (bench/central/qp.jl): n agents, horizon N = 24, the
# pushforward along a blocking of the horizon into blocks of b instants, input
# constraints |u| <= ABAR per component (box) or ||u_t|| <= ABAR (soc).
#
#   BENCH_N=1,4,16,32,64 BENCH_B=1,8 BENCH_CONE=box julia --project=bench bench/single.jl
#
# Solvers (equal tolerances): SheafMPC (cold start: zero iterate, rho reset, no
# cached polish factorization; only the ordering, symbolic analysis and KKT
# factorization from setup are reused), OSQP (cold, polished, as the paper's
# run_julia.jl) and Clarabel at 1e-8. Timing: setup once; solve as min and
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

function run_sheafmpc(p; eps = EPS, kw...)
    s = setup(p; eps_abs = eps, eps_rel = eps, kw...)
    reset!(s); solve!(s)                                   # warm-up (compilation)
    ts = Float64[]; info = s.info
    for _ in 1:REPS
        reset!(s)
        info = solve!(s)
        push!(ts, info.solve_time)
    end
    return (obj = info.obj, x = copy(s.xsol), status = string(info.status), iters = info.iter, t_setup = info.setup_time,
            t = minimum(ts), tmed = median(ts), polish = string(info.polish), polish_attempts = info.polish_attempts,
            polish_factorizations = info.polish_factorizations, linsys = string(info.linsys), rho_updates = info.rho_updates)
end

function run_osqp(p; eps = EPS)
    P = SparseMatrixCSC(triu(p.P))
    m = OSQP.Model()
    t_setup = @elapsed OSQP.setup!(m; P = P, q = p.q, A = p.A, l = p.l, u = p.u, verbose = false, eps_abs = eps,
                                   eps_rel = eps, polish = true, warm_starting = false, max_iter = 400_000, adaptive_rho = true)
    r = OSQP.solve!(m)
    ts = Float64[]
    for _ in 1:REPS
        r = OSQP.solve!(m)
        push!(ts, r.info.solve_time)
    end
    return (obj = SheafMPC.objective(p, r.x) , x = r.x, status = string(r.info.status), iters = r.info.iter,
            t_setup = t_setup, t = minimum(ts), tmed = median(ts), polish = string(r.info.status_polish))
end

function main()
    rows = Dict{String,Any}[]
    @printf("%-5s %3s %3s %-9s %-8s %6s %10s %10s %10s %9s %9s  %s\n", "cone", "n", "b", "solver", "status", "iters",
            "setup ms", "min ms", "med ms", "rel gap", "viol", "notes")
    for n in NS
        pref = fleet_conic(blocked_qp(n, N, 1); cone = CONE)
        ref = clarabel_solve(pref; tol = 1e-10)
        for b in BS
            N % b == 0 || continue
            p = fleet_conic(blocked_qp(n, N, b); cone = CONE)
            res = Dict{String,Any}()
            res["sheafmpc"] = run_sheafmpc(p)
            CONE == "box" && (res["osqp"] = run_osqp(p))
            c = clarabel_solve(p; tol = 1e-8, reps = REPS)
            res["clarabel"] = (obj = c.obj, x = c.x, status = c.status, iters = c.iters, t_setup = NaN, t = c.t, tmed = c.tmed)
            for name in ("sheafmpc", "osqp", "clarabel")
                haskey(res, name) || continue
                r = res[name]
                gap = relgap(r.obj, ref.obj); viol = violation(p, r.x)
                note = name == "sheafmpc" ? @sprintf("polish %s (%d tries, %d fact.) %s rho+%d", r.polish, r.polish_attempts,
                                                     r.polish_factorizations, r.linsys, r.rho_updates) :
                       name == "osqp" ? "polish " * r.polish : ""
                @printf("%-5s %3d %3d %-9s %-8s %6d %10.3f %10.3f %10.3f %9.1e %9.1e  %s\n", CONE, n, b, name,
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
