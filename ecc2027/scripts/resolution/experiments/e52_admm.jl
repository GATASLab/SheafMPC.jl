# E52-admm: does the reduction help a distributed solver too? Consensus ADMM
# (the package's DistributedMPC: general-form consensus ADMM over the fully
# condensed program, one exchange per neighbour per iteration, Boyd et al.
# 2011 Sec. 7.2, Summers and Lygeros 2012) run on the fleet's graph (one agent
# per vehicle) against the same ADMM on the quotient graph of the rows (one
# agent per row, E41's quotient program, plus one gather and one broadcast
# inside every row per sample). E26's coherent fleet, ball limits, so the
# quotient is exact (Thm. thm:equitable) and both converge to coordinated MPC.
#
#   BENCH_SIDE=32 BENCH_SEEDS=1,2 julia --project=env scripts/resolution/experiments/e52_admm.jl
#   E52_MODE=merge E52_PARTDIR=<parts> julia --project=env scripts/resolution/experiments/e52_admm.jl
#
# Per size (seed 1 only for the tuning):
#   tune     rho of each method from E52_RHOS (cold start at step 0: iterations
#            until the plan's objective is within 1e-3 of the optimum, at most
#            E52_TUNE_MAXIT)
# Per seed:
#   coord    coordinated MPC (MPCController on the condensed program, TeamMPC,
#            MPCController's accuracy): the closed-loop cost reference
#   trace    at the states of steps E52_TRACE_STEPS of coord's loop, ADMM from a
#            cold start, one iteration at a time up to E52_TRACE_MAXIT: the
#            relative suboptimality (J(plan) - J*) / J* after every iteration
#            (J* from a tight central solve at that state, 1e-9), iterations and
#            time to reach 1e-2, 1e-3, 1e-4
#   loops    for every budget b of E52_BUDGETS: the closed loop of ADMM with b
#            iterations per sample (warm started by the shifted previous plan,
#            the package's default), on the fleet and on the quotient. Per
#            step: relative suboptimality of the applied plan at the measured
#            state (J* by a tight central solve of the coordinated program),
#            sequential and parallel time, rounds and floats; per loop the
#            closed-loop cost relative to coord's.
#
# Communication per sample (recorded per method; `rounds` are message exchanges,
# `floats` the numbers sent):
#   coordinated, team MPC (central)   2 rounds: states up (6 n), inputs down (3 n)
#   ADMM over vehicles                b rounds, DistributedMPC's interface floats
#   ADMM over rows (quotient)         b + 2 rounds: inside every row the members send their
#                                     states to the row's agent (6 n) and receive their input
#                                     (3 n); between rows the quotient's interface floats
#   decentralized MPC                 0 rounds (neighbours sensed)
#
# Times: sequential is all agents' work on one core; parallel is, per
# iteration, the slowest local solve, plus the rest of the step divided over
# the agents (E27's accounting), plus for the quotient the gather (averaging)
# and broadcast. Communication latency is not included.
#
# The quotient is E51's (Quot51: one agent per lossless team, from colour
# refinement of the data classes; the rows for E26's fleet).

include(joinpath(@__DIR__, "e51_symmetric.jl"))

const MODE52 = get(ENV, "E52_MODE", "run")
const PARTDIR52 = get(ENV, "E52_PARTDIR", joinpath(ROOT26, "bench", "baselines", "results", "parts52"))
const OUT52 = get(ENV, "E52_OUT", joinpath(ROOT26, "results", "e52_admm.json"))
const RHOS52 = parse.(Float64, split(get(ENV, "E52_RHOS", "0.1,0.3,1,3,10,30,100,300"), ","))
const TUNE_MAXIT52 = parse(Int, get(ENV, "E52_TUNE_MAXIT", "300"))
const TRACE_MAXIT52 = parse(Int, get(ENV, "E52_TRACE_MAXIT", "500"))
const TRACE_STEPS52 = parse.(Int, split(get(ENV, "E52_TRACE_STEPS", "0,10,20"), ","))
const BUDGETS52 = parse.(Int, split(get(ENV, "E52_BUDGETS", "1,2,5,10,20,50"), ","))
const METHODS52 = filter(!isempty, split(get(ENV, "E52_METHODS", "full,quot"), ","))
const ACC52 = (1e-2, 1e-3, 1e-4)
const LOCAL52 = (eps_abs = 1e-6, eps_rel = 1e-6, max_iter = 20_000)     # local QPs: MPCController's accuracy (E27)

