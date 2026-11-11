# team_mpc.jl: the paper's method end to end (Algorithm 1 and the certificate), at small size.
#
#   julia --project=. examples/team_mpc.jl
#
# Part 1: a 16 x 16 grid of quadrotors (odd rows) and ground vehicles (even rows), every row tracking its
# own centre trajectory plus its slot (coherent rows). Colour refinement finds the rows from the data
# classes; team MPC applies the inputs of coordinated MPC (Thm. 1) on a QP 16 times smaller.
#
# Part 2: the same kind of fleet with irregular formation weights, every vehicle tracking the formation
# centre plus its slot (coherent across the fleet). The exact teams fragment; quasi-stable colouring gives
# coarser, lossy teams; the certificate (Thm. 2) bounds their gap from the team solve alone.

using TeamMPC, LinearAlgebra, Printf, Random, Statistics

function closed_loop(ctrl, fl, sc; steps = 20)
    x = formation_start(sc); us = Vector{Vector{Vector{Float64}}}(); ts = Float64[]
    for k in 0:(steps-1)
        refs, term = references(sc, k * sc.h)
        t = @elapsed out = step!(ctrl, x, refs; terminal = term)
        u = deepcopy(out isa StepInfo ? out.u : out)
        push!(us, u); push!(ts, t)
        x = plant_step(fl, x, u)
    end
    return us, ts[2:end]
end

println("Part 1: lossless teams on a 16 x 16 grid")
sc = GridScenario(rows = 16, cols = 16, H = 10, coherence = :rows)
fl = fleet(sc)
rowclass = [2 * (div(i - 1, sc.cols) + 1) + (agent_kind(sc, i) == :quadrotor ? 0 : 1) for i in 1:nagents(sc)]
teams1 = lossless_teams(fl; classes = rowclass)       # the data classes: one per row (each row its own reference)
@printf("  %d vehicles, %d teams (the rows: %s)\n", nagents(fl), maximum(teams1), teams1 == canonical_partition(row_teams(sc)))
tm = TeamController(fl, teams1; offsets = slot_offsets(fl, slots(sc)))
co = MPCController(fl, full_condensing(); certify = false)
ut, tt = closed_loop(tm, fl, sc)
uc, tc = closed_loop(co, fl, sc)
d = maximum(maximum(norm(a - b, Inf) for (a, b) in zip(x, y)) for (x, y) in zip(ut, uc))
@printf("  largest input difference, team vs coordinated MPC: %.1e\n", d)
@printf("  ms per step (median): team %.2f, coordinated %.2f, ratio %.0f\n", 1e3median(tt), 1e3median(tc), median(tc) / median(tt))

println("\nPart 2: lossy teams with a certificate")
sc2 = GridScenario(rows = 6, cols = 6, H = 8, coherence = :fleet, umax_scale = 0.5)
base = fleet(sc2)
rng = Xoshiro(1)
W = [1.0 + 0.4 * (rand(rng) - 0.5) for _ in base.edges, _ in 1:base.H]       # irregular weights, constant in time
W = repeat(W[:, 1], 1, base.H)
fl2 = Fleet(base.agents, base.edges; H = base.H, targets = base.targets, weights = W)
D2 = slot_offsets(fl2, slots(sc2))
x0 = formation_start(sc2); refs, term = references(sc2)
co2 = MPCController(fl2, full_condensing(); certify = false, eps_abs = 1e-9, eps_rel = 1e-9)
for (name, lab) in (("lossless", lossless_teams(fl2)), ("q = 0.2", quasi_stable_teams(fl2; q = 0.2)),
                    ("q = 0.5", quasi_stable_teams(fl2; q = 0.5)), ("data classes", data_classes(fl2)))
    t = TeamController(fl2, lab; offsets = D2, eps_abs = 1e-9, eps_rel = 1e-9)
    step!(t, x0, refs; terminal = term)
    cert, Jt, cq = certificate(t, x0, refs; terminal = term)
    step!(co2, project(t, x0), refs; terminal = term)
    _, U = trajectories(co2.fp, plan(co2))
    gap = Jt - objective(cq, stack_inputs(cq, U))
    @printf("  %-13s %3d teams  spread %.2f  gap %.2e  certificate %.2e  (%.2f x the gap)\n", name, maximum(lab),
            team_spread(fl2, lab)[1], max(gap, 0.0), cert, gap > 1e-9 ? cert / gap : NaN)
end
