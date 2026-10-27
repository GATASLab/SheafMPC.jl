# compare.jl: single solves, interleaved, for before/after measurements.
#
#   BENCH_N=1,4,16,64 BENCH_CONE=box,soc BENCH_B=1 BENCH_REPS=21 \
#   SHEAF_VARIANTS='base:;nopol:polish=false' julia --project=bench bench/compare.jl
#
# Every solver is set up once per problem; then REPS rounds, each one timed
# cold solve of every solver in turn (interleaved, so that load drifts hit all
# of them alike). Setup is timed the same way (SETUP_REPS rounds). Clocks are
# time_ns around the call. Reported: min and median.
#
# Solvers:
#   sheafmpc:<variant>  reset! then solve! (cold), settings from SHEAF_VARIANTS
#   osqp_cold           OSQP 0.6 with warm_start = false (zero start each solve;
#                       rho as left by the previous solve, as OSQP does), polish on
#   osqp_warm           warm_start = true: every solve starts from the previous
#                       solution of the same QP (the paper's setting)
#   clarabel            interior point, 1e-8, setup kept
# Accuracy against Clarabel at 1e-10 on the same QP: relative objective gap and
# constraint violation; `ok` when both are within TARGET (default 1e-6).

include(joinpath(@__DIR__, "common.jl"))