"""The local QPs to MPCController's accuracy (DistributedMPC's own default is 1e-9)."""
function local52!(D::SM.DistributedMPC)
    for L in D.locals, (k, v) in pairs(LOCAL52)
        setproperty!(L.solver.settings, k, v)
    end
    return D
end

"""A tight central solver of a fleet (the reference J*): condensed, 1e-9."""
function central52(fl::SM.Fleet; tol = 1e-9)
    st = SM.Settings(); st.eps_abs = tol; st.eps_rel = tol; st.max_iter = 100_000
    return SM.MPCController(fl, SM.full_condensing(); certify = false, settings = st)
end

"""J of the plan of the last step of a controller or distributed MPC (its fine program, the plan's own objective)."""
Jplan52(C) = SM.objective(C.fp.program, SM.plan(C))

"""A method: the ADMM over the fleet (`full`) or over the quotient of the rows (`quot`)."""
mutable struct Admm52
    name::String
    D::SM.DistributedMPC
    Q::Union{Nothing,Quot51}
end

function Admm52(name::AbstractString, sc::Scenario26, Q::Quot51, rho::Float64; budget::Int, warm::Symbol)
    if name == "full"
        D = local52!(SM.DistributedMPC(sc.fleet, collect(1:sc.n); rho = rho, budget = budget, warm = warm))
        return Admm52("full", D, nothing)
    end
    D = local52!(SM.DistributedMPC(Q.fleet, collect(1:length(Q.teams)); rho = rho, budget = budget, warm = warm))
    return Admm52("quot", D, Q)
end

"""
One step (one call of DistributedMPC's step!) at the measured states `x`:
returns the members' inputs, the step info, the plan's objective (the fleet's
for `full`, the quotient's, equal to the fleet's of the lifted plan, for
`quot`), the gather and broadcast time (quot), and rounds and floats.
"""
function astep52!(M::Admm52, sc::Scenario26, x, refs, term)
    if M.name == "full"
        info = SM.step!(M.D, x, refs; terminal = term)
        return [copy(v) for v in info.u], info, Jplan52(M.D), 0.0, M.D.iterations, M.D.floats
    end
    t0 = time_ns()
    xq, rq, tq = teamdata51(M.Q, sc, x, refs, term)
    t1 = time_ns()
    info = SM.step!(M.D, xq, rq; terminal = tq)
    t2 = time_ns()
    u = [copy(info.u[M.Q.team[i]]) for i in 1:sc.n]
    t3 = time_ns()
    return u, info, Jplan52(M.D), ((t1 - t0) + (t3 - t2)) / 1e9, M.D.iterations + 2, M.D.floats + 9 * sc.n
end

"""The reference J* at the measured states: the coordinated program, solved tightly (centrally)."""
function jstar52!(Cref, x, refs, term)
    SM.step!(Cref, x, refs; terminal = term)
    return Jplan52(Cref)
end

"""ADMM from a cold start at one state, one iteration at a time: the suboptimality after every iteration."""
function trace52(name, sc, Q, rho, x, refs, term, Jstar; maxit::Int)
    M = Admm52(name, sc, Q, rho; budget = 1, warm = :previous)
    sub = Float64[]; tpar = Float64[]; tseq = Float64[]
    for it in 1:maxit
        _, info, J, tg, _, _ = astep52!(M, sc, x, refs, term)
        push!(sub, (J - Jstar) / abs(Jstar))
        push!(tseq, info.t_solve); push!(tpar, M.D.t_parallel)
        sub[end] <= minimum(ACC52) && break
        info.status in (:numerical_error, :primal_infeasible, :dual_infeasible) && break
    end
    first_at(a) = (k = findfirst(<=(a), sub); k === nothing ? -1 : k)
    reach = Dict{String,Any}()
    for a in ACC52
        k = first_at(a)
        reach[string(a)] = Dict("iter" => k, "seq_s" => k < 0 ? NaN : sum(tseq[1:k]), "par_s" => k < 0 ? NaN : sum(tpar[1:k]))
    end
    return Dict{String,Any}("sub" => sub, "reach" => reach, "agents" => length(M.D.locals),
                            "floats_per_iter" => SM.floats_per_iteration(M.D), "rho" => rho)
end

