# E6-refine: adaptive spatial resolution (manuscript Algorithm alg:refine,
# Proposition prop:refine, THEORY Sec. 5).
#
#   julia --project=env scripts/resolution/experiments/e6_refine.jl
#
# A heterogeneous 6 x 6 grid fleet (rows alternating quadrotors and ground
# vehicles) flies a formation past a disc obstacle that keeps out the ground
# vehicles only (keep-out linearized about a nominal plan). Starting from a
# coarse clustering, the loop of Algorithm alg:refine is run exactly as the
# manuscript states it:
#
#   solve P_Pi; compute eta_B = sum over the rigidified springs of B of
#   (1/2)||mu_e||^2_{W_e^{-1}}, with the minimum-norm internal forces recovered
#   block by block from the coarse solve; stop if sum eta <= eps; otherwise mark
#   a smallest set of clusters carrying at least theta = 0.5 of sum eta
#   (Dorfler marking) and split each marked cluster along a minimum cut of its
#   internal graph that separates the endpoints of its highest-eta spring.
#
# eps is 1e-2 of the initial estimate. For every iteration the record holds the
# clustering, sum eta, the true price (from a fine solve), the lower bound of
# Thm 2.7(b), which clusters split and their clearance to the obstacle. Three
# static runs: from whole rows (almost equitable, homogeneous), from 2 x 2
# blocks (mixing the two kinds), and from whole rows with incoherent references.
# Then a receding-horizon run (20 steps) with the clustering warm started from
# the previous step and the loop rerun at every step, against fine MPC: per-step
# clustering size, price bound, true price, solve effort, and the realized
# closed-loop cost. Writes results/e6_refine.json.

include(joinpath(@__DIR__, "common_spatial.jl"))

const OPTS6 = SolverOptions()
const SEED6 = 20260927
const THETA6 = 0.5
const EPS_FRAC6 = 1e-2
const RH_STEPS6 = 20
const OBSTACLE6 = (center = [3.6, 0.45], radius = 0.5, affects = :rover)

e6_scenario(; coherence::Symbol = :fleet) =
    FleetScenario(rows = 6, cols = 6, H = 10, h = 0.2, coherence = coherence,
                  obstacles = ObstacleT[OBSTACLE6], seed = SEED6)

"""Agents with at least one keep-out half-space in the program, and those active at a plan."""
function constrained_agents(spec::MPCSpec)
    return [i for i in 1:spec.n if !isempty(spec.halfspaces[i])]
end

function active_halfspace_agents(model::MPCModel, x::AbstractVector; tol = 1e-7)
    spec = model.spec
    out = Int[]
    for i in 1:spec.n, (t, a, beta) in spec.halfspaces[i]
        p = x[model.program.offsets[model.vid[i, t+1]] .+ (1:2)]
        if dot(a, p) - beta <= tol * max(1.0, abs(beta))
            push!(out, i)
        end
    end
    return sort(unique(out))
end

"""Smallest slack `abar - ||u||` of the input cones at a plan (positive: every cone strictly inside)."""
function min_input_slack(model::MPCModel, x::AbstractVector)
    s = Inf
    for i in 1:model.spec.n, t in 0:(model.spec.H-1)
        _, u = agent_state(model, x, i, t)
        s = min(s, model.spec.agents[i].abar - norm(u))
    end
    return s
end

