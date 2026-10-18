# kkt_e2e.jl: end-to-end ADMM solves of the fleet QPs with each linear system
# backend of SheafMPC, against OSQP.
#
#   julia --project=bench -t 8 bench/kkt_e2e.jl
#
# Single QPs (the protocol of bench/single.jl): setup once, then cold solves
# (reset! before each: zero iterate, rho reset, no cached polish factorization;
# the ordering, symbolic analysis and KKT factorization from setup are kept),
# min and median over REPS after a warm-up; accuracy against Clarabel at 1e-10.
# Receding horizon (the protocol of bench/rh.jl, ring fleet): STEPS steps of
# MPC with x0 propagated by the reference controller, update! + shifted warm
# start + solve! per step, timed end to end.
#
# Backends: :timed (the former default: times QDLDL with AMD/MMD/AMF and
# CliqueTrees in setup and keeps the fastest), :auto (engine and order from
# BlockLDL's cost model), :qdldl, :cliquetrees, :blockldl, and :auto with the
# agent/block labels as `kkt_structure`, on 1 and BENCH_E2E_THREADS threads.
# OSQP: cold, polished (single), warm shifted (receding horizon).
#
# Environment: BENCH_N (1,4,16,64,256), BENCH_GRAPHS (ring,grid), BENCH_B (1,24),
# BENCH_REPS (15), BENCH_EPS (1e-7), BENCH_STEPS (20), BENCH_E2E (single,rh),
# BENCH_E2E_THREADS (8), BENCH_TAG.

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "fleet.jl"))
include(joinpath(@__DIR__, "kkt_problems.jl"))

