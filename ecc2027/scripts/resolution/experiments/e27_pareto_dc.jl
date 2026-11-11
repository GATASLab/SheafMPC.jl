# Provenance: e27_pareto.jl blob 0717982 (main@4ed57a7), the version in every November HPG tree. Unchanged except this header.
# The October versions under the plain names are the ones the E26-E42 ZOH campaign ran with.
# E27-pareto: where do reduced team programs sit among the multi-agent MPC
# schemes one would run at scale? E26's fleet (an s x s grid of quadrotors
# flying in lanes) is driven in closed loop by coordinated MPC of the whole
# fleet, by the reduced controller of rows (centralized, and as a mixed
# resolution that forms the rows only from instant t0 on), by decentralized MPC
# and by consensus-ADMM distributed MPC over vehicles and over rows, while the
# data move from coherent (rows exact) to incoherent (every vehicle's reference
# wanders off its lane). Recorded for every method: closed-loop cost relative to
# coordinated MPC, sequential and parallel computation per step, and
# communication per step, so that the cost / computation / communication front
# can be read at every level of incoherence.
#
#   BENCH_SIDE=32 BENCH_MODE=tune julia --project=env scripts/resolution/experiments/e27_pareto.jl
#           (rho of distributed MPC over vehicles and over rows: <partdir>/e27_rho_n<n>.json)
#   BENCH_SIDE=32 BENCH_SIGMAS=0.1 BENCH_SEEDS=1,2 BENCH_KICK=0 \
#       julia --project=env scripts/resolution/experiments/e27_pareto.jl
#           (one part per seed: <partdir>/e27_run_n<n>_sig<sigma>_kick<kick>_seed<s>.json)
#   BENCH_MODE=merge julia --project=env scripts/resolution/experiments/e27_pareto.jl
#           (parts -> results/e27_pareto.json; BENCH_PARTDIR, BENCH_OUT=<path> for a canary)
#   julia --project=env scripts/resolution/experiments/e27_summary.jl
#           (the tables, and the data of figures/fig_pareto.tex)
#
# The environment is env's (TeamMPC.jl as a sibling checkout of this
# repository, JSON); the baseline solvers it also holds are not loaded.
#
# The fleet is E26's (e26_flagship.jl, whose parts are copied here, not
# included): quadrotors as 3D double integrators, rows alternating a light
# (||a|| <= 4, no drag) and a heavy airframe (||a|| <= 0.5, linear drag 0.4),
# input balls, springs of weight 1 on every grid edge on the 3D position, H =
# 10, h = 0.2, 30 closed-loop steps; each row a lane with its own manoeuvre;
# the start is every vehicle on its slot plus one rigid perturbation of the
# fleet. Seed s draws exactly E26's lanes, wanders and start perturbation, so
# sigma = 0 is E26's coherent instance of that seed.
#
# Regimes. BENCH_SIGMAS: every vehicle's reference wanders off its lane by
# E26's incoherent wander scaled by sigma (sigma = 0: coherent, rows exact by
# Thm. thm:equitable; the larger sigma, the less coherent the rows).
# BENCH_KICK > 0 adds process noise: after every step every vehicle's velocity
# receives an independent N(0, kick^2 I_3) kick (E21's disturbance, in 3D), the
# same sequence for every method and sigma of a seed. A team program hardens
# the formation inside every row from the next instant on, so a kick that the
# input balls cannot absorb in one step makes it infeasible; the mixed
# resolution gives the row t0 instants to regroup.
#
# Methods (one closed loop each; the plant runs each method's own first input,
# radially clipped into its ball):
#   fine        coordinated MPC of the whole fleet (E26's time-expanded program,
#               the measured state as data; TeamMPC, warm started from the
#               previous primal-dual solution shifted one instant); the cost
#               reference
#   rows        the reduced controller of rows, centralized: E26's chain of
#               reductions (full condensing, then adjacent blocks of a row
#               merged level by level up to whole rows)
#   rows_abs    rows with E21's absorb: the targets of the formation edges
#               inside every row re-based each step on the measured state,
#               b = C A^t (xhat_j - xhat_i), so equal inputs inside a row are
#               always feasible (the members' offsets are carried as their free
#               response and never corrected by the row); the closed-loop cost
#               is measured on the true targets
#   rows_proj   rows deployed with a local tracking layer: every row's measured
#               states projected onto its agreement subspace (always feasible),
#               the rows' plan from the projected states, and each vehicle's
#               lifted first input plus a discrete-LQR feedback on its own
#               deviation from its projected state, projected onto its input
#               ball (RowsProj27)
#   mix_t<t0>   the mixed resolution: every vehicle alone (condensed) before
#               instant t0, its row from t0 on; the same chain, the early blocks
#               never merged. The hard dynamics edge from instant t0 - 1 to t0
#               of every vehicle stays a hard edge between its early block and
#               its row's block
#   dec_cv, dec_ref
#               E25's fair decentralized MPC on this fleet: each vehicle
#               minimizes its own cost plus every incident spring at full
#               weight over its own inputs, with its neighbours predicted at
#               constant velocity from their measured states (_cv) or on their
#               references (_ref). The neighbours' states are taken as sensed
#               (no messages), as in E25
#   dmpc_b<b>   consensus-ADMM distributed MPC over vehicles (the package's
#               DistributedMPC: each vehicle's condensed program, one exchange
#               with every neighbour per iteration), b iterations per step
#   dmpcrows_b<b>
#               the same over the rows (DistributedMPC on Teams(rows) x !:
#               each row is one agent solving its row's reduced program; the
#               members send their states to their row's computer and receive
#               their inputs, two more rounds per step)
#   twolevel_b<b>
#               two levels (a coarse-grid correction): each step the rows'
#               reduced program is solved centrally (as rows), its plan lifted
#               to the fleet and used as the warm start of distributed MPC over
#               vehicles (the consensus targets from the lifted plan, the scaled
#               duals shifted one instant), which then runs b iterations with
#               the same rho, local QPs and settings as dmpc_b<b>. Sequential:
#               rows' step + the warm start + DMPC's step; parallel: rows' step
#               (central) + the warm start and DMPC's per-agent work over n +
#               the slowest local solve per iteration; rounds: 2 (states to the
#               computer, the consensus targets back) + b; floats: 6 n states,
#               the targets of every interface to both ends, DMPC's exchanges.
#               DistributedMPC has no call that takes a warm-start plan, so it
#               runs with warm = :previous and its targets and duals are set by
#               this script before every step (its data are written once more
#               there, a small overcount charged to this method)
#   twolevel_mu_b<b>, twolevel_abs_mu_b<b>
#               the same with the scaled duals mapped from the coarse solve
#               (coarse_duals27!): the forces the coarse plan implies on every
#               interface, the hardened edges' from the coarse multipliers
#               recovered by TeamMPC's Certifier; at a coarse plan optimal for
#               the fleet the warm start is a fixed point of consensus ADMM (the
#               plan does not move). The certificate is central time, the duals
#               go with the targets (twice the targets' floats). With b = 1 the
#               applied plan is the coarse plan itself (the local solves do not
#               move at the first iteration; only z does)
#   twolevel_abs_b<b>
#               the same with rows_abs as the coarse level: always feasible, it
#               moves every row as one body and leaves the shape of every row to
#               distributed MPC
#   twolevel_mix_t<t0>_b<b>
#               the same with the mixed resolution (rows from instant t0) as
#               the coarse level: the applied inputs are distributed MPC's, so
#               the rows leave exact formation and the rows' own program, which
#               restores it at the next instant, is infeasible at most steps
#               (then the targets come from DistributedMPC's previous plan
#               shifted, as for plain DMPC); the mixed program leaves t0
#               instants to regroup
# The gap-kernel team selector of E25 is not run: its kernel is a dense matrix
# over the soft rows (edges x 3 x H = 59520 at 1024 vehicles, 28 GB).
#
# Solvers and warm starts. Every program is solved by TeamMPC's solver with
# MPCController's accuracy (eps_abs = eps_rel = 1e-6, max_iter = 20000): the
# centralized programs, every vehicle's program of decentralized MPC, and every
# local QP of distributed MPC (DistributedMPC's own default for its local QPs,
# 1e-9, is overridden after construction). Each step starts from the previous
# plan shifted one instant: the time-expanded program as MPCController does
# (primal and dual, warm_start_shifted!); every reduced program of a chain from
# the previous reduced solution as it is (BENCH_RED_WARM=previous, E26's rule;
# with BENCH_RED_WARM=shift, E27's first run, from the previous fine plan
# shifted one instant and restricted level by level to the current reduced
# coordinates, its duals as they were); every vehicle's condensed program of
# decentralized MPC from its previous plan shifted one instant and restricted;
# distributed MPC by its own shifted warm start (consensus targets from
# the shifted plan, scaled duals shifted one instant). Distributed MPC's rho is
# tuned once per fleet size, as in E25: iterations to Boyd's tolerances from a
# cold start at step 0 of seed 1, sigma 0.1 (BENCH_MODE=tune; at most
# BENCH_TUNE_MAXIT = 300 iterations, a rho that needs more is not chosen), for
# vehicles and for rows apart. The local QP of a row keeps every member's input
# cones (DistributedMPC does not merge duplicate rows), so it is slower per
# iteration than its size suggests.
#
# The reduced controller's construction path (BENCH_RED_PATH). `stepop` (the
# default, E26's path at TeamMPC 0fae551): the step's data are written into the
# fine program and SM.StepOperator, composed once offline from the chain of
# rows (`stepop` in the build times), maps the changing entries (tracking costs
# and the dynamics targets from the measured state) to the reduced QP's vectors
# in one sparse product; the merged copies of a row's input cones are chained
# to their kept row and applied to the data's departure from row coherence,
# with an error bound that certifies the merge check (else the copies are
# computed level by level, counted as `stepop_fallbacks`); the applied inputs
# u_{i,0} are lifted by the operator's precomposed product. The fine plan (for
# the fallback of an infeasible step, the residual checks and the comparison
# with the level by level path, `stepop_diff` and `stepop_input_diff`) is
# lifted outside the timed step after SM.sync!, as in E26's plan26!. `chain`
# (E27's first run, TeamMPC ce71be2): TeamMPC's update! on every level of the
# chain and the full lift every step. The step operator is used for the form
# `rows` (rows, rows_fbdec, rows_proj); the other forms (mix_t<t0>, rows_abs and
# the coarse level of the two-level controllers) keep the chain. The warm start
# of a reduced program (BENCH_RED_WARM): `previous` (the default, E26's rule)
# or `shift` (E27's first run; chain only). A run records both.
#
# Excluded runs. A method-run in which TeamMPC (ce71be2) reported a local QP of
# DistributedMPC dual infeasible (impossible: the local QPs are strictly convex;
# the warm-started ADMM-to-IPM crossover, the same QP solves cold) is left out of
# the summaries and listed in results (`excluded`); it is deterministic, so a
# rerun reproduces it. It occurred only in twolevel_mu_b5 (three runs).
#
# Infeasible steps. A program that is infeasible at a step (an empty fiber, or
# the solver's status primal or dual infeasible) is counted, and every vehicle
# it controls applies its previous plan shifted one step (E25's fallback). A
# method name with the suffix _fbdec (rows_fbdec, mix_t2_fbdec, ...) falls back
# instead to decentralized MPC for that step (dec_cv, built with the method,
# its sequential and parallel time added to the step's): under process noise
# E25's fallback never brings a row back into exact formation, so one
# infeasible step makes every later one infeasible. Steps not solved to
# tolerance are counted apart (their plan is applied).
#
# Recorded per method and seed: closed-loop cost (E19's accounting: the stage
# cost of the applied inputs, formation included) and its ratio to coordinated
# MPC on the same seed; the largest difference of its applied inputs from
# coordinated MPC's (over steps and vehicles; also over the smaller input bound,
# 0.5); mean formation error; the largest input-ball violation
# before the clip; the largest residual of a lifted plan in its program (hard
# edges, node cones); infeasible, fallback and unconverged steps; per step the
# time split into construction (data into the programs, the step operator's
# product or the reduction update of every level, the QP vectors and the
# merge), setup (the data into the solver and the warm start; at the first
# step the solver's setup), solve and lift (the applied inputs), E26's
# boundary, and:
#   sequential  all the work of the step on one core (every agent's solves
#               summed): construction + setup + solve + lift
#   parallel    centralized methods: the sequential time (one computer).
#               Decentralized MPC: the slowest vehicle's own time (its data,
#               setup, solve and lift). Distributed MPC: per iteration the
#               slowest agent's local solve, summed over the iterations, plus
#               the rest of the step (every agent's data update and warm start,
#               the consensus updates, the lift) divided evenly over the agents,
#               since each agent does its own share. No central step.
#               Communication latency is not included in either
#   rounds      message exchanges per step: centralized 2 (states to the
#               computer, inputs back); decentralized 0; distributed MPC one per
#               iteration (over rows two more, inside every row)
#   floats      floats sent per step: centralized 9 n (6 states up, 3 inputs
#               down); distributed MPC its interfaces both ways per iteration
#               (over rows plus 9 n inside the rows)
# Medians over steps exclude the first (setup, factorizations, cold start);
# the first step is recorded apart. Offline construction (programs, fibers,
# local QPs) is recorded per method. At step 0 for rows: the gap of the
# reduction from the package's gap_bounds (lower bound from the fine optimum,
# Thm. thm:price; the true gap; the certified upper bound), over J*.
#
# Timing hygiene: one Julia thread, one BLAS thread, the process pinned by the
# caller (taskset -c on the job's first core); every method first runs
# BENCH_WARMUP_STEPS steps on a 4 x 4 fleet (discarded) to compile; all timing
# inside functions (time_ns); garbage collected before every closed loop; the
# load averages logged; the TeamMPC commit recorded in every part.

using LinearAlgebra, SparseArrays, Printf, Random, Statistics, Serialization
import JSON
import TeamMPC
const SM = TeamMPC

const SIDE27 = parse(Int, get(ENV, "BENCH_SIDE", "8"))
const H27 = 10
const DT27 = 0.2
const STEPS27 = parse(Int, get(ENV, "BENCH_STEPS", "30"))
const SIGMAS27 = parse.(Float64, split(get(ENV, "BENCH_SIGMAS", "0.1"), ","))
const SEEDS27 = parse.(Int, split(get(ENV, "BENCH_SEEDS", "1"), ","))
const KICK27 = parse(Float64, get(ENV, "BENCH_KICK", "0"))
const METHODS27 = filter(!isempty, split(get(ENV, "BENCH_METHODS",
    "fine,rows,rows_abs,mix_t2,dec_cv,dec_ref,dmpc_b1,dmpc_b5,dmpc_b20,dmpcrows_b1,dmpcrows_b5,twolevel_b1,twolevel_b5,twolevel_abs_b1,twolevel_abs_b5"), ","))