"""
    refine_loop(model, solP, alpha0; eps, theta) -> (iterations, summary, final)

Algorithm alg:refine on one fixed program. `solP` is the fine optimum (used only
to report the true price and the lower bound, never by the algorithm).
"""
function refine_loop(model::MPCModel, solP::DirectSolution, alpha0::AbstractVector{<:Integer};
                     eps::Union{Nothing,Real} = nothing, eps_frac::Real = EPS_FRAC6, theta::Real = THETA6,
                     obstacle = OBSTACLE6, max_iter::Int = model.spec.n)
    P = model.program
    spec = model.spec
    gedges = spec.gedges
    fine_pos = planned_positions(model, solP.x)
    constrained = constrained_agents(spec)
    alpha = canonical_partition(alpha0)
    iters = Dict{String,Any}[]
    final = nothing
    terminated = false
    reason = "running"
    for it in 1:(max_iter+1)
        tp = @elapsed (Pc, L) = coarsen(P, spatial_partition(model, alpha))
        if Pc === nothing
            reason = "empty affine fibre"; break
        end
        ts = @elapsed solc = solve_direct(Pc; opts = OPTS6)
        if !isoptimal(solc)
            reason = "coarse program not solved: $(solc.status)"; break
        end
        te = @elapsed est = cluster_estimator(model, alpha, Pc, L, solc)
        z = lift(L, solc.x)
        S = [e for e in L.collapsed if !P.edges[e].hard]
        lower = price_lower_bound(P, S, solP.x)
        solH, muH = solve_hardened(P, L.collapsed; opts = OPTS6)
        muS = [muH[findfirst(==(e), L.collapsed)] for e in S]
        members = block_members(alpha)
        eta_sum = sum(est.eta_cluster)
        gamma = solc.J - solP.J
        rec = Dict{String,Any}(
            "iteration" => it, "clustering" => copy(alpha), "clusters" => members,
            "n_clusters" => length(members), "cluster_sizes" => length.(members),
            "eta_cluster" => est.eta_cluster, "eta_sum" => eta_sum,
            "eta_edge" => [Dict{String,Any}("edge" => [i, j], "eta" => v) for ((i, j), v) in sort(collect(est.eta_edge); by = first)],
            "J_coarse" => solc.J, "J_fine" => solP.J, "gamma" => gamma, "gamma_rel" => gamma / abs(solP.J),
            "lower" => lower, "bound_hardened_solver_multiplier" => price_upper_bound(P, S, muS),
            "J_hardened" => solH.J, "hardened_value_rel" => relerr(solH.J, solc.J),
            "residual" => est.residual, "fallbacks" => est.fallbacks,
            "coarse" => solstat(solc), "coarse_size" => Dict("vertices" => nvertices(Pc), "variables" => c0dim(Pc), "edges" => nedges(Pc)),
            "min_input_slack" => min_input_slack(model, z),
            "clearance" => [clearance(fine_pos, m, obstacle) for m in members],
            "clearance_t0" => [minimum(norm(spec.xhat[i][1:2] - obstacle.center) - obstacle.radius for i in m) for m in members],
            "constrained" => [any(in(constrained), m) for m in members],
            "active_at_coarse" => [any(in(active_halfspace_agents(model, z)), m) for m in members],
            "time_coarsen" => tp, "time_solve" => ts, "time_estimator" => te)
        push!(iters, rec)
        final = (alpha = copy(alpha), Pc = Pc, L = L, solc = solc, z = z)
        eps === nothing && (eps = eps_frac * eta_sum)          # eps = a fraction of the initial estimate
        if eta_sum <= eps
            terminated = true; reason = "sum eta <= eps"; break
        end
        if it > max_iter
            reason = "iteration limit"; break
        end
        marked = dorfler_mark(est.eta_cluster, theta)
        alpha_new, splits = refine_split(alpha, marked, est.eta_edge, gedges)
        rec["marked"] = marked
        rec["splits"] = splits
        rec["connected_after"] = sp_clusters_connected(alpha_new, gedges)
        rec["strict_refinement"] = maximum(alpha_new) > maximum(alpha) && is_refinement(alpha_new, alpha)
        alpha = alpha_new
    end
    nsplits = sum((length(get(r, "marked", Int[])) for r in iters); init = 0)
    summary = Dict{String,Any}("terminated" => terminated, "reason" => reason, "n_iterations" => length(iters),
                               "eta0" => isempty(iters) ? NaN : iters[1]["eta_sum"],
                               "n_splits" => nsplits, "n_agents" => spec.n, "initial_clusters" => maximum(canonical_partition(alpha0)),
                               "split_limit" => spec.n - maximum(canonical_partition(alpha0)), "eps" => eps,
                               "constrained_agents" => constrained)
    return iters, summary, final
