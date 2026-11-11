# E113: a distributed MPC baseline on E106's irregular formations at the same 200 ms period.
#
# Consensus ADMM over the vehicles (E52/E71's DistributedMPC, one agent per vehicle, rho = E71_RHO = 0.1, the
# value E71 used on this formation; local QPs to MPCController's accuracy), warm started from the shifted previous
# plan and duals (the package's :shift). Same generator, seeds, steps, references, starts and limits as E106
# (sq_instance, scenario63 through e102_irregular4096.jl and e71_budget.jl), same overrun rule: on a step whose
# time exceeds the period the previously applied plan, shifted one sample, is applied. Step 0 is the offline
# initialization of every arm (untimed for all of them): here E113_INIT ADMM iterations from the free response.
#
# Time per sample is E52's PARALLEL time: per ADMM iteration the slowest local solve (each vehicle's QP timed on
# one core), summed over the iterations, plus the rest of the step (data, warm start, lift) divided over the
# vehicles. It assumes one core per vehicle and zero communication latency; the sequential time (every local
# solve on one core) is recorded too. Overrun rule and in-period share use the parallel time.
#
# Per seed:
#   coord        converged centralized MPC (coord71): the reference cost Jc (checked against E106's)
#   rt_admm, team_resp_quarter   (n = 1024 only, E102's arms with E106's rule: E102_FRACS=0.25, E71_FALLBACK=shift,
#                E71_CERT_IN_STEP=1; at 4096 they are E106's own runs, merged from results/e106_overrun_full.json)
#   dadmm_b<b>   b ADMM iterations per sample (E113_BUDGETS): the cost against the budget, and the smallest b
#                whose closed-loop cost is at most the team arm's ("iterations to reach the team cost")
#   dadmm_h      the period-limited controller: iterate to DistributedMPC's residual tolerances (eps_abs 1e-6,
#                eps_rel 1e-4) or at most b_h iterations, b_h = floor((h - o) / p), p the largest parallel time of
#                one iteration and o the largest non-iteration overhead per vehicle over the steps of the largest
#                budget run, capped at E113_CAP for compute (the cap and how often it bound are recorded)
# Communication per sample: rounds = ADMM iterations (one neighbour exchange each), floats = iterations times
# DistributedMPC.floats_per_iteration (y + lam one way and c + mu the other, every interface). Central and team
# MPC: 2 rounds (states up, sum nx floats; inputs down, sum nu floats).
#
#   E113_N=4096 E113_SEEDS=1 E113_PARTDIR=<dir> julia --project=env scripts/resolution/experiments/e113_distributed.jl
#   E113_MODE=merge E113_PARTDIR=<dir> julia --project=env scripts/resolution/experiments/e113_distributed.jl

const MODE113 = get(ENV, "E113_MODE", "run")
haskey(ENV, "E71_FALLBACK") || (ENV["E71_FALLBACK"] = "shift")
haskey(ENV, "E71_CERT_IN_STEP") || (ENV["E71_CERT_IN_STEP"] = "1")
haskey(ENV, "E102_FRACS") || (ENV["E102_FRACS"] = "0.25")
if MODE113 == "run"
    include(joinpath(@__DIR__, "e102_irregular4096.jl"))
else
    using Statistics, Printf
    import JSON
end

