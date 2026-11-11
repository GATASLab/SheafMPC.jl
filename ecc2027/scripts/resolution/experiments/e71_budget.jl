# E71-budget: equal time budget on the irregular (natural, random geometric) formation of E63.
# Every controller must deliver an input within the 200 ms period; all in closed loop from E63's starts
# and references (scenario63, soc limits), E71_STEPS steps, step 0 the offline initialization (untimed,
# as in E26/E38/E63).
#
#   rt_<variant>_<ms>   (a) coordinated MPC (MPCController, condensed, our solver) warm started from the
#                       shifted previous iterate (whatever the previous status) and stopped at a wall-clock
#                       budget: the solver's time limit is the budget less the previous step's construction,
#                       setup and lift times, a 1 ms reserve and an overrun guard (largest overrun of the last
#                       10 steps, clamped to [2, 50] ms). The first inputs are projected onto their balls.
#                       variant auto: the default solver (ADMM with crossover to the IPM, polish);
#                       variant admm: E38's interruptible solver (ADMM only, no polish, rho fixed).
#                       Per step: the plan's suboptimality (J(plan) - J*)/|J*| at the measured state (J* the
#                       tight central solve, 1e-9), the distance of the applied first inputs to the optimal
#                       ones (relative 2-norm over the fleet), the raw ball violation.
#   admm_b<b>[_init]    (b) E52's consensus ADMM over the vehicles (DistributedMPC, rho E71_RHO), b iterations
#                       per sample, warm (shift). `_init`: step 0 runs E71_INIT iterations (offline, like
#                       the others' initialization); without: step 0 is b iterations from cold (E52/E63).
#                       Parallel time as E52 (no communication latency), rounds, floats per sample.
#   team_<choice>       (c) team MPC (E51's quotient program, loop51's step), choices classes and qs8.
#   coord               (d) coordinated MPC solved to MPCController's accuracy: the reference cost.
#
# Certified gap, per step and controller, at the measured state (untimed evaluation on the package's
# CondensedQP, J(u) = u'Hu/2 + q'u + c over the input balls; the controller's step time excludes it):
#   plan        the controller's open-loop plan (every input over the horizon), projected radially onto the
#               balls: a feasible plan u_p; its true gap J(u_p) - J* (J* the tight central solve's projected plan)
#   dual        for any w, d(w) = J(w) - g'w - sum_{i,t} r_i ||g_{i,t}||, g = Hw + q, is a valid lower bound on J*
#               (the Lagrangian dual at the ball multipliers z_{i,t} = g_{i,t}, z0 = ||g_{i,t}||, in the dual cone;
#               equal to J* at w = u*). Certificate J(u_p) - max(d(u_raw), d(u_p)) >= the true gap; available to
#               early-stopped central MPC (one product with H, its own data) and to ADMM after one more
#               neighbour exchange of plans and a global sum. Time t_cert (the H product and the norms).
#   thm2        team MPC: the paper's certificate eta (Thm. 2, team_certificate on the team plan, teams S the
#               team map); ADMM: Thm. 2 with singleton teams (S empty, local per vehicle). Time t_eta.
#   vf_<P>_<start>  E72's V-FISTA (constant momentum (sqrt(kb)-1)/(sqrt(kb)+1), metric kb*P, kb = 1.05 lambda_max(P^{-1}H)
#               by power iteration offline, block prox = ball-constrained QP per part by E71_MIN inner FISTA steps)
#               on the coordinated condensed QP, centrally, stopped at the 200 ms budget (iterations stop when the
#               next one would pass the budget less a 1 ms reserve and the overrun guard), applying the best iterate
#               (feasible: every iterate ends on the projection). P: HS (block Jacobi by region teams, H_S of
#               Thm. 2, own Hessians and the edges inside teams) or own (per vehicle). start: cold (zero), shift
#               (the previous step's final iterate moved one instant, last repeated), team (the team MPC plan of
#               this step, regions; its solve counted in the step time). The step time includes the condensed q at
#               the measured state (free responses only; H is constant and built offline). Certificates as above,
#               Thm. 2 with the region teams at the iterate.
#   checks      d <= J*_upper (dual_viol), the certificate >= the true gap, the plan's raw ball violation.
#
#   BENCH_INSTANCE=natural E71_N=1024 E71_SEEDS=1 julia --project=env scripts/resolution/experiments/e71_budget.jl
#   E71_MODE=merge E71_PARTDIR=<parts> E71_OUT=<json> julia --project=env scripts/resolution/experiments/e71_budget.jl

const MODE71 = get(ENV, "E71_MODE", "run")
using Statistics, Printf, SparseArrays, LinearAlgebra, Random
import JSON

const PARTDIR71 = get(ENV, "E71_PARTDIR", joinpath(@__DIR__, "..", "..", "..", "bench", "irregular", "results", "parts71"))
const OUT71 = get(ENV, "E71_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "e71_budget.json"))

if MODE71 == "run"
    haskey(ENV, "BENCH_INSTANCE") || (ENV["BENCH_INSTANCE"] = "natural")
    haskey(ENV, "BENCH_DISC") || (ENV["BENCH_DISC"] = "zoh")
    haskey(ENV, "BENCH_FLEET") || (ENV["BENCH_FLEET"] = "dronecar")
    include(joinpath(@__DIR__, "e63_time.jl"))
    if get(ENV, "E71_C", "") == "real"           # E74's geometry (mission74, lanes74), nothing else of e74_mission.jl
        let src = read(joinpath(@__DIR__, "e74_mission.jl"), String)
            a = first(findfirst("function radius_edges74", src))
            b = last(findfirst("for c in 1:maximum(inst.class)]", src))
            include_string(Main, src[a:b], joinpath(@__DIR__, "e74_mission.jl"))
        end
    end
end

const N71 = parse(Int, get(ENV, "E71_N", "1024"))
const SEEDS71 = parse.(Int, split(get(ENV, "E71_SEEDS", "1"), ","))
const STEPS71 = parse(Int, get(ENV, "E71_STEPS", "30"))
const DEADLINES71 = parse.(Float64, split(get(ENV, "E71_DEADLINES", "0.2,0.1"), ","))
const RTVARIANTS71 = split(get(ENV, "E71_RT", "auto,admm"), ",")
const BUDGETS71 = parse.(Int, split(get(ENV, "E71_BUDGETS", "1,2,5"), ","))
const RHO71 = parse(Float64, get(ENV, "E71_RHO", "0.1"))
const INIT71 = parse(Int, get(ENV, "E71_INIT", "200"))
const TEAMS71 = split(get(ENV, "E71_TEAMS", "classes,qs8"), ",")
const COLD71 = get(ENV, "E71_COLD", "1") == "1"
const PATHS71 = split(get(ENV, "E71_PATHS", "base"), ",")
const VFP71 = split(get(ENV, "E71_VF_METRICS", "HS,own"), ",")
const VFS71 = split(get(ENV, "E71_VF_STARTS", "cold,shift,team"), ",")
const MIN71 = parse(Int, get(ENV, "E71_MIN", "30"))
const PERIOD71 = 0.2
const RESERVE71 = 1e-3; const GMIN71 = 2e-3; const GMAX71 = 0.05; const GWIN71 = 10
# Overrun rule of arm71 (E106): "none" applies the controller's plan whenever it finishes (E71, E71c, E102);
# "shift" applies, on a step whose time exceeds the deadline, the previously applied plan shifted by one sample
# (its last input repeated), and keeps that shifted plan as the previous plan.
const FALLBACK71 = get(ENV, "E71_FALLBACK", "none")
const FBDEAD71 = parse(Float64, get(ENV, "E71_FALLBACK_DEADLINE", "Inf"))   # canary only: a smaller deadline for the rule
# E71_CERT_IN_STEP=1: a team arm's step is its solve plus the certificate eta (Lemma cert), for the time, the period,
# and the overrun rule; the early-stopped and other non-team arms are unchanged.
const CERTSTEP71 = get(ENV, "E71_CERT_IN_STEP", "0") == "1"

st71(v) = isempty(v) ? Dict{String,Any}() : Dict{String,Any}("median" => median(v), "max" => maximum(v), "min" => minimum(v), "mean" => mean(v), "n" => length(v))

function udist71(u, us)
    num = sum(sum(abs2, u[i] - us[i]) for i in eachindex(u)); den = sum(sum(abs2, v) for v in us)
    return sqrt(num / max(den, 1e-300)), maximum(norm(u[i] - us[i]) for i in eachindex(u))
end

fin71(x) = (x isa Real && !isfinite(x)) ? nothing : x
clean71(x) = x
clean71(x::AbstractFloat) = isfinite(x) ? x : nothing
clean71(x::AbstractDict) = Dict{String,Any}(string(k) => clean71(v) for (k, v) in x)
clean71(x::AbstractVector) = Any[clean71(v) for v in x]
clean71(x::Tuple) = Any[clean71(v) for v in x]

"""Raw and radially projected input vectors of per-agent plans U (nu x H) on cq, and the raw ball violation."""
function proj71(cq, fl, U)
    u = SM.stack_inputs(cq, U); up = copy(u); viol = 0.0
    for i in 1:SM.nagents(fl), t in 0:(fl.H-1)
        ix = SM.uidx(cq, i, t); r = fl.agents[i].input.radius; nr = norm(view(up, ix))
        viol = max(viol, nr - r)
        nr > r && (up[ix] .*= r / nr)
    end
    return u, up, viol
end

"""The Lagrangian dual value at the multipliers z = grad J(w): a lower bound on J* for any w."""
function dual71(cq, fl, w)
    g = cq.H * w .+ cq.q
    s = 0.0
    for i in 1:SM.nagents(fl), t in 0:(fl.H-1)
        s += fl.agents[i].input.radius * norm(view(g, SM.uidx(cq, i, t)))
    end
    return SM.objective(cq, w) - dot(g, w) - s
end

"""
Evaluation of a plan U at the measured state (cq of that state, Cref already stepped there): true gap of the
projected plan, the dual certificate (and its time), optionally Thm. 2 with `teams` (and its time).
"""
function cert71(cq, fl, U, Cref; teams = nothing)
    _, upr, _ = proj71(cq, fl, SM.trajectories(Cref.fp, SM.plan(Cref))[2])
    Jsu = SM.objective(cq, upr); Jsl = dual71(cq, fl, upr)            # J* in [Jsl, Jsu]
    t0 = time_ns()
    u, up, viol = proj71(cq, fl, U)
    Jp = SM.objective(cq, up)
    d = max(dual71(cq, fl, u), dual71(cq, fl, up))
    tc = (time_ns() - t0) / 1e9
    a = abs(Jsu)
    rec = Dict{String,Any}("Jp" => Jp, "Jstar_u" => Jsu, "Jstar_l" => Jsl, "gap" => (Jp - Jsu) / a, "cert" => (Jp - d) / a,
                           "dual_viol" => (d - Jsu) / a, "plan_viol" => viol, "t_cert" => tc,
                           "finite" => isfinite(Jp) && isfinite(d))
    if teams !== nothing
        te = @elapsed begin
            eta = SM.team_certificate(cq, teams, up)[1]
        end
        rec["eta"] = eta / a; rec["t_eta"] = te
    end
    return rec
end

"""Summary of the certificate records of steps >= 1."""
function certsum71(a)
    col(k) = [Float64(r[k]) for r in a if haskey(r, k) && r[k] !== nothing]
    d = Dict{String,Any}("gap" => st71(col("gap")), "cert" => st71(col("cert")), "t_cert" => st71(col("t_cert")),
                         "plan_viol" => st71(col("plan_viol")), "dual_viol_max" => maximum(col("dual_viol")),
                         "cert_below_gap" => count(r -> r["cert"] < r["gap"] - 1e-9, a), "no_cert" => count(r -> !r["finite"], a),
                         "jstar_bracket_rel" => st71([(r["Jstar_u"] - r["Jstar_l"]) / abs(r["Jstar_u"]) for r in a]))
    gs = [r["cert"] / r["gap"] for r in a if r["gap"] > 1e-9]
    d["cert_over_gap"] = st71(gs)
    if haskey(a[1], "eta")
        d["eta"] = st71(col("eta")); d["t_eta"] = st71(col("t_eta"))
        d["eta_below_gap"] = count(r -> r["eta"] < r["gap"] - 1e-9, a)
        es = [r["eta"] / r["gap"] for r in a if r["gap"] > 1e-9]
        d["eta_over_gap"] = st71(es)
    end
    return d
end

"""(a) coordinated MPC stopped at `deadline` per step (see the header)."""
function rt71(sc, Cref, variant, deadline; steps = STEPS71)
    GC.gc()
    C = controller51(sc.fleet)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; over = Float64[]
    pre = 0.0; post = 0.0
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        tl = Inf; guard = NaN
        if k == 0
            info = SM.step!(C, x, refs; terminal = term)           # offline initialization, to tolerance
            if variant == "admm"
                s = C.solver.settings
                s.polish = false; s.adaptive_rho = false; s.warm_reset_rho = false; s.method = :admm
            end
        else
            guard = isempty(over) ? GMIN71 : clamp(maximum(over[max(1, end - GWIN71 + 1):end]), GMIN71, GMAX71)
            tl = max(deadline - pre - post - RESERVE71 - guard, 1e-6)
            C.solver.settings.time_limit = tl
            C.solver.info.status = :solved                          # warm start from the (possibly stopped) iterate, shifted
            info = SM.step!(C, x, refs; terminal = term)
            C.solver.settings.time_limit = Inf
            push!(over, max(info.t_solve - tl, 0.0))
        end
        pre = info.t_construct + info.t_setup; post = info.t_lift
        tt = info.t_total
        u = [copy(v) for v in info.u]
        Jp = SM.objective(C.fp.program, SM.plan(C))
        st = string(info.status); it = info.iter; ipm = C.solver.info.ipm_iter; meth = string(C.solver.info.method)
        Uc = SM.trajectories(C.fp, SM.plan(C))[2]
        Js = jstar52!(Cref, x, refs, term)
        us = [copy(v) for v in Cref.info.u]
        cq = SM.CondensedQP(sc.fleet, x, refs; terminal = term)
        cr = cert71(cq, sc.fleet, Uc, Cref)
        cr["in_time"] = tt + cr["t_cert"] <= deadline
        ucr, _ = clip26(sc, us)
        uc, viol = clip26(sc, u)
        drel, dmax = udist71(uc, ucr)
        cost += stage_cost26(sc, x, uc, refs)
        cq = nothing; GC.gc()
        push!(rec, Dict{String,Any}("step" => k, "t_total" => tt, "t_solve" => info.t_solve, "limit" => fin71(tl), "guard" => fin71(guard), "cert" => cr,
                                    "met" => tt <= deadline, "met_period" => tt <= PERIOD71, "status" => st, "iter" => it, "ipm_iter" => ipm,
                                    "method" => meth, "sub" => (Jp - Js) / abs(Js), "u_rel" => drel, "u_max" => dmax, "viol" => viol))
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(key) = [Float64(r[key]) for r in a]
    return Dict{String,Any}("variant" => variant, "deadline" => deadline, "closed_loop_cost" => cost,
        "t_total" => st71(col("t_total")), "met_frac" => count(r -> r["met"], a) / length(a),
        "met_period_frac" => count(r -> r["met_period"], a) / length(a),
        "sub" => st71(col("sub")), "u_rel" => st71(col("u_rel")), "u_max" => st71(col("u_max")), "viol" => st71(col("viol")),
        "status_counts" => Dict(s => count(r -> r["status"] == s, a) for s in unique(r["status"] for r in a)),
        "methods" => Dict(s => count(r -> r["method"] == s, a) for s in unique(r["method"] for r in a)),
        "iter" => st71(col("iter")), "certified" => certsum71([r["cert"] for r in a]),
        "cert_in_time_frac" => count(r -> r["cert"]["in_time"], a) / length(a), "steps" => rec)
end

"""(b) consensus ADMM over the vehicles, b iterations per sample; `init` iterations at step 0 (0: b from cold)."""
function admm71(sc, Q, Cref, b, init; steps = STEPS71)
    GC.gc()
    M = Admm52("full", sc, Q, RHO71; budget = b, warm = :shift)
    nag = length(M.D.locals)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        M.D.budget = (k == 0 && init > 0) ? init : b
        u, info, J, tg, rounds, floats = astep52!(M, sc, x, refs, term)
        Ua = SM.trajectories(M.D.fp, SM.plan(M.D))[2]
        Js = jstar52!(Cref, x, refs, term)
        us = [copy(v) for v in Cref.info.u]
        cq = SM.CondensedQP(sc.fleet, x, refs; terminal = term)
        cr = cert71(cq, sc.fleet, Ua, Cref; teams = collect(1:sc.n))
        cq = nothing; GC.gc()
        par = (info.t_total - info.t_solve) / nag + M.D.t_parallel + tg
        uc, viol = clip26(sc, u)
        ucr, _ = clip26(sc, us)
        drel, _ = udist71(uc, ucr)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "sub" => (J - Js) / abs(Js), "seq" => info.t_total + tg, "par" => par,
                                    "rounds" => rounds, "floats" => floats, "status" => string(info.status), "viol" => viol, "u_rel" => drel, "cert" => cr))
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(key) = [Float64(r[key]) for r in a]
    return Dict{String,Any}("budget" => b, "init" => init, "rho" => RHO71, "agents" => nag, "closed_loop_cost" => cost,
        "seq" => st71(col("seq")), "par" => st71(col("par")), "met_par_frac" => count(r -> r["par"] <= PERIOD71, a) / length(a),
        "met_seq_frac" => count(r -> r["seq"] <= PERIOD71, a) / length(a), "rounds" => a[end]["rounds"],
        "floats" => st71(col("floats")), "sub" => st71(col("sub")), "u_rel" => st71(col("u_rel")), "viol" => st71(col("viol")),
        "certified" => certsum71([r["cert"] for r in a]), "steps" => rec)
