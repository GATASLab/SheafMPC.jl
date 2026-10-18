# rh_compare.jl: receding horizon on the fleet QP, solvers interleaved step by
# step, for before/after measurements.
#
#   BENCH_N=1,4,16,64 BENCH_CONE=box BENCH_WARMUP=0 BENCH_STEPS=30 BENCH_REPLAYS=3 \
#   SHEAF_VARIANTS='base:' julia --project=bench bench/rh_compare.jl
#
# The QP sequence is fixed by a reference closed loop (Clarabel at 1e-10,
# untimed; fleet.jl), so every solver sees the same QPs. BENCH_WARMUP steps of
# that closed loop run first and are not recorded: WARMUP = 0 is the
# accelerate-from-rest scenario of rh.jl (the fleet starts at rest, x0 = 0,
# and the active set moves every step); a WARMUP of a few dozen steps starts
# the recorded window closer to steady tracking.
#
# Per replay, every solver is set up on the first QP; then, step by step, each
# solver in turn runs its timed step (data update, warm start, solve). The
# time of a step is the minimum over BENCH_REPLAYS replays. Reported: step 1
# (the first, cold, solve after setup), and median and max over steps 2..S;
# iterations; the largest relative objective gap to the reference and the
# largest constraint violation over all steps (`ok` when both within TARGET).
#
#   sheafmpc:<v>       update!, warm_start_shifted! (the previous plan moved one
#                      stage), solve!
#   sheafmpc_cold:<v>  update!, reset!, solve!
#   osqp_warm          OSQP 0.6, update! and solve! from its own previous
#                      solution (warm_start = true; OSQP's default)
#   osqp_shift         the same with warm_start! from the shifted previous plan
#   osqp_cold          warm_start = false
#   clarabel           a solver built per step (untimed), solve! timed, 1e-8

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "fleet.jl"))

