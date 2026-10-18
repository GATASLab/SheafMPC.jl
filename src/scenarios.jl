# scenarios.jl: the agents and the grid fleet of the paper's experiments.

"""
    quadrotor(h; umax = 4.0, q = 1.0, qz = 1.0, qf = 5.0, qv = 1.0, r = 0.1, drift = zeros(2))

A quadrotor as a 3D double integrator (exact zero-order hold with step `h`, a
number or one step per instant): state `(p, v)` in `R^6`, input the
acceleration `a` with `||a|| <= umax`, formation output the planar position,
tracked output the position (weights `q, q, qz`), terminal cost `qf` on the
position and `qv` on the velocity (`Cf = I`, terminal reference
`(p_ref, v_ref)`), effort weight `r`. A known planar drift acceleration
`drift` enters the affine term `g`.
"""
function quadrotor(h; umax::Real = 4.0, q::Real = 1.0, qz::Real = 1.0, qf::Real = 5.0, qv::Real = 1.0,
                   r::Real = 0.1, drift = zeros(2))
    hs = h isa Real ? [Float64(h)] : Vector{Float64}(h)
    I3 = Matrix{Float64}(I, 3, 3)
    A = [[I3 ht*I3; zeros(3, 3) I3] for ht in hs]
    B = [[0.5ht^2*I3; ht*I3] for ht in hs]
    g = [[0.5ht^2*[drift; 0.0]; ht*[drift; 0.0]] for ht in hs]
    Q = Matrix(Diagonal([q, q, qz]))
    Qf = Matrix(cat(qf * Q, qv * I3; dims = (1, 2)))
    return Agent(A, B; g = g, C = [Matrix{Float64}(I, 2, 2) zeros(2, 4)], Cr = [I3 zeros(3, 3)], Q = Q,
                 R = r * I3, Cf = Matrix{Float64}(I, 6, 6), Qf = Qf, input = BallSet(umax), kind = :quadrotor)
end

"""
    ground_vehicle(h; umax = 2.0, drag = 0.4, q = 1.0, qf = 5.0, qv = 1.0, r = 0.1, drift = zeros(2))

A ground vehicle as a planar double integrator with linear drag,
`v+ = (1 - drag h) v + h a`: state `(p, v)` in `R^4`, input `||a|| <= umax`,
formation and tracked output the position, terminal cost `qf` on the position
and `qv` on the velocity (`Cf = I`, terminal reference `(p_ref, v_ref)`).
"""
function ground_vehicle(h; umax::Real = 2.0, drag::Real = 0.4, q::Real = 1.0, qf::Real = 5.0, qv::Real = 1.0,
                        r::Real = 0.1, drift = zeros(2))
    hs = h isa Real ? [Float64(h)] : Vector{Float64}(h)
    I2 = Matrix{Float64}(I, 2, 2)
    A = [[I2 ht*I2; zeros(2, 2) (1 - drag * ht)*I2] for ht in hs]
    B = [[0.5ht^2*I2; ht*I2] for ht in hs]
    g = [[0.5ht^2*drift; ht*drift] for ht in hs]
    C = [I2 zeros(2, 2)]
    Q = q * I2
    Qf = Matrix(cat(qf * Q, qv * I2; dims = (1, 2)))
    return Agent(A, B; g = g, C = C, Cr = C, Q = Q, R = r * I2, Cf = Matrix{Float64}(I, 4, 4), Qf = Qf,
                 input = BallSet(umax), kind = :ground_vehicle)
end

"""
    grid_graph(rows, cols; spacing = 1.0) -> (edges, slots)

The grid formation graph (row major, edges between horizontal and vertical
neighbours) and the slot of every agent, `spacing * (c - (cols+1)/2, r - (rows+1)/2)`
for row `r` and column `c`: rows are lanes along the direction of travel `+x`.
"""
function grid_graph(rows::Integer, cols::Integer; spacing::Real = 1.0)
    idx(r, c) = (r - 1) * cols + c
    edges = Tuple{Int,Int}[]
    slots = [zeros(2) for _ in 1:(rows*cols)]
    for r in 1:rows, c in 1:cols
        i = idx(r, c)
        slots[i] = spacing * [c - (cols + 1) / 2, r - (rows + 1) / 2]
        c < cols && push!(edges, (i, idx(r, c + 1)))
        r < rows && push!(edges, (i, idx(r + 1, c)))
    end
    return edges, slots
end

"""
    GridScenario(; rows = 8, cols = 8, H = 10, h = 0.2, spacing = 1.0, wform = 1.0, coherence = :rows,
                 speed = 1.0, umax_scale = 1.0, seed = 1)

The paper's grid fleet: `rows x cols` agents, quadrotors on odd rows and
ground vehicles on even rows, formation springs of weight `wform` on every
grid edge with targets from the grid slots, flying in `+x`. `coherence`:
`:fleet` (every agent tracks the formation centre plus its slot: the data are
coherent and every clustering has zero gap), `:rows` (each row tracks its own
centre trajectory: coherent inside rows, which are almost equitable teams),
`:agents` (each agent also wanders off its slot: incoherent). The seed draws
the per-row and per-agent reference parameters.
"""
Base.@kwdef struct GridScenario
    rows::Int = 8
    cols::Int = 8
    H::Int = 10
    h::Float64 = 0.2
    spacing::Float64 = 1.0
    wform::Float64 = 1.0
    coherence::Symbol = :rows
    speed::Float64 = 1.0
    umax_scale::Float64 = 1.0
    seed::Int = 1
end