ints(k, d) = parse.(Int, split(get(ENV, k, d), ","))
const NS = ints("BENCH_N", "1,4,16,64")
const BS = ints("BENCH_B", "1")
const CONES = split(get(ENV, "BENCH_CONE", "box,soc"), ",")
const REPS = parse(Int, get(ENV, "BENCH_REPS", "21"))
const SETUP_REPS = parse(Int, get(ENV, "BENCH_SETUP_REPS", "7"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const TARGET = parse(Float64, get(ENV, "BENCH_TARGET", "1e-6"))
const N = 24

include(joinpath(@__DIR__, "variants_parse.jl"))
const VARIANTS = parse_variants(get(ENV, "SHEAF_VARIANTS", "base:"))

timed(f) = (t = time_ns(); r = f(); ((time_ns() - t) / 1e9, r))

mutable struct Entry
    name::String
    setup::Function          # () -> handle
    solve::Function          # handle -> (obj, x, status, iters, note)
    h::Any
    ts::Vector{Float64}
    tsetup::Vector{Float64}
    last::Any
end

function sheaf_entry(p, name, kw)
    setupf = () -> setup(p; eps_abs = EPS, eps_rel = EPS, kw...)
    solvef = s -> begin
        reset!(s)
        info = solve!(s)
        (info.obj, s.xsol, string(info.status), info.iter,
         @sprintf("pol %s %d/%d rho+%d %s", info.polish, info.polish_attempts, info.polish_factorizations, info.rho_updates, info.linsys))
    end
    return Entry("sheafmpc:" * name, setupf, solvef, nothing, Float64[], Float64[], nothing)
end

function osqp_entry(p, warm)
    P = SparseMatrixCSC(triu(p.P))
    setupf = () -> begin
        m = OSQP.Model()
        OSQP.setup!(m; P = P, q = p.q, A = p.A, l = p.l, u = p.u, verbose = false, eps_abs = EPS, eps_rel = EPS,
                    polish = true, max_iter = 400_000, adaptive_rho = true, warm_start = warm)
        (m, OSQP.Results())
    end
    solvef = h -> begin
        m, r = h
        OSQP.solve!(m, r)
        (SheafMPC.objective(p, r.x), r.x, string(r.info.status), r.info.iter, @sprintf("pol %d", r.info.status_polish))
    end
    return Entry(warm ? "osqp_warm" : "osqp_cold", setupf, solvef, nothing, Float64[], Float64[], nothing)
end

# check that the OSQP settings took effect (OSQP.jl ignores unknown keywords)
function osqp_settings(m::OSQP.Model)
    ws = unsafe_load(m.workspace)
    st = unsafe_load(ws.settings)
    return (warm_start = st.warm_start, eps_abs = st.eps_abs, eps_rel = st.eps_rel, polish = st.polish,
            adaptive_rho = st.adaptive_rho, rho = st.rho)
end

function clarabel_entry(p)
    setupf = () -> clarabel_setup(p; tol = 1e-8)
    solvef = s -> begin
        r = Clarabel.solve!(s)
        (SheafMPC.objective(p, r.x), r.x, string(r.status), r.iterations, "")
    end
    return Entry("clarabel", setupf, solvef, nothing, Float64[], Float64[], nothing)
end

function main()
    println("load before: ", strip(read(`uptime`, String)))
    @printf("%-4s %3s %2s %-22s %8s %8s %6s %9s %9s %9s %8s %8s %3s  %s\n", "cone", "n", "b", "solver", "setup", "setup",
            "iters", "min ms", "med ms", "max ms", "gap", "viol", "ok", "notes")
    @printf("%-4s %3s %2s %-22s %8s %8s\n", "", "", "", "", "min ms", "med ms")
    rows = Dict{String,Any}[]
    for cone in CONES, n in NS, b in BS
        N % b == 0 || continue
        p = fleet_conic(blocked_qp(n, N, b); cone = String(cone))
        ref = clarabel_solve(p; tol = 1e-10)
        es = Entry[]
        for (name, kw) in VARIANTS
            push!(es, sheaf_entry(p, name, kw))
        end
        if cone == "box"
            push!(es, osqp_entry(p, false)); push!(es, osqp_entry(p, true))
        end
        push!(es, clarabel_entry(p))
        for e in es                                  # compile, then interleaved setup timing
            e.h = e.setup(); e.solve(e.h)
        end
        for e in es
            e.name == "osqp_cold" && @assert osqp_settings(e.h[1]).warm_start == 0
            e.name == "osqp_warm" && @assert osqp_settings(e.h[1]).warm_start == 1
        end
        for _ in 1:SETUP_REPS, e in es
            GC.gc(false)
            t, h = timed(e.setup)
            push!(e.tsetup, t)
            e.h = h
        end
        for e in es
            e.solve(e.h)                             # warm-up of the kept handle
        end
        for _ in 1:REPS, e in es
            GC.gc(false)
            t, r = timed(() -> e.solve(e.h))
            push!(e.ts, t); e.last = r
        end
        for e in es
            obj, x, status, iters, note = e.last
            gap = relgap(obj, ref.obj); viol = violation(p, x)
            ok = gap <= TARGET && viol <= TARGET
            su = isempty(e.tsetup) ? (NaN, NaN) : (minimum(e.tsetup), median(e.tsetup))
            @printf("%-4s %3d %2d %-22s %8.3f %8.3f %6d %9.3f %9.3f %9.3f %8.1e %8.1e %3s  %s\n", cone, n, b, e.name,
                    1e3 * su[1], 1e3 * su[2], iters, 1e3 * minimum(e.ts), 1e3 * median(e.ts), 1e3 * maximum(e.ts), gap, viol,
                    ok ? "yes" : "NO", note)
            push!(rows, Dict{String,Any}("cone" => cone, "n" => n, "b" => b, "solver" => e.name, "setup_min" => su[1],
                                         "setup_med" => su[2], "iters" => iters, "t_min" => minimum(e.ts),
                                         "t_med" => median(e.ts), "gap" => gap, "viol" => viol, "ok" => ok, "note" => note))
        end
        flush(stdout)
    end
    println("load after: ", strip(read(`uptime`, String)))
    out = get(ENV, "BENCH_OUT", "")
    isempty(out) || open(io -> JSON.print(io, Dict("rows" => rows, "variants" => string(VARIANTS)), 1), out, "w")
end

BLAS.set_num_threads(1)
main()
