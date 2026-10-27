# kkt.jl: the KKT kernel benchmark: BlockLDL against OSQP's QDLDL (C),
# QDLDL.jl (Clarabel's default), CliqueTrees' ChordalLDLt and a Riccati
# recursion, on the ADMM KKT matrices of multi-agent MPC programs.
#
#   julia --project=bench -t 8 bench/kkt.jl
#
# Environment:
#   BENCH_KKT_SET     fleet,reduced,threads,lowrank (any subset; default all)
#   BENCH_N           agent counts of the fleet set (default 1,4,16,64,256,1024)
#   BENCH_GRAPHS      ring,grid
#   BENCH_FORMS       expanded,condensed (b = 1 and b = N)
#   BENCH_DYN         di (planar double integrator) or quad (12 + 4)
#   BENCH_RICCATI_MAX largest n for the Riccati recursion (default 256)
#   BENCH_THREADS     thread counts of the threads set (default 1,2,4,8)
#   BENCH_BUDGET      seconds of repeats per measurement (default 0.5)
#   BENCH_TAG         suffix of the result file
#   BENCH_RELAX       supernode relaxation: exact, light (default), cholmod
#
# Every measurement: one warm-up, then repeats until BENCH_BUDGET seconds (at
# least 5, at most 2000); min and median. The load average is recorded before
# every case. Factorization times are numeric refactorizations on the analysed
# pattern (the operation of a rho update); symbolic times include the ordering.
# nnz(L) counts the unit diagonal for every kernel.

using SheafMPC, SparseArrays, LinearAlgebra, Printf, Statistics, JSON
import QDLDL, CliqueTrees
try
    @eval import Metis
catch
end
const BL = SheafMPC.BlockLDL
include(joinpath(@__DIR__, "kkt_problems.jl"))
include(joinpath(@__DIR__, "kkt_baselines.jl"))

envlist(k, d) = split(get(ENV, k, d), ",")
const SETS = envlist("BENCH_KKT_SET", "fleet,reduced,threads,lowrank")
const NS = parse.(Int, envlist("BENCH_N", "1,4,16,64,256,1024"))
const GRAPHS = Symbol.(envlist("BENCH_GRAPHS", "ring,grid"))
const FORMS = envlist("BENCH_FORMS", "expanded,condensed")
const DYN = Symbol(get(ENV, "BENCH_DYN", "di"))
const RICCATI_MAX = parse(Int, get(ENV, "BENCH_RICCATI_MAX", "256"))
const THREADS = parse.(Int, envlist("BENCH_THREADS", "1,2,4,8"))
const BUDGET = parse(Float64, get(ENV, "BENCH_BUDGET", "0.5"))
const TAG = get(ENV, "BENCH_TAG", "")
# supernode relaxation of BlockLDL: exact, light (the package default) or cholmod
const RELAX = Dict("exact" => BL.EXACT, "light" => BL.LIGHT, "cholmod" => BL.Relax())[get(ENV, "BENCH_RELAX", "light")]
const HN = 24
const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))
"reduced" in SETS && include(joinpath(PAPER, "scripts", "resolution", "experiments", "common_spatial.jl"))

loadavg() = (s = read("/proc/loadavg", String); parse(Float64, split(s)[1]))

"min and median seconds of f() over repeats (after one warm-up)."
function timeit(f; budget = BUDGET, minreps = 5, maxreps = 2000)
    f()
    ts = Float64[]
    t0 = time()
    while length(ts) < maxreps && (length(ts) < minreps || time() - t0 < budget)
        push!(ts, @elapsed f())
    end
    return (min = minimum(ts), med = median(ts), reps = length(ts))
end

kkt_signs(N, n) = [i <= n ? 1.0 : -1.0 for i in 1:N]

relres(K, x, b) = (r = similar(b); BL.symv_upper!(r, K, x); norm(r - b, Inf) / norm(b, Inf))