end

function team71(sc, lab, Cref; steps = STEPS71)
    GC.gc()
    tb = @elapsed (Q = Quot51(sc, lab); C = controller51(Q.fleet))
    GC.gc()
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        t0 = time_ns()
        xq, rq, tq = teamdata51(Q, sc, x, refs, term)
        info = SM.step!(C, xq, rq; terminal = tq)
        u = [copy(info.u[Q.team[i]]) for i in 1:sc.n]
        tt = (time_ns() - t0) / 1e9
        Uq = SM.trajectories(C.fp, SM.plan(C))[2]
        U = [copy(Uq[Q.team[i]]) for i in 1:sc.n]
        jstar52!(Cref, x, refs, term)
        cq = SM.CondensedQP(sc.fleet, x, refs; terminal = term)
        cr = cert71(cq, sc.fleet, U, Cref; teams = lab)
        cr["in_time"] = tt + cr["t_eta"] <= PERIOD71
        cq = nothing
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "t_total" => tt, "t_solve" => info.t_solve, "status" => string(info.status), "viol" => viol, "cert" => cr))
        x = plant26(sc, x, uc)
        GC.gc()
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; v = [r["t_total"] for r in a]
    return Dict{String,Any}("closed_loop_cost" => cost, "t_total" => st71(v), "met_frac" => count(<=(PERIOD71), v) / length(v),
                            "teams" => length(Q.teams), "build_seconds" => tb, "certified" => certsum71([r["cert"] for r in a]),
                            "cert_in_time_frac" => count(r -> r["cert"]["in_time"], a) / length(a), "steps" => rec)
end

function coord71(sc; steps = STEPS71)
    GC.gc()
    out, _ = loop51(sc, controller51(sc.fleet), nothing; steps = steps)
    v = [s["t_total"] for s in out["steps"][2:end]]
    out["met_frac"] = count(<=(PERIOD71), v) / length(v)
    return out
end

function run71(seed; n = N71, steps = STEPS71, quiet = false, deadlines = DEADLINES71, budgets = BUDGETS71, teams = TEAMS71, init = INIT71)
    inst = sq_instance(n, seed)
    lab0, _ = sq_teams(inst, "classes", seed)
    sc = scenario63(inst, seed, lab0)
    res = Dict{String,Any}("seed" => seed, "n_requested" => n, "n" => length(inst.kinds), "edges" => length(inst.edges),
                           "steps" => steps, "period" => PERIOD71, "load_start" => loadavg26(), "controllers" => Dict{String,Any}())
    R = res["controllers"]
    R["coord"] = coord71(sc; steps = steps); Jc = R["coord"]["closed_loop_cost"]
    quiet || @printf("seed %d n %d coord cost %.6e ms med %.1f max %.1f\n", seed, res["n"], Jc, ms26(R["coord"]["t_total"]["median"]), ms26(R["coord"]["t_total"]["max"]))
    Cref = central52(sc.fleet)
    for ch in teams
        lab, _ = sq_teams(inst, ch, seed)
        o = team71(sc, lab, Cref; steps = steps); o["cost_ratio"] = o["closed_loop_cost"] / Jc
        R["team_$ch"] = o
        quiet || @printf("  team_%-8s ratio %.4f ms med %.1f max %.1f met %.2f\n", ch, o["cost_ratio"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), o["met_frac"])
        flush(stdout)
    end
    for v in RTVARIANTS71, d in deadlines
        o = rt71(sc, Cref, v, d; steps = steps); o["cost_ratio"] = o["closed_loop_cost"] / Jc
        R[@sprintf("rt_%s_%dms", v, round(Int, 1e3d))] = o
        quiet || @printf("  rt %-4s %3d ms ratio %.4f ms med %.1f max %.1f met %.2f sub med %.2e max %.2e urel med %.2e\n", v, round(Int, 1e3d),
                         o["cost_ratio"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), o["met_frac"], o["sub"]["median"], o["sub"]["max"], o["u_rel"]["median"])
        @printf("      certified: gap med %.2e max %.2e  cert med %.2e max %.2e  t_cert med %.1f ms  below %d dualviol %.1e\n", o["certified"]["gap"]["median"],
                o["certified"]["gap"]["max"], o["certified"]["cert"]["median"], o["certified"]["cert"]["max"], ms26(o["certified"]["t_cert"]["median"]),
                o["certified"]["cert_below_gap"], o["certified"]["dual_viol_max"])
        flush(stdout)
    end
    Q = Quot51(sc, lab0)
    for b in budgets, ini in (COLD71 ? (init, 0) : (init,))
        o = admm71(sc, Q, Cref, b, ini; steps = steps); o["cost_ratio"] = o["closed_loop_cost"] / Jc
        R["admm_b$(b)" * (ini > 0 ? "_init" : "")] = o
        quiet || @printf("  admm b %d init %d ratio %.4f par med %.1f max %.1f seq med %.1f floats %.3g sub med %.2e\n", b, ini, o["cost_ratio"],
                         ms26(o["par"]["median"]), ms26(o["par"]["max"]), ms26(o["seq"]["median"]), o["floats"]["median"], o["sub"]["median"])
        flush(stdout)
    end
    res["load_end"] = loadavg26()
    return res
end


