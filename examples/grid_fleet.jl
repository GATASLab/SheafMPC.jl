# grid_fleet.jl: the paper's grid-fleet scenario, end to end.
#
#   julia --project=. examples/grid_fleet.jl            (8 x 8 fleet; ROWS=4 COLS=4 for a quick run)
#
# An 8 x 8 grid of vehicles, quadrotors on odd rows and ground vehicles on even
# rows, flies a formation in +x over a horizon of H = 10 steps of 0.2 s. Each
# row tracks its own centre trajectory (coherence :rows) and, in the second
# part, every vehicle also wanders off its slot (:agents, incoherent).
#
# 1. Levels of reduction: the fine program, partial and full condensing (exact),
#    rows as teams (zero gap: rows are almost equitable and coherent), strips of
#    rows and the whole fleet (a virtual structure), each with its size, solve
#    time, value and certified gap. The fine-solve bound (lower) is sharp; the
#    reduced-solve bound (upper) needs no fine solve but is loose for soft
#    formation springs, as in the paper.
# 2. Choosing teams on incoherent data with the gap kernel: the selector against
#    rows and 2 x 2 blocks at the same number of teams.
# 3. The closed loop: 30 receding-horizon steps on the selected teams, with the
#    timing breakdown of a step.
# 4. Distributed MPC by consensus ADMM over the vehicles and over the rows.

using SheafMPC, Printf, Statistics, LinearAlgebra

BLAS.set_num_threads(1)
const ROWS = parse(Int, get(ENV, "ROWS", "8"))
const COLS = parse(Int, get(ENV, "COLS", "8"))

function program(sc)
    refs, term = references(sc, 0.0)
    return FleetProgram(fleet(sc); x0 = formation_start(sc), references = refs, terminal = term)
end

# compile on a small instance first, so that the times below are run times
let w = GridScenario(rows = 2, cols = 2, H = 4)
    p = program(w); f = solve(p); R = reduce(p, Teams(row_teams(w)) ⊠ partial_condensing(2)); r = solve(R)
    gap_bounds(p, R, r; fine_solution = f); select_teams(gap_kernel(p, f.x); k = 2)
    reduce(p, full_condensing()); reduce(p, Teams(ones(Int, 4)))
end

println("1. levels of reduction, coherent rows ($(ROWS) x $(COLS) fleet, H = 10)")
sc = GridScenario(rows = ROWS, cols = COLS, H = 10, coherence = :rows, seed = 1)
fp = program(sc)
t = @elapsed fine = solve(fp)
@printf("   %-26s %7s %9s %9s %12s %10s %10s %10s\n", "level", "vars", "reduce s", "solve s", "J", "lower", "gap", "upper")
@printf("   %-26s %7d %9s %9.3f %12.6f\n", "fine", c0dim(fp.program), "", t, fine.J)
for (name, res) in (("partial condensing (5)", partial_condensing(5)), ("full condensing", full_condensing()),
                    ("rows as teams", Teams(row_teams(sc))), ("strips of 2 rows", Teams(strip_teams(sc, 2))),
                    ("rows, condensed", Teams(row_teams(sc)) ⊠ full_condensing()),
                    ("whole fleet", Teams(ones(Int, nagents(sc)))))
    tr = @elapsed R = reduce(fp, res)
    ts = @elapsed red = solve(R)
    b = gap_bounds(fp, R, red; fine_solution = fine)
    @printf("   %-26s %7d %9.3f %9.3f %12.6f %10.2e %10.2e %10.2e\n", name, c0dim(R.program), tr, ts, red.J,
            b.lower, b.gap, b.upper)
end

println("\n2. choosing teams on incoherent data")
sc2 = GridScenario(rows = ROWS, cols = COLS, H = 10, coherence = :agents, seed = 1)
fp2 = program(sc2)
fine2 = solve(fp2)
tk = @elapsed K = gap_kernel(fp2, fine2.x)
println("   ", K, @sprintf(" (built in %.2f s)", tk))
k = ROWS * COLS ÷ 4
ts = @elapsed sel = select_teams(K; k = k)
@printf("   %d teams: selector gap %.4f (%.2f s); 2 x 2 blocks %.4f; 1 x 4 blocks %.4f (J* = %.4f)\n",
        k, sel.gap, ts, gap(K, block_teams(sc2, 2, 2)), gap(K, block_teams(sc2, 1, 4)), K.Jstar)
R = reduce(fp2, Teams(sel.teams))
red = solve(R)
@printf("   the selected teams by pushforward and solve: gap %.4f (the kernel is exact while no constraint is active)\n",
        red.J - fine2.J)

println("\n3. closed loop on the selected teams, 30 steps")
fl = fleet(sc2)
ctrl = MPCController(fl, Teams(sel.teams))
x = formation_start(sc2)
T = Dict(s => Float64[] for s in (:construct, :setup, :solve, :lift, :certify, :total))
for step in 0:29
    refs, term = references(sc2, step * sc2.h)
    info = step!(ctrl, x, refs; terminal = term)
    info.status == :solved || @warn "step $step: $(info.status)"
    if step > 0
        push!(T[:construct], info.t_construct); push!(T[:setup], info.t_setup); push!(T[:solve], info.t_solve)
        push!(T[:lift], info.t_lift); push!(T[:certify], info.t_certify); push!(T[:total], info.t_total)
    end
    global x = plant_step(fl, x, info.u)
end
println("   ", ctrl)
@printf("   median ms per step: construct %.3f, setup %.3f, solve %.3f, lift %.3f, certify %.3f, total %.3f\n",
        (1e3 * median(T[s]) for s in (:construct, :setup, :solve, :lift, :certify, :total))...)
@printf("   last step: J = %.4f, certified gap <= %.4g\n", ctrl.info.J, ctrl.info.gap_upper)

println("\n4. distributed MPC (consensus ADMM), 10 steps")
for (name, teams) in (("over the vehicles", collect(1:nagents(sc2))), ("over the rows", row_teams(sc2)))
    D = DistributedMPC(fl, teams)
    xd = formation_start(sc2)
    its = Int[]; tpar = Float64[]
    for step in 0:9
        refs, term = references(sc2, step * sc2.h)
        info = step!(D, xd, refs; terminal = term)
        push!(its, info.iter); push!(tpar, D.t_parallel)
        xd = plant_step(fl, xd, info.u)
    end
    @printf("   %-18s %3d local problems, median %3d iterations per step, %5d floats per iteration, %.2f ms parallel compute\n",
            name, length(D.locals), median(its), floats_per_iteration(D), 1e3 * median(tpar))
end