"All kernels on one KKT matrix; returns a Dict per kernel."
function bench_kkt(K::SparseMatrixCSC, n::Int; structure = nothing, riccati = nothing, label = "")
    N = size(K, 1)
    b = randn(N); x = similar(b)
    out = Dict{String,Any}()
    # OSQP's QDLDL (C)
    ts = @elapsed C = CQDLDL(K)
    factor!(C)
    tf = timeit(() -> factor!(C))
    tso = timeit(() -> (copyto!(x, b); solve!(C, x)))
    out["osqp_qdldl"] = Dict("symbolic" => ts, "factor" => tf.min, "factor_med" => tf.med, "solve" => tso.min,
                             "solve_med" => tso.med, "nnzL" => cqdldl_nnz(C), "res" => relres(K, x, b))
    # QDLDL.jl
    ts = @elapsed Q = SheafMPC.make_system(:qdldl, copy(K), collect(1:N), n)
    tf = timeit(() -> SheafMPC.refactor!(Q))
    tso = timeit(() -> (copyto!(x, b); SheafMPC.solve!(Q, x)))
    out["qdldl_jl"] = Dict("symbolic" => ts, "factor" => tf.min, "factor_med" => tf.med, "solve" => tso.min,
                           "solve_med" => tso.med, "nnzL" => SheafMPC.factor_nnz(Q) + N, "res" => relres(K, x, b))
    # CliqueTrees ChordalLDLt (AMF), and METIS when loaded
    for (nm, alg) in (("cliquetrees", nothing), ("cliquetrees_metis", :metis))
        alg === :metis && Base.get_extension(CliqueTrees, :MetisExt) === nothing && continue
        ts = @elapsed Ct = alg === nothing ? SheafMPC.make_system(:cliquetrees, copy(K), collect(1:N), n) :
                           SheafMPC.ChordalSystem(copy(K), collect(1:N), n; alg = CliqueTrees.METIS())
        tf = timeit(() -> SheafMPC.refactor!(Ct))
        tso = timeit(() -> (copyto!(x, b); SheafMPC.solve!(Ct, x)))
        out[nm] = Dict("symbolic" => ts, "factor" => tf.min, "factor_med" => tf.med, "solve" => tso.min,
                       "solve_med" => tso.med, "nnzL" => SheafMPC.factor_nnz(Ct), "res" => relres(K, x, b))
    end
    # BlockLDL: the cost model's choice (one thread), and AMD for reference
    signs = kkt_signs(N, n)
    to = @elapsed (perm, name, table) = BL.choose_ordering(K; structure = structure, cost = BL.CostModel(nthreads = 1))
    for (nm, p, tord) in (("blockldl", perm, to), ("blockldl_amd", nothing, 0.0))
        tsy = @elapsed begin
            pp = p === nothing ? BL.order_amd(K) : p
            S = BL.symbolic(K, pp, signs; relax = RELAX)
        end
        F = BL.Factor(S)
        BL.factor!(F, K)
        tf = timeit(() -> BL.factor!(F, K))
        w = zeros(N)
        tso = timeit(() -> (copyto!(x, b); BL.ldiv!(F, x, w)))
        r = zeros(N); xr = zeros(N)
        _, rr, steps = BL.solve_refined!(F, K, xr, b, r, w; iters = 3, rtol = 1e-15)
        out[nm] = Dict("symbolic" => tsy + tord, "ordering_time" => tord, "factor" => tf.min, "factor_med" => tf.med,
                       "solve" => tso.min, "solve_med" => tso.med, "nnzL" => S.nnzL, "flops" => S.flops,
                       "nsup" => S.nsup, "res" => relres(K, x, b), "res_refined" => rr, "refine_steps" => steps,
                       "nreg" => F.nreg, "ordering" => string(p === nothing ? :amd : name))
        nm == "blockldl" && (out[nm]["candidates"] = [Dict("name" => string(t.name), "nnzL" => t.nnzL, "flops" => t.flops,
                                                         "critical" => t.critical, "est" => t.est, "time" => t.time)
                                                    for t in table])
    end
    # Riccati (HPIPM-like) on the stacked LQ problem with hard dynamics
    if riccati !== nothing
        W, q, rr = riccati
        nx, nu = size(W.B)
        xs = [zeros(nx) for _ in 1:W.N]; us = [zeros(nu) for _ in 1:W.N]; ls = [zeros(nx) for _ in 1:W.N]
        tf = timeit(() -> riccati_factor!(W); minreps = 3)
        tso = timeit(() -> riccati_solve!(W, q, rr, zeros(nx), xs, us, ls); minreps = 3)
        out["riccati"] = Dict("factor" => tf.min, "factor_med" => tf.med, "solve" => tso.min, "solve_med" => tso.med,
                              "res" => riccati_residual(W, q, rr, zeros(nx), xs, us, ls),
                              "flops" => W.N * (2.0 * nx^3 + 2.0 * nu * nx^2 + nu^2 * nx + nu^3 / 3))
    end
    return out
end

function print_case(label, N, nnzK, res)
    @printf("%-34s N=%7d nnzK=%8d load=%.1f\n", label, N, nnzK, loadavg())
    for k in ("osqp_qdldl", "qdldl_jl", "cliquetrees", "cliquetrees_metis", "blockldl_amd", "blockldl", "riccati")
        haskey(res, k) || continue
        r = res[k]
        @printf("   %-18s factor %9.3f ms  solve %8.3f ms  nnzL %9s  res %.1e %s\n", k, 1e3 * r["factor"],
                1e3 * r["solve"], haskey(r, "nnzL") ? string(r["nnzL"]) : "-", r["res"],
                haskey(r, "ordering") ? "(" * r["ordering"] * ")" : "")
    end
    flush(stdout)