end

"""Mean clearance of the clusters split at some iteration and of the splittable clusters left unsplit there."""
function split_clearance(iters)
    split = Float64[]; unsplit = Float64[]
    for r in iters
        haskey(r, "marked") || continue
        for (b, sz) in enumerate(r["cluster_sizes"])
            sz >= 2 || continue
            push!(b in r["marked"] ? split : unsplit, r["clearance"][b])
        end
    end
    return (split = split, unsplit = unsplit)
end

function static_run(name::String, sc::FleetScenario, alpha0::Vector{Int})
    spec = fleet_spec(sc)
    model = build_model(spec)
    P = model.program
    solP = solve_direct(P; opts = OPTS6)
    isoptimal(solP) || error("fine program not solved: $(solP.status)")
    iters, summary, _ = refine_loop(model, solP, alpha0)       # eps = 1e-2 of the initial estimate
    sc_ = split_clearance(iters)
    summary["mean_clearance_split"] = isempty(sc_.split) ? NaN : mean(sc_.split)
    summary["mean_clearance_unsplit"] = isempty(sc_.unsplit) ? NaN : mean(sc_.unsplit)
    summary["n_split_records"] = length(sc_.split)
    summary["n_unsplit_records"] = length(sc_.unsplit)
    fa = active_set(P, solP.x)
    return Dict{String,Any}("name" => name, "scenario" => scenario_dict(sc), "J_fine" => solP.J,
                            "fine" => solstat(solP), "fine_active_halfspaces" => length(fa.nonneg), "fine_active_soc" => length(fa.soc),
                            "halfspaces" => [[[t, a, b] for (t, a, b) in hs] for hs in spec.halfspaces],
                            "xhat" => spec.xhat, "fine_positions" => planned_positions(model, solP.x),
                            "iterations" => iters, "summary" => summary)
end

# ---------------------------------------------------------------------------
# Receding horizon
# ---------------------------------------------------------------------------

"""Stage cost of the realized closed loop at world time `t0`: tracking, effort and formation energy."""
function stage_cost(spec::MPCSpec, x::Vector{Vector{Float64}}, u::Union{Nothing,Vector{Vector{Float64}}})
    c = 0.0
    for i in 1:spec.n
        ag = spec.agents[i]
        e = ag.Cr * x[i] - spec.ref[i][:, 1]
        c += 0.5 * dot(e, ag.Q * e)
        u === nothing || (c += 0.5 * dot(u[i], ag.R * u[i]))
    end
    for (k, (i, j)) in enumerate(spec.gedges)
        d = spec.agents[j].C * x[j] - spec.agents[i].C * x[i] - spec.ftarget[:, k, 1]
        c += 0.5 * spec.fweight[k, 1] * dot(d, d)
    end
    return c
end

"""The plant: one exact step of every agent's dynamics with the applied input."""
plant_step(spec::MPCSpec, x, u) = [spec.agents[i].A[1] * x[i] + spec.agents[i].B[1] * u[i] + spec.agents[i].c[1] for i in 1:spec.n]

function rover_clearance(spec::MPCSpec, x, ob)
    return minimum((norm(x[i][1:2] - ob.center) - ob.radius for i in 1:spec.n
                    if ob.affects == :all || spec.agents[i].kind == ob.affects); init = Inf)
end

