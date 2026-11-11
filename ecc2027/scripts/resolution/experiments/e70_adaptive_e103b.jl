# Provenance: e70_adaptive.jl blob 2c0e1e6, the version E103b and E112 loaded (HPG tree /blue/fairbanksj/itaykadosh/e71/tree, Nov 4); e70_adaptive.jl is the later E70b. Unchanged except this header.
# E70-adaptive: online team selection by refine-until-certified, within the sampling period.
#
# Natural formation (squads_dc.jl, BENCH_INSTANCE=natural), ball limits, nominal closed loop of E70_STEPS steps.
# Modes (E70_MODES, comma separated):
#   adapt<eps>  start from the data classes (one team per region). Control core, every sample: project, solve the
#               team program (E51's quotient program, the paper's solver, warm), evaluate the per-team terms
#               beta_c sum_{i in c} ||y_i||^2 of the imbalance bound B1 (Thm. thm:qbound) from the team plan,
#               broadcast. Selection core: if B1 > eps * J_team and no refinement is pending, split the teams with
#               the largest terms (greedily until their terms cover the excess B1 - eps J_team), each in two at the
#               largest gap of its members' totals into the neighbouring team that contributes most to its term,
#               build the refined quotient program and prime its solver at the current data; it replaces the
#               current one ceil(t_select / period) >= 1 samples later. Teams are never re-coarsened (they stay
#               in formation, so the coherent-data hypothesis of the bound holds at every sample).
#               (A canary refining inside the sample on one core needed 200-360 ms per round at 1000 vehicles,
#               the rebuild and the cold first solve each about 100-190 ms, so it cannot meet the period.)
#   classes     fixed: one team per data class
#   qs<q>       fixed: quasi-stable colouring with q (squads_dc.jl), computed once before the loop
# Timed per sample (one thread, the two cores simulated sequentially): control core = projection, solve, bound,
# broadcast; selection core = splitting, build, priming solve and bound. The deadline is E70_PERIOD_MS (200 ms)
# for the control core at every sample and for every selection round (met_select); met_one_core adds both. Offline (untimed, E70_GAP=1): at every sample's state and final
# teams, J* (full condensed program, Clarabel 1e-9) and J_team (same program restricted to team plans) give the
# true gap; B1 is also recomputed on the Clarabel team plan (E63's qbound63) as a check of the online bound.
#
#   BENCH_INSTANCE=natural E70_N=256 E70_SEEDS=1 julia --project=env scripts/resolution/experiments/e70_adaptive.jl
#   E70_MODE=merge E70_PARTDIR=<parts> julia --project=env scripts/resolution/experiments/e70_adaptive.jl

haskey(ENV, "BENCH_INSTANCE") || (ENV["BENCH_INSTANCE"] = "natural")
include(joinpath(@__DIR__, "e63_gap.jl"))
isdefined(Main, :Quot51) || include(joinpath(@__DIR__, "e51_symmetric.jl"))

const MODE70 = get(ENV, "E70_MODE", "run")
const N70 = parse(Int, get(ENV, "E70_N", "256"))
const SEEDS70 = parse.(Int, split(get(ENV, "E70_SEEDS", "1"), ","))
const STEPS70 = parse(Int, get(ENV, "E70_STEPS", "20"))
const MODES70 = split(get(ENV, "E70_MODES", "adapt0.01,adapt0.05,adapt0.1,classes,qs8"), ",")
const PERIOD70 = parse(Float64, get(ENV, "E70_PERIOD_MS", "200")) / 1e3
const GAP70 = get(ENV, "E70_GAP", "1") == "1"
const PARTDIR70 = get(ENV, "E70_PARTDIR", joinpath(ROOT27, "bench", "irregular", "results", "parts70"))
const OUT70 = get(ENV, "E70_OUT", joinpath(ROOT27, "results", "e70_adaptive.json"))
const H70 = H63G
const DT70 = DT63G

# ---------------------------------------------------------------------------
# The instance
# ---------------------------------------------------------------------------

