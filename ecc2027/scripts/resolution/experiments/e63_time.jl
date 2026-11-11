# E63-time: time per step on the irregular squad formation (squads_dc.jl), team MPC against the baselines.
#
# The fleet: squads of 4 to 16 drones or cars, one (type, variant) per squad, random squad graph, between two
# adjacent squads irregular edges with equal per-member totals (almost equitable, essentially no symmetry).
# E63_EPS > 0 perturbs the edges between squads (almost equitability fails; teams from quasi-stable colouring,
# lossy); E63_SPREAD > 0 spreads every member's drag and input bound (near-coherent; team MPC then plans with
# the nominal squad model and the plant runs the true one).
#
# Paths (E63_PATHS, comma separated):
#   team     team MPC: the quotient program of the teams (one vehicle per team, E51's Quot51, built offline
#            once from the graph), MPCController condensed, warm; the step averages the measured states
#            over each team, solves, broadcasts
#   orbits   the quotient of the coarsest EQUITABLE partition (ordinary colour refinement): symmetric MPC
#            reduces by orbits, which refine it, so this is a lower bound on symmetric MPC's size and time
#   coord    coordinated MPC, MPCController condensed, warm (n <= E63_COORDN)
#   lifted   E54's lifted QP: colour refinement of the coordinated QP's data at every sample (n <= E63_LIFTN)
#   admm     E52's consensus ADMM over the fleet (full) and over the team quotient (quot), budget E63_BUDGET
#   replay   Clarabel (and OSQP warm for box limits) on the condensed coordinated QP along coord's states
#   diag     the generic reduction (E26's 'red': time-expanded reduction, merged cones) of the same teams:
#            its cone count and time, the cause of slow lossy teams in E60 (per-member cones kept)
#
#   E63_N=256 E63_SEEDS=1 julia --project=env scripts/resolution/experiments/e63_time.jl
#   E63_MODE=merge E63_PARTDIR=<parts> julia --project=env scripts/resolution/experiments/e63_time.jl

isdefined(Main, :Scenario26) || include(joinpath(@__DIR__, "e26_flagship_dc.jl"))
isdefined(Main, :Quot51) || include(joinpath(@__DIR__, "e51_symmetric.jl"))
for f in ("e52_admm.jl", "e54_lifted.jl")
    src = replace(read(joinpath(@__DIR__, f), String), "include(joinpath(@__DIR__, \"e51_symmetric.jl\"))" => "")
    include_string(Main, src, joinpath(@__DIR__, f))
end
include(joinpath(@__DIR__, "squads_dc.jl"))

const MODE63 = get(ENV, "E63_MODE", "run")
const N63 = parse(Int, get(ENV, "E63_N", "256"))
const SEEDS63 = parse.(Int, split(get(ENV, "E63_SEEDS", "1"), ","))
const STEPS63 = parse(Int, get(ENV, "E63_STEPS", "30"))
const CONE63 = Symbol(get(ENV, "E63_CONE", "soc"))
const PATHS63 = split(get(ENV, "E63_PATHS", "team,orbits,coord,lifted,replay"), ",")
const TEAMS63 = get(ENV, "E63_TEAMS", SQ_EPS == 0 ? "aep" : "qs0.1")
const COORDN63 = parse(Int, get(ENV, "E63_COORDN", "4096"))
const LIFTN63 = parse(Int, get(ENV, "E63_LIFTN", "4096"))
const REPLAYN63 = parse(Int, get(ENV, "E63_REPLAYN", "1024"))
const BUDGET63 = parse.(Int, split(get(ENV, "E63_BUDGET", "5,20"), ","))
const RHO63 = Dict("full" => parse(Float64, get(ENV, "E63_RHO_FULL", "0.3")), "quot" => parse(Float64, get(ENV, "E63_RHO_QUOT", "10")))
const PARTDIR63 = get(ENV, "E63_PARTDIR", joinpath(ROOT26, "bench", "irregular", "results", "parts63"))