function receding_horizon(sc::FleetScenario, alpha0::Vector{Int}; steps::Int = RH_STEPS6)
    ob = sc.obstacles[1]
    layout = sp_grid(sc.rows, sc.cols; spacing = sc.spacing)[2]
    x0 = formation_start(sc, layout)
    # eps fixed for the whole run: 1e-2 of the estimate of alpha0 at the first step
    spec0 = fleet_spec(sc; xhat = x0)
    m0 = build_model(spec0)
    Pc0, L0 = coarsen(m0.program, spatial_partition(m0, alpha0))
    s0 = solve_direct(Pc0; opts = OPTS6)
    eta0 = sum(cluster_estimator(m0, alpha0, Pc0, L0, s0).eta_cluster)
    eps = EPS_FRAC6 * eta0
    # adaptive-resolution MPC
    xa = x0; nom = nothing; alpha = canonical_partition(alpha0)
    steps_rec = Dict{String,Any}[]
    cost_a = 0.0
    for k in 0:(steps-1)
        t0 = k * sc.h
        spec = fleet_spec(sc; xhat = xa, t0 = t0, nominal = nom)
        model = build_model(spec)
        tf = @elapsed solP = solve_direct(model.program; opts = OPTS6)
        isoptimal(solP) || error("fine program at step $k not solved: $(solP.status)")
        tl = @elapsed (iters, summary, final) = refine_loop(model, solP, alpha; eps = eps)
        final === nothing && error("adaptive loop failed at step $k: $(summary["reason"])")
        u = [agent_state(model, final.z, i, 0)[2] for i in 1:spec.n]
        xnext = plant_step(spec, xa, u)
        plan_x1 = [agent_state(model, final.z, i, 1)[1] for i in 1:spec.n]
        cost_a += stage_cost(spec, xa, u)
        last = iters[end]
        # merging back to alpha0 (the manuscript's remark after prop:refine): by Thm 2.7(b)
        # applied to P_{Pi_k} and the coarsening to alpha0, the merge costs at least the
        # energy the springs it would rigidify store at the current optimum
        merge = Dict{String,Any}("applicable" => false)
        if maximum(final.alpha) > maximum(canonical_partition(alpha0))
            P = model.program
            Pi0 = spatial_partition(model, alpha0)
            inside_k = Set(collapsed_edges(P, spatial_partition(model, final.alpha)))
            Sm = [e for e in collapsed_edges(P, Pi0) if !P.edges[e].hard && !(e in inside_k)]
            P0c, _ = coarsen(P, Pi0)
            s0m = P0c === nothing ? nothing : solve_direct(P0c; opts = OPTS6)
            J0m = s0m === nothing ? Inf : (isoptimal(s0m) ? s0m.J : (isinfeasible(s0m) ? Inf : NaN))
            merge = Dict{String,Any}("applicable" => true, "n_springs" => length(Sm),
                                     "lower" => price_lower_bound(P, Sm, final.z), "merge_price" => J0m - final.solc.J,
                                     "status" => s0m === nothing ? "empty affine fibre" : string(s0m.status))
        end
        push!(steps_rec, Dict{String,Any}("step" => k, "t0" => t0, "merge_to_initial" => merge,
            "positions" => [x[1:2] for x in xa], "clustering_initial" => copy(alpha),
            "clustering" => copy(final.alpha), "clusters" => block_members(final.alpha),
            "n_clusters" => maximum(final.alpha), "n_iterations" => length(iters), "n_splits" => summary["n_splits"],
            "terminated" => summary["terminated"], "eta_sum" => last["eta_sum"], "gamma" => last["gamma"],
            "gamma_rel" => last["gamma_rel"], "lower" => last["lower"], "J_fine" => solP.J, "J_coarse" => last["J_coarse"],
            "eta_sum_iterations" => [r["eta_sum"] for r in iters], "gamma_iterations" => [r["gamma"] for r in iters],
            "lower_iterations" => [r["lower"] for r in iters],
            "clarabel_iterations" => sum(r["coarse"]["iterations"] for r in iters),
            "coarse_variables" => last["coarse_size"]["variables"], "fine_variables" => c0dim(model.program),
            "time_loop" => tl, "time_fine_solve" => tf,
            "time_coarse_solves" => sum(r["time_solve"] for r in iters),
            "time_estimators" => sum(r["time_estimator"] for r in iters),
            "time_coarsenings" => sum(r["time_coarsen"] for r in iters),
            "first_transition_defect" => maximum(norm(plan_x1[i] - xnext[i], Inf) for i in 1:spec.n),
            "residual" => maximum(r["residual"] for r in iters), "fallbacks" => sum(r["fallbacks"] for r in iters),
            "min_input_slack" => minimum(r["min_input_slack"] for r in iters),
            "constrained_agents" => constrained_agents(spec),
            "clearance" => [clearance(planned_positions(model, solP.x), m, ob) for m in block_members(final.alpha)],
            "rover_clearance" => rover_clearance(spec, xa, ob),
            "planned_positions" => planned_positions(model, final.z)))
        nom = shifted_nominal(planned_positions(model, final.z))
        alpha = final.alpha
        xa = xnext
    end
    specK = fleet_spec(sc; xhat = xa, t0 = steps * sc.h, nominal = nom)
    cost_a += stage_cost(specK, xa, nothing)
    final_pos_a = [x[1:2] for x in xa]
    clear_a = min(minimum(s["rover_clearance"] for s in steps_rec), rover_clearance(specK, xa, ob))
    # fine MPC
    xf = x0; nomf = nothing
    fine_rec = Dict{String,Any}[]
    cost_f = 0.0
    for k in 0:(steps-1)
        t0 = k * sc.h
        spec = fleet_spec(sc; xhat = xf, t0 = t0, nominal = nomf)
        model = build_model(spec)
        tf = @elapsed solP = solve_direct(model.program; opts = OPTS6)
        isoptimal(solP) || error("fine MPC at step $k not solved: $(solP.status)")
        u = [agent_state(model, solP.x, i, 0)[2] for i in 1:spec.n]
        cost_f += stage_cost(spec, xf, u)
        push!(fine_rec, Dict{String,Any}("step" => k, "t0" => t0, "positions" => [x[1:2] for x in xf],
                                         "J" => solP.J, "time_solve" => tf, "clarabel_iterations" => solP.iterations,
                                         "variables" => c0dim(model.program), "rover_clearance" => rover_clearance(spec, xf, ob)))
        nomf = shifted_nominal(planned_positions(model, solP.x))
        xf = plant_step(spec, xf, u)
    end
    specKf = fleet_spec(sc; xhat = xf, t0 = steps * sc.h, nominal = nomf)
    cost_f += stage_cost(specKf, xf, nothing)
    clear_f = min(minimum(s["rover_clearance"] for s in fine_rec), rover_clearance(specKf, xf, ob))
    return Dict{String,Any}("scenario" => scenario_dict(sc), "steps" => steps, "eps" => eps, "eta0" => eta0,
        "initial_clustering" => canonical_partition(alpha0), "adaptive" => steps_rec, "fine" => fine_rec,
        "final_positions_adaptive" => final_pos_a, "final_positions_fine" => [x[1:2] for x in xf],
        "closed_loop_cost_adaptive" => cost_a, "closed_loop_cost_fine" => cost_f,
        "closed_loop_cost_ratio" => cost_a / cost_f,
        "min_rover_clearance_adaptive" => clear_a, "min_rover_clearance_fine" => clear_f,
        "time_adaptive_total" => sum(s["time_loop"] for s in steps_rec),
        "time_fine_total" => sum(s["time_solve"] for s in fine_rec))