const MODE27 = get(ENV, "BENCH_MODE", "run")                 # run, tune, merge
const RED_PATH27 = get(ENV, "BENCH_RED_PATH", "stepop")      # stepop (E26's path) or chain (level by level)
const RED_WARM27 = get(ENV, "BENCH_RED_WARM", "previous")    # previous (E26's rule) or shift (chain only)
RED_PATH27 in ("stepop", "chain") || error("unknown BENCH_RED_PATH $(RED_PATH27)")
RED_WARM27 in ("previous", "shift") || error("unknown BENCH_RED_WARM $(RED_WARM27)")
(RED_PATH27 == "stepop" && RED_WARM27 == "shift") && error("BENCH_RED_WARM=shift needs the fine plan every step: BENCH_RED_PATH=chain")
const LINKTOL27 = 1e-9                                        # the merged copies' links: dropped mass (times their departure), E26's
const WARMUP27 = parse(Int, get(ENV, "BENCH_WARMUP_STEPS", "3"))
const GAP27 = get(ENV, "BENCH_GAP", "1") == "1"
const RHOS27 = [0.3, 1.0, 3.0, 10.0, 30.0]
const TUNE_SIGMA27 = 0.1
const TUNE_MAXIT27 = parse(Int, get(ENV, "BENCH_TUNE_MAXIT", "300"))
const UMAX_LIGHT27 = 4.0
const UMAX_HEAVY27 = 0.5
const MERGE_TOL27 = 1e-9
const KICK_SEED27 = 4_242_421
const FRONT_TOL27 = 1e-4                                       # cost ratios within this are ties on the fronts
const ROOT27 = normpath(joinpath(@__DIR__, "..", "..", ".."))
const REPRO_DIR27 = get(ENV, "BENCH_REPRO_DIR", "")          # diagnostics: save DistributedMPC before a step that ends dual infeasible
const PARTTAG27 = get(ENV, "BENCH_PARTTAG", "")             # suffix of the part files (a later run of more methods on the same seeds)
const PARTDIR27 = get(ENV, "BENCH_PARTDIR", joinpath(ROOT27, "bench", "pareto", "results", "parts"))
const SM_SETTINGS27 = (eps_abs = 1e-6, eps_rel = 1e-6, max_iter = 20_000)     # MPCController's defaults

loadavg27() = (s = try read("/proc/loadavg", String) catch; "" end; isempty(s) ? Float64[] : parse.(Float64, split(s)[1:3]))
sec27(t1, t0) = (t1 - t0) / 1e9

function settings27()
    st = SM.Settings()
    for (k, v) in pairs(SM_SETTINGS27)
        setproperty!(st, k, v)
    end
    return st
end

# ---------------------------------------------------------------------------
# The fleet (E26's, with the wander scaled by sigma and the velocity kicks)
# ---------------------------------------------------------------------------

struct Scenario27
    side::Int
    n::Int
    H::Int
    h::Float64
    sigma::Float64
    kick::Float64
    seed::Int
    fleet::SM.Fleet
    slots::Vector{Vector{Float64}}
    lane::Vector{NamedTuple}
    wander::Vector{NamedTuple}
    dp::Vector{Float64}
    dv::Vector{Float64}
    noise::Vector{Vector{Vector{Float64}}}      # noise[k+1][i]: the kick on vehicle i's velocity after step k
    kinds::Vector{Symbol}
    lanei::Vector{Int}                          # the lane of every vehicle: its row (quad) or its type (dronecar)
end

include(joinpath(@__DIR__, "fleet_dc.jl"))

"""The lane index of every vehicle: its row for the quad fleet, its type for the drone/car fleet."""
lanes_of27(side, kinds) = FLEET_DC == :quad ? [div(i - 1, side) + 1 for i in eachindex(kinds)] : [k == :drone ? 1 : 2 for k in kinds]

Scenario27(side, n, H, h, sigma, kick, seed, fl::SM.Fleet, slots, lane, wander, dp, dv, noise) =
    Scenario27(side, n, H, h, sigma, kick, seed, fl, slots, lane, wander, dp, dv, noise, [ag.kind for ag in fl.agents],
               lanes_of27(side, [ag.kind for ag in fl.agents]))

"""The agents of the fleet: E26's quadrotors (heavy rows by `heavyof`), or drones and cars in the layout."""
function agents27(side, h, seed, layout::Symbol; heavyof = i -> iseven(div(i - 1, side) + 1))
    n = side^2
    if FLEET_DC == :quad
        return [heavyof(i) ? airframe27(h, UMAX_HEAVY27, 0.4, 0.2) : airframe27(h, UMAX_LIGHT27, 0.0, 0.1) for i in 1:n]
    end
    kinds = [kind_dc(i, side, layout) for i in 1:n]
    return dc_agents(kinds, h, :soc, seed)[1]
end

"""The fleet over `edges` with E27's weights; drone/car edges compare the coordinates of `dc_select`."""
fleet27(ags, edges, H, slots, wts) = FLEET_DC == :quad ? SM.Fleet(ags, edges; H = H, offsets = slots, weights = wts) :
    SM.Fleet(ags, edges; H = H, offsets = slots, weights = wts, select = dc_select(edges, [ag.kind for ag in ags]))

"""The lanes: one per row (quad) or one per type (dronecar)."""
lanes27(seed, side) = FLEET_DC == :quad ?
    (rng = Xoshiro(seed); [(speed = 0.8 + 0.4 * rand(rng), amp = 0.1 + 0.3 * rand(rng), om = 0.5 + rand(rng), ph = 2pi * rand(rng),
                            alt = 1.5 + 0.4 * (rand(rng) - 0.5)) for _ in 1:side]) : dc_lanes(seed)

ny27(ag::SM.Agent) = size(ag.Cr, 1)
nfloats27(sc) = sum(ag.nx + ag.nu for ag in sc.fleet.agents)      # a state up and an input down per vehicle
pdim27(ag::SM.Agent) = div(ag.nx, 2)            # position (and velocity) dimension of a double integrator

row27(sc, i) = div(i - 1, sc.side) + 1
col27(sc, i) = rem(i - 1, sc.side) + 1
heavy27(sc, i) = iseven(row27(sc, i))

"""The discretization of a 3D double integrator with linear drag `d` (p' = v, v' = -d v + u) at step `h`:
the exact zero-order hold (default), or with `BENCH_DISC=euler` the zero-order hold of the drag-free model
with drag applied by an explicit Euler step, as before Oct 27. Returns (A, B) for the state (p, v)."""
function dyn27(h, d)
    I3 = Matrix{Float64}(I, 3, 3)
    if get(ENV, "BENCH_DISC", "zoh") == "euler" || d == 0
        a, phi, bp, bv = 1 - d * h, h, 0.5h^2, h
    else
        a = exp(-d * h); phi = (1 - a) / d; bp = (h - phi) / d; bv = phi
    end
    return [I3 phi*I3; zeros(3, 3) a*I3], [bp*I3; bv*I3]
end

"""A quadrotor as a 3D double integrator with linear drag `drag`, formation and tracked output the position (E26's airframe26, input ball)."""
function airframe27(h, umax, drag, r)
    I3 = Matrix{Float64}(I, 3, 3)
    A, B = dyn27(h, drag)
    C = [I3 zeros(3, 3)]
    return SM.Agent(A, B; C = C, Cr = C, Q = Matrix(1.0I, 3, 3), R = r * I3, Cf = Matrix(1.0I, 6, 6),
                    Qf = Matrix(Diagonal([5.0, 5, 5, 1, 1, 1])), input = SM.BallSet(umax), kind = drag > 0 ? :heavy : :light)
end

function Scenario27(side::Int; seed::Int, sigma::Float64, kick::Float64 = KICK27, steps::Int = STEPS27, H::Int = H27, h::Float64 = DT27)
    n = side^2
    edges, sl = SM.grid_graph(side, side)
    slots = [[s; 0.0] for s in sl]
    ags = agents27(side, h, seed, :rows)
    # BENCH_AEP_EPS = eps > 0: the edges between rows get the weight 1 + eps cos(2 pi c / side) at column c, so the
    # rows stay coherent teams but are no longer almost equitable (eps = 0: unit weights, as before)
    # BENCH_AEP_DROP = p > 0: each edge between rows is lost (weight 0) with probability p, drawn from the seed
    epsA = parse(Float64, get(ENV, "BENCH_AEP_EPS", "0"))
    dropA = parse(Float64, get(ENV, "BENCH_AEP_DROP", "0"))
    rngA = Xoshiro(27_500_000 + seed)
    between(i, j) = div(i - 1, side) != div(j - 1, side)
    wts = (epsA == 0 && dropA == 0) ? 1.0 :
          repeat([!between(i, j) ? 1.0 : (rand(rngA) < dropA ? 0.0 : 1.0 + epsA * cos(2pi * rem(i - 1, side) / side))
                  for (i, j) in edges], 1, H)
    # BENCH_MIRROR_EDGES = 1: add an edge of weight BENCH_MIRROR_W (1e-6) between the vehicles mirrored in each row,
    # (r, c) and (r, side + 1 - c), unless they are neighbours, so that the mirror pairs (the orbits of the fleet's
    # symmetries relative to the slots) are connected teams. The edges lie inside a row and inside a mirror pair, so
    # neither partition's almost equitability changes; the weight is positive because the certificate inverts it
    if get(ENV, "BENCH_MIRROR_EDGES", "0") == "1"
        W0 = wts isa Real ? fill(Float64(wts), length(edges), H) : wts
        extra = [((r - 1) * side + c, (r - 1) * side + side + 1 - c) for r in 1:side for c in 1:div(side, 2) if side + 1 - c != c + 1]
        edges = vcat(edges, extra)
        wts = vcat(W0, fill(parse(Float64, get(ENV, "BENCH_MIRROR_W", "1e-6")), length(extra), H))
    end
    fl = fleet27(ags, edges, H, slots, wts)
    lane = lanes27(seed, side)
    rngw = Xoshiro(1_000_003 * seed + 17)
    wander = [(amp = 0.5 + rand(rngw), om = 0.5 + rand(rngw), ph = 2pi * rand(rngw), omz = 0.5 + rand(rngw), phz = 2pi * rand(rngw))
              for _ in 1:n]
    rngs = Xoshiro(7919 * seed)
    dp = 0.3 * randn(rngs, 2); dv = 0.15 * randn(rngs, 2)
    rngk = Xoshiro(KICK_SEED27 + seed)
    noise = [[kick * randn(rngk, 3) for _ in 1:n] for _ in 1:steps]
    return Scenario27(side, n, H, h, sigma, kick, seed, fl, slots, lane, wander, dp, dv, noise)
end

"""Reference position and velocity of vehicle `i` at world time `tau`: its lane's manoeuvre, plus its wander scaled by sigma."""
function reference27(sc::Scenario27, i::Int, tau::Real)
    q = sc.lane[sc.lanei[i]]
    p = [q.speed * tau, q.amp * (sin(q.om * tau + q.ph) - sin(q.ph)), q.alt] + sc.slots[i]
    v = [q.speed, q.amp * q.om * cos(q.om * tau + q.ph), 0.0]
    if sc.sigma > 0
        w = sc.wander[i]; s = sc.sigma * w.amp
        p += s * [sin(w.om * tau + w.ph) - sin(w.ph), cos(w.om * tau + w.ph) - cos(w.ph), sin(w.omz * tau + w.phz) - sin(w.phz)]
        v += s * [w.om * cos(w.om * tau + w.ph), -w.om * sin(w.om * tau + w.ph), w.omz * cos(w.omz * tau + w.phz)]
    end
    d = ny27(sc.fleet.agents[i])
    return p[1:d], v[1:d]
end

"""The references of the step at world time `t0`: `refs[i]` (3 x (H+1) positions) and `term[i]` (terminal position and velocity)."""
function references27(sc::Scenario27, t0::Real)
    refs = Vector{Matrix{Float64}}(undef, sc.n); term = Vector{Vector{Float64}}(undef, sc.n)
    for i in 1:sc.n
        R = zeros(ny27(sc.fleet.agents[i]), sc.H + 1)
        for t in 0:sc.H
            R[:, t+1] = reference27(sc, i, t0 + sc.h * t)[1]
        end
        refs[i] = R
        term[i] = [R[:, end]; reference27(sc, i, t0 + sc.h * sc.H)[2]]
    end
    return refs, term
end

start27(sc::Scenario27) = [sc.fleet.agents[i].nx == 6 ? [sc.slots[i] + [sc.dp; 1.5]; [1.0, 0.15] + sc.dv; 0.0] :
                           [sc.slots[i][1:2] + sc.dp; [1.0, 0.15] + sc.dv] for i in 1:sc.n]

function stage_cost27(sc::Scenario27, x, u, refs)
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

formation_error27(sc, x) = sqrt(sum(norm(SM.edge_residual(sc.fleet, k, x[i], x[j], 1))^2
                                    for (k, (i, j)) in enumerate(sc.fleet.edges)) / length(sc.fleet.edges))

"""Clip every input radially into its ball; the clipped inputs and the largest violation before."""
function clip27(sc::Scenario27, u)
    viol = 0.0; out = similar(u)
    for (i, ag) in enumerate(sc.fleet.agents)
        r = ag.input.radius; nu = norm(u[i])
        viol = max(viol, nu - r)
        out[i] = nu > r ? u[i] * (r / nu) : copy(u[i])
    end
    return out, viol
end

"""The plant: the nominal dynamics, then the step's velocity kicks (none when kick = 0)."""
function plant27(sc::Scenario27, x, u, k::Int)
    xn = [ag.A[1] * x[i] + ag.B[1] * u[i] + ag.g[1] for (i, ag) in enumerate(sc.fleet.agents)]
    if sc.kick > 0
        for i in eachindex(xn)
            d = pdim27(sc.fleet.agents[i])
            xn[i][(d+1):(2d)] .+= sc.noise[k+1][i][1:d]
        end
    end
    return xn
end

# ---------------------------------------------------------------------------
# The parametric program (E26's ParamProgram26: the measured state as data)
# ---------------------------------------------------------------------------

function _input_rows27(ag::SM.Agent, d::Int, off::Int)
    nu = ag.nu
    A = zeros(1 + nu, d); A[2:end, (off+1):(off+nu)] .= -Matrix(1.0I, nu, nu)
    return A, [ag.input.radius; zeros(nu)], [SM.soc_cone(1 + nu)]
end

struct ParamProgram27
    P::SM.GraphProgram
    vid::Matrix{Int}
    dyn::Matrix{Int}
    CrQ::Vector{Matrix{Float64}}
    CfQf::Vector{Matrix{Float64}}