const ROOT113 = joinpath(@__DIR__, "..", "..", "..")
const N113 = parse(Int, get(ENV, "E113_N", "4096"))
const SEEDS113 = parse.(Int, split(get(ENV, "E113_SEEDS", "1"), ","))
const STEPS113 = parse(Int, get(ENV, "E113_STEPS", "30"))
const BUDGETS113 = parse.(Int, split(get(ENV, "E113_BUDGETS", "1,2,5,10,20"), ","))
const INIT113 = parse(Int, get(ENV, "E113_INIT", "50"))
const CAP113 = parse(Int, get(ENV, "E113_CAP", "100"))
const ARMS102_113 = split(get(ENV, "E113_TEAM_ARMS", "coord,rt_admm,team"), ",")   # run102's arms at n <= E113_TEAM_N
const TEAMN113 = parse(Int, get(ENV, "E113_TEAM_N", "1024"))
const PART113 = get(ENV, "E113_PARTDIR", joinpath(ROOT113, "bench", "irregular", "results", "parts113"))
const OUT113 = get(ENV, "E113_OUT", joinpath(ROOT113, "results", "e113_distributed.json"))
const E106_113 = get(ENV, "E113_E106", joinpath(ROOT113, "results", "e106_overrun_full.json"))
const H113 = 0.2

sts113(v) = isempty(v) ? Dict{String,Any}() : Dict{String,Any}("median" => median(v), "max" => maximum(v), "min" => minimum(v),
                                                               "mean" => mean(v), "p90" => quantile(v, 0.9), "n" => length(v))

"""
Closed loop of consensus ADMM over the vehicles. `b > 0`: exactly b iterations per sample; `b = 0`: to the
residual tolerances or at most `maxit` iterations. Overrun rule on the parallel time (shift of the applied plan).
"""
function dadmm113(sc, b::Int, Jc; maxit::Int = 3000, steps::Int = STEPS113, init::Int = INIT113, rho = RHO71)
    GC.gc()
    tb = @elapsed begin
        D = local52!(SM.DistributedMPC(sc.fleet, collect(1:sc.n); rho = rho, budget = b, warm = :shift, maxit = max(maxit, 1)))
    end
    M = Admm52("full", D, nothing)
    nag = length(D.locals); fpi = SM.floats_per_iteration(D)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; Uapp = nothing
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        if k == 0
            D.budget = init; D.maxit = max(init, 1)
        else
            D.budget = b; D.maxit = max(maxit, 1)
        end
        u, info, _, tg, rounds, floats = astep52!(M, sc, x, refs, term)
        it = D.iterations
        over = (info.t_total - info.t_solve) / nag
        par = over + D.t_parallel + tg
        seq = info.t_total + tg
        U = SM.trajectories(D.fp, SM.plan(D))[2]
        fallback = k > 0 && par > H113 && Uapp !== nothing
        if fallback
            Uapp = [hcat(Ui[:, 2:end], Ui[:, end]) for Ui in Uapp]
            u = [copy(Ui[:, 1]) for Ui in Uapp]
        else
            Uapp = [copy(Ui) for Ui in U]
        end
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "par" => par, "seq" => seq, "iters" => it, "rounds" => rounds, "floats" => floats,
                                    "par_per_iter" => it > 0 ? D.t_parallel / it : NaN, "overhead_per_agent" => over,
                                    "converged" => D.converged, "status" => string(info.status), "local_failures" => D.local_failures,
                                    "fallback" => fallback, "met" => par <= H113, "viol" => viol))
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(key) = [Float64(r[key]) for r in a]
    return Dict{String,Any}("budget" => b, "maxit" => b > 0 ? b : maxit, "init" => init, "rho" => rho, "agents" => nag,
        "build_seconds" => tb, "floats_per_iteration" => fpi, "closed_loop_cost" => cost, "cost_ratio" => cost / Jc,
        "par" => sts113(col("par")), "seq" => sts113(col("seq")), "iters" => sts113(col("iters")),
        "floats" => sts113(col("floats")), "par_per_iter" => sts113(col("par_per_iter")),
        "overhead_per_agent" => sts113(col("overhead_per_agent")),
        "met_par_frac" => count(r -> r["met"], a) / length(a), "met_seq_frac" => count(r -> r["seq"] <= H113, a) / length(a),
        "fallback_frac" => count(r -> r["fallback"], a) / length(a), "converged_frac" => count(r -> r["converged"], a) / length(a),
        "cap_hit_frac" => b > 0 ? nothing : count(r -> r["iters"] >= maxit, a) / length(a),
        "bad_steps" => count(r -> r["status"] in ("numerical_error", "primal_infeasible", "dual_infeasible"), rec),
        "local_failures" => sum(r["local_failures"] for r in rec), "viol" => sts113(col("viol")), "steps" => rec)