end

# ---------------------------------------------------------------------------
# Figure layout (the renderer's schema) and main
# ---------------------------------------------------------------------------

function figure_block(run::Dict{String,Any}, sc::FleetScenario)
    edges, _ = sp_grid(sc.rows, sc.cols; spacing = sc.spacing)
    kinds = [string(sp_kind(sp_rowcol(i, sc.cols)[1])) for i in 1:nagents(sc)]
    return Dict{String,Any}(
        "run" => run["name"], "index_base" => 1,
        "agents" => [Dict{String,Any}("pos" => run["xhat"][i][1:2], "kind" => kinds[i]) for i in 1:nagents(sc)],
        "edges" => [[i, j] for (i, j) in edges],
        "obstacle" => Dict{String,Any}("center" => OBSTACLE6.center, "radius" => OBSTACLE6.radius, "affects" => string(OBSTACLE6.affects)),
        "epsilon" => run["summary"]["eps"],
        "iterations" => [Dict{String,Any}("clusters" => r["clusters"], "eta_sum" => r["eta_sum"], "gamma" => r["gamma"],
                                          "marked" => get(r, "marked", Int[])) for r in run["iterations"]],
        "note" => "positions at the planning instant t = 0 of the static run (the formation start); agent and cluster indices are 1-based; marked lists positions in the same iteration's clusters list; eta_sum is the certified bound and gamma the true price from a fine solve")
