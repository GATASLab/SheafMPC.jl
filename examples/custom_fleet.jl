# custom_fleet.jl: a fleet from its matrices.
#
#   julia --project=. examples/custom_fleet.jl
#
# Six planar double integrators in a ring formation, two of them heavier
# (smaller input authority), one with a box input set instead of a ball, and a
# wall y <= 1.2 for the first agent from instant 3 on (a polyhedral state set).
# The ring shrinks smoothly after instant 4 (time-varying targets) and one
# edge is absent at the first instants (a switching topology). Then: the fine
# program, teams of two, a time blocking, their product, teams that form only
# from instant 2 on, and the gap certificates.

using SheafMPC, LinearAlgebra, Printf

h, H = 0.2, 12
A = [1.0 0 h 0; 0 1 0 h; 0 0 1 0; 0 0 0 1]
B = [0.5h^2 0; 0 0.5h^2; h 0; 0 h]
C = [1.0 0 0 0; 0 1 0 0]                                   # formation output: the position
wall = Polyhedron([0.0 1 0 0], [1.2])                      # y <= 1.2
agents = Agent[]
for i in 1:6
    input = i == 3 ? BoxSet([-1.0, -1.0], [1.0, 1.0]) : BallSet(i in (2, 5) ? 0.8 : 2.0)
    state = i == 1 ? [t >= 3 ? wall : nothing for t in 1:H] : nothing
    push!(agents, Agent(A, B; C = C, Q = Matrix(1.0I, 2, 2), R = 0.1 * Matrix(1.0I, 2, 2),
                        Cf = Matrix(1.0I, 4, 4), Qf = Matrix(Diagonal([5.0, 5, 1, 1])), input = input, state = state))
end
edges = [(i, i % 6 + 1) for i in 1:6]
ring(r) = [r * [cos(2pi * (i - 1) / 6), sin(2pi * (i - 1) / 6)] for i in 1:6]
targets = zeros(2, 6, H)
for t in 1:H
    o = ring(1.0 - 0.1 * (1 - cos(pi * clamp(t - 4, 0, 8) / 8)))   # radius 1 -> 0.8 over instants 4..12
    for (k, (i, j)) in enumerate(edges)
        targets[:, k, t] = o[j] - o[i]
    end
end
present = trues(6, H); present[1, 1:3] .= false             # edge (1, 2) absent at t = 1, 2, 3
fl = Fleet(agents, edges; H = H, targets = targets, weights = 2.0, present = present)

x0 = [[p; 0.5; 0.0] for p in ring(1.0)]
refs = [hcat([ring(1.0)[i] + [0.5 * h * t, 0.0] for t in 0:H]...) for i in 1:6]
term = [[refs[i][:, end]; 0.5; 0.0] for i in 1:6]
fp = FleetProgram(fl; x0 = x0, references = refs, terminal = term)
println(fp)

fine = solve(fp)
@printf("fine: %s, J = %.6f\n", fine.status, fine.J)
for (name, res) in (("teams of two", Teams([1, 1, 2, 2, 3, 3])), ("blocks of 3 instants", partial_condensing(3)),
                    ("teams of two, blocks of 3", Teams([1, 1, 2, 2, 3, 3]) ⊠ partial_condensing(3)),
                    ("teams of two from t = 2", Teams([1, 1, 2, 2, 3, 3]; from = 2)))
    R = reduce(fp, res)
    red = solve(R)
    b = gap_bounds(fp, R, red; fine_solution = fine)
    x = lift(R, red)
    X, U = trajectories(fp, x)
    @printf("%-28s vars %4d -> %4d  J = %.6f  gap %.3e in [%.3e, %.3e]  wall ok: %s\n", name, c0dim(fp.program),
            c0dim(R.program), red.J, b.gap, b.lower, b.upper, all(X[1][2, 4:end] .<= 1.2 + 1e-6))
end