end

function ParamProgram27(sc::Scenario27)
    fl = sc.fleet; n, H = sc.n, sc.H
    vid = zeros(Int, n, H + 1)
    nodes = SM.NodeData[]
    for i in 1:n, t in 0:H
        ag = fl.agents[i]; nx, nu = ag.nx, ag.nu
        if t == 0
            A, b, cones = _input_rows27(ag, nu, 0)
            push!(nodes, SM.NodeData(ag.R, zeros(nu), 0.0, A, b, cones))
        elseif t < H
            d = nx + nu
            Q = zeros(d, d); Q[1:nx, 1:nx] .= ag.Cr' * ag.Q * ag.Cr; Q[(nx+1):d, (nx+1):d] .= ag.R
            A, b, cones = _input_rows27(ag, d, nx)
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
    return ParamProgram27(SM.GraphProgram(nodes, edges), vid, dyn, [ag.Cr' * ag.Q for ag in fl.agents],
                          [ag.Cf' * ag.Qf for ag in fl.agents])
end

"""Write the step's measured states and references into the program in place (E26's set_data26!)."""
function set_data27!(pp::ParamProgram27, sc::Scenario27, x, refs, term)
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

"""Every agent's planned inputs (3 x H) in a plan `x` of the parametric program."""
function inputs27(pp::ParamProgram27, sc::Scenario27, x)
    P = pp.P; H = sc.H
    ags = sc.fleet.agents
    U = [zeros(ags[i].nu, H) for i in 1:sc.n]
    for i in 1:sc.n
        nx, nu = ags[i].nx, ags[i].nu
        U[i][:, 1] = x[SM.vrange(P, pp.vid[i, 1])]
        for t in 1:(H-1)
            U[i][:, t+1] = x[SM.vrange(P, pp.vid[i, t+1])[(nx+1):(nx+nu)]]
        end
    end
    return U
end

first_inputs27(pp::ParamProgram27, x) = [x[SM.vrange(pp.P, pp.vid[i, 1])] for i in axes(pp.vid, 1)]

"""The shift of a plan of the parametric program by one instant: x_t <- x_{t+1}, u_t <- u_{t+1}, the last instants keep their own."""
function fine_xmap27(pp::ParamProgram27, sc::Scenario27)
    P = pp.P; H = sc.H
    xmap = collect(1:SM.c0dim(P))
    for i in 1:sc.n
        nx, nu = sc.fleet.agents[i].nx, sc.fleet.agents[i].nu
        o0 = P.offsets[pp.vid[i, 1]]; o1 = P.offsets[pp.vid[i, 2]]
        xmap[o0 .+ (1:nu)] = o1 .+ ((nx+1):(nx+nu))
        for t in 1:(H-1)
            ot = P.offsets[pp.vid[i, t+1]]; on = P.offsets[pp.vid[i, t+2]]
            xmap[ot .+ (1:nx)] = on .+ (1:nx)
            t < H - 1 && (xmap[ot .+ ((nx+1):(nx+nu))] = on .+ ((nx+1):(nx+nu)))
        end
    end
    return xmap
end

# ---------------------------------------------------------------------------
# Resolutions as chains: fine, rows (rows x !), mixed (vehicles before t0, rows from t0)
# ---------------------------------------------------------------------------

"""
The levels of a resolution of the parametric program. `fine`: none. `rows`:
every vehicle condensed, then adjacent blocks of a row merged level by level
up to whole rows (E26's chain26). `mix_t<t0>`: every vehicle condensed into an
early block (instants before t0) and a late block (t0 on), then the late blocks
merged as for rows; the early blocks are never merged. Returns the chain and
the key of every block of the last level: (0, i, 0) the early block of vehicle
i, (1, row, colblock) a late block.
"""
function chain27(pp::ParamProgram27, sc::Scenario27, form::AbstractString)
    form == "fine" && return SM.ReducedProgram[], [(1, i, 0) for i in 1:sc.n]
    t0 = form in ("rows", "rows_abs") ? 0 : parse(Int, match(r"^mix_t(\d+)$", form).captures[1])
    labels = [t < t0 ? 2i - 1 : 2i for i in 1:sc.n for t in 0:sc.H]       # agent-major vertices
    R = reduce(pp.P, SM.VertexPartition(labels))
    chain = SM.ReducedProgram[R]
    keys_ = Tuple{Int,Int,Int}[]; lead = Int[]                           # coarse vertices by first appearance
    for i in 1:sc.n
        t0 > 0 && (push!(keys_, (0, i, 0)); push!(lead, i))
        push!(keys_, (1, i, 0)); push!(lead, i)
    end
    length(keys_) == SM.nvertices(R.program) || error("unexpected coarse vertex count")
    w = 1
    while w < sc.side
        w *= 2
        lab = [k[1] == 0 ? k : (1, row27(sc, l), cld(col27(sc, l), w)) for (k, l) in zip(keys_, lead)]
        Pi = SM.canonical_partition(lab)
        nb = maximum(Pi)
        nk = Vector{Tuple{Int,Int,Int}}(undef, nb); nl = zeros(Int, nb); seen = falses(nb)
        for (b, p) in enumerate(Pi)
            seen[p] && continue
            seen[p] = true; nk[p] = lab[b]; nl[p] = lead[b]
        end
        R = reduce(R, SM.VertexPartition(Pi))
        push!(chain, R)
        keys_ = nk; lead = nl
    end
    return chain, keys_
end

# ---------------------------------------------------------------------------
# The QP of a program with duplicate constraints merged to a tolerance (E26's Merged26)
# ---------------------------------------------------------------------------

mutable struct Merged27
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

function _merge_groups27(qp::SM.ConicQP, b::Vector{Float64}, tol::Float64)
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

function Merged27(P::SM.GraphProgram; merge::Bool = true)
    full = SM.QPMap(P; dedup = false)
    m = SM.nrows(full.qp)
    group = merge ? _merge_groups27(full.qp, full.b, MERGE_TOL27) : collect(1:m)
    G = Merged27(full, Int[], Int[], full.qp, Float64[], true, 0.0, 0, 0, 0)
    _assemble27!(G, group)
    return G
end

function _assemble27!(G::Merged27, group::Vector{Int})
    qp = G.full.qp
    m = length(group)
    keep = [i for i in 1:m if group[i] == i]
    pos = zeros(Int, m); pos[keep] .= 1:length(keep)
    G.group = [pos[group[i]] for i in 1:m]
    G.keep = keep
    socs = [pos[first(B)]:pos[last(B)] for B in qp.socs if pos[first(B)] > 0]
    G.merged_cones = length(qp.socs) - length(socs)
    G.merged_rows = m - length(keep)
    G.b = zeros(length(keep))
    G.qp = SM.ConicQP(qp.P, copy(G.full.q), qp.A[keep, :], fill(-Inf, length(keep)), fill(Inf, length(keep));
                      c = G.full.c, socs = socs, socb = zeros(length(keep)), kinds = qp.kinds[keep])
    _fill_b27!(G)
    return G
end

function _fill_b27!(G::Merged27)
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
            sp = max(sp, abs(b[g] - bf[i]) / max(1.0, abs(b[g])))
        end
    end
    G.spread = sp
    sp > MERGE_TOL27 && (G.valid = false)
    return G
end

refresh27!(G::Merged27, P::SM.GraphProgram) = (SM.refresh!(G.full, P); _fill_b27!(G); G.valid)

function unmerge27!(G::Merged27)
    _assemble27!(G, collect(1:SM.nrows(G.full.qp)))
    G.valid = true
    G.rebuilt += 1
    return G
end

"""A conic QP from its matrices, the row kinds and the current right-hand side `b` (the `b - A x in K` convention)."""
function qp_with27(qp::SM.ConicQP, q, b, c)
    m = SM.nrows(qp)
    l = fill(-Inf, m); u = fill(Inf, m); socb = zeros(m)
    @inbounds for i in 1:m
        k = qp.kinds[i]
        if k == SM.ROW_EQ
            l[i] = b[i]; u[i] = b[i]
        elseif k == SM.ROW_LEQ
            u[i] = b[i]
        else
            socb[i] = b[i]
        end
    end
    return SM.ConicQP(qp.P, q, qp.A, l, u; c = c, socs = qp.socs, socb = socb, kinds = qp.kinds)
end

current_qp27(G::Merged27) = qp_with27(G.qp, G.full.q, G.b, G.full.c)
current_qp27(M::SM.QPMap) = qp_with27(M.qp, M.q, M.b, M.c)

# ---------------------------------------------------------------------------
# Centralized controllers: coordinated (fine), rows, mixed
# ---------------------------------------------------------------------------

mutable struct Form27
    name::String
    pp::ParamProgram27
    chain::Vector{SM.ReducedProgram}
    keys::Vector{Tuple{Int,Int,Int}}
    G::Merged27
    levels::Vector{Vector{Float64}}
    xmapf::Vector{Int}                        # shift of the fine plan (x only)
    xmap::Vector{Int}                         # fine: the merged QP's shifted warm start (MPCController's rule)
    ymap::Vector{Int}
    t_build::Dict{String,Float64}
    absorb::Vector{Tuple{Int,Int,Int,Matrix{Float64}}}    # rows_abs: (formation edge, i, j, C A^t) of every edge inside a row
    op::Union{SM.StepOperator,Nothing}        # the step operator of the chain (BENCH_RED_PATH=stepop, form rows), else nothing
    ubuf::Vector{Float64}                     # the applied inputs it lifts, agent by agent
    coh::Vector{Int}                          # merged copies: the entry of the row's first member, per active entry
    lbmax::Float64                            # and the largest bounds of a copy's error
    lwmax::Float64
    bound::Float64                            # the bound of the last step
    fallbacks::Int                            # steps whose copies were recomputed level by level
    path::String                              # the construction path: stepop or chain
end

Pq27(F::Form27) = isempty(F.chain) ? F.pp.P : F.chain[end].program

"""
A program of a centralized controller: the parametric (fine) program, the
levels of its resolution, the merged QP and, for the form `rows` with
BENCH_RED_PATH=stepop (`stepop = true`), E26's step operator of the chain
(Form26: the changing data to the QP vectors and the applied inputs, the
merged copies chained to their kept row and certified by their error bound).
"""
function Form27(sc::Scenario27, name::AbstractString; x0 = start27(sc), t0 = 0.0, stepop::Bool = RED_PATH27 == "stepop")
    tb = Dict{String,Float64}()
    t = time_ns(); pp = ParamProgram27(sc); tb["program"] = sec27(time_ns(), t)
    refs, term = references27(sc, t0)
    set_data27!(pp, sc, x0, refs, term)
    ab = absorb27(sc, name)
    isempty(ab) || rebase27!(pp, ab, x0)
    t = time_ns(); chain, keys_ = chain27(pp, sc, name); tb["fibers"] = sec27(time_ns(), t)
    Pq = isempty(chain) ? pp.P : chain[end].program
    t = time_ns(); G = Merged27(Pq); tb["qp"] = sec27(time_ns(), t)
    levels = Vector{Float64}[zeros(SM.c0dim(pp.P))]
    for R in chain
        push!(levels, zeros(SM.c0dim(R.program)))
    end
    op = nothing; coh = Int[]
    if stepop && name == "rows" && !isempty(chain)
        t = time_ns()
        act = active27(pp, sc)
        if G.merged_rows > 0
            W, coh = coherence27(pp, sc, act)
            op = SM.StepOperator(chain[end], G.full, act; lift_rows = input_rows27(pp, sc), chains = merge_chains27(G),
                                 invariant = W, link_droptol = LINKTOL27)
        else
            op = SM.StepOperator(chain[end], G.full, act; lift_rows = input_rows27(pp, sc))
        end
        tb["stepop"] = sec27(time_ns(), t)
    end
    lb = op === nothing ? 0.0 : maximum(op.linkbound; init = 0.0)
    lw = op === nothing ? 0.0 : maximum(op.linkboundW; init = 0.0)
    F = Form27(String(name), pp, chain, keys_, G, levels, fine_xmap27(pp, sc), Int[], Int[], tb, absorb27(sc, name), op,
               zeros(op === nothing ? 0 : length(op.lift_rows)), coh, lb, lw, 0.0, 0, op === nothing ? "chain" : "stepop")
    name == "fine" && shift_maps27!(F, sc)
    return F
end

"""
The entries of the parametric program's data that change from step to step
(what `set_data27!` writes, besides the constants): the tracking costs q of
every state and the targets of the dynamics edges from (i, 0) (E26's active26).
"""
function active27(pp::ParamProgram27, sc::Scenario27)
    P = pp.P; act = Int[]
    for (i, ag) in enumerate(sc.fleet.agents)
        for t in 1:sc.H
            append!(act, SM.data_index(P, :q, pp.vid[i, t+1])[1:ag.nx])
        end
        append!(act, SM.data_index(P, :be, pp.dyn[i, 1]))
    end
    return act
end

"""The chains of the merged rows of `G`: every copy after the previous copy of its group, the kept row first (E26's merge_chains26)."""
function merge_chains27(G::Merged27)
    prev = zeros(Int, length(G.group)); last = Dict{Int,Int}()
    for i in eachindex(G.group)
        g = G.group[i]
        prev[i] = get(last, g, 0); last[g] = i
    end
    return prev
end

"""
Coherence of the data (E26's coherence26): the same entry of every member of a
row moves alike when the row's data stay coherent, and then the copies of a
merged cone stay equal (Thm. thm:equitable). `W` (one column per row and
entry) spans these motions; the second output is, per active entry, the entry
of the row's first member that it follows.
"""
function coherence27(pp::ParamProgram27, sc::Scenario27, act)
    P = pp.P
    owner = zeros(Int, length(act)); pos = zeros(Int, length(act))
    o = 0
    for i in 1:sc.n
        len = sc.H * sc.fleet.agents[i].nx + length(SM.erange(P, pp.dyn[i, 1]))
        owner[(o+1):(o+len)] .= i; pos[(o+1):(o+len)] .= 1:len
        o += len
    end
    o == length(act) || error("active27 changed its layout")
    cls = Dict{Tuple{Int,Int},Int}(); first = zeros(Int, length(act)); col = zeros(Int, length(act))
    for j in eachindex(act)
        key = (row27(sc, owner[j]), pos[j])
        c = get!(cls, key, length(cls) + 1)
        col[j] = c
        col27(sc, owner[j]) == 1 && (first[j] = j)
    end
    firstof = zeros(Int, length(cls))
    for j in eachindex(act)
        first[j] > 0 && (firstof[col[j]] = j)
    end
    return sparse(1:length(act), col, 1.0, length(act), length(cls)), firstof[col]
end

"""The bound of the copies' error: the data's departure from row coherence since the build, and the common motion (E26's copy_bound26)."""
function copy_bound27(F::Form27)
    op = F.op; a = op.a; a0 = op.qb.x0; first = F.coh
    dev = 0.0; tinf = 0.0
    @inbounds for j in eachindex(a)
        f = first[j]
        t = a[f] - a0[f]
        dev = max(dev, abs((a[j] - a0[j]) - t)); tinf = max(tinf, abs(t))
    end
    return F.lbmax * dev + F.lwmax * tinf
end

"""The largest relative spread of the merged cones' copies in the full right-hand side `bf` (as `_fill_b27!`)."""
function spread27(G::Merged27, bf::AbstractVector)
    sp = 0.0
    for i in eachindex(bf)
        g = G.group[i]; k = G.keep[g]
        (k == i || G.qp.kinds[g] == SM.ROW_LEQ) && continue
        sp = max(sp, abs(bf[k] - bf[i]) / max(1.0, abs(bf[k])))
    end
    return sp
end

"""The coordinates of the applied inputs u_{i,0} in a plan of the parametric program, agent by agent."""
input_rows27(pp::ParamProgram27, sc::Scenario27) = reduce(vcat, [collect(SM.vrange(pp.P, pp.vid[i, 1])) for i in 1:sc.n])

"""MPCController's shifted warm start of the time-expanded program, mapped to the merged rows (E26's shift_maps26!)."""
function shift_maps27!(F::Form27, sc::Scenario27)
    pp = F.pp; P = pp.P; H = sc.H
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
    F.xmap = F.xmapf
    F.ymap = [F.G.group[yfull[i]] for i in F.G.keep]
    return F
end

"""The reduction update of every level of the chain (the level by level construction path)."""
function construct_red27!(F::Form27)
    feasible = true
    for R in F.chain
        SM.update!(R)
        feasible &= R.feasible
    end
    return feasible
end

"""
E21's absorb: the formation edges inside every row (the ones a row hardens), as
(edge, i, j, C A^t), so that their targets can be re-based on the measured
state, b = C A^t (xhat_j - xhat_i): the members' offsets from their slots are
carried along as the free response, equal inputs inside a row are always
feasible, and the row never corrects its own shape (the fine level does, in the
two-level controller). Empty for every form but `rows_abs`.
"""
function absorb27(sc::Scenario27, name::AbstractString)
    out = Tuple{Int,Int,Int,Matrix{Float64}}[]
    name == "rows_abs" || return out
    fl = sc.fleet; ne = length(fl.edges)
    for t in 1:sc.H, (k, (i, j)) in enumerate(fl.edges)
        row27(sc, i) == row27(sc, j) || continue
        A = fl.agents[i].A[1]
        A == fl.agents[j].A[1] || error("a row of two airframes")
        push!(out, (sc.n * sc.H + (t - 1) * ne + k, i, j, fl.agents[i].C * A^t))
    end
    return out
end

function rebase27!(pp::ParamProgram27, ab, x)
    P = pp.P
    @inbounds for (e, i, j, M) in ab
        b = P.edges[e].b; xi = x[i]; xj = x[j]
        for a in eachindex(b)
            s = 0.0
            for q in eachindex(xi)
                s += M[a, q] * (xj[q] - xi[q])
            end
            b[a] = s
        end
    end
    return pp
end

"""
Construction of a step (E26's construct26!): the data into the fine program,
then the QP vectors of the last level, by the step operator (one precomposed
product from the changing data; the levels' programs are left behind,
`plan27!` brings them up to date) or level by level (every level's reduction
update and the QP map), and the merged right-hand side. With the step
operator the merge check of the chained copies is certified with their error
bound, or else done on the copies computed level by level (`fallbacks`).
"""
function construct27!(F::Form27, sc::Scenario27, x, refs, term)
    set_data27!(F.pp, sc, x, refs, term)
    isempty(F.absorb) || rebase27!(F.pp, F.absorb, x)
    if F.op !== nothing
        SM.update!(F.op)
        _fill_b27!(F.G)
        if F.op.deviation
            F.bound = copy_bound27(F)
            if !(F.G.valid && F.G.spread + F.bound <= MERGE_TOL27)
                SM.sync!(F.op)
                F.G.valid = true
                _fill_b27!(F.G)
                F.fallbacks += 1
            end
        end
        return F.op.feasible, F.G.valid
    end
    feasible = construct_red27!(F)
    ok = refresh27!(F.G, Pq27(F))
    return feasible, ok
end

"""Lift a solution of the last level to the fine plan (in place, level by level)."""
function lift27!(F::Form27, y::AbstractVector)
    nl = length(F.chain)
    copyto!(F.levels[nl+1], y)
    for k in nl:-1:1
        SM.lift!(F.levels[k], F.chain[k], F.levels[k+1])
    end
    return F.levels[1]
end

"""
The inputs a solution `y` of the last level applies, u_{i,0} of every agent
(E26's lift26!): by the step operator (precomposed from `y` and the step's
data), or from the fine plan lifted level by level.
"""
function lift_inputs27!(F::Form27, y::AbstractVector)
    F.op === nothing && return first_inputs27(F.pp, lift27!(F, y))
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

"""
The fine plan of a solution `y`, outside the timed step (E26's plan26!): with
the step operator the levels are first brought up to the step's data
(SM.sync!, the level by level update, whose QP vectors are compared with the
operator's, `stepop_diff`), then lifted level by level, and the applied inputs
`u` compared with the lifted plan's (`stepop_input_diff`); without it, the plan
`lift_inputs27!` lifted.
"""
function plan27!(F::Form27, y::AbstractVector, u, diag::Dict{String,Any})
    F.op === nothing && return F.levels[1]
    M = F.G.full
    q, b = copy(M.q), copy(M.bfull)
    SM.sync!(F.op)
    xf = lift27!(F, y)
    rel(a, c) = isempty(c) ? 0.0 : maximum(abs, a - c) / max(1.0, maximum(abs, c))
    if F.op.deviation
        kept = F.G.keep
        diag["stepop_diff"] = max(rel(q, M.q), rel(b[kept], M.bfull[kept]))
        diag["stepop_copy_err"] = maximum(abs, b - M.bfull); diag["stepop_copy_bound"] = F.bound
    else
        diag["stepop_diff"] = max(rel(q, M.q), rel(b, M.bfull))
    end
    diag["stepop_input_diff"] = maximum(maximum(abs, u[i] - xf[SM.vrange(F.pp.P, F.pp.vid[i, 1])]) for i in eachindex(u))
    return xf
end

sizes27(F::Form27) = Dict{String,Any}("variables" => SM.nvars(F.G.qp), "rows" => SM.nrows(F.G.qp), "cones" => length(F.G.qp.socs),
    "rows_full" => SM.nrows(F.G.full.qp), "cones_full" => length(F.G.full.qp.socs), "merged_cones" => F.G.merged_cones,
    "levels" => length(F.chain), "blocks" => length(F.keys), "fine_variables" => SM.c0dim(F.pp.P),
    "nnz_P" => nnz(F.G.qp.P), "nnz_A" => nnz(F.G.qp.A),
    "nnz_X" => isempty(F.chain) ? 0 : sum(nnz(R.X) for R in F.chain), "path" => F.path,
    "stepop_deviation" => F.op !== nothing && F.op.deviation, "nnz_stepop" => F.op === nothing ? 0 : nnz(F.op.qb),
    "nnz_stepop_lift" => F.op === nothing ? 0 : nnz(F.op.lift), "stepop_dust" => F.op === nothing ? 0.0 : F.op.dust,
    "stepop_copy_bounds" => [F.lbmax, F.lwmax], "build_parts" => F.t_build)

abstract type Ctl27 end

mutable struct Central27 <: Ctl27
    F::Form27
    s::Union{Nothing,SM.Solver}
    xs::Vector{Float64}
    ys::Vector{Vector{Float64}}
    methods::Dict{String,Int}
end

Central27(sc::Scenario27, form::AbstractString; stepop::Bool = RED_PATH27 == "stepop") =
    (F = Form27(sc, form; stepop = stepop); Central27(F, nothing, zeros(SM.c0dim(F.pp.P)), [zeros(SM.c0dim(R.program)) for R in F.chain], Dict{String,Int}()))

"""
The warm start of a centralized step (the data are already in the solver):
coordinated MPC from the previous primal-dual solution shifted one instant;
a chain from the previous fine plan shifted one instant and restricted level by
level (BENCH_RED_WARM=shift) or the previous reduced solution (previous).
"""
function warm27!(c::Central27)
    s = c.s; F = c.F
    if s.info.status != :solved
        SM.reset!(s)
    elseif isempty(F.chain)
        SM.warm_start_shifted!(s, F.xmap, F.ymap)
    elseif RED_WARM27 == "shift"
        xp = F.levels[1]; xs = c.xs; xm = F.xmapf
        @inbounds for j in eachindex(xs)
            xs[j] = xp[xm[j]]
        end
        y = xs
        for (k, R) in enumerate(F.chain)
            SM.restrict!(c.ys[k], R, y)
            y = c.ys[k]
        end
        SM.warm_start!(s; x = y)
    end                                            # previous: the previous solution as it is
    return c
end

"""
One step of a centralized controller. Timed (E26's boundary): construction
(the data into the fine program, the QP vectors, the merge), setup (the data
into the solver and the warm start; at the first step, or after a rebuild, the
solver's setup), solve, and the lift of the applied inputs. Untimed: the fine
plan (for the fallback, the residuals and, with the step operator, its checks).
"""
function step27!(c::Central27, sc::Scenario27, x, refs, term, k::Int)
    F = c.F
    diag = Dict{String,Any}()
    t0 = time_ns()
    feasible, ok = construct27!(F, sc, x, refs, term)
    t1 = time_ns()
    rebuilt = false
    if !ok
        unmerge27!(F.G)
        if F.op !== nothing && F.op.deviation
            F.op = nothing; F.path = "chain"; diag["stepop_off"] = true          # copies are rows now: level by level
        end
        F.name == "fine" && shift_maps27!(F, sc)
        c.s = nothing; rebuilt = true
    end
    if c.s === nothing
        c.s = SM.setup(current_qp27(F.G); settings = settings27())
    else
        # the step operator does not recompute the constant (it does not move the minimizer): the solver keeps its own (E26)
        SM.update!(c.s; q = F.G.full.q, b = F.G.b, c = F.op === nothing ? F.G.full.c : nothing)
        warm27!(c)
    end
    t2 = time_ns()
    info = SM.solve!(c.s)
    t3 = time_ns()
    u = lift_inputs27!(F, c.s.xsol)
    t4 = time_ns()
    xf = plan27!(F, c.s.xsol, u, diag)
    st = feasible ? info.status : :primal_infeasible
    m = string(info.method); c.methods[m] = get(c.methods, m, 0) + 1
    fz = SM.feasibility(F.pp.P, xf)
    bad = st in (:primal_infeasible, :dual_infeasible)
    tc, ts, tv, tl = sec27(t1, t0), sec27(t2, t1), sec27(t3, t2), sec27(t4, t3)
    seq = tc + ts + tv + tl
    F.op === nothing || (diag["merge_spread"] = F.G.spread)
    return (u = u, U = inputs27(F.pp, sc, xf), infeasible = fill(bad, sc.n), unconverged = (!bad && st != :solved) ? 1 : 0,
            status = string(st), iter = info.iter + info.ipm_iter, tc = tc, ts = ts, tv = tv, tl = tl, seq = seq, par = seq,
            rounds = 2, floats = nfloats27(sc), feas = max(fz.hard, fz.cone), rebuilt = rebuilt, method = m, diag = diag)
end

# ---------------------------------------------------------------------------
# Decentralized MPC: one condensed program per vehicle (E25's fair baseline on this fleet)
# ---------------------------------------------------------------------------

"""Vehicle `ag` alone, its tracked outputs (stage and terminal) extended by one copy of its position per incident spring of weight `ws[k]`."""
function fair_agent27(ag::SM.Agent, ws::Vector{Float64}, sels::Vector{Matrix{Float64}} = [Matrix{Float64}(I, size(ag.C, 1), size(ag.C, 1)) for _ in ws])
    m = length(ws)
    m == 0 && return ag
    C = ag.C
    Wb = cat([w * Matrix{Float64}(I, size(S, 1), size(S, 1)) for (w, S) in zip(ws, sels)]...; dims = (1, 2))
    Cs = reduce(vcat, [S * C for S in sels])
    return SM.Agent(ag.A, ag.B; g = ag.g, C = C, Cr = [ag.Cr; Cs], Q = Matrix(cat(ag.Q, Wb; dims = (1, 2))), R = ag.R,
                    Cf = [ag.Cf; Cs], Qf = Matrix(cat(ag.Qf, Wb; dims = (1, 2))), input = ag.input, kind = ag.kind)
end

mutable struct Veh27
    i::Int
    inc::Vector{Tuple{Int,Int,Float64}}           # (edge k, neighbour j, s): the spring wants C x_i = p_j + s target_k
    fp::SM.FleetProgram
    R::SM.ReducedProgram
    M::SM.QPMap
    s::Union{Nothing,SM.Solver}
    xf::Vector{Float64}
    xs::Vector{Float64}
    y0::Vector{Float64}
    Rm::Matrix{Float64}
    term::Vector{Float64}
    started::Bool
end

function Veh27(sc::Scenario27, i::Int, inc)
    ag = sc.fleet.agents[i]
    ws = [sc.fleet.weights[k, 1] for (k, _, _) in inc]
    all(k -> all(==(sc.fleet.weights[k, 1]), sc.fleet.weights[k, :]), first.(inc)) || error("time-varying formation weights")
    sels = [sc.fleet.select[k] for (k, _, _) in inc]
    fl = SM.Fleet([fair_agent27(ag, ws, sels)], Tuple{Int,Int}[]; H = sc.H)
    fp = SM.FleetProgram(fl)
    R = reduce(fp, SM.full_condensing())
    M = SM.QPMap(R.program)
    nf = SM.c0dim(fp.program)
    ps = sum((size(S, 1) for S in sels); init = 0)
    return Veh27(i, inc, fp, R, M, nothing, zeros(nf), zeros(nf), zeros(SM.c0dim(R.program)),
                 zeros(ny27(ag) + ps, sc.H + 1), zeros(ag.nx + ps), false)
end

mutable struct Dec27 <: Ctl27
    byref::Bool
    vs::Vector{Veh27}
end

function Dec27(sc::Scenario27, byref::Bool)
    inc = [Tuple{Int,Int,Float64}[] for _ in 1:sc.n]
    for (k, (a, b)) in enumerate(sc.fleet.edges)
        push!(inc[a], (k, b, -1.0)); push!(inc[b], (k, a, 1.0))
    end
    return Dec27(byref, [Veh27(sc, i, inc[i]) for i in 1:sc.n])
end

"""Vehicle `v`'s references: its own, then each spring's target from the predicted neighbour (no spring at t = 0: the state is pinned)."""
function fair_refs27!(v::Veh27, sc::Scenario27, x, refs, term, byref::Bool)
    H = sc.H; h = sc.h; Rm = v.Rm; fl = sc.fleet
    Ri = refs[v.i]; ny = size(Ri, 1); nx = fl.agents[v.i].nx
    @inbounds for t in 1:(H+1), a in 1:ny
        Rm[a, t] = Ri[a, t]
    end
    v.term[1:nx] .= term[v.i]
    o = ny; ot = nx
    Ci = fl.agents[v.i].C
    for (k, j, s) in v.inc
        S = fl.select[k]; pk = size(S, 1)
        Rm[(o+1):(o+pk), 1] .= S * (Ci * x[v.i])
        aj = fl.agents[j]; dj = pdim27(aj)
        pj0 = aj.C * x[j]; vj = aj.C * [x[j][(dj+1):(2dj)]; zeros(dj)]        # position and velocity in R^3
        for t in 1:H
            pj = byref ? [refs[j][:, t+1]; zeros(3 - size(refs[j], 1))] : pj0 + t * h * vj
            Rm[(o+1):(o+pk), t+1] .= S * (pj + s * fl.targets[:, k, t])
        end
        v.term[(ot+1):(ot+pk)] .= Rm[(o+1):(o+pk), H+1]
        o += pk; ot += pk
    end
    return v
end

function vstep27!(v::Veh27, sc::Scenario27, x, refs, term, byref::Bool)
    t0 = time_ns()
    fair_refs27!(v, sc, x, refs, term, byref)
    SM.set_state!(v.fp, [x[v.i]])
    SM.set_references!(v.fp, [v.Rm]; terminal = [v.term])
    SM.update!(v.R)
    SM.refresh!(v.M, v.R.program)
    if !v.M.valid
        v.M = SM.QPMap(v.R.program; dedup = false); v.s = nothing
    end
    t1 = time_ns()
    M = v.M
    if v.s === nothing
        v.s = SM.setup(current_qp27(M); settings = settings27())
    else
        SM.update!(v.s; q = M.q, b = M.b, c = M.c)
        if v.s.info.status != :solved
            SM.reset!(v.s)
        elseif v.started
            SM.shift_plan!(v.xs, v.fp, v.xf, [x[v.i]])
            SM.restrict!(v.y0, v.R, v.xs)
            SM.warm_start!(v.s; x = v.y0)
        end
    end
    t2 = time_ns()
    info = SM.solve!(v.s)
    t3 = time_ns()
    SM.lift!(v.xf, v.R, v.s.xsol)
    ag1 = v.fp.fleet.agents[1]
    o = v.fp.program.offsets[v.fp.vid[1, 1]] + ag1.nx
    u = v.xf[(o+1):(o+ag1.nu)]
    t4 = time_ns()
    v.started = true
    return u, info.status, info.iter + info.ipm_iter, sec27(t1, t0), sec27(t2, t1), sec27(t3, t2), sec27(t4, t3)
end

function step27!(c::Dec27, sc::Scenario27, x, refs, term, k::Int)
    n = sc.n
    u = Vector{Vector{Float64}}(undef, n); U = Vector{Matrix{Float64}}(undef, n)
    bad = falses(n); unconv = 0; tc = ts = tv = tl = 0.0; par = 0.0; its = 0; fz = 0.0
    for v in c.vs
        ui, st, it, a, b, cc, d = vstep27!(v, sc, x, refs, term, c.byref)
        u[v.i] = ui
        tc += a; ts += b; tv += cc; tl += d; par = max(par, a + b + cc + d); its += it
        bad[v.i] = st in (:primal_infeasible, :dual_infeasible)
        (!bad[v.i] && st != :solved) && (unconv += 1)
    end
    for v in c.vs                                   # untimed: the plans for the fallback and the residuals
        U[v.i] = SM.trajectories(v.fp, v.xf)[2][1]
        f = SM.feasibility(v.fp.program, v.xf); fz = max(fz, f.hard, f.cone)
    end
    return (u = u, U = U, infeasible = bad, unconverged = unconv, status = all(.!bad) && unconv == 0 ? "solved" : "mixed",
            iter = round(Int, its / n), tc = tc, ts = ts, tv = tv, tl = tl, seq = tc + ts + tv + tl, par = par, rounds = 0, floats = 0,
            feas = fz, rebuilt = false, method = "per vehicle")
end

# ---------------------------------------------------------------------------
# Distributed MPC (the package's DistributedMPC) over vehicles or over rows
# ---------------------------------------------------------------------------

mutable struct Dmpc27 <: Ctl27
    D::SM.DistributedMPC
    rows::Bool
end

"""The local QPs to MPCController's accuracy (DistributedMPC's own default is 1e-9)."""
function local_accuracy27!(D::SM.DistributedMPC)
    for L in D.locals, (k, v) in pairs(SM_SETTINGS27)
        setproperty!(L.solver.settings, k, v)
    end
    return D
end

rowteams27(sc) = [row27(sc, i) for i in 1:sc.n]

function Dmpc27(sc::Scenario27, rows::Bool, rho::Float64, budget::Int)
    D = SM.DistributedMPC(sc.fleet, rows ? rowteams27(sc) : collect(1:sc.n); rho = rho, budget = budget, warm = :shift)
    return Dmpc27(local_accuracy27!(D), rows)
end

function step27!(c::Dmpc27, sc::Scenario27, x, refs, term, k::Int)
    D = c.D
    info = SM.step!(D, x, refs; terminal = term)
    xf = SM.plan(D)
    nag = length(D.locals)
    seq = info.t_total
    par = (info.t_total - info.t_solve) / nag + D.t_parallel
    st = info.status
    bad = st in (:primal_infeasible, :dual_infeasible) || !info.feasible
    fz = SM.feasibility(D.fp.program, xf)
    return (u = [copy(v) for v in info.u], U = SM.trajectories(D.fp, xf)[2], infeasible = fill(bad, sc.n),
            unconverged = (!bad && st != :solved) ? 1 : 0, status = string(st), iter = info.iter,
            tc = info.t_construct, ts = info.t_setup, tv = info.t_solve, tl = info.t_lift, seq = seq, par = par,
            rounds = info.iter + (c.rows ? 2 : 0), floats = D.floats + (c.rows ? nfloats27(sc) : 0),
            feas = max(fz.hard, fz.cone), rebuilt = false, method = "consensus ADMM")
end

# ---------------------------------------------------------------------------
# Two levels: the rows' reduced plan as the warm start of distributed MPC over vehicles
# ---------------------------------------------------------------------------

"""
The coarse-grid correction: each step the rows' reduced program is solved
(centrally, as `rows`), its plan lifted to the fleet, and distributed MPC over
vehicles runs `budget` iterations from it: the consensus targets of every
interface are the lifted plan's (restricted to the vehicles' condensed
coordinates, as DistributedMPC's own shifted warm start restricts its shifted
plan), the scaled duals shifted one instant (zero at the first step). The
package's DistributedMPC has no call that takes a warm-start plan, so it runs
with `warm = :previous` and its targets and duals are set here before each
step. When the rows' program is infeasible, the targets come from
DistributedMPC's previous plan shifted one instant, as for plain DMPC.
"""
mutable struct TwoLevel27 <: Ctl27
    rows::Central27
    D::SM.DistributedMPC
    src::Vector{Int}          # FleetProgram coordinate j: index into the parametric plan (> 0) or measured state entry -k
    xfp::Vector{Float64}
    duals::Bool               # _mu: the scaled duals from the coarse solve's forces (else shifted, as plain DMPC)
    cert::Any                 # the Certifier of the coarse chain (_mu)
    ifedges::Vector{Vector{Int}}    # per interface: the parametric program's formation edge of each of its coarse edges
    hardened::BitVector       # parametric program edges the coarse level hardens (formation edges inside a row)
    zsave::Vector{Vector{Float64}}  # the targets set before the step (diagnostics)
end

function TwoLevel27(sc::Scenario27, rho::Float64, budget::Int; coarse::AbstractString = "rows", duals::Bool = false)
    rows = Central27(sc, coarse; stepop = false)       # the coarse plan is lifted to the fleet every step: level by level
    D = local_accuracy27!(SM.DistributedMPC(sc.fleet, collect(1:sc.n); rho = rho, budget = budget, warm = :previous))
    pp = rows.F.pp; fp = D.fp
    src = zeros(Int, SM.c0dim(fp.program))
    for i in 1:sc.n, t in 0:sc.H
        rf = SM.vrange(fp.program, fp.vid[i, t+1]); rp = SM.vrange(pp.P, pp.vid[i, t+1])
        if t == 0
            src[rf[1:6]] .= -(6 * (i - 1) .+ (1:6)); src[rf[7:9]] .= rp
        else
            length(rf) == length(rp) || error("layouts disagree at ($i, $t)")
            src[rf] .= rp
        end
    end
    ne = length(sc.fleet.edges)
    kidx = Dict(e => k for (k, e) in enumerate(sc.fleet.edges))
    Pc = D.R.program
    ifedges = [[sc.n * sc.H + (Pc.edges[e].tag.t - 1) * ne + kidx[(Pc.edges[e].tag.i, Pc.edges[e].tag.j)] for e in I.edges] for I in D.ifs]
    for (I, es) in zip(D.ifs, ifedges), (e, ep) in zip(I.edges, es)
        tg = pp.P.edges[ep].tag
        (tg.kind == :form && tg.i == Pc.edges[e].tag.i && tg.j == Pc.edges[e].tag.j && tg.t == Pc.edges[e].tag.t) || error("edge maps disagree")
    end
    hardened = falses(length(pp.P.edges))
    for (ep, E) in enumerate(pp.P.edges)
        E.tag.kind == :form && row27(sc, E.tag.i) == row27(sc, E.tag.j) && (hardened[ep] = true)
    end
    cert = duals ? SM.Certifier(rows.F.chain[end]) : nothing
    return TwoLevel27(rows, D, src, zeros(SM.c0dim(fp.program)), duals, cert, ifedges, hardened, [zeros(length(z)) for z in D.z])
end

"""
The scaled duals that make the lifted coarse plan stationary for every local QP
of distributed MPC. For an interface u -> v with coarse edges e, let g^r be the
gradient in u's interface coordinates of the springs at the lifted plan,
sum_e sgn X_e' W_e r_e (r_e its residual on the true targets), and g^f the same
with the force of every edge the coarse level hardens replaced by its
multiplier mu_e from the coarse solve (recovered by the Certifier, the forces of
Thm. thm:price). Stationarity of u's local QP at the lifted plan with z at the
plan's interface values needs rho lam = g^f - g^r / 2, and of the copy v holds,
rho mu = -g^r / 2. Where the coarse plan is optimal for the fleet (coherent
data, zero gap: mu_e = W_e r_e = 0 on the hardened edges) lam + mu = 0 and the
warm start is a fixed point of consensus ADMM; otherwise the first consensus
update moves z by (g^f - g^r) / (2 rho), along the teams' internal forces.
"""
function coarse_duals27!(c::TwoLevel27, sc::Scenario27)
    F = c.rows.F; G = F.G; s = c.rows.s; P = F.pp.P; xp = F.levels[1]; D = c.D
    M = G.full; Pq = Pq27(F)
    cnt = zeros(Int, length(G.keep))
    for g in G.group
        cnt[g] += 1
    end
    yfull = [s.ysol[G.group[i]] / cnt[G.group[i]] for i in eachindex(G.group)]
    he = zeros(SM.c1dim(Pq))
    for k in 1:M.nh
        he[M.hard_rows[k]] = yfull[k]
    end
    SM.certify!(c.cert, xp, he, yfull[(M.nh+1):end])
    mus = SM.multipliers(c.cert)
    fl = sc.fleet; vid = F.pp.vid; ne = length(fl.edges)
    for (q, I) in enumerate(D.ifs)
        gr = zeros(length(D.z[q])); gf = zeros(length(D.z[q]))
        for (j, ep) in enumerate(c.ifedges[q])
            tg = P.edges[ep].tag; t = tg.t; k = ep - sc.n * sc.H - (t - 1) * ne
            pi_ = view(xp, SM.vrange(P, vid[tg.i, t+1])[1:3]); pj = view(xp, SM.vrange(P, vid[tg.j, t+1])[1:3])
            r = pj - pi_ - fl.targets[:, k, t]
            wr = fl.weights[k, t] * r
            Xt = transpose(I.X[j])
            gr .+= I.sgn[j] .* (Xt * wr)
            gf .+= I.sgn[j] .* (Xt * (c.hardened[ep] ? mus[ep] : wr))
        end
        D.lam[q] .= (gf .- 0.5 .* gr) ./ D.rho
        D.mu[q] .= (-0.5 / D.rho) .* gr
    end
    return c
end

function step27!(c::TwoLevel27, sc::Scenario27, x, refs, term, k::Int)
    o = step27!(c.rows, sc, x, refs, term, k)
    D = c.D; fp = D.fp; R = D.R; Pc = R.program
    t0 = time_ns()
    SM.set_state!(fp, x); SM.set_references!(fp, refs; terminal = term); SM.update!(R)     # restrict needs this step's particular solution
    started = D.steps > 0 && D.healthy
    if !o.infeasible[1]
        xp = c.rows.F.levels[1]; xfp = c.xfp; src = c.src
        @inbounds for j in eachindex(xfp)
            s = src[j]
            xfp[j] = s > 0 ? xp[s] : x[div(-s - 1, 6) + 1][rem(-s - 1, 6) + 1]
        end
    else
        started ? SM.shift_plan!(c.xfp, fp, D.x, x) : SM.free_response!(c.xfp, fp, x)
    end
    SM.restrict!(D.y0, R, c.xfp)
    tcert = 0.0
    usedual = c.duals && !o.infeasible[1]
    for (q, I) in enumerate(D.ifs)
        mul!(D.z[q], I.R, view(D.y0, SM.vrange(Pc, I.u)))
        copyto!(c.zsave[q], D.z[q])
        usedual && continue
        for v in (D.lam[q], D.mu[q])
            if started
                copyto!(D.a[q], v)
                @inbounds for j in eachindex(v)
                    v[j] = D.a[q][I.shift[j]]
                end
            else
                fill!(v, 0.0)
            end
        end
    end
    if usedual
        t1 = time_ns()
        # the forces: central, on the coarse level's computer
        coarse_duals27!(c, sc)
        tcert = sec27(time_ns(), t1)
    end
    tw = sec27(time_ns(), t0) - tcert
    snap = isempty(REPRO_DIR27) ? nothing : deepcopy((D = D, x = x, refs = refs, term = term, k = k))   # diagnostics only, outside every run
    info = SM.step!(D, x, refs; terminal = term)
    if snap !== nothing && info.status == :dual_infeasible
        f = joinpath(REPRO_DIR27, "dmpc_state_n$(sc.n)_sig$(sigtag27(sc.sigma))_seed$(sc.seed)_step$(k).jls")
        mkpath(REPRO_DIR27); serialize(f, snap); println("saved the state before a $(info.status) step: ", f); flush(stdout)
    end
    xf = SM.plan(D)
    n = sc.n
    seq = o.seq + tcert + tw + info.t_total
    par = o.par + tcert + tw / n + (info.t_total - info.t_solve) / n + D.t_parallel
    st = info.status
    bad = st in (:primal_infeasible, :dual_infeasible) || !info.feasible
    fz = SM.feasibility(D.fp.program, xf)
    return (u = [copy(v) for v in info.u], U = SM.trajectories(D.fp, xf)[2], infeasible = fill(bad, n),
            unconverged = (!bad && st != :solved) ? 1 : 0, status = string(st) * (o.infeasible[1] ? " (rows infeasible)" : ""),
            iter = info.iter, tc = o.tc + tw + info.t_construct, ts = o.ts + info.t_setup, tv = o.tv + info.t_solve,
            tl = o.tl + info.t_lift, seq = seq, par = par, rounds = 2 + info.iter,
            floats = 6n + (c.duals ? 2 : 1) * SM.floats_per_iteration(D) + D.floats, feas = max(fz.hard, fz.cone), rebuilt = o.rebuilt,
            method = "rows then consensus ADMM")
end

# ---------------------------------------------------------------------------
# Rows with projection and local tracking (a team plan, and each vehicle tracking it)
# ---------------------------------------------------------------------------

"""Discrete LQR gain of `(A, B)` with weights `Q`, `R` (Riccati iteration, E21's dlqr)."""
function dlqr27(A, B, Q, R; iters = 100_000)
    P = copy(Q)
    for _ in 1:iters
        Pn = Q + A' * P * A - A' * P * B * ((R + B' * P * B) \ (B' * P * A))
        norm(Pn - P) <= 1e-12 * norm(P) && (P = Pn; break)
        P = Pn
    end
    return (R + B' * P * B) \ (B' * P * A)
end

"""
rows_proj: each step every row's measured member states are projected onto the
row's agreement subspace {x_i = x_c + (o_i, 0)} (the least-squares restriction:
x_c the mean of x_i - (o_i, 0) over the row, o_i the slot), the rows' reduced
program is solved from the projected states (always feasible: equal inputs keep
a row in formation), its plan lifted, and every vehicle applies its lifted
first input plus a local feedback on its own deviation from its projected state,
u_i = u_i^lift - K_i (xhat_i - xproj_i), radially projected onto its input ball.
K_i is the discrete LQR gain of the vehicle's own dynamics with the weights of
its MPC stage cost: (1 + its number of springs) on the position (tracking and
the incident springs, each of weight 1), its input weight R. The projection is
central (with the rows' solve); the feedback is each vehicle's own.
"""
mutable struct RowsProj27 <: Ctl27
    rows::Central27
    K::Vector{Matrix{Float64}}
    members::Vector{Vector{Int}}
end

"""Project the measured states of the members `M` of one team onto its formation (8): every member at its slot
with the team's mean velocity and mean offset from the slots. Members of a team share their state space; a team
that mixes drones and cars is projected per type (its members of each type)."""
function project27!(xp, sc::Scenario27, x, M)
    for kd in unique(sc.fleet.agents[i].nx for i in M)
        Mk = [i for i in M if sc.fleet.agents[i].nx == kd]
        d = div(kd, 2)
        xc = zeros(kd)
        for i in Mk
            xc .+= x[i]; xc[1:d] .-= sc.slots[i][1:d]
        end
        xc ./= length(Mk)
        for i in Mk
            v = copy(xc); v[1:d] .+= sc.slots[i][1:d]; xp[i] = v
        end
    end
    return xp
end

const GAIN27 = Symbol(get(ENV, "BENCH_GAIN", "team"))      # team: one gain per team and type (Prop. recovery); vehicle: E27's

"""
The local gains of the projected controllers. `team` (default): one gain per team (per type inside a team that
mixes drones and cars), the LQR of its first member's model with the weights (1 + the members' mean number of
springs) C'C and R, so that every member's deviation evolves under the same A - B K_c (Prop. recovery).
`vehicle` (BENCH_GAIN=vehicle, E27's): every vehicle its own degree-scaled LQR gain.
"""
function gains27(sc::Scenario27, members::Vector{Vector{Int}}; mode::Symbol = GAIN27)
    deg = zeros(Int, sc.n)
    for (i, j) in sc.fleet.edges
        deg[i] += 1; deg[j] += 1
    end
    K = Vector{Matrix{Float64}}(undef, sc.n)
    cache = Dict{Tuple{Symbol,Float64},Matrix{Float64}}()
    if mode == :vehicle
        for (i, ag) in enumerate(sc.fleet.agents)
            K[i] = get!(cache, (ag.kind, Float64(deg[i]))) do
                dlqr27(ag.A[1], ag.B[1], (1.0 + deg[i]) * (ag.C' * ag.C) + 1e-9 * I, Matrix(ag.R))
            end
        end
        return K
    end
    for M in members, kd in unique(sc.fleet.agents[i].kind for i in M)
        Mk = [i for i in M if sc.fleet.agents[i].kind == kd]
        ag = sc.fleet.agents[Mk[1]]
        dbar = sum(deg[i] for i in Mk) / length(Mk)
        Kc = get!(cache, (kd, dbar)) do
            dlqr27(ag.A[1], ag.B[1], (1.0 + dbar) * (ag.C' * ag.C) + 1e-9 * I, Matrix(ag.R))
        end
        for i in Mk
            K[i] = Kc
        end
    end
    return K
end

function RowsProj27(sc::Scenario27)
    members = [Int[] for _ in 1:sc.side]
    for i in 1:sc.n
        push!(members[row27(sc, i)], i)
    end
    return RowsProj27(Central27(sc, "rows"), gains27(sc, members), members)
end

function step27!(c::RowsProj27, sc::Scenario27, x, refs, term, k::Int)
    t0 = time_ns()
    xp = Vector{Vector{Float64}}(undef, sc.n)
    for M in c.members
        project27!(xp, sc, x, M)
    end
    tp = sec27(time_ns(), t0)
    o = step27!(c.rows, sc, xp, refs, term, k)
    t1 = time_ns()
    u = Vector{Vector{Float64}}(undef, sc.n)
    for (i, ag) in enumerate(sc.fleet.agents)
        v = o.u[i] - c.K[i] * (x[i] - xp[i])
        r = ag.input.radius; nv = norm(v)
        u[i] = nv > r ? v * (r / nv) : v
    end
    tf = sec27(time_ns(), t1)
    return (u = u, U = o.U, infeasible = o.infeasible, unconverged = o.unconverged, status = o.status, iter = o.iter,
            tc = o.tc + tp, ts = o.ts, tv = o.tv, tl = o.tl + tf, seq = o.seq + tp + tf, par = o.par + tp + tf / sc.n,
            rounds = 2, floats = nfloats27(sc), feas = o.feas, rebuilt = o.rebuilt, method = "rows, projected, local LQR", diag = o.diag)
end

# ---------------------------------------------------------------------------
# One closed loop
# ---------------------------------------------------------------------------

function make27(m::AbstractString, sc::Scenario27, rho)
    (m == "fine" || m == "rows" || m == "rows_abs" || startswith(m, "mix_t")) && return Central27(sc, m)
    m == "rows_proj" && return RowsProj27(sc)
    m == "dec_cv" && return Dec27(sc, false)
    m == "dec_ref" && return Dec27(sc, true)
    mt = match(r"^twolevel(_mix_t\d+|_abs)?(_mu)?_b(\d+)$", m)
    mt === nothing || return TwoLevel27(sc, rho.vehicles, parse(Int, mt.captures[3]); duals = mt.captures[2] !== nothing,
                                        coarse = mt.captures[1] === nothing ? "rows" : mt.captures[1] == "_abs" ? "rows_abs" : mt.captures[1][2:end])
    mm = match(r"^dmpc(rows)?_b(\d+)$", m)
    mm === nothing && error("unknown method $m")
    rows = mm.captures[1] !== nothing
    return Dmpc27(sc, rows, rows ? rho.rows : rho.vehicles, parse(Int, mm.captures[2]))
end

function sizes27(c::Ctl27)
    c isa Central27 && return sizes27(c.F)
    c isa Dec27 && return Dict{String,Any}("agents" => length(c.vs), "local_variables_max" => maximum(SM.c0dim(v.R.program) for v in c.vs))
    c isa RowsProj27 && return sizes27(c.rows.F)
    c isa TwoLevel27 && return merge(sizes27(c.rows.F), Dict{String,Any}("agents" => length(c.D.locals),
                                     "floats_per_iteration" => SM.floats_per_iteration(c.D), "rho" => c.D.rho, "budget" => c.D.budget))
    D = c.D
    return Dict{String,Any}("agents" => length(D.locals), "interfaces" => length(D.ifs), "floats_per_iteration" => SM.floats_per_iteration(D),
                            "local_variables_max" => maximum(length(L.q) for L in D.locals), "rho" => D.rho, "budget" => D.budget)
end

"""
One method's closed loop of `steps` steps from E26's start; the per-run record
with its per-step records. A method name ending in `_fbdec` falls back to
decentralized MPC (dec_cv) at a step where its program is infeasible: every
vehicle of that program applies its own decentralized plan, and the fallback's
time is added to the step (sequential and parallel alike). Otherwise the
fallback is E25's: the previous plan shifted one step.
"""
function run_method27(m::AbstractString, sc::Scenario27, rho; steps::Int = STEPS27)
    fbdec = endswith(m, "_fbdec")
    base = fbdec ? m[1:(end-6)] : m
    la0 = loadavg27()
    GC.gc()
    tb = @elapsed (c = make27(base, sc, rho); fb = fbdec ? Dec27(sc, false) : nothing)
    GC.gc()
    x = start27(sc)
    rec = Dict{String,Any}[]; cost = 0.0; prevU = nothing; applied = Vector{Vector{Vector{Float64}}}()
    for k in 0:(steps-1)
        refs, term = references27(sc, k * sc.h)
        o = step27!(c, sc, x, refs, term, k)
        u = o.u; U = o.U
        seq, par = o.seq, o.par
        nfb = 0; ndec = 0
        if fb !== nothing && any(o.infeasible)
            f = step27!(fb, sc, x, refs, term, k)
            seq += f.seq; par += f.par
            for i in 1:sc.n
                o.infeasible[i] || continue
                ndec += 1; u[i] = f.u[i]; U[i] = f.U[i]
            end
        else
            for i in 1:sc.n
                (o.infeasible[i] && prevU !== nothing) || continue
                nfb += 1
                u[i] = prevU[i][:, min(2, size(prevU[i], 2))]
                U[i] = hcat(prevU[i][:, 2:end], prevU[i][:, end])
            end
        end
        uc, viol = clip27(sc, u)
        r = Dict{String,Any}("step" => k, "status" => o.status, "iter" => o.iter, "t_construct" => o.tc, "t_setup" => o.ts,
            "t_solve" => o.tv, "t_lift" => o.tl, "t_seq" => seq, "t_par" => par, "rounds" => o.rounds, "floats" => o.floats,
            "infeasible_agents" => count(o.infeasible), "fallback_agents" => nfb + ndec, "fallback_dec_agents" => ndec,
            "unconverged" => o.unconverged, "feas" => o.feas, "input_violation_raw" => viol, "rebuilt" => o.rebuilt,
            "stage_cost" => stage_cost27(sc, x, uc, refs), "formation_error" => formation_error27(sc, x))
        hasproperty(o, :diag) && merge!(r, o.diag)
        cost += r["stage_cost"]
        push!(rec, r); push!(applied, uc)
        prevU = U
        x = plant27(sc, x, uc, k)
    end
    refs, _ = references27(sc, steps * sc.h)
    cost += stage_cost27(sc, x, nothing, refs)
    out = Dict{String,Any}("method" => m, "closed_loop_cost" => cost, "steps" => rec, "build_seconds" => tb, "sizes" => sizes27(c),
                           "fallback" => fbdec ? "decentralized MPC (dec_cv) at the step, its time added" :
                                                 "the previous plan shifted one step (E25)")
    out["applied"] = applied                    # in memory only: compared with coordinated MPC's in run_seed27
    c isa Central27 && (out["solver_methods"] = c.methods; out["merge_rebuilt"] = c.F.G.rebuilt; out["merged_cones"] = c.F.G.merged_cones)
    Fc = c isa Central27 ? c.F : c isa RowsProj27 ? c.rows.F : nothing
    if Fc !== nothing
        out["red_path"] = Fc.path; out["stepop_fallbacks"] = Fc.fallbacks
    end
    out["loadavg"] = [la0, loadavg27()]
    c = nothing
    return summarize_run27!(out)
end

stats27(v) = isempty(v) ? Dict{String,Any}() :
    Dict{String,Any}("median" => median(v), "min" => minimum(v), "max" => maximum(v), "mean" => mean(v), "n" => length(v))

function summarize_run27!(out)
    rec = out["steps"]
    col(key) = [Float64(r[key]) for r in rec]
    for key in ("t_construct", "t_setup", "t_solve", "t_lift", "t_seq", "t_par", "rounds", "floats", "iter")
        v = col(key)
        out[key] = stats27(length(v) > 1 ? v[2:end] : v)            # after the first step
        out[key*"_first"] = v[1]
    end
    out["infeasible_steps"] = count(r -> r["infeasible_agents"] > 0, rec)
    out["infeasible_agent_steps"] = sum(r["infeasible_agents"] for r in rec)
    out["fallback_agent_steps"] = sum(r["fallback_agents"] for r in rec)
    out["fallback_steps"] = count(r -> r["fallback_agents"] > 0, rec)
    out["unconverged_steps"] = count(r -> r["unconverged"] > 0, rec)
    out["input_violation_raw"] = maximum(col("input_violation_raw"))
    used = [Float64(r["feas"]) for r in rec if r["infeasible_agents"] == 0]       # plans that were applied
    out["feas_max"] = isempty(used) ? 0.0 : maximum(used)
    out["feas_max_all"] = maximum(col("feas"))
    out["mean_formation_error"] = mean(col("formation_error"))
    out["rebuilt_steps"] = count(r -> r["rebuilt"], rec)
    for key in ("stepop_diff", "stepop_input_diff", "stepop_copy_err", "stepop_copy_bound", "merge_spread")
        v = [Float64(r[key]) for r in rec if haskey(r, key)]
        isempty(v) || (out[key*"_max"] = maximum(v))
    end
    out["stepop_off_steps"] = count(r -> get(r, "stepop_off", false), rec)
    return out
end

# ---------------------------------------------------------------------------
# Step 0: the gap of rows (gap_bounds), every method at the same state
# ---------------------------------------------------------------------------

function step0_gap27(sc::Scenario27)
    out = Dict{String,Any}()
    F = Form27(sc, "rows")
    P = F.pp.P; Rtop = F.chain[end]
    tf = @elapsed fine0 = SM.solve(P)
    tr = @elapsed red0 = SM.solve(Rtop)
    out["fine_status"] = string(fine0.status); out["reduced_status"] = string(red0.status)
    out["J_fine"] = fine0.J; out["J_reduced"] = red0.J; out["fine_solve_seconds"] = tf; out["reduced_solve_seconds"] = tr
    if SM.isoptimal(fine0) && SM.isoptimal(red0)
        tg = @elapsed gb = SM.gap_bounds(P, Rtop, red0; fine_solution = fine0)
        J = abs(fine0.J)
        out["gap_lower"] = gb.lower; out["gap"] = gb.gap; out["gap_upper"] = gb.upper; out["gap_residual"] = gb.residual
        out["lower_rel"] = gb.lower / J; out["gap_rel"] = gb.gap / J; out["upper_rel"] = gb.upper / J; out["gap_seconds"] = tg
    end
    return out
end

# ---------------------------------------------------------------------------
# rho of distributed MPC: tuned once per fleet size (E25's rule)
# ---------------------------------------------------------------------------

function tune27()
    BLAS.set_num_threads(1)
    sc = Scenario27(SIDE27; seed = 1, sigma = TUNE_SIGMA27, kick = 0.0)
    x0 = start27(sc); refs, term = references27(sc, 0.0)
    println("E27 tune: n = $(sc.n), sigma $(TUNE_SIGMA27), seed 1, step 0, cold, maxit $(TUNE_MAXIT27)"); flush(stdout)
    out = Dict{String,Any}("n" => sc.n, "sigma" => TUNE_SIGMA27, "seed" => 1, "maxit" => TUNE_MAXIT27, "rhos" => RHOS27,
                           "criterion" => "iterations to Boyd's tolerances (eps_abs 1e-6, eps_rel 1e-4) from a cold start at step 0")
    which = split(get(ENV, "BENCH_TUNE_TEAMS", "rows,vehicles"), ",")
    for (name, teams) in (("rows", rowteams27(sc)), ("vehicles", collect(1:sc.n)))
        name in which || continue
        tab = Dict{String,Any}()
        for rho in RHOS27
            GC.gc()
            D = local_accuracy27!(SM.DistributedMPC(sc.fleet, teams; rho = rho, warm = :cold, maxit = TUNE_MAXIT27))
            t = @elapsed info = SM.step!(D, x0, refs; terminal = term)
            tab[string(rho)] = Dict{String,Any}("iterations" => info.iter, "converged" => D.converged, "status" => string(info.status),
                                                "seconds" => t)
            @printf("  %-8s rho %5.1f  iterations %5d  converged %s  %.1f s\n", name, rho, info.iter, D.converged, t); flush(stdout)
        end
        conv = [r for r in RHOS27 if tab[string(r)]["converged"]]
        best = isempty(conv) ? RHOS27[argmin([tab[string(r)]["iterations"] for r in RHOS27])] :
               conv[argmin([tab[string(r)]["iterations"] for r in conv])]
        out[name] = best; out["table_"*name] = tab
    end
    out["meta"] = meta27()
    write27(joinpath(PARTDIR27, "e27_rho_n$(sc.n).json"), out)
end

function rho27(n::Int)
    if haskey(ENV, "BENCH_RHO_VEHICLES") && haskey(ENV, "BENCH_RHO_ROWS")
        return (vehicles = parse(Float64, ENV["BENCH_RHO_VEHICLES"]), rows = parse(Float64, ENV["BENCH_RHO_ROWS"]), source = "given")
    end
    f = joinpath(PARTDIR27, "e27_rho_n$(n).json")
    isfile(f) || error("no rho for n = $n: run BENCH_MODE=tune first, or give BENCH_RHO_VEHICLES and BENCH_RHO_ROWS")
    d = JSON.parsefile(f)
    return (vehicles = Float64(d["vehicles"]), rows = Float64(get(d, "rows", NaN)), source = f)     # rows: not tuned when DMPC over rows is not run
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function meta27()
    sm = pkgdir(SM)
    rev = try readchomp(`git -C $sm rev-parse --short HEAD`) catch
        f = joinpath(sm, ".synced_rev"); isfile(f) ? first(strip(read(f, String)), 7) : "unknown"
    end
    dirty = try !isempty(readchomp(`git -C $sm status --porcelain --untracked-files=no -- src`)) catch; false end
    return Dict{String,Any}("julia" => string(VERSION), "host" => gethostname(), "threads" => Threads.nthreads(),
        "blas_threads" => BLAS.get_num_threads(), "cpu" => Sys.cpu_info()[1].model, "teammpc_rev" => rev,
        "teammpc_dirty" => dirty, "teammpc_path" => sm, "slurm_job" => get(ENV, "SLURM_JOB_ID", ""),
        "affinity" => try readchomp(`taskset -cp $(getpid())`) catch; "" end, "red_path" => RED_PATH27, "red_warm" => RED_WARM27,
        "slurm_cpus_on_node" => get(ENV, "SLURM_CPUS_ON_NODE", ""), "node_exclusive" => get(ENV, "BENCH_EXCLUSIVE", "0") == "1",
        "job_load_start" => get(ENV, "BENCH_JOB_LOAD", ""))      # /proc/loadavg when the job started (the job script sets it)
end

jsonable27(x::AbstractDict) = Dict{String,Any}(string(k) => jsonable27(v) for (k, v) in x)
jsonable27(x::AbstractVector) = [jsonable27(v) for v in x]
jsonable27(x::Tuple) = [jsonable27(v) for v in x]
jsonable27(x::AbstractFloat) = isfinite(x) ? Float64(x) : (isnan(x) ? "NaN" : (x > 0 ? "Inf" : "-Inf"))
jsonable27(x::Symbol) = string(x)
jsonable27(x::NamedTuple) = jsonable27(Dict(pairs(x)))
jsonable27(x) = x

write27(path, d) = (mkpath(dirname(path)); open(io -> JSON.json(io, jsonable27(d); pretty = 1), path, "w"); println("wrote ", path); flush(stdout))

sigtag27(s) = replace(@sprintf("%g", s), "." => "p")
tag27(sc) = "n$(sc.n)_sig$(sigtag27(sc.sigma))_kick$(sigtag27(sc.kick))_seed$(sc.seed)"

"""Compile every code path on a 4 x 4 fleet (discarded)."""
function warmup27()
    sc = Scenario27(4; seed = 1, sigma = 0.1, kick = KICK27, steps = max(WARMUP27, 1))
    rho = (vehicles = 1.0, rows = 1.0)
    for m in METHODS27
        run_method27(m, sc, rho; steps = WARMUP27)
    end
    GAP27 && step0_gap27(sc)
end

function run_seed27(sigma::Float64, seed::Int, rho)
    sc = Scenario27(SIDE27; seed = seed, sigma = sigma)
    la0 = loadavg27()
    res = Dict{String,Any}()
    for m in METHODS27
        tw = @elapsed r = run_method27(m, sc, rho)
        r["wall_seconds"] = tw
        res[m] = r
        @printf("  %-12s cost %.8g  seq %9.3f ms  par %9.3f ms  rounds %3d  floats %8d  infeas %2d  unconv %2d  feas %.1e  build %.1fs  wall %.0fs\n",
                m, r["closed_loop_cost"], 1e3 * r["t_seq"]["median"], 1e3 * r["t_par"]["median"], round(Int, r["rounds"]["median"]),
                round(Int, r["floats"]["median"]), r["infeasible_steps"], r["unconverged_steps"], r["feas_max"], r["build_seconds"], tw)
        flush(stdout)
    end
    if haskey(res, "fine")
        base = res["fine"]["closed_loop_cost"]
        for (m, r) in res
            r["cost_ratio"] = r["closed_loop_cost"] / base
        end
        @printf("  ratios: %s\n", join([@sprintf("%s %.5f", m, res[m]["cost_ratio"]) for m in METHODS27], ", "))
        # applied inputs against coordinated MPC's, largest over steps and vehicles (absolute, and over the smaller bound)
        uf = res["fine"]["applied"]
        for (m, r) in res
            d = maximum(maximum(abs, r["applied"][k][i] - uf[k][i]) for k in eachindex(uf) for i in eachindex(uf[k]))
            r["input_diff_max"] = d; r["input_diff_rel"] = d / min(UMAX_LIGHT27, UMAX_HEAVY27)
        end
    end
    for (_, r) in res
        delete!(r, "applied")
    end
    gap = Dict{String,Any}()
    if GAP27
        GC.gc()
        gap = step0_gap27(sc)
        @printf("  rows at step 0: gap/J* %.3e  [lower %.3e, upper %.3e]\n", get(gap, "gap_rel", NaN), get(gap, "lower_rel", NaN),
                get(gap, "upper_rel", NaN))
    end
    la1 = loadavg27()
    return Dict{String,Any}("experiment" => "E27-pareto-part", "side" => SIDE27, "n" => sc.n, "sigma" => sigma, "kick" => sc.kick,
        "seed" => seed, "steps" => STEPS27, "H" => sc.H, "h" => sc.h, "methods" => METHODS27, "rho" => Dict(pairs(rho)),
        "results" => res, "step0_rows" => gap, "loadavg" => [la0, la1], "meta" => meta27(), "warmup_steps" => WARMUP27,
        "settings" => Dict(pairs(SM_SETTINGS27)), "umax_light" => UMAX_LIGHT27, "umax_heavy" => UMAX_HEAVY27, "merge_tol" => MERGE_TOL27)
end

function main27()
    MODE27 == "merge" && return merge27()
    BLAS.set_num_threads(1)
    MODE27 == "tune" && return tune27()
    MODE27 == "run" || error("unknown BENCH_MODE $(MODE27)")
    println("E27: side $SIDE27 (n = $(SIDE27^2)), sigmas $SIGMAS27, kick $KICK27, seeds $SEEDS27, methods $METHODS27, ",
            "red path $RED_PATH27, red warm $RED_WARM27")
    println("load ", loadavg27()); flush(stdout)
    rho = rho27(SIDE27^2)
    @printf("rho: vehicles %g, rows %g (%s)\n", rho.vehicles, rho.rows, rho.source)
    t = @elapsed warmup27()
    @printf("warm-up %.1f s\n", t); flush(stdout)
    for sigma in SIGMAS27, seed in SEEDS27
        println("sigma $sigma, seed $seed"); flush(stdout)
        part = run_seed27(sigma, seed, rho)
        sc = Scenario27(SIDE27; seed = seed, sigma = sigma)
        write27(joinpath(PARTDIR27, "e27_run_$(tag27(sc))$(PARTTAG27).json"), part)
    end
end

# ---------------------------------------------------------------------------
# Merge: parts -> results/e27_pareto.json
# ---------------------------------------------------------------------------

fnum27(x) = x === nothing ? NaN : x isa AbstractString ? parse(Float64, x) : Float64(x)

"""
Non-dominated methods of `pts` (method => (cost ratio, resource)): no other is
at most as costly and as expensive, and better in one. Cost ratios within
`tol` = 1e-4 are ties: near-optimal closed loops differ by that much from
seed to seed (some below coordinated MPC's), which is not a difference in the
controller's quality.
"""
function front27(pts::Dict{String,Tuple{Float64,Float64}}; tol = FRONT_TOL27)
    out = String[]
    for (m, (c, r)) in pts
        dom = any(o != m && (co <= c + tol) && (ro <= r) && ((co < c - tol) || (ro < r)) for (o, (co, ro)) in pts)
        dom || push!(out, m)
    end
    return sort(out; by = m -> pts[m][2])
end

"""Spearman's rank correlation."""
function spearman27(x, y)
    rk(v) = (p = sortperm(v); r = similar(v, Float64); r[p] = 1:length(v); r)
    return cor(rk(x), rk(y))
end

function merge27()
    files = sort(filter(f -> startswith(f, "e27_run_") && endswith(f, ".json"), readdir(PARTDIR27)))
    isempty(files) && error("no parts in $PARTDIR27")
    parts = [JSON.parsefile(joinpath(PARTDIR27, f)) for f in files]
    settings = Dict{String,Any}()
    revs = String[]; hosts = String[]; cpus = String[]; jobs = String[]; threads = Int[]; blas = Int[]; paths = String[]; warms = String[]
    jobinfo = Any[]
    for (f, p) in zip(files, parts)
        key = "n$(p["n"])_sig$(sigtag27(fnum27(p["sigma"])))_kick$(sigtag27(fnum27(p["kick"])))"
        S = get!(settings, key, Dict{String,Any}("n" => p["n"], "sigma" => fnum27(p["sigma"]), "kick" => fnum27(p["kick"]),
                                                  "runs" => Any[], "parts" => String[], "rho" => p["rho"]))
        push!(S["runs"], p); push!(S["parts"], f)
        m = p["meta"]
        push!(revs, m["teammpc_rev"]); push!(hosts, m["host"]); push!(cpus, m["cpu"]); push!(jobs, m["slurm_job"])
        push!(threads, m["threads"]); push!(blas, m["blas_threads"]); push!(paths, m["red_path"]); push!(warms, m["red_warm"])
        push!(jobinfo, Dict{String,Any}("part" => f, "host" => m["host"], "job" => m["slurm_job"], "exclusive" => get(m, "node_exclusive", false),
                                        "cpus_on_node" => get(m, "slurm_cpus_on_node", ""), "job_load_start" => get(m, "job_load_start", ""),
                                        "loadavg_part" => p["loadavg"]))
    end
    out = Dict{String,Any}("experiment" => "E27-pareto", "parts" => files, "teammpc_revs" => unique(revs), "hosts" => unique(hosts),
        "cpus" => unique(cpus), "jobs" => sort(unique(jobs)), "threads" => unique(threads), "blas_threads" => unique(blas),
        "red_paths" => unique(paths), "red_warms" => unique(warms), "steps" => parts[1]["steps"], "H" => parts[1]["H"], "h" => parts[1]["h"],
        "settings_solver" => parts[1]["settings"], "umax_light" => parts[1]["umax_light"], "umax_heavy" => parts[1]["umax_heavy"],
        "node_exclusive" => unique([x["exclusive"] for x in jobinfo]), "part_nodes" => jobinfo)
    length(out["teammpc_revs"]) == 1 || @warn "parts were timed against several TeamMPC commits: $(out["teammpc_revs"])"
    scatter = Any[]
    determinism = 0.0; ndet = 0; excluded = Any[]
    for (key, S) in settings
        # parts of the same seed (a later run of more methods) are combined; a method run twice must agree exactly
        byseed = Dict{Int,Any}()
        for r in S["runs"]
            sd = r["seed"]
            if !haskey(byseed, sd)
                byseed[sd] = r; r["metas"] = [r["meta"]]
                continue
            end
            r0 = byseed[sd]
            push!(r0["metas"], r["meta"])
            for (m, x) in r["results"]
                if haskey(r0["results"], m)
                    a, b = fnum27(r0["results"][m]["closed_loop_cost"]), fnum27(x["closed_loop_cost"])
                    determinism = max(determinism, abs(a - b) / abs(a)); ndet += 1
                else
                    r0["results"][m] = x
                end
            end
            isempty(r0["step0_rows"]) && (r0["step0_rows"] = r["step0_rows"])
        end
        S["runs"] = sort(collect(values(byseed)); by = r -> r["seed"])
        for r in S["runs"]
            haskey(r["results"], "fine") || continue
            base = fnum27(r["results"]["fine"]["closed_loop_cost"])
            for (_, x) in r["results"]
                x["cost_ratio"] = fnum27(x["closed_loop_cost"]) / base
            end
        end
        S["seeds"] = [r["seed"] for r in S["runs"]]
        allunique(S["seeds"]) || error("duplicate seeds in $key")
        # method-runs in which a solver reported a strictly convex local QP dual infeasible (TeamMPC ce71be2, the
        # warm-started ADMM-to-IPM crossover; deterministic, so a rerun reproduces it): left out of the summaries
        for r in S["runs"], (m, x) in r["results"]
            bad = [st["step"] for st in x["steps"] if startswith(st["status"], "dual_infeasible")]
            isempty(bad) && continue
            x["excluded"] = true
            push!(excluded, Dict{String,Any}("setting" => key, "seed" => r["seed"], "method" => m, "steps" => bad,
                                             "cost_ratio" => get(x, "cost_ratio", nothing)))
        end
        methods = unique(reduce(vcat, [collect(keys(r["results"])) for r in S["runs"]]))
        M = Dict{String,Any}()
        for m in methods
            rs = [r["results"][m] for r in S["runs"] if haskey(r["results"], m) && !get(r["results"][m], "excluded", false)]
            isempty(rs) && continue
            d = Dict{String,Any}("seeds" => length(rs), "excluded_seeds" => count(r -> haskey(r["results"], m) && get(r["results"][m], "excluded", false), S["runs"]))
            all(x -> haskey(x, "cost_ratio"), rs) && (d["cost_ratio"] = stats27([fnum27(x["cost_ratio"]) for x in rs]))
            for q in ("t_seq", "t_par", "t_construct", "t_setup", "t_solve", "t_lift", "rounds", "floats", "iter")
                v = [fnum27(x[q]["median"]) for x in rs]
                d[q] = stats27(v)                                           # over seeds of each seed's median step
                d[q*"_max"] = maximum(fnum27(x[q]["max"]) for x in rs)
                d[q*"_first"] = stats27([fnum27(x[q*"_first"]) for x in rs])
            end
            for q in ("infeasible_steps", "infeasible_agent_steps", "fallback_agent_steps", "fallback_steps", "unconverged_steps", "rebuilt_steps")
                d[q] = sum(Int(x[q]) for x in rs)
            end
            d["input_violation_raw"] = maximum(fnum27(x["input_violation_raw"]) for x in rs)
            all(x -> haskey(x, "input_diff_rel"), rs) && (d["input_diff_rel"] = maximum(fnum27(x["input_diff_rel"]) for x in rs);
                                                           d["input_diff_max"] = maximum(fnum27(x["input_diff_max"]) for x in rs))
            d["feas_max"] = maximum(fnum27(x["feas_max"]) for x in rs)
            d["formation_error"] = stats27([fnum27(x["mean_formation_error"]) for x in rs])
            d["build_seconds"] = stats27([fnum27(x["build_seconds"]) for x in rs])
            d["sizes"] = rs[1]["sizes"]; d["fallback"] = rs[1]["fallback"]
            haskey(rs[1], "solver_methods") && (d["solver_methods"] = [x["solver_methods"] for x in rs])
            haskey(rs[1], "red_path") && (d["red_paths"] = unique([x["red_path"] for x in rs]);
                                          d["stepop_fallbacks"] = sum(Int(x["stepop_fallbacks"]) for x in rs))
            for q in ("stepop_diff_max", "stepop_input_diff_max", "stepop_copy_err_max", "stepop_copy_bound_max", "merge_spread_max")
                v = [fnum27(x[q]) for x in rs if haskey(x, q)]
                isempty(v) || (d[q] = maximum(v))
            end
            any(x -> haskey(x, "stepop_off_steps"), rs) && (d["stepop_off_steps"] = sum(Int(get(x, "stepop_off_steps", 0)) for x in rs))
            any(x -> haskey(x, "loadavg"), rs) && (d["loadavg_1min_max"] = maximum(maximum(fnum27(l[1]) for l in x["loadavg"] if !isempty(l)) for x in rs if haskey(x, "loadavg")))
            M[m] = d
        end
        S["methods"] = M
        # the fronts at this setting: median cost ratio against median parallel time, sequential time, rounds
        if haskey(M, "fine")
            for (fname, q) in (("parallel", "t_par"), ("sequential", "t_seq"), ("rounds", "rounds"), ("floats", "floats"))
                pts = Dict{String,Tuple{Float64,Float64}}(m => (d["cost_ratio"]["median"], d[q]["median"]) for (m, d) in M if haskey(d, "cost_ratio"))
                S["front_"*fname] = front27(pts)
            end
        end
        # rows: the gap at step 0 against the realized cost ratio
        G = Any[]
        for r in S["runs"]
            g = r["step0_rows"]
            haskey(g, "gap_rel") || continue
            row = Dict{String,Any}("seed" => r["seed"], "lower_rel" => fnum27(g["lower_rel"]), "gap_rel" => fnum27(g["gap_rel"]),
                                   "upper_rel" => fnum27(g["upper_rel"]))
            haskey(r["results"], "rows") && haskey(r["results"]["rows"], "cost_ratio") && (row["ratio"] = fnum27(r["results"]["rows"]["cost_ratio"]))
            push!(G, row)
            haskey(row, "ratio") && push!(scatter, merge(row, Dict{String,Any}("n" => S["n"], "sigma" => S["sigma"], "kick" => S["kick"])))
        end
        S["gaps_rows"] = G
        if !isempty(G)
            S["gap_rows"] = Dict(q => stats27([x[q] for x in G]) for q in ("lower_rel", "gap_rel", "upper_rel"))
        end
        for r in S["runs"], (_, x) in r["results"]
            delete!(x, "steps")                     # per-step records stay in the parts
        end
        S["loadavg"] = [Dict("seed" => r["seed"], "load" => r["loadavg"]) for r in S["runs"]]
        S["metas"] = reduce(vcat, [r["metas"] for r in S["runs"]])
        delete!(S, "runs")
    end
    out["settings"] = settings
    out["front_cost_tie"] = FRONT_TOL27
    out["excluded"] = excluded
    out["excluded_reason"] = "a DistributedMPC local QP (strictly convex) reported dual infeasible by TeamMPC's warm-started ADMM-to-IPM crossover; the same QP solves cold"
    out["rerun_max_rel_diff"] = determinism; out["rerun_count"] = ndet       # a method run in two parts of one seed: closed-loop costs
    # does the offline gap predict the loss? rows, every seed and sigma without kicks
    sc = [x for x in scatter if x["kick"] == 0 && x["sigma"] > 0]
    out["gap_scatter"] = scatter
    if length(sc) >= 3
        lo = [x["lower_rel"] for x in sc]; gp = [x["gap_rel"] for x in sc]; ex = [x["ratio"] - 1 for x in sc]
        pos = [k for k in eachindex(sc) if lo[k] > 0 && ex[k] > 0]
        out["gap_vs_realized"] = Dict{String,Any}("points" => length(sc),
            "spearman_lower" => spearman27(lo, ex), "spearman_gap" => spearman27(gp, ex),
            "pearson_log_lower" => length(pos) >= 3 ? cor(log.(lo[pos]), log.(ex[pos])) : NaN,
            "pearson_log_gap" => length(pos) >= 3 ? cor(log.(gp[pos]), log.(ex[pos])) : NaN,
            "excess_over_lower" => stats27([ex[k] / lo[k] for k in pos]), "excess_over_gap" => stats27([ex[k] / gp[k] for k in pos]),
            "positive_points" => length(pos))
    end
    out["numbers"] = numbers27(out)
    path = get(ENV, "BENCH_OUT", joinpath(ROOT27, "results", "e27_pareto.json"))
    write27(path, out)
    return out
end

const SIZEWORD27 = Dict(64 => "SixtyFour", 256 => "TwoFiftySix", 1024 => "OneK", 4096 => "FourK")
const SIGWORD27 = Dict(0.0 => "SigZero", 0.01 => "SigA", 0.03 => "SigB", 0.1 => "SigC", 0.3 => "SigD", 1.0 => "SigE")
const KICKWORD27 = Dict(0.0 => "", 0.02 => "Kick", 0.01 => "KickLow", 0.05 => "KickHigh")
const METHWORD27 = Dict("fine" => "Fine", "rows" => "Rows", "mix_t2" => "MixTwo", "mix_t3" => "MixThree", "dec_cv" => "DecCv",
    "dec_ref" => "DecRef", "dmpc_b1" => "DmpcBOne", "dmpc_b5" => "DmpcBFive", "dmpc_b20" => "DmpcBTwenty",
    "dmpcrows_b1" => "DmpcRowsBOne", "dmpcrows_b5" => "DmpcRowsBFive", "rows_fbdec" => "RowsFbDec", "mix_t2_fbdec" => "MixTwoFbDec",
    "mix_t3_fbdec" => "MixThreeFbDec", "dmpcrows_b5_fbdec" => "DmpcRowsBFiveFbDec", "twolevel_b1" => "TwoLevelBOne",
    "twolevel_b5" => "TwoLevelBFive", "twolevel_mix_t2_b1" => "TwoLevelMixBOne", "twolevel_mix_t2_b5" => "TwoLevelMixBFive",
    "twolevel_abs_b1" => "TwoLevelAbsBOne", "twolevel_abs_b5" => "TwoLevelAbsBFive",
    "twolevel_mu_b1" => "TwoLevelMuBOne", "twolevel_mu_b5" => "TwoLevelMuBFive", "twolevel_abs_mu_b1" => "TwoLevelAbsMuBOne",
    "twolevel_abs_mu_b5" => "TwoLevelAbsMuBFive", "rows_proj" => "RowsProj", "rows_abs" => "RowsAbs", "rows_abs_fbdec" => "RowsAbsFbDec")

"""The flat numbers the \\cnPar macros read (numbers_pareto.jl): <Size><Sigma><Kick>_<Method>_<quantity>."""
function numbers27(out)
    N = Dict{String,Any}()
    feas = 0.0; viol = 0.0; ones_dev = 0.0
    for (_, S) in out["settings"]
        haskey(SIZEWORD27, S["n"]) && haskey(SIGWORD27, S["sigma"]) && haskey(KICKWORD27, S["kick"]) || continue
        tag = SIZEWORD27[S["n"]] * SIGWORD27[S["sigma"]] * KICKWORD27[S["kick"]]
        N[tag*"_seeds"] = length(S["seeds"])
        for (m, d) in S["methods"]
            haskey(METHWORD27, m) || continue
            mk = tag * "_" * METHWORD27[m]
            if haskey(d, "cost_ratio")
                N[mk*"_ratio_med"] = d["cost_ratio"]["median"]; N[mk*"_ratio_min"] = d["cost_ratio"]["min"]
                N[mk*"_ratio_max"] = d["cost_ratio"]["max"]
            end
            N[mk*"_seq_ms"] = 1e3 * d["t_seq"]["median"]; N[mk*"_par_ms"] = 1e3 * d["t_par"]["median"]
            N[mk*"_seq_max_ms"] = 1e3 * d["t_seq_max"]; N[mk*"_par_max_ms"] = 1e3 * d["t_par_max"]   # worst step after the first, every seed
            N[mk*"_rounds"] = d["rounds"]["median"]; N[mk*"_floats"] = d["floats"]["median"]
            N[mk*"_infeasible"] = d["infeasible_steps"]; N[mk*"_unconverged"] = d["unconverged_steps"]
            feas = max(feas, d["feas_max"]); viol = max(viol, d["input_violation_raw"])
            m == "fine" && haskey(d, "cost_ratio") && (ones_dev = max(ones_dev, abs(d["cost_ratio"]["max"] - 1), abs(d["cost_ratio"]["min"] - 1)))
        end
        if haskey(S, "gap_rows")
            N[tag*"_rows_lower_med"] = S["gap_rows"]["lower_rel"]["median"]; N[tag*"_rows_gap_med"] = S["gap_rows"]["gap_rel"]["median"]
        end
        haskey(S, "front_parallel") && (N[tag*"_front_parallel"] = join(S["front_parallel"], ","))
        haskey(S, "front_parallel") && (N[tag*"_rows_on_front"] = "rows" in S["front_parallel"] ? 1 : 0)
    end
    N["feas_max"] = feas; N["input_violation_raw_max"] = viol; N["fine_ratio_dev"] = ones_dev
    haskey(out, "rerun_max_rel_diff") && (N["rerun_max_rel_diff"] = out["rerun_max_rel_diff"])
    N["excluded_runs"] = length(out["excluded"]); N["excluded_steps"] = sum((length(x["steps"]) for x in out["excluded"]); init = 0)
    if haskey(out, "gap_vs_realized")
        g = out["gap_vs_realized"]
        N["gap_spearman_lower"] = g["spearman_lower"]; N["gap_spearman_gap"] = g["spearman_gap"]; N["gap_points"] = g["points"]
    end
    N["steps"] = out["steps"]; N["H"] = out["H"]
    return N
end

if abspath(PROGRAM_FILE) == @__FILE__
    BLAS.set_num_threads(1)
    main27()
end