"""Scenario26 of the instance on the fleet `fl` (E51's quotient needs fleet, slots, lanes, H, n)."""
function scenario70(inst, seed::Int, fl)
    n = length(inst.kinds)
    _, dp, dv = sq_start(inst, fl, seed)
    params = NamedTuple[sq_params_of(inst, i) for i in 1:n]
    wander = NamedTuple[(amp = 0.0, om = 0.0, ph = 0.0, omz = 0.0, phz = 0.0) for _ in 1:n]
    lab = SM.canonical_partition(inst.class)
    return Scenario26(isqrt(n), n, H70, DT70, CONE63G, :coherent, 0.0, seed, fl, inst.slots, sq_lanes(inst, seed), wander,
                      dp, dv, copy(inst.kinds), copy(inst.class), lab, sq_ranks(lab, inst.slots), params)
end

"""Adjacency of the formation graph (compressed): neighbours and weights of every vehicle."""
function adjacency70(n, edges, w)
    nb = [Int[] for _ in 1:n]; nw = [Float64[] for _ in 1:n]
    for ((i, j), x) in zip(edges, w)
        x == 0 && continue
        push!(nb[i], j); push!(nw[i], x); push!(nb[j], i); push!(nw[j], x)
    end
    return nb, nw
end

"""Algebraic connectivity of the edges inside the team `m` (0 if it is not connected or a single vehicle)."""
function lambda70(m::Vector{Int}, nb, nw)
    s = length(m); s < 2 && return 0.0
    pos = Dict(v => a for (a, v) in enumerate(m)); L = zeros(s, s)
    for (a, v) in enumerate(m), (u, x) in zip(nb[v], nw[v])
        b = get(pos, u, 0); (b == 0 || b <= a) && continue
        L[a, a] += x; L[b, b] += x; L[a, b] -= x; L[b, a] -= x
    end
    return max(eigvals(Symmetric(L))[2], 0.0)
end

# ---------------------------------------------------------------------------
# The per-team terms of B1 from the team plan of the quotient controller
# ---------------------------------------------------------------------------