"""rho of a method: the fastest of RHOS52 to 1e-3 from a cold start at step 0 of seed 1."""
function tune52(name, sc, Q)
    x0 = start26(sc); refs, term = references26(sc, 0.0)
    Js = jstar52!(central52(sc.fleet), x0, refs, term)
    best = (Inf, RHOS52[1]); rows = Dict{String,Any}()
    for rho in RHOS52
        tr = trace52(name, sc, Q, rho, x0, refs, term, Js; maxit = TUNE_MAXIT52)
        k = tr["reach"]["0.001"]["iter"]
        rows[string(rho)] = Dict("iter_1e-3" => k, "final_sub" => tr["sub"][end])
        @printf("    tune %-4s rho %7.2f  iters to 1e-3: %4d  (final %.2e)\n", name, rho, k, tr["sub"][end]); flush(stdout)
        k > 0 && k < best[1] && (best = (k, rho))
    end
    return best[2], rows
end

"""The closed loop of one method with budget b; coord's cost `Jc` for the ratio, Cref for J* per step."""
function loop52(name, sc, Q, rho, b, Cref; steps::Int = STEPS26)
    GC.gc()
    tb0 = time()
    M = Admm52(name, sc, Q, rho; budget = b, warm = :shift)
    tb = time() - tb0
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]
    nag = length(M.D.locals)
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        u, info, J, tg, rounds, floats = astep52!(M, sc, x, refs, term)
        Js = jstar52!(Cref, x, refs, term)
        par = (info.t_total - info.t_solve) / nag + M.D.t_parallel + tg
        uc, viol = clip26(sc, u)
        sc_ = stage_cost26(sc, x, uc, refs)
        cost += sc_
        push!(rec, Dict{String,Any}("step" => k, "sub" => (J - Js) / abs(Js), "seq" => info.t_total + tg, "par" => par,
                                    "rounds" => rounds, "floats" => floats, "status" => string(info.status),
                                    "viol" => viol, "local_failures" => M.D.local_failures))
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    after = rec[2:end]
    col(key) = [Float64(r[key]) for r in after]
    return Dict{String,Any}("method" => name, "budget" => b, "rho" => rho, "agents" => nag, "build_seconds" => tb,
                            "closed_loop_cost" => cost, "sub" => sumstats26([Float64(r["sub"]) for r in rec]),
                            "seq" => sumstats26(col("seq")), "par" => sumstats26(col("par")),
                            "rounds" => rec[end]["rounds"], "floats" => sumstats26(col("floats")),
                            "bad_steps" => count(r -> r["status"] in ("numerical_error", "primal_infeasible", "dual_infeasible"), rec),
                            "local_failures" => sum(r["local_failures"] for r in rec), "steps" => rec)
end

"""Coordinated MPC's closed loop (MPCController, condensed, MPCController's accuracy): cost and the states of its steps."""
function coord52(sc; steps::Int = STEPS26)
    C = controller51(sc.fleet)
    x = start26(sc); cost = 0.0; xs = Vector{Vector{Vector{Float64}}}(); ts = Float64[]
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        info = SM.step!(C, x, refs; terminal = term)
        push!(ts, info.t_total)
        uc, _ = clip26(sc, [copy(v) for v in info.u])
        cost += stage_cost26(sc, x, uc, refs)
        push!(xs, x)
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    return cost, xs, ts
end

const COMM52 = Dict(
    "coordinated" => "2 rounds per sample: states up (6 n floats), inputs down (3 n floats)",
    "team_central" => "2 rounds per sample: states up (6 n floats), team inputs down (3 n floats); averaging and lift at the central computer",
    "admm_full" => "b rounds per sample (one per iteration), interface floats both ways per iteration (DistributedMPC.floats)",
    "admm_quot" => "b + 2 rounds per sample: gather inside every row (6 n floats), b rounds between the rows' agents (quotient interface floats), broadcast inside every row (3 n floats)",
    "decentralized" => "0 rounds (neighbours sensed)")