end

"""Floats per sample of central or team MPC: every state up once, every first input down once."""
central_floats113(sc) = (up = sum(ag.nx for ag in sc.fleet.agents), down = sum(ag.nu for ag in sc.fleet.agents))

function run113(seed; n = N113, steps = STEPS113, quiet = false, budgets = BUDGETS113, init = INIT113, cap = CAP113)
    res = Dict{String,Any}("seed" => seed, "n_requested" => n, "steps" => steps, "load_start" => loadavg26(),
                           "controllers" => Dict{String,Any}(), "arm_seconds" => Dict{String,Any}())
    R = res["controllers"]
    if n <= TEAMN113                                       # E102's coord, rt_admm and team arms in this job
        ta = @elapsed (r102 = run102(seed; n = n, steps = steps, quiet = quiet, arms = ARMS102_113))
        res["arm_seconds"]["e102_arms"] = ta; res["selection"] = r102["selection"]
        for (k, o) in r102["controllers"]
            o isa AbstractDict && haskey(o, "steps") && delete!(o, "steps")
            R[k] = o
        end
        Jc = R["coord"]["closed_loop_cost"]
    end
    inst = sq_instance(n, seed)
    labc, _ = sq_teams(inst, "classes", seed)
    sc = scenario63(inst, seed, labc)
    res["n"] = sc.n; res["edges"] = length(inst.edges); res["classes"] = length(unique(inst.class))
    cf = central_floats113(sc); res["central_floats"] = Dict("up" => cf.up, "down" => cf.down, "rounds" => 2)
    if n > TEAMN113
        ta = @elapsed (co = coord71(sc; steps = steps)); res["arm_seconds"]["coord"] = ta
        Jc = co["closed_loop_cost"]; delete!(co, "steps_detail"); haskey(co, "steps") && delete!(co, "steps")
        R["coord"] = co
    end
    quiet || (@printf("seed %d n %d coord cost %.6e\n", seed, sc.n, Jc); flush(stdout))
    for b in budgets
        key = "dadmm_b$b"
        ta = @elapsed (o = safe71(() -> dadmm113(sc, b, Jc; steps = steps, init = init), key)); res["arm_seconds"][key] = ta
        R[key] = o
        quiet || (o isa AbstractDict && haskey(o, "cost_ratio") &&
            @printf("  %-10s ratio %.5f par med %.2f max %.2f ms seq med %.0f ms met(par) %.2f iters %d floats %.3e (%.0f s)\n", key,
                    o["cost_ratio"], 1e3 * o["par"]["median"], 1e3 * o["par"]["max"], 1e3 * o["seq"]["median"], o["met_par_frac"],
                    b, o["floats"]["median"], ta))
        flush(stdout)
    end
    # the iterations that fit the period, from the largest budget run's measured parallel times
    bmax = maximum(budgets); ob = R["dadmm_b$bmax"]
    if ob isa AbstractDict && haskey(ob, "par_per_iter")
        p = ob["par_per_iter"]["max"]; o_ = ob["overhead_per_agent"]["max"]
        bh = max(1, floor(Int, (H113 - o_) / p))
        res["b_h"] = Dict("b_h" => bh, "par_per_iter_max" => p, "par_per_iter_med" => ob["par_per_iter"]["median"],
                          "overhead_max" => o_, "cap" => cap, "maxit" => min(bh, cap), "from" => "dadmm_b$bmax")
        key = "dadmm_h"
        ta = @elapsed (o = safe71(() -> dadmm113(sc, 0, Jc; maxit = min(bh, cap), steps = steps, init = init), key))
        res["arm_seconds"][key] = ta; R[key] = o
        quiet || (o isa AbstractDict && haskey(o, "cost_ratio") &&
            @printf("  %-10s b_h %d (cap %d) ratio %.5f par med %.2f max %.2f ms met(par) %.2f iters med %.0f max %.0f converged %.2f cap hit %.2f (%.0f s)\n",
                    key, bh, cap, o["cost_ratio"], 1e3 * o["par"]["median"], 1e3 * o["par"]["max"], o["met_par_frac"],
                    o["iters"]["median"], o["iters"]["max"], o["converged_frac"], o["cap_hit_frac"], ta))
        flush(stdout)
    end
    res["load_end"] = loadavg26()
    return res