end

function fleet_set(rows)
    for graph in GRAPHS, form in FORMS, n in NS
        graph == :grid && isqrt(n)^2 != n && continue
        b = form == "expanded" ? 1 : HN
        lab0 = loadavg()
        qp, lab = fleet_problem(n, HN; graph = graph, b = b, dyn = DYN)
        K, nv, _ = kkt_matrix(qp)
        L = kkt_labels(lab)
        st = BL.KKTStructure(L.agent, L.block)
        ric = (form == "expanded" && n <= RICCATI_MAX) ? fleet_riccati(n, HN; graph = graph, dyn = DYN) : nothing
        res = bench_kkt(K, nv; structure = st, riccati = ric)
        label = "fleet $graph $form $(DYN) n=$n"
        print_case(label, size(K, 1), nnz(K), res)
        push!(rows, Dict{String,Any}("set" => "fleet", "graph" => string(graph), "form" => form, "dyn" => string(DYN),
                                     "n" => n, "N" => HN, "kkt_dim" => size(K, 1), "nnzK" => nnz(K), "load" => lab0,
                                     "kernels" => res))
        GC.gc()
    end
end

"The paper's grid fleet (Resolution, common_spatial.jl) and its team pushforwards."
function reduced_set(rows)
    for (R, Cc) in ((8, 8), (16, 16))
        sc = FleetScenario(; rows = R, cols = Cc, H = HN, coherence = :rows, seed = 20261018)
        layout = sp_grid(R, Cc; spacing = sc.spacing)[2]
        spec = fleet_spec(sc; xhat = formation_start(sc, layout), t0 = 0.0)
        model = build_model(spec)
        P = model.program
        ag, tm = vertex_coordinates(model)
        for k in (0, 1, 2, 4, R)
            alpha = k == 0 ? collect(1:(R*Cc)) : k == 1 ? sp_rows(R, Cc) : sp_strips(R, Cc, k)
            Pi = spatial_partition(model, alpha)
            tp = 0.0
            if k == 0
                Pk = P
            else
                tp = @elapsed (Pk, _) = pushforward(P, Pi; basis = :structured)
            end
            Pc = canonical_partition(Pi)
            nb = maximum(Pc)
            vteam = zeros(Int, nb); vtime = zeros(Int, nb)
            for v in eachindex(Pc)
                vteam[Pc[v]] = alpha[ag[v]]; vtime[Pc[v]] = tm[v] + 1
            end
            offs = Pk.offsets
            var_agent = zeros(Int, offs[end]); var_block = zeros(Int, offs[end])
            for v in 1:nb
                var_agent[(offs[v]+1):offs[v+1]] .= vteam[v]
                var_block[(offs[v]+1):offs[v+1]] .= vtime[v]
            end
            qp = sheaf_qp(Pk)
            K, nv, _ = kkt_matrix(qp)
            st = SheafMPC._kkt_structure(K, nv, (agent = var_agent, block = var_block))
            res = bench_kkt(K, nv; structure = st)
            lvl = k == 0 ? "fine" : k == R ? "fleet" : "teams k=$k"
            print_case("reduced $(R)x$(Cc) $lvl", size(K, 1), nnz(K), res)
            push!(rows, Dict{String,Any}("set" => "reduced", "rows" => R, "cols" => Cc, "H" => HN, "level" => lvl,
                                         "k" => k, "t_pushforward" => tp, "kkt_dim" => size(K, 1), "nnzK" => nnz(K),
                                         "load" => loadavg(), "kernels" => res))
            GC.gc()
        end
    end
end