function run52(seed::Int, rhos::Dict{String,Float64}; side::Int = SIDE26, quiet::Bool = false, budgets = BUDGETS52,
               trace::Bool = true, steps::Int = STEPS26)
    sc = Scenario26(side; seed = seed)
    Q = Quot51(sc, partitions51(sc)[1])
    res = Dict{String,Any}("seed" => seed, "n" => sc.n, "side" => side, "rows" => length(Q.teams), "rho" => rhos,
                           "communication" => COMM52, "load" => loadavg26())
    tc0 = time()
    Jc, xs, tsc = coord52(sc; steps = steps)
    tc = time() - tc0
    res["coord"] = Dict("closed_loop_cost" => Jc, "seconds" => tc, "ms_med" => 1e3 * median(tsc[2:end]), "ms_max" => 1e3 * maximum(tsc[2:end]))
    Cref = central52(sc.fleet)
    if trace
        res["trace"] = Dict{String,Any}()
        for k in TRACE_STEPS52
            k < steps || continue
            refs, term = references26(sc, k * sc.h)
            Js = jstar52!(Cref, xs[k+1], refs, term)
            for m in METHODS52
                tr = trace52(m, sc, Q, rhos[m], xs[k+1], refs, term, Js; maxit = TRACE_MAXIT52)
                res["trace"]["$(m)_step$k"] = tr
                quiet || @printf("  trace %-4s step %2d  iters to 1e-2/1e-3/1e-4: %s\n", m, k,
                                 join([string(tr["reach"][string(a)]["iter"]) for a in ACC52], "/"))
                flush(stdout)
            end
        end
    end
    res["loops"] = Dict{String,Any}()
    for b in budgets, m in METHODS52
        out = loop52(m, sc, Q, rhos[m], b, Cref; steps = steps)
        out["cost_ratio"] = out["closed_loop_cost"] / Jc
        res["loops"]["$(m)_b$b"] = out
        quiet || @printf("  loop  %-4s b=%3d  cost ratio %.6f  sub med %.2e max %.2e  seq %8.2f ms  par %8.2f ms  rounds %d\n",
                         m, b, out["cost_ratio"], out["sub"]["median"], out["sub"]["max"], ms26(out["seq"]["median"]),
                         ms26(out["par"]["median"]), out["rounds"])
        flush(stdout)
    end
    return res
end

"""TeamMPC's version and the pinned revision of the active environment's manifest (env)."""
function teammpc52()
    d = Dict{String,Any}("teammpc_version" => string(pkgversion(SM)))
    mf = joinpath(dirname(Base.active_project()), "Manifest.toml")
    if isfile(mf)
        e = Base.parsed_toml(mf)["deps"]["TeamMPC"][1]
        d["teammpc_repo_rev"] = get(e, "repo-rev", get(e, "path", ""))
        d["teammpc_tree_sha1"] = get(e, "git-tree-sha1", "")
    end
    return d
end