ints(k, d) = parse.(Int, split(get(ENV, k, d), ","))
const NS = ints("BENCH_N", "1,4,16,64")
const CONE = get(ENV, "BENCH_CONE", "box")
const STEPS = parse(Int, get(ENV, "BENCH_STEPS", "30"))
const WARMUP = parse(Int, get(ENV, "BENCH_WARMUP", "0"))
const REPLAYS = parse(Int, get(ENV, "BENCH_REPLAYS", "3"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const TARGET = parse(Float64, get(ENV, "BENCH_TARGET", "1e-6"))
const COLD = get(ENV, "BENCH_COLD", "1") == "1"
const N = 24
const T0 = 0.4
include(joinpath(@__DIR__, "variants_parse.jl"))
const VARIANTS = parse_variants(get(ENV, "SHEAF_VARIANTS", "base:"))

function reference_sequence(n)
    x0 = [zeros(4) for _ in 1:n]
    seq = []
    for k in 0:(WARMUP + STEPS - 1)
        t0 = T0 + k * H
        Q = blocked_qp_x0(n, N, 1; t0 = t0, x0 = x0)
        p = fleet_conic(Q; cone = CONE)
        r = clarabel_solve(p; tol = 1e-10)
        k >= WARMUP && push!(seq, (Q = Q, p = p, ref = r.obj))
        x0 = plant_step(x0, first_inputs(Q, r.x))
    end
    return seq
end

rhs_b(p) = p.socb .+ [p.kinds[i] == SheafMPC.ROW_EQ ? p.u[i] : 0.0 for i in 1:nrows(p)]

mutable struct RHEntry
    name::String
    make::Function            # () -> handle
    step::Function            # (handle, k, p) -> (obj, x, iters, note)
    ts::Matrix{Float64}       # replays x steps
    its::Vector{Int}
    gaps::Vector{Float64}
    viols::Vector{Float64}
    notes::Vector{String}
end
RHEntry(name, make, step) = RHEntry(name, make, step, fill(Inf, REPLAYS, STEPS), zeros(Int, STEPS), zeros(STEPS),
                                    zeros(STEPS), fill("", STEPS))

function sheaf_entry(p0, xmap, ymap, name, kw; cold = false)
    make = () -> setup(p0; eps_abs = EPS, eps_rel = EPS, kw...)
    step = (s, k, p) -> begin
        if CONE == "box"
            update!(s; q = p.q, l = p.l, u = p.u)
        else
            update!(s; q = p.q, b = rhs_b(p))
        end
        (cold || k == 1) ? reset!(s) : warm_start_shifted!(s, xmap, ymap)
        info = solve!(s)
        (info.obj - p0.c + p.c, s.xsol, info.iter,
         @sprintf("%s%d/%d", info.polish == :success ? (info.polish_iter == 0 ? "W" : "P") : "-", info.polish_attempts,
                  info.polish_factorizations + info.rho_updates))
    end
    return RHEntry((cold ? "sheafmpc_cold:" : "sheafmpc:") * name, make, step)
end

function osqp_entry(p0, xmap, ymap, mode)
    make = () -> begin
        m = OSQP.Model()
        OSQP.setup!(m; P = SparseMatrixCSC(triu(p0.P)), q = p0.q, A = p0.A, l = p0.l, u = p0.u, verbose = false,
                    eps_abs = EPS, eps_rel = EPS, polish = true, warm_start = mode != :cold, max_iter = 400_000,
                    adaptive_rho = true)
        ws = unsafe_load(unsafe_load(m.workspace).settings)
        @assert ws.warm_start == (mode != :cold ? 1 : 0)
        (m, OSQP.Results(), Ref(zeros(nvars(p0))), Ref(zeros(nrows(p0))))
    end
    step = (h, k, p) -> begin
        m, r, xp, yp = h
        OSQP.update!(m; q = p.q, l = p.l, u = p.u)
        if mode == :shift && k > 1
            OSQP.warm_start!(m; x = [j == 0 ? 0.0 : xp[][j] for j in xmap], y = [i == 0 ? 0.0 : yp[][i] for i in ymap])
        end
        OSQP.solve!(m, r)
        xp[] = copy(r.x); yp[] = copy(r.y)
        (SheafMPC.objective(p, r.x), r.x, r.info.iter, "")
    end
    return RHEntry("osqp_" * string(mode), make, step)
end

function clarabel_entry()
    make = () -> nothing
    step = (h, k, p) -> error("timed separately")
    return RHEntry("clarabel", make, step)
end

function main()
    println("load before: ", strip(read(`uptime`, String)), "  warmup $WARMUP steps $STEPS replays $REPLAYS cone $CONE")
    @printf("%-4s %3s %-24s %9s %9s %9s %7s %7s %8s %8s %3s  %s\n", "cone", "n", "solver", "step1 ms", "med ms",
            "max ms", "med it", "max it", "max gap", "max viol", "ok", "per-step polish (W warm, P iterated) / fact.")
    for n in NS
        seq = reference_sequence(n)
        p0 = seq[1].p
        xmap, ymap = shift_maps(seq[1].Q, CONE)
        es = RHEntry[]
        for (name, kw) in VARIANTS
            push!(es, sheaf_entry(p0, xmap, ymap, name, kw))
            COLD && push!(es, sheaf_entry(p0, xmap, ymap, name, kw; cold = true))
        end
        if CONE == "box"
            for mode in (:warm, :shift, :cold)
                push!(es, osqp_entry(p0, xmap, ymap, mode))
            end
        end
        cl = clarabel_entry()
        # compile
        for e in es
            h = e.make(); e.step(h, 1, p0); e.step(h, 2, seq[min(2, end)].p)
        end
        clarabel_solve(p0; tol = 1e-8, reps = 1)
        for rep in 1:REPLAYS
            hs = [e.make() for e in es]
            for (k, st) in enumerate(seq)
                for (j, e) in enumerate(es)
                    GC.gc(false)
                    t0 = time_ns()
                    obj, x, it, note = e.step(hs[j], k, st.p)
                    e.ts[rep, k] = min(e.ts[rep, k], (time_ns() - t0) / 1e9)
                    if rep == 1
                        e.its[k] = it; e.gaps[k] = relgap(obj, st.ref); e.viols[k] = violation(st.p, x); e.notes[k] = note
                    end
                end
                s = clarabel_setup(st.p; tol = 1e-8)
                GC.gc(false)
                t0 = time_ns()
                r = Clarabel.solve!(s)
                cl.ts[rep, k] = (time_ns() - t0) / 1e9
                if rep == 1
                    cl.its[k] = r.iterations; cl.gaps[k] = relgap(SheafMPC.objective(st.p, r.x), st.ref)
                    cl.viols[k] = violation(st.p, r.x)
                end
            end
        end
        for e in [es; cl]
            t = vec(minimum(e.ts; dims = 1))
            w = 2:STEPS
            ok = maximum(e.gaps) <= TARGET && maximum(e.viols) <= TARGET
            @printf("%-4s %3d %-24s %9.3f %9.3f %9.3f %7.1f %7d %8.1e %8.1e %3s  %s\n", CONE, n, e.name, 1e3 * t[1],
                    1e3 * median(t[w]), 1e3 * maximum(t[w]), median(e.its[w]), maximum(e.its[w]), maximum(e.gaps),
                    maximum(e.viols), ok ? "yes" : "NO", join(e.notes[w], " ")[1:min(end, 120)])
        end
        flush(stdout)
    end
    println("load after: ", strip(read(`uptime`, String)))
end

BLAS.set_num_threads(1)
check_fleet()
main()