envl(k, d) = split(get(ENV, k, d), ",")
const NS = parse.(Int, envl("BENCH_N", "1,4,16,64,256"))
const GRAPHS = Symbol.(envl("BENCH_GRAPHS", "ring,grid"))
const BS = parse.(Int, envl("BENCH_B", "1,24"))
const REPS = parse(Int, get(ENV, "BENCH_REPS", "15"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const STEPS = parse(Int, get(ENV, "BENCH_STEPS", "20"))
const MODES = envl("BENCH_E2E", "single,rh")
const ET = parse(Int, get(ENV, "BENCH_E2E_THREADS", "8"))
const TAG = get(ENV, "BENCH_TAG", "")
const NH = 24

loadavg() = parse(Float64, split(read("/proc/loadavg", String))[1])

function backends(lab)
    st = (agent = lab.var_agent, block = lab.var_block)
    v = Any[("timed", (linsys = :timed,)), ("auto", (linsys = :auto,)), ("qdldl", (linsys = :qdldl,)),
            ("cliquetrees", (linsys = :cliquetrees,)), ("blockldl", (linsys = :blockldl, kkt_structure = st)),
            ("auto_struct", (linsys = :auto, kkt_structure = st))]
    ET > 1 && ET <= Threads.nthreads() &&
        push!(v, ("auto_t$(ET)", (linsys = :auto, kkt_structure = st, kkt_threads = ET)))
    return v
end

function run_backend(p, kw)
    tsetup = Float64[]
    s = nothing
    for _ in 1:3
        push!(tsetup, @elapsed(s = setup(p; eps_abs = EPS, eps_rel = EPS, kw...)))
    end
    reset!(s); solve!(s)
    ts = Float64[]; info = s.info
    for _ in 1:REPS
        reset!(s)
        info = solve!(s)
        push!(ts, info.solve_time)
    end
    return (obj = info.obj, x = copy(s.xsol), status = string(info.status), iters = info.iter, t_setup = minimum(tsetup),
            t = minimum(ts), tmed = median(ts), polish = string(info.polish), rho_updates = info.rho_updates,
            linsys = string(info.linsys), nnzL = SheafMPC.factor_nnz(s.kkt),
            ordering = s.kkt isa SheafMPC.BlockLDLSystem ? "blockldl " * string(s.kkt.ordering) : string(nameof(typeof(s.kkt))),
            polish_factorizations = info.polish_factorizations)
end

function run_osqp_single(p)
    P = SparseMatrixCSC(triu(p.P))
    m = OSQP.Model()
    t_setup = @elapsed OSQP.setup!(m; P = P, q = p.q, A = p.A, l = p.l, u = p.u, verbose = false, eps_abs = EPS,
                                   eps_rel = EPS, polish = true, warm_start = false, max_iter = 400_000, adaptive_rho = true)
    r = OSQP.solve!(m)
    ts = Float64[]
    for _ in 1:REPS
        r = OSQP.solve!(m)
        push!(ts, r.info.solve_time)
    end
    return (obj = SheafMPC.objective(p, r.x), x = r.x, status = string(r.info.status), iters = r.info.iter,
            t_setup = t_setup, t = minimum(ts), tmed = median(ts), polish = string(r.info.status_polish))
end

function single_mode(rows)
    @printf("%-5s %2s %5s %-14s %-8s %6s %10s %10s %10s %9s  %s\n", "graph", "b", "n", "backend", "status", "iters",
            "setup ms", "min ms", "med ms", "rel gap", "notes")
    for graph in GRAPHS, b in BS, n in NS
        graph == :grid && isqrt(n)^2 != n && continue
        qp, lab = fleet_problem(n, NH; graph = graph, b = b)
        ref = clarabel_solve(qp; tol = 1e-10)
        load0 = loadavg()
        res = Pair{String,Any}[]
        for (name, kw) in backends(lab)
            push!(res, name => run_backend(qp, kw))
        end
        push!(res, "osqp" => run_osqp_single(qp))
        for (name, r) in res
            gap = relgap(r.obj, ref.obj)
            note = haskey(r, :linsys) ? @sprintf("%s %s nnzL=%d polish %s rho+%d", r.linsys, r.ordering, r.nnzL,
                                                 r.polish, r.rho_updates) : "polish " * r.polish
            @printf("%-5s %2d %5d %-14s %-8s %6d %10.3f %10.3f %10.3f %9.1e  %s\n", graph, b, n, name, first(r.status, 8),
                    r.iters, 1e3 * r.t_setup, 1e3 * r.t, 1e3 * r.tmed, gap, note)
            d = Dict{String,Any}("mode" => "single", "graph" => string(graph), "b" => b, "n" => n, "N" => NH,
                                 "backend" => name, "eps" => EPS, "ref_obj" => ref.obj, "rel_gap" => gap,
                                 "vars" => nvars(qp), "rows" => nrows(qp), "load" => load0)
            for (k, v) in pairs(r)
                k == :x && continue
                d[string(k)] = v isa AbstractFloat && !isfinite(v) ? string(v) : v
            end
            push!(rows, d)
        end
        flush(stdout)
    end
end

# receding horizon: the sequence of rh.jl (ring fleet, x0 propagated by the reference)
function reference_sequence(n, b)
    x0 = [zeros(4) for _ in 1:n]
    seq = []
    for k in 0:(STEPS-1)
        t0 = 0.4 + k * H
        Q = blocked_qp_x0(n, NH, b; t0 = t0, x0 = x0)
        p = fleet_conic(Q; cone = "box")
        r = clarabel_solve(p; tol = 1e-10)
        push!(seq, (Q = Q, p = p, ref = r.obj))
        x0 = plant_step(x0, first_inputs(Q, r.x))
    end
    return seq
end

function rh_backend(seq, xmap, ymap, kw)
    p0 = seq[1].p
    s = setup(p0; eps_abs = EPS, eps_rel = EPS, kw...)
    solve!(s); reset!(s)
    ts = Float64[]; its = Int[]; gaps = Float64[]
    for (k, st) in enumerate(seq)
        p = st.p
        t = @elapsed begin
            update!(s; q = p.q, l = p.l, u = p.u)
            k == 1 ? reset!(s) : warm_start_shifted!(s, xmap, ymap)
            info = solve!(s)
        end
        push!(ts, t); push!(its, info.iter); push!(gaps, relgap(info.obj - p0.c + p.c, st.ref))
    end
    return (; ts, its, gaps)
end

function rh_osqp(seq, xmap, ymap)
    p0 = seq[1].p
    m = OSQP.Model()
    OSQP.setup!(m; P = SparseMatrixCSC(triu(p0.P)), q = p0.q, A = p0.A, l = p0.l, u = p0.u, verbose = false,
                eps_abs = EPS, eps_rel = EPS, polish = true, warm_start = true, max_iter = 400_000, adaptive_rho = true)
    OSQP.solve!(m)
    ts = Float64[]; its = Int[]; gaps = Float64[]
    xprev = zeros(nvars(p0)); yprev = zeros(nrows(p0))
    for (k, st) in enumerate(seq)
        p = st.p
        local r
        t = @elapsed begin
            OSQP.update!(m; q = p.q, l = p.l, u = p.u)
            k > 1 && OSQP.warm_start!(m; x = [j == 0 ? 0.0 : xprev[j] for j in xmap], y = [i == 0 ? 0.0 : yprev[i] for i in ymap])
            r = OSQP.solve!(m)
        end
        xprev = r.x; yprev = r.y
        push!(ts, t); push!(its, r.info.iter); push!(gaps, relgap(SheafMPC.objective(p, r.x), st.ref))
    end
    return (; ts, its, gaps)
end

function rh_mode(rows)
    @printf("%3s %5s %-14s %10s %10s %10s %8s %9s\n", "b", "n", "backend", "step0 ms", "med ms", "max ms", "med it",
            "max gap")
    for b in filter(x -> x == 1 || x == NH, BS), n in NS
        seq = reference_sequence(n, b)
        xmap, ymap = shift_maps(seq[1].Q, "box")
        _, lab = fleet_problem(n, NH; graph = :ring, b = b)
        res = Pair{String,Any}[]
        for (name, kw) in backends(lab)
            push!(res, name => rh_backend(seq, xmap, ymap, kw))
        end
        push!(res, "osqp_shift" => rh_osqp(seq, xmap, ymap))
        for (name, r) in res
            w = 2:length(r.ts)
            @printf("%3d %5d %-14s %10.3f %10.3f %10.3f %8.1f %9.1e\n", b, n, name, 1e3 * r.ts[1], 1e3 * median(r.ts[w]),
                    1e3 * maximum(r.ts[w]), median(r.its[w]), maximum(r.gaps))
            push!(rows, Dict{String,Any}("mode" => "rh", "graph" => "ring", "b" => b, "n" => n, "backend" => name,
                                         "steps" => STEPS, "t_step0" => r.ts[1], "t_med" => median(r.ts[w]),
                                         "t_max" => maximum(r.ts[w]), "it_med" => median(r.its[w]),
                                         "max_gap" => maximum(r.gaps), "ts" => r.ts, "iters" => r.its, "load" => loadavg()))
        end
        flush(stdout)
    end
end

function main()
    BLAS.set_num_threads(1)
    @printf("host %s, %s, %d threads, load %.1f\n", gethostname(), Sys.cpu_info()[1].model, Threads.nthreads(), loadavg())
    rows = Dict{String,Any}[]
    "single" in MODES && single_mode(rows)
    "rh" in MODES && rh_mode(rows)
    out = joinpath(@__DIR__, "results", "kkt_e2e" * (isempty(TAG) ? "" : "_" * TAG) * ".json")
    open(io -> JSON.print(io, Dict("rows" => rows, "host" => gethostname(), "cpu" => Sys.cpu_info()[1].model,
                                   "threads" => Threads.nthreads()), 1), out, "w")
    println("wrote ", out)
end

main()