end

function figure_closed_loop(rh::Dict{String,Any}, sc::FleetScenario)
    kinds = [string(sp_kind(sp_rowcol(i, sc.cols)[1])) for i in 1:nagents(sc)]
    return Dict{String,Any}(
        "index_base" => 1, "kinds" => kinds, "h" => sc.h,
        "obstacle" => Dict{String,Any}("center" => OBSTACLE6.center, "radius" => OBSTACLE6.radius, "affects" => string(OBSTACLE6.affects)),
        "epsilon" => rh["eps"],
        "steps" => [Dict{String,Any}("step" => s["step"], "t" => s["t0"], "positions" => s["positions"],
                                     "clusters" => s["clusters"], "eta_sum" => s["eta_sum"], "gamma" => s["gamma"])
                    for s in rh["adaptive"]],
        "fine_positions" => [s["positions"] for s in rh["fine"]],
        "final_positions_adaptive" => rh["final_positions_adaptive"], "final_positions_fine" => rh["final_positions_fine"])
end

"""
Derived scalars for the manuscript's macros (scripts/resolution/numbers_spatial.jl),
computed from the per-iteration records above; the checks recompute their own.
"""
function e6_numbers(runs, rh)
    byname = Dict(r["name"] => r for r in runs)
    out = Dict{String,Any}()
    ratios = Float64[]; gam_over_eta = Float64[]
    for r in runs, it in r["iterations"]
        g, e = it["gamma"], it["eta_sum"]
        g > 1e-9 * abs(it["J_fine"]) && push!(ratios, e / g)
        e > 0 && push!(gam_over_eta, g / e)
    end
    for s in rh["adaptive"], (g, e) in zip(s["gamma_iterations"], s["eta_sum_iterations"])
        g > 1e-9 * abs(s["J_fine"]) && push!(ratios, e / g)
        e > 0 && push!(gam_over_eta, g / e)
    end
    out["looseness_min"] = minimum(ratios)
    out["looseness_max"] = maximum(ratios)
    out["looseness_median"] = median(ratios)
    out["gamma_over_eta_max"] = maximum(gam_over_eta)
    for (key, name) in (("rows", "rows"), ("blocks", "blocks2x2"), ("incoherent", "rows_incoherent"))
        r = byname[name]
        its = r["iterations"]
        s = r["summary"]
        first, last = its[1], its[end]
        lab = Dict{Int,Int}()
        for (b, m) in enumerate(last["clusters"]), a in m
            lab[a] = b
        end
        out[key] = Dict{String,Any}(
            "iterations" => length(its), "splits" => s["n_splits"], "split_limit" => s["split_limit"],
            "initial_clusters" => first["n_clusters"], "final_clusters" => last["n_clusters"],
            "eta_start" => first["eta_sum"], "gamma_start" => first["gamma"], "gamma_rel_start" => first["gamma_rel"],
            "eta_end" => last["eta_sum"], "gamma_end" => last["gamma"], "gamma_rel_end" => last["gamma_rel"], "eps" => s["eps"],
            "looseness_start" => first["eta_sum"] / first["gamma"],
            "clearance_split" => s["mean_clearance_split"], "clearance_unsplit" => s["mean_clearance_unsplit"],
            "initial_clusters_split" => count(m -> length(unique(lab[a] for a in m)) >= 2, first["clusters"]),
            "J_fine" => r["J_fine"])
    end
    st = rh["adaptive"]
    ms = [s["merge_to_initial"] for s in st if s["merge_to_initial"]["applicable"]]
    out["rh"] = Dict{String,Any}(
        "steps" => length(st), "clusters_start" => st[1]["n_clusters"], "clusters_end" => st[end]["n_clusters"],
        "splits" => sum(s["n_splits"] for s in st), "split_steps" => [s["step"] for s in st if s["n_splits"] > 0],
        "cost_ratio" => rh["closed_loop_cost_ratio"], "cost_excess" => rh["closed_loop_cost_ratio"] - 1, "cost_excess_percent" => 100 * (rh["closed_loop_cost_ratio"] - 1),
        "time_adaptive" => rh["time_adaptive_total"], "time_fine" => rh["time_fine_total"],
        "time_ratio" => rh["time_adaptive_total"] / rh["time_fine_total"], "eps" => rh["eps"],
        "eta_max" => maximum(s["eta_sum"] for s in st), "gamma_rel_max" => maximum(s["gamma_rel"] for s in st),
        "first_transition_defect_max" => maximum(s["first_transition_defect"] for s in st),
        "merge_steps" => length(ms), "merge_infeasible" => count(m -> !isfinite(m["merge_price"]), ms),
        "min_clearance_adaptive" => rh["min_rover_clearance_adaptive"], "min_clearance_fine" => rh["min_rover_clearance_fine"])
    return out
