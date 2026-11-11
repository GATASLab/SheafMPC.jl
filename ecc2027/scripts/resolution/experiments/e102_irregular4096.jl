# E102: the equal 200 ms budget of E71c on the irregular (natural, random geometric) formation at 4096 vehicles,
# every arm of a seed in the SAME job, sequentially, on one pinned core (ratios between arms are then fair).
#
# Same generator, scenario, references, limits and solvers as E71c (resprun71 of e71_budget.jl, which this script
# includes; e71_budget.jl lives in the itay/ecc-final tree, set E102_E71 to its path if it is not next to this file).
# Per seed, in this order:
#   coord          converged centralized MPC (coord71, MPCController to its default accuracy): the reference cost Jc
#   rt_admm        centralized MPC warm started from the shifted iterate and stopped at the 200 ms period
#                  (arm71 :rt, ADMM only, no polish, rho fixed, overrun guard; E71/E71c's rt_admm_200ms)
#   team_resp_K    team MPC on response teams (E79's k-means on unconstrained responses, respteams71) with K teams:
#                  K = the q=8 count of E71c (team_resp_qs8) and coarser counts 0.5 K, 0.35 K, 0.25 K (E102_FRACS),
#                  each floored at the number of classes (at the floor the teams are the classes: one team per region)
# Every arm: per-step wall time (one core), fraction within the period, closed-loop cost over Jc, raw input-limit
# violation of the first input before projection, certified gaps at the measured state against a tight (1e-9)
# central solve: true gap, the dual certificate (cert), and the KKT-normal certificate in H_S of the arm's teams (eta;
# for rt_admm in H_S of the q=8 response teams). The labels for the K counts come from one embedding and one set of
# per-class k-means runs (identical to calling respteams71 once per K: the rng consumption does not depend on K).
#
#   E102_N=4096 E102_SEEDS=1,2,3 E102_PARTDIR=<dir> julia --project=env scripts/resolution/experiments/e102_irregular4096.jl
#   E102_MODE=merge E102_PARTDIR=<dir> E102_OUT=results/e102_irregular4096.json julia --project=env scripts/resolution/experiments/e102_irregular4096.jl

const MODE102 = get(ENV, "E102_MODE", "run")
haskey(ENV, "E71_FALLBACK") || (ENV["E71_FALLBACK"] = get(ENV, "E102_FALLBACK", "none"))   # E106: shift
haskey(ENV, "E71_C") && ENV["E71_C"] == "real" && error("E102 runs the irregular formation only")
haskey(ENV, "E71_MODE") || (ENV["E71_MODE"] = MODE102 == "run" ? "run" : "merge_c")
include(get(ENV, "E102_E71", joinpath(@__DIR__, "e71_budget.jl")))

