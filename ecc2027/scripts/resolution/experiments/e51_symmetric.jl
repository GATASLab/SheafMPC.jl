# E51-symmetric: the symmetric-MPC baseline. Symmetric MPC (Danielson and
# Borrelli) reduces a problem by the orbits of its symmetries. On E26's fleet
# (fleet_dc.jl: drone rows and car rows alternating, one lane per type), the
# symmetries that fix the data relative to the slots are the mirror images of
# the columns, so the orbits are the pairs of mirror columns of each row
# (side * ceil(side / 2) orbits: 512 at 1024 vehicles). They are the coarsest
# EQUITABLE partition refining the data classes (ordinary colour refinement,
# which also counts the edges inside a group); the coarsest ALMOST equitable
# one (colour refinement ignoring them, Sec. V) is the rows. Both are lossless
# for coherent data (Thm. thm:equitable), so the three controllers below apply
# the same inputs and the comparison is of time only.
#
#   BENCH_SIDE=32 BENCH_SEEDS=1,2 julia --project=env scripts/resolution/experiments/e51_symmetric.jl
#   E51_MODE=merge E51_PARTDIR=<parts> julia --project=env scripts/resolution/experiments/e51_symmetric.jl
#
# Per seed, coherent data, one closed loop (STEPS26 steps) each of
#   rows     team MPC on the quotient program of the rows (one vehicle per row)
#   orbits   symmetric MPC: the quotient program of the mirror orbits (one
#            vehicle per orbit; an orbit's two members need not be adjacent)
#   coord    coordinated MPC (BENCH_COORD51=1, the default for side <= 64)
# all with the SAME code path and solver: the package's MPCController on the
# condensed program (full_condensing), its default accuracy (1e-6) and warm
# start (the previous plan shifted one instant). A team step adds the
# averaging of the measured states and references over the team (the
# projection, with the slots) and the broadcast of the team inputs, timed.
# Recorded: time per step (median and worst after the first), QP sizes,
# offline build time, closed-loop costs and the largest difference of applied
# inputs between the loops.
#
# The quotient program (generic, any coherent equitable or almost equitable
# partition): one agent per team, a copy of its members' agent with tracking,
# effort and terminal weights times the team size; between two teams one
# formation edge whose weight is the total weight of the edges between them
# and whose target is their weighted mean relative to the slots (the edges
# between two teams compare the same coordinates, `select`, checked). The
# slot of a member is its position offset with zero velocity, Delta_i =
# (s_i, 0) in its own state space (A Delta = Delta).
#
# Timing hygiene as E26 (one thread, warm-up on a 4 x 4 fleet, GC before each loop).

isdefined(Main, :Scenario26) || include(joinpath(@__DIR__, "e26_flagship_dc.jl"))

const MODE51 = get(ENV, "E51_MODE", "run")
const COORD51 = get(ENV, "BENCH_COORD51", SIDE26 <= 64 ? "1" : "0") == "1"
const PARTDIR51 = get(ENV, "E51_PARTDIR", joinpath(ROOT26, "bench", "baselines", "results", "parts51"))
const OUT51 = get(ENV, "E51_OUT", joinpath(ROOT26, "results", "e51_symmetric.json"))

# ---------------------------------------------------------------------------
# Colour refinement (both variants) and the partitions of the scenario
# ---------------------------------------------------------------------------

canon51(v) = (d = Dict{Any,Int}(); [get!(d, x, length(d) + 1) for x in v])

"""
Colour refinement from the partition `classes` on the graph of `edges` with
weights `w`. `within = true` counts the edges inside a group too (ordinary
colour refinement: the coarsest equitable partition refining the classes);
`false` ignores them (the coarsest almost equitable partition).
"""
function refine51(n::Int, edges, w, classes; within::Bool)
    nbr = [Tuple{Int,Float64}[] for _ in 1:n]
    for ((i, j), wk) in zip(edges, w)
        push!(nbr[i], (j, wk)); push!(nbr[j], (i, wk))
    end
    a = canon51(classes)
    while true
        sig = map(1:n) do i
            tot = Dict{Int,Float64}()
            for (j, wk) in nbr[i]
                (within || a[j] != a[i]) && (tot[a[j]] = get(tot, a[j], 0.0) + wk)
            end
            (a[i], sort!([c => round(s; digits = 9) for (c, s) in tot if abs(s) > 1e-12]))
        end
        b = canon51(sig)
        maximum(b) == maximum(a) && return a
        a = b
    end