# ---------------------------------------------------------------------------------------------------------------
# V-FISTA in a block metric (E72's (C)), on the package's condensed QP, stopped at a wall-clock budget
# ---------------------------------------------------------------------------------------------------------------

"""The condensed linear term q at a state (free responses only; the Hessian is constant, built offline)."""
function qdata71(fl, off, x0, refs, term)
    n = SM.nagents(fl); H = fl.H
    resp = [SM._condense_agent(ag, x0[i], H) for (i, ag) in enumerate(fl.agents)]
    q = zeros(off[end])
    for (i, ag) in enumerate(fl.agents)
        fs, Ms = resp[i]; R = refs[i]; qi = view(q, off[i]+1:off[i+1])
        for t in 1:(H-1)
            a = ag.Cr * Ms[t]; b = ag.Cr * fs[t] - view(R, :, t + 1)
            qi .+= a' * (ag.Q * b)
        end
        rf = term === nothing ? view(R, :, H + 1) : term[i]
        a = ag.Cf * Ms[H]; b = ag.Cf * fs[H] - rf
        qi .+= a' * (ag.Qf * b)
    end
    for (k, (i, j)) in enumerate(fl.edges)
        S = fl.select[k]; fi, Mi = resp[i]; fj, Mj = resp[j]
        Ci = S * fl.agents[i].C; Cj = S * fl.agents[j].C
        for t in 1:H
            (fl.present[k, t] && fl.weights[k, t] > 0) || continue
            w = fl.weights[k, t]
            b = Cj * fj[t] - Ci * fi[t] - S * fl.targets[:, k, t]
            q[off[i]+1:off[i+1]] .+= w .* ((-Ci * Mi[t])' * b); q[off[j]+1:off[j+1]] .+= w .* ((Cj * Mj[t])' * b)
        end
    end
    return q
end

struct VF71
    H::SparseMatrixCSC{Float64,Int}
    off::Vector{Int}
    parts::Vector{Vector{Int}}
    dense::Vector{Matrix{Float64}}
    lmax::Vector{Float64}
    balls::Vector{Vector{Tuple{UnitRange{Int},Float64}}}
    blocks::Vector{UnitRange{Int}}
    um::Vector{Float64}
    kb::Float64
    lab::Vector{Int}
end

"""Offline: the metric's parts (P = H_S of the teams `lab`; singleton teams: own Hessians) and kb."""
function VF71(cq, fl, lab)
    n = SM.nagents(fl); H = fl.H
    off = [cq.off; length(cq.q)]
    lab = SM.canonical_partition(lab); k = maximum(lab)
    mem = [findall(==(c), lab) for c in 1:k]
    parts = Vector{Int}[]; dense = Matrix{Float64}[]; balls = Vector{Tuple{UnitRange{Int},Float64}}[]
    for m in mem
        loc = cumsum([0; [off[i+1] - off[i] for i in m]])
        HS = zeros(loc[end], loc[end]); pos = Dict(i => a for (a, i) in enumerate(m))
        for (a, i) in enumerate(m)
            HS[loc[a]+1:loc[a+1], loc[a]+1:loc[a+1]] .+= cq.H0[i]
        end
        if length(m) > 1
            for (i, j, Hii, Hij, Hjj) in cq.edge_terms
                (haskey(pos, i) && haskey(pos, j)) || continue
                a, b = pos[i], pos[j]; ri = loc[a]+1:loc[a+1]; rj = loc[b]+1:loc[b+1]
                HS[ri, ri] .+= Hii; HS[rj, rj] .+= Hjj; HS[ri, rj] .+= Hij; HS[rj, ri] .+= Hij'
            end
        end
        push!(parts, reduce(vcat, [collect(off[i]+1:off[i+1]) for i in m])); push!(dense, HS)
        bl = Tuple{UnitRange{Int},Float64}[]
        for (a, i) in enumerate(m), t in 0:(H-1)
            nu = fl.agents[i].nu
            push!(bl, (loc[a] + t * nu + 1:loc[a] + (t + 1) * nu, fl.agents[i].input.radius))
        end
        push!(balls, bl)
    end
    blocks = [SM.uidx(cq, i, t) for i in 1:n for t in 0:(H-1)]
    um = [fl.agents[i].input.radius for i in 1:n for t in 0:(H-1)]
    Ls = [cholesky(Symmetric(D)).L for D in dense]
    lmax = [eigmax(Symmetric(D)) for D in dense]
    N = length(cq.q)
    Linv(y) = (z = zeros(N); for (c, L) in zip(parts, Ls); z[c] .= L \ y[c]; end; z)
    Linvt(y) = (z = zeros(N); for (c, L) in zip(parts, Ls); z[c] .= L' \ y[c]; end; z)
    x = randn(Xoshiro(3), N); x ./= norm(x); lam = 0.0
    for _ in 1:100
        y = Linv(cq.H * Linvt(x)); lam = dot(x, y); x = y / norm(y)
    end
    return VF71(cq.H, off, parts, dense, lmax, balls, blocks, um, 1.05 * lam, lab)
end

function projvf71!(v, V::VF71)
    @inbounds for (k, b) in enumerate(V.blocks)
        nb = norm(view(v, b)); nb > V.um[k] && (v[b] .*= V.um[k] / nb)
    end
    return v
end

"""V-FISTA from u0 until the predicted end of the next iteration passes `tend` (time_ns); the best iterate."""
function vfista71!(V::VF71, q, u0, tend::UInt64, titer::Ref{Float64})
    beta = (sqrt(V.kb) - 1) / (sqrt(V.kb) + 1)
    x = projvf71!(copy(u0), V); Hx = V.H * x; y = copy(x); Hy = copy(Hx)
    fbest = 0.5 * dot(x, Hx) + dot(q, x); best = copy(x); xn = copy(x); k = 0
    while time_ns() + round(UInt64, 1e9 * titer[]) < tend
        ti = time_ns()
        gy = Hy .+ q
        for (p, c) in enumerate(V.parts)
            v = xn[c]
            proxpart72_!(v, gy[c], y[c], V.dense[p], V.kb, V.lmax[p], V.balls[p], MIN71)
            xn[c] = v
        end
        projvf71!(xn, V)
        Hxn = V.H * xn; f = 0.5 * dot(xn, Hxn) + dot(q, xn)
        f < fbest && (fbest = f; best .= xn)
        yn = xn .+ beta .* (xn .- x); Hy = Hxn .+ beta .* (Hxn .- Hx); y = yn
        x = copy(xn); Hx = Hxn; k += 1
        titer[] = (time_ns() - ti) / 1e9
    end
    return best, k
end

"""E72's block prox: min q'(v - y) + kb/2 (v - y)'Pm(v - y) over the part's balls, m_in FISTA steps from v."""
function proxpart72_!(v, q, y, Pm, kb, lmax, balls, m_in)
    st = 1 / (kb * lmax)
    z = copy(v); vo = copy(v); t = 1.0
    w = similar(v); gz = similar(v)
    for _ in 1:m_in
        mul!(gz, Pm, z .- y)
        @. w = z - st * (q + kb * gz)
        for (rg, r) in balls
            nb = norm(view(w, rg)); nb > r && (w[rg] .*= r / nb)
        end
        tn = (1 + sqrt(1 + 4t^2)) / 2; bt = (t - 1) / tn
        @. z = w + bt * (w - vo)
        vo .= w; t = tn
    end
    v .= vo
    return v
end

"""Shift a stacked plan one instant earlier (the last instant repeated)."""
function shiftu71(V::VF71, fl, u)
    v = similar(u); H = fl.H
    for i in 1:SM.nagents(fl)
        nu = fl.agents[i].nu; o = V.off[i]
        for t in 0:(H-1)
            s = min(t + 1, H - 1)
            v[o+t*nu+1:o+(t+1)*nu] .= u[o+s*nu+1:o+(s+1)*nu]
        end
    end
    return v
end

"""(vf) V-FISTA closed loop with metric teams `mlab`, start cold/shift/team, deadline per step."""
function vf71(sc, Cref, V::VF71, start, labreg; deadline = PERIOD71, steps = STEPS71)
    GC.gc()
    fl = sc.fleet
    Qt = start == "team" ? Quot51(sc, labreg) : nothing
    Ct = start == "team" ? controller51(Qt.fleet) : nothing
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; over = Float64[]
    titer = Ref(0.0); uprev = zeros(V.off[end])
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        guard = isempty(over) ? GMIN71 : clamp(maximum(over[max(1, end - GWIN71 + 1):end]), GMIN71, GMAX71)
        t0 = time_ns()
        tend = k == 0 ? t0 + round(UInt64, 60e9) : t0 + round(UInt64, 1e9 * (deadline - RESERVE71 - guard))
        q = qdata71(fl, V.off, x, refs, term)
        tq = (time_ns() - t0) / 1e9; tt_team = 0.0
        if start == "cold"
            u0 = zeros(length(q))
        elseif start == "shift"
            u0 = k == 0 ? zeros(length(q)) : shiftu71(V, fl, uprev)
        else
            t1 = time_ns()
            xq, rq, tq_ = teamdata51(Qt, sc, x, refs, term)
            SM.step!(Ct, xq, rq; terminal = tq_)
            Uq = SM.trajectories(Ct.fp, SM.plan(Ct))[2]
            u0 = zeros(length(q))
            for i in 1:sc.n, t in 0:(fl.H-1)
                nu = fl.agents[i].nu
                u0[V.off[i]+t*nu+1:V.off[i]+(t+1)*nu] .= view(Uq[Qt.team[i]], :, t + 1)
            end
            tt_team = (time_ns() - t1) / 1e9
        end
        if k == 0
            # step 0: the offline initialization (untimed): MIN71-inner V-FISTA for at most 60 s or 2000 iterations
            u = projvf71!(copy(u0), V); it = 0
            tlim = time_ns() + round(UInt64, 60e9); Tr = Ref(0.0)
            while it < 2000 && time_ns() < tlim
                u, k1 = vfista71!(V, q, u, time_ns() + round(UInt64, 1e9 * max(0.5, 3 * Tr[])), Tr); it += k1
                k1 == 0 && break
            end
            titer[] = Tr[]
        else
            u, it = vfista71!(V, q, u0, tend, titer)
        end
        tt = (time_ns() - t0) / 1e9
        k >= 1 && push!(over, max(tt - (deadline - RESERVE71), 0.0))
        uprev = copy(u)
        U = [reshape(u[V.off[i]+1:V.off[i+1]], fl.agents[i].nu, fl.H) for i in 1:sc.n]
        uapp = [copy(U[i][:, 1]) for i in 1:sc.n]
        jstar52!(Cref, x, refs, term)
        cq = SM.CondensedQP(fl, x, refs; terminal = term)
        qerr = norm(cq.q - q) / max(norm(cq.q), 1e-300)
        cr = cert71(cq, fl, U, Cref; teams = labreg)
        cr["in_time"] = tt + cr["t_cert"] <= deadline
        cq = nothing
        uc, viol = clip26(sc, uapp)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "t_total" => tt, "t_q" => tq, "t_team" => tt_team, "iters" => it, "guard" => guard,
                                    "met" => tt <= deadline, "q_err" => qerr, "viol" => viol, "cert" => cr))
        x = plant26(sc, x, uc)
        GC.gc()
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(key) = [Float64(r[key]) for r in a]
    return Dict{String,Any}("start" => start, "kb" => V.kb, "parts" => length(V.parts), "m_in" => MIN71, "closed_loop_cost" => cost,
        "t_total" => st71(col("t_total")), "t_q" => st71(col("t_q")), "t_team" => st71(col("t_team")), "iters" => st71(col("iters")),
        "met_frac" => count(r -> r["met"], a) / length(a), "q_err_max" => maximum(col("q_err")),
        "certified" => certsum71([r["cert"] for r in a]), "cert_in_time_frac" => count(r -> r["cert"]["in_time"], a) / length(a),
        "steps" => rec)