function main52()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR52)
    # warm-up on a 4 x 4 fleet: every path
    run52(1, Dict("full" => 1.0, "quot" => 1.0); side = 4, quiet = true, budgets = [1, 2], steps = 3)
    rpath = joinpath(PARTDIR52, @sprintf("e52_rho_n%d.json", SIDE26^2))
    rhos = Dict{String,Float64}()
    if isfile(rpath)
        r = JSON.parsefile(rpath)
        for (k, v) in r["rho"]
            rhos[k] = v
        end
    end
    if any(m -> !haskey(rhos, m), METHODS52)
        sc = Scenario26(SIDE26; seed = 1)
        Q = Quot51(sc, partitions51(sc)[1])
        tab = Dict{String,Any}()
        for m in METHODS52
            haskey(rhos, m) && continue
            @printf("E52 tune %s side %d\n", m, SIDE26); flush(stdout)
            rhos[m], tab[m] = tune52(m, sc, Q)
        end
        open(io -> JSON.print(io, Dict("rho" => rhos, "table" => tab, "n" => SIDE26^2), 1), rpath, "w")
    end
    for seed in SEEDS26
        @printf("E52 side %d seed %d rho %s\n", SIDE26, seed, rhos); flush(stdout)
        res = run52(seed, rhos)
        res["meta"] = merge(meta26(), Dict{String,Any}("job" => get(ENV, "SLURM_JOB_ID", ""), "cone" => string(CONE26), "steps" => STEPS26,
                           "disc" => get(ENV, "BENCH_DISC", "zoh"), "local_settings" => Dict(pairs(LOCAL52)),
                           "array_job" => get(ENV, "SLURM_ARRAY_JOB_ID", ""), "partition" => get(ENV, "SLURM_JOB_PARTITION", ""),
                           "exclusive" => get(ENV, "E52_EXCLUSIVE", "0") == "1", "commit" => get(ENV, "E52_COMMIT", ""),
                           "tree" => get(ENV, "E52_TREE", ""), "rho_source" => get(ENV, "E52_RHO_SOURCE", "tuned in this run")), teammpc52())
        path = joinpath(PARTDIR52, @sprintf("e52_n%d_seed%d.json", SIDE26^2, seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

function merge52()
    byn = Dict{Int,Vector{Any}}()
    for f in readdir(PARTDIR52; join = true)
        (endswith(f, ".json") && !occursin("_rho_", f)) || continue
        p = JSON.parsefile(f)
        push!(get!(byn, p["n"], Any[]), p)
    end
    out = Dict{String,Any}("experiment" => "E52 consensus ADMM on the fleet vs on the quotient of the rows",
                           "communication" => COMM52, "period_ms" => 1e3 * DT26, "sizes" => Dict{String,Any}())
    for (n, parts) in sort!(collect(byn); by = first)
        sort!(parts; by = p -> p["seed"])
        d = Dict{String,Any}("seeds" => [p["seed"] for p in parts], "rho" => parts[1]["rho"], "rows" => parts[1]["rows"])
        # provenance of every part (written by main52)
        d["parts"] = [Dict("seed" => p["seed"], "meta" => get(p, "meta", nothing)) for p in parts]
        d["coord_ms_med"] = median([p["coord"]["ms_med"] for p in parts])
        L = Dict{String,Any}()
        for key in keys(parts[1]["loops"])
            ps = [p["loops"][key] for p in parts if haskey(p["loops"], key)]
            L[key] = Dict{String,Any}("cost_ratio_med" => median([q["cost_ratio"] for q in ps]),
                                      "cost_ratio_max" => maximum([q["cost_ratio"] for q in ps]),
                                      "sub_med" => median([q["sub"]["median"] for q in ps]),
                                      "sub_max" => maximum([q["sub"]["max"] for q in ps]),
                                      "seq_ms_med" => 1e3 * median([q["seq"]["median"] for q in ps]),
                                      "par_ms_med" => 1e3 * median([q["par"]["median"] for q in ps]),
                                      "par_ms_max" => 1e3 * maximum([q["par"]["max"] for q in ps]),
                                      "rounds" => ps[1]["rounds"], "floats_med" => median([q["floats"]["median"] for q in ps]),
                                      "agents" => ps[1]["agents"], "bad_steps" => sum(q["bad_steps"] for q in ps),
                                      "cost_ratio_seeds" => [q["cost_ratio"] for q in ps],
                                      "seq_ms_seeds" => [1e3 * q["seq"]["median"] for q in ps],
                                      "par_ms_seeds" => [1e3 * q["par"]["median"] for q in ps],
                                      "local_failures" => sum(q["local_failures"] for q in ps))
        end
        d["loops"] = L
        T = Dict{String,Any}()
        if haskey(parts[1], "trace")
            for key in keys(parts[1]["trace"])
                ps = [p["trace"][key] for p in parts if haskey(p, "trace") && haskey(p["trace"], key)]
                T[key] = Dict(a => Dict("iter_med" => median([q["reach"][a]["iter"] for q in ps]),
                                        "iter_max" => maximum([q["reach"][a]["iter"] for q in ps]),
                                        "unreached" => count(q -> q["reach"][a]["iter"] < 0, ps),
                                        "par_s_med" => median([q["reach"][a]["par_s"] for q in ps]),
                                        "iter_seeds" => [q["reach"][a]["iter"] for q in ps])
                              for a in keys(ps[1]["reach"]))
            end
        end
        d["trace"] = T
        out["sizes"][string(n)] = d
    end
    metas = [p["meta"] for d in values(out["sizes"]) for p in d["parts"] if p["meta"] !== nothing]
    uniq(k) = sort!(unique([string(get(m, k, "")) for m in metas]))
    out["meta"] = Dict("hosts" => uniq("host"), "jobs" => uniq("job"), "array_jobs" => uniq("array_job"),
                       "partition" => uniq("partition"), "exclusive" => uniq("exclusive"), "cpus" => uniq("cpu"),
                       "julia" => uniq("julia"), "commit" => uniq("commit"), "tree" => uniq("tree"),
                       "teammpc_version" => uniq("teammpc_version"), "teammpc_repo_rev" => uniq("teammpc_repo_rev"),
                       "rho_source" => uniq("rho_source"), "partdir" => PARTDIR52)
    open(io -> JSON.print(io, out, 1), OUT52, "w")
    println("wrote $OUT52")
    JSON.print(stdout, out, 1)
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE52 == "merge" ? merge52() : main52()
end
