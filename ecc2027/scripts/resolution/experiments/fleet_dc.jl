# fleet_dc.jl: the drone/car fleet of the restructured Sec. VI, shared by the E26 and E27 families
# (included by e26_flagship.jl and e27_pareto.jl).
#
# BENCH_FLEET = quad (the Oct 27 fleet: quadrotor rows alternating a light and a heavy airframe, one lane per
# row) or dronecar (default): drones (3D double integrators, state (p, v) in R^6, input ||a|| <= 4, no drag,
# effort weight 0.1) and cars (planar point masses with linear drag 0.3, state in R^4, input ||a|| <= 0.4,
# effort weight 0.2). BENCH_LAYOUT = rows (drone rows and car rows alternate) or columns (drones and cars
# alternate along every row, the mixed fleet). Every drone flies the drone lane and every car drives the car
# lane, each shifted by its slot (one lane per type, drawn per seed), so the data classes are the two types.
# The formation output is the position in R^3 (a car's altitude row is zero); a drone-drone edge compares the
# 3D positions, a drone-car or car-car edge the horizontal positions (Fleet's `select`).
# BENCH_HET = 1 gives every vehicle its own parameters inside its type (drag x (1 +- 0.2), input bound
# x (1 +- 0.1), uniform per vehicle from the seed; a drone's nominal drag 0 becomes 0.05 x (1 +- 0.2)), so
# exact symmetry fails; teams are still colour refinement of the nominal classes.
# Teams (BENCH_DC_TEAMS): cr (default; colour refinement of the nominal classes (type, lane) on the formation
# graph), rows, or split (rows split by type).

const FLEET_DC = Symbol(get(ENV, "BENCH_FLEET", "dronecar"))
const LAYOUT_DC = Symbol(get(ENV, "BENCH_LAYOUT", "rows"))
const HET_DC = get(ENV, "BENCH_HET", "0") == "1"
const TEAMS_DC = Symbol(get(ENV, "BENCH_DC_TEAMS", "cr"))
const UMAX_DRONE_DC = 4.0
const UMAX_CAR_DC = parse(Float64, get(ENV, "BENCH_UMAX_CAR", "0.4"))
const DRAG_CAR_DC = 0.3
const R_DRONE_DC = 0.1
const R_CAR_DC = 0.2

"""The exact zero-order hold of a double integrator in R^dim with linear drag d (p' = v, v' = -d v + u) at step h:
(A, B) for the state (p, v); `BENCH_DISC=euler` restores the old drag discretization."""
function dyn_dc(h, d, dim::Int)
    Id = Matrix{Float64}(I, dim, dim)
    if get(ENV, "BENCH_DISC", "zoh") == "euler" || d == 0
        a, phi, bp, bv = 1 - d * h, h, 0.5h^2, h
    else
        a = exp(-d * h); phi = (1 - a) / d; bp = (h - phi) / d; bv = phi
    end
    return [Id phi*Id; zeros(dim, dim) a*Id], [bp*Id; bv*Id]
end

"""A drone: 3D double integrator, formation and tracked output the 3D position."""
function drone_dc(h, umax, drag, r, cone)
    I3 = Matrix{Float64}(I, 3, 3)
    A, B = dyn_dc(h, drag, 3)
    C = [I3 zeros(3, 3)]
    U = cone == :soc ? SM.BallSet(umax) : SM.BoxSet(fill(-umax / sqrt(3), 3), fill(umax / sqrt(3), 3))
    return SM.Agent(A, B; C = C, Cr = C, Q = Matrix(1.0I, 3, 3), R = r * I3, Cf = Matrix(1.0I, 6, 6),
                    Qf = Matrix(Diagonal([5.0, 5, 5, 1, 1, 1])), input = U, kind = :drone)
end

"""A car: planar double integrator with drag; formation output its position in R^3 (altitude row zero),
tracked output the planar position."""
function car_dc(h, umax, drag, r, cone)
    I2 = Matrix{Float64}(I, 2, 2)
    A, B = dyn_dc(h, drag, 2)
    Cr = [I2 zeros(2, 2)]
    C = [Cr; zeros(1, 4)]
    U = cone == :soc ? SM.BallSet(umax) : SM.BoxSet(fill(-umax / sqrt(2), 2), fill(umax / sqrt(2), 2))
    return SM.Agent(A, B; C = C, Cr = Cr, Q = Matrix(1.0I, 2, 2), R = r * I2, Cf = Matrix(1.0I, 4, 4),
                    Qf = Matrix(Diagonal([5.0, 5, 1, 1])), input = U, kind = :car)