end

function main()
    tstart = time()
    rows, cols = 6, 6
    sc = e6_scenario()
    runs = Dict{String,Any}[]
    push!(runs, static_run("rows", sc, sp_rows(rows, cols)))
    push!(runs, static_run("blocks2x2", sc, sp_blocks(rows, cols, 2, 2)))
    push!(runs, static_run("rows_incoherent", e6_scenario(; coherence = :agents), sp_rows(rows, cols)))
    for r in runs
        s = r["summary"]
        @printf("%-16s iterations %2d splits %2d (limit %2d) terminated %s  eta0 %.3e eps %.3e final eta %.3e gamma %.3e  clearance split %.3f unsplit %.3f\n",
                r["name"], s["n_iterations"], s["n_splits"], s["split_limit"], s["terminated"], s["eta0"], s["eps"],
                r["iterations"][end]["eta_sum"], r["iterations"][end]["gamma"], s["mean_clearance_split"], s["mean_clearance_unsplit"])
    end
    rh = receding_horizon(sc, sp_rows(rows, cols))
    @printf("receding horizon: cost ratio %.6f, clusters %s, adaptive %.1f s, fine %.1f s\n", rh["closed_loop_cost_ratio"],
            string([s["n_clusters"] for s in rh["adaptive"]]), rh["time_adaptive_total"], rh["time_fine_total"])
    results = Dict{String,Any}("experiment" => "E6-refine", "seed" => SEED6, "meta" => run_metadata(OPTS6),
        "theta" => THETA6, "eps_fraction" => EPS_FRAC6,
        "estimator" => "eta_B = sum over the formation springs f_{ij,t} rigidified inside cluster B (all instants t) of (1/2)||mu||^2_{W^{-1}}, mu the minimum W^{-1}-norm internal force recovered block by block from the coarse solve (local_multipliers, normal cone a variable); the estimator of an agent-graph edge ij is the sum over t",
        "split_rule" => "minimum cut of the marked cluster's internal agent graph separating the endpoints of its highest-eta edge, capacities eta_ij + 1e-9 max eta, the cluster replaced by the connected components left by the cut",
        "clearance" => "min over the cluster's members and the instants 0..H of the fine plan of ||p - c|| - radius (planar)",
        "runs" => runs, "receding_horizon" => rh, "numbers" => e6_numbers(runs, rh),
        "n_agents" => nagents(sc), "H" => sc.H,
        "figure" => figure_block(runs[1], sc),
        "figure_runs" => Dict{String,Any}(r["name"] => figure_block(r, sc) for r in runs),
        "figure_closed_loop" => figure_closed_loop(rh, sc),
        "runtime_seconds" => time() - tstart)
    write_results("e6_refine", results)
    @printf("E6 runtime %.1f s\n", time() - tstart)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
