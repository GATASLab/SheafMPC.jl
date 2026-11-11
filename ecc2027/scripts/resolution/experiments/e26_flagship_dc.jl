# Provenance: e26_flagship.jl blob ac32bd3 (main@4ed57a7), the version in every November HPG tree (E51-E112); the drone/car fleet of fleet_dc.jl. Unchanged except this header.
# The October versions under the plain names are the ones the E26-E42 ZOH campaign ran with.
# E26-flagship: one coherent formation of up to 16384 quadrotors in closed-loop
# receding-horizon MPC, where the reduction is exact (rows of a grid are almost
# equitable, the data are coherent inside them: Thm. thm:equitable), so the
# reduced controller follows the closed loop of coordinated MPC of the whole
# fleet while solving a program whose size does not grow with the length of a
# row. Every program is a TeamMPC.jl program; coordinated MPC is also solved by
# the baseline solvers of bench/central (Clarabel, OSQP, Mumblebee), and so is
# the reduced program, so that the speedup of the reduction is separated from
# the speedup of the solver.
#
#   BENCH_SIDE=16 BENCH_CONE=soc BENCH_REGIME=coherent BENCH_SEEDS=1,2 \
#       julia --project=env scripts/resolution/experiments/e26_flagship.jl
#           (env/results/parts/e26_<regime>_<cone>_n<n>_seed<s>.json and, per
#            baseline solver, e26_replay_<solver>_<regime>_<cone>_n<n>_seed<s>.json)
#   BENCH_MODE=merge julia --project=env scripts/resolution/experiments/e26_flagship.jl
#           (parts -> results/e26_flagship.json; BENCH_PARTDIR, BENCH_OUT=<path> for a canary)
#   julia --project=env scripts/resolution/experiments/e26_summary.jl   (the tables)
#
# Modes (BENCH_MODE): `all` runs the TeamMPC closed loops and then the
# baseline replays in one process; `loop` only the closed loops (it saves the
# measured states of both loops to BENCH_STATEDIR); `replay` only the baselines,
# on the states a `loop` run saved; `merge` merges the parts.
#
# The fleet (BENCH_SIDE = s: an s x s grid, s = 16, 32, 64, 128, so n = 256 to
# 16384; H = 10, h = 0.2, 30 closed-loop steps): quadrotors as 3D double
# integrators, rows alternating two airframes, light (||a|| <= 4, no drag,
# effort weight 0.1) and heavy (||a|| <= UMAX_HEAVY26, linear drag 0.4,
# effort weight 0.2); input balls (BENCH_CONE=soc) or boxes inscribed in them,
# |a_k| <= amax / sqrt(3) (BENCH_CONE=box, for the solvers without cones).
# Formation: springs of weight 1 on every grid edge on the 3D position, targets
# from the planar grid slots. Each row is a lane flying its own manoeuvre (the
# research module's :rows coherence, with altitude): speed, lateral weave and
# altitude drawn per lane from the seed. Start: every vehicle on its slot at
# altitude 1.5 with one common velocity, plus a rigid perturbation of the whole
# fleet (E23's start23: 0.3 m and 0.15 m/s Gaussian), which keeps every lane
# coherent. BENCH_REGIME=incoherent adds to every vehicle's reference its own
# wander of amplitude BENCH_SIGMA (planar circle and altitude sine, E19's
# :agents shape scaled down), so the rows lose their coherence mildly.
#
# Why not E25's fleet. E25's formation output is the planar position, so the
# altitude of a quadrotor lies outside the agreement subspace of its row: even
# the exact team keeps one altitude channel and one input cone per member, and
# the reduced program has as many cones as the fleet. With the formation on the
# 3D position every member's inputs are its row's. Two airframes alternate by
# row, so the kinds still change from row to row, as Thm. thm:equitable allows.
#
# The programs. The measured state is data, not a variable: vertex (i, 0)
# holds the input u_{i,0} only, and the dynamics edge from it has the tail map
# B and the target A xhat_i + g (the paper's Def. def:mpcgraph pins x_{i,0}
# through Omega_{i,0}; eliminating the pinned coordinates leaves the program
# unchanged, and keeps them out of every fiber). Coordinated MPC solves the
# time-expanded program (`fine`) or its full condensing (`cond`, the exact
# blocking id x !). The reduced controller (`red`) is the chain of
# reductions: full condensing, then teams of teams, pairs of adjacent
# vehicles of a row, pairs of pairs, and so on to whole rows (Thm.
# thm:functorial: the chain is the reduction along rows x !, and lifts level
# by level). The chain is used instead of one reduction along rows x !
# because TeamMPC's particular solution xbar = X b is a stored operator whose
# size grows with the square of a team's depth along its spanning tree (a row
# of 128 vehicles: about 3e9 nonzeros); along the chain every level merges two
# blocks and X stays linear in the fleet. Its value equals the one-step
# reduction's (checked for n <= 256).
#
# Duplicate cones. In the reduced program every member of a row carries its own
# input cone, and with coherent data the cones of a row's members at one
# instant are the same cone. TeamMPC's dedup_rows merges only bitwise equal
# rows and shifts; after the chain they agree to round-off (1e-13), so it
# merges none. Here cone blocks (and half-space rows) whose rows of A agree to
# MERGE_TOL26 relative are merged, a second-order cone only if its shift agrees
# to the same tolerance at setup and at every step (else every copy is kept
# from then on, a rebuild), a half-space row with the tightest bound (exact).
# Every lifted plan is checked for feasibility in the fine program, so a merge
# that mattered would show there.
#
# Solvers. TeamMPC (the package's conic ADMM with crossover to its IPM, the
# MPCController defaults eps_abs = eps_rel = 1e-6, max_iter = 20000, polish)
# runs the closed loops, warm started as MPCController does: the time-expanded
# program from the previous primal-dual solution shifted one instant
# (warm_start_shifted!), condensed and reduced programs from the previous
# solution as it is. The baselines replay the closed loop of coordinated MPC
# (fine and cond) and of the reduced controller (red), step by step, on the
# same programs: Clarabel 0.11.1 (tol_gap_abs = tol_gap_rel = tol_feas = 1e-8,
# qdldl, presolve and chordal decomposition off so that q and b are updated in
# place, cold by construction), Mumblebee at e78d9b9 (feas_tol = gap_tol =
# 1e-8, AMF elimination, cold; its reinit! fails on repeated solves, so every
# solve starts from a fresh init, outside the timer and recorded as t_init, the
# central bench's workaround), OSQP 0.8.1 (box only; eps_abs = eps_rel from
# BENCH_OSQP_EPS, polish, adaptive rho; cold: warm_start = false, read back
# from the workspace, and the step size reset before each solve outside the
# timer; warm: the previous solution shifted exactly as TeamMPC's), and
# TeamMPC cold (reset! before each solve). Accuracy: every replayed solve's
# lifted plan is scored on the fine program against the closed loop's
# TeamMPC plan at the same step (relative objective difference), and at step
# 0 against a tight Clarabel solve (1e-10) when BENCH_TIGHT=1.
#
# The step operator (BENCH_STEPOP=1, the default; 0 restores the level by level
# path). Only the measured states and the references change from step to step,
# and the QP vectors of the chain's last level are affine in them, so
# SM.StepOperator composes the levels once (offline, `stepop` in the build
# times), restricted to those entries, into one sparse map, and a step costs
# one sparse product of the size of the reduced QP and of the data instead of
# streaming every level's operators and full vectors. Likewise the applied
# inputs u_{i,0} are lifted by one precomposed product from the solution and
# the data; the reduced controller warm starts from its previous solution, so
# it lifts nothing else. The copies of a merged cone (one per member of a row)
# each depend on the data of the whole row, but their differences only on the
# row's departure from coherence (they vanish for coherent data, Thm.
# thm:equitable): the operator keeps the kept row and the differences of
# consecutive copies, applied to that departure (the change of every entry
# minus that of the row's first member), with a bound of their error that the
# merge check adds to the spread (a step whose bound does not certify the
# check computes the copies level by level, `stepop_fallbacks`).
# The constant of the QP objective (quadratic in the data) is not recomputed:
# it does not move the minimizer, and the solver keeps the one of step 0 (it
# enters only the normalization of the gap test). The fine plan of every step,
# for the checks below, is lifted outside the timed step after the level by
# level update (SM.sync!), which also checks the operator: `stepop_diff`, the
# largest relative difference of the QP vectors, and `stepop_input_diff`, of
# the applied inputs, per step.
#
# Recorded per closed loop and seed: the closed-loop cost (stage cost of the
# applied inputs, formation included, E19's accounting) and the reduced
# controller's ratio to coordinated MPC; the largest difference of applied
# inputs and of states between the two loops; the plan difference at step 0
# (same state); time per step split into construction (writing the step's
# data into the fine program, the QP vectors by the step operator or the
# reduction update of every level, and the merge), setup (the data into the
# solver and the warm start), solve and lift (the applied inputs, by the step
# operator or through every level to the fine plan);
# iterations, method, status; the feasibility of every lifted plan in the fine
# program (hard edges, node cones); the input activity (largest ||u|| / amax
# of a plan, and the number of input cones within 1e-6 of their bound at the
# optimum of step 0); offline construction (program, fibers of every level,
# QP, step operator, solver setup). At step 0: the gap of the reduction from the package's
# gap_bounds (lower bound from the fine optimum, the true gap, the certified
# upper bound from the reduced solve), and checks that the chain equals the
# one-step reduction and that the parametric program equals the package's
# FleetProgram (n <= 256).
#
# Timing hygiene: one Julia thread, one BLAS thread, the process pinned by the
# caller (taskset -c on the job's first core); every code path first runs on a
# 4 x 4 fleet for BENCH_WARMUP_STEPS steps (discarded) to compile; all timing is
# inside functions (time_ns), never at top level; garbage is collected before
# every loop and replay; the 1, 5 and 15 minute load averages are logged.

using LinearAlgebra, SparseArrays, Printf, Random, Statistics, Serialization
import JSON
import TeamMPC
const SM = TeamMPC
import Clarabel
import OSQP
using Mumblebee.IPM: IPMProblem, IPMSettings, PositiveCone, CofreeCone, SecondOrderCone, AbstractCone
import Mumblebee.IPM
using CliqueTrees: AMF

const SIDE26 = parse(Int, get(ENV, "BENCH_SIDE", "8"))
const H26 = 10
const DT26 = 0.2
const STEPS26 = parse(Int, get(ENV, "BENCH_STEPS", "30"))
const CONE26 = Symbol(get(ENV, "BENCH_CONE", "soc"))
const REGIME26 = Symbol(get(ENV, "BENCH_REGIME", "coherent"))
const SEEDS26 = parse.(Int, split(get(ENV, "BENCH_SEEDS", "1,2,3,4,5"), ","))
const MODE26 = get(ENV, "BENCH_MODE", "all")
const SOLVERS26 = filter(!isempty, split(get(ENV, "BENCH_SOLVERS", "teammpc_warm,teammpc_cold,clarabel,mumblebee,osqp_cold,osqp_warm"), ","))
const FORMS26 = filter(!isempty, split(get(ENV, "BENCH_FORMS", "fine,cond,red"), ","))
const REPLAY26 = parse(Int, get(ENV, "BENCH_REPLAY_STEPS", string(STEPS26)))
const COORD26 = get(ENV, "BENCH_COORD", "1") == "1"            # 0: the reduced loop only (no cost ratio)
const SIGMA26 = parse(Float64, get(ENV, "BENCH_SIGMA", "0.1"))
const OSQP_EPS26 = parse(Float64, get(ENV, "BENCH_OSQP_EPS", "1e-6"))
const TIGHT26 = get(ENV, "BENCH_TIGHT", SIDE26 <= 32 ? "1" : "0") == "1"
const WARMUP26 = parse(Int, get(ENV, "BENCH_WARMUP_STEPS", "3"))
const UMAX_LIGHT26 = 4.0
const UMAX_HEAVY26 = parse(Float64, get(ENV, "BENCH_UMAX_HEAVY", "0.5"))
const MERGE_TOL26 = 1e-9
const ROOT26 = normpath(joinpath(@__DIR__, "..", "..", ".."))
const PARTDIR26 = get(ENV, "BENCH_PARTDIR", joinpath(ROOT26, "bench", "flagship", "results", "parts"))
const STATEDIR26 = get(ENV, "BENCH_STATEDIR", joinpath(ROOT26, "bench", "flagship", "results", "states"))
const SM_SETTINGS26 = (eps_abs = parse(Float64, get(ENV, "BENCH_SM_EPS", "1e-6")),
                       eps_rel = parse(Float64, get(ENV, "BENCH_SM_EPS", "1e-6")), max_iter = 20_000)     # MPCController's defaults (1e-6)
const STEPOP26 = get(ENV, "BENCH_STEPOP", "1") == "1"      # 0: the level by level update and the full lift per step
const LINKTOL26 = 1e-9                                       # the merged copies' links: dropped mass (times their departure)

loadavg26() = (s = try read("/proc/loadavg", String) catch; "" end; isempty(s) ? Float64[] : parse.(Float64, split(s)[1:3]))
ms26(t) = 1e3 * t

# ---------------------------------------------------------------------------
# The fleet
# ---------------------------------------------------------------------------

"""
    Scenario26

An `side x side` grid of quadrotors (row major, rows are lanes along +x), the
formation springs of `SM.grid_graph` on the 3D position, per-lane reference
parameters, per-vehicle wander parameters (incoherent regime) and the rigid
start perturbation, all drawn from `seed`.
"""
struct Scenario26
    side::Int
    n::Int
    H::Int
    h::Float64
    cone::Symbol
    regime::Symbol
    sigma::Float64
    seed::Int
    fleet::SM.Fleet
    slots::Vector{Vector{Float64}}
    lane::Vector{NamedTuple}
    wander::Vector{NamedTuple}
    dp::Vector{Float64}
    dv::Vector{Float64}
    kinds::Vector{Symbol}         # :drone / :car (dronecar), :light / :heavy (quad)
    lanei::Vector{Int}            # the lane of every vehicle (its row for quad, its type for dronecar)
    team::Vector{Int}             # the team of every vehicle (colour refinement for dronecar)
    rank::Vector{Int}             # its rank inside the team (by column)
    params::Vector{NamedTuple}    # (drag, umax, r) per vehicle
