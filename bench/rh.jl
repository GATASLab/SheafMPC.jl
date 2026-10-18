# rh.jl: receding horizon on the fleet QP (bench/central/qp.jl with a measured
# state and a moving clock, fleet.jl).
#
#   BENCH_N=1,4,16,32,64 BENCH_B=1 BENCH_CONE=box julia --project=bench bench/rh.jl
#
# The closed loop starts from the paper's QP (x0 = 0, t0 = 0.4) and runs STEPS
# steps of MPC: solve, apply every agent's first input to the plant, advance
# the clock by h. The state sequence is fixed once by a reference controller
# (Clarabel at 1e-10, untimed), so that every solver sees the same sequence of
# QPs; only q, the equality right-hand side and c change between steps (P and A
# are constant), which is what `update!` handles without refactoring.
#
# Per step, timed end to end (data update, warm start, solve):
#   sheafmpc         update!, warm_start_shifted! (the previous plan moved one
#                    step, last step repeated), solve! (warm polish first, the
#                    polish factorization cached across steps)
#   sheafmpc_cold    update!, reset!, solve! (no warm start)
#   osqp             OSQP.update! and solve! with OSQP's own warm start (the
#                    previous solution, unshifted)
#   osqp_shift       OSQP.update!, OSQP.warm_start! with the same shifted plan
#                    and multipliers, solve!
#   osqp_rho0.03     as osqp, with SheafMPC's default rho
#   clarabel         setup and solve at 1e-8 (solve timed)
# Reported: median and max per-step time over steps 1..STEPS-1 (step 0 is the
# first, cold solve after setup, reported separately), iterations, and the
# relative objective gap to the reference at every step (max over steps).

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "fleet.jl"))