"Thread scaling of BlockLDL (factor and solve) on the structured order picked for each thread count."
function threads_set(rows)
    for graph in GRAPHS, form in FORMS, n in NS
        n >= 16 || continue
        graph == :grid && isqrt(n)^2 != n && continue
        b = form == "expanded" ? 1 : HN
        qp, lab = fleet_problem(n, HN; graph = graph, b = b, dyn = DYN)
        K, nv, _ = kkt_matrix(qp)
        L = kkt_labels(lab)
        st = BL.KKTStructure(L.agent, L.block)
        N = size(K, 1)
        signs = kkt_signs(N, nv)
        bb = randn(N); x = similar(bb); w = zeros(N)
        res = Dict{String,Any}()
        @printf("threads %s %s n=%d N=%d load=%.1f\n", graph, form, n, N, loadavg())
        perms = Dict{Symbol,Vector{Int}}()
        for ord in (:amd, :nd4, :nd16)
            perms[ord] = BL.make_ordering(K, ord; structure = st)
        end
        for nt in THREADS
            nt <= Threads.nthreads() || continue
            pm, name, _ = BL.choose_ordering(K; structure = st, cost = BL.CostModel(nthreads = nt))
            for (ord, perm) in [collect(perms); [:model => pm]]
                S = BL.symbolic(K, perm, signs; relax = RELAX)
                F = BL.Factor(S; nthreads = nt)
                tf = timeit(() -> BL.factor!(F, K))
                tso = timeit(() -> (copyto!(x, bb); BL.ldiv!(F, x, w)))
                key = string(nt, "_", ord)
                res[key] = Dict("threads" => nt, "order" => string(ord), "model_pick" => string(name), "factor" => tf.min,
                                "factor_med" => tf.med, "solve" => tso.min, "solve_med" => tso.med, "nnzL" => S.nnzL,
                                "flops" => S.flops, "res" => relres(K, x, bb),
                                "tasks" => F.sched === nothing ? 1 : length(F.sched.tasks))
                @printf("   t=%2d %-6s%s factor %9.3f ms  solve %8.3f ms  nnzL %9d  res %.1e\n", nt, ord,
                        ord == :model ? "(" * string(name) * ")" : "", 1e3 * tf.min, 1e3 * tso.min, S.nnzL, res[key]["res"])
                flush(stdout)
            end
        end
        push!(rows, Dict{String,Any}("set" => "threads", "graph" => string(graph), "form" => form, "n" => n,
                                     "kkt_dim" => N, "load" => loadavg(), "threads" => res))
        GC.gc()
    end
end

"Rank-k diagonal updates (rho changed on k rows) against a refactorization."
function lowrank_set(rows)
    for graph in GRAPHS, n in filter(x -> 16 <= x <= 256, NS)
        graph == :grid && isqrt(n)^2 != n && continue
        qp, lab = fleet_problem(n, HN; graph = graph, b = 1, dyn = DYN)
        K, nv, di = kkt_matrix(qp)
        N = size(K, 1)
        perm, name, _ = BL.choose_ordering(K; structure = nothing)
        S = BL.symbolic(K, perm, kkt_signs(N, nv); relax = RELAX)
        F = BL.Factor(S); BL.factor!(F, K)
        tref = timeit(() -> BL.factor!(F, K)).min
        w = zeros(N)
        m = N - nv
        res = Dict{String,Any}("refactor" => tref)
        @printf("lowrank %s n=%d N=%d refactor %.3f ms load=%.1f\n", graph, n, N, 1e3 * tref, loadavg())
        for k in (1, 4, 16, 64, 256)
            k <= m || continue
            rows_ = nv .+ (k == 1 ? [m ÷ 2] : round.(Int, range(1, m; length = k)))
            dl = 0.5 .* nonzeros(K)[di[rows_]]                  # rho halved on these rows
            # time update + downdate pairs on a fresh factor, report one update
            BL.factor!(F, K)
            t = timeit(() -> (BL.update_diagonal!(F, rows_, dl, w); BL.update_diagonal!(F, rows_, -dl ./ 1.5, w));
                       minreps = 3).min / 2
            cost = sum(BL.path_cost(F, j) for j in rows_)
            # accuracy of one update against the refactorization
            BL.factor!(F, K); BL.update_diagonal!(F, rows_, dl, w)
            K2 = copy(K); nonzeros(K2)[di[rows_]] .+= dl
            bb = randn(N); x = copy(bb); BL.ldiv!(F, x, zeros(N))
            res[string(k)] = Dict("update" => t, "path_entries" => cost, "res" => relres(K2, x, bb))
            @printf("   k=%4d update %9.3f ms (%.2fx refactor)  path entries %9d  res %.1e\n", k, 1e3 * t, t / tref,
                    cost, res[string(k)]["res"])
            flush(stdout)
        end
        push!(rows, Dict{String,Any}("set" => "lowrank", "graph" => string(graph), "n" => n, "kkt_dim" => N,
                                     "ordering" => string(name), "load" => loadavg(), "lowrank" => res))
    end
end

function main()
    BLAS.set_num_threads(1)
    rows = Dict{String,Any}[]
    @printf("host %s, %s, %d threads, load %.1f\n", gethostname(), Sys.cpu_info()[1].model, Threads.nthreads(), loadavg())
    mkpath(joinpath(@__DIR__, "results"))
    out = joinpath(@__DIR__, "results", "kkt" * (isempty(TAG) ? "" : "_" * TAG) * ".json")
    save() = open(io -> JSON.print(io, Dict("rows" => rows, "host" => gethostname(), "cpu" => Sys.cpu_info()[1].model,
                                            "threads" => Threads.nthreads(), "sets" => SETS), 1), out, "w")
    "fleet" in SETS && (fleet_set(rows); save())
    "reduced" in SETS && (reduced_set(rows); save())
    "threads" in SETS && (threads_set(rows); save())
    "lowrank" in SETS && (lowrank_set(rows); save())
    println("wrote ", out)
end

main()