end

row26(sc, i) = div(i - 1, sc.side) + 1
col26(sc, i) = rem(i - 1, sc.side) + 1
heavy26(sc, i) = sc.kinds[i] in (:heavy, :car)
umax26(sc, i) = sc.params[i].umax
ny26(ag::SM.Agent) = size(ag.Cr, 1)

"""A quadrotor as a 3D double integrator with linear drag `drag` (the quad fleet)."""
function airframe26(h, umax, drag, r, cone)
    a = drone_dc(h, umax, drag, r, cone)
    return SM.Agent(a.A, a.B; C = a.C, Cr = a.Cr, Q = a.Q, R = a.R, Cf = a.Cf, Qf = a.Qf, input = a.input,
                    kind = drag > 0 ? :heavy : :light)
end

include(joinpath(@__DIR__, "fleet_dc.jl"))

function Scenario26(side::Int; seed::Int, cone::Symbol = CONE26, regime::Symbol = REGIME26, sigma::Float64 = SIGMA26,
                    H::Int = H26, h::Float64 = DT26)
    n = side^2
    edges, sl = SM.grid_graph(side, side)
    slots = [[s; 0.0] for s in sl]
    if FLEET_DC == :quad
        ags = [iseven(div(i - 1, side) + 1) ? airframe26(h, UMAX_HEAVY26, 0.4, 0.2, cone) : airframe26(h, UMAX_LIGHT26, 0.0, 0.1, cone)
               for i in 1:n]
        params = [iseven(div(i - 1, side) + 1) ? (drag = 0.4, umax = UMAX_HEAVY26, r = 0.2) : (drag = 0.0, umax = UMAX_LIGHT26, r = 0.1)
                  for i in 1:n]
        kinds = [ag.kind for ag in ags]
        fl = SM.Fleet(ags, edges; H = H, offsets = slots, weights = 1.0)
        rng = Xoshiro(seed)
        lane = [(speed = 0.8 + 0.4 * rand(rng), amp = 0.1 + 0.3 * rand(rng), om = 0.5 + rand(rng), ph = 2pi * rand(rng),
                 alt = 1.5 + 0.4 * (rand(rng) - 0.5)) for _ in 1:side]
        lanei = [div(i - 1, side) + 1 for i in 1:n]
        team = copy(lanei); rank = [rem(i - 1, side) + 1 for i in 1:n]
    else
        kinds = [kind_dc(i, side, LAYOUT_DC) for i in 1:n]
        ags, params = dc_agents(kinds, h, cone, seed)
        fl = SM.Fleet(ags, edges; H = H, offsets = slots, weights = 1.0, select = dc_select(edges, kinds))
        lane = dc_lanes(seed)
        lanei = [k == :drone ? 1 : 2 for k in kinds]
        team, rank = dc_teams(n, side, side, edges, kinds, lanei)
    end
    rngw = Xoshiro(1_000_003 * seed + 17)
    wander = [(amp = 0.5 + rand(rngw), om = 0.5 + rand(rngw), ph = 2pi * rand(rngw), omz = 0.5 + rand(rngw), phz = 2pi * rand(rngw))
              for _ in 1:n]
    rngs = Xoshiro(7919 * seed)
    dp = 0.3 * randn(rngs, 2); dv = 0.15 * randn(rngs, 2)
    return Scenario26(side, n, H, h, cone, regime, sigma, seed, fl, slots, lane, wander, dp, dv, kinds, lanei, team, rank, params)
end

"""Reference position and velocity (in the vehicle's tracked output: 3D for a drone, planar for a car) of vehicle
`i` at world time `tau` (its lane's manoeuvre shifted by its slot, plus its wander if incoherent)."""
function reference26(sc::Scenario26, i::Int, tau::Real)
    q = sc.lane[sc.lanei[i]]
    p = [q.speed * tau, q.amp * (sin(q.om * tau + q.ph) - sin(q.ph)), q.alt] + sc.slots[i]
    v = [q.speed, q.amp * q.om * cos(q.om * tau + q.ph), 0.0]
    if sc.regime == :incoherent
        w = sc.wander[i]; s = sc.sigma * w.amp
        p += s * [sin(w.om * tau + w.ph) - sin(w.ph), cos(w.om * tau + w.ph) - cos(w.ph), sin(w.omz * tau + w.phz) - sin(w.phz)]
        v += s * [w.om * cos(w.om * tau + w.ph), -w.om * sin(w.om * tau + w.ph), w.omz * cos(w.omz * tau + w.phz)]
    end
    d = ny26(sc.fleet.agents[i])
    return p[1:d], v[1:d]
end

"""The references of the step at world time `t0`: `refs[i]` (ny x (H+1) positions) and `term[i]` (terminal position and velocity)."""
function references26(sc::Scenario26, t0::Real)
    refs = Vector{Matrix{Float64}}(undef, sc.n); term = Vector{Vector{Float64}}(undef, sc.n)
    for i in 1:sc.n
        d = ny26(sc.fleet.agents[i])
        R = zeros(d, sc.H + 1)
        for t in 0:sc.H
            R[:, t+1] = reference26(sc, i, t0 + sc.h * t)[1]
        end
        refs[i] = R
        term[i] = [R[:, end]; reference26(sc, i, t0 + sc.h * sc.H)[2]]
    end
    return refs, term
end

"""The start: on the slot (a drone at altitude 1.5) with velocity (1, 0.15), plus the rigid perturbation."""
start26(sc::Scenario26) = [sc.fleet.agents[i].nx == 6 ? [sc.slots[i] + [sc.dp; 1.5]; [1.0, 0.15] + sc.dv; 0.0] :
                           [sc.slots[i][1:2] + sc.dp; [1.0, 0.15] + sc.dv] for i in 1:sc.n]

"""Stage cost of the applied inputs `u` at the states `x` and references `refs` (E19's accounting; `u = nothing`: terminal)."""
function stage_cost26(sc::Scenario26, x, u, refs)
    c = 0.0
    for (i, ag) in enumerate(sc.fleet.agents)
        e = ag.Cr * x[i] - refs[i][:, 1]
        c += 0.5 * dot(e, ag.Q * e)
        u === nothing || (c += 0.5 * dot(u[i], ag.R * u[i]))
    end
    fl = sc.fleet
    for (k, (i, j)) in enumerate(fl.edges)
        d = SM.edge_residual(fl, k, x[i], x[j], 1)
        c += 0.5 * fl.weights[k, 1] * dot(d, d)
    end
    return c
end

formation_error26(sc, x) = sqrt(sum(norm(SM.edge_residual(sc.fleet, k, x[i], x[j], 1))^2
                                    for (k, (i, j)) in enumerate(sc.fleet.edges)) / length(sc.fleet.edges))

"""Clip every input into its set (radial for a ball, componentwise for a box); the clipped inputs and the largest violation before."""
function clip26(sc::Scenario26, u)
    viol = 0.0; out = similar(u)
    for (i, ag) in enumerate(sc.fleet.agents)
        U = ag.input
        if U isa SM.BallSet
            nu = norm(u[i]); viol = max(viol, nu - U.radius)
            out[i] = nu > U.radius ? u[i] * (U.radius / nu) : copy(u[i])
        else
            viol = max(viol, maximum(u[i] - U.hi), maximum(U.lo - u[i]))
            out[i] = clamp.(u[i], U.lo, U.hi)
        end
    end
    return out, viol
end

plant26(sc::Scenario26, x, u) = [ag.A[1] * x[i] + ag.B[1] * u[i] + ag.g[1] for (i, ag) in enumerate(sc.fleet.agents)]

"""Largest ||u|| / amax (ball) or max |u_k| / bound (box) of the inputs `u`."""
activity26(sc, u) = maximum((ag.input isa SM.BallSet ? norm(u[i]) / ag.input.radius : maximum(abs.(u[i]) ./ ag.input.hi))
                            for (i, ag) in enumerate(sc.fleet.agents))

# ---------------------------------------------------------------------------
# The parametric program: the measured state as data
# ---------------------------------------------------------------------------

function _input_rows26(ag::SM.Agent, d::Int, off::Int)
    nu = ag.nu; U = ag.input
    if U isa SM.BallSet
        A = zeros(1 + nu, d); A[2:end, (off+1):(off+nu)] .= -Matrix(1.0I, nu, nu)
        return A, [U.radius; zeros(nu)], [SM.soc_cone(1 + nu)]
    end
    A = zeros(2nu, d); A[1:nu, (off+1):(off+nu)] .= Matrix(1.0I, nu, nu); A[(nu+1):end, (off+1):(off+nu)] .= -Matrix(1.0I, nu, nu)
    return A, [U.hi; -U.lo], [SM.nonneg_cone(2nu)]
end

"""
    ParamProgram26(sc)

The time-expanded program of the fleet with the measured state as data:
vertex (i, 0) holds u_{i,0}, vertex (i, t) holds (x_{i,t}, u_{i,t}) for
1 <= t < H and x_{i,H} at t = H (agent-major order); the dynamics edge from
(i, 0) has tail map B and target A xhat_i + g, the others [A B] and g; the
formation edges as in SM.FleetProgram. `dyn0[i]` is the edge from (i, 0).
"""
struct ParamProgram26
    P::SM.GraphProgram
    vid::Matrix{Int}
    dyn::Matrix{Int}
    CrQ::Vector{Matrix{Float64}}
    CfQf::Vector{Matrix{Float64}}
end