"""
Per-team terms beta_c sum_{i in c} ||y_i||^2 of Thm. thm:qbound at the team plan of controller C (quotient Q):
y_i = sum_b (w(i, b) - wbar_cb) v_cb, v_cb the stacked Lambda_cb' rho_cb in the tracked-position coordinates
(as E63's qbound63). Also returns, per team, the neighbour b with the largest share sum_i (w(i,b) - wbar)^2 ||v_cb||^2
(the direction to split along).
"""
function terms70(C, Q, nb, nw, lamc::Vector{Float64}, cst)
    fq = Q.fleet; H = fq.H; nt = length(Q.teams)
    X, _ = SM.trajectories(C.fp, SM.plan(C))
    # v_cb for every quotient edge (both ends)
    V = Dict{Tuple{Int,Int},Vector{Float64}}()
    for (k, (a, b)) in enumerate(fq.edges)
        La = fq.select[k] * fq.agents[a].C * fq.agents[a].Cr'; Lb = fq.select[k] * fq.agents[b].C * fq.agents[b].Cr'
        va = Float64[]; vb = Float64[]
        for t in 1:H
            fq.present[k, t] || continue
            r = SM.edge_residual(fq, k, view(X[a], :, t + 1), view(X[b], :, t + 1), t)
            append!(va, -(La' * r)); append!(vb, Lb' * r)
        end
        V[(a, b)] = va; V[(b, a)] = vb
    end
    term = zeros(nt); dir = zeros(Int, nt)
    tot = Dict{Int,Float64}()
    for c in 1:nt
        m = Q.teams[c]; s = length(m)
        s < 2 && continue
        # members' totals into the neighbouring teams
        nbt = Int[]; idx = Dict{Int,Int}()
        D = Vector{Vector{Float64}}()
        for (a, v) in enumerate(m)
            empty!(tot)
            for (u, x) in zip(nb[v], nw[v])
                b = Q.team[u]; b == c && continue
                tot[b] = get(tot, b, 0.0) + x
            end
            for (b, x) in tot
                j = get(idx, b, 0)
                j == 0 && (push!(nbt, b); idx[b] = j = length(nbt); push!(D, zeros(s)))
                D[j][a] = x
            end
        end
        isempty(nbt) && continue
        Dm = reduce(hcat, D); Dm .-= sum(Dm; dims = 1) ./ s           # w(i, b) - wbar_cb
        Vm = reduce(hcat, (V[(c, b)] for b in nbt))
        Y = Dm * Vm'                                                 # rows y_i'
        betac = cst.sigma^2 / (2 * (cst.r + (cst.alpha + lamc[c]) * cst.sigma^2))
        term[c] = betac * sum(abs2, Y)
        share = vec(sum(abs2, Dm; dims = 1)) .* vec(sum(abs2, Vm; dims = 1))
        dir[c] = nbt[argmax(share)]
    end
    return term, dir
end

"""Split team c (members m) in two at the largest gap of the members' totals into team b."""
function split70(m::Vector{Int}, b::Int, team::Vector{Int}, nb, nw)
    x = zeros(length(m))
    for (a, v) in enumerate(m), (u, w) in zip(nb[v], nw[v])
        team[u] == b && (x[a] += w)
    end
    o = sortperm(x); g = argmax(diff(x[o]))
    return m[o[1:g]], m[o[(g+1):end]]
end

# ---------------------------------------------------------------------------
# One closed loop
# ---------------------------------------------------------------------------

function loop70(inst, seed::Int, mode::AbstractString; steps::Int = STEPS70, gap::Bool = GAP70, quiet::Bool = false)
    n = length(inst.kinds)
    fl = sq_fleet(inst, DT70, H70, CONE63G)
    sc = scenario70(inst, seed, fl)
    lanes = sq_lanes(inst, seed)
    cf = cfleet63(fl, H70)
    nb, nw = adjacency70(n, inst.edges, inst.w)
    qb0 = qbound_setup63(cf, SM.canonical_partition(inst.class), 0.0)       # r, alpha, sigma (the models only)
    cst = (r = qb0.r, alpha = qb0.alpha, sigma = qb0.sigma)
    adapt = startswith(mode, "adapt")
    eps = adapt ? parse(Float64, mode[6:end]) : NaN
    tsel = @elapsed (lab = adapt || mode == "classes" ? SM.canonical_partition(inst.class) : sq_teams(inst, mode, seed)[1])
    lamcache = Dict{Vector{Int},Float64}()
    lamof(m) = get!(() -> lambda70(m, nb, nw), lamcache, m)
    GC.gc()
    tb0 = @elapsed (Q = Quot51(sc, lab); C = controller51(Q.fleet))
    x, _, _ = sq_start(inst, fl, seed)
    cost = 0.0; recs = Dict{String,Any}[]; X =Vector{Vector{Vector{Float64}}}(); LAB = Vector{Vector{Int}}()
    pending = nothing                 # a refinement being prepared on the second core: (Q, C, ready_at, B1 at prime)
    for k in 0:(steps-1)
        refs, term = sq_references(inst, lanes, fl, k * DT70, DT70, H70)
        swapped = false
        if pending !== nothing && k >= pending.ready
            Q, C = pending.Q, pending.C; pending = nothing; swapped = true
        end
        # the control core: project, solve warm, bound, broadcast
        t0 = time_ns()
        xq, rq, tq = teamdata51(Q, sc, x, refs, term)
        info = SM.step!(C, xq, rq; terminal = tq)
        t1 = time_ns()
        lamc = [lamof(m) for m in Q.teams]
        tm, dir = terms70(C, Q, nb, nw, lamc, cst)
        B = sum(tm); Jt = info.J
        u = [copy(info.u[Q.team[i]]) for i in 1:n]
        t2 = time_ns()
        tcrit = (t2 - t0) / 1e9; tsolve = (t1 - t0) / 1e9; tbound = (t2 - t1) / 1e9
        teams_now = length(Q.teams); lab_now = copy(Q.team)
        # the selection core: if not certified and nothing pending, split and prepare the refined program
        tbg = 0.0; splits = 0; Bnew = NaN; launched = false; tbuild = 0.0; tprime = 0.0
        if adapt && B > eps * Jt && pending === nothing
            launched = true
            tbg = @elapsed begin
                excess = B - eps * Jt
                order = sortperm(tm; rev = true); covered = 0.0
                newlab = copy(Q.team); nxt = length(Q.teams)
                for c in order
                    (covered >= excess || tm[c] <= 0) && break
                    _, p2 = split70(Q.teams[c], dir[c], Q.team, nb, nw)
                    nxt += 1; newlab[p2] .= nxt
                    covered += tm[c]; splits += 1
                end
                tbuild = @elapsed (Q2 = Quot51(sc, newlab); C2 = controller51(Q2.fleet))
                tprime = @elapsed begin                     # set up the solver and a warm start at the current data
                    xq2, rq2, tq2 = teamdata51(Q2, sc, x, refs, term)
                    info2 = SM.step!(C2, xq2, rq2; terminal = tq2)
                    tm2, _ = terms70(C2, Q2, nb, nw, [lamof(m) for m in Q2.teams], cst)
                end
                Bnew = sum(tm2) / info2.J
            end
            pending = (Q = Q2, C = C2, ready = k + max(1, ceil(Int, tbg / PERIOD70)))
        end
        uc, viol = clip26(sc, u)
        l, form, cross = sq_stage(fl, x, uc, refs; lab = lab_now)
        cost += l
        push!(recs, Dict{String,Any}("step" => k, "t_total" => tcrit, "t_solve" => tsolve, "t_bound" => tbound,
                                     "t_select" => tbg, "t_build" => tbuild, "t_prime" => tprime, "launched" => launched,
                                     "ready_in" => launched ? pending.ready - k : 0, "swapped" => swapped,
                                     "splits" => splits, "teams" => teams_now, "B1" => B, "Jteam_online" => Jt, "B1_rel" => B / Jt,
                                     "B1_rel_refined" => launched ? Bnew : nothing,
                                     "certified" => adapt ? B <= eps * Jt : nothing, "met" => tcrit <= PERIOD70,
                                     "met_select" => tbg <= PERIOD70, "met_one_core" => tcrit + tbg <= PERIOD70,
                                     "status" => string(info.status), "iter" => info.iter, "viol" => viol, "stage" => l))
        push!(X, [copy(v) for v in x]); push!(LAB, lab_now)
        x = sq_plant(fl, x, uc)
        if !quiet
            @printf("  %-10s k %2d teams %4d%s B1/J %.4f  ctrl %6.1f ms (solve %.1f bound %.1f)  select %6.1f ms (splits %3d build %.1f prime %.1f, B1/J after %.4f)  %s\n",
                    mode, k, teams_now, swapped ? "*" : " ", B / Jt, 1e3 * tcrit, 1e3 * tsolve, 1e3 * tbound, 1e3 * tbg, splits,
                    1e3 * tbuild, 1e3 * tprime, Bnew, string(info.status)); flush(stdout)
        end
    end
    refs, _ = sq_references(inst, lanes, fl, steps * DT70, DT70, H70)
    cost += sq_stage(fl, x, nothing, refs)[1]
    # offline: the true gap at every sample's state and final teams
    if gap
        K = Cons63(cf, CONE63G)
        x0 = X[1]
        r0, t0_ = sq_references(inst, lanes, fl, 0.0, DT70, H70)
        base = CProg(cf, CData(x0, r0, t0_))
        Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
        Hown = H0blk30(cf)
        qbc = Dict{Vector{Int},Any}()
        for (k, rec) in enumerate(recs)
            refs, term = sq_references(inst, lanes, fl, (k - 1) * DT70, DT70, H70)
            P = CProg(base, CData(X[k], refs, term))
            _, hq, c = quad63(P, Hb)
            full = solve63(Hb, hq, c, K, nothing; E = P.E, e = P.e)
            tm = solve63(Hb, hq, c, K, teamZ63(cf, LAB[k]); E = P.E, e = P.e)
            qb = get!(() -> qbound_setup63(cf, LAB[k], 0.0), qbc, LAB[k])
            qbr = qbound63(P, Hown, qb, tm.u, inst.slots)
            rec["Jstar"] = full.J; rec["Jteam"] = tm.J; rec["gap"] = tm.J - full.J
            rec["gap_rel"] = (tm.J - full.J) / abs(full.J); rec["gap_over_Jteam"] = (tm.J - full.J) / abs(tm.J)
            rec["B1_offline"] = qbr["B1"]; rec["t_full"] = full.seconds; rec["t_team_clarabel"] = tm.seconds
            rec["status_full"] = full.status; rec["status_team"] = tm.status
            rec["bound_holds"] = rec["B1"] >= rec["gap"] - 1e-6 * abs(full.J)
            if !quiet
                @printf("    offline k %2d gap/J* %.4f gap/Jt %.4f  B1/gap %.2f (offline %.2f)  Jt online/offline %.6f\n", k - 1,
                        rec["gap_rel"], rec["gap_over_Jteam"], rec["B1"] / max(rec["gap"], 1e-300), qbr["B1"] / max(rec["gap"], 1e-300),
                        rec["Jteam_online"] / tm.J); flush(stdout)
            end
        end
    end
    after = recs[2:end]
    col(key) = [Float64(r[key]) for r in after]
    out = Dict{String,Any}("mode" => mode, "eps" => adapt ? eps : nothing, "closed_loop_cost" => cost, "select_seconds_offline" => tsel,
                           "build0_seconds" => tb0, "teams_final" => length(Q.teams), "steps" => recs,
                           "t_total" => sumstats26_(col("t_total")), "t_total_all" => sumstats26_([r["t_total"] for r in recs]),
                           "met_frac" => count(r -> r["met"], recs) / length(recs),
                           "met_frac_after0" => count(r -> r["met"], after) / max(length(after), 1),
                           "launches" => count(r -> r["launched"], recs), "splits_total" => sum(r["splits"] for r in recs),
                           "t_select_max" => maximum(r["t_select"] for r in recs), "met_select_frac" => count(r -> r["met_select"], recs) / length(recs),
                           "met_one_core_frac" => count(r -> r["met_one_core"], recs) / length(recs))
    adapt && (out["certified_frac"] = count(r -> r["certified"], recs) / length(recs))
    if gap
        out["gap_rel"] = sumstats26_([r["gap_rel"] for r in recs])
        out["gap_over_Jteam"] = sumstats26_([r["gap_over_Jteam"] for r in recs])
        out["bound_violations"] = count(r -> !r["bound_holds"], recs)
        adapt && (out["gap_le_eps_frac"] = count(r -> r["gap_over_Jteam"] <= eps, recs) / length(recs))
    end
    return out
end

function run70(n::Int, seed::Int; modes = MODES70, steps::Int = STEPS70, gap::Bool = GAP70, quiet::Bool = false)
    inst = sq_instance(n, seed)
    res = Dict{String,Any}("instance" => INST63G, "n_requested" => n, "seed" => seed, "n" => length(inst.kinds),
                           "edges" => length(inst.edges), "classes" => maximum(inst.class), "cone" => string(CONE63G),
                           "period_ms" => 1e3 * PERIOD70, "steps" => steps, "modes" => Dict{String,Any}())
    for mode in modes
        quiet || (@printf("E70 n=%d seed %d mode %s\n", res["n"], seed, mode); flush(stdout))
        res["modes"][mode] = loop70(inst, seed, mode; steps = steps, gap = gap, quiet = quiet)
        o = res["modes"][mode]
        quiet || (@printf("  => teams %d  ms med %.1f max %.1f  met %.2f  cert %s  gap/J* med %s\n", o["teams_final"],
                          1e3 * o["t_total"]["median"], 1e3 * o["t_total"]["max"], o["met_frac"], string(get(o, "certified_frac", "-")),
                          gap ? @sprintf("%.4f", o["gap_rel"]["median"]) : "-"); flush(stdout))
    end
    return res
end

function main70()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR70)
    get(ENV, "E70_WARMUP", "1") == "1" && run70(48, 1; modes = ["adapt0.01", "classes", "qs8"], steps = 3, gap = true, quiet = true)
    for seed in SEEDS70
        res = run70(N70, seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model)
        tag = join(MODES70, "+")
        path = joinpath(PARTDIR70, @sprintf("e70_%s_n%d_%s_seed%d.json", INST63G, N70, tag, seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

"""Merge the parts: per (n, mode) medians over seeds and samples."""
function merge70()
    parts = [JSON.parsefile(joinpath(PARTDIR70, f)) for f in readdir(PARTDIR70) if endswith(f, ".json")]
    rows = Dict{String,Any}()
    for p in parts, (mode, o) in p["modes"]
        key = "n$(p["n_requested"])_$mode"
        r = get!(rows, key, Dict{String,Any}("n_requested" => p["n_requested"], "mode" => mode, "runs" => Any[]))
        push!(r["runs"], merge(Dict{String,Any}("seed" => p["seed"], "n" => p["n"]), Dict(k => v for (k, v) in o if k != "steps")))
        for s in o["steps"]
            push!(get!(r, "samples", Any[]), s)
        end
    end
    for (key, r) in rows
        S = r["samples"]; S1 = [s for s in S if s["step"] > 0]
        r["n_median"] = median([x["n"] for x in r["runs"]]); r["seeds"] = length(r["runs"])
        r["ms_median"] = 1e3 * median([s["t_total"] for s in S1]); r["ms_max"] = 1e3 * maximum(s["t_total"] for s in S1)
        r["ms_max_step0"] = 1e3 * maximum(s["t_total"] for s in S if s["step"] == 0)
        r["met_frac"] = count(s -> s["met"], S) / length(S); r["met_frac_after0"] = count(s -> s["met"], S1) / length(S1)
        r["teams_median"] = median([s["teams"] for s in S]); r["teams_max"] = maximum(s["teams"] for s in S)
        r["launches"] = count(s -> s["launched"], S); r["splits_total"] = sum(s["splits"] for s in S)
        r["select_ms_max"] = 1e3 * maximum(s["t_select"] for s in S)
        r["select_ms_median_launched"] = (L = [s["t_select"] for s in S if s["launched"]]; isempty(L) ? nothing : 1e3 * median(L))
        r["met_select_frac"] = count(s -> s["met_select"], S) / length(S); r["met_one_core_frac"] = count(s -> s["met_one_core"], S) / length(S)
        r["ready_in_max"] = maximum(s["ready_in"] for s in S)
        r["B1_rel_median"] = median([s["B1_rel"] for s in S])
        if startswith(r["mode"], "adapt")
            r["certified_frac"] = count(s -> s["certified"], S) / length(S)
            r["certified_frac_after0"] = count(s -> s["certified"], S1) / length(S1)
        end
        if haskey(S[1], "gap")
            r["gap_rel_median"] = median([s["gap_rel"] for s in S]); r["gap_rel_max"] = maximum(s["gap_rel"] for s in S)
            r["gap_over_Jteam_max"] = maximum(s["gap_over_Jteam"] for s in S)
            r["bound_violations"] = count(s -> !s["bound_holds"], S)
            g = [s["B1"] / s["gap"] for s in S if s["gap"] > 1e-7 * abs(s["Jstar"])]
            isempty(g) || (r["B1_over_gap_median"] = median(g); r["B1_over_gap_min"] = minimum(g))
            r["Jteam_online_over_offline_range"] = [extrema(s["Jteam_online"] / s["Jteam"] for s in S)...]
        end
        delete!(r, "samples")
    end
    out = Dict("experiment" => "e70_adaptive", "period_ms" => 1e3 * PERIOD70, "rows" => rows)
    open(io -> JSON.print(io, out, 1), OUT70, "w")
    println("wrote $OUT70")
    for key in sort(collect(keys(rows)); by = k -> (rows[k]["n_requested"], rows[k]["mode"]))
        r = rows[key]
        @printf("%-18s n %6.0f seeds %d teams %5.0f (max %4d)  ms med %6.1f max %6.1f (k0 %6.1f)  met %.3f  cert %s  gap/J* med %s max %s  B1/gap med %s  viol %s\n",
                key, r["n_median"], r["seeds"], r["teams_median"], r["teams_max"], r["ms_median"], r["ms_max"], r["ms_max_step0"],
                r["met_frac"], string(round(get(r, "certified_frac", NaN); digits = 3)),
                string(round(get(r, "gap_rel_median", NaN); digits = 4)), string(round(get(r, "gap_rel_max", NaN); digits = 4)),
                string(round(get(r, "B1_over_gap_median", NaN); digits = 2)), string(get(r, "bound_violations", "-")))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE70 == "run" ? main70() : merge70()
end