nagents(sc::GridScenario) = sc.rows * sc.cols
_rowcol(i, cols) = (div(i - 1, cols) + 1, rem(i - 1, cols) + 1)
"""`agent_kind(sc, i)`: `:quadrotor` on odd rows, `:ground_vehicle` on even rows."""
agent_kind(sc::GridScenario, i::Integer) = isodd(_rowcol(i, sc.cols)[1]) ? :quadrotor : :ground_vehicle
"""`row_teams(sc)`: every grid row a team."""
row_teams(sc::GridScenario) = [_rowcol(i, sc.cols)[1] for i in 1:nagents(sc)]
"""`strip_teams(sc, k)`: strips of `k` consecutive rows."""
strip_teams(sc::GridScenario, k::Integer) = canonical_partition([cld(_rowcol(i, sc.cols)[1], k) for i in 1:nagents(sc)])
"""`block_teams(sc, a, b)`: rectangular blocks of `a` rows by `b` columns."""
function block_teams(sc::GridScenario, a::Integer, b::Integer)
    nb = cld(sc.cols, b)
    return canonical_partition([(cld(_rowcol(i, sc.cols)[1], a) - 1) * nb + cld(_rowcol(i, sc.cols)[2], b) for i in 1:nagents(sc)])
end

function _scenario_params(sc::GridScenario)
    rng = Xoshiro(sc.seed)
    row = [(speed = sc.speed * (0.8 + 0.4 * rand(rng)), amp = 0.1 + 0.3 * rand(rng), om = 0.5 + rand(rng),
            ph = 2pi * rand(rng), alt = 1.5 + 0.4 * (rand(rng) - 0.5)) for _ in 1:sc.rows]
    agent = [(amp = 0.3 + 0.5 * rand(rng), om = 0.5 + rand(rng), ph = 2pi * rand(rng),
              ampz = 0.3 * rand(rng), omz = 0.5 + rand(rng), phz = 2pi * rand(rng)) for _ in 1:nagents(sc)]
    return (row = row, agent = agent)
end

function _reference(sc::GridScenario, prm, slots, i::Int, tau::Real)
    r, _ = _rowcol(i, sc.cols)
    if sc.coherence == :fleet
        return [sc.speed * tau, 0.3 * sin(0.5 * tau)] + slots[i], [sc.speed, 0.15 * cos(0.5 * tau)], 1.5
    elseif sc.coherence == :rows
        q = prm.row[r]
        p = [q.speed * tau, q.amp * (sin(q.om * tau + q.ph) - sin(q.ph))]
        v = [q.speed, q.amp * q.om * cos(q.om * tau + q.ph)]
        return p + slots[i], v, q.alt
    elseif sc.coherence == :agents
        a = prm.agent[i]
        p = [sc.speed * tau, 0.3 * sin(0.5 * tau)] + slots[i] +
            a.amp * [sin(a.om * tau + a.ph) - sin(a.ph), cos(a.om * tau + a.ph) - cos(a.ph)]
        v = [sc.speed, 0.15 * cos(0.5 * tau)] + a.amp * a.om * [cos(a.om * tau + a.ph), -sin(a.om * tau + a.ph)]
        z = 1.5 + a.ampz * (sin(a.omz * tau + a.phz) - sin(a.phz))
        return p, v, z
    end
    throw(ArgumentError("unknown coherence $(sc.coherence) (use :fleet, :rows or :agents)"))
end

"""`fleet(sc)`: the scenario's `Fleet` (agents, grid formation graph, slot targets, weights)."""
function fleet(sc::GridScenario)
    edges, slots = grid_graph(sc.rows, sc.cols; spacing = sc.spacing)
    agents = [agent_kind(sc, i) == :quadrotor ? quadrotor(sc.h; umax = 4.0 * sc.umax_scale) :
              ground_vehicle(sc.h; umax = 2.0 * sc.umax_scale) for i in 1:nagents(sc)]
    return Fleet(agents, edges; H = sc.H, offsets = slots, weights = sc.wform)
end

"""`slots(sc)`: the formation slot of every agent."""
slots(sc::GridScenario) = grid_graph(sc.rows, sc.cols; spacing = sc.spacing)[2]

"""
    references(sc, t0 = 0.0) -> (refs, terminal)

The tracking references at world time `t0` for the instants `t0 + h t`,
`t = 0, ..., H`, in the form `set_references!` and `step!` take: `refs[i]`
(position and, for quadrotors, altitude, by instant) and `terminal[i]`
(terminal position and velocity).
"""
function references(sc::GridScenario, t0::Real = 0.0; prm = _scenario_params(sc))
    sl = slots(sc)
    n, H = nagents(sc), sc.H
    refs = Vector{Matrix{Float64}}(undef, n)
    terminal = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        quad = agent_kind(sc, i) == :quadrotor
        R = zeros(quad ? 3 : 2, H + 1)
        for t in 0:H
            p, _, z = _reference(sc, prm, sl, i, t0 + sc.h * t)
            R[1:2, t+1] = p
            quad && (R[3, t+1] = z)
        end
        _, v, _ = _reference(sc, prm, sl, i, t0 + sc.h * H)
        refs[i] = R
        terminal[i] = quad ? [R[:, H+1]; v; 0.0] : [R[:, H+1]; v]
    end
    return refs, terminal
end

"""`formation_start(sc)`: every agent on its slot at the origin, one common velocity, quadrotors at altitude 1.5."""
function formation_start(sc::GridScenario)
    sl = slots(sc)
    v0 = [sc.speed, 0.15]
    return [agent_kind(sc, i) == :quadrotor ? [sl[i]; 1.5; v0; 0.0] : [sl[i]; v0] for i in 1:nagents(sc)]
end
