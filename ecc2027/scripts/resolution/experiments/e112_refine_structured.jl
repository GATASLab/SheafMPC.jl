# E112: Algorithm 1 with certified refinement (Theorem refine) on a structured formation with a known perturbation.
#
# Formation: the planted squads of squads_dc.jl (BENCH_INSTANCE=squads, Fig. teams(a)): squads of 4 to 16 vehicles of
# one data class, irregular edges inside a squad, and between adjacent squads edges drawn by the north-west corner rule
# so that every member of a squad has the same total weight into every other squad. The coarsest lossless teams phi0
# (colour refinement ignoring the edges inside a team, on the unperturbed weights) are then the squads (or coarser).
# Perturbation: every edge between squads gets the weight w_ij + omega w'_ij with w'_ij = w_ij U(-1, 1) (squads_dc.jl's
# eps; the same draws for every omega, the same graph), so phi0 is no longer almost equitable and Corollary defect
# predicts a gap O(omega^2). The coarsest lossless teams of the perturbed weights are recorded (they fragment).
#
# Setting (Theorem refine, as E103b): regulation to the slots at rest in formation error coordinates, the terminal
# equality x_H = slot state for every vehicle, ball limits, H = 10, h = 0.2 s. Start in formation for phi0: team c of
# phi0 displaced by (dp_c, dv_c), dp_c ~ 0.15 N(0, I), dv_c ~ 0.05 N(0, I) in the plane, scaled by 0.7 until the team
# program of phi0 with the terminal equality is feasible (E103b's rule).
#
# omega in {0.05, 0.2, 1.0} and eps in {0.05, 0.01, 1e-3, 1e-4}: at the requested eps = 0.01, 0.05 the coarse teams are
# already certified for omega <= 0.2 (their gap is about 1e-4 J*), so the smaller eps and omega = 1 (the end of the
# range of Corollary defect) are added to make the splitting act.
#
# Arms (one process per (n, seed), every omega and arm on one core):
#   exact      centralized MPC, Clarabel to 1e-9 with the terminal equality, every sample: reference cost and J*
#   coord      centralized MPC with TeamMPC at its default accuracy (the converged centralized time)
#   fix        phi0 fixed, no refinement (team solve and certificate timed, no splits)
#   ref_<eps>  Algorithm 1 in the sample: solve the team program, certify (Lemma cert, per team, E63's NNLS over the
#              active ball normals, terminal rows eliminated), and while eta > eps W + delta split the teams of largest
#              eta_c by 2-means of the members' Newton steps (own-Hessian metric, E103b's split103b, covering
#              eta - (eps W + delta)/2), rebuild the quotient program and re-solve. Every split refines the teams.
#              delta = E112_DELTA_REL * W_0 with W_0 the value of phi0 at x(0).
# Timed per sample (one thread): team solve (projection, TeamMPC solve, terminal fix, lift), certificate (cert103b
# and the plan value), splitting (all rounds: 2-means, quotient build, certificate operators, cold re-solve,
# re-certificate). Untimed per sample: J(u) and J* (Clarabel 1e-9) for the true gap. Checks: eta >= gap at every
# certified plan, and the two inequalities of Theorem refine(ii) on the finite run,
#   tail:  sum_{s=t}^{T-1} l(s) + W_T <= W_t   (W_T the Clarabel team value at x(T) with the final teams)
#   value: W_t <= (J*_t + delta) / (1 - eps).
#
#   E112_N=256 E112_SEEDS=1 julia --project=env scripts/resolution/experiments/e112_refine_structured.jl
#   E112_MODE=merge E112_PARTDIR=<parts> E112_OUT=<json> julia --project=env .../e112_refine_structured.jl

const MODE112 = get(ENV, "E112_MODE", "run")
if MODE112 == "run"
    ENV["BENCH_INSTANCE"] = "squads"
    ENV["E103B_MODE"] = "run"
    # E112_LIBDIR (optional override, default this directory): the experiments directory whose E103b chain
    # (e103b -> e70_adaptive_e103b -> e63_gap -> e30_bounds_dc -> e27_pareto_dc/e26_flagship_dc + fleet_dc, e51,
    # squads_dc) is loaded. The HPG runs (jobs 50301368, 50301851) set it to the E71 tree
    # (/blue/fairbanksj/itaykadosh/e71/tree), the tree that produced results/e103b_amortized.json; this directory
    # carries the same files, the drone/car library under the _dc names.
    const LIBDIR112 = get(ENV, "E112_LIBDIR", @__DIR__)
    include(joinpath(LIBDIR112, "e103b_amortized.jl"))
    isdefined(Main, :car_dc) || include(joinpath(LIBDIR112, "fleet_dc.jl"))     # drone_dc, car_dc, dc_select, dc_lanes