end

function runvf71(seed; n = N71, steps = STEPS71, quiet = false)
    inst = sq_instance(n, seed)
    labreg, _ = sq_teams(inst, "classes", seed)
    sc = scenario63(inst, seed, labreg)
    res = Dict{String,Any}("seed" => seed, "n_requested" => n, "n" => length(inst.kinds), "edges" => length(inst.edges),
                           "steps" => steps, "period" => PERIOD71, "load_start" => loadavg26(), "controllers" => Dict{String,Any}())
    R = res["controllers"]
    co = coord71(sc; steps = steps); Jc = co["closed_loop_cost"]; co["cost_ratio"] = 1.0
    R["coord_vfjob"] = co
    Cref = central52(sc.fleet)
    x0 = start26(sc); refs0, term0 = references26(sc, 0.0)
    cq0 = SM.CondensedQP(sc.fleet, x0, refs0; terminal = term0)
    for P in VFP71
        tb = @elapsed (V = VF71(cq0, sc.fleet, P == "HS" ? labreg : collect(1:sc.n)))
        for st in VFS71
            o = vf71(sc, Cref, V, st, labreg; steps = steps)
            o["cost_ratio"] = o["closed_loop_cost"] / Jc; o["build_seconds"] = tb
            R["vf_$(P)_$st"] = o
            quiet || @printf("  vf %-3s %-5s kb %.2f ratio %.4f ms med %.1f max %.1f met %.2f iters med %.0f gap med %.2e cert med %.2e eta med %.2e qerr %.1e\n",
                             P, st, V.kb, o["cost_ratio"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), o["met_frac"],
                             o["iters"]["median"], o["certified"]["gap"]["median"], o["certified"]["cert"]["median"],
                             o["certified"]["eta"]["median"], o["q_err_max"])
            flush(stdout)
        end
    end
    res["load_end"] = loadavg26()
    return res
end