end

"""The data classes of `sc` (vehicle type and lane: the vehicles whose slot-relative data agree)."""
classes51(sc::Scenario26) = [(sc.fleet.agents[i].kind, sc.lanei[i], sc.fleet.agents[i].nx) for i in 1:sc.n]

"""The lossless teams (colour refinement ignoring internal edges) and the symmetry orbits (ordinary colour refinement)."""
function partitions51(sc::Scenario26)
    w = sc.fleet.weights[:, 1] .* sc.fleet.present[:, 1]
    cl = classes51(sc)
    aep = refine51(sc.n, sc.fleet.edges, w, cl; within = false)
    orb = refine51(sc.n, sc.fleet.edges, w, cl; within = true)
    canon51(aep) == canon51(sc.team) || @warn "colour refinement does not reproduce the scenario's teams"
    return aep, orb
end

# ---------------------------------------------------------------------------
# The quotient program of a coherent partition
# ---------------------------------------------------------------------------

"""Member i's slot in its own state space: position offset, zero velocity (A Delta = Delta)."""
function slotstate51(sc::Scenario26, i::Int)
    ag = sc.fleet.agents[i]; d = div(ag.nx, 2)
    return [sc.slots[i][1:d]; zeros(ag.nx - d)]
end

function scaled51(ag::SM.Agent, m::Real)
    return SM.Agent(ag.A[1], ag.B[1]; C = ag.C, Cr = ag.Cr, Q = m * ag.Q, R = m * ag.R, Cf = ag.Cf, Qf = m * ag.Qf,
                    g = ag.g[1], input = ag.input, kind = ag.kind)
end

struct Quot51
    fleet::SM.Fleet
    teams::Vector{Vector{Int}}
    team::Vector{Int}
    Delta::Vector{Vector{Float64}}
    merged::Int
end

function Quot51(sc::Scenario26, team::Vector{Int})
    team = canon51(team)
    nt = maximum(team)
    teams = [findall(==(c), team) for c in 1:nt]
    fl = sc.fleet; H = sc.H; p = size(fl.agents[1].C, 1)
    for m in teams                                     # coherent teams: one agent type per team
        all(i -> fl.agents[i].kind == fl.agents[m[1]].kind && sc.lanei[i] == sc.lanei[m[1]], m) ||
            error("team mixes data classes: not coherent")
    end
    Delta = [slotstate51(sc, i) for i in 1:sc.n]
    ags = [scaled51(fl.agents[first(m)], length(m)) for m in teams]
    acc = Dict{Tuple{Int,Int},Any}()
    merged = 0
    for (k, (i, j)) in enumerate(fl.edges)
        a, b = team[i], team[j]
        a == b && continue
        merged += 1
        s = 1.0
        if a > b
            a, b = b, a; s = -1.0
        end
        rel = fl.agents[j].C * Delta[j] - fl.agents[i].C * Delta[i]
        e = get!(acc, (a, b), (W = zeros(H), Wb = zeros(p, H), S = fl.select[k]))
        e.S == fl.select[k] || error("edges between two teams compare different coordinates")
        for t in 1:H
            fl.present[k, t] || continue
            e.W[t] += fl.weights[k, t]
            e.Wb[:, t] .+= fl.weights[k, t] .* (s .* (fl.targets[:, k, t] .- rel))
        end
    end
    qedges = sort!(collect(keys(acc)))
    ne = length(qedges)
    Wm = zeros(ne, H); T = zeros(p, ne, H)
    for (k, key) in enumerate(qedges)
        e = acc[key]
        Wm[k, :] .= e.W
        for t in 1:H
            T[:, k, t] .= e.W[t] > 0 ? e.Wb[:, t] ./ e.W[t] : 0.0
        end
    end
    fq = SM.Fleet(ags, qedges; H = H, targets = T, weights = Wm, select = [acc[key].S for key in qedges])
    return Quot51(fq, teams, team, Delta, merged)
end

"""The team data of a step: member averages of the slot-relative states (the projection) and references."""
function teamdata51(Q::Quot51, sc::Scenario26, x, refs, term)
    xq = Vector{Vector{Float64}}(undef, length(Q.teams)); rq = similar(xq, Matrix{Float64}); tq = similar(xq)
    @inbounds for (c, m) in enumerate(Q.teams)
        ag = sc.fleet.agents[m[1]]; w = 1.0 / length(m)
        xc = zeros(ag.nx); Rc = zeros(size(refs[m[1]])); tc = zeros(length(term[m[1]]))
        for i in m
            D = Q.Delta[i]
            xc .+= w .* (x[i] .- D)
            Rc .+= w .* (refs[i] .- ag.Cr * D)
            tc .+= w .* (term[i] .- ag.Cf * D)
        end
        xq[c] = xc; rq[c] = Rc; tq[c] = tc
    end
    return xq, rq, tq
