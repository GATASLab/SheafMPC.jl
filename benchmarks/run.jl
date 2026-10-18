# run.jl: run one tier of the benchmark.
#
#   julia --project=benchmarks benchmarks/run.jl TIER [options]
#
# TIER: quick (local, about 5 minutes), full (local), hpg (the large sizes, one
# instance per process: use --only), smoke (a correctness pass, no load gate).
# Options:
#   --families a,b     restrict to these family keys (see TIER_SPECS)
#   --solvers a,b      restrict to these solvers
#   --only NAME        run only the instance whose key contains NAME
#   --out DIR          results directory (default benchmarks/results/<tier>_<date>)
#   --list             print the instance keys of the tier and exit
# Environment: BENCH_MAX_LOAD (4), BENCH_MAX_WAIT (7200 s), BENCH_TIME_LIMIT (s per
# solve), BENCH_MUMBLEBEE_NAME (rename the Mumblebee solver, for a second variant).
#
# One JSON file per instance: machine and software, the load before and after,
# the references, and per solver and accuracy tier the calibration, the cold
# rows and the warm rows (see src/protocol.jl).

include(joinpath(@__DIR__, "src", "BenchHarness.jl"))
using .BenchHarness
const BH = BenchHarness
using Dates, Printf, Statistics, LinearAlgebra
import JSON

BLAS.set_num_threads(1)

argval(k, d) = (i = findfirst(==(k), ARGS); i === nothing ? d : ARGS[i+1])
const TIER = isempty(ARGS) ? "quick" : ARGS[1]
const ONLY = argval("--only", "")
const FAMS = split(argval("--families", ""), ",", keepempty = false)
const SOLV = split(argval("--solvers", ""), ",", keepempty = false)
const OUT = argval("--out", joinpath(@__DIR__, "results", TIER * "_" * Dates.format(now(), "yyyymmdd_HHMM")))
const TLIM = parse(Float64, get(ENV, "BENCH_TIME_LIMIT", TIER == "hpg" ? "600" : "60"))

# instance specs per tier: (key, family key, constructor, reps, cold_qps, accuracy tiers)
spec(key, fam, f; reps = 3, cold = 5, tiers = ["low", "medium", "high"]) = (key = key, fam = fam, f = f, reps = reps, cold = cold, tiers = tiers)

function tier_specs(t)
    S = []
    if t == "smoke"
        push!(S, spec("fleet_ring_box_n4", "fleet", () -> BH.fleet_instance(n = 4, L = 3); reps = 1, cold = 2))
        push!(S, spec("fleet_ring_soc_n4", "fleet", () -> BH.fleet_instance(n = 4, cone = :soc, L = 3); reps = 1, cold = 2))
        push!(S, spec("di_box_N10", "single", () -> BH.single_instance(model = :di, N = 10, L = 3); reps = 1, cold = 2))
        push!(S, spec("di_soc_N10", "single", () -> BH.single_instance(model = :di, N = 10, cone = :soc, L = 3); reps = 1, cold = 2))
        push!(S, spec("quad_N10", "single", () -> BH.single_instance(model = :quad, N = 10, L = 3); reps = 1, cold = 2))
        push!(S, spec("chain_M4", "chain", () -> BH.chain_instance(M = 4, L = 3); reps = 1, cold = 2))
        push!(S, spec("osqprand_nx10_s1", "osqprand", () -> BH.osqprand_instance(nx = 10, L = 3); reps = 1, cold = 2))
        push!(S, spec("reduced_k8", "reduced", () -> BH.reduced_instance(k = 8, L = 3); reps = 1, cold = 2))
    elseif t == "quick"
        for n in (1, 4, 16)
            push!(S, spec("fleet_ring_box_n$n", "fleet", () -> BH.fleet_instance(n = n, L = 6)))
        end
        push!(S, spec("fleet_ring_soc_n4", "fleet", () -> BH.fleet_instance(n = 4, cone = :soc, L = 6)))
        push!(S, spec("fleet_ring_box_b4_n4", "fleet", () -> BH.fleet_instance(n = 4, b = 4, L = 6)))
        push!(S, spec("di_box_N20", "single", () -> BH.single_instance(model = :di, N = 20, L = 6)))
        push!(S, spec("quad_N20", "single", () -> BH.single_instance(model = :quad, N = 20, L = 6)))
        push!(S, spec("chain_M4", "chain", () -> BH.chain_instance(M = 4, L = 6)))
        push!(S, spec("osqprand_nx20_s1", "osqprand", () -> BH.osqprand_instance(nx = 20, L = 6)))
        push!(S, spec("reduced_k8", "reduced", () -> BH.reduced_instance(k = 8, L = 6)))
    elseif t == "full" || t == "hpg"
        big = t == "hpg"
        ns = big ? (256, 1024) : (1, 4, 16, 64, 256)
        for graph in (:ring, :grid), cone in (:box, :soc), b in (1, 4), n in ns
            L = n >= 1024 ? 6 : n >= 256 ? 8 : 12
            reps = n >= 256 ? 3 : 5
            push!(S, spec("fleet_$(graph)_$(cone)" * (b == 1 ? "" : "_b$b") * "_n$n", "fleet",
                          () -> BH.fleet_instance(n = n, graph = graph, cone = cone, b = b, L = L); reps = reps, cold = min(L, 6)))
        end
        if !big
            for N in (10, 25, 50, 100)
                push!(S, spec("di_box_N$N", "single", () -> BH.single_instance(model = :di, N = N, L = 12); reps = 5))
                push!(S, spec("di_soc_N$N", "single", () -> BH.single_instance(model = :di, N = N, cone = :soc, L = 12); reps = 5))
                push!(S, spec("quad_N$N", "single", () -> BH.single_instance(model = :quad, N = N, L = 12); reps = 5))
            end
            for M in (3, 4, 6, 8, 10)
                push!(S, spec("chain_M$M", "chain", () -> BH.chain_instance(M = M, L = 12); reps = 5))
            end
            for nx in (10, 20, 40, 80, 160), s in (1, 2, 3)
                push!(S, spec("osqprand_nx$(nx)_s$s", "osqprand", () -> BH.osqprand_instance(nx = nx, seed = s, L = 12); reps = 5))
            end
            for k in (0, 2, 4, 8)
                push!(S, spec("reduced_k$k", "reduced", () -> BH.reduced_instance(k = k, L = 12); reps = 5))
            end
        end
    else
        error("unknown tier $t")
    end
    return S