end

"""The kind of vehicle i of a rows x cols grid (row major) in the layout."""
kind_dc(i, cols, layout) = (r = div(i - 1, cols) + 1; c = rem(i - 1, cols) + 1;
                            (layout == :rows ? isodd(r) : isodd(c)) ? :drone : :car)

"""
    dc_agents(n, kinds, h, cone, seed) -> (agents, params)

The drone and car agents; with BENCH_HET=1 every vehicle's drag and input bound spread about its type's
(params[i] = (drag, umax, r)).
"""
function dc_agents(kinds::Vector{Symbol}, h, cone, seed::Int)
    rng = Xoshiro(424_243 * seed + 11)
    ags = SM.Agent[]; params = NamedTuple[]
    for k in kinds
        sd = HET_DC ? 1 + 0.2 * (2rand(rng) - 1) : 1.0
        su = HET_DC ? 1 + 0.1 * (2rand(rng) - 1) : 1.0
        if k == :drone
            d = HET_DC ? 0.05 * sd : 0.0; u = UMAX_DRONE_DC * su
            push!(ags, drone_dc(h, u, d, R_DRONE_DC, cone)); push!(params, (drag = d, umax = u, r = R_DRONE_DC))
        else
            d = DRAG_CAR_DC * sd; u = UMAX_CAR_DC * su
            push!(ags, car_dc(h, u, d, R_CAR_DC, cone)); push!(params, (drag = d, umax = u, r = R_CAR_DC))
        end
    end
    return ags, params
end

"""The edge selections: the 3D positions between two drones, the horizontal ones otherwise."""
dc_select(edges, kinds) = [(kinds[i] == :drone && kinds[j] == :drone) ? Matrix(1.0I, 3, 3) : [1.0 0 0; 0 1 0]
                           for (i, j) in edges]

"""The lanes, one per type (drone lane first): speed, lateral weave, altitude (drones), from the seed."""
function dc_lanes(seed::Int)
    rng = Xoshiro(seed)
    return [(speed = 0.8 + 0.4 * rand(rng), amp = 0.1 + 0.3 * rand(rng), om = 0.5 + rand(rng), ph = 2pi * rand(rng),
             alt = 1.5 + 0.4 * (rand(rng) - 0.5)) for _ in 1:2]
end

"""Teams (one label per vehicle) and every vehicle's rank inside its team (by column, then row)."""
function dc_teams(n, rows, cols, edges, kinds, lanei; teams::Symbol = TEAMS_DC)
    r = [div(i - 1, cols) + 1 for i in 1:n]; c = [rem(i - 1, cols) + 1 for i in 1:n]
    lab = if teams == :rows
        r
    elseif teams == :split
        SM.canonical_partition([(r[i], kinds[i]) for i in 1:n])
    elseif teams == :cr
        SM.colour_refinement(n, edges, 1.0, SM.canonical_partition([(kinds[i], lanei[i]) for i in 1:n]))
    else
        error("unknown teams $teams")
    end
    lab = SM.canonical_partition(lab)
    rank = zeros(Int, n)
    for b in 1:maximum(lab)
        mem = sort([i for i in 1:n if lab[i] == b]; by = i -> (c[i], r[i]))
        for (k, i) in enumerate(mem)
            rank[i] = k
        end
    end
    return lab, rank
end

"""Is every team connected in the graph (edges)? Returns the number of disconnected teams."""
function dc_disconnected(n, edges, lab)
    parent = collect(1:n)
    f(x) = (while parent[x] != x; parent[x] = parent[parent[x]]; x = parent[x]; end; x)
    for (i, j) in edges
        lab[i] == lab[j] || continue
        a, b = f(i), f(j); a != b && (parent[a] = b)
    end
    roots = Dict{Int,Set{Int}}()
    for i in 1:n
        push!(get!(roots, lab[i], Set{Int}()), f(i))
    end
    return count(s -> length(s) > 1, values(roots))
end