end

"""MPCController on the condensed program, the package's default accuracy and warm start."""
controller51(fl::SM.Fleet; settings = SM.Settings()) = SM.MPCController(fl, SM.full_condensing(); certify = false, settings = settings)

"""
The closed loop of a central controller `C` of `sc` (`Q === nothing`) or of
the quotient `Q` of `sc` (team MPC: project, solve, broadcast). Returns the
record and the applied inputs.
"""
function loop51(sc::Scenario26, C, Q; steps::Int = STEPS26)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; us = Vector{Vector{Vector{Float64}}}()
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        t0 = time_ns()
        if Q === nothing
            info = SM.step!(C, x, refs; terminal = term)
            u = [copy(v) for v in info.u]
            tg = 0.0
        else
            xq, rq, tq = teamdata51(Q, sc, x, refs, term)
            t1 = time_ns()
            info = SM.step!(C, xq, rq; terminal = tq)
            t2 = time_ns()
            u = [copy(info.u[Q.team[i]]) for i in 1:sc.n]
            tg = ((t1 - t0) + (time_ns() - t2)) / 1e9
        end
        tt = (time_ns() - t0) / 1e9
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "t_total" => tt, "t_solve" => info.t_solve, "t_team" => tg,
                                    "iter" => info.iter, "status" => string(info.status), "viol" => viol))
        push!(us, uc)
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    after = rec[2:end]
    col(key) = [Float64(r[key]) for r in after]
    out = Dict{String,Any}("closed_loop_cost" => cost, "t_total" => sumstats26(col("t_total")),
                           "t_solve" => sumstats26(col("t_solve")), "t_team" => sumstats26(col("t_team")),
                           "first_s" => rec[1]["t_total"], "unsolved" => count(r -> r["status"] != "solved", rec),
                           "iter" => sumstats26(col("iter")),
                           "steps" => [Dict("t_total" => r["t_total"], "iter" => r["iter"]) for r in rec])
    return out, us
end

qpsize51(C) = (q = C.solver === nothing ? nothing : C.solver; q === nothing ? Dict{String,Any}() :
               Dict{String,Any}("variables" => length(q.xsol)))

function run51(seed::Int; side::Int = SIDE26, quiet::Bool = false, coord::Bool = COORD51, steps::Int = STEPS26)
    sc = Scenario26(side; seed = seed)
    res = Dict{String,Any}("seed" => seed, "n" => sc.n, "side" => side, "load" => loadavg26(),
                           "fleet" => string(FLEET_DC), "layout" => string(LAYOUT_DC))
    aep, orb = partitions51(sc)
    U = Dict{String,Any}()
    for (name, part) in (("rows", aep), ("orbits", orb))
        GC.gc()
        tb = @elapsed begin
            Q = Quot51(sc, part)
            C = controller51(Q.fleet)
        end
        GC.gc()
        out, us = loop51(sc, C, Q; steps = steps)
        out["build_seconds"] = tb; out["teams"] = length(Q.teams); out["quotient_edges"] = length(Q.fleet.edges)
        out["merged_edges"] = Q.merged; out["qp"] = qpsize51(C)
        res[name] = out; U[name] = us
    end
    if coord
        GC.gc()
        tb = @elapsed (C = controller51(sc.fleet))
        GC.gc()
        out, us = loop51(sc, C, nothing; steps = steps)
        out["build_seconds"] = tb; out["teams"] = sc.n; out["qp"] = qpsize51(C)
        res["coord"] = out; U["coord"] = us
    end
    for (a, b) in (("rows", "orbits"), ("coord", "rows"), ("coord", "orbits"))
        (haskey(U, a) && haskey(U, b)) || continue
        res["input_diff_$(a)_$(b)"] = maxdiff26(U[a], U[b])
        res["cost_ratio_$(a)_$(b)"] = res[a]["closed_loop_cost"] / res[b]["closed_loop_cost"]
    end
    if !quiet
        for k in ("rows", "orbits", "coord")
            haskey(res, k) || continue
            o = res[k]
            @printf("  %-6s n=%5d teams %5d  ms/step med %9.3f max %9.3f  (team %.3f)  vars %s  build %.2f s\n", k, sc.n,
                    o["teams"], ms26(o["t_total"]["median"]), ms26(o["t_total"]["max"]), ms26(o["t_team"]["median"]),
                    string(get(o["qp"], "variables", "?")), o["build_seconds"])
        end
        for key in sort!(filter(k -> startswith(k, "input_diff"), collect(keys(res))))
            @printf("  %s %.1e\n", key, res[key])
        end
    end
    return res