end

function solver_specs()
    sp = [BH.sheafmpc_spec(time_limit = TLIM), BH.osqp_spec(time_limit = TLIM), BH.clarabel_spec(time_limit = TLIM),
          BH.mumblebee_spec()]
    isdefined(BH, :hpipm_spec) && push!(sp, BH.hpipm_spec())
    isdefined(BH, :piqp_spec) && push!(sp, BH.piqp_spec())
    if haskey(ENV, "BENCH_MUMBLEBEE_NAME")
        i = findfirst(s -> s.name == "mumblebee", sp)
        s = sp[i]
        sp[i] = BH.SolverSpec(name = ENV["BENCH_MUMBLEBEE_NAME"], kind = s.kind, applicable = s.applicable, variants = s.variants,
                              setup = s.setup, solve! = s.solve!, update! = s.update!, warm! = s.warm!, info = s.info)
    end
    isempty(SOLV) || filter!(s -> s.name in SOLV, sp)
    return sp
end

jsonable(x::AbstractFloat) = isfinite(x) ? Float64(x) : (isnan(x) ? "NaN" : (x > 0 ? "Inf" : "-Inf"))
jsonable(x::Union{Integer,Bool,String,Nothing}) = x
jsonable(x::Symbol) = string(x)
jsonable(x::AbstractString) = String(x)
jsonable(x::AbstractDict) = Dict{String,Any}(string(k) => jsonable(v) for (k, v) in x)
jsonable(x::Union{AbstractVector,Tuple}) = [jsonable(v) for v in x]
jsonable(x) = string(x)

function instance_summary(inst)
    p = inst.seq[1]
    return Dict{String,Any}("family" => inst.family, "name" => inst.name, "params" => inst.params,
                            "nvars" => BH.nvars(p), "ncons" => BH.ncons(p), "nnzP" => BH.nnz(p.P), "nnzA" => BH.nnz(p.A),
                            "nsoc" => length(p.socs), "has_stage" => p.stage !== nothing, "L" => length(inst.seq),
                            "shift" => inst.shift !== nothing, "t_generate" => inst.t_generate,
                            "refs" => [Dict{String,Any}("obj0" => r.obj0, "source" => r.source, "status" => r.status,
                                                        "prim_rel" => r.prim_rel, "dual_rel" => r.dual_rel, "t" => r.t) for r in inst.refs])
end