ints(k, d) = parse.(Int, split(get(ENV, k, d), ","))
const NS = ints("BENCH_N", "1,4,16,32,64")
const BS = ints("BENCH_B", "1")
const CONE = get(ENV, "BENCH_CONE", "box")
const STEPS = parse(Int, get(ENV, "BENCH_STEPS", "30"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const N = 24
const T0 = 0.4

function reference_sequence(n, b)
    x0 = [zeros(4) for _ in 1:n]
    seq = []
    for k in 0:(STEPS-1)
        t0 = T0 + k * H
        Q = blocked_qp_x0(n, N, b; t0 = t0, x0 = x0)
        p = fleet_conic(Q; cone = CONE)
        r = clarabel_solve(p; tol = 1e-10)
        push!(seq, (Q = Q, p = p, ref = r.obj))
        x0 = plant_step(x0, first_inputs(Q, r.x))
    end
    return seq
end

stats(v) = (med = median(v), max = maximum(v), mean = mean(v))

function run_sheafmpc(seq, xmap, ymap; cold = false)
    p0 = seq[1].p
    s = setup(p0; eps_abs = EPS, eps_rel = EPS)
    solve!(s); reset!(s)                     # compile
    ts = Float64[]; its = Int[]; gaps = Float64[]; pol = Int[]; facs = Int[]
    for (k, st) in enumerate(seq)
        p = st.p
        t = @elapsed begin
            if CONE == "box"
                update!(s; q = p.q, l = p.l, u = p.u, c = p.c)
            else
                update!(s; q = p.q, b = p.socb .+ [p.kinds[i] == SheafMPC.ROW_EQ ? p.u[i] : 0.0 for i in 1:nrows(p)], c = p.c)
            end
            if cold || k == 1
                reset!(s)
            else
                warm_start_shifted!(s, xmap, ymap)
            end
            info = solve!(s)
        end
        obj = info.obj                       # update! sets the constant too
        push!(ts, t); push!(its, info.iter); push!(gaps, relgap(obj, st.ref))
        push!(pol, info.polish == :success ? (info.polish_iter == 0 ? 2 : 1) : 0); push!(facs, info.polish_factorizations)
    end
    return (; ts, its, gaps, pol, facs, setup = s.info.setup_time)
end

function run_osqp(seq, xmap, ymap; shift = false, rho = 0.1)
    p0 = seq[1].p
    mk() = (m = OSQP.Model(); OSQP.setup!(m; P = SparseMatrixCSC(triu(p0.P)), q = p0.q, A = p0.A, l = p0.l, u = p0.u,
                                          verbose = false, eps_abs = EPS, eps_rel = EPS, polish = true, warm_start = true,
                                          max_iter = 400_000, adaptive_rho = true, rho = rho); m)
    OSQP.solve!(mk())                        # compile
    m = nothing
    tsetup = @elapsed (m = mk())
    ts = Float64[]; its = Int[]; gaps = Float64[]; tin = Float64[]
    xprev = zeros(nvars(p0)); yprev = zeros(nrows(p0))
    for (k, st) in enumerate(seq)
        p = st.p
        local r
        t = @elapsed begin
            OSQP.update!(m; q = p.q, l = p.l, u = p.u)
            if shift && k > 1
                OSQP.warm_start!(m; x = [j == 0 ? 0.0 : xprev[j] for j in xmap], y = [i == 0 ? 0.0 : yprev[i] for i in ymap])
            end
            r = OSQP.solve!(m)
        end
        xprev = r.x; yprev = r.y
        push!(ts, t); push!(tin, r.info.solve_time); push!(its, r.info.iter)
        push!(gaps, relgap(SheafMPC.objective(p, r.x), st.ref))
    end
    return (; ts, its, gaps, tin, setup = tsetup)
end

function run_clarabel(seq)
    ts = Float64[]; its = Int[]; gaps = Float64[]
    for st in seq
        r = clarabel_solve(st.p; tol = 1e-8, reps = 1)
        push!(ts, r.t); push!(its, r.iters); push!(gaps, relgap(r.obj, st.ref))
    end
    return (; ts, its, gaps)
end

function main()
    rows = Dict{String,Any}[]
    @printf("%-4s %3s %2s %-14s %10s %10s %10s %8s %8s %9s  %s\n", "cone", "n", "b", "solver", "step0 ms", "med ms", "max ms",
            "med it", "max it", "max gap", "notes")
    for n in NS, b in BS
        seq = reference_sequence(n, b)
        @assert all(st.p.P == seq[1].p.P && st.p.A == seq[1].p.A for st in seq)
        xmap, ymap = shift_maps(seq[1].Q, CONE)
        res = Dict{String,Any}()
        # an untimed replay first: a path first taken mid-sequence (the polish
        # corrections, a crossover to the IPM) would otherwise time compilation
        run_sheafmpc(seq, xmap, ymap); run_sheafmpc(seq, xmap, ymap; cold = true)
        res["sheafmpc"] = run_sheafmpc(seq, xmap, ymap)
        res["sheafmpc_cold"] = run_sheafmpc(seq, xmap, ymap; cold = true)
        if CONE == "box"
            res["osqp"] = run_osqp(seq, xmap, ymap)
            res["osqp_shift"] = run_osqp(seq, xmap, ymap; shift = true)
            res["osqp_rho0.03"] = run_osqp(seq, xmap, ymap; rho = 0.03)
        end
        res["clarabel"] = run_clarabel(seq)
        for name in ("sheafmpc", "sheafmpc_cold", "osqp", "osqp_shift", "osqp_rho0.03", "clarabel")
            haskey(res, name) || continue
            r = res[name]
            w = 2:length(r.ts)
            st = stats(r.ts[w]); it = stats(r.its[w])
            note = name == "sheafmpc" ? @sprintf("warm polish at it 0: %d/%d steps, polish factorizations %d", count(==(2), r.pol[w]), length(w), sum(r.facs[w])) :
                   startswith(name, "osqp") ? @sprintf("internal solve med %.3f ms", 1e3 * median(r.tin[w])) : ""
            @printf("%-4s %3d %2d %-14s %10.3f %10.3f %10.3f %8.1f %8d %9.1e  %s\n", CONE, n, b, name, 1e3 * r.ts[1],
                    1e3 * st.med, 1e3 * st.max, it.med, Int(it.max), maximum(r.gaps), note)
            d = Dict{String,Any}("cone" => CONE, "n" => n, "N" => N, "b" => b, "solver" => name, "eps" => EPS, "steps" => STEPS,
                                 "t_step0" => r.ts[1], "t_med" => st.med, "t_max" => st.max, "t_mean" => st.mean,
                                 "it_med" => it.med, "it_max" => it.max, "max_gap" => maximum(r.gaps),
                                 "ts" => r.ts, "iters" => r.its, "gaps" => r.gaps)
            haskey(r, :pol) && (d["warm_polish_steps"] = count(==(2), r.pol[w]); d["polish_factorizations"] = sum(r.facs[w]))
            haskey(r, :tin) && (d["t_internal_med"] = median(r.tin[w]))
            push!(rows, d)
        end
        flush(stdout)
    end
    out = joinpath(@__DIR__, "results", "rh_$(CONE).json")
    open(io -> JSON.print(io, Dict("rows" => rows, "host" => gethostname(), "cpu" => Sys.cpu_info()[1].model), 1), out, "w")
    println("wrote ", out)
end

BLAS.set_num_threads(1)
check_fleet()
main()