const N102 = parse(Int, get(ENV, "E102_N", "4096"))
const SEEDS102 = parse.(Int, split(get(ENV, "E102_SEEDS", "1"), ","))
const STEPS102 = parse(Int, get(ENV, "E102_STEPS", "30"))
const HYB102 = parse.(Float64, split(get(ENV, "E102_HYB_FRACS", "0.25,0.35"), ","))   # team counts of the hybrid arms
const FRACS102 = parse.(Float64, split(get(ENV, "E102_FRACS", "1,0.5,0.35,0.25"), ","))   # of the q=8 count, floored at one team per class
const ARMS102 = split(get(ENV, "E102_ARMS", "coord,rt_admm,team"), ",")
const PART102 = get(ENV, "E102_PARTDIR", joinpath(@__DIR__, "..", "..", "..", "bench", "irregular", "results", "parts102"))
const OUT102 = get(ENV, "E102_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "e102_irregular4096.json"))

"""respteams71's embedding and per-class k-means once, then E79's allocation DP for every budget in `Kbs`."""
function respteams102(sc, E, inst, seed, Kbs)
    n = sc.n; cls = inst.class; K = maximum(cls)
    t0 = time_ns()
    F = cholesky(Symmetric(E.H))
    Uc = [cholesky(Symmetric(E.H0[i])).U for i in 1:n]
    Y = [Float64[] for _ in 1:n]
    for r in 1:R71
        rng = Xoshiro(79_000_000 + 1000 * (10_000 + seed) + r); tr = 2.0 * r
        dp = [0.3 .* randn(rng, 2) for _ in 1:K]; dv = [0.15 .* randn(rng, 2) for _ in 1:K]
        x0 = map(1:n) do i
            p, vv = reference26(sc, i, tr); d = length(p); c = cls[i]
            [p .+ [dp[c]; zeros(d - 2)]; vv .+ [dv[c]; zeros(d - 2)]]
        end
        refs, term = references26(sc, tr)
        q, _ = qc71(sc.fleet, E.off, x0, refs, term)
        u = -(F \ q)
        for i in 1:n
            append!(Y[i], Uc[i] * u[E.off[i]+1:E.off[i+1]] ./ sqrt(R71))
        end
    end
    F = nothing; GC.gc()
    temb = (time_ns() - t0) / 1e9
    rng = Xoshiro(79 + seed)
    cs = sort(unique(cls)); mem = [findall(==(c), cls) for c in cs]
    t1 = time_ns()
    sols = [begin X = Matrix{Float64}(reduce(vcat, (Y[i]' for i in m))); [kmeans79_(X, j, rng) for j in 1:length(m)] end for m in mem]
    tkm = (time_ns() - t1) / 1e9
    labs = Dict{Int,Vector{Int}}()
    for Kb in Kbs
        nc = length(cs)
        best = fill(Inf, nc + 1, Kb + 1); arg = zeros(Int, nc + 1, Kb + 1); best[1, 1] = 0.0
        for a in 1:nc, k in 0:Kb
            best[a, k+1] == Inf && continue
            for j in 1:length(mem[a])
                k + j <= Kb || break
                v = best[a, k+1] + sols[a][j][2]
                v < best[a+1, k+j+1] && (best[a+1, k+j+1] = v; arg[a+1, k+j+1] = j)
            end
        end
        @assert best[nc+1, Kb+1] < Inf "budget $Kb infeasible for $(nc) classes"
        lab = zeros(Int, n); k = Kb; nxt = 0
        for a in nc:-1:1
            j = arg[a+1, k+1]
            lab[mem[a]] .= nxt .+ sols[a][j][1]; nxt += j; k -= j
        end
        labs[Kb] = SM.canonical_partition(lab)
    end
    return labs, Dict{String,Any}("embed_seconds" => temb, "kmeans_seconds" => tkm, "classes" => length(cs),
                                  "class_size_max" => maximum(length.(mem)), "class_size_med" => median(length.(mem)))
end

function run102(seed; n = N102, steps = STEPS102, quiet = false, arms = ARMS102)
    inst = sq_instance(n, seed)
    labc, _ = sq_teams(inst, "classes", seed)
    sc = scenario63(inst, seed, labc)
    res = Dict{String,Any}("kind" => "e102", "n_requested" => n, "seed" => seed, "n" => length(inst.kinds), "edges" => length(inst.edges),
                           "steps" => steps, "period" => PERIOD71, "load_start" => loadavg26(), "controllers" => Dict{String,Any}(),
                           "load_before" => Dict{String,Any}(), "arm_seconds" => Dict{String,Any}())
    R = res["controllers"]
    tE = @elapsed (E = Ev71(sc)); res["eval_build_seconds"] = tE
    lq, _ = sq_teams(inst, "qs8", seed); K8 = maximum(lq)
    ncls = length(unique(inst.class))
    Kof = Dict(f => max(ncls, round(Int, f * K8)) for f in FRACS102)    # at least one team per class
    Kbs = unique([Kof[f] for f in FRACS102])
    tsel = @elapsed ((labs, sel) = respteams102(sc, E, inst, seed, unique([K8; Kbs])))   # K8 always (rt's H_S)
    sel["select_seconds"] = tsel; sel["K_qs8"] = K8; sel["Ks"] = Kbs; res["selection"] = sel
    S8 = hs71(E, labs[K8])
    Rf = Ref71(sc)
    Jc = NaN
    if "coord" in arms
        res["load_before"]["coord"] = loadavg26()
        ta = @elapsed (co = coord71(sc; steps = steps)); res["arm_seconds"]["coord"] = ta
        Jc = co["closed_loop_cost"]; co["cost_ratio"] = 1.0; co["viol"] = nothing
        delete!(co, "steps_detail")
        R["coord"] = co
        quiet || @printf("seed %d n %d coord cost %.6e ms med %.1f max %.1f met %.2f (%.0f s)\n", seed, res["n"], Jc,
                         ms26(co["t_total"]["median"]), ms26(co["t_total"]["max"]), co["met_frac"], ta)
        flush(stdout)
    end
    pr(key, o, ta) = quiet || !haskey(o, "certified") ||
        @printf("  %-16s K %5d ratio %.5f ms med %.1f max %.1f met %.2f viol %.2e gap med %.1e cert/gap %.1f eta/gap %.1f (%.0f s)\n",
                key, o["teams"], o["cost_ratio"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), o["met_frac"], o["viol"]["max"],
                o["certified"]["gap"]["median"], get(o["certified"]["cert_over_gap"], "median", NaN),
                get(get(o["certified"], "eta_over_gap", Dict()), "median", NaN), ta)
    if "rt_admm" in arms
        res["load_before"]["rt_admm"] = loadavg26()
        ta = @elapsed (o = safe71(() -> arm71(sc, :rt, Rf, E, S8, Jc; steps = steps), "rt_admm")); res["arm_seconds"]["rt_admm"] = ta
        R["rt_admm"] = o; pr("rt_admm", o, ta); flush(stdout)
    end
    if "qs8" in arms                                                              # quasi-stable teams, q = 8
        key = "team_qs8"; res["load_before"][key] = loadavg26()
        ta = @elapsed (o = safe71(() -> arm71(sc, :team, Rf, E, hs71(E, lq), Jc; lab = lq, steps = steps), key)); res["arm_seconds"][key] = ta
        R[key] = o; pr(key, o, ta); flush(stdout); GC.gc()
    end
    if "team" in arms
        for Kb in Kbs
            key = "team_resp_$Kb"
            res["load_before"][key] = loadavg26()
            S = Kb == K8 ? S8 : hs71(E, labs[Kb])
            ta = @elapsed (o = safe71(() -> arm71(sc, :team, Rf, E, S, Jc; lab = labs[Kb], steps = steps), key)); res["arm_seconds"][key] = ta
            o isa AbstractDict && (o["frac_of_qs8"] = Kb / K8; o["K_qs8"] = K8; o["fracs_requested"] = [f for f in FRACS102 if Kof[f] == Kb];
                                   o["at_class_floor"] = Kb == ncls; o["classes"] = ncls)
            R[key] = o; pr(key, o, ta); flush(stdout)
            S = nothing; GC.gc()
        end
    end
    if "hyb" in arms                                  # team plan, then V-FISTA on the centralized program in H_S (E71c hyb)
        for f in HYB102
            Kb = max(ncls, round(Int, f * K8)); key = "hyb_resp_$Kb"
            res["load_before"][key] = loadavg26()
            lab = haskey(labs, Kb) ? labs[Kb] : respteams102(sc, E, inst, seed, [Kb])[1][Kb]
            S = hs71(E, lab)
            ta = @elapsed (o = safe71(() -> (V = VFS71(E, S); arm71(sc, :hyb, Rf, E, S, Jc; lab = lab, V = V, steps = steps)), key))
            res["arm_seconds"][key] = ta
            o isa AbstractDict && (o["frac_of_qs8"] = Kb / K8; o["frac_requested"] = f; o["at_class_floor"] = Kb == ncls)
            R[key] = o; pr(key, o, ta); flush(stdout); S = nothing; GC.gc()
        end
    end
    if "vf" in arms                                   # V-FISTA on the centralized program, H_S of the regions, shifted start
        key = "vf_HS_shift"; res["load_before"][key] = loadavg26()
        ta = @elapsed (o = safe71(() -> begin
            Cref = central52(sc.fleet)
            x0 = start26(sc); refs0, term0 = references26(sc, 0.0)
            cq0 = SM.CondensedQP(sc.fleet, x0, refs0; terminal = term0)
            V = VF71(cq0, sc.fleet, labc)
            o = vf71(sc, Cref, V, "shift", labc; steps = steps); o["cost_ratio"] = o["closed_loop_cost"] / Jc; o
        end, key))
        res["arm_seconds"][key] = ta
        o isa AbstractDict && haskey(o, "steps") && delete!(o, "steps")
        R[key] = o; quiet || (o isa AbstractDict && haskey(o, "cost_ratio") && @printf("  %-16s ratio %.5f ms med %.1f met %.2f (%.0f s)\n", key, o["cost_ratio"], ms26(o["t_total"]["median"]), o["met_frac"], ta))
        flush(stdout); GC.gc()
    end
    res["load_end"] = loadavg26()
    return res
end

function main102()
    BLAS.set_num_threads(1)
    mkpath(PART102)
    run102(1; n = 64, steps = 3, quiet = true)                                     # warm-up (compile every path)
    for seed in SEEDS102
        res = run102(seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(), "affinity" => get(ENV, "E71_AFFINITY", ""),
                           "partition" => get(ENV, "SLURM_JOB_PARTITION", ""), "exclusive" => get(ENV, "E102_EXCLUSIVE", "0") == "1")
        path = joinpath(PART102, @sprintf("e102_n%d_seed%d.json", N102, seed))
        open(io -> JSON.print(io, clean71(res), 1), path, "w"); println("wrote $path"); flush(stdout)
    end
end

"""Merge: per size, per arm (the team arms keyed by their fraction of the q=8 count), over seeds."""
function merge102()
    raw = [JSON.parsefile(f) for f in readdir(PART102; join = true) if endswith(f, ".json") && occursin("e102_", basename(f))]
    out = Dict{String,Any}("experiment" => "E102: E71c's equal 200 ms budget on the irregular formation, all arms of a seed in one job, sequentially, on one pinned core (partition and node exclusivity per seed under partition/exclusive). Arms: converged centralized (reference cost), centralized stopped at the period (ADMM only, warm, E71c rt_admm), quasi-stable teams (q=8, when run), response teams at the q=8 count of E71c and at 1/2, 0.35 and 1/4 of it (floored at one team per class). Overrun rule per arm under fallback_rule: none = the plan is applied whenever it finishes; shift = on a step over the period the previously applied plan, shifted one sample, is applied (E106). Certified gaps against a tight (1e-9) central solve at the measured state.",
                           "generator" => Dict("density_per_m2" => 1.0, "radius_m" => parse(Float64, get(ENV, "BENCH_NAT_RADIUS", "1.5")),
                                               "region_size" => parse(Int, get(ENV, "BENCH_NAT_REGION", "12")), "reference_tol" => 1e-9,
                                               "note" => "natural_instance of squads_dc.jl: slots uniform at one per m^2, edges below the radius (largest component), weight 1/distance, regions by k-means of about region_size slots, each region one class (drone or car, one variant)"),
                           "period_ms" => 1e3 * PERIOD71,
                           "fields" => Dict("ms_med" => "median over seeds of the per-seed median time per step (ms, one core, steps after the untimed step 0)",
                                            "ms_max" => "worst step over seeds (ms)", "met_frac" => "mean over seeds of the fraction of steps within 200 ms",
                                            "cost_ratio_med/max" => "closed-loop cost over that of converged centralized MPC in the same job, median/worst over seeds",
                                            "certified.cert_over_gap_med" => "dual certificate over the true gap, median of per-seed medians",
                                            "certified.eta_over_gap_med" => "KKT-normal certificate in H_S (the arm's teams; for rt_admm the q=8 teams) over the true gap",
                                            "viol_max_raw" => "largest input-limit violation of the first input before projection (applied input is projected)"),
                           "sizes" => Dict{String,Any}())
    for nreq in sort!(unique([p["n_requested"] for p in raw]))
        P = sort([p for p in raw if p["n_requested"] == nreq]; by = p -> p["seed"])
        S = Dict{String,Any}("seeds" => [p["seed"] for p in P], "n" => [p["n"] for p in P], "edges" => [p["edges"] for p in P],
                             "steps" => P[1]["steps"], "hosts" => [p["meta"]["host"] for p in P], "cpu" => unique([p["meta"]["cpu"] for p in P]),
                             "jobs" => [p["meta"]["job"] for p in P], "partition" => [get(p["meta"], "partition", "hpg-default") for p in P],
                             "exclusive" => [get(p["meta"], "exclusive", false) for p in P], "affinity" => [p["meta"]["affinity"] for p in P],
                             "load" => [Dict("start" => p["load_start"], "end" => p["load_end"], "before_arm" => p["load_before"]) for p in P],
                             "arm_seconds" => [p["arm_seconds"] for p in P], "selection" => [p["selection"] for p in P],
                             "controllers" => Dict{String,Any}())
        cs = [p["controllers"]["coord"] for p in P if haskey(p["controllers"], "coord")]
        if !isempty(cs)
            S["controllers"]["coord"] = Dict{String,Any}("seeds" => length(cs), "cost_med" => med71([c["closed_loop_cost"] for c in cs]),
                "ms_med" => 1e3 * med71([c["t_total"]["median"] for c in cs]), "ms_max" => 1e3 * max71([c["t_total"]["max"] for c in cs]),
                "met_frac" => mean71([c["met_frac"] for c in cs]), "cost_ratio_med" => 1.0, "cost_ratio_max" => 1.0)
        end
        rts = [p["controllers"]["rt_admm"] for p in P if haskey(p["controllers"], "rt_admm")]
        isempty(rts) || (S["controllers"]["rt_admm"] = armmerge71(rts))
        for key in ("vf_HS_shift",)
            vs = [p["controllers"][key] for p in P if haskey(p["controllers"], key) && p["controllers"][key] isa AbstractDict && haskey(p["controllers"][key], "cost_ratio")]
            isempty(vs) || (S["controllers"][key] = Dict{String,Any}("seeds" => length(vs), "cost_ratio_med" => med71([v["cost_ratio"] for v in vs]),
                "cost_ratio_max" => max71([v["cost_ratio"] for v in vs]), "cost_ratio_per_seed" => [v["cost_ratio"] for v in vs],
                "ms_med" => 1e3 * med71([v["t_total"]["median"] for v in vs]), "ms_max" => 1e3 * max71([v["t_total"]["max"] for v in vs]),
                "met_frac" => mean71([v["met_frac"] for v in vs]), "iters_max" => max71([v["iters"]["max"] for v in vs])))
        end
        for f in sort(unique(vcat([[get(o, "frac_requested", nothing) for (k, o) in p["controllers"] if startswith(k, "hyb_resp_") && o isa AbstractDict] for p in P]...)))
            f === nothing && continue
            ps = [o for p in P for (k, o) in p["controllers"] if startswith(k, "hyb_resp_") && o isa AbstractDict && get(o, "frac_requested", -1) == f]
            m = armmerge71(ps); m === nothing && continue
            m["teams_per_seed"] = [o["teams"] for o in ps]; m["frac_requested"] = f
            m["cost_ratio_per_seed"] = [o["cost_ratio"] for o in ps]
            m["refine_skipped_frac"] = sum(o["refine_skipped_steps"] for o in ps) / sum(length(o["steps"]) - 1 for o in ps)
            S["controllers"]["hyb_f$(round(Int, 100f))"] = m
        end
        # every team fraction (the frontier), keyed by the requested fraction in percent
        FR = Dict{String,Vector{Any}}()
        for p in P, (k, o) in p["controllers"]
            (startswith(k, "team_resp_") && o isa AbstractDict && haskey(o, "fracs_requested")) || continue
            for f in o["fracs_requested"]
                push!(get!(FR, "team_f$(round(Int, 100f))", Any[]), o)
            end
        end
        begin
            for (k, ps) in FR
                m = armmerge71(ps); m === nothing && continue
                m["teams_per_seed"] = [o["teams"] for o in ps]; m["cost_ratio_per_seed"] = [o["cost_ratio"] for o in ps]
                S["controllers"][k] = m
            end
        end
        rp = [p["controllers"]["rt_admm"]["cost_ratio"] for p in P if haskey(p["controllers"], "rt_admm") && p["controllers"]["rt_admm"] isa AbstractDict && haskey(p["controllers"]["rt_admm"], "cost_ratio")]
        isempty(rp) || haskey(S["controllers"], "rt_admm") && S["controllers"]["rt_admm"] !== nothing && (S["controllers"]["rt_admm"]["cost_ratio_per_seed"] = rp)
        qs = [p["controllers"]["team_qs8"] for p in P if haskey(p["controllers"], "team_qs8")]
        isempty(qs) || (S["controllers"]["team_qs8"] = armmerge71(qs))
        for (tag, f) in (("qs8", 1.0), ("half", 0.5), ("f035", 0.35), ("quarter", 0.25))
            ps = Any[]
            for p in P, (k, o) in p["controllers"]
                startswith(k, "team_resp_") && o isa AbstractDict && haskey(o, "fracs_requested") && any(x -> isapprox(x, f), o["fracs_requested"]) && push!(ps, o)
            end
            isempty(ps) && continue
            m = armmerge71(ps); m["teams_per_seed"] = [o["teams"] for o in ps]; m["frac_requested"] = f
            m["cost_ratio_per_seed"] = [o["cost_ratio"] for o in ps]
            m["at_class_floor"] = [o["at_class_floor"] for o in ps]; m["classes_per_seed"] = [o["classes"] for o in ps]
            S["controllers"]["team_resp_$tag"] = m
        end
        out["sizes"][string(nreq)] = S
    end
    open(io -> JSON.print(io, clean71(out), 1), OUT102, "w"); println("wrote $OUT102")
    for (n, S) in sort(collect(out["sizes"]); by = x -> parse(Int, x[1])), (k, d) in sort(collect(S["controllers"]); by = first)
        d === nothing && continue
        c = get(d, "certified", Dict())
        @printf("%5s %-18s teams %-6s ms med %7.1f max %7.1f met %.3f cost %.5f/%.5f cert/gap %s eta/gap %s viol %s\n", n, k,
                string(get(d, "teams", "")), d["ms_med"], d["ms_max"], d["met_frac"], d["cost_ratio_med"], d["cost_ratio_max"],
                string(get(c, "cert_over_gap_med", "")), string(get(c, "eta_over_gap_med", "")), string(get(d, "viol_max_raw", "")))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE102 == "merge" ? merge102() : main102()
end