function run_instance(s, solvers)
    inst = s.f()
    gate = TIER == "smoke" ? Dict{String,Any}("load" => BH.loadavg(), "gate" => "skipped") : BH.wait_for_load()
    res = Dict{String,Any}("tier" => TIER, "key" => s.key, "instance" => instance_summary(inst),
                           "machine" => BH.machine_info(), "load_before" => gate, "time_limit" => TLIM,
                           "protocol" => Dict("reps" => s.reps, "cold_qps" => s.cold, "tiers" => s.tiers,
                                              "calibration" => "tolerance in eps .* (1, 0.1, 0.01, 0.001), fastest variant meeting the tier on the first, middle and last QP",
                                              "timer" => "time_ns around the call; GC.gc(false) before, outside the clock"),
                           "solvers" => Dict{String,Any}())
    for sp in solvers
        sp.applicable(inst.seq[1]) || continue
        sres = Dict{String,Any}("info" => sp.info(), "kind" => string(sp.kind), "tiers" => Dict{String,Any}())
        for (tname, eps) in BH.TIERS
            tname in s.tiers || continue
            tr = Dict{String,Any}("eps" => eps)
            cal = BH.calibrate(sp, inst, eps; time_cap = TLIM)
            tr["calibration"] = cal
            ch = cal["chosen"]
            if ch === nothing
                tr["status"] = "never_meets"
                @printf("  %-10s %-6s never meets the tier (best obj_err %.1e, prim_rel %.1e)\n", sp.name, tname,
                        minimum([get(t, "obj_err", Inf) for t in cal["trials"]]; init = Inf),
                        minimum([get(t, "prim_rel", Inf) for t in cal["trials"]]; init = Inf))
            else
                v, tol = ch["variant"], ch["tol"]
                cold = BH.run_cold(sp, inst, eps, v, tol; reps = s.reps, cold_qps = s.cold)
                warm, tsu = BH.run_warm(sp, inst, eps, v, tol; reps = s.reps)
                tr["status"] = "ran"; tr["variant"] = v; tr["tol"] = tol
                tr["cold"] = cold; tr["warm"] = warm; tr["warm_setup"] = tsu
                tr["cold_stats"] = BH.seqstats(cold); tr["warm_stats"] = BH.seqstats(warm; skipfirst = true)
                tr["setup_med"] = median([r["t_setup_med"] for r in cold])
                cs = tr["cold_stats"]; ws = tr["warm_stats"]
                @printf("  %-10s %-6s cold med %9.3f ms (fail %d/%d)  warm med %9.3f p90 %9.3f max %9.3f ms (fail %d/%d)  setup %8.2f ms  %s tol %.0e\n",
                        sp.name, tname, 1e3 * cs["median"], cs["failures"], cs["count"], 1e3 * ws["median"], 1e3 * ws["p90"],
                        1e3 * ws["max"], ws["failures"], ws["count"], 1e3 * tr["setup_med"], string(v), tol)
            end
            flush(stdout)
            sres["tiers"][tname] = tr
        end
        res["solvers"][sp.name] = sres
    end
    res["load_after"] = BH.loadavg()
    return res
end

function main()
    specs = tier_specs(TIER)
    isempty(FAMS) || filter!(s -> s.fam in FAMS, specs)
    isempty(ONLY) || filter!(s -> occursin(ONLY, s.key), specs)
    if "--list" in ARGS
        foreach(s -> println(s.key), specs); return
    end
    mkpath(OUT)
    solvers = solver_specs()
    pk = BH.git_state(BH.SHEAFMPC_DIR)
    if pk["dirty"]
        write(joinpath(OUT, "sheafmpc_worktree_$(pk["diff_sha1"][1:min(end, 12)]).diff"), BH.package_diff(BH.SHEAFMPC_DIR))
    end
    println("tier $TIER, $(length(specs)) instances, solvers $(join([s.name for s in solvers], ", ")), out $OUT")
    println("SheafMPC $(pk["sha"][1:min(end, 10)])", pk["dirty"] ? " + worktree diff $(pk["diff_sha1"][1:min(end, 12)])" : "")
    for s in specs
        file = joinpath(OUT, s.key * ".json")
        isfile(file) && (println("skip $(s.key) (done)"); continue)
        println("== $(s.key)  load $(BH.loadavg()[1])"); flush(stdout)
        res = run_instance(s, solvers)
        res["harness_git"] = BH.git_state(@__DIR__; paths = ["benchmarks"])
        open(io -> JSON.print(io, jsonable(res)), file, "w")
    end
    println("wrote ", OUT)
end

main()