function main71()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR71)
    "base" in PATHS71 && run71(1; n = 32, steps = 3, quiet = true, budgets = [1], init = 5)          # warm-up (compile every path)
    "vf" in PATHS71 && runvf71(1; n = 32, steps = 3, quiet = true)
    for seed in SEEDS71, pth in PATHS71
        res = pth == "vf" ? runvf71(seed) : run71(seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(), "affinity" => get(ENV, "E71_AFFINITY", ""))
        path = joinpath(PARTDIR71, @sprintf("e71%s_n%d_seed%d.json", pth == "vf" ? "vf" : "", N71, seed))
        open(io -> JSON.print(io, clean71(res), 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

med71(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : median(w))
max71(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : maximum(w))

"""Certificate summary over seeds (medians of per-seed medians, worst of per-seed maxima)."""
function certmerge71(ps)
    c = [q["certified"] for q in ps]
    g(k, s) = [get(get(x, k, Dict()), s, nothing) for x in c]
    d = Dict{String,Any}("gap_med" => med71(g("gap", "median")), "gap_max" => max71(g("gap", "max")),
                         "cert_med" => med71(g("cert", "median")), "cert_max" => max71(g("cert", "max")),
                         "cert_over_gap_med" => med71(g("cert_over_gap", "median")),
                         "t_cert_ms_med" => (m = med71(g("t_cert", "median")); m === nothing ? nothing : 1e3m),
                         "plan_viol_max" => max71(g("plan_viol", "max")), "dual_viol_max" => max71([x["dual_viol_max"] for x in c]),
                         "cert_below_gap" => sum(x["cert_below_gap"] for x in c), "no_cert_steps" => sum(x["no_cert"] for x in c),
                         "jstar_bracket_max" => max71(g("jstar_bracket_rel", "max")))
    if haskey(c[1], "eta")
        d["eta_med"] = med71(g("eta", "median")); d["eta_max"] = max71(g("eta", "max"))
        d["eta_over_gap_med"] = med71(g("eta_over_gap", "median"))
        d["t_eta_ms_med"] = 1e3 * med71(g("t_eta", "median")); d["t_eta_ms_max"] = 1e3 * max71(g("t_eta", "max"))
        d["eta_below_gap"] = sum(x["eta_below_gap"] for x in c)
    end
    haskey(ps[1], "cert_in_time_frac") && (d["cert_in_time_frac"] = mean(q["cert_in_time_frac"] for q in ps))
    return d
end

function merge71()
    raw = [JSON.parsefile(f) for f in readdir(PARTDIR71; join = true) if endswith(f, ".json")]
    isempty(raw) && error("no parts in $PARTDIR71")
    byk = Dict{Tuple{Int,Int},Any}()
    for p in raw
        key = (p["n_requested"], p["seed"])
        if haskey(byk, key)
            q = byk[key]
            merge!(q["controllers"], p["controllers"])
            q["meta"]["host"] = string(q["meta"]["host"], "+", p["meta"]["host"]); q["meta"]["job"] = string(q["meta"]["job"], "+", p["meta"]["job"])
        else
            byk[key] = p
        end
    end
    parts = collect(values(byk))
    out = Dict{String,Any}("experiment" => "E71 equal time budget on the natural irregular formation (E63): early-stopped coordinated MPC, consensus ADMM, team MPC, converged coordinated MPC; certified gaps",
                           "period_ms" => 1e3 * PERIOD71, "sizes" => Dict{String,Any}())
    for nreq in sort!(unique([p["n_requested"] for p in parts]))
        P = [p for p in parts if p["n_requested"] == nreq]
        S = Dict{String,Any}("seeds" => [p["seed"] for p in P], "n" => [p["n"] for p in P], "steps" => P[1]["steps"],
                             "hosts" => [p["meta"]["host"] for p in P], "cpu" => unique([p["meta"]["cpu"] for p in P]),
                             "affinity" => [p["meta"]["affinity"] for p in P], "jobs" => [p["meta"]["job"] for p in P],
                             "load" => [[p["load_start"], p["load_end"]] for p in P], "controllers" => Dict{String,Any}())
        for key in unique(reduce(vcat, [collect(keys(p["controllers"])) for p in P]))
            ps = [p["controllers"][key] for p in P if haskey(p["controllers"], key)]
            d = Dict{String,Any}("seeds" => length(ps))
            d["cost_ratio_med"] = key == "coord" ? 1.0 : median([get(q, "cost_ratio", NaN) for q in ps])
            d["cost_ratio_max"] = key == "coord" ? 1.0 : maximum([get(q, "cost_ratio", NaN) for q in ps])
            d["cost_med"] = median([q["closed_loop_cost"] for q in ps])
            if startswith(key, "admm")
                d["par_ms_med"] = 1e3 * median([q["par"]["median"] for q in ps]); d["par_ms_max"] = 1e3 * maximum([q["par"]["max"] for q in ps])
                d["seq_ms_med"] = 1e3 * median([q["seq"]["median"] for q in ps]); d["seq_ms_max"] = 1e3 * maximum([q["seq"]["max"] for q in ps])
                d["met_par_frac"] = mean([q["met_par_frac"] for q in ps]); d["met_seq_frac"] = mean([q["met_seq_frac"] for q in ps])
                d["rounds"] = ps[1]["rounds"]; d["floats_med"] = median([q["floats"]["median"] for q in ps])
                d["sub_med"] = median([q["sub"]["median"] for q in ps]); d["sub_max"] = maximum([q["sub"]["max"] for q in ps])
                d["u_rel_med"] = median([q["u_rel"]["median"] for q in ps]); d["budget"] = ps[1]["budget"]; d["init"] = ps[1]["init"]
            else
                d["ms_med"] = 1e3 * median([q["t_total"]["median"] for q in ps]); d["ms_max"] = 1e3 * maximum([q["t_total"]["max"] for q in ps])
                d["met_frac"] = mean([q["met_frac"] for q in ps])
                d["rounds"] = 2; d["floats_per_sample"] = 9 * median(S["n"])
                if startswith(key, "rt")
                    d["met_period_frac"] = mean([q["met_period_frac"] for q in ps])
                    d["sub_med"] = median([q["sub"]["median"] for q in ps]); d["sub_max"] = maximum([q["sub"]["max"] for q in ps])
                    d["u_rel_med"] = median([q["u_rel"]["median"] for q in ps]); d["u_rel_max"] = maximum([q["u_rel"]["max"] for q in ps])
                    d["viol_max"] = maximum([q["viol"]["max"] for q in ps])
                elseif startswith(key, "team")
                    d["teams_med"] = median([q["teams"] for q in ps])
                elseif startswith(key, "vf")
                    d["iters_med"] = median([q["iters"]["median"] for q in ps]); d["iters_min"] = minimum([q["iters"]["min"] for q in ps])
                    d["kb_med"] = median([q["kb"] for q in ps]); d["parts_med"] = median([q["parts"] for q in ps])
                    d["t_team_ms_med"] = 1e3 * median([q["t_team"]["median"] for q in ps]); d["q_err_max"] = maximum([q["q_err_max"] for q in ps])
                elseif key == "coord_vfjob"
                    d["cost_vs_coord_max"] = maximum([abs(p["controllers"]["coord_vfjob"]["closed_loop_cost"] / p["controllers"]["coord"]["closed_loop_cost"] - 1)
                                                      for p in P if haskey(p["controllers"], "coord") && haskey(p["controllers"], "coord_vfjob")]; init = 0.0)
                end
            end
            haskey(ps[1], "certified") && (d["certified"] = certmerge71(ps))
            S["controllers"][key] = d
        end
        out["sizes"][string(nreq)] = S
    end
    open(io -> JSON.print(io, clean71(out), 1), OUT71, "w")
    println("wrote $OUT71")
    for (n, S) in out["sizes"], (k, d) in sort!(collect(S["controllers"]); by = first)
        @printf("n%s %-16s %s\n", n, k, JSON.json(clean71(d)))
    end
end

# ===============================================================================================================
# E71c: realistic formations of E74 (lossless teams phi*) and response teams (E79) on the irregular formation.
#
#   E71_C=real E71_VARIANT=<E1t|Ccyl|C1|L26bal> E71_N=<1024|4096|16384>: arms
#     rt_admm      early-stopped coordinated MPC (ADMM only, warm from the shifted iterate), as rt71
#     team_phi     team MPC on phi* (colour refinement of the classes, within = false; lossless), default accuracy
#     hyb_phi      the same team solve, then V-FISTA in the H_S(phi*) metric from the team plan for the rest of
#                  the budget (sparse H_S; prox per team by E71_MIN inner FISTA steps)
#     reference    team MPC on phi* solved to 1e-9 (exact: phi* is lossless), per step J* and the closed loop (the
#                  converged cost); at N <= E71_COORDN also coordinated MPC (default accuracy) and J* of the tight
#                  central solve at every step of the reference loop (check of losslessness)
#   E71_C=resp: on the irregular (natural) formation, response teams (E79's resp: k-means of the unconstrained
#     centralized plans of E71_R random coherent data sets in the members' own-Hessian metric, inside each class,
#     team counts of qs8 and qs2 allocated by DP): team_resp<K> and hyb_resp<K> (V-FISTA in H_S(resp) from the
#     team plan); reference: coordinated MPC (closed loop) and the tight central solve (J* per step)
#
# Certificates per step (on the condensed QP, H built once, q and c at the measured state):
#   gap       J(u_p) - J*, u_p the plan projected onto the balls
#   dual      J(u_p) - max d(w), d the Lagrangian dual at z = grad J(w), w in {raw plan, u_p}
#   kkt       E72's certificate at u_p with its own KKT normals in the H_S metric (H_S of the arm's teams; phi*
#             for rt_admm): 1/2 g'H_S^{-1}g + eps(n), g = grad J(u_p) + n, n_b = max(0, -g_b'w) w on active balls
# ===============================================================================================================

const C71 = get(ENV, "E71_C", "")
const VARIANT71 = get(ENV, "E71_VARIANT", "C1")
const RTSKIP71 = split(get(ENV, "E71_RT_SKIP", "L26bal@16384"), ",")
const RESPQ71 = split(get(ENV, "E71_RESP_Q", "qs8,qs2"), ",")
const R71 = parse(Int, get(ENV, "E71_R", "24"))
const COORDN71 = parse(Int, get(ENV, "E71_COORDN", "4096"))
const CARMS71 = split(get(ENV, "E71_ARMS", "rt_admm,team,hyb"), ",")

"""Condensed q and c at a state (H constant): the q and c of SM.CondensedQP without the Hessian."""
function qc71(fl, off, x0, refs, term)
    H = fl.H
    resp = [SM._condense_agent(ag, x0[i], H) for (i, ag) in enumerate(fl.agents)]
    q = zeros(off[end]); c = 0.0
    for (i, ag) in enumerate(fl.agents)
        fs, Ms = resp[i]; R = refs[i]; qi = view(q, off[i]+1:off[i+1])
        e0 = ag.Cr * x0[i] - view(R, :, 1); c += 0.5 * dot(e0, ag.Q * e0)
        for t in 1:(H-1)
            a = ag.Cr * Ms[t]; b = ag.Cr * fs[t] - view(R, :, t + 1)
            qi .+= a' * (ag.Q * b); c += 0.5 * dot(b, ag.Q * b)
        end
        rf = term === nothing ? view(R, :, H + 1) : term[i]
        a = ag.Cf * Ms[H]; b = ag.Cf * fs[H] - rf
        qi .+= a' * (ag.Qf * b); c += 0.5 * dot(b, ag.Qf * b)
    end
    for (k, (i, j)) in enumerate(fl.edges)
        S = fl.select[k]; fi, Mi = resp[i]; fj, Mj = resp[j]
        Ci = S * fl.agents[i].C; Cj = S * fl.agents[j].C
        for t in 1:H
            (fl.present[k, t] && fl.weights[k, t] > 0) || continue
            w = fl.weights[k, t]
            b = Cj * fj[t] - Ci * fi[t] - S * fl.targets[:, k, t]
            q[off[i]+1:off[i+1]] .+= w .* ((-Ci * Mi[t])' * b); q[off[j]+1:off[j+1]] .+= w .* ((Cj * Mj[t])' * b)
            c += 0.5 * w * dot(b, b)
        end
    end
    return q, c
end

"""The constant structure: H, offsets, balls, and H_S metrics (sparse, block diagonal) per team map."""
struct Ev71
    fl::Any
    H::SparseMatrixCSC{Float64,Int}
    off::Vector{Int}
    blocks::Vector{UnitRange{Int}}
    um::Vector{Float64}
    H0::Vector{Matrix{Float64}}
    edge_terms::Vector{Tuple{Int,Int,Matrix{Float64},Matrix{Float64},Matrix{Float64}}}
end

function Ev71(sc)
    fl = sc.fleet; x = start26(sc); refs, term = references26(sc, 0.0)
    cq = SM.CondensedQP(fl, x, refs; terminal = term)
    off = [cq.off; length(cq.q)]
    n = SM.nagents(fl)
    blocks = [off[i] + t * fl.agents[i].nu + 1:off[i] + (t + 1) * fl.agents[i].nu for i in 1:n for t in 0:(fl.H-1)]
    um = [fl.agents[i].input.radius for i in 1:n for t in 0:(fl.H-1)]
    q, c = qc71(fl, off, x, refs, term)
    @assert norm(q - cq.q) <= 1e-9 * max(norm(cq.q), 1.0) && abs(c - cq.c) <= 1e-9 * max(abs(cq.c), 1.0) "qc71 disagrees with CondensedQP"
    return Ev71(fl, cq.H, off, blocks, um, cq.H0, cq.edge_terms)
end

"""H_S of a team map (own Hessians and the edges inside teams), sparse, block diagonal by team; its factor; parts."""
function hs71(E::Ev71, lab)
    lab = SM.canonical_partition(lab)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    function put!(ri, rj, B)
        for b in axes(B, 2), a in axes(B, 1)
            B[a, b] == 0 && continue
            push!(I_, ri[a]); push!(J_, rj[b]); push!(V_, B[a, b])
        end
    end
    rng(i) = E.off[i]+1:E.off[i+1]
    for i in eachindex(lab)
        put!(rng(i), rng(i), E.H0[i])
    end
    for (i, j, Hii, Hij, Hjj) in E.edge_terms
        lab[i] == lab[j] || continue
        put!(rng(i), rng(i), Hii); put!(rng(j), rng(j), Hjj); put!(rng(i), rng(j), Hij); put!(rng(j), rng(i), Matrix(Hij'))
    end
    N = E.off[end]
    HS = sparse(I_, J_, V_, N, N)
    HS = (HS + HS') / 2
    F = cholesky(Symmetric(HS))
    parts = [reduce(vcat, [collect(rng(i)) for i in findall(==(c), lab)]) for c in 1:maximum(lab)]
    return (HS = HS, F = F, parts = parts, lab = lab)
end

projE71!(v, E::Ev71) = (for (k, b) in enumerate(E.blocks); nb = norm(view(v, b)); nb > E.um[k] && (v[b] .*= E.um[k] / nb); end; v)
JE71(E, q, c, u) = 0.5 * dot(u, E.H * u) + dot(q, u) + c
function dualE71(E, q, c, w)
    g = E.H * w .+ q
    return JE71(E, q, c, w) - dot(g, w) - sum(E.um[k] * norm(view(g, b)) for (k, b) in enumerate(E.blocks))
end
stackE71(E, U) = reduce(vcat, [vec(U[i]) for i in eachindex(U)])

"""E72's certificate at a feasible u with its KKT normals in the metric S (an hs71)."""
function kktE71(E, S, q, u; tol = 1e-6)
    g = E.H * u .+ q; n = zeros(length(u)); e = 0.0
    for (k, b) in enumerate(E.blocks)
        nu = norm(view(u, b)); nu >= (1 - tol) * E.um[k] || continue
        w = u[b] ./ nu; n[b] .= max(0.0, -dot(view(g, b), w)) .* w
    end
    for (k, b) in enumerate(E.blocks)
        e += E.um[k] * norm(view(n, b)) - dot(view(n, b), view(u, b))
    end
    gg = g .+ n
    return 0.5 * dot(gg, S.F \ gg) + max(e, 0.0)
end

"""Per-step evaluation of a plan U against the reference plan Ur (both per-vehicle nu x H)."""
function evalE71(E, S, q, c, U, Ur)
    ur = projE71!(stackE71(E, Ur), E)
    Jsu = JE71(E, q, c, ur); Jsl = dualE71(E, q, c, ur); a = abs(Jsu)
    t0 = time_ns()
    u = stackE71(E, U); up = projE71!(copy(u), E)
    viol = maximum(norm(view(u, b)) - E.um[k] for (k, b) in enumerate(E.blocks))
    Jp = JE71(E, q, c, up)
    d = max(dualE71(E, q, c, u), dualE71(E, q, c, up))
    tc = (time_ns() - t0) / 1e9
    te = @elapsed (kk = kktE71(E, S, q, up))
    return Dict{String,Any}("Jp" => Jp, "Jstar_u" => Jsu, "Jstar_l" => Jsl, "gap" => (Jp - Jsu) / a, "cert" => (Jp - d) / a,
                            "eta" => kk / a, "dual_viol" => (d - Jsu) / a, "plan_viol" => viol, "t_cert" => tc, "t_eta" => te,
                            "finite" => isfinite(Jp) && isfinite(d) && isfinite(kk))
end

"""Sparse V-FISTA (E72's (C)) in the metric kb*H_S of S, block prox per team; kb by power iteration on H_S^{-1}H."""
struct VFS71
    S::Any
    Pm::Vector{SparseMatrixCSC{Float64,Int}}
    lmax::Vector{Float64}
    balls::Vector{Vector{Tuple{UnitRange{Int},Float64}}}
    kb::Float64
end

function VFS71(E::Ev71, S)
    N = E.off[end]
    pos = zeros(Int, N); prt = zeros(Int, N)
    for (p, c) in enumerate(S.parts), (a, j) in enumerate(c)
        pos[j] = a; prt[j] = p
    end
    balls = [Tuple{UnitRange{Int},Float64}[] for _ in S.parts]
    for (k, b) in enumerate(E.blocks)
        p = prt[first(b)]; push!(balls[p], (pos[first(b)]:pos[last(b)], E.um[k]))
    end
    Pm = [S.HS[c, c] for c in S.parts]
    lmax = map(Pm) do M
        x = randn(Xoshiro(5), size(M, 1)); x ./= norm(x); lam = 0.0
        for _ in 1:60; y = M * x; lam = norm(y); x = y / lam; end
        1.05 * lam
    end
    x = randn(Xoshiro(3), N); x ./= norm(x); lam = 0.0
    for _ in 1:100
        y = S.F \ (E.H * x); lam = norm(y); x = y / lam
    end
    return VFS71(S, Pm, lmax, balls, 1.05 * lam)
end

function vfS71!(V::VFS71, E::Ev71, q, u0, tend::UInt64, titer::Ref{Float64}; m_in = MIN71)
    beta = (sqrt(V.kb) - 1) / (sqrt(V.kb) + 1)
    x = projE71!(copy(u0), E); Hx = E.H * x; y = copy(x); Hy = copy(Hx)
    fbest = 0.5 * dot(x, Hx) + dot(q, x); best = copy(x); xn = copy(x); k = 0
    while time_ns() + round(UInt64, 1e9 * titer[]) < tend
        ti = time_ns()
        gy = Hy .+ q
        for (p, c) in enumerate(V.S.parts)
            v = xn[c]
            proxS71!(v, gy[c], y[c], V.Pm[p], V.kb, V.lmax[p], V.balls[p], m_in)
            xn[c] = v
        end
        projE71!(xn, E)
        Hxn = E.H * xn; f = 0.5 * dot(xn, Hxn) + dot(q, xn)
        f < fbest && (fbest = f; best .= xn)
        y = xn .+ beta .* (xn .- x); Hy = Hxn .+ beta .* (Hxn .- Hx)
        x = copy(xn); Hx = Hxn; k += 1
        titer[] = (time_ns() - ti) / 1e9
    end
    return best, k
end

function proxS71!(v, q, y, Pm, kb, lmax, balls, m_in)
    st = 1 / (kb * lmax)
    z = copy(v); vo = copy(v); t = 1.0; w = similar(v); gz = similar(v)
    for _ in 1:m_in
        mul!(gz, Pm, z .- y)
        @. w = z - st * (q + kb * gz)
        for (rg, r) in balls
            nb = norm(view(w, rg)); nb > r && (w[rg] .*= r / nb)
        end
        tn = (1 + sqrt(1 + 4t^2)) / 2; bt = (t - 1) / tn
        @. z = w + bt * (w - vo)
        vo .= w; t = tn
    end
    v .= vo
    return v
end

"""A tight controller (1e-9) of a fleet (the package merges eps from kwargs, so they are passed as kwargs)."""
tight71(fl) = SM.MPCController(fl, SM.full_condensing(); certify = false, eps_abs = 1e-9, eps_rel = 1e-9, max_iter = 100_000)

"""Reference plan provider: tight team MPC on lossless teams (mode team) or the tight central solve."""
mutable struct Ref71
    mode::Symbol
    Q::Any
    C::Any
end
Ref71(sc, lab) = (Q = Quot51(sc, lab); Ref71(:team, Q, tight71(Q.fleet)))
Ref71(sc) = Ref71(:central, nothing, tight71(sc.fleet))
function refU71!(R::Ref71, sc, x, refs, term)
    if R.mode == :central
        info = SM.step!(R.C, x, refs; terminal = term)
        return SM.trajectories(R.C.fp, SM.plan(R.C))[2], [copy(v) for v in info.u]
    end
    xq, rq, tq = teamdata51(R.Q, sc, x, refs, term)
    info = SM.step!(R.C, xq, rq; terminal = tq)
    Uq = SM.trajectories(R.C.fp, SM.plan(R.C))[2]
    return [copy(Uq[R.Q.team[i]]) for i in 1:sc.n], [copy(info.u[R.Q.team[i]]) for i in 1:sc.n]
end

"""The closed loop of the reference itself (its converged cost) and, optionally, a second reference's J* per step."""
function refloop71(sc, R::Ref71, E, S; steps, check::Union{Nothing,Ref71} = nothing)
    GC.gc()
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        t0 = time_ns(); U, u = refU71!(R, sc, x, refs, term); tt = (time_ns() - t0) / 1e9
        r = Dict{String,Any}("step" => k, "t_total" => tt)
        if check !== nothing
            q, c = qc71(sc.fleet, E.off, x, refs, term)
            Uc, _ = refU71!(check, sc, x, refs, term)
            ev = evalE71(E, S, q, c, U, Uc)
            r["ref_gap_vs_check"] = ev["gap"]; r["ref_cert"] = ev["cert"]; r["ref_eta"] = ev["eta"]
        end
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, r)
        x = plant26(sc, x, uc)
        GC.gc()
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]
    out = Dict{String,Any}("closed_loop_cost" => cost, "t_total" => st71([r["t_total"] for r in a]), "mode" => string(R.mode))
    if check !== nothing
        g = [r["ref_gap_vs_check"] for r in rec]
        out["gap_vs_check"] = st71(g); out["eta_vs_check"] = st71([r["ref_eta"] for r in rec])
    end
    return out
end

"""An arm's closed loop. kind: :rt (early-stopped central, ADMM only), :team, :hyb (team then V-FISTA)."""
function arm71(sc, kind::Symbol, R::Ref71, E, S, Jref; lab = nothing, V = nothing, deadline = PERIOD71, steps)
    GC.gc()
    fl = sc.fleet
    Q = lab === nothing ? nothing : Quot51(sc, lab)
    C = kind == :rt ? controller51(fl) : controller51(Q.fleet)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; over = Float64[]; pre = 0.0; post = 0.0; titer = Ref(0.0)
    tq71 = Ref(0.0); skipped = 0; Uapp = nothing; fell = 0
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        guard = isempty(over) ? GMIN71 : clamp(maximum(over[max(1, end - GWIN71 + 1):end]), GMIN71, GMAX71)
        it = 0; tteam = 0.0; status = ""
        t0 = time_ns()
        if kind == :rt
            if k == 0
                info = SM.step!(C, x, refs; terminal = term)
                s = C.solver.settings; s.polish = false; s.adaptive_rho = false; s.warm_reset_rho = false; s.method = :admm
            else
                tl = max(deadline - pre - post - RESERVE71 - guard, 1e-6)
                C.solver.settings.time_limit = tl
                C.solver.info.status = :solved
                info = SM.step!(C, x, refs; terminal = term)
                C.solver.settings.time_limit = Inf
                push!(over, max(info.t_solve - tl, 0.0))          # the solver's overrun past its limit (as rt71)
            end
            pre = info.t_construct + info.t_setup; post = info.t_lift
            U = SM.trajectories(C.fp, SM.plan(C))[2]; u = [copy(v) for v in info.u]; status = string(info.status); it = info.iter
        else
            xq, rq, tq = teamdata51(Q, sc, x, refs, term)
            info = SM.step!(C, xq, rq; terminal = tq)
            Uq = SM.trajectories(C.fp, SM.plan(C))[2]
            U = [copy(Uq[Q.team[i]]) for i in 1:sc.n]; u = [copy(info.u[Q.team[i]]) for i in 1:sc.n]; status = string(info.status)
            tteam = (time_ns() - t0) / 1e9
            if kind == :hyb
                tend = t0 + round(UInt64, 1e9 * (deadline - RESERVE71 - guard))
                # skip the refinement when the data (q) and one iteration, as last measured, do not fit in what is left
                if k == 0 || time_ns() + round(UInt64, 1e9 * (tq71[] + titer[])) < tend
                    tq0 = time_ns()
                    q, _ = qc71(fl, E.off, x, refs, term)
                    tq71[] = (time_ns() - tq0) / 1e9
                    u0 = stackE71(E, U)
                    if k == 0
                        ub, it = vfS71!(V, E, q, u0, time_ns() + round(UInt64, 1e9 * 0.5), titer)
                    else
                        ub, it = vfS71!(V, E, q, u0, tend, titer)
                        push!(over, max((time_ns() - tend) / 1e9, 0.0))
                    end
                    U = [reshape(ub[E.off[i]+1:E.off[i+1]], fl.agents[i].nu, fl.H) for i in 1:sc.n]
                    u = [copy(U[i][:, 1]) for i in 1:sc.n]
                else
                    skipped += 1
                end
            end
        end
        tt = (time_ns() - t0) / 1e9
        Ur, _ = refU71!(R, sc, x, refs, term)
        q, c = qc71(fl, E.off, x, refs, term)
        ev = evalE71(E, S, q, c, U, Ur)
        ev["in_time"] = tt + ev["t_cert"] <= deadline; ev["in_time_eta"] = tt + ev["t_eta"] <= deadline
        tsolve = tt
        CERTSTEP71 && kind == :team && (tt += ev["t_eta"])
        fallback = FALLBACK71 == "shift" && k > 0 && tt > min(deadline, FBDEAD71) && Uapp !== nothing
        if fallback
            Uapp = [hcat(Ui[:, 2:end], Ui[:, end]) for Ui in Uapp]
            u = [copy(Ui[:, 1]) for Ui in Uapp]; fell += 1
        else
            Uapp = [copy(Ui) for Ui in U]
        end
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "t_total" => tt, "t_solve" => tsolve, "cert_in_step" => CERTSTEP71 && kind == :team, "t_team" => tteam, "iters" => it, "met" => tt <= deadline,
                                    "status" => status, "viol" => viol, "cert" => ev, "fallback" => fallback))
        x = plant26(sc, x, uc)
        GC.gc()
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(key) = [Float64(r[key]) for r in a]
    return Dict{String,Any}("kind" => string(kind), "closed_loop_cost" => cost, "cost_ratio" => cost / Jref,
        "t_total" => st71(col("t_total")), "t_team" => st71(col("t_team")), "iters" => st71(col("iters")),
        "met_frac" => count(r -> r["met"], a) / length(a), "viol" => st71(col("viol")),
        "teams" => lab === nothing ? sc.n : maximum(lab), "kb" => V === nothing ? nothing : V.kb, "refine_skipped_steps" => skipped,
        "fallback_rule" => FALLBACK71, "fallback_frac" => count(r -> r["fallback"], a) / length(a),
        "certified" => certsum71([r["cert"] for r in a]),
        "cert_in_time_frac" => count(r -> r["cert"]["in_time"], a) / length(a),
        "eta_in_time_frac" => count(r -> r["cert"]["in_time_eta"], a) / length(a), "steps" => rec)
end

"""Scenario of an E74 mission instance (E74's lanes per class, E63's start), teams `lab` recorded."""
function scenario74c(inst, seed::Int, lab)
    n = length(inst.kinds)
    fl = sq_fleet(inst, DT26, H26, CONE63)
    _, dp, dv = sq_start(inst, fl, seed)
    params = NamedTuple[sq_params_of(inst, i) for i in 1:n]
    wander = NamedTuple[(amp = 0.0, om = 0.0, ph = 0.0, omz = 0.0, phz = 0.0) for _ in 1:n]
    return Scenario26(isqrt(n), n, H26, DT26, CONE63, :coherent, 0.0, seed, fl, inst.slots, lanes74(inst, seed), wander,
                      dp, dv, copy(inst.kinds), copy(inst.class), SM.canonical_partition(lab), sq_ranks(lab, inst.slots), params)
end

safe71(f, name) = try
    f()
catch e
    @printf("  %s FAILED: %s\n", name, sprint(showerror, e)[1:min(end, 400)]); flush(stdout)
    Dict{String,Any}("error" => sprint(showerror, e)[1:min(end, 2000)])
end

function realrun71(v, N, seed; steps = STEPS71, quiet = false)
    inst = mission74(v, N); n = length(inst.kinds)
    tcr = @elapsed (lab = SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = false)))
    sc = scenario74c(inst, seed, lab)
    res = Dict{String,Any}("kind" => "realistic", "variant" => v, "n_requested" => N, "seed" => seed, "n" => n,
                           "edges" => length(inst.edges), "classes" => maximum(inst.class), "teams_phi" => maximum(lab),
                           "refine_seconds" => tcr, "spread" => sq_spread(n, inst.edges, inst.w, lab)[1],
                           "steps" => steps, "period" => PERIOD71, "load_start" => loadavg26(), "controllers" => Dict{String,Any}())
    R = res["controllers"]
    tb = @elapsed (E = Ev71(sc)); res["eval_build_seconds"] = tb
    tb = @elapsed (S = hs71(E, lab)); res["hs_build_seconds"] = tb
    Rf = Ref71(sc, lab)
    chk = n <= COORDN71 ? Ref71(sc) : nothing
    R["reference"] = refloop71(sc, Rf, E, S; steps = steps, check = chk)
    R["reference"]["note"] = "team MPC on phi* to 1e-9 (lossless); check: tight central solve per step" * (chk === nothing ? " (not run: n > E71_COORDN)" : "")
    chk = nothing; GC.gc()
    Jref = R["reference"]["closed_loop_cost"]
    if n <= COORDN71
        R["coord"] = safe71(() -> (o = coord71(sc; steps = steps); o["cost_ratio"] = o["closed_loop_cost"] / Jref; o), "coord")
    end
    quiet || @printf("E71c %s n %d seed %d phi* %d teams, spread %.1e, ref cost %.6e%s\n", v, n, seed, maximum(lab), res["spread"], Jref,
                     haskey(R["reference"], "gap_vs_check") ? @sprintf(" (gap vs central med %.1e max %.1e)", R["reference"]["gap_vs_check"]["median"], R["reference"]["gap_vs_check"]["max"]) : "")
    for arm in CARMS71
        if arm == "rt_admm"
            if "$v@$N" in RTSKIP71
                R["rt_admm"] = Dict{String,Any}("skipped" => "E71_RT_SKIP: the coordinated QP's factorization is too large at this size")
                continue
            end
            R["rt_admm"] = safe71(() -> arm71(sc, :rt, Rf, E, S, Jref; steps = steps), "rt_admm")
        elseif arm == "team"
            R["team_phi"] = safe71(() -> arm71(sc, :team, Rf, E, S, Jref; lab = lab, steps = steps), "team_phi")
        elseif arm == "hyb"
            R["hyb_phi"] = safe71(() -> (V = VFS71(E, S); arm71(sc, :hyb, Rf, E, S, Jref; lab = lab, V = V, steps = steps)), "hyb_phi")
        end
        key = arm == "rt_admm" ? "rt_admm" : arm == "team" ? "team_phi" : "hyb_phi"
        o = R[key]
        quiet || haskey(o, "certified") && @printf("  %-8s ratio %.6f ms med %.1f max %.1f met %.2f gap med %.1e max %.1e cert med %.1e eta med %.1e iters %.0f\n",
                         key, o["cost_ratio"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), o["met_frac"],
                         o["certified"]["gap"]["median"], o["certified"]["gap"]["max"], o["certified"]["cert"]["median"],
                         o["certified"]["eta"]["median"], o["iters"]["median"])
        flush(stdout)
    end
    res["load_end"] = loadavg26()
    return res