end

function main51()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR51)
    run51(1; side = 4, quiet = true, coord = true, steps = 3)          # warm-up: every path
    for seed in SEEDS26
        @printf("E51 side %d seed %d (%s, %s)\n", SIDE26, seed, FLEET_DC, LAYOUT_DC); flush(stdout)
        res = run51(seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "threads" => Threads.nthreads(),
                           "job" => get(ENV, "SLURM_JOB_ID", ""), "cpu" => Sys.cpu_info()[1].model, "cone" => string(CONE26),
                           "steps" => STEPS26, "disc" => get(ENV, "BENCH_DISC", "zoh"))
        path = joinpath(PARTDIR51, @sprintf("e51_n%d_seed%d.json", SIDE26^2, seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

function merge51()
    byn = Dict{Int,Vector{Any}}()
    for f in readdir(PARTDIR51; join = true)
        endswith(f, ".json") || continue
        p = JSON.parsefile(f)
        push!(get!(byn, p["n"], Any[]), p)
    end
    out = Dict{String,Any}("experiment" => "E51 symmetric MPC (mirror orbits) vs team MPC (rows) vs coordinated MPC, same controller code",
                           "period_ms" => 1e3 * DT26, "sizes" => Dict{String,Any}())
    for (n, parts) in sort!(collect(byn); by = first)
        d = Dict{String,Any}("seeds" => [p["seed"] for p in parts])
        for k in ("rows", "orbits", "coord")
            hp = [p for p in parts if haskey(p, k)]
            isempty(hp) && continue
            d[k] = Dict{String,Any}("ms_med" => 1e3 * median([p[k]["t_total"]["median"] for p in hp]),
                                    "ms_max" => 1e3 * maximum([p[k]["t_total"]["max"] for p in hp]),
                                    "solve_ms_med" => 1e3 * median([p[k]["t_solve"]["median"] for p in hp]),
                                    "team_ms_med" => 1e3 * median([p[k]["t_team"]["median"] for p in hp]),
                                    "build_s_med" => median([p[k]["build_seconds"] for p in hp]),
                                    "teams" => hp[1][k]["teams"], "variables" => get(hp[1][k]["qp"], "variables", -1),
                                    "unsolved" => sum(p[k]["unsolved"] for p in hp),
                                    "over_period_steps" => sum(count(s -> s["t_total"] > DT26, p[k]["steps"][2:end]) for p in hp))
        end
        for key in unique(vcat([filter(k -> startswith(k, "input_diff") || startswith(k, "cost_ratio"), collect(keys(p))) for p in parts]...))
            v = [p[key] for p in parts if haskey(p, key)]
            d[key * (startswith(key, "input") ? "_max" : "_maxdev")] = startswith(key, "input") ? maximum(v) : maximum(abs.(v .- 1))
        end
        d["parts"] = [Dict("seed" => p["seed"], "meta" => get(p, "meta", nothing)) for p in parts]
        out["sizes"][string(n)] = d
    end
    # provenance: every part's host, job, CPU and Julia (written by main51)
    metas = [get(p, "meta", Dict()) for parts in values(byn) for p in parts]
    out["meta"] = Dict("hosts" => sort!(unique([get(m, "host", "") for m in metas])),
                       "jobs" => sort!(unique([get(m, "job", "") for m in metas])),
                       "cpus" => sort!(unique([get(m, "cpu", "") for m in metas])),
                       "julia" => sort!(unique([get(m, "julia", "") for m in metas])),
                       "partdir" => PARTDIR51, "commit" => get(ENV, "E51_COMMIT", ""),
                       "exclusive" => get(ENV, "E51_EXCLUSIVE", ""))
    open(io -> JSON.print(io, out, 1), OUT51, "w")
    println("wrote $OUT51")
    JSON.print(stdout, out, 1)
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE51 == "merge" ? merge51() : main51()
end