"""Scenario26 of a squad instance (E26's controllers, loops and baselines run on it unchanged); `team` the labels."""
function scenario63(inst, seed::Int, team::Vector{Int}; nominal::Bool = false, cone::Symbol = CONE63)
    n = length(inst.kinds)
    fl = sq_fleet(inst, DT26, H26, cone; nominal = nominal)
    _, dp, dv = sq_start(inst, fl, seed)
    params = NamedTuple[sq_params_of(inst, i; nominal = nominal) for i in 1:n]
    wander = NamedTuple[(amp = 0.0, om = 0.0, ph = 0.0, omz = 0.0, phz = 0.0) for _ in 1:n]
    rank = sq_ranks(team, inst.slots)
    return Scenario26(isqrt(n), n, H26, DT26, cone, :coherent, 0.0, seed, fl, inst.slots, sq_lanes(inst, seed), wander,
                      dp, dv, copy(inst.kinds), copy(inst.class), SM.canonical_partition(team), rank, params)
end

function run63(seed::Int; n::Int = N63, steps::Int = STEPS63, paths = PATHS63, quiet::Bool = false)
    inst = sq_instance(n, seed); n = length(inst.kinds)
    res = Dict{String,Any}("instance" => get(ENV, "BENCH_INSTANCE", "squads"), "n_requested" => N63, "seed" => seed, "n" => length(inst.kinds), "eps" => inst.eps, "spread" => inst.spread, "cone" => string(CONE63),
                           "squads" => inst.nsquads, "classes" => length(unique(inst.class)), "edges" => length(inst.edges),
                           "load" => loadavg26(), "teams_choice" => TEAMS63)
    lab, tcr = sq_teams(inst, TEAMS63, seed)
    orb, torb = sq_teams(inst, "equitable", seed)
    res["teams"] = maximum(lab); res["refine_seconds"] = tcr
    res["orbits_bound"] = maximum(orb); res["equitable_seconds"] = torb
    res["teams_spread"] = sq_spread(n, inst.edges, inst.w, lab)[1]
    res["teams_are_squads_or_coarser"] = all(length(unique(lab[inst.squad .== k])) == 1 for k in 1:inst.nsquads)
    res["almost_equitable"] = SM.is_almost_equitable(n, inst.edges, inst.w, lab)
    sc = scenario63(inst, seed, lab)                        # true model: plant and coordinated MPC
    scn = inst.spread > 0 ? scenario63(inst, seed, lab; nominal = true) : sc   # team MPC's model
    U = Dict{String,Any}()
    if "team" in paths
        GC.gc()
        tb = @elapsed (Q = Quot51(scn, lab); C = controller51(Q.fleet))
        GC.gc()
        out, us = loop51(sc, C, Q; steps = steps)
        out["build_seconds"] = tb; out["teams"] = length(Q.teams); out["qp"] = qpsize51(C)
        res["team"] = out; U["team"] = us
    end
    if "orbits" in paths && inst.spread == 0
        GC.gc()
        tb = @elapsed (Q = Quot51(sc, orb); C = controller51(Q.fleet))
        GC.gc()
        out, us = loop51(sc, C, Q; steps = steps)
        out["build_seconds"] = tb; out["teams"] = length(Q.teams); out["qp"] = qpsize51(C)
        res["orbits"] = out; U["orbits"] = us
    end
    traj = nothing
    if "coord" in paths && n <= COORDN63
        GC.gc()
        tb = @elapsed (C = controller51(sc.fleet))
        GC.gc()
        out, us = loop51(sc, C, nothing; steps = steps)
        out["build_seconds"] = tb; out["teams"] = n; out["qp"] = qpsize51(C)
        res["coord"] = out; U["coord"] = us
    end
    if "lifted" in paths && n <= LIFTN63 && inst.spread == 0
        GC.gc()
        out, us = lifted_loop54(sc; steps = steps, check = false)
        delete!(out, "steps")
        res["lifted"] = out; U["lifted"] = us
    end
    if "admm" in paths
        Qa = Quot51(scn, lab)
        Cref = central52(sc.fleet)
        Jc = haskey(res, "coord") ? res["coord"]["closed_loop_cost"] : NaN
        res["admm"] = Dict{String,Any}()
        for b in BUDGET63, m in ("full", "quot")
            o = loop52(m, sc, Qa, RHO63[m], b, Cref; steps = steps)
            o["cost_ratio"] = o["closed_loop_cost"] / Jc
            delete!(o, "steps")
            res["admm"]["$(m)_b$b"] = o
        end
    end
    if "replay" in paths && n <= REPLAYN63
        GC.gc()
        F = Form26(sc, "cond")
        lo, tr = graph_loop26(sc, F, start26(sc); steps = steps)
        res["replay"] = Dict{String,Any}()
        for name in (CONE63 == :soc ? ("clarabel",) : ("clarabel", "osqp_warm"))
            F2 = Form26(sc, "cond")
            r = replay26(sc, F2, name, tr; steps = steps)
            delete!(r, "steps")
            res["replay"][name] = r
        end
        o = Dict{String,Any}("closed_loop_cost" => lo["closed_loop_cost"])
        v = [s["t_total"] for s in lo["steps"][2:end]]
        o["t_total"] = sumstats26(v)
        res["replay"]["teammpc_cond"] = o
    end
    if "diag" in paths
        GC.gc()
        tb = @elapsed (F = Form26(scn, "red"))
        lo, _ = graph_loop26(sc, F, start26(sc); steps = min(steps, 5))
        v = [s["t_total"] for s in lo["steps"][2:end]]
        res["diag_generic"] = Dict{String,Any}("build_seconds" => tb, "t_total" => sumstats26(v), "cones" => length(F.G.qp.socs),
                                               "variables" => length(F.G.qp.q), "merged_cones" => F.G.merged_cones,
                                               "closed_loop_cost_5" => lo["closed_loop_cost"])
    end
    for (a, b) in (("coord", "team"), ("coord", "orbits"), ("coord", "lifted"), ("team", "lifted"))
        (haskey(U, a) && haskey(U, b)) || continue
        res["input_diff_$(a)_$(b)"] = maxdiff26(U[a], U[b])
        res["cost_ratio_$(b)_$(a)"] = res[b]["closed_loop_cost"] / res[a]["closed_loop_cost"]
    end
    if !quiet
        @printf("E63 n=%d seed %d eps %.3g spread %.3g: squads %d classes %d, teams %d (%s, AE %s, spread %.2e, %.3f s), equitable %d\n",
                n, seed, inst.eps, inst.spread, inst.nsquads, res["classes"], res["teams"], TEAMS63, res["almost_equitable"],
                res["teams_spread"], tcr, res["orbits_bound"])
        for k in ("team", "orbits", "coord", "lifted")
            haskey(res, k) || continue
            o = res[k]
            @printf("  %-7s ms/step med %9.3f max %9.3f  cost %.6e\n", k, ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]),
                    o["closed_loop_cost"])
        end
        haskey(res, "diag_generic") && @printf("  generic reduction: cones %d vars %d ms/step med %.1f\n", res["diag_generic"]["cones"],
                                               res["diag_generic"]["variables"], ms26(res["diag_generic"]["t_total"]["median"]))
        for key in sort!(filter(k -> startswith(k, "cost_ratio") || startswith(k, "input_diff"), collect(keys(res))))
            @printf("  %s %.3e\n", key, res[key])
        end
        flush(stdout)
    end
    return res
end

function main63()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR63)
    run63(1; n = 32, steps = 3, quiet = true, paths = filter(!=("admm"), PATHS63))    # warm-up
    for seed in SEEDS63
        res = run63(seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "steps" => STEPS63, "paths" => PATHS63)
        tag = @sprintf("e63_%s_n%d_eps%g_spread%g_%s_%s_seed%d", get(ENV, "BENCH_INSTANCE", "squads"), N63, SQ_EPS, SQ_SPREAD, CONE63, TEAMS63, seed)
        path = joinpath(PARTDIR63, tag * ".json")
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE63 == "run" && main63()
end