end

"""E79's response embedding on the condensed QP: unconstrained plans of R random coherent data sets, own-Hessian metric."""
function respteams71(sc, E, inst, seed, Kb)
    n = sc.n; cls = inst.class; K = maximum(cls)
    tf = @elapsed (F = cholesky(Symmetric(E.H)))
    Uc = [cholesky(Symmetric(E.H0[i])).U for i in 1:n]
    Y = [Float64[] for _ in 1:n]
    tr = @elapsed for r in 1:R71
        rng = Xoshiro(79_000_000 + 1000 * (10_000 + seed) + r); t0 = 2.0 * r
        dp = [0.3 .* randn(rng, 2) for _ in 1:K]; dv = [0.15 .* randn(rng, 2) for _ in 1:K]
        x0 = map(1:n) do i
            p, vv = reference26(sc, i, t0); d = length(p); c = cls[i]
            [p .+ [dp[c]; zeros(d - 2)]; vv .+ [dv[c]; zeros(d - 2)]]
        end
        refs, term = references26(sc, t0)
        q, _ = qc71(sc.fleet, E.off, x0, refs, term)
        u = -(F \ q)
        for i in 1:n
            append!(Y[i], Uc[i] * u[E.off[i]+1:E.off[i+1]] ./ sqrt(R71))
        end
    end
    rng = Xoshiro(79 + seed)
    tk = @elapsed (lab = alloc79_(cls, m -> reduce(vcat, (Y[i]' for i in m)), Kb, rng))
    return lab, tf + tr + tk
end

function resprun71(seed; n = N71, steps = STEPS71, quiet = false)
    inst = sq_instance(n, seed)
    labc, _ = sq_teams(inst, "classes", seed)
    sc = scenario63(inst, seed, labc)
    res = Dict{String,Any}("kind" => "resp", "n_requested" => n, "seed" => seed, "n" => length(inst.kinds),
                           "steps" => steps, "period" => PERIOD71, "load_start" => loadavg26(), "controllers" => Dict{String,Any}())
    R = res["controllers"]
    E = Ev71(sc)
    Rf = Ref71(sc)
    co = coord71(sc; steps = steps); Jc = co["closed_loop_cost"]; co["cost_ratio"] = 1.0
    R["coord_respjob"] = co
    for qn in RESPQ71
        lq, _ = sq_teams(inst, qn, seed); Kb = maximum(lq)
        lab, tsel = respteams71(sc, E, inst, seed, Kb)
        S = hs71(E, lab)
        o = safe71(() -> arm71(sc, :team, Rf, E, S, Jc; lab = lab, steps = steps), "team_resp$Kb")
        o isa Dict && (o["select_seconds"] = tsel; o["budget_from"] = qn)
        R["team_resp_$qn"] = o
        o2 = safe71(() -> (V = VFS71(E, S); arm71(sc, :hyb, Rf, E, S, Jc; lab = lab, V = V, steps = steps)), "hyb_resp$Kb")
        o2 isa Dict && (o2["select_seconds"] = tsel; o2["budget_from"] = qn)
        R["hyb_resp_$qn"] = o2
        for (key, o) in (("team_resp_$qn", o), ("hyb_resp_$qn", o2))
            quiet || haskey(o, "certified") && @printf("  %-14s K %4d ratio %.4f ms med %.1f max %.1f met %.2f gap med %.1e cert med %.1e eta med %.1e iters %.0f\n",
                             key, Kb, o["cost_ratio"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), o["met_frac"],
                             o["certified"]["gap"]["median"], o["certified"]["cert"]["median"], o["certified"]["eta"]["median"], o["iters"]["median"])
        end
        flush(stdout)
    end
    res["load_end"] = loadavg26()
    return res
end

"""E79's k-means allocation (kmeans79/alloc79 of e79_teamselect.jl, verbatim logic)."""
function kmeans79_(X::Matrix{Float64}, k::Int, rng; restarts::Int = 4, iters::Int = 60)
    m = size(X, 1)
    k >= m && return (collect(1:m), 0.0)
    k == 1 && (mu = vec(mean(X; dims = 1)); return (ones(Int, m), sum(abs2, X .- mu')))
    best = (Int[], Inf)
    for _ in 1:restarts
        C = zeros(k, size(X, 2)); C[1, :] .= X[rand(rng, 1:m), :]
        d2 = vec(sum(abs2, X .- C[1, :]'; dims = 2))
        for c in 2:k
            s = sum(d2)
            idx = s <= 0 ? rand(rng, 1:m) : findfirst(>=(rand(rng) * s), cumsum(d2))
            idx === nothing && (idx = m)
            C[c, :] .= X[idx, :]
            d2 .= min.(d2, vec(sum(abs2, X .- C[c, :]'; dims = 2)))
        end
        a = zeros(Int, m)
        for _ in 1:iters
            D = max.(vec(sum(abs2, X; dims = 2)) .+ vec(sum(abs2, C; dims = 2))' .- 2 .* (X * C'), 0.0)
            anew = [argmin(D[p, :]) for p in 1:m]
            for c in 1:k
                if !any(==(c), anew)
                    far = argmax([D[p, anew[p]] for p in 1:m]); anew[far] = c
                end
            end
            anew == a && break
            a = anew
            for c in 1:k
                C[c, :] .= vec(mean(X[a .== c, :]; dims = 1))
            end
        end
        cost = sum(sum(abs2, X[p, :] .- C[a[p], :]) for p in 1:m)
        cost < best[2] && (best = (copy(a), cost))
    end
    return best
end

function alloc79_(cls::Vector{Int}, emb::Function, Kb::Int, rng)
    cs = sort(unique(cls)); mem = [findall(==(c), cls) for c in cs]
    sols = Vector{Vector{Tuple{Vector{Int},Float64}}}(undef, length(cs))
    for (a, m) in enumerate(mem)
        X = Matrix{Float64}(emb(m))
        sols[a] = [kmeans79_(X, j, rng) for j in 1:length(m)]
    end
    nc = length(cs); INF = Inf
    best = fill(INF, nc + 1, Kb + 1); arg = zeros(Int, nc + 1, Kb + 1); best[1, 1] = 0.0
    for a in 1:nc, K in 0:Kb
        best[a, K+1] == INF && continue
        for j in 1:length(mem[a])
            K + j <= Kb || break
            v = best[a, K+1] + sols[a][j][2]
            v < best[a+1, K+j+1] && (best[a+1, K+j+1] = v; arg[a+1, K+j+1] = j)
        end
    end
    @assert best[nc+1, Kb+1] < INF "budget $Kb infeasible for $(nc) classes"
    lab = zeros(Int, length(cls)); K = Kb; nxt = 0
    for a in nc:-1:1
        j = arg[a+1, K+1]
        lab[mem[a]] .= nxt .+ sols[a][j][1]; nxt += j; K -= j
    end
    return SM.canonical_partition(lab)
end

function main71c()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR71)
    meta() = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                  "cpu" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(), "affinity" => get(ENV, "E71_AFFINITY", ""))
    if C71 == "real"
        realrun71(VARIANT71, 256, 1; steps = 3, quiet = true)                    # warm-up (compile every path)
        for seed in SEEDS71
            res = realrun71(VARIANT71, N71, seed); res["meta"] = meta()
            path = joinpath(PARTDIR71, @sprintf("e71c_real_%s_n%d_seed%d.json", VARIANT71, N71, seed))
            open(io -> JSON.print(io, clean71(res), 1), path, "w"); println("wrote $path"); flush(stdout)
        end
    else
        resprun71(1; n = 64, steps = 3, quiet = true)
        for seed in SEEDS71
            res = resprun71(seed); res["meta"] = meta()
            path = joinpath(PARTDIR71, @sprintf("e71c_resp_n%d_seed%d.json", N71, seed))
            open(io -> JSON.print(io, clean71(res), 1), path, "w"); println("wrote $path"); flush(stdout)
        end
    end
end

min71(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : minimum(w))
mean71(v) = (w = [Float64(x) for x in v if x !== nothing && isfinite(Float64(x))]; isempty(w) ? nothing : mean(w))

"""Summary of an arm over seeds (E71c records)."""
function armmerge71(ps)
    ps = [q for q in ps if q isa AbstractDict && haskey(q, "certified")]
    isempty(ps) && return nothing
    d = Dict{String,Any}("seeds" => length(ps), "cost_ratio_med" => med71([q["cost_ratio"] for q in ps]),
                         "cost_ratio_max" => max71([q["cost_ratio"] for q in ps]),
                         "ms_med" => 1e3 * med71([q["t_total"]["median"] for q in ps]), "ms_max" => 1e3 * max71([q["t_total"]["max"] for q in ps]),
                         "met_frac" => mean71([q["met_frac"] for q in ps]), "iters_med" => med71([q["iters"]["median"] for q in ps]),
                         "teams" => med71([q["teams"] for q in ps]), "kb" => med71([q["kb"] for q in ps]),
                         "cert_in_time_frac" => mean71([q["cert_in_time_frac"] for q in ps]),
                         "eta_in_time_frac" => mean71([q["eta_in_time_frac"] for q in ps]), "certified" => certmerge71(ps),
                         "viol_max_raw" => max71([q["viol"]["max"] for q in ps]),
                         "viol_note" => "largest violation of an input ball by the controller's first input before the projection; the applied input and the closed-loop cost are after the projection (clip26)")
    haskey(ps[1], "select_seconds") && (d["select_seconds_med"] = med71([q["select_seconds"] for q in ps]))
    if haskey(ps[1], "fallback_frac")
        d["fallback_rule"] = ps[1]["fallback_rule"]; d["fallback_frac"] = mean71([q["fallback_frac"] for q in ps])
    end
    # time per step with the KKT-normal certificate added (solve plus eta), when the steps are kept
    if haskey(ps[1], "steps")
        tc = [[Float64(get(r, "t_solve", r["t_total"])) + Float64(get(r["cert"], "t_eta", NaN)) for r in q["steps"][2:end]] for q in ps]
        d["solve_ms_med"] = 1e3 * med71([median([Float64(get(r, "t_solve", r["t_total"])) for r in q["steps"][2:end]]) for q in ps])
        d["cert_in_step"] = get(ps[1]["steps"][end], "cert_in_step", false)
        d["ms_eta_med"] = 1e3 * med71([median(v) for v in tc])
        te = [[Float64(get(r["cert"], "t_eta", NaN)) for r in q["steps"][2:end]] for q in ps]
        d["eta_ms_med"] = 1e3 * med71([median(v) for v in te])
    end
    return d
end

function merge71c()
    dirs = split(get(ENV, "E71_PARTDIRS", PARTDIR71), ",")
    out = Dict{String,Any}("experiment" => "E71c: equal 200 ms budget; realistic formations of E74 (lossless phi*): early-stopped coordinated MPC (ADMM only), team MPC on phi*, hybrid team + V-FISTA in H_S; irregular formation: E71 controllers, V-FISTA, response teams (E79) and their hybrid. Per step: cost vs converged, true gap, certified gaps (dual; KKT-normal certificate in H_S), time, met fraction.",
                           "period_ms" => 1e3 * PERIOD71, "realistic" => Dict{String,Any}(), "irregular" => Dict{String,Any}())
    raw = Any[]
    for d in dirs, f in readdir(d; join = true)
        endswith(f, ".json") && push!(raw, JSON.parsefile(f))
    end
    # realistic
    for p in filter(p -> get(p, "kind", "") == "realistic", raw)
        key = "$(p["variant"])_n$(p["n_requested"])"
        push!(get!(out["realistic"], key, Any[]), p)
    end
    for (key, P) in out["realistic"]
        S = Dict{String,Any}("seeds" => [p["seed"] for p in P], "n" => P[1]["n"], "edges" => P[1]["edges"], "teams_phi" => P[1]["teams_phi"],
                             "spread" => P[1]["spread"], "steps" => P[1]["steps"], "hosts" => [p["meta"]["host"] for p in P],
                             "cpu" => unique([p["meta"]["cpu"] for p in P]), "affinity" => [p["meta"]["affinity"] for p in P],
                             "jobs" => [p["meta"]["job"] for p in P], "load" => [[p["load_start"], p["load_end"]] for p in P],
                             "controllers" => Dict{String,Any}())
        rf = [p["controllers"]["reference"] for p in P]
        S["reference"] = Dict{String,Any}("note" => rf[1]["note"], "cost_med" => med71([r["closed_loop_cost"] for r in rf]),
                                          "ms_med" => 1e3 * med71([r["t_total"]["median"] for r in rf]))
        haskey(rf[1], "gap_vs_check") && (S["reference"]["gap_vs_central_max"] = max71([r["gap_vs_check"]["max"] for r in rf]);
                                          S["reference"]["gap_vs_central_min"] = min71([r["gap_vs_check"]["min"] for r in rf]))
        if haskey(P[1]["controllers"], "coord") && haskey(P[1]["controllers"]["coord"], "closed_loop_cost")
            cs = [p["controllers"]["coord"] for p in P]
            S["controllers"]["coord"] = Dict("cost_ratio_med" => med71([c["cost_ratio"] for c in cs]), "cost_ratio_max" => max71([c["cost_ratio"] for c in cs]),
                                             "ms_med" => 1e3 * med71([c["t_total"]["median"] for c in cs]), "ms_max" => 1e3 * max71([c["t_total"]["max"] for c in cs]),
                                             "met_frac" => mean71([c["met_frac"] for c in cs]))
        end
        for arm in ("rt_admm", "team_phi", "hyb_phi")
            ps = [p["controllers"][arm] for p in P if haskey(p["controllers"], arm)]
            isempty(ps) && continue
            m = armmerge71(ps)
            S["controllers"][arm] = m === nothing ? Dict("skipped_or_failed" => [get(q, "skipped", get(q, "error", "")) for q in ps]) : m
        end
        out["realistic"][key] = S
    end
    # irregular: E71 base, vf, resp parts grouped by (n, seed)
    irr = filter(p -> get(p, "kind", "") != "realistic", raw)
    byk = Dict{Tuple{Int,Int},Any}()
    for p in irr
        k = (p["n_requested"], p["seed"])
        haskey(byk, k) ? merge!(byk[k]["controllers"], p["controllers"]) : (byk[k] = deepcopy(p))
    end
    for nreq in sort!(unique([k[1] for k in keys(byk)]))
        P = [v for (k, v) in byk if k[1] == nreq]
        S = Dict{String,Any}("seeds" => sort([p["seed"] for p in P]), "n" => [p["n"] for p in P], "controllers" => Dict{String,Any}())
        allkeys = unique(reduce(vcat, [collect(keys(p["controllers"])) for p in P]))
        for key in allkeys
            ps = [p["controllers"][key] for p in P if haskey(p["controllers"], key)]
            if startswith(key, "team_resp") || startswith(key, "hyb_resp")
                S["controllers"][key] = armmerge71(ps)
            elseif startswith(key, "coord")
                S["controllers"][key] = Dict("cost_med" => med71([q["closed_loop_cost"] for q in ps]),
                                             "ms_med" => 1e3 * med71([q["t_total"]["median"] for q in ps]), "ms_max" => 1e3 * max71([q["t_total"]["max"] for q in ps]),
                                             "met_frac" => mean71([q["met_frac"] for q in ps]), "seeds" => length(ps))
            else
                d = Dict{String,Any}("seeds" => length(ps), "cost_ratio_med" => med71([get(q, "cost_ratio", NaN) for q in ps]),
                                     "cost_ratio_max" => max71([get(q, "cost_ratio", NaN) for q in ps]))
                if startswith(key, "admm")
                    d["par_ms_med"] = 1e3 * med71([q["par"]["median"] for q in ps]); d["par_ms_max"] = 1e3 * max71([q["par"]["max"] for q in ps])
                    d["seq_ms_med"] = 1e3 * med71([q["seq"]["median"] for q in ps]); d["seq_ms_max"] = 1e3 * max71([q["seq"]["max"] for q in ps])
                    d["met_par_frac"] = mean71([q["met_par_frac"] for q in ps]); d["met_seq_frac"] = mean71([q["met_seq_frac"] for q in ps])
                    d["rounds"] = ps[1]["rounds"]; d["floats_med"] = med71([q["floats"]["median"] for q in ps])
                else
                    d["ms_med"] = 1e3 * med71([q["t_total"]["median"] for q in ps]); d["ms_max"] = 1e3 * max71([q["t_total"]["max"] for q in ps])
                    d["met_frac"] = mean71([q["met_frac"] for q in ps])
                    startswith(key, "vf") && (d["iters_med"] = med71([q["iters"]["median"] for q in ps]))
                end
                haskey(ps[1], "certified") && (d["certified"] = certmerge71(ps))
                haskey(ps[1], "viol") && ps[1]["viol"] isa AbstractDict && haskey(ps[1]["viol"], "max") &&
                    (d["viol_max_raw"] = max71([q["viol"]["max"] for q in ps]))
                startswith(key, "rt_auto") && (d["dropped"] = "the interior-point crossover is not interruptible within a step (worst step 2.0 s at the 200 ms budget): not an early-stopped arm, excluded from the comparison")
                S["controllers"][key] = d
            end
        end
        out["irregular"][string(nreq)] = S
    end
    open(io -> JSON.print(io, clean71(out), 1), OUT71, "w")
    println("wrote $OUT71")
end

"""results/e71c_figure.json: per formation and size, per arm, time per step, met fraction, cost and certified gap."""
function figure71c()
    M = JSON.parsefile(get(ENV, "E71_IN", OUT71))
    out = Dict{String,Any}("source" => "e71c_budget.json (E71/E71c, merged on HPG)", "period_ms" => 1e3 * PERIOD71,
        "fields" => Dict("ms_med" => "median over seeds of the per-seed median time per step (ms, one pinned core)",
                         "ms_max" => "worst step over seeds", "met" => "fraction of steps (after step 0) within the 200 ms period",
                         "cost_med/cost_max" => "closed-loop cost over the reference's (median/worst over seeds)",
                         "gap_med/gap_max" => "true gap J(u_p) - J* over |J*| per step (median of per-seed medians / worst)",
                         "cert_med/cert_max" => "certified gap: KKT-normal certificate in H_S (Thm. 2 eta for team arms), relative to |J*|",
                         "dual_med" => "certified gap by the Lagrangian dual (z = grad J), relative"),
        "reference" => Dict("realistic" => "team MPC on phi* to 1e-9 (lossless: exact); checked against the tight central solve at 1024 and 4096",
                            "irregular" => "coordinated MPC (MPCController, eps 1e-6) closed loop; J* per step from the central solve (1e-6 in E71, 1e-9 in E71c)"),
        "dropped" => "early stop with the interior-point crossover (rt_auto): the IPM is not interruptible within a step (worst 2.0 s)",
        "rows" => Any[])
    num(x) = x === nothing ? nothing : Float64(x)
    function row(form, n, arm, d; note = "")
        d === nothing && return
        c = get(d, "certified", Dict())
        haskey(d, "skipped_or_failed") && (push!(out["rows"], Dict("formation" => form, "n" => n, "arm" => arm, "skipped" => d["skipped_or_failed"])); return)
        r = Dict{String,Any}("formation" => form, "n" => n, "arm" => arm,
            "ms_med" => num(get(d, "ms_med", get(d, "seq_ms_med", nothing))), "ms_max" => num(get(d, "ms_max", get(d, "seq_ms_max", nothing))),
            "met" => num(get(d, "met_frac", get(d, "met_seq_frac", nothing))),
            "cost_med" => num(get(d, "cost_ratio_med", nothing)), "cost_max" => num(get(d, "cost_ratio_max", nothing)),
            "gap_med" => num(get(c, "gap_med", nothing)), "gap_max" => num(get(c, "gap_max", nothing)),
            "cert_med" => num(get(c, "eta_med", nothing)), "cert_max" => num(get(c, "eta_max", nothing)),
            "dual_med" => num(get(c, "cert_med", nothing)), "teams" => get(d, "teams", get(d, "teams_med", nothing)),
            "viol_max_raw" => num(get(d, "viol_max_raw", get(d, "viol_max", nothing))))
        isempty(note) || (r["note"] = note)
        haskey(d, "par_ms_med") && (r["par_ms_med"] = d["par_ms_med"]; r["met_par"] = d["met_par_frac"])
        push!(out["rows"], r)
    end
    for (key, S) in M["realistic"]
        form, nn = split(key, "_n"); n = parse(Int, nn); C = S["controllers"]
        row(form, n, "lossless_teams", get(C, "team_phi", nothing))
        row(form, n, "early_stopped_central", get(C, "rt_admm", nothing))
        row(form, n, "hybrid", get(C, "hyb_phi", nothing))
        haskey(C, "coord") && row(form, n, "converged_central", C["coord"])
    end
    for (nn, S) in M["irregular"]
        n = parse(Int, nn); C = S["controllers"]
        row("irregular", n, "early_stopped_central", get(C, "rt_admm_200ms", nothing))
        haskey(C, "coord") && row("irregular", n, "converged_central", merge(Dict{String,Any}("cost_ratio_med" => 1.0, "cost_ratio_max" => 1.0), C["coord"]))
        for q in ("qs8", "qs2")
            row("irregular", n, "clustered_teams_$q", get(C, "team_resp_$q", nothing); note = "response teams (E79), team count of $q")
            row("irregular", n, "hybrid_$q", get(C, "hyb_resp_$q", nothing); note = "response teams of $q, then V-FISTA in H_S")
        end
        row("irregular", n, "region_teams", get(C, "team_classes", nothing))
        for b in (1, 2, 5)
            row("irregular", n, "consensus_admm_b$b", get(C, "admm_b$(b)_init", nothing);
                note = "ms and met: all agents' work on one core (sequential); par_ms and met_par: simulated parallel, no communication latency")
        end
    end
    sort!(out["rows"]; by = r -> (r["formation"], r["n"], r["arm"]))
    path = get(ENV, "E71_FIG", joinpath(dirname(OUT71), "e71c_figure.json"))
    open(io -> JSON.print(io, clean71(out), 1), path, "w")
    println("wrote $path")
    for r in out["rows"]
        println(JSON.json(clean71(r)))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    if MODE71 == "merge"
        merge71()
    elseif MODE71 == "merge_c"
        merge71c()
    elseif MODE71 == "figure"
        figure71c()
    else
        C71 == "" ? main71() : main71c()
    end
end