end

function main113()
    BLAS.set_num_threads(1)
    mkpath(PART113)
    run113(1; n = 64, steps = 3, quiet = true, budgets = [1, 2], init = 2, cap = 3)        # warm-up (compile every path)
    for seed in SEEDS113
        res = run113(seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "array_job" => get(ENV, "SLURM_ARRAY_JOB_ID", ""), "task" => get(ENV, "SLURM_ARRAY_TASK_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(), "affinity" => get(ENV, "E71_AFFINITY", ""),
                           "partition" => get(ENV, "SLURM_JOB_PARTITION", ""), "exclusive" => get(ENV, "E102_EXCLUSIVE", "0") == "1",
                           "commit" => get(ENV, "E113_COMMIT", ""), "tree" => get(ENV, "E113_TREE", ""))
        path = joinpath(PART113, @sprintf("e113_n%d_seed%d.json", N113, seed))
        open(io -> JSON.print(io, clean71(res), 1), path, "w"); println("wrote $path"); flush(stdout)
    end
end

# ------------------------------------------------------------------------------------------------ merge
_med(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : median(w))
_max(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : maximum(w))
_min(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : minimum(w))
_mean(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : mean(w))

function merge113()
    raw = [JSON.parsefile(f) for f in readdir(PART113; join = true) if endswith(f, ".json") && startswith(basename(f), "e113_")]
    e106 = isfile(E106_113) ? JSON.parsefile(E106_113) : nothing
    out = Dict{String,Any}(
        "experiment" => "E113: consensus ADMM over the vehicles (distributed MPC) on E106's irregular formations, same seeds, steps, references, starts and overrun rule (on a step over the 200 ms period the previously applied plan shifted one sample is applied), against converged centralized MPC, centralized ADMM stopped at the period and one team per type and reference region (E106 at 4096, rerun in the same job at 1024)",
        "timing" => "ADMM time per sample is the parallel time of E52: per iteration the slowest vehicle's local QP (timed on one core), summed, plus the rest of the step divided over the vehicles. It assumes one core per vehicle and zero communication latency. seq is all local solves on one core. Central, stopped and team arms are one core.",
        "communication" => "ADMM: one round per iteration, floats per sample = iterations x floats_per_iteration (both directions over every interface). Central and team MPC: 2 rounds, states up (sum nx) and first inputs down (sum nu).",
        "fields" => Dict("cost_ratio_med/max/min" => "closed-loop cost over converged centralized MPC in the same job, over seeds",
                         "met_par_frac" => "mean over seeds of the share of steps 1..29 whose parallel time is within the period",
                         "par_ms_med" => "median over seeds of the per-seed median parallel time per sample (ms)",
                         "seq_ms_med" => "the same for the sequential time (one core)",
                         "b_to_team" => "per seed, the smallest fixed budget whose closed-loop cost is at most the team arm's (nothing if none)"),
        "period_ms" => 1e3 * H113, "sizes" => Dict{String,Any}())
    for nreq in sort!(unique([p["n_requested"] for p in raw]))
        P = sort([p for p in raw if p["n_requested"] == nreq]; by = p -> p["seed"])
        S = Dict{String,Any}("seeds" => [p["seed"] for p in P], "n" => [p["n"] for p in P], "edges" => [p["edges"] for p in P],
                             "classes" => [p["classes"] for p in P], "steps" => P[1]["steps"],
                             "hosts" => [p["meta"]["host"] for p in P], "jobs" => [p["meta"]["job"] for p in P],
                             "array_jobs" => unique([p["meta"]["array_job"] for p in P]), "partition" => unique([p["meta"]["partition"] for p in P]),
                             "exclusive" => [p["meta"]["exclusive"] for p in P], "cpu" => unique([p["meta"]["cpu"] for p in P]),
                             "affinity" => [p["meta"]["affinity"] for p in P], "commit" => unique([p["meta"]["commit"] for p in P]),
                             "tree" => unique([p["meta"]["tree"] for p in P]), "arm_seconds" => [p["arm_seconds"] for p in P],
                             "central_floats" => P[1]["central_floats"], "b_h" => [get(p, "b_h", nothing) for p in P],
                             "controllers" => Dict{String,Any}())
        C = S["controllers"]
        Jc = [p["controllers"]["coord"]["closed_loop_cost"] for p in P]
        C["coord"] = Dict{String,Any}("cost_per_seed" => Jc, "ms_med" => 1e3 * _med([p["controllers"]["coord"]["t_total"]["median"] for p in P]),
                                      "met_frac" => _mean([p["controllers"]["coord"]["met_frac"] for p in P]))
        # the team and stopped-centralized arms: this job's at 1024, E106's at 4096
        team = Dict{Int,Float64}(); src = ""
        if all(p -> haskey(p["controllers"], "rt_admm"), P)
            src = "this job (E102 arms, E106 rule)"
            for (tag, pick) in (("rt_admm", k -> k == "rt_admm"), ("team_classes", k -> startswith(k, "team_resp_")))
                os = [first(o for (k, o) in p["controllers"] if pick(k)) for p in P]
                C[tag] = Dict{String,Any}("cost_ratio_per_seed" => [o["cost_ratio"] for o in os], "cost_ratio_med" => _med([o["cost_ratio"] for o in os]),
                    "cost_ratio_max" => _max([o["cost_ratio"] for o in os]), "met_frac" => _mean([o["met_frac"] for o in os]),
                    "ms_med" => 1e3 * _med([o["t_total"]["median"] for o in os]), "ms_max" => 1e3 * _max([o["t_total"]["max"] for o in os]),
                    "teams_per_seed" => [o["teams"] for o in os], "fallback_frac" => _mean([o["fallback_frac"] for o in os]))
                tag == "team_classes" && for (p, o) in zip(P, os); team[p["seed"]] = o["cost_ratio"]; end
            end
        elseif e106 !== nothing && haskey(e106["sizes"], string(nreq))
            E = e106["sizes"][string(nreq)]; src = "E106 ($(E106_113)), same seeds"
            S["e106_cost_check"] = Dict("coord_cost_med_e106" => E["controllers"]["coord"]["cost_med"], "coord_cost_med_here" => _med(Jc),
                                        "n_e106" => E["n"], "n_here" => S["n"])
            for (tag, k) in (("rt_admm", "rt_admm"), ("team_classes", "team_resp_quarter"))
                o = E["controllers"][k]
                C[tag] = Dict{String,Any}("cost_ratio_per_seed" => o["cost_ratio_per_seed"], "cost_ratio_med" => o["cost_ratio_med"],
                    "cost_ratio_max" => o["cost_ratio_max"], "met_frac" => o["met_frac"], "ms_med" => o["ms_med"], "ms_max" => o["ms_max"],
                    "teams" => o["teams"])
                tag == "team_classes" && for (s, r) in zip(E["seeds"], o["cost_ratio_per_seed"]); team[s] = r; end
            end
        end
        S["baseline_source"] = src
        keys_ = sort(unique(vcat([[k for k in keys(p["controllers"]) if startswith(k, "dadmm_")] for p in P]...)))
        for k in keys_
            os = [p["controllers"][k] for p in P if haskey(p["controllers"], k) && haskey(p["controllers"][k], "cost_ratio")]
            isempty(os) && continue
            C[k] = Dict{String,Any}("seeds" => length(os), "budget" => os[1]["budget"], "init" => os[1]["init"], "rho" => os[1]["rho"], "maxit_per_seed" => [o["maxit"] for o in os],
                "cost_ratio_per_seed" => [o["cost_ratio"] for o in os], "cost_ratio_med" => _med([o["cost_ratio"] for o in os]),
                "cost_ratio_max" => _max([o["cost_ratio"] for o in os]), "cost_ratio_min" => _min([o["cost_ratio"] for o in os]),
                "met_par_frac" => _mean([o["met_par_frac"] for o in os]), "met_seq_frac" => _mean([o["met_seq_frac"] for o in os]),
                "fallback_frac" => _mean([o["fallback_frac"] for o in os]),
                "par_ms_med" => 1e3 * _med([o["par"]["median"] for o in os]), "par_ms_max" => 1e3 * _max([o["par"]["max"] for o in os]),
                "seq_ms_med" => 1e3 * _med([o["seq"]["median"] for o in os]), "seq_ms_max" => 1e3 * _max([o["seq"]["max"] for o in os]),
                "par_per_iter_ms_med" => 1e3 * _med([o["par_per_iter"]["median"] for o in os]),
                "iters_med" => _med([o["iters"]["median"] for o in os]), "iters_max" => _max([o["iters"]["max"] for o in os]),
                "rounds_med" => _med([o["iters"]["median"] for o in os]),
                "floats_med" => _med([o["floats"]["median"] for o in os]), "floats_per_iteration_med" => _med([o["floats_per_iteration"] for o in os]),
                "converged_frac" => _mean([o["converged_frac"] for o in os]), "cap_hit_frac" => _mean([o["cap_hit_frac"] for o in os]),
                "bad_steps" => sum(o["bad_steps"] for o in os), "local_failures" => sum(o["local_failures"] for o in os),
                "build_seconds_med" => _med([o["build_seconds"] for o in os]))
        end
        bs = sort([C[k]["budget"] for k in keys(C) if startswith(k, "dadmm_b")])
        b2t = Any[]
        for p in P
            s = p["seed"]; haskey(team, s) || (push!(b2t, nothing); continue)
            bb = nothing
            for b in bs
                o = p["controllers"]["dadmm_b$b"]
                if haskey(o, "cost_ratio") && o["cost_ratio"] <= team[s]
                    bb = b; break
                end
            end
            push!(b2t, bb)
        end
        S["b_to_team"] = b2t; S["budgets"] = bs
        out["sizes"][string(nreq)] = S
    end
    open(io -> JSON.print(io, out, 1), OUT113, "w"); println("wrote $OUT113")
    for (n, S) in sort(collect(out["sizes"]); by = x -> parse(Int, x[1]))
        println("n = $n (realized $(S["n"])), baselines from $(S["baseline_source"]), b to team cost $(S["b_to_team"]), b_h $([b === nothing ? nothing : b["b_h"] for b in S["b_h"]])")
        for (k, d) in sort(collect(S["controllers"]); by = first)
            k == "coord" && continue
            @printf("  %-14s cost %s / %s  met %s  ms %s  iters %s  floats %s\n", k, string(get(d, "cost_ratio_med", "")), string(get(d, "cost_ratio_max", "")),
                    string(get(d, "met_par_frac", get(d, "met_frac", ""))), string(get(d, "par_ms_med", get(d, "ms_med", ""))),
                    string(get(d, "iters_med", "")), string(get(d, "floats_med", "")))
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE113 == "merge" ? merge113() : main113()
end