function ParamProgram26(sc::Scenario26)
    fl = sc.fleet; n, H = sc.n, sc.H
    vid = zeros(Int, n, H + 1)
    nodes = SM.NodeData[]
    for i in 1:n, t in 0:H
        ag = fl.agents[i]; nx, nu = ag.nx, ag.nu
        if t == 0
            A, b, cones = _input_rows26(ag, nu, 0)
            push!(nodes, SM.NodeData(ag.R, zeros(nu), 0.0, A, b, cones))
        elseif t < H
            d = nx + nu
            Q = zeros(d, d); Q[1:nx, 1:nx] .= ag.Cr' * ag.Q * ag.Cr; Q[(nx+1):d, (nx+1):d] .= ag.R
            A, b, cones = _input_rows26(ag, d, nx)
            push!(nodes, SM.NodeData(Q, zeros(d), 0.0, A, b, cones))
        else
            push!(nodes, SM.NodeData(ag.Cf' * ag.Qf * ag.Cf, zeros(nx), 0.0))
        end
        vid[i, t+1] = length(nodes)
    end
    edges = SM.GraphEdge[]
    dyn = zeros(Int, n, H)
    for i in 1:n, t in 0:(H-1)
        ag = fl.agents[i]; A, B, g = ag.A[1], ag.B[1], ag.g[1]
        dh = t + 1 < H ? ag.nu : 0
        push!(edges, SM.GraphEdge(vid[i, t+1], vid[i, t+2], t == 0 ? B : [A B], [Matrix(1.0I, ag.nx, ag.nx) zeros(ag.nx, dh)],
                                  true, Matrix(1.0I, ag.nx, ag.nx), copy(g), SM.EdgeTag(:dyn, i, i, t)))
        dyn[i, t+1] = length(edges)
    end
    for t in 1:H, (k, (i, j)) in enumerate(fl.edges)
        ai, aj = fl.agents[i], fl.agents[j]
        di = t < H ? ai.nx + ai.nu : ai.nx; dj = t < H ? aj.nx + aj.nu : aj.nx
        Mi, Mj = SM.edge_maps(fl, k); p = size(Mi, 1)
        push!(edges, SM.GraphEdge(vid[i, t+1], vid[j, t+1], [Mi zeros(p, di - ai.nx)], [Mj zeros(p, dj - aj.nx)], false,
                                  fl.weights[k, t] * Matrix(1.0I, p, p), fl.select[k] * fl.targets[:, k, t], SM.EdgeTag(:form, i, j, t)))
    end
    return ParamProgram26(SM.GraphProgram(nodes, edges), vid, dyn, [ag.Cr' * ag.Q for ag in fl.agents],
                          [ag.Cf' * ag.Qf for ag in fl.agents])
end

"""Write the step's measured states and references into the program in place (no allocation)."""
function set_data26!(pp::ParamProgram26, sc::Scenario26, x, refs, term)
    P = pp.P; H = sc.H
    @inbounds for (i, ag) in enumerate(sc.fleet.agents)
        b = P.edges[pp.dyn[i, 1]].b
        A = ag.A[1]; g = ag.g[1]; xi = x[i]
        for a in eachindex(b)
            s = g[a]
            for j in eachindex(xi)
                s += A[a, j] * xi[j]
            end
            b[a] = s
        end
        R = refs[i]; Q = ag.Q; ny = size(R, 1)
        nd = P.nodes[pp.vid[i, 1]]
        c = 0.0
        for a in 1:ny
            e = xi[a] - R[a, 1]
            c += e * Q[a, a] * e
        end
        nd.c = 0.5 * c
        CrQ = pp.CrQ[i]
        for t in 1:(H-1)
            nd = P.nodes[pp.vid[i, t+1]]
            c = 0.0
            for a in 1:ny
                c += R[a, t+1] * Q[a, a] * R[a, t+1]
            end
            for k in 1:ag.nx
                s = 0.0
                for a in 1:ny
                    s += CrQ[k, a] * R[a, t+1]
                end
                nd.q[k] = -s
            end
            nd.c = 0.5 * c
        end
        nd = P.nodes[pp.vid[i, H+1]]
        rf = term[i]; CfQf = pp.CfQf[i]; Qf = ag.Qf
        c = 0.0
        for k in 1:ag.nx
            s = 0.0
            for a in eachindex(rf)
                s += CfQf[k, a] * rf[a]
            end
            nd.q[k] = -s
            c += rf[k] * Qf[k, k] * rf[k]
        end
        nd.c = 0.5 * c
    end
    return pp
end

"""Every agent's planned states (6 x (H+1), the measured state first) and inputs (3 x H) in a plan `x` of the parametric program."""
function trajectories26(pp::ParamProgram26, sc::Scenario26, xm, x)
    P = pp.P; H = sc.H
    ags = sc.fleet.agents
    X = [zeros(ags[i].nx, H + 1) for i in 1:sc.n]; U = [zeros(ags[i].nu, H) for i in 1:sc.n]
    for i in 1:sc.n
        nx, nu = ags[i].nx, ags[i].nu
        X[i][:, 1] = xm[i]
        U[i][:, 1] = x[SM.vrange(P, pp.vid[i, 1])]
        for t in 1:H
            r = SM.vrange(P, pp.vid[i, t+1])
            X[i][:, t+1] = x[r[1:nx]]
            t < H && (U[i][:, t+1] = x[r[(nx+1):(nx+nu)]])
        end
    end
    return X, U
end

first_inputs26(pp::ParamProgram26, x) = [x[SM.vrange(pp.P, pp.vid[i, 1])] for i in axes(pp.vid, 1)]

# ---------------------------------------------------------------------------
# Resolutions: fine, cond (id x !), red (rows x !, as a chain)
# ---------------------------------------------------------------------------

"""
The levels of a resolution of the parametric program: `fine` none, `cond`
full condensing (one block per agent), `red` full condensing, then pairs of
adjacent blocks of a row merged level by level up to whole rows. `members[b]`
lists the agents of block `b` of the last level.
"""
function chain26(pp::ParamProgram26, sc::Scenario26, form::AbstractString)
    form == "fine" && return SM.ReducedProgram[], [[i] for i in 1:sc.n]
    labels = [i for i in 1:sc.n for t in 0:sc.H]          # agent-major vertices
    R = reduce(pp.P, SM.VertexPartition(labels))
    chain = SM.ReducedProgram[R]
    members = [[i] for i in 1:sc.n]                        # coarse vertex i is agent i (first appearance)
    form == "cond" && return chain, members
    form == "red" || error("unknown form $form")
    w = 1
    maxlen = maximum(count(==(b), sc.team) for b in unique(sc.team))
    while w < maxlen
        w *= 2
        Pi = SM.canonical_partition([(sc.team[m[1]], cld(sc.rank[m[1]], w)) for m in members])
        newm = [Int[] for _ in 1:maximum(Pi)]
        for (b, m) in enumerate(members)
            append!(newm[Pi[b]], m)
        end
        R = reduce(R, SM.VertexPartition(Pi))
        push!(chain, R)
        members = newm
    end
    return chain, members
end

# ---------------------------------------------------------------------------
# The QP of a program with duplicate constraints merged to a tolerance
# ---------------------------------------------------------------------------

"""
    Merged26(P)

The conic QP of `P` (TeamMPC's QPMap without its exact dedup) with cone blocks
and half-space rows merged when their rows of A agree to MERGE_TOL26 relative:
a second-order cone only when its shift agrees too (checked at every step by
`refresh26!`), a half-space row with the tightest bound. `qp` is the merged
QP (current data), `b` its right-hand side in the `b - A x in K` convention,
`group[i]` the merged row of every full row, `valid` false once a merged
cone's copies stopped agreeing (then every row is kept: `unmerge26!`).
"""
mutable struct Merged26
    full::SM.QPMap
    keep::Vector{Int}
    group::Vector{Int}
    qp::SM.ConicQP
    b::Vector{Float64}
    valid::Bool
    spread::Float64
    merged_cones::Int
    merged_rows::Int
    rebuilt::Int
end

function _merge_groups26(qp::SM.ConicQP, b::Vector{Float64}, tol::Float64)
    m = SM.nrows(qp)
    At = SparseMatrixCSC{Float64,Int}(sparse(transpose(qp.A)))
    pat(i) = view(rowvals(At), nzrange(At, i))
    vals(i) = view(nonzeros(At), nzrange(At, i))
    close(u, v) = length(u) == length(v) && (isempty(u) || maximum(abs(u[k] - v[k]) for k in eachindex(u)) <= tol * max(1.0, maximum(abs, v)))
    group = collect(1:m)
    insoc = falses(m)
    for B in qp.socs
        insoc[B] .= true
    end
    # half-space rows: same pattern, values within tol
    reps = Dict{Vector{Int},Vector{Int}}()
    for i in 1:m
        (insoc[i] || qp.kinds[i] != SM.ROW_LEQ) && continue
        isempty(pat(i)) && continue
        lst = get!(reps, collect(pat(i)), Int[])
        hit = 0
        for r in lst
            close(vals(i), vals(r)) && (hit = r; break)
        end
        hit == 0 ? push!(lst, i) : (group[i] = hit)
    end
    # cone blocks: same patterns, values and shift within tol
    sreps = Dict{Vector{Vector{Int}},Vector{Int}}()
    for (k, B) in enumerate(qp.socs)
        key = [collect(pat(i)) for i in B]
        lst = get!(sreps, key, Int[])
        hit = 0
        for r in lst
            Br = qp.socs[r]
            if all(close(vals(B[a]), vals(Br[a])) for a in eachindex(B)) && close(view(b, B), view(b, Br))
                hit = r; break
            end
        end
        if hit == 0
            push!(lst, k)
        else
            Br = qp.socs[hit]
            for a in eachindex(B)
                group[B[a]] = Br[a]
            end
        end
    end
    return group
end

function Merged26(P::SM.GraphProgram; merge::Bool = true)
    full = SM.QPMap(P; dedup = false)
    m = SM.nrows(full.qp)
    group = merge ? _merge_groups26(full.qp, full.b, MERGE_TOL26) : collect(1:m)
    G = Merged26(full, Int[], Int[], full.qp, Float64[], true, 0.0, 0, 0, 0)
    _assemble26!(G, group)
    return G
end

function _assemble26!(G::Merged26, group::Vector{Int})
    qp = G.full.qp
    m = length(group)
    keep = [i for i in 1:m if group[i] == i]
    pos = zeros(Int, m); pos[keep] .= 1:length(keep)
    G.group = [pos[group[i]] for i in 1:m]
    G.keep = keep
    socs = [pos[first(B)]:pos[last(B)] for B in qp.socs if pos[first(B)] > 0]
    G.merged_cones = length(qp.socs) - length(socs)
    G.merged_rows = m - length(keep)
    kinds = qp.kinds[keep]
    G.b = zeros(length(keep))
    G.qp = SM.ConicQP(qp.P, copy(G.full.q), qp.A[keep, :], fill(-Inf, length(keep)), fill(Inf, length(keep));
                      c = G.full.c, socs = socs, socb = zeros(length(keep)), kinds = kinds)
    _fill_b26!(G)
    return G
end

"""The merged right-hand side from the full one (tightest half-space bound; a cone's shift from its kept copy, the spread checked)."""
function _fill_b26!(G::Merged26)
    bf = G.full.b; b = G.b; kinds = G.qp.kinds
    @inbounds for (k, i) in enumerate(G.keep)
        b[k] = bf[i]
    end
    sp = 0.0
    @inbounds for i in eachindex(bf)
        g = G.group[i]
        G.keep[g] == i && continue
        if kinds[g] == SM.ROW_LEQ
            b[g] = min(b[g], bf[i])
        else
            d = abs(b[g] - bf[i]) / max(1.0, abs(b[g]))
            sp = max(sp, d)
        end
    end
    G.spread = sp
    sp > MERGE_TOL26 && (G.valid = false)
    return G
end

"""Refresh the full QP from the program (SM.refresh!) and the merged right-hand side; false if a merged cone's copies disagree."""
function refresh26!(G::Merged26, P::SM.GraphProgram)
    SM.refresh!(G.full, P)
    _fill_b26!(G)
    return G.valid
end

"""Keep every row from now on (the copies of a merged cone stopped agreeing)."""
function unmerge26!(G::Merged26)
    _assemble26!(G, collect(1:SM.nrows(G.full.qp)))
    G.valid = true
    G.rebuilt += 1
    return G
end

"""The merged QP with the current data (bounds from `b` by row kind)."""
function current_qp26(G::Merged26)
    qp = G.qp; m = SM.nrows(qp)
    l = fill(-Inf, m); u = fill(Inf, m); socb = zeros(m)
    @inbounds for i in 1:m
        k = qp.kinds[i]
        if k == SM.ROW_EQ
            l[i] = G.b[i]; u[i] = G.b[i]
        elseif k == SM.ROW_LEQ
            u[i] = G.b[i]
        else
            socb[i] = G.b[i]
        end
    end
    return SM.ConicQP(qp.P, G.full.q, qp.A, l, u; c = G.full.c, socs = qp.socs, socb = socb, kinds = qp.kinds)
end

# ---------------------------------------------------------------------------
# A program of the closed loop: the fine program, its levels, the merged QP
# ---------------------------------------------------------------------------

mutable struct Form26
    name::String
    pp::ParamProgram26
    chain::Vector{SM.ReducedProgram}
    members::Vector{Vector{Int}}
    G::Merged26
    levels::Vector{Vector{Float64}}           # plan at every level, finest first
    xmap::Vector{Int}                         # shifted warm start (empty: the previous solution as it is)
    ymap::Vector{Int}
    t_build::Dict{String,Float64}
    op::Union{SM.StepOperator,Nothing}        # the step operator of the chain (BENCH_STEPOP=1), else nothing
    ubuf::Vector{Float64}                     # the applied inputs it lifts, agent by agent
    coh::Vector{Int}                          # merged copies: the entry of the row's first member, per active entry
    lbmax::Float64                            # and the largest bounds of a copy's error
    lwmax::Float64
    bound::Float64                            # the bound of the last step
    fallbacks::Int                            # steps whose copies were recomputed level by level
end

Pq26(F::Form26) = isempty(F.chain) ? F.pp.P : F.chain[end].program

function Form26(sc::Scenario26, name::AbstractString; x0 = start26(sc), t0 = 0.0, merge::Bool = true)
    tb = Dict{String,Float64}()
    t = time_ns(); pp = ParamProgram26(sc); tb["program"] = (time_ns() - t) / 1e9
    refs, term = references26(sc, t0)
    set_data26!(pp, sc, x0, refs, term)
    t = time_ns(); chain, members = chain26(pp, sc, name); tb["fibers"] = (time_ns() - t) / 1e9
    Pq = isempty(chain) ? pp.P : chain[end].program
    t = time_ns(); G = Merged26(Pq; merge = merge); tb["qp"] = (time_ns() - t) / 1e9
    levels = Vector{Float64}[zeros(SM.c0dim(pp.P))]
    for R in chain
        push!(levels, zeros(SM.c0dim(R.program)))
    end
    op = nothing; coh = Int[]
    if STEPOP26 && !isempty(chain)
        t = time_ns()
        act = active26(pp, sc)
        if G.merged_rows > 0
            # the copies of a merged cone differ by functions of the rows' departure from coherence: chained to
            # their kept row, applied to that departure (small), certified at every step by their error bound
            W, coh = coherence26(pp, sc, act)
            op = SM.StepOperator(chain[end], G.full, act; lift_rows = input_rows26(pp, sc), chains = merge_chains26(G),
                                 invariant = W, link_droptol = LINKTOL26)
        else
            op = SM.StepOperator(chain[end], G.full, act; lift_rows = input_rows26(pp, sc))
        end
        tb["stepop"] = (time_ns() - t) / 1e9
    end
    lb = op === nothing ? 0.0 : maximum(op.linkbound; init = 0.0)
    lw = op === nothing ? 0.0 : maximum(op.linkboundW; init = 0.0)
    F = Form26(String(name), pp, chain, members, G, levels, Int[], Int[], tb, op, zeros(op === nothing ? 0 : length(op.lift_rows)),
               coh, lb, lw, 0.0, 0)
    name == "fine" && shift_maps26!(F, sc)
    return F
end

"""
The entries of the parametric program's data that change from step to step
(what `set_data26!` writes, besides the constants): the tracking costs q of
every state and the targets of the dynamics edges from (i, 0).
"""
function active26(pp::ParamProgram26, sc::Scenario26)
    P = pp.P; act = Int[]
    for (i, ag) in enumerate(sc.fleet.agents)
        for t in 1:sc.H
            append!(act, SM.data_index(P, :q, pp.vid[i, t+1])[1:ag.nx])
        end
        append!(act, SM.data_index(P, :be, pp.dyn[i, 1]))
    end
    return act
end

"""
The chains of the merged rows of `G`: every copy after the previous copy of
its group, the kept row first (so the kept rows are the anchors).
"""
function merge_chains26(G::Merged26)
    prev = zeros(Int, length(G.group)); last = Dict{Int,Int}()
    for i in eachindex(G.group)
        g = G.group[i]
        prev[i] = get(last, g, 0); last[g] = i
    end
    return prev
end

"""
Coherence of the data: the same entry of every member of a row moves alike
when the row's data stay coherent (the members' data differ by their slots
only), and then the copies of a merged cone stay equal (Thm. thm:equitable).
`W` (one column per row and entry) spans these motions; `first[j]` is the
entry of the row's first member that active entry `j` follows.
"""
function coherence26(pp::ParamProgram26, sc::Scenario26, act)
    P = pp.P
    owner = zeros(Int, length(act)); pos = zeros(Int, length(act))
    o = 0
    for i in 1:sc.n
        len = sc.H * sc.fleet.agents[i].nx + length(SM.erange(P, pp.dyn[i, 1]))
        owner[(o+1):(o+len)] .= i; pos[(o+1):(o+len)] .= 1:len
        o += len
    end
    o == length(act) || error("active26 changed its layout")
    cls = Dict{Tuple{Int,Int},Int}(); first = zeros(Int, length(act)); col = zeros(Int, length(act))
    for j in eachindex(act)
        key = (sc.team[owner[j]], pos[j])
        c = get!(cls, key, length(cls) + 1)
        col[j] = c
        sc.rank[owner[j]] == 1 && (first[j] = j)
    end
    firstof = zeros(Int, length(cls))
    for j in eachindex(act)
        first[j] > 0 && (firstof[col[j]] = j)
    end
    return sparse(1:length(act), col, 1.0, length(act), length(cls)), firstof[col]
end

"""
The bound of the copies' error: the data's departure from row coherence since
the build, and the common motion, by the operator's bounds.
"""
function copy_bound26(F::Form26)
    op = F.op; a = op.a; a0 = op.qb.x0; first = F.coh
    dev = 0.0; tinf = 0.0
    @inbounds for j in eachindex(a)
        f = first[j]
        t = a[f] - a0[f]
        dev = max(dev, abs((a[j] - a0[j]) - t)); tinf = max(tinf, abs(t))
    end
    return F.lbmax * dev + F.lwmax * tinf
end

"""The largest relative spread of the merged cones' copies in the full right-hand side `bf` (as `_fill_b26!`)."""
function spread26(G::Merged26, bf::AbstractVector)
    sp = 0.0
    for i in eachindex(bf)
        g = G.group[i]; k = G.keep[g]
        (k == i || G.qp.kinds[g] == SM.ROW_LEQ) && continue
        sp = max(sp, abs(bf[k] - bf[i]) / max(1.0, abs(bf[k])))
    end
    return sp
end

"""The coordinates of the applied inputs u_{i,0} in a plan of the parametric program, agent by agent."""
input_rows26(pp::ParamProgram26, sc::Scenario26) = reduce(vcat, [collect(SM.vrange(pp.P, pp.vid[i, 1])) for i in 1:sc.n])

"""
The shifted warm start of the time-expanded program (MPCController's rule on
the parametric program): x_t, u_t and the dynamics and input-cone multipliers
of instant t take the previous solution's values at t + 1, the last instants
keep their own; then mapped to the merged rows.
"""
function shift_maps26!(F::Form26, sc::Scenario26)
    pp = F.pp; P = pp.P; H = sc.H
    xmap = collect(1:SM.c0dim(P))
    for i in 1:sc.n
        nx, nu = sc.fleet.agents[i].nx, sc.fleet.agents[i].nu
        o0 = P.offsets[pp.vid[i, 1]]; o1 = P.offsets[pp.vid[i, 2]]
        xmap[o0 .+ (1:nu)] = o1 .+ ((nx+1):(nx+nu))                   # u_0 <- u_1
        for t in 1:(H-1)
            ot = P.offsets[pp.vid[i, t+1]]; on = P.offsets[pp.vid[i, t+2]]
            xmap[ot .+ (1:nx)] = on .+ (1:nx)                         # x_t <- x_{t+1}
            t < H - 1 && (xmap[ot .+ ((nx+1):(nx+nu))] = on .+ ((nx+1):(nx+nu)))   # u_t <- u_{t+1}
        end
    end
    # full QP rows: hard (dynamics) edges in edge order, nx rows each, then node rows by vertex
    M = F.G.full
    yfull = collect(1:SM.nrows(M.qp))
    hoff = 0
    for i in 1:sc.n, t in 0:(H-1)
        nx = sc.fleet.agents[i].nx
        t < H - 1 && (yfull[hoff .+ (1:nx)] = hoff + nx .+ (1:nx))
        hoff += nx
    end
    ro = P.row_offsets
    for i in 1:sc.n, t in 0:(H-2)
        v, w = pp.vid[i, t+1], pp.vid[i, t+2]
        (ro[v+1] - ro[v]) == (ro[w+1] - ro[w]) || continue
        yfull[hoff + ro[v] .+ (1:(ro[v+1]-ro[v]))] = hoff + ro[w] .+ (1:(ro[w+1]-ro[w]))
    end
    F.xmap = xmap
    F.ymap = [F.G.group[yfull[i]] for i in F.G.keep]
    return F
end

"""
Construction of a step: the data into the fine program, then the QP vectors of
the last level, by the step operator (one precomposed product from the
changing data; the levels' programs are left behind, `plan26!` brings them
up to date) or level by level (every level's reduction update and the QP
map), and the merged right-hand side. For a merged QP the step operator's
copies come with an error bound, and the merge check is certified with it,
or else done on the copies computed level by level (counted here,
`fallbacks`).
"""
function construct26!(F::Form26, sc::Scenario26, x, refs, term)
    set_data26!(F.pp, sc, x, refs, term)
    if F.op !== nothing
        SM.update!(F.op)
        _fill_b26!(F.G)
        if F.op.deviation
            # the merge check on the copies: certified with their error bound, else on the copies level by level
            F.bound = copy_bound26(F)
            if !(F.G.valid && F.G.spread + F.bound <= MERGE_TOL26)
                SM.sync!(F.op)
                F.G.valid = true
                _fill_b26!(F.G)
                F.fallbacks += 1
            end
        end
        return F.op.feasible, F.G.valid
    end
    feasible = true
    for R in F.chain
        SM.update!(R)
        feasible &= R.feasible
    end
    ok = refresh26!(F.G, Pq26(F))
    return feasible, ok
end

"""
The inputs a solution `y` of the last level applies, u_{i,0} of every agent:
by the step operator (precomposed from `y` and the step's data), or from the
fine plan lifted level by level.
"""
function lift26!(F::Form26, y::AbstractVector)
    if F.op !== nothing
        u = SM.lift!(F.ubuf, F.op, y)
        U = Vector{Vector{Float64}}(undef, size(F.pp.vid, 1))
        o = 0
        for i in eachindex(U)
            d = length(SM.vrange(F.pp.P, F.pp.vid[i, 1]))
            U[i] = u[(o+1):(o+d)]
            o += d
        end
        return U
    end
    return first_inputs26(F.pp, lift_levels26!(F, y))
end

"""Lift a solution of the last level to the fine plan (in place, level by level)."""
function lift_levels26!(F::Form26, y::AbstractVector)
    nl = length(F.chain)
    copyto!(F.levels[nl+1], y)
    for k in nl:-1:1
        SM.lift!(F.levels[k], F.chain[k], F.levels[k+1])
    end
    return F.levels[1]
end

"""
The fine plan of a solution `y`, for the checks (outside the timed step):
with the step operator, the levels are first brought up to the step's data
(`SM.sync!`, the level by level update; the QP vectors it recomputes are
compared with the operator's, `stepop_diff`), then lifted level by level;
without it, the plan `lift26!` lifted.
"""
function plan26!(F::Form26, y::AbstractVector, u, r = nothing)
    F.op === nothing && return F.levels[1]
    M = F.G.full
    q, b = copy(M.q), copy(M.bfull)
    SM.sync!(F.op)
    xf = lift_levels26!(F, y)
    if r !== nothing
        rel(a, c) = isempty(c) ? 0.0 : maximum(abs, a - c) / max(1.0, maximum(abs, c))
        if F.op.deviation
            # the QP's rows are the kept ones; the copies serve the merge check (within their bound)
            kept = F.G.keep
            r["stepop_diff"] = max(rel(q, M.q), rel(b[kept], M.bfull[kept]))
            r["stepop_copy_err"] = maximum(abs, b - M.bfull); r["stepop_copy_bound"] = F.bound
            r["merge_spread_exact"] = spread26(F.G, M.bfull)
        else
            r["stepop_diff"] = max(rel(q, M.q), rel(b, M.bfull))
        end
        r["stepop_input_diff"] = maximum(maximum(abs, u[i] - xf[SM.vrange(F.pp.P, F.pp.vid[i, 1])]) for i in eachindex(u))
    end
    return xf
end

sizes26(F::Form26) = Dict{String,Any}("variables" => SM.nvars(F.G.qp), "rows" => SM.nrows(F.G.qp), "cones" => length(F.G.qp.socs),
    "rows_full" => SM.nrows(F.G.full.qp), "cones_full" => length(F.G.full.qp.socs), "merged_rows" => F.G.merged_rows,
    "merged_cones" => F.G.merged_cones, "nnz_P" => nnz(F.G.qp.P), "nnz_A" => nnz(F.G.qp.A), "levels" => length(F.chain),
    "blocks" => length(F.members), "fine_variables" => SM.c0dim(F.pp.P),
    "nnz_X" => isempty(F.chain) ? 0 : sum(nnz(R.X) for R in F.chain), "nnz_N" => isempty(F.chain) ? 0 : sum(nnz(R.N) for R in F.chain),
    "fiber_kinds" => isempty(F.chain) ? String[] : unique(string.(SM.fiber_kinds(F.chain[end]))),
    "stepop" => F.op !== nothing, "stepop_deviation" => F.op !== nothing && F.op.deviation,
    "nnz_stepop" => F.op === nothing ? 0 : nnz(F.op.qb), "nnz_stepop_lift" => F.op === nothing ? 0 : nnz(F.op.lift),
    "stepop_dust" => F.op === nothing ? 0.0 : F.op.dust, "stepop_copy_bounds" => [F.lbmax, F.lwmax])

# ---------------------------------------------------------------------------
# Solvers on the merged QP
# ---------------------------------------------------------------------------

abstract type Slv26 end

# --- TeamMPC -------------------------------------------------------------

mutable struct SMSlv26 <: Slv26
    s::SM.Solver
    warm::Bool
    xmap::Vector{Int}
    ymap::Vector{Int}
    methods::Dict{String,Int}
end

function SMSlv26(F::Form26; warm::Bool = true)
    st = SM.Settings()
    for (k, v) in pairs(SM_SETTINGS26)
        setproperty!(st, k, v)
    end
    s = SM.setup(current_qp26(F.G); settings = st)
    return SMSlv26(s, warm, F.xmap, F.ymap, Dict{String,Int}())
end

function update26!(S::SMSlv26, F::Form26)
    # the step operator does not recompute the constant (it does not move the minimizer): the solver keeps its own
    SM.update!(S.s; q = F.G.full.q, b = F.G.b, c = F.op === nothing ? F.G.full.c : nothing)
    if !S.warm || S.s.info.status != :solved
        SM.reset!(S.s)
    elseif !isempty(S.xmap)
        SM.warm_start_shifted!(S.s, S.xmap, S.ymap)
    end                                           # else: the previous solution as it is
    return S
end

function solve26!(S::SMSlv26)
    info = SM.solve!(S.s)
    k = string(info.method); S.methods[k] = get(S.methods, k, 0) + 1
    return S.s.xsol, info.status, info.iter + info.ipm_iter
end

info26(S::SMSlv26) = Dict{String,Any}("solver" => "TeamMPC", "eps_abs" => S.s.settings.eps_abs, "eps_rel" => S.s.settings.eps_rel,
    "max_iter" => S.s.settings.max_iter, "method" => string(S.s.settings.method), "polish" => S.s.settings.polish,
    "warm" => S.warm ? (isempty(S.xmap) ? "previous solution" : "previous solution shifted one instant") : "cold (reset!)",
    "methods_used" => S.methods, "linsys" => string(S.s.info.linsys))

# --- Clarabel -------------------------------------------------------------

mutable struct ClaSlv26 <: Slv26
    s::Clarabel.Solver{Float64}
    settings::Clarabel.Settings{Float64}
end

function clarabel_cones26(qp::SM.ConicQP)
    cones = Clarabel.SupportedCone[]
    socstart = Dict(first(B) => length(B) for B in qp.socs)
    i = 1; m = SM.nrows(qp)
    while i <= m
        if haskey(socstart, i)
            push!(cones, Clarabel.SecondOrderConeT(socstart[i])); i += socstart[i]; continue
        end
        k = qp.kinds[i]; j = i
        while j + 1 <= m && qp.kinds[j+1] == k && !haskey(socstart, j + 1)
            j += 1
        end
        k == SM.ROW_EQ ? push!(cones, Clarabel.ZeroConeT(j - i + 1)) :
        k == SM.ROW_LEQ ? push!(cones, Clarabel.NonnegativeConeT(j - i + 1)) : error("interval row in the merged QP")
        i = j + 1
    end
    return cones
end

function ClaSlv26(F::Form26; tol::Float64 = 1e-8)
    qp = F.G.qp
    st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol, direct_solve_method = :qdldl,
                           presolve_enable = false, chordal_decomposition_enable = false, input_sparse_dropzeros = false)
    s = Clarabel.Solver()
    Clarabel.setup!(s, SparseMatrixCSC{Float64,Int}(triu(qp.P)), copy(F.G.full.q), qp.A, copy(F.G.b), clarabel_cones26(qp), st)
    return ClaSlv26(s, st)
end

function update26!(S::ClaSlv26, F::Form26)
    Clarabel.update_q!(S.s, F.G.full.q)
    Clarabel.update_b!(S.s, F.G.b)
    return S
end

function solve26!(S::ClaSlv26)
    r = Clarabel.solve!(S.s)
    st = r.status == Clarabel.SOLVED ? :solved : Symbol(lowercase(string(r.status)))
    return r.x, st, Int(r.iterations)
end

info26(S::ClaSlv26) = Dict{String,Any}("solver" => "Clarabel 0.11.1", "tol_gap_abs" => S.settings.tol_gap_abs,
    "tol_gap_rel" => S.settings.tol_gap_rel, "tol_feas" => S.settings.tol_feas, "direct_solve_method" => string(S.settings.direct_solve_method),
    "presolve_enable" => S.settings.presolve_enable, "chordal_decomposition_enable" => S.settings.chordal_decomposition_enable,
    "warm" => "cold (interior point)")

# --- OSQP -----------------------------------------------------------------

"""OSQP's form of the merged QP (no cones): equality rows, then every half-space row merged with its mirror into one interval row."""
struct OSQPLay26
    A::SparseMatrixCSC{Float64,Int}
    P::SparseMatrixCSC{Float64,Int}
    eq::Vector{Int}                                  # merged rows kept as l = u = b
    ub::Vector{Vector{Tuple{Int,Float64}}}           # interval row k: u = min(b[r] * s)
    lb::Vector{Vector{Tuple{Int,Float64}}}           # interval row k: l = max(b[r] * s)
    row_of::Vector{Int}                              # OSQP row of every merged row
end

function OSQPLay26(qp::SM.ConicQP)
    isempty(qp.socs) || error("OSQP has no second-order cone")
    At = SparseMatrixCSC{Float64,Int}(sparse(transpose(qp.A)))
    m = SM.nrows(qp)
    eq = [i for i in 1:m if qp.kinds[i] == SM.ROW_EQ]
    row_of = zeros(Int, m)
    row_of[eq] .= 1:length(eq)
    keys_ = Dict{Tuple{Vector{Int},Vector{Float64}},Int}()
    ub = Vector{Vector{Tuple{Int,Float64}}}(); lb = Vector{Vector{Tuple{Int,Float64}}}()
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for i in 1:m
        qp.kinds[i] == SM.ROW_LEQ || continue
        rg = nzrange(At, i); cols = rowvals(At)[rg]; vals = nonzeros(At)[rg]
        isempty(cols) && continue
        s = vals[1]
        k = get!(keys_, (cols, vals ./ s)) do
            push!(ub, Tuple{Int,Float64}[]); push!(lb, Tuple{Int,Float64}[])
            for (c, v) in zip(cols, vals ./ s)
                push!(I_, length(ub)); push!(J_, c); push!(V_, v)
            end
            length(ub)
        end
        s > 0 ? push!(ub[k], (i, 1 / s)) : push!(lb[k], (i, 1 / s))
        row_of[i] = length(eq) + k
    end
    A = [qp.A[eq, :]; sparse(I_, J_, V_, length(ub), SM.nvars(qp))]
    return OSQPLay26(SparseMatrixCSC{Float64,Int}(A), SparseMatrixCSC{Float64,Int}(triu(qp.P)), eq, ub, lb, row_of)
end

function osqp_bounds26(L::OSQPLay26, b::Vector{Float64})
    ne = length(L.eq); nm = length(L.ub)
    l = Vector{Float64}(undef, ne + nm); u = similar(l)
    @inbounds for (k, r) in enumerate(L.eq)
        l[k] = b[r]; u[k] = b[r]
    end
    @inbounds for k in 1:nm
        u[ne+k] = isempty(L.ub[k]) ? Inf : minimum(b[r] * s for (r, s) in L.ub[k])
        l[ne+k] = isempty(L.lb[k]) ? -Inf : maximum(b[r] * s for (r, s) in L.lb[k])
    end
    return l, u
end

mutable struct OSQPSlv26 <: Slv26
    L::OSQPLay26
    m::OSQP.Model
    warm::Bool
    rho::Float64
    xmap::Vector{Int}
    ymap::Vector{Int}                             # OSQP rows (empty: the previous solution as it is)
    xprev::Vector{Float64}
    yprev::Vector{Float64}
    eps::Float64
end

osqp_settings26(m::OSQP.Model) = unsafe_load(unsafe_load(m.workspace).settings)

function OSQPSlv26(F::Form26; warm::Bool, eps::Float64 = OSQP_EPS26)
    L = OSQPLay26(F.G.qp)
    l, u = osqp_bounds26(L, F.G.b)
    rho = 0.1
    m = OSQP.Model()
    OSQP.setup!(m; P = L.P, q = copy(F.G.full.q), A = L.A, l = l, u = u, eps_abs = eps, eps_rel = eps, polish = true,
                max_iter = 400_000, adaptive_rho = true, verbose = false, warm_start = warm, rho = rho)
    # OSQP.jl drops unknown keywords silently (an earlier bench passed `warm_starting`): read the settings back
    s = osqp_settings26(m)
    (s.warm_start == Int(warm) && s.eps_abs == eps && s.eps_rel == eps && s.polish == 1 && s.rho == rho) ||
        error("OSQP settings did not take effect: warm_start = $(s.warm_start), eps_abs = $(s.eps_abs), rho = $(s.rho)")
    ymap = Int[]
    if !isempty(F.xmap)
        # OSQP row k takes the previous value of the OSQP row of the shifted merged row behind it
        rep = zeros(Int, size(L.A, 1))
        for (i, r) in enumerate(L.row_of)
            r > 0 && rep[r] == 0 && (rep[r] = i)
        end
        ymap = [L.row_of[F.ymap[rep[k]]] for k in 1:size(L.A, 1)]
    end
    return OSQPSlv26(L, m, warm, rho, F.xmap, ymap, Float64[], Float64[], eps)
end

function update26!(S::OSQPSlv26, F::Form26)
    l, u = osqp_bounds26(S.L, F.G.b)
    OSQP.update!(S.m; q = F.G.full.q, l = l, u = u)
    if S.warm && !isempty(S.xprev) && !isempty(S.ymap)
        OSQP.warm_start!(S.m; x = S.xprev[S.xmap], y = S.yprev[S.ymap])
    end                                                    # else: OSQP's own warm start, the previous solution as it is
    return S
end

function solve26!(S::OSQPSlv26)
    r = OSQP.solve!(S.m)
    S.xprev = copy(r.x); S.yprev = copy(r.y)
    st = r.info.status == :Solved ? :solved : Symbol(lowercase(string(r.info.status)))
    return r.x, st, Int(r.info.iter)
end

info26(S::OSQPSlv26) = (s = osqp_settings26(S.m);
    Dict{String,Any}("solver" => "OSQP 0.8.1", "eps_abs" => s.eps_abs, "eps_rel" => s.eps_rel, "polish" => s.polish,
                     "adaptive_rho" => s.adaptive_rho, "rho_initial" => S.rho, "max_iter" => s.max_iter, "warm_start" => s.warm_start,
                     "warm" => S.warm ? (isempty(S.ymap) ? "previous solution (OSQP's own)" : "previous solution shifted one instant") :
                                        "cold (warm_start = false, rho reset before each solve)"))

# --- Mumblebee -------------------------------------------------------------

"""
Mumblebee's form of the merged QP (bench/central/reduce_solvers.jl's
mumblebee_layout, on the merged QP): min (1/2) p'Qp - f'p s.t. Bp = g, p in K.
An input variable bounded by exactly one cone row (an input ball) sits inside
that cone; a variable bounded by exactly one pair of half-space rows is shifted
to w = x - lo >= 0 with v = hi - x >= 0 and w + v = hi - lo; every other cone
row gets a slack. x = S p - sh.
"""
struct MBLay26
    Q::SparseMatrixCSC{Float64,Int}
    B::SparseMatrixCSC{Float64,Int}
    K::Vector{AbstractCone}
    s::Vector{Int}
    S::SparseMatrixCSC{Float64,Int}
    soc_vars::Vector{Tuple{Int,Int,Float64}}
    box_vars::Vector{Tuple{Int,Int,Int,Float64,Float64}}
    eq_rows::Vector{Int}
    nn_rows::Vector{Int}
    t_rows::Vector{Int}
    socslack_rows::Vector{Int}
    A::SparseMatrixCSC{Float64,Int}
    H::SparseMatrixCSC{Float64,Int}
end

function MBLay26(qp::SM.ConicQP)
    n = SM.nvars(qp); m = SM.nrows(qp)
    A = qp.A
    At = SparseMatrixCSC{Float64,Int}(sparse(transpose(A)))
    nzr(r) = nzrange(At, r)
    insoc = zeros(Int, m)
    for (k, B) in enumerate(qp.socs)
        insoc[B] .= k
    end
    ineq_count = zeros(Int, n)
    for r in 1:m
        qp.kinds[r] == SM.ROW_EQ && continue
        for p in nzr(r)
            ineq_count[rowvals(At)[p]] += 1
        end
    end
    role = fill(:free, n)
    soc_direct = Tuple{UnitRange{Int},Vector{Tuple{Int,Float64}}}[]
    soc_slack = UnitRange{Int}[]
    for B in qp.socs
        ok = isempty(nzr(B[1]))
        vars = Tuple{Int,Float64}[]
        if ok
            for r in B[2:end]
                rg = nzr(r)
                if length(rg) == 1 && ineq_count[rowvals(At)[rg[1]]] == 1 && role[rowvals(At)[rg[1]]] == :free
                    push!(vars, (rowvals(At)[rg[1]], nonzeros(At)[rg[1]]))
                else
                    ok = false; break
                end
            end
            ok = ok && length(unique(first.(vars))) == length(vars)
        end
        if ok
            for (j, _) in vars
                role[j] = :soc
            end
            push!(soc_direct, (B, vars))
        else
            push!(soc_slack, B)
        end
    end
    single = Dict{Int,Vector{Tuple{Int,Float64}}}()
    for r in 1:m
        (qp.kinds[r] == SM.ROW_LEQ && insoc[r] == 0) || continue
        rg = nzr(r)
        length(rg) == 1 || continue
        push!(get!(single, rowvals(At)[rg[1]], Tuple{Int,Float64}[]), (r, nonzeros(At)[rg[1]]))
    end
    box = Tuple{Int,Int,Int,Float64,Float64}[]
    used = falses(m)
    for j in sort!(collect(keys(single)))
        rs = single[j]
        (length(rs) == 2 && ineq_count[j] == 2 && role[j] == :free) || continue
        up = findfirst(t -> t[2] > 0, rs); lo = findfirst(t -> t[2] < 0, rs)
        (up === nothing || lo === nothing) && continue
        push!(box, (j, rs[up][1], rs[lo][1], rs[up][2], rs[lo][2]))
        role[j] = :box; used[rs[up][1]] = true; used[rs[lo][1]] = true
    end
    nn_rows = [r for r in 1:m if qp.kinds[r] == SM.ROW_LEQ && insoc[r] == 0 && !used[r]]
    eq_rows = [r for r in 1:m if qp.kinds[r] == SM.ROW_EQ]
    free = findall(==(:free), role)
    nf = length(free); nbx = length(box); nns = length(nn_rows)
    SI = Int[]; SJ = Int[]; SV = Float64[]
    for (k, j) in enumerate(free)
        push!(SI, j); push!(SJ, k); push!(SV, 1.0)
    end
    for (k, (j, _, _, _, _)) in enumerate(box)
        push!(SI, j); push!(SJ, nf + 2k - 1); push!(SV, 1.0)
    end
    off = nf + 2nbx + nns
    K = AbstractCone[]; s = Int[]
    nf > 0 && (push!(K, CofreeCone()); push!(s, nf))
    (2nbx + nns) > 0 && (push!(K, PositiveCone()); push!(s, 2nbx + nns))
    soc_vars = Tuple{Int,Int,Float64}[]
    t_rows = Int[]; t_cols = Int[]
    socslack_rows = Int[]; socslack_cols = Int[]
    for (rr, vars) in soc_direct
        push!(t_rows, rr[1]); push!(t_cols, off + 1)
        for (k, (j, a)) in enumerate(vars)
            push!(SI, j); push!(SJ, off + 1 + k); push!(SV, -1 / a)
            push!(soc_vars, (j, rr[1+k], a))
        end
        push!(K, SecondOrderCone()); push!(s, length(rr)); off += length(rr)
    end
    for rr in soc_slack
        append!(socslack_rows, rr); append!(socslack_cols, off .+ (1:length(rr)))
        push!(K, SecondOrderCone()); push!(s, length(rr)); off += length(rr)
    end
    np = off
    Smat = sparse(SI, SJ, SV, n, np)
    blocks = SparseMatrixCSC{Float64,Int}[]
    push!(blocks, A[eq_rows, :] * Smat)
    push!(blocks, sparse([1:nbx; 1:nbx], [nf .+ (2(1:nbx) .- 1); nf .+ 2(1:nbx)], ones(2nbx), nbx, np))
    push!(blocks, A[nn_rows, :] * Smat + sparse(1:nns, nf + 2nbx .+ (1:nns), ones(nns), nns, np))
    push!(blocks, sparse(1:length(t_rows), t_cols, ones(length(t_rows)), length(t_rows), np))
    push!(blocks, A[socslack_rows, :] * Smat + sparse(1:length(socslack_rows), socslack_cols, ones(length(socslack_rows)), length(socslack_rows), np))
    B = reduce(vcat, blocks)
    Q = Smat' * qp.P * Smat; Q = (Q + Q') / 2
    return MBLay26(SparseMatrixCSC{Float64,Int}(Q), SparseMatrixCSC{Float64,Int}(B), K, s, SparseMatrixCSC{Float64,Int}(Smat),
                   soc_vars, box, eq_rows, nn_rows, t_rows, socslack_rows, A, qp.P)
end

function mb_vectors26(L::MBLay26, q::Vector{Float64}, b::Vector{Float64})
    sh = zeros(size(L.S, 1))
    for (j, r, a) in L.soc_vars
        sh[j] = -b[r] / a
    end
    ub = Float64[]; lb = Float64[]
    for (j, ru, rl, au, al) in L.box_vars
        U = b[ru] / au; Lo = b[rl] / al
        sh[j] = -Lo
        push!(ub, U); push!(lb, Lo)
    end
    Ash = L.A * sh
    gm = [b[L.eq_rows] + Ash[L.eq_rows]; ub - lb; b[L.nn_rows] + Ash[L.nn_rows]; b[L.t_rows]; b[L.socslack_rows] + Ash[L.socslack_rows]]
    f = -(L.S' * (q - L.H * sh))
    return f, gm, sh
end

mutable struct MBSlv26 <: Slv26
    L::MBLay26
    prob::Any
    solver::Any
    settings::Any
    f::Vector{Float64}
    g::Vector{Float64}
    sh::Vector{Float64}
    t_init::Float64
end

function MBSlv26(F::Form26; tol::Float64 = 1e-8)
    L = MBLay26(F.G.qp)
    f, g, sh = mb_vectors26(L, F.G.full.q, F.G.b)
    st = IPMSettings{Float64}(; elim_alg = AMF(), feas_tol = tol, gap_tol = tol, max_iter = 200, verbose = 0)
    prob = IPMProblem(L.Q, L.B, f, g, 0.0, L.K, L.s)
    solver = IPM.init(prob, st)
    return MBSlv26(L, prob, solver, st, f, g, sh, 0.0)
end

function update26!(S::MBSlv26, F::Form26)
    S.f, S.g, S.sh = mb_vectors26(S.L, F.G.full.q, F.G.b)
    return S
end

"""Mumblebee at e78d9b9: reinit! keeps the KKT solver's state and repeated solves can stop at iteration 1, so each solve starts from a fresh init (outside the timer)."""
function before_solve26!(S::MBSlv26)
    S.t_init = @elapsed (S.solver = IPM.init(S.prob, S.settings))
    return S
end
"""OSQP cold: the initial step size before each solve (a refactorization, outside the timer, the central bench's rule)."""
function before_solve26!(S::OSQPSlv26)
    S.warm || OSQP.update_settings!(S.m; rho = S.rho)
    return S
end
before_solve26!(S::Slv26) = S

function solve26!(S::MBSlv26)
    IPM.reinit!(S.solver; f = S.f, g = S.g)
    r = IPM.solve!(S.solver)
    st = string(r.status) == "OPTIMAL" ? :solved : Symbol(lowercase(string(r.status)))
    return S.L.S * r.p - S.sh, st, Int(r.niter)
end

info26(S::MBSlv26) = Dict{String,Any}("solver" => "Mumblebee e78d9b9", "feas_tol" => S.settings.feas_tol, "gap_tol" => S.settings.gap_tol,
    "max_iter" => S.settings.max_iter, "elim_alg" => "AMF", "variables" => size(S.L.S, 2), "rows" => size(S.L.B, 1),
    "warm" => "cold (interior point; a fresh init before every solve, outside the timer)")

function make_solver26(name::AbstractString, F::Form26)
    name == "teammpc_warm" && return SMSlv26(F; warm = true)
    name == "teammpc_cold" && return SMSlv26(F; warm = false)
    name == "clarabel" && return ClaSlv26(F)
    name == "clarabel_tight" && return ClaSlv26(F; tol = 1e-10)
    name == "mumblebee" && return MBSlv26(F)
    name == "osqp_cold" && return OSQPSlv26(F; warm = false)
    name == "osqp_warm" && return OSQPSlv26(F; warm = true)
    error("unknown solver $name")
end

supports26(name, cone) = !(startswith(name, "osqp") && cone == :soc)

# ---------------------------------------------------------------------------
# The TeamMPC closed loop
# ---------------------------------------------------------------------------

"""
One closed loop of `steps` steps of the controller of `F` (TeamMPC, warm as
MPCController), from `x0`. Records the per-step times, statuses, plan
objective (on the fine program) and feasibility, and the applied inputs and
states (kept in memory for the comparison of the loops and saved for the
replays).
"""
function graph_loop26(sc::Scenario26, F::Form26, x0; steps::Int = STEPS26)
    t = time_ns(); S = SMSlv26(F; warm = true); tsetup0 = (time_ns() - t) / 1e9
    x = [copy(v) for v in x0]
    rec = Dict{String,Any}[]; cost = 0.0
    xs = Vector{Vector{Vector{Float64}}}(); us = Vector{Vector{Vector{Float64}}}()
    Js = Float64[]; plan0 = Float64[]; U0 = Vector{Vector{Float64}}()
    P = F.pp.P
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        r = Dict{String,Any}("step" => k)
        t0 = time_ns()
        feasible, ok = construct26!(F, sc, x, refs, term)
        t1 = time_ns()
        if !ok
            unmerge26!(F.G)
            F.op !== nothing && F.op.deviation && (F.op = nothing; r["stepop_off"] = true)   # copies are rows now: level by level
            F.name == "fine" && shift_maps26!(F, sc)
            S = SMSlv26(F; warm = true)
            r["unmerged"] = true
        end
        t2 = time_ns()
        k == 0 || update26!(S, F)
        t3 = time_ns()
        y, status, iter = solve26!(S)
        t4 = time_ns()
        u = lift26!(F, y)
        t5 = time_ns()
        xf = plan26!(F, y, u, r)
        fz = SM.feasibility(P, xf)
        J = SM.objective(P, xf)
        k == 0 && (plan0 = copy(xf))
        r["t_construct"] = (t1 - t0) / 1e9; r["t_setup"] = (t3 - t1) / 1e9 + (k == 0 ? tsetup0 : 0.0)
        r["t_solve"] = (t4 - t3) / 1e9; r["t_lift"] = (t5 - t4) / 1e9
        r["t_total"] = (t5 - t0) / 1e9 + (k == 0 ? tsetup0 : 0.0)
        r["status"] = string(feasible ? status : :primal_infeasible); r["iter"] = iter; r["method"] = string(S.s.info.method)
        r["polish"] = string(S.s.info.polish); r["J"] = J; r["feas_hard"] = fz.hard; r["feas_cone"] = fz.cone
        r["merge_spread"] = get(r, "merge_spread_exact", F.G.spread); r["activity"] = activity26(sc, u)
        uc, viol = clip26(sc, u)
        r["input_violation_raw"] = viol
        r["stage_cost"] = stage_cost26(sc, x, uc, refs); r["formation_error"] = formation_error26(sc, x)
        cost += r["stage_cost"]
        push!(rec, r); push!(xs, x); push!(us, uc); push!(Js, J)
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    push!(xs, x)
    return Dict{String,Any}("closed_loop_cost" => cost, "steps" => rec, "setup_seconds" => tsetup0, "solver" => info26(S),
                            "rebuilt" => F.G.rebuilt, "stepop_fallbacks" => F.fallbacks), (x = xs, u = us, J = Js, plan0 = plan0)
end

sumstats26(v) = isempty(v) ? Dict{String,Any}() :
    Dict{String,Any}("median" => median(v), "min" => minimum(v), "max" => maximum(v), "mean" => mean(v), "n" => length(v))

function summarize_loop26!(out)
    rec = out["steps"]
    col(key) = [Float64(r[key]) for r in rec if haskey(r, key)]
    for key in ("t_construct", "t_setup", "t_solve", "t_lift", "t_total")
        v = col(key)
        out[key] = sumstats26(v)
        out[key*"_after_first"] = sumstats26(v[2:end])
    end
    out["iter"] = sumstats26(col("iter"))
    out["feas_hard_max"] = maximum(col("feas_hard")); out["feas_cone_max"] = maximum(col("feas_cone"))
    out["unsolved_steps"] = count(r -> r["status"] != "solved", rec)
    out["methods"] = Dict(m => count(r -> r["method"] == m, rec) for m in unique(r["method"] for r in rec))
    out["activity_max"] = maximum(col("activity")); out["activity_steps"] = count(>=(1 - 1e-6), col("activity"))
    out["input_violation_raw"] = maximum(col("input_violation_raw"))
    out["mean_formation_error"] = mean(col("formation_error"))
    out["merge_spread_max"] = maximum(col("merge_spread"))
    v = col("stepop_diff"); isempty(v) || (out["stepop_diff_max"] = maximum(v))
    v = col("stepop_input_diff"); isempty(v) || (out["stepop_input_diff_max"] = maximum(v))
    v = col("stepop_copy_err"); isempty(v) || (out["stepop_copy_err_max"] = maximum(v); out["stepop_copy_bound_max"] = maximum(col("stepop_copy_bound")))
    return out
end

maxdiff26(a, b) = maximum(maximum(abs, a[k][i] - b[k][i]) for k in eachindex(a) for i in eachindex(a[k]))

# ---------------------------------------------------------------------------
# Replays: a solver on the sequence of programs of a closed loop
# ---------------------------------------------------------------------------

"""
Solver `name` on the programs of the closed loop `traj` (the measured states of
each step) in form `F`: per step construction, the data into the solver
(setup), solve and lift, timed apart; the lifted plan scored on the fine
program against the loop's objective `traj.J`.
"""
function replay26(sc::Scenario26, F::Form26, name::AbstractString, traj; steps::Int = REPLAY26)
    t = time_ns(); S = make_solver26(name, F); tsetup0 = (time_ns() - t) / 1e9
    P = F.pp.P
    rec = Dict{String,Any}[]
    for k in 0:(min(steps, length(traj.J))-1)
        refs, term = references26(sc, k * sc.h)
        r = Dict{String,Any}("step" => k)
        t0 = time_ns()
        _, ok = construct26!(F, sc, traj.x[k+1], refs, term)
        t1 = time_ns()
        if !ok
            unmerge26!(F.G)
            F.op !== nothing && F.op.deviation && (F.op = nothing; r["stepop_off"] = true)   # copies are rows now: level by level
            F.name == "fine" && shift_maps26!(F, sc)
            S = make_solver26(name, F)
            r["unmerged"] = true
        end
        t2 = time_ns()
        k == 0 || update26!(S, F)
        t3 = time_ns()
        before_solve26!(S)
        t4 = time_ns()
        y, status, iter = solve26!(S)
        t5 = time_ns()
        u = lift26!(F, y)
        t6 = time_ns()
        xf = plan26!(F, y, u, r)
        J = SM.objective(P, xf); fz = SM.feasibility(P, xf)
        r["t_construct"] = (t1 - t0) / 1e9; r["t_setup"] = (t3 - t1) / 1e9 + (k == 0 ? tsetup0 : 0.0)
        r["t_reset"] = (t4 - t3) / 1e9
        r["t_solve"] = (t5 - t4) / 1e9; r["t_lift"] = (t6 - t5) / 1e9
        r["t_total"] = r["t_construct"] + r["t_setup"] + r["t_solve"] + r["t_lift"]
        S isa MBSlv26 && (r["t_init"] = S.t_init)
        r["status"] = string(status); r["iter"] = iter; r["J"] = J
        r["J_rel_diff"] = (J - traj.J[k+1]) / abs(traj.J[k+1])
        r["feas_hard"] = fz.hard; r["feas_cone"] = fz.cone
        push!(rec, r)
        GC.gc(false)
    end
    out = Dict{String,Any}("solver" => name, "form" => F.name, "steps" => rec, "setup_seconds" => tsetup0, "settings" => info26(S),
                           "replayed_steps" => length(rec))
    col(key) = [Float64(r[key]) for r in rec if haskey(r, key)]
    for key in ("t_construct", "t_setup", "t_solve", "t_lift", "t_total", "t_reset", "t_init")
        v = col(key)
        isempty(v) && continue
        out[key] = sumstats26(v); out[key*"_after_first"] = sumstats26(v[2:end])
    end
    out["iter"] = sumstats26(col("iter"))
    out["J_rel_diff_absmax"] = maximum(abs, col("J_rel_diff"))
    out["feas_hard_max"] = maximum(col("feas_hard")); out["feas_cone_max"] = maximum(col("feas_cone"))
    out["unsolved_steps"] = count(r -> r["status"] != "solved", rec)
    v = col("stepop_diff"); isempty(v) || (out["stepop_diff_max"] = maximum(v))
    return out
end

# ---------------------------------------------------------------------------
# Step 0: gap bounds, accuracy reference, consistency checks
# ---------------------------------------------------------------------------

function step0_checks26(sc::Scenario26, Ffine::Form26, Fred::Form26)
    out = Dict{String,Any}()
    P = Fred.pp.P                                  # the root of the chain (gap_bounds needs that very program)
    x0 = start26(sc); refs, term = references26(sc, 0.0)
    construct26!(Fred, sc, x0, refs, term)
    construct26!(Ffine, sc, x0, refs, term)
    Fred.op === nothing || SM.sync!(Fred.op)       # the levels' programs at the step's data
    Rtop = Fred.chain[end]
    tf = @elapsed fine0 = SM.solve(P)
    tr = @elapsed red0 = SM.solve(Rtop)
    out["fine_status"] = string(fine0.status); out["reduced_status"] = string(red0.status)
    out["J_fine"] = fine0.J; out["J_reduced"] = red0.J; out["fine_solve_seconds"] = tf; out["reduced_solve_seconds"] = tr
    if SM.isoptimal(fine0) && SM.isoptimal(red0)
        tg = @elapsed gb = SM.gap_bounds(P, Rtop, red0; fine_solution = fine0)
        out["gap_lower"] = gb.lower; out["gap"] = gb.gap; out["gap_upper"] = gb.upper; out["gap_residual"] = gb.residual
        out["gap_seconds"] = tg
        out["gap_rel"] = gb.gap / abs(fine0.J); out["lower_rel"] = gb.lower / abs(fine0.J); out["upper_rel"] = gb.upper / abs(fine0.J)
        out["plan_diff"] = maximum(abs, SM.lift(Rtop, red0) - fine0.x)
    end
    # input cones at their bound at the fine optimum
    nact = 0
    for (i, ag) in enumerate(sc.fleet.agents), t in 0:(sc.H-1)
        r = SM.vrange(P, Ffine.pp.vid[i, t+1]); u = t == 0 ? fine0.x[r] : fine0.x[r[(ag.nx+1):(ag.nx+ag.nu)]]
        a = ag.input isa SM.BallSet ? norm(u) / ag.input.radius : maximum(abs.(u) ./ ag.input.hi)
        a >= 1 - 1e-5 && (nact += 1)
    end
    out["active_input_sets_step0"] = nact
    if TIGHT26
        St = make_solver26("clarabel_tight", Ffine)
        y, st, it = solve26!(St)
        out["J_tight"] = SM.objective(P, y); out["tight_status"] = string(st)
    end
    if sc.n <= 256
        # the chain against the one-step reduction along rows x !
        Pi = [sc.team[i] for i in 1:sc.n for t in 0:sc.H]
        one = reduce(P, SM.VertexPartition(Pi))
        s1 = SM.solve(one)
        out["J_one_step"] = s1.J
        out["chain_vs_one_step"] = abs(s1.J - red0.J) / abs(red0.J)
        out["one_step_nnz_X"] = nnz(one.X); out["chain_nnz_X"] = sum(nnz(R.X) for R in Fred.chain)
        # the parametric program against the package's FleetProgram (x_{i,0} pinned)
        fp = SM.FleetProgram(sc.fleet; x0 = x0, references = refs, terminal = term)
        s2 = SM.solve(fp)
        out["J_fleetprogram"] = s2.J
        out["param_vs_fleetprogram"] = abs(s2.J - fine0.J) / abs(fine0.J)
        # the package's own exact dedup on the reduced program
        Mp = SM.QPMap(Rtop.program; dedup = true)
        out["package_dedup_rows"] = SM.nrows(Mp.qp); out["package_dedup_cones"] = length(Mp.qp.socs)
    end
    return out
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

fleettag_dc() = FLEET_DC == :quad ? "" : string(FLEET_DC == :dronecar ? "dc" : FLEET_DC, LAYOUT_DC == :rows ? "" : "_" * string(LAYOUT_DC),
                                                 HET_DC ? "_het" : "", TEAMS_DC == :cr ? "" : "_" * string(TEAMS_DC), "_")
tag26(sc) = "$(fleettag_dc())$(sc.regime)_$(sc.cone)_n$(sc.n)_seed$(sc.seed)"

function meta26()
    sm = pkgdir(SM)
    rev = try readchomp(`git -C $sm rev-parse --short HEAD`) catch
        f = joinpath(sm, ".synced_rev"); isfile(f) ? first(strip(read(f, String)), 7) : "unknown"
    end
    dirty = try !isempty(readchomp(`git -C $sm status --porcelain --untracked-files=no -- src`)) catch; false end
    return Dict{String,Any}("julia" => string(VERSION), "host" => gethostname(), "threads" => Threads.nthreads(),
        "blas_threads" => BLAS.get_num_threads(), "cpu" => Sys.cpu_info()[1].model, "teammpc_rev" => rev,
        "teammpc_dirty" => dirty, "teammpc_path" => sm, "slurm_job" => get(ENV, "SLURM_JOB_ID", ""),
        "affinity" => try readchomp(`taskset -cp $(getpid())`) catch; "" end,
        "fleet" => string(FLEET_DC), "layout" => string(LAYOUT_DC), "het" => HET_DC, "teams" => string(TEAMS_DC),
        "umax_car" => UMAX_CAR_DC)
end

jsonable26(x::AbstractDict) = Dict{String,Any}(string(k) => jsonable26(v) for (k, v) in x)
jsonable26(x::AbstractVector) = [jsonable26(v) for v in x]
jsonable26(x::Tuple) = [jsonable26(v) for v in x]
jsonable26(x::AbstractFloat) = isfinite(x) ? Float64(x) : (isnan(x) ? "NaN" : (x > 0 ? "Inf" : "-Inf"))
jsonable26(x::Symbol) = string(x)
jsonable26(x::NamedTuple) = jsonable26(Dict(pairs(x)))
jsonable26(x) = x

write26(path, d) = (mkpath(dirname(path)); open(io -> JSON.json(io, jsonable26(d); pretty = 1), path, "w"); println("wrote ", path); flush(stdout))

"""The TeamMPC closed loops of one seed: coordinated (fine) and reduced (red), the step-0 checks, the cond replay."""
function run_loops26(seed::Int; side::Int = SIDE26, steps::Int = STEPS26, quiet::Bool = false)
    sc = Scenario26(side; seed = seed)
    x0 = start26(sc)
    la0 = loadavg26()
    res = Dict{String,Any}()
    forms = Dict{String,Form26}()
    for name in (COORD26 ? ("fine", "red") : ("red",))
        GC.gc()
        tb = @elapsed (forms[name] = Form26(sc, name))
        GC.gc()
        out, traj = graph_loop26(sc, forms[name], x0; steps = steps)
        out["build_seconds"] = forms[name].t_build; out["build_total_seconds"] = tb; out["sizes"] = sizes26(forms[name])
        res[name] = summarize_loop26!(out)
        res[name]["traj"] = traj
        quiet || @printf("  %-5s n=%5d cost %.10g  ms/step %9.3f (construct %8.3f setup %7.3f solve %9.3f lift %7.3f)  vars %d rows %d  build %.1fs\n",
                         name, sc.n, out["closed_loop_cost"], ms26(out["t_total_after_first"]["median"]),
                         ms26(out["t_construct_after_first"]["median"]), ms26(out["t_setup_after_first"]["median"]),
                         ms26(out["t_solve_after_first"]["median"]), ms26(out["t_lift_after_first"]["median"]),
                         out["sizes"]["variables"], out["sizes"]["rows"], tb)
        flush(stdout)
    end
    cmp = Dict{String,Any}()
    cmp["teams"] = teaminfo26(sc)
    if COORD26
        tf, tr = res["fine"]["traj"], res["red"]["traj"]
        cmp["cost_ratio"] = res["red"]["closed_loop_cost"] / res["fine"]["closed_loop_cost"]
        cmp["input_diff_max"] = maxdiff26(tf.u, tr.u); cmp["state_diff_max"] = maxdiff26(tf.x, tr.x)
        cmp["plan0_diff"] = maximum(abs, tf.plan0 - tr.plan0)
        cmp["speedup_median"] = res["fine"]["t_total_after_first"]["median"] / res["red"]["t_total_after_first"]["median"]
        GC.gc()
        cmp["step0"] = step0_checks26(sc, forms["fine"], forms["red"])
        quiet || @printf("  cost ratio %.10f  input diff %.1e  state diff %.1e  plan0 diff %.1e  gap/J* %.1e [%.1e, %.1e]  speedup %.1fx\n",
                         cmp["cost_ratio"], cmp["input_diff_max"], cmp["state_diff_max"], cmp["plan0_diff"],
                         get(cmp["step0"], "gap_rel", NaN), get(cmp["step0"], "lower_rel", NaN), get(cmp["step0"], "upper_rel", NaN),
                         cmp["speedup_median"])
    end
    la1 = loadavg26()
    return sc, forms, res, cmp, (la0, la1)
end

"""The teams: their number, whether they are the rows, how many are disconnected in G, the colour refinement time."""
function teaminfo26(sc::Scenario26)
    fl = sc.fleet
    cls = SM.canonical_partition([(sc.kinds[i], sc.lanei[i]) for i in 1:sc.n])
    t = @elapsed (cr = SM.colour_refinement(sc.n, fl.edges, 1.0, cls))
    t = min(t, @elapsed SM.colour_refinement(sc.n, fl.edges, 1.0, cls))
    return Dict{String,Any}("teams" => maximum(sc.team), "are_rows" => SM.canonical_partition(sc.team) == SM.canonical_partition([row26(sc, i) for i in 1:sc.n]),
        "disconnected" => dc_disconnected(sc.n, fl.edges, sc.team), "cr_teams" => maximum(cr), "cr_seconds" => t,
        "almost_equitable" => SM.is_almost_equitable(sc.n, fl.edges, 1.0, sc.team), "classes" => maximum(cls))
end

"""Strip the trajectories from a loop record (they go to the state file)."""
function strip26(res)
    out = Dict{String,Any}()
    for (k, v) in res
        d = copy(v); delete!(d, "traj"); out[k] = d
    end
    return out
end

function run_replays26(sc::Scenario26, forms, trajs; quiet::Bool = false)
    out = Dict{String,Any}()
    for fname in FORMS26
        traj = fname == "red" ? trajs["red"] : get(trajs, "fine", nothing)
        traj === nothing && continue
        for sname in SOLVERS26
            supports26(sname, sc.cone) || continue
            (sname == "teammpc_warm" && fname in ("fine", "red")) && continue      # that is the closed loop itself
            GC.gc()
            F = Form26(sc, fname)
            r = try
                replay26(sc, F, sname, traj)
            catch err
                Dict{String,Any}("solver" => sname, "form" => fname, "error" => sprint(showerror, err)[1:min(end, 400)])
            end
            out["$(fname)/$(sname)"] = r
            if !quiet
                if haskey(r, "error")
                    println("  replay $fname/$sname FAILED: ", r["error"])
                else
                    @printf("  replay %-5s %-14s ms/step %10.3f (solve %10.3f)  |dJ|/J %.1e  unsolved %d  steps %d\n", fname, sname,
                            ms26(r["t_total"]["median"]), ms26(r["t_solve"]["median"]), r["J_rel_diff_absmax"], r["unsolved_steps"],
                            r["replayed_steps"])
                end
                flush(stdout)
            end
            F = nothing
        end
    end
    return out
end

"""
The coordinated closed loop of a seed as data for env/run_hpipm.py
(HPIPM through acados on the same programs): the fleet (airframe, input bound,
formation edges, targets, weights), and per step the measured states, the
references, and the first inputs and objective of TeamMPC's plan.
"""
function export_hpipm26(sc::Scenario26)
    trajs = deserialize(joinpath(STATEDIR26, "e26_states_$(tag26(sc)).jls"))
    tr = trajs["fine"]
    steps = min(REPLAY26, length(tr.J))
    fl = sc.fleet
    d = Dict{String,Any}("n" => sc.n, "H" => sc.H, "h" => sc.h, "cone" => string(sc.cone), "seed" => sc.seed,
        "heavy" => [heavy26(sc, i) for i in 1:sc.n], "umax" => [umax26(sc, i) for i in 1:sc.n],
        "drag" => [sc.params[i].drag for i in 1:sc.n], "r" => [fl.agents[i].R[1, 1] for i in 1:sc.n],
        "kind" => [string(k) for k in sc.kinds], "nx" => [ag.nx for ag in fl.agents], "nu" => [ag.nu for ag in fl.agents],
        "select" => [size(S, 1) for S in fl.select], "fleet" => string(FLEET_DC), "layout" => string(LAYOUT_DC),
        "qf" => [fl.agents[i].Qf[1, 1] for i in 1:sc.n], "qv" => [fl.agents[i].Qf[end, end] for i in 1:sc.n],
        "edges" => [[i, j] for (i, j) in fl.edges], "targets" => [fl.targets[:, k, 1] for k in eachindex(fl.edges)],
        "weights" => [fl.weights[k, 1] for k in eachindex(fl.edges)], "steps" => Any[])
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        push!(d["steps"], Dict{String,Any}("x" => tr.x[k+1], "refs" => [vec(R) for R in refs], "term" => term, "u_loop" => tr.u[k+1],
                                           "J_loop" => tr.J[k+1]))
    end
    write26(joinpath(STATEDIR26, "e26_hpipm_input_$(tag26(sc)).json"), d)
end

"""Compile every code path on a 4 x 4 fleet (discarded)."""
function warmup26()
    for seed in (1,)
        sc = Scenario26(4; seed = seed)
        trajs = Dict{String,Any}()
        for name in ("fine", "cond", "red")
            F = Form26(sc, name)
            _, traj = graph_loop26(sc, F, start26(sc); steps = WARMUP26)
            trajs[name] = traj
        end
        step0_checks26(sc, Form26(sc, "fine"), Form26(sc, "red"))
        for fname in ("fine", "cond", "red"), sname in SOLVERS26
            supports26(sname, sc.cone) || continue
            replay26(sc, Form26(sc, fname), sname, trajs[fname == "red" ? "red" : "fine"]; steps = WARMUP26)
        end
    end
end

function main26()
    MODE26 == "merge" && return merge26()
    BLAS.set_num_threads(1)
    println("E26: side $SIDE26 (n = $(SIDE26^2)), cone $CONE26, regime $REGIME26, seeds $SEEDS26, mode $MODE26, solvers $SOLVERS26, forms $FORMS26")
    println("load ", loadavg26()); flush(stdout)
    if MODE26 != "export"
        t = @elapsed warmup26()
        @printf("warm-up %.1f s\n", t); flush(stdout)
    end
    for seed in SEEDS26
        sc0 = Scenario26(SIDE26; seed = seed)
        if MODE26 in ("all", "loop")
            sc, forms, res, cmp, la = run_loops26(seed)
            trajs = Dict(k => v["traj"] for (k, v) in res)
            mkpath(STATEDIR26)
            serialize(joinpath(STATEDIR26, "e26_states_$(tag26(sc)).jls"), trajs)
            part = Dict{String,Any}("experiment" => "E26-flagship-loops", "side" => SIDE26, "n" => sc.n, "cone" => string(CONE26),
                "regime" => string(REGIME26), "sigma" => sc.sigma, "seed" => seed, "steps" => STEPS26, "H" => sc.H, "h" => sc.h,
                "umax_light" => UMAX_LIGHT26, "umax_heavy" => UMAX_HEAVY26, "merge_tol" => MERGE_TOL26,
                "loops" => strip26(res), "compare" => cmp, "meta" => meta26(), "loadavg" => la)
            write26(joinpath(PARTDIR26, "e26_$(tag26(sc)).json"), part)
            forms = nothing; res = nothing
            if MODE26 == "all" && !isempty(SOLVERS26)
                rep = run_replays26(sc, nothing, trajs)
                write26(joinpath(PARTDIR26, "e26_replay_$(join(SOLVERS26, "+"))_$(tag26(sc)).json"),
                        Dict{String,Any}("experiment" => "E26-flagship-replays", "n" => sc.n, "cone" => string(CONE26),
                                         "regime" => string(REGIME26), "seed" => seed, "replays" => rep, "meta" => meta26(),
                                         "replay_steps" => REPLAY26, "loadavg" => loadavg26()))
            end
        elseif MODE26 == "export"
            export_hpipm26(sc0)
        elseif MODE26 == "replay"
            trajs = deserialize(joinpath(STATEDIR26, "e26_states_$(tag26(sc0)).jls"))
            rep = run_replays26(sc0, nothing, trajs)
            write26(joinpath(PARTDIR26, "e26_replay_$(join(SOLVERS26, "+"))_$(join(FORMS26, "+"))_$(tag26(sc0)).json"),
                    Dict{String,Any}("experiment" => "E26-flagship-replays", "n" => sc0.n, "cone" => string(CONE26),
                                     "regime" => string(REGIME26), "seed" => seed, "replays" => rep, "meta" => meta26(),
                                     "replay_steps" => REPLAY26, "loadavg" => loadavg26()))
        end
    end
end

# ---------------------------------------------------------------------------
# Merge: parts -> results/e26_flagship.json
# ---------------------------------------------------------------------------

const SIZEWORD26 = Dict(16 => "Sixteen", 64 => "SixtyFour", 256 => "TwoFiftySix", 1024 => "OneK", 4096 => "FourK", 16384 => "SixteenK")
const REGWORD26 = Dict("coherent" => "Coh", "incoherent" => "Inc")
const CONEWORD26 = Dict("soc" => "Soc", "box" => "Box")
fnum26(x) = x === nothing ? NaN : x isa AbstractString ? parse(Float64, x) : Float64(x)
getd26(d, ks...) = (for k in ks; (d isa AbstractDict && haskey(d, k)) || return nothing; d = d[k]; end; d)

"""The per-seed record of one loop part and its replays (flat numbers)."""
function seed_record26(p, reps)
    L = p["loops"]; c = get(p, "compare", Dict{String,Any}()); s0 = get(c, "step0", Dict{String,Any}())
    r = Dict{String,Any}("seed" => p["seed"], "host" => p["meta"]["host"], "cpu" => p["meta"]["cpu"], "job" => get(p["meta"], "slurm_job", ""),
                         "teammpc_rev" => p["meta"]["teammpc_rev"])
    for k in ("cost_ratio", "input_diff_max", "state_diff_max", "plan0_diff", "speedup_median")
        haskey(c, k) && (r[k] = c[k])
    end
    for k in ("gap_rel", "lower_rel", "upper_rel", "gap_residual", "chain_vs_one_step", "param_vs_fleetprogram", "J_fine", "J_reduced",
              "J_tight", "active_input_sets_step0", "package_dedup_cones", "plan_diff", "one_step_nnz_X", "chain_nnz_X")
        haskey(s0, k) && (r["step0_"*k] = s0[k])
    end
    haskey(s0, "J_tight") && (r["step0_tight_rel_fine"] = abs(fnum26(s0["J_fine"]) - fnum26(s0["J_tight"])) / abs(fnum26(s0["J_tight"])))
    for (name, x) in L
        for key in ("t_total", "t_construct", "t_setup", "t_solve", "t_lift")
            r["$(name)_$(key)_med"] = fnum26(x[key*"_after_first"]["median"])
            r["$(name)_$(key)_max"] = fnum26(x[key*"_after_first"]["max"])
        end
        r["$(name)_t_first"] = fnum26(x["steps"][1]["t_total"])
        r["$(name)_iter_med"] = fnum26(x["iter"]["median"])
        r["$(name)_cost"] = fnum26(x["closed_loop_cost"])
        r["$(name)_feas"] = max(fnum26(x["feas_hard_max"]), fnum26(x["feas_cone_max"]))
        r["$(name)_unsolved"] = x["unsolved_steps"]; r["$(name)_methods"] = x["methods"]
        r["$(name)_activity_max"] = fnum26(x["activity_max"]); r["$(name)_activity_steps"] = x["activity_steps"]
        r["$(name)_rebuilt"] = x["rebuilt"]; r["$(name)_merge_spread"] = fnum26(x["merge_spread_max"])
        r["$(name)_sizes"] = x["sizes"]; r["$(name)_build"] = x["build_total_seconds"]
        r["$(name)_formation_error"] = fnum26(x["mean_formation_error"])
    end
    R = Dict{String,Any}()
    for (key, x) in reps
        haskey(x, "error") && (R[key] = Dict{String,Any}("error" => x["error"]); continue)
        R[key] = Dict{String,Any}("ms_med" => 1e3 * fnum26(x["t_total_after_first"]["median"]),
            "ms_max" => 1e3 * fnum26(x["t_total_after_first"]["max"]), "solve_ms_med" => 1e3 * fnum26(x["t_solve_after_first"]["median"]),
            "construct_ms_med" => 1e3 * fnum26(x["t_construct_after_first"]["median"]), "setup_ms_med" => 1e3 * fnum26(x["t_setup_after_first"]["median"]),
            "first_ms" => 1e3 * fnum26(x["steps"][1]["t_total"]), "setup_seconds" => fnum26(x["setup_seconds"]),
            "J_rel_diff_absmax" => fnum26(x["J_rel_diff_absmax"]), "unsolved" => x["unsolved_steps"], "steps" => x["replayed_steps"],
            "feas" => max(fnum26(x["feas_hard_max"]), fnum26(x["feas_cone_max"])), "iter_med" => fnum26(x["iter"]["median"]),
            "settings" => x["settings"])
        haskey(x, "t_init") && (R[key]["init_ms_med"] = 1e3 * fnum26(x["t_init"]["median"]))
        haskey(x, "t_reset") && (R[key]["reset_ms_med"] = 1e3 * fnum26(x["t_reset"]["median"]))
    end
    r["replays"] = R
    return r
end

function summarize_config26(recs)
    S = Dict{String,Any}()
    scal = Set{String}()
    for r in recs, (k, v) in r
        v isa Number && k != "seed" && push!(scal, k)
    end
    for k in scal
        v = [fnum26(r[k]) for r in recs if haskey(r, k)]
        S[k] = sumstats26(filter(!isnan, v))
    end
    # the replays: median over seeds of each seed's median, extremes
    keys_ = unique(reduce(vcat, [collect(keys(r["replays"])) for r in recs]; init = String[]))
    RS = Dict{String,Any}()
    for key in keys_
        xs = [r["replays"][key] for r in recs if haskey(r["replays"], key) && !haskey(r["replays"][key], "error")]
        errs = [r["replays"][key]["error"] for r in recs if haskey(r["replays"], key) && haskey(r["replays"][key], "error")]
        d = Dict{String,Any}("seeds" => length(xs), "errors" => errs)
        if !isempty(xs)
            for q in ("ms_med", "solve_ms_med", "construct_ms_med", "setup_ms_med", "first_ms", "setup_seconds", "iter_med", "init_ms_med", "reset_ms_med")
                v = [fnum26(x[q]) for x in xs if haskey(x, q)]
                isempty(v) || (d[q] = sumstats26(v))
            end
            d["ms_max"] = maximum(fnum26(x["ms_max"]) for x in xs)
            d["J_rel_diff_absmax"] = maximum(fnum26(x["J_rel_diff_absmax"]) for x in xs)
            d["unsolved"] = sum(x["unsolved"] for x in xs); d["steps"] = minimum(x["steps"] for x in xs)
            d["feas"] = maximum(fnum26(x["feas"]) for x in xs); d["settings"] = xs[1]["settings"]
        end
        RS[key] = d
    end
    S["replays"] = RS
    # coordinated MPC: every (form, solver) that solved every replayed step to the accuracy of the closed loop
    cands = Dict{String,Float64}()
    haskey(S, "fine_t_total_med") && (cands["fine/teammpc_warm"] = 1e3 * S["fine_t_total_med"]["median"])
    for (key, d) in RS
        (startswith(key, "red/") || !haskey(d, "ms_med")) && continue
        (d["unsolved"] == 0 && d["J_rel_diff_absmax"] <= 1e-5) || continue
        cands[key] = d["ms_med"]["median"]
    end
    S["coordinated_ms"] = cands
    if !isempty(cands)
        best = argmin(k -> cands[k], collect(keys(cands)))
        S["best_coordinated"] = best; S["best_coordinated_ms"] = cands[best]
        haskey(S, "red_t_total_med") && (S["speedup_best"] = cands[best] / (1e3 * S["red_t_total_med"]["median"]))
    end
    haskey(S, "fine_t_total_med") && haskey(S, "red_t_total_med") &&
        (S["speedup_teammpc"] = S["fine_t_total_med"]["median"] / S["red_t_total_med"]["median"])
    return S
end

"""The flat numbers the cnEtwentysix macros read (numbers_flagship.jl)."""
function numbers26(configs)
    N = Dict{String,Any}()
    feas = 0.0; ratio_dev = 0.0; worst_acc = 0.0
    for (_, C) in configs
        tag = REGWORD26[C["regime"]] * "_" * CONEWORD26[C["cone"]] * "_" * SIZEWORD26[C["n"]]
        S = C["summary"]
        N[tag*"_n"] = C["n"]; N[tag*"_seeds"] = length(C["seeds"])
        g(k, f = "median") = haskey(S, k) ? S[k][f] : nothing
        put(name, v) = v === nothing || (v isa Number && isnan(v)) || (N[tag*"_"*name] = v)
        put("ratio_med", g("cost_ratio")); put("ratio_min", g("cost_ratio", "min")); put("ratio_max", g("cost_ratio", "max"))
        haskey(S, "cost_ratio") && put("ratio_dev_max", max(abs(S["cost_ratio"]["max"] - 1), abs(S["cost_ratio"]["min"] - 1)))
        put("input_diff_max", g("input_diff_max", "max")); put("state_diff_max", g("state_diff_max", "max"))
        put("plan_diff_max", g("plan0_diff", "max"))
        put("gap_rel_med", g("step0_gap_rel")); put("gap_rel_max", g("step0_gap_rel", "max"))
        haskey(S, "step0_gap_rel") && put("gap_rel_absmax", max(abs(S["step0_gap_rel"]["max"]), abs(S["step0_gap_rel"]["min"])))
        put("lower_rel_med", g("step0_lower_rel")); put("upper_rel_med", g("step0_upper_rel"))
        put("active_cones_med", g("step0_active_input_sets_step0")); put("active_steps_med", g("fine_activity_steps"))
        put("red_activity_steps_med", g("red_activity_steps"))
        for (L, nm) in (("red", "red"), ("fine", "fine"))
            haskey(S, "$(L)_t_total_med") || continue
            put("$(nm)_ms_med", 1e3 * g("$(L)_t_total_med")); put("$(nm)_ms_max", 1e3 * g("$(L)_t_total_max", "max"))
            put("$(nm)_construct_ms_med", 1e3 * g("$(L)_t_construct_med")); put("$(nm)_setup_ms_med", 1e3 * g("$(L)_t_setup_med"))
            put("$(nm)_solve_ms_med", 1e3 * g("$(L)_t_solve_med")); put("$(nm)_lift_ms_med", 1e3 * g("$(L)_t_lift_med"))
            put("$(nm)_first_ms_med", 1e3 * g("$(L)_t_first")); put("$(nm)_iter_med", g("$(L)_iter_med"))
            put("$(nm)_build_s_med", g("$(L)_build"))
        end
        put("speedup_teammpc", get(S, "speedup_teammpc", nothing)); put("speedup_best", get(S, "speedup_best", nothing))
        put("best_coord_ms", get(S, "best_coordinated_ms", nothing))
        for (key, d) in S["replays"]
            haskey(d, "ms_med") || continue
            k = replace(key, "/" => "_")
            put(k * "_ms_med", d["ms_med"]["median"]); put(k * "_solve_ms_med", d["solve_ms_med"]["median"])
            put(k * "_acc", d["J_rel_diff_absmax"]); put(k * "_unsolved", d["unsolved"])
            worst_acc = max(worst_acc, d["J_rel_diff_absmax"]); feas = max(feas, d["feas"])
        end
        for nm in ("fine", "red")
            haskey(S, "$(nm)_feas") && (feas = max(feas, S["$(nm)_feas"]["max"]))
        end
        if C["regime"] == "coherent" && haskey(S, "cost_ratio")
            ratio_dev = max(ratio_dev, abs(S["cost_ratio"]["max"] - 1), abs(S["cost_ratio"]["min"] - 1))
        end
        r1 = C["per_seed"][1]
        haskey(r1, "red_sizes") && (put("red_vars", r1["red_sizes"]["variables"]); put("red_cones", r1["red_sizes"]["cones"]);
                                   put("red_cones_full", r1["red_sizes"]["cones_full"]); put("red_levels", r1["red_sizes"]["levels"]))
        haskey(r1, "fine_sizes") && (put("fine_vars", r1["fine_sizes"]["variables"]); put("fine_rows", r1["fine_sizes"]["rows"]))
    end
    N["feas_max"] = feas; N["coherent_ratio_dev_max"] = ratio_dev; N["replay_acc_max"] = worst_acc
    N["steps"] = STEPS26; N["H"] = H26; N["merge_tol"] = MERGE_TOL26; N["umax_heavy"] = UMAX_HEAVY26; N["umax_light"] = UMAX_LIGHT26
    return N
end

function merge26()
    files = sort(filter(f -> startswith(f, "e26_") && endswith(f, ".json"), readdir(PARTDIR26)))
    loops = [f for f in files if !startswith(f, "e26_replay_")]
    isempty(loops) && error("no parts in $PARTDIR26")
    configs = Dict{String,Any}()
    metas = Any[]
    for f in loops
        p = JSON.parsefile(joinpath(PARTDIR26, f))
        tag = "$(p["regime"])_$(p["cone"])_n$(p["n"])_seed$(p["seed"])"
        reps = Dict{String,Any}()
        for g in files
            (startswith(g, "e26_replay_") && endswith(g, "_" * tag * ".json")) || continue
            q = JSON.parsefile(joinpath(PARTDIR26, g))
            for (k, v) in q["replays"]
                haskey(reps, k) && error("two replays of $k for $tag")
                reps[k] = v
            end
            push!(metas, q["meta"])
        end
        key = "$(p["regime"])_$(p["cone"])_n$(p["n"])"
        C = get!(configs, key, Dict{String,Any}("regime" => p["regime"], "cone" => p["cone"], "n" => p["n"], "side" => p["side"],
                                               "sigma" => p["sigma"], "steps" => p["steps"], "per_seed" => Any[], "parts" => String[]))
        push!(C["per_seed"], seed_record26(p, reps)); push!(C["parts"], f)
        push!(metas, p["meta"])
    end
    for (_, C) in configs
        sort!(C["per_seed"]; by = r -> r["seed"])
        C["seeds"] = [r["seed"] for r in C["per_seed"]]
        allunique(C["seeds"]) || error("duplicate seeds")
        C["summary"] = summarize_config26(C["per_seed"])
    end
    out = Dict{String,Any}("experiment" => "E26-flagship", "configs" => configs, "numbers" => numbers26(configs),
        "teammpc_revs" => unique([m["teammpc_rev"] for m in metas]), "hosts" => unique([m["host"] for m in metas]),
        "cpus" => unique([m["cpu"] for m in metas]), "jobs" => unique([get(m, "slurm_job", "") for m in metas]),
        "julia" => unique([m["julia"] for m in metas]), "threads" => unique([m["threads"] for m in metas]),
        "blas_threads" => unique([m["blas_threads"] for m in metas]), "steps" => STEPS26, "H" => H26, "h" => DT26,
        "merge_tol" => MERGE_TOL26, "umax_light" => UMAX_LIGHT26, "umax_heavy" => UMAX_HEAVY26)
    length(out["teammpc_revs"]) == 1 || @warn "parts were timed against several TeamMPC commits: $(out["teammpc_revs"])"
    path = get(ENV, "BENCH_OUT", joinpath(ROOT26, "results", "e26_flagship.json"))
    write26(path, out)
    return out
end

if abspath(PROGRAM_FILE) == @__FILE__
    BLAS.set_num_threads(1)
    main26()
end