else
    using JSON, Statistics, Printf
end

const N112 = parse(Int, get(ENV, "E112_N", "256"))
const SEEDS112 = parse.(Int, split(get(ENV, "E112_SEEDS", "1"), ","))
const STEPS112 = parse(Int, get(ENV, "E112_STEPS", "30"))
const OMEGAS112 = parse.(Float64, split(get(ENV, "E112_OMEGAS", "0.05,0.2,1.0"), ","))
const EPS112 = parse.(Float64, split(get(ENV, "E112_EPS", "0.05,0.01,0.001,0.0001"), ","))
const ARMS112 = split(get(ENV, "E112_ARMS", "coord,fix,ref"), ",")
const DELTA_REL112 = parse(Float64, get(ENV, "E112_DELTA_REL", "1e-4"))
const ROUNDS112 = parse(Int, get(ENV, "E112_ROUNDS", "40"))
const PARTDIR112 = get(ENV, "E112_PARTDIR", joinpath(@__DIR__, "..", "..", "..", "results", "e112_parts"))
const OUT112 = get(ENV, "E112_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "e112_refine_structured.json"))
const P112 = 0.2

if MODE112 == "run"

"""The perturbed squads instance, phi0 (coarsest lossless teams of the unperturbed weights) and E103b's setup."""
function setup112(n, seed, omega)
    inst0 = squads_instance(n, seed; eps = 0.0)
    inst = squads_instance(n, seed; eps = omega)
    inst.edges == inst0.edges || error("the perturbation changed the graph")
    n = length(inst.kinds)
    phi0 = sq_teams(inst0, "aep", seed)[1]
    phiw = sq_teams(inst, "aep", seed)[1]
    fl0 = sq_fleet(inst, DT63G, H63G, CONE63G)
    refs, term = refs_reg63(inst, fl0, H63G)
    fl = termfleet103(fl0, term)
    sc = scenario70(inst, seed, fl)
    K0 = maximum(phi0)
    rng = Xoshiro(112_200 + seed)
    dp = [0.15 .* randn(rng, 2) for _ in 1:K0]; dv = [0.05 .* randn(rng, 2) for _ in 1:K0]
    start(a) = [fl.agents[i].nx == 6 ? [inst.slots[i] + [a .* dp[phi0[i]]; 1.5]; [a .* dv[phi0[i]]; 0.0]] :
                [inst.slots[i][1:2] + a .* dp[phi0[i]]; a .* dv[phi0[i]]] for i in 1:n]
    cf = cfleet63(fl0, H63G; terminal = :equality); Kc = Cons63(cf, CONE63G)
    x0 = start(1.0)
    base = CProg(cf, CData(x0, refs, term))
    H0b = H0blk30(cf); Hb = sparse(H0b + base.A' * base.Wd * base.A)
    scale = 1.0; W0 = NaN
    for _ in 1:12
        P = CProg(base, CData(x0, refs, term)); _, hq, c = quad63(P, Hb)
        s = solve63(Hb, hq, c, Kc, teamZ63(cf, phi0); E = P.E, e = P.e)
        s.status in ("SOLVED", "ALMOST_SOLVED") && (W0 = s.J; break)
        scale *= 0.7; x0 = start(scale)
    end
    isfinite(W0) || error("no feasible start for phi0")
    return (inst = inst, n = n, fl = fl, sc = sc, cls = phi0, x0 = x0, refs = refs, term = term, cf = cf, K = Kc,
            base = base, H0b = H0b, Hb = Hb, scale = scale, phi0 = phi0, phiw = phiw, W0 = W0)
end

"""The team value at x with teams lab (Clarabel, terminal equality, 1e-9; untimed)."""
function teamvalue112(I, x, lab)
    P = CProg(I.base, CData(x, I.refs, I.term)); _, hq, c = quad63(P, I.Hb)
    s = solve63(I.Hb, hq, c, I.K, teamZ63(I.cf, lab); E = P.E, e = P.e)
    return s.J, s.status
end

"""Solve the team program of T at x and certify the plan: (u, etac, d, W, t_solve, t_cert)."""
function solvecert112(I, T, co, x)
    t0 = time_ns()
    xq, rq, tq = teamdata51(T.Q, I.sc, x, I.refs, I.term)
    info = SM.step!(T.C, xq, rq; terminal = tq)
    Uq = [copy(v) for v in SM.trajectories(T.C.fp, SM.plan(T.C))[2]]
    fixterm103!(I, T, Uq, x)
    u = liftU103(T, Uq)
    t1 = time_ns()
    etac, d, P = cert103b(I, co, x, u); _, hq, c = quad63(P, I.Hb); W = J63(I.Hb, hq, c, u)
    t2 = time_ns()
    return (u = u, etac = etac, d = d, W = W, status = string(info.status), t_solve = (t1 - t0) / 1e9, t_cert = (t2 - t1) / 1e9)
end

"""One closed loop of team MPC from phi0: refine = false (fixed teams) or Algorithm 1 with (eps, delta)."""
function arm112(I, Jref; refine::Bool, eps::Float64 = NaN, delta::Float64 = 0.0, steps = STEPS112, seed = 1)
    GC.gc(); rng = Xoshiro(1121 + seed)
    T = team103(I, I.phi0); co = certop103(I, T.lab); lab = T.lab
    x = [copy(v) for v in I.x0]; cost = 0.0; rec = Dict{String,Any}[]
    for k in 0:(steps-1)
        teams_in = maximum(lab)
        r = solvecert112(I, T, co, x)
        tsolve = r.t_solve; tcert = r.t_cert; tsplit = 0.0; ns = 0; rounds = 0; stalled = false
        if refine
            while sum(r.etac) > eps * abs(r.W) + delta
                if rounds >= ROUNDS112
                    stalled = true; break
                end
                ts0 = time_ns()
                lab2, s = split103b(I, lab, r.etac, r.d, sum(r.etac) - (eps * abs(r.W) + delta) / 2, rng)
                if s == 0
                    tsplit += (time_ns() - ts0) / 1e9; stalled = true; break
                end
                T = team103(I, lab2); co = certop103(I, T.lab); lab = T.lab
                r = solvecert112(I, T, co, x)
                tsplit += (time_ns() - ts0) / 1e9
                ns += s; rounds += 1
            end
        end
        ttot = tsolve + tcert + tsplit
        # evaluation (untimed)
        Jt, Js, sts, tres = truth103(I, x, r.u)
        eta = sum(r.etac); gap = Jt - Js
        ua = first63(I.cf, r.u); x1 = sq_plant(I.fl, x, ua); l = stage103(I, x, ua, x1)
        cost += l
        push!(rec, Dict{String,Any}("step" => k, "teams_in" => teams_in, "teams" => maximum(lab), "splits" => ns, "rounds" => rounds,
            "stalled" => stalled, "t_solve" => tsolve, "t_cert" => tcert, "t_split" => tsplit, "t_total" => ttot,
            "met" => ttot <= P112, "eta" => eta, "W" => r.W, "Jplan" => Jt, "Jstar" => Js, "gap" => gap, "l" => l,
            "status" => r.status, "status_full" => sts, "term_res" => tres,
            "certified" => eta <= eps * abs(r.W) + delta))
        x = x1
        GC.gc()
    end
    cost += sq_stage(I.fl, x, nothing, I.refs)[1]
    WT, stT = teamvalue112(I, x, lab)
    # checks
    tolg(r) = 1e-8 * abs(r["Jstar"]) + 1e-12
    cert_viol = count(r -> r["gap"] > r["eta"] + tolg(r), rec)
    ratio = [r["eta"] / r["gap"] for r in rec if r["gap"] > 1e-7 * abs(r["Jstar"])]
    tail = zeros(length(rec)); acc = WT
    for t in length(rec):-1:1
        acc += rec[t]["l"]; tail[t] = acc            # sum_{s >= t} l(s) + W_T
    end
    tail_slack = [(tail[t] - rec[t]["W"]) / abs(rec[t]["W"]) for t in eachindex(rec)]
    tail_viol = count(>(1e-6), tail_slack)
    val_slack = refine ? [(rec[t]["W"] - (rec[t]["Jstar"] + delta) / (1 - eps)) / abs(rec[t]["W"]) for t in eachindex(rec)] : Float64[]
    val_viol = count(>(1e-9), val_slack)
    a = rec[2:end]
    return Dict{String,Any}("refine" => refine, "eps" => eps, "delta" => delta, "closed_loop_cost" => cost, "cost_ratio" => cost / Jref,
        "teams" => [r["teams"] for r in rec], "teams_start" => maximum(I.phi0), "teams_final" => rec[end]["teams"],
        "splits" => [r["splits"] for r in rec], "splits_total" => sum(r["splits"] for r in rec), "splits_after0" => sum(r["splits"] for r in a; init = 0),
        "samples_split_after0" => count(r -> r["splits"] > 0, a), "stalled" => count(r -> r["stalled"], rec),
        "uncertified" => refine ? count(r -> !r["certified"], rec) : nothing,
        "t_total" => st103([r["t_total"] for r in a]), "t_solve" => st103([r["t_solve"] for r in a]),
        "t_cert" => st103([r["t_cert"] for r in a]), "t_split_when" => st103([r["t_split"] for r in a if r["splits"] > 0]),
        "t_total0" => rec[1]["t_total"], "t_split0" => rec[1]["t_split"],
        "met_frac" => count(r -> r["met"], a) / length(a),
        "eta_over_gap" => st103(ratio), "gap_rel" => st103([r["gap"] / abs(r["Jstar"]) for r in rec]),
        "eta_rel" => st103([r["eta"] / abs(r["W"]) for r in rec]),
        "cert_viol" => cert_viol, "tail_viol" => tail_viol, "tail_slack_max" => maximum(tail_slack),
        "value_viol" => refine ? val_viol : nothing, "value_slack_max" => refine ? maximum(val_slack) : nothing,
        "WT" => WT, "WT_status" => stT, "steps" => rec)
end

function run112(seed; n = N112, steps = STEPS112, omegas = OMEGAS112, epss = EPS112, arms = ARMS112, quiet = false)
    res = Dict{String,Any}("n_requested" => n, "seed" => seed, "steps" => steps, "period" => P112, "omega" => Dict{String,Any}())
    for om in omegas
        I = setup112(n, seed, om)
        delta = DELTA_REL112 * I.W0
        R = Dict{String,Any}("n" => I.n, "omega" => om, "teams_phi0" => maximum(I.phi0), "teams_lossless_perturbed" => maximum(I.phiw),
                             "squads" => I.inst.nsquads, "classes" => maximum(I.inst.class), "edges" => length(I.inst.edges),
                             "start_scale" => I.scale, "W0" => I.W0, "delta" => delta, "arms" => Dict{String,Any}())
        res["omega"][string(om)] = R; A = R["arms"]
        quiet || (@printf("n %d seed %d omega %.2f: phi0 %d teams (squads %d), lossless after perturbation %d, scale %.2f\n",
                          I.n, seed, om, maximum(I.phi0), I.inst.nsquads, maximum(I.phiw), I.scale); flush(stdout))
        ex = exact103(I; steps = steps); Jc = ex["closed_loop_cost"]; A["exact"] = ex
        pr(key, o) = quiet || haskey(o, "error") || (@printf("  %-10s ratio %.6f ms med %7.1f max %7.1f met %.2f teams %s splits %s eta/gap med %s min %s gap med %s viol %s/%s/%s\n",
            key, o["cost_ratio"], 1e3 * o["t_ctl_med"], 1e3 * o["t_ctl_max"], o["met_frac"], get(o, "teams_str", "-"), string(get(o, "splits_total", "-")),
            haskey(o, "eta_over_gap") && haskey(o["eta_over_gap"], "median") ? @sprintf("%.3f", o["eta_over_gap"]["median"]) : "-",
            haskey(o, "eta_over_gap") && haskey(o["eta_over_gap"], "min") ? @sprintf("%.3f", o["eta_over_gap"]["min"]) : "-",
            haskey(o, "gap_rel") ? @sprintf("%.1e", o["gap_rel"]["median"]) : "-",
            string(get(o, "cert_viol", "-")), string(get(o, "tail_viol", "-")), string(get(o, "value_viol", "-"))); flush(stdout))
        ex["t_ctl_med"] = ex["t_ctl"]["median"]; ex["t_ctl_max"] = ex["t_ctl"]["max"]; pr("exact", ex)
        for arm in arms
            keys_ = arm == "ref" ? [@sprintf("ref_%g", e) for e in epss] : [arm]
            for key in keys_
                A[key] = try
                    o = if arm == "coord"
                        central103(I, Jc; kind = :coord, steps = steps)
                    elseif arm == "fix"
                        arm112(I, Jc; refine = false, steps = steps, seed = seed)
                    else
                        arm112(I, Jc; refine = true, eps = parse(Float64, key[5:end]), delta = delta, steps = steps, seed = seed)
                    end
                    tt = haskey(o, "t_total") ? o["t_total"] : o["t_ctl"]
                    o["t_ctl_med"] = tt["median"]; o["t_ctl_max"] = tt["max"]
                    haskey(o, "teams") && (o["teams_str"] = "$(o["teams_start"])->$(o["teams"][1])->$(o["teams_final"])")
                    o
                catch err
                    @printf("  %s FAILED: %s\n", key, sprint(showerror, err)[1:min(end, 600)]); flush(stdout)
                    Dict{String,Any}("error" => sprint(showerror, err)[1:min(end, 2000)])
                end
                pr(key, A[key])
            end
        end
    end
    return res
end

function main112()
    BLAS.set_num_threads(1); mkpath(PARTDIR112)
    get(ENV, "E112_WARMUP", "1") == "1" && run112(1; n = 48, steps = 3, omegas = [0.2], quiet = true)
    for seed in SEEDS112
        t0 = time()
        res = run112(seed)
        res["meta"] = Dict("host" => gethostname(), "job" => get(ENV, "SLURM_JOB_ID", ""), "cpu" => Sys.cpu_info()[1].model,
                           "affinity" => get(ENV, "E112_AFFINITY", ""), "commit" => get(ENV, "E112_COMMIT", ""), "seconds" => time() - t0,
                           "libdir" => LIBDIR112, "lib_md5" => get(ENV, "E112_LIBMD5", ""))
        path = joinpath(PARTDIR112, @sprintf("e112_n%d_seed%d.json", N112, seed))
        open(io -> JSON.print(io, clean103(res), 1), path, "w"); println("wrote $path"); flush(stdout)
    end
end

end # run

function merge112()
    parts = [JSON.parsefile(joinpath(PARTDIR112, f)) for f in readdir(PARTDIR112) if endswith(f, ".json")]
    md(v) = isempty(v) ? nothing : Dict("median" => median(v), "min" => minimum(v), "max" => maximum(v), "n" => length(v))
    rows = Dict{String,Any}(); inst = Dict{String,Any}(); scatter = Dict{String,Any}()
    for p in parts, (oms, R) in p["omega"]
        ikey = "n$(p["n_requested"])_om$(oms)"
        I = get!(inst, ikey, Dict{String,Any}("runs" => Any[]))
        push!(I["runs"], Dict(k => R[k] for k in ("n", "teams_phi0", "teams_lossless_perturbed", "squads", "classes", "edges", "start_scale", "W0", "delta")))
        for (arm, o) in R["arms"]
            haskey(o, "error") && continue
            r = get!(rows, "$(ikey)_$arm", Dict{String,Any}("n_requested" => p["n_requested"], "omega" => parse(Float64, oms), "arm" => arm, "runs" => Any[]))
            run = Dict{String,Any}("seed" => p["seed"], "cost_ratio" => o["cost_ratio"], "ms_med" => 1e3 * o["t_ctl_med"], "ms_max" => 1e3 * o["t_ctl_max"],
                                   "met_frac" => o["met_frac"])
            for f in ("teams_start", "teams_final", "splits_total", "splits_after0", "samples_split_after0", "stalled", "uncertified",
                      "cert_viol", "tail_viol", "tail_slack_max", "value_viol", "value_slack_max", "t_total0", "t_split0")
                haskey(o, f) && o[f] !== nothing && (run[f] = o[f])
            end
            haskey(o, "teams") && (run["teams"] = o["teams"]; run["teams_after0"] = o["teams"][1]; run["splits_per_step"] = o["splits"])
            for (f, g) in (("t_solve", "solve_ms_med"), ("t_cert", "cert_ms_med"), ("t_split_when", "split_ms_med"))
                haskey(o, f) && haskey(o[f], "median") && (run[g] = 1e3 * o[f]["median"])
            end
            haskey(o, "t_split_when") && haskey(o["t_split_when"], "max") && (run["split_ms_max"] = 1e3 * o["t_split_when"]["max"])
            for f in ("eta_over_gap", "gap_rel", "eta_rel")
                haskey(o, f) && haskey(o[f], "median") && (run[f * "_med"] = o[f]["median"]; run[f * "_min"] = o[f]["min"]; run[f * "_max"] = o[f]["max"])
            end
            push!(r["runs"], run)
            if haskey(o, "steps") && !isempty(o["steps"]) && haskey(o["steps"][1], "eta")
                sc = get!(scatter, "$(ikey)_$arm", Any[])
                for s in o["steps"]
                    J = abs(s["Jstar"]); push!(sc, [s["gap"] / J, s["eta"] / J])
                end
            end
        end
    end
    for (key, r) in rows
        R = r["runs"]; r["seeds"] = length(R)
        for f in ("cost_ratio", "ms_med", "ms_max", "met_frac", "teams_start", "teams_after0", "teams_final", "splits_total", "splits_after0",
                  "samples_split_after0", "solve_ms_med", "cert_ms_med", "split_ms_med", "split_ms_max", "t_total0", "t_split0",
                  "eta_over_gap_med", "eta_over_gap_min", "gap_rel_med", "gap_rel_max", "eta_rel_med", "tail_slack_max", "value_slack_max")
            v = [Float64(x[f]) for x in R if haskey(x, f) && x[f] !== nothing]
            isempty(v) || (r[f] = md(v))
        end
        for f in ("cert_viol", "tail_viol", "value_viol", "stalled", "uncertified")
            any(haskey(x, f) for x in R) && (r[f * "_total"] = sum(get(x, f, 0) for x in R))
        end
    end
    for (k, I) in inst
        for f in ("n", "teams_phi0", "teams_lossless_perturbed", "squads", "classes", "edges", "start_scale")
            I[f] = md([Float64(x[f]) for x in I["runs"]])
        end
    end
    meta = [Dict("n" => p["n_requested"], "seed" => p["seed"], "host" => p["meta"]["host"], "job" => p["meta"]["job"], "cpu" => p["meta"]["cpu"],
                 "affinity" => p["meta"]["affinity"], "commit" => p["meta"]["commit"], "seconds" => p["meta"]["seconds"],
                 "libdir" => get(p["meta"], "libdir", ""), "lib_md5" => get(p["meta"], "lib_md5", "")) for p in parts]
    out = Dict("experiment" => "E112 Algorithm 1 with certified refinement (Theorem refine) on the planted squads formation with inter-squad weights w + omega w', w' = w U(-1,1); start from the coarsest lossless teams of w (squads), now lossy; nominal loop (regulation, terminal equality, teams in formation), ball limits, H = 10, h = 0.2 s",
               "period_ms" => 1e3 * P112, "delta_rel" => parse(Float64, get(ENV, "E112_DELTA_REL", "1e-4")),
               "instances" => inst, "rows" => rows, "runs" => meta, "scatter" => scatter,
               "jobs" => sort(unique([m["job"] for m in meta])), "hosts" => sort(unique([m["host"] for m in meta])),
               "commits" => sort(unique([m["commit"] for m in meta])))
    open(io -> JSON.print(io, out, 1), OUT112, "w"); println("wrote $OUT112")
    for key in sort(collect(keys(rows)))
        r = rows[key]; g(f) = haskey(r, f) ? r[f]["median"] : NaN; gx(f) = haskey(r, f) ? r[f]["max"] : NaN
        @printf("%-26s ratio %.6f ms %7.1f max %7.1f met %.2f teams %5.0f->%5.0f->%5.0f splits>0 %4.0f cert %5.1f split %6.0f eta/gap %.3f (min %.3f) gap %.1e viol %s/%s/%s\n",
                key, g("cost_ratio"), g("ms_med"), gx("ms_max"), g("met_frac"), g("teams_start"), g("teams_after0"), g("teams_final"),
                g("splits_after0"), g("cert_ms_med"), g("split_ms_med"), g("eta_over_gap_med"),
                haskey(r, "eta_over_gap_min") ? r["eta_over_gap_min"]["min"] : NaN, g("gap_rel_med"),
                string(get(r, "cert_viol_total", "-")), string(get(r, "tail_viol_total", "-")), string(get(r, "value_viol_total", "-")))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE112 == "merge" ? merge112() : main112()
end
