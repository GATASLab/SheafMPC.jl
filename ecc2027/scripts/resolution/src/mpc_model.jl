# mpc_model.jl: multi-agent MPC as a graph program on G box P_H
# and the resolutions of G box P_H used by the experiments.
#
# Vertex (i, t) carries agent i's state and input at instant t (only the state
# at t = H). Two kinds of edges:
#
# * dynamics (fibre) edges d_{i,t} : (i,t) -> (i,t+1), space R^{n_i},
#   (delta x) = x_{i,t+1} - A_{i,t} x_{i,t} - B_{i,t} u_{i,t}, target c_{i,t};
#   hard in hard MPC, soft with weight rho I for t >= 1 in virtual-future MPC;
# * formation (slice) edges f_{ij,t} : (i,t) -> (j,t) for t >= 1, space R^2
#   (planar position), (delta x) = C_j x_{j,t} - C_i x_{i,t}, target b_{ij,t}
#   (the desired relative position), weight w_{ij,t}, soft.
#
# Every datum may vary with t: the dynamics, the targets and weights, and the
# formation graph itself (a switching topology E_t). The box product is built on
# the union graph G = union of the G_t; an edge ij absent at instant t is either
# omitted or carried as a zero-dimensional edge space (`absent = :omit` or
# `:zero`), and the two encodings give the same program.
#
# Two agent types: "quad", a 3D double integrator (state (p, v) in R^6, input a
# in R^3, ||a|| <= abar_q), and "rover", a planar double integrator with linear
# drag, v+ = (1 - c h) v + h a (state in R^4, input in R^2, ||a|| <= abar_r,
# smaller). Both track a planar reference, quads also an altitude reference.

# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------

"""
    AgentModel

One agent over the horizon: dynamics `x_{t+1} = A[t+1] x_t + B[t+1] u_t + c[t+1]`
(`t = 0..H-1`), formation output `C` (planar position), tracking output `Cr`
with stage weight `Q` and terminal weight `Qf`, terminal velocity weight `qv` on
the coordinates `vel`, effort weight `R`, input set `||u|| <= abar`. `E` embeds
a planar offset into the state (the planar position coordinates).
"""
struct AgentModel
    kind::Symbol
    nx::Int
    nu::Int
    A::Vector{Matrix{Float64}}
    B::Vector{Matrix{Float64}}
    c::Vector{Vector{Float64}}
    C::Matrix{Float64}
    Cr::Matrix{Float64}
    Q::Matrix{Float64}
    Qf::Matrix{Float64}
    qv::Float64
    vel::Vector{Int}
    R::Matrix{Float64}
    abar::Float64
    E::Matrix{Float64}
end

const QUAD_ABAR = 4.0
const ROVER_ABAR = 2.0
const ROVER_DRAG = 0.4

"""Quad: 3D double integrator, exact zero-order-hold discretization with steps `h[t]`."""
function quad_agent(h::Vector{Float64}; abar = QUAD_ABAR, q = 1.0, qz = 1.0, qf = 5.0,
                    qv = 1.0, r = 0.1, drift = [zeros(2) for _ in h])
    I3 = Matrix{Float64}(I, 3, 3)
    A = [[I3 ht*I3; zeros(3, 3) I3] for ht in h]
    B = [[0.5ht^2*I3; ht*I3] for ht in h]
    c = [[0.5ht^2*[w; 0.0]; ht*[w; 0.0]] for (ht, w) in zip(h, drift)]
    C = [Matrix{Float64}(I, 2, 2) zeros(2, 4)]
    Cr = [I3 zeros(3, 3)]
    Q = Matrix(Diagonal([q, q, qz]))
    E = [Matrix{Float64}(I, 2, 2); zeros(4, 2)]
    return AgentModel(:quad, 6, 3, A, B, c, C, Cr, Q, qf * Q, qv, [4, 5, 6], r * I3, abar, E)
end

"""Rover: planar double integrator with linear drag `v+ = (1 - c_t h_t) v + h_t a`."""
function rover_agent(h::Vector{Float64}; abar = ROVER_ABAR, drag = fill(ROVER_DRAG, length(h)),
                     q = 1.0, qf = 5.0, qv = 1.0, r = 0.1, drift = [zeros(2) for _ in h])
    I2 = Matrix{Float64}(I, 2, 2)
    A = [[I2 ht*I2; zeros(2, 2) (1 - ct * ht)*I2] for (ht, ct) in zip(h, drag)]
    B = [[0.5ht^2*I2; ht*I2] for ht in h]
    c = [[0.5ht^2*w; ht*w] for (ht, w) in zip(h, drift)]
    C = [I2 zeros(2, 2)]
    Q = q * I2
    E = [I2; zeros(2, 2)]
    return AgentModel(:rover, 4, 2, A, B, c, C, copy(C), Q, qf * Q, qv, [3, 4], r * I2, abar, E)
end

# ---------------------------------------------------------------------------
# Graphs and formations
# ---------------------------------------------------------------------------

function _grid_shape(n::Int)
    r = floor(Int, sqrt(n))
    while n % r != 0
        r -= 1
    end
    return r, n ÷ r
end

"""
    agent_graph(kind, n, rng; spacing) -> (edges, layout)

Undirected agent graph (`i < j` edge list) and a planar layout used as the
formation shape: `:ring`, `:path`, `:complete`, `:grid` (a near-square
rows x cols grid), `:rgg` (random geometric graph, radius grown until connected).
"""
function agent_graph(kind::Symbol, n::Int, rng::AbstractRNG; spacing::Real = 1.0)
    edges = Tuple{Int,Int}[]
    layout = [zeros(2) for _ in 1:n]
    if kind in (:ring, :complete)
        R = n > 2 ? spacing / (2 * sin(pi / n)) : spacing / 2
        for i in 1:n
            layout[i] = R * [cos(2pi * (i - 1) / n), sin(2pi * (i - 1) / n)]
        end
        if kind == :ring
            for i in 1:n
                j = i == n ? 1 : i + 1
                n == 2 && i == 2 && break
                push!(edges, (min(i, j), max(i, j)))
            end
        else
            for i in 1:n, j in (i+1):n
                push!(edges, (i, j))
            end
        end
    elseif kind == :path
        for i in 1:n
            layout[i] = [spacing * (i - 1), 0.0]
            i < n && push!(edges, (i, i + 1))
        end
    elseif kind == :grid
        rows, cols = _grid_shape(n)
        idx(r, c) = (r - 1) * cols + c
        for r in 1:rows, c in 1:cols
            layout[idx(r, c)] = spacing * [c - 1.0, r - 1.0]
            c < cols && push!(edges, (idx(r, c), idx(r, c + 1)))
            r < rows && push!(edges, (idx(r, c), idx(r + 1, c)))
        end
    elseif kind == :rgg
        side = spacing * sqrt(n)
        for i in 1:n
            layout[i] = side * rand(rng, 2)
        end
        radius = 1.2 * spacing
        while true
            edges = [(i, j) for i in 1:n for j in (i+1):n if norm(layout[i] - layout[j]) <= radius]
            _connected(n, edges) && break
            radius *= 1.1
        end
    else
        throw(ArgumentError("unknown graph kind $kind"))
    end
    ctr = sum(layout) / n
    layout = [p - ctr for p in layout]
    return edges, layout
end

function _connected(n::Int, edges)
    parent = collect(1:n)
    for (i, j) in edges
        _union!(parent, i, j)
    end
    return all(_find!(parent, v) == _find!(parent, 1) for v in 1:n)
end

# ---------------------------------------------------------------------------
# The MPC data (explicit and time varying) and the configurations that make it
# ---------------------------------------------------------------------------

"""
    MPCSpec

Every datum of THEORY Def 4.1, explicit and possibly time varying:

* `h[t+1]`: step length from `t` to `t+1` (`t = 0..H-1`);
* `agents[i]`: dynamics per instant, outputs, weights, input bound;
* `gedges[k] = (i, j)`: the union agent graph; `present[k, t]` whether `ij` is
  an edge of `G_t` (`t = 1..H`); `ftarget[:, k, t]`, `fweight[k, t]`: target
  `b_{ij,t}` (desired `C_j x_j - C_i x_i`) and weight `w_{ij,t}`;
* `xhat[i]`: measured state; `ref[i][:, t+1]`: tracking reference; `vref[i]`:
  terminal velocity reference;
* `halfspaces[i]`: state constraints `(t, a, beta)` meaning `a' C_i x_{i,t} >= beta`
  (a convex keep-out, one tangent half-space per affected instant);
* `typing`: `:hard` (every dynamics edge hard) or `:virtual` (only `d_{i,0}` hard,
  the rest soft with weight `rho I`);
* `absent`: `:omit` or `:zero`, the encoding of absent formation edges;
* `offsets[:, i, t+1]`: formation offsets `o_{i,t}` the targets were made from
  (`b_{ij,t} = o_{j,t} - o_{i,t}`), kept for the reference QPs.
"""
struct MPCSpec
    n::Int
    H::Int
    h::Vector{Float64}
    agents::Vector{AgentModel}
    gedges::Vector{Tuple{Int,Int}}
    present::BitMatrix
    ftarget::Array{Float64,3}
    fweight::Matrix{Float64}
    xhat::Vector{Vector{Float64}}
    ref::Vector{Matrix{Float64}}
    vref::Vector{Vector{Float64}}
    halfspaces::Vector{Vector{Tuple{Int,Vector{Float64},Float64}}}
    typing::Symbol
    rho::Float64
    absent::Symbol
    offsets::Array{Float64,3}
    obstacles::Vector{NamedTuple{(:center, :radius, :affects),Tuple{Vector{Float64},Float64,Symbol}}}
    config::Dict{String,Any}
end

"""
    MPCConfig(; kwargs...)

A compact description of an MPC instance from which `mpc_spec` makes the data
(deterministically, from `seed`):

* `n`, `H`, `h`: fleet size, horizon, nominal step;
* `graph`: `:ring`, `:path`, `:grid`, `:rgg`, `:complete`;
* `fleet`: `:mixed` (odd agents quads, even agents rovers), `:rows` (on a grid:
  quads on odd rows, rovers on even rows), `:quad`, `:rover`;
* `typing`, `rho`: `:hard` MPC, `:virtual`-future MPC (only `d_{i,0}` hard), or
  `:soft` (every dynamics edge a spring of weight `rho`, the implementability control);
* `incoherence`: scale of the references' departure from the formation (1 by default);
* `coherent`: references `r_{i,t} = r_{c,t} + o_{i,t}` in the formation output
  (otherwise each agent's reference wanders off its slot);
* `formation_start`: measured states in formation with equal velocities;
* `obstacle`, `obstacle_affects`: one disc keep-out ahead of the fleet, binding on
  the agents of the given kind (`:all`, `:quad`, `:rover`) whose reference passes near it;
* `abar_scale`: scales both input bounds (small values make them active);
* `wform`, `random_weights`: formation weight scale, random per-edge factors;
* `wind`: magnitude of a known constant drift acceleration (a nonzero affine
  term `c_{i,t}` in the dynamics);
* `time_varying`: non-uniform steps `h_t`, time-varying drag and drift, a
  formation that scales and rotates, weights that grow along the horizon;
* `switching`: probability that a union-graph edge is absent at an instant;
* `absent`: encoding of absent edges, `:omit` or `:zero`.
"""
Base.@kwdef struct MPCConfig
    n::Int = 6
    H::Int = 8
    h::Float64 = 0.2
    graph::Symbol = :ring
    fleet::Symbol = :mixed
    typing::Symbol = :hard
    rho::Float64 = 10.0
    coherent::Bool = false
    formation_start::Bool = false
    obstacle::Bool = false
    obstacle_affects::Symbol = :all
    abar_scale::Float64 = 1.0
    wform::Float64 = 1.0
    random_weights::Bool = false
    wind::Float64 = 0.0
    speed::Float64 = 1.0
    spacing::Float64 = 1.0
    time_varying::Bool = false
    switching::Float64 = 0.0
    absent::Symbol = :omit
    incoherence::Float64 = 1.0
    seed::Int = 1
end

config_dict(cfg::MPCConfig) = Dict{String,Any}(string(f) => (v = getfield(cfg, f); v isa Symbol ? string(v) : v)
                                               for f in fieldnames(MPCConfig))

_center_ref(tau::Real, speed::Real) = [speed * tau, 0.3 * sin(0.5 * tau)]
_center_vel(tau::Real, speed::Real) = [speed, 0.15 * cos(0.5 * tau)]
_rot(th) = [cos(th) -sin(th); sin(th) cos(th)]

"""
    mpc_spec(cfg; xhat = nothing, t0 = 0.0, nominal = nothing) -> MPCSpec

Make the explicit data of an instance from its configuration. `xhat` overrides
the measured states and `t0` shifts the reference clock (for receding horizon).
With `cfg.obstacle`, the keep-out disc is linearized around `nominal[i]` (a
`2 x (H+1)` array of planar positions per agent; by default the optimal plan of
the obstacle-free problem), one tangent half-space per instant at which the
nominal passes within a margin of the disc.
"""
function mpc_spec(cfg::MPCConfig; xhat = nothing, t0::Real = 0.0, nominal = nothing)
    rng = Xoshiro(cfg.seed)
    n, H = cfg.n, cfg.H
    h = cfg.time_varying ? [cfg.h * (0.6 + 0.8 * rand(rng)) for _ in 1:H] : fill(cfg.h, H)
    tau = t0 .+ [0.0; cumsum(h)]
    wdir = normalize(randn(rng, 2))
    wfac = cfg.time_varying ? [1 + 0.5 * sin(tau[t]) for t in 1:H] : ones(H)
    drift = [cfg.wind * wfac[t] * wdir for t in 1:H]
    drag = cfg.time_varying ? [ROVER_DRAG * (0.5 + rand(rng)) for _ in 1:H] : fill(ROVER_DRAG, H)
    gcols = _grid_shape(n)[2]
    kinds = [cfg.fleet == :mixed ? (isodd(i) ? :quad : :rover) :
             cfg.fleet == :rows ? (isodd((i - 1) ÷ gcols + 1) ? :quad : :rover) : cfg.fleet for i in 1:n]
    agents = [k == :quad ? quad_agent(h; abar = QUAD_ABAR * cfg.abar_scale, drift = drift) :
              rover_agent(h; abar = ROVER_ABAR * cfg.abar_scale, drag = drag, drift = drift)
              for k in kinds]
    gedges0, layout = agent_graph(cfg.graph, n, rng; spacing = cfg.spacing)
    # formation offsets o_{i,t}: the layout, scaled and rotated when time varying
    offsets = zeros(2, n, H + 1)
    for t in 0:H, i in 1:n
        s, th = cfg.time_varying ? (1 + 0.2 * sin(tau[t+1]), 0.1 * (tau[t+1] - t0)) : (1.0, 0.0)
        offsets[:, i, t+1] = s * _rot(th) * layout[i]
    end
    # switching topology on the union graph; edges never present are dropped
    present0 = trues(length(gedges0), H)
    if cfg.switching > 0
        for k in eachindex(gedges0), t in 1:H
            present0[k, t] = rand(rng) >= cfg.switching
        end
    end
    keep = [any(present0[k, :]) for k in eachindex(gedges0)]
    gedges = gedges0[keep]
    present = BitMatrix(present0[keep, :])
    base_w = [cfg.random_weights ? cfg.wform * (0.5 + 1.5 * rand(rng)) : cfg.wform for _ in gedges0][keep]
    fweight = [base_w[k] * (cfg.time_varying ? 0.5 + t / H : 1.0) for k in eachindex(gedges), t in 1:H]
    ftarget = zeros(2, length(gedges), H)
    for (k, (i, j)) in enumerate(gedges), t in 1:H
        ftarget[:, k, t] = offsets[:, j, t+1] - offsets[:, i, t+1]
    end
    # references
    ref = Vector{Matrix{Float64}}(undef, n)
    vref = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        amp, om, ph = 0.3 + 0.5 * rand(rng), 0.5 + rand(rng), 2pi * rand(rng)
        omz, phz = 0.5 + rand(rng), 2pi * rand(rng)
        ny = size(agents[i].Cr, 1)
        R = zeros(ny, H + 1)
        for t in 0:H
            p = _center_ref(tau[t+1], cfg.speed) + offsets[:, i, t+1]
            if !cfg.coherent
                s = tau[t+1] - t0
                p += cfg.incoherence * amp * [sin(om * s + ph) - sin(ph), cos(om * s + ph) - cos(ph)]
            end
            R[1:2, t+1] = p
            if ny == 3
                R[3, t+1] = cfg.coherent ? 1.5 : 1.5 + cfg.incoherence * 0.3 * sin(omz * (tau[t+1] - t0) + phz)
            end
        end
        ref[i] = R
        vc = _center_vel(tau[end], cfg.speed)
        vref[i] = agents[i].kind == :quad ? [vc; 0.0] : vc
    end
    # measured states
    xh = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        ag = agents[i]
        p = _center_ref(tau[1], cfg.speed) + offsets[:, i, 1]
        v = _center_vel(tau[1], cfg.speed)
        if ag.kind == :quad
            x = [p; 1.5; v; 0.0]
            if !cfg.formation_start
                x += [0.3 * randn(rng, 2); 0.2 * randn(rng); 0.2 * randn(rng, 2); 0.1 * randn(rng)]
            end
        else
            x = [p; v]
            if !cfg.formation_start
                x += [0.3 * randn(rng, 2); 0.2 * randn(rng, 2)]
            end
        end
        xh[i] = x
    end
    if xhat !== nothing
        xh = [copy(x) for x in xhat]
    end
    obstacles = NamedTuple{(:center, :radius, :affects),Tuple{Vector{Float64},Float64,Symbol}}[]
    halfspaces = [Tuple{Int,Vector{Float64},Float64}[] for _ in 1:n]
    spec = MPCSpec(n, H, h, agents, gedges, present, ftarget, fweight, xh, ref, vref,
                   halfspaces, cfg.typing, cfg.rho, cfg.absent, offsets, obstacles, config_dict(cfg))
    cfg.obstacle || return spec
    # obstacle: one disc on the path of a front agent, keep-out linearized as
    # tangent half-spaces around a NOMINAL plan of each agent (by default the
    # obstacle-free optimal plan; in receding horizon, the previous plan)
    if nominal === nothing
        mfree = build_model(spec)
        sol = solve_direct(mfree.program)
        isoptimal(sol) || throw(ErrorException("obstacle-free problem not solved: $(sol.status)"))
        nominal = [reduce(hcat, [sol.x[mfree.program.offsets[mfree.vid[i, t+1]] .+ (1:2)] for t in 0:H]) for i in 1:n]
    end
    rad = 0.35 * cfg.spacing
    front = maximum(nominal[i][1, end] for i in 1:n)
    fronts = [i for i in 1:n if nominal[i][1, end] >= front - 0.25 * cfg.spacing]
    ifr = fronts[rand(rng, 1:length(fronts))]
    side = rand(rng) < 0.5 ? -1.0 : 1.0
    tx = max(2, round(Int, 0.6 * H))
    dirv = nominal[ifr][:, tx+1] - nominal[ifr][:, tx]
    nrm = norm(dirv) > 1e-9 ? [-dirv[2], dirv[1]] / norm(dirv) : [0.0, 1.0]
    ctr = nominal[ifr][:, tx+1] + side * 0.8 * rad * nrm
    push!(obstacles, (center = ctr, radius = rad, affects = cfg.obstacle_affects))
    act = rad + 0.3 * cfg.spacing
    for i in 1:n
        (cfg.obstacle_affects == :all || cfg.obstacle_affects == agents[i].kind) || continue
        for t in 1:H
            d = nominal[i][:, t+1] - ctr
            norm(d) <= act || continue
            a = norm(d) > 1e-9 ? d / norm(d) : nrm
            push!(halfspaces[i], (t, a, dot(a, ctr) + rad))
        end
    end
    return MPCSpec(n, H, h, agents, gedges, present, ftarget, fweight, xh, ref, vref,
                   halfspaces, cfg.typing, cfg.rho, cfg.absent, offsets, obstacles, config_dict(cfg))
end

"""
    MPCModel

A built instance: the data (`spec`), the graph program on `G box P_H`, and the
index maps `vid[i, t+1]` (vertex of `(i, t)`), `dyn[i, t+1]` (edge `d_{i,t}`),
`form[k, t]` (edge `f_{ij,t}` for union edge `k`, 0 when omitted).
"""
struct MPCModel
    spec::MPCSpec
    program::GraphProgram
    vid::Matrix{Int}
    dyn::Matrix{Int}
    form::Matrix{Int}
end

_spacedim(ag::AgentModel, t::Int, H::Int) = t < H ? ag.nx + ag.nu : ag.nx

function _stage_node(spec::MPCSpec, i::Int, t::Int)
    ag = spec.agents[i]
    H = spec.H
    nx, nu = ag.nx, ag.nu
    du = t < H ? nu : 0
    d = nx + du
    Q = zeros(d, d); q = zeros(d); c = 0.0
    Wt = t < H ? ag.Q : ag.Qf
    r = spec.ref[i][:, t+1]
    Q[1:nx, 1:nx] .+= ag.Cr' * Wt * ag.Cr
    q[1:nx] .-= ag.Cr' * (Wt * r)
    c += 0.5 * dot(r, Wt * r)
    if t == H && ag.qv > 0
        Sv = zeros(length(ag.vel), nx)
        for (k, idx) in enumerate(ag.vel)
            Sv[k, idx] = 1.0
        end
        Q[1:nx, 1:nx] .+= ag.qv * (Sv' * Sv)
        q[1:nx] .-= ag.qv * (Sv' * spec.vref[i])
        c += 0.5 * ag.qv * dot(spec.vref[i], spec.vref[i])
    end
    du > 0 && (Q[(nx+1):d, (nx+1):d] .+= ag.R)
    Ablocks = Matrix{Float64}[]; b = Float64[]; cones = ConeBlock[]
    if t == 0
        push!(Ablocks, [Matrix{Float64}(I, nx, nx) zeros(nx, du)])
        append!(b, spec.xhat[i]); push!(cones, zero_cone(nx))
    end
    if du > 0
        push!(Ablocks, [zeros(1, d); zeros(nu, nx) -Matrix{Float64}(I, nu, nu)])
        append!(b, [ag.abar; zeros(nu)]); push!(cones, soc_cone(1 + nu))
    end
    hs = [(a, beta) for (tt, a, beta) in spec.halfspaces[i] if tt == t]
    if !isempty(hs)
        for (a, beta) in hs
            push!(Ablocks, [-(a' * ag.C) zeros(1, du)])
            push!(b, -beta)
        end
        push!(cones, nonneg_cone(length(hs)))
    end
    A = isempty(Ablocks) ? zeros(0, d) : reduce(vcat, Ablocks)
    return NodeData(Q, q, c, A, b, cones)
end

"""
    build_model(spec) -> MPCModel

Assemble THEORY Def 4.1 for the data `spec`: vertices in agent-major order
(`(1,0), (1,1), ..., (1,H), (2,0), ...`), then the dynamics edges, then the
formation edges instant by instant.
"""
function build_model(spec::MPCSpec)
    n, H = spec.n, spec.H
    vid = zeros(Int, n, H + 1)
    nodes = NodeData[]
    for i in 1:n, t in 0:H
        push!(nodes, _stage_node(spec, i, t))
        vid[i, t+1] = length(nodes)
    end
    edges = GraphEdge[]
    dyn = zeros(Int, n, H)
    for i in 1:n, t in 0:(H-1)
        ag = spec.agents[i]
        dh = _spacedim(ag, t + 1, H) - ag.nx
        Ft = [ag.A[t+1] ag.B[t+1]]
        Fh = [Matrix{Float64}(I, ag.nx, ag.nx) zeros(ag.nx, dh)]
        hard = spec.typing == :hard || (t == 0 && spec.typing != :soft)
        W = spec.rho * Matrix{Float64}(I, ag.nx, ag.nx)
        push!(edges, GraphEdge(vid[i, t+1], vid[i, t+2], Ft, Fh, hard, W, ag.c[t+1],
                               EdgeTag(:dyn, i, i, t)))
        dyn[i, t+1] = length(edges)
    end
    form = zeros(Int, length(spec.gedges), H)
    for t in 1:H, (k, (i, j)) in enumerate(spec.gedges)
        ag_i, ag_j = spec.agents[i], spec.agents[j]
        di, dj = _spacedim(ag_i, t, H), _spacedim(ag_j, t, H)
        if spec.present[k, t]
            Ci = [ag_i.C zeros(2, di - ag_i.nx)]
            Cj = [ag_j.C zeros(2, dj - ag_j.nx)]
            W = spec.fweight[k, t] * Matrix{Float64}(I, 2, 2)
            push!(edges, GraphEdge(vid[i, t+1], vid[j, t+1], Ci, Cj, false, W,
                                   spec.ftarget[:, k, t], EdgeTag(:form, i, j, t)))
            form[k, t] = length(edges)
        elseif spec.absent == :zero
            push!(edges, GraphEdge(vid[i, t+1], vid[j, t+1], zeros(0, di), zeros(0, dj), false,
                                   zeros(0, 0), Float64[], EdgeTag(:form, i, j, t)))
            form[k, t] = length(edges)
        end
    end
    return MPCModel(spec, GraphProgram(nodes, edges), vid, dyn, form)
end

build_model(cfg::MPCConfig; kwargs...) = build_model(mpc_spec(cfg; kwargs...))
build_mpc(; kwargs...) = build_model(MPCConfig(; kwargs...))

"""The same data with the other encoding of absent edges (`:omit` <-> `:zero`)."""
function with_absent_encoding(spec::MPCSpec, absent::Symbol)
    return MPCSpec(spec.n, spec.H, spec.h, spec.agents, spec.gedges, spec.present, spec.ftarget,
                   spec.fweight, spec.xhat, spec.ref, spec.vref, spec.halfspaces, spec.typing,
                   spec.rho, absent, spec.offsets, spec.obstacles, spec.config)
end

"""The same data with another dynamics typing (`:hard` or `:virtual`) and weight `rho`."""
function with_typing(spec::MPCSpec, typing::Symbol; rho::Real = spec.rho)
    return MPCSpec(spec.n, spec.H, spec.h, spec.agents, spec.gedges, spec.present, spec.ftarget,
                   spec.fweight, spec.xhat, spec.ref, spec.vref, spec.halfspaces, typing,
                   Float64(rho), spec.absent, spec.offsets, spec.obstacles, spec.config)
end

# ---------------------------------------------------------------------------
# Resolutions of G box P_H
# ---------------------------------------------------------------------------

nverts(model::MPCModel) = nvertices(model.program)

"""`(agent, time)` of every vertex."""
function vertex_coordinates(model::MPCModel)
    n, H = model.spec.n, model.spec.H
    agent = zeros(Int, n * (H + 1)); time = zeros(Int, n * (H + 1))
    for i in 1:n, t in 0:H
        v = model.vid[i, t+1]
        agent[v] = i; time[v] = t
    end
    return agent, time
end

"""
    product_partition(model, alpha, beta)

The product resolution `alpha box beta`: `alpha[i]` labels agent `i`'s cluster,
`beta[t+1]` labels instant `t`'s time block (an interval partition for a time
blocking); vertex `(i, t)` goes to block `(alpha[i], beta[t+1])`.
"""
function product_partition(model::MPCModel, alpha::AbstractVector{<:Integer}, beta::AbstractVector{<:Integer})
    n, H = model.spec.n, model.spec.H
    length(alpha) == n && length(beta) == H + 1 || throw(DimensionMismatch("alpha needs $n labels, beta $(H+1)"))
    d = Dict{Tuple{Int,Int},Int}()
    Pi = zeros(Int, nverts(model))
    for i in 1:n, t in 0:H
        Pi[model.vid[i, t+1]] = get!(d, (Int(alpha[i]), Int(beta[t+1])), length(d) + 1)
    end
    return canonical_partition(Pi)
end

"""`id_G box !`: one block per agent path, the time leg (full condensing)."""
time_leg(model::MPCModel) = product_partition(model, 1:model.spec.n, ones(Int, model.spec.H + 1))
"""`! box id_P`: one block per instant, the agent leg (full centralization)."""
agent_leg(model::MPCModel) = product_partition(model, ones(Int, model.spec.n), 1:(model.spec.H+1))
"""`! box !`: one block, the corner."""
corner_partition(model::MPCModel) = ones(Int, nverts(model))
"""The bottom of the lattice: singletons."""
bottom_partition(model::MPCModel) = collect(1:nverts(model))

"""A random interval partition of `{0..H}`: each of the `H` cut points is cut with probability `p`."""
function random_time_blocking(H::Int, rng::AbstractRNG; p::Real = 0.5)
    beta = ones(Int, H + 1)
    for t in 1:H
        beta[t+1] = beta[t] + (rand(rng) < p ? 1 : 0)
    end
    return beta
end

"""A random clustering of the agents into `k` clusters, connected in the union graph (region growing)."""
function random_agent_clustering(spec::MPCSpec, rng::AbstractRNG, k::Integer)
    n = spec.n
    k = clamp(k, 1, n)
    adj = [Int[] for _ in 1:n]
    for (i, j) in spec.gedges
        push!(adj[i], j); push!(adj[j], i)
    end
    label = zeros(Int, n)
    seeds = randperm(rng, n)[1:k]
    for (c, s) in enumerate(seeds)
        label[s] = c
    end
    while any(==(0), label)
        cand = [(v, u) for v in 1:n if label[v] != 0 for u in adj[v] if label[u] == 0]
        if isempty(cand)
            u = findfirst(==(0), label)
            label[u] = rand(rng, 1:k)
        else
            v, u = rand(rng, cand)
            label[u] = label[v]
        end
    end
    return canonical_partition(label)
end

"""
    virtual_base_partition(model)

`Pi_0` of THEORY Prop 4.6: `(i, 0)` merged with `(i, 1)` for every agent, all
other vertices singletons.
"""
function virtual_base_partition(model::MPCModel)
    Pi = collect(1:nverts(model))
    for i in 1:model.spec.n
        Pi[model.vid[i, 2]] = model.vid[i, 1]
    end
    return canonical_partition(Pi)
end

"""THEORY Prop 4.6: every first dynamics edge `d_{i,0}` is hard or collapsed."""
function implementable(model::MPCModel, Pi::AbstractVector{<:Integer})
    P = model.program
    return all(i -> (e = model.dyn[i, 1]; P.edges[e].hard || Pi[P.edges[e].tail] == Pi[P.edges[e].head]),
               1:model.spec.n)
end

# ---------------------------------------------------------------------------
# Independent reference QPs (built from the physical data, not from the graph)
# ---------------------------------------------------------------------------

"""
Condensing matrices of one agent: `x_t = Phi[t+1] xhat + Gam[t+1] u + g[t+1]`
for `t = 0..H`, `u = (u_0, ..., u_{H-1})`, by the recursion
`Phi_{t+1} = A_t Phi_t`, `Gam_{t+1} = A_t Gam_t + B_t S_t`, `g_{t+1} = A_t g_t + c_t`.
"""
function condensing_matrices(ag::AgentModel, H::Int)
    nx, nu = ag.nx, ag.nu
    Phi = Vector{Matrix{Float64}}(undef, H + 1)
    Gam = Vector{Matrix{Float64}}(undef, H + 1)
    g = Vector{Vector{Float64}}(undef, H + 1)
    Phi[1] = Matrix{Float64}(I, nx, nx)
    Gam[1] = zeros(nx, nu * H)
    g[1] = zeros(nx)
    for t in 0:(H-1)
        S = zeros(nu, nu * H)
        S[:, (t*nu+1):((t+1)*nu)] = Matrix{Float64}(I, nu, nu)
        Phi[t+2] = ag.A[t+1] * Phi[t+1]
        Gam[t+2] = ag.A[t+1] * Gam[t+1] + ag.B[t+1] * S
        g[t+2] = ag.A[t+1] * g[t+1] + ag.c[t+1]
    end
    return Phi, Gam, g
end

"""Accumulate `(1/2)||M z + m0||^2_W` into `(Hz, gz, cz)`."""
function _add_ls!(Hz, gz, cz::Base.RefValue{Float64}, M, m0, W)
    WM = W * M
    Hz .+= M' * WM
    gz .+= M' * (W * m0)
    cz[] += 0.5 * dot(m0, W * m0)
    return nothing
end

"""
    condensed_qp(spec) -> NamedTuple

The fully condensed hard MPC of THEORY Prop 4.2, coded directly from the model
data with the condensing matrices of every agent, on the UNION agent graph: the
decision variable is the stacked input sequences `U = (u_1, ..., u_n)`, the
edge `ij` of the union graph carries one block of residuals per instant at
which `ij` is present (a direct sum, nothing merged), node sets are the input
cones and the keep-out half-spaces rewritten in `U`. Returns the QP
`min (1/2) U'HU + g'U + c s.t. b - A U in K` (Clarabel cones), and `to_fine(U)`,
the full trajectory in the graph program's variable order.
"""
function condensed_qp(spec::MPCSpec)
    n, H = spec.n, spec.H
    cond = [condensing_matrices(ag, H) for ag in spec.agents]
    nus = [ag.nu * H for ag in spec.agents]
    uoff = [0; cumsum(nus)]
    nU = uoff[end]
    Hz = zeros(nU, nU); gz = zeros(nU); cz = Ref(0.0)
    # agent i's state at t as an affine function of U: X[i][t+1] * U + x0[i][t+1]
    X = [[zeros(spec.agents[i].nx, nU) for _ in 0:H] for i in 1:n]
    x0 = [[zeros(spec.agents[i].nx) for _ in 0:H] for i in 1:n]
    for i in 1:n
        Phi, Gam, g = cond[i]
        cols = (uoff[i]+1):uoff[i+1]
        for t in 0:H
            X[i][t+1][:, cols] = Gam[t+1]
            x0[i][t+1] = Phi[t+1] * spec.xhat[i] + g[t+1]
        end
    end
    for i in 1:n
        ag = spec.agents[i]
        for t in 0:H
            Wt = t < H ? ag.Q : ag.Qf
            _add_ls!(Hz, gz, cz, ag.Cr * X[i][t+1], ag.Cr * x0[i][t+1] - spec.ref[i][:, t+1], Wt)
        end
        Sv = zeros(length(ag.vel), ag.nx)
        for (k, idx) in enumerate(ag.vel)
            Sv[k, idx] = 1.0
        end
        _add_ls!(Hz, gz, cz, Sv * X[i][H+1], Sv * x0[i][H+1] - spec.vref[i], ag.qv * Matrix{Float64}(I, length(ag.vel), length(ag.vel)))
        Reff = kron(Matrix{Float64}(I, H, H), ag.R)
        cols = (uoff[i]+1):uoff[i+1]
        Hz[cols, cols] .+= Reff
    end
    # formation on the union graph: one stacked block per edge, one summand per present instant
    for (k, (i, j)) in enumerate(spec.gedges)
        Tk = [t for t in 1:H if spec.present[k, t]]
        isempty(Tk) && continue
        M = reduce(vcat, [spec.agents[j].C * X[j][t+1] - spec.agents[i].C * X[i][t+1] for t in Tk])
        m0 = reduce(vcat, [spec.agents[j].C * x0[j][t+1] - spec.agents[i].C * x0[i][t+1] - spec.ftarget[:, k, t] for t in Tk])
        W = Matrix(Diagonal(reduce(vcat, [fill(spec.fweight[k, t], 2) for t in Tk])))
        _add_ls!(Hz, gz, cz, M, m0, W)
    end
    Hz = (Hz + Hz') / 2
    # constraints: input cones, half-spaces
    Arows = Matrix{Float64}[]; brows = Float64[]; cones = ConeBlock[]
    for i in 1:n
        ag = spec.agents[i]
        for t in 0:(H-1)
            Au = zeros(1 + ag.nu, nU)
            Au[2:end, (uoff[i]+t*ag.nu+1):(uoff[i]+(t+1)*ag.nu)] = -Matrix{Float64}(I, ag.nu, ag.nu)
            push!(Arows, Au); append!(brows, [ag.abar; zeros(ag.nu)]); push!(cones, soc_cone(1 + ag.nu))
        end
        for (t, a, beta) in spec.halfspaces[i]
            row = a' * ag.C
            push!(Arows, -row * X[i][t+1]); push!(brows, dot(row, x0[i][t+1]) - beta)
            push!(cones, nonneg_cone(1))
        end
    end
    A = isempty(Arows) ? zeros(0, nU) : reduce(vcat, Arows)
    function to_fine(U::AbstractVector)
        out = Float64[]
        for i in 1:n
            ag = spec.agents[i]
            for t in 0:H
                append!(out, X[i][t+1] * U + x0[i][t+1])
                t < H && append!(out, U[(uoff[i]+t*ag.nu+1):(uoff[i]+(t+1)*ag.nu)])
            end
        end
        return out
    end
    return (H = Hz, g = gz, c = cz[], A = A, b = brows, cones = cones, to_fine = to_fine, nU = nU)
end

"""
    virtual_structure_qp(spec) -> NamedTuple

The virtual-structure controller of THEORY Prop 4.3 coded directly: ONE center
agent (the common dynamics of an identical fleet), every agent placed at
`x_i = x_c + E o_i` and driven by the center's input. Requires an identical
fleet with time-invariant offsets and the fleet starting in formation with
equal velocities. Returns the QP in the center's inputs and `to_fine(u_c)`.
"""
function virtual_structure_qp(spec::MPCSpec; tol::Real = 1e-12)
    n, H = spec.n, spec.H
    ag = spec.agents[1]
    all(a -> a.kind == ag.kind && a.A == ag.A && a.B == ag.B && a.c == ag.c && a.C == ag.C &&
             a.Q == ag.Q && a.Qf == ag.Qf && a.R == ag.R && a.abar == ag.abar && a.qv == ag.qv,
        spec.agents) || throw(ArgumentError("virtual_structure_qp needs an identical fleet"))
    o = [spec.offsets[:, i, 1] for i in 1:n]
    all(t -> all(i -> spec.offsets[:, i, t] == o[i], 1:n), 1:(H+1)) ||
        throw(ArgumentError("virtual_structure_qp needs time-invariant offsets"))
    xc0 = spec.xhat[1] - ag.E * o[1]
    for i in 1:n
        norm(spec.xhat[i] - (xc0 + ag.E * o[i]), Inf) <= tol ||
            throw(ArgumentError("virtual_structure_qp needs the fleet to start in formation"))
    end
    Phi, Gam, g = condensing_matrices(ag, H)
    nU = ag.nu * H
    Hz = zeros(nU, nU); gz = zeros(nU); cz = Ref(0.0)
    Sv = zeros(length(ag.vel), ag.nx)
    for (k, idx) in enumerate(ag.vel)
        Sv[k, idx] = 1.0
    end
    for i in 1:n
        for t in 0:H
            Wt = t < H ? ag.Q : ag.Qf
            _add_ls!(Hz, gz, cz, ag.Cr * Gam[t+1], ag.Cr * (Phi[t+1] * xc0 + g[t+1] + ag.E * o[i]) - spec.ref[i][:, t+1], Wt)
        end
        _add_ls!(Hz, gz, cz, Sv * Gam[H+1], Sv * (Phi[H+1] * xc0 + g[H+1]) - spec.vref[i],
                 ag.qv * Matrix{Float64}(I, length(ag.vel), length(ag.vel)))
        Hz .+= kron(Matrix{Float64}(I, H, H), ag.R)
    end
    # formation energy of the rigid fleet (a constant, zero for exact targets)
    for (k, (i, j)) in enumerate(spec.gedges), t in 1:H
        spec.present[k, t] || continue
        r = ag.C * ag.E * (o[j] - o[i]) - spec.ftarget[:, k, t]
        cz[] += 0.5 * spec.fweight[k, t] * dot(r, r)
    end
    Hz = (Hz + Hz') / 2
    Arows = Matrix{Float64}[]; brows = Float64[]; cones = ConeBlock[]
    for t in 0:(H-1)
        Au = zeros(1 + ag.nu, nU)
        Au[2:end, (t*ag.nu+1):((t+1)*ag.nu)] = -Matrix{Float64}(I, ag.nu, ag.nu)
        push!(Arows, Au); append!(brows, [ag.abar; zeros(ag.nu)]); push!(cones, soc_cone(1 + ag.nu))
    end
    for i in 1:n, (t, a, beta) in spec.halfspaces[i]
        row = a' * ag.C
        push!(Arows, -row * Gam[t+1]); push!(brows, dot(row, Phi[t+1] * xc0 + g[t+1] + ag.E * o[i]) - beta)
        push!(cones, nonneg_cone(1))
    end
    A = isempty(Arows) ? zeros(0, nU) : reduce(vcat, Arows)
    function to_fine(u::AbstractVector)
        out = Float64[]
        for i in 1:n, t in 0:H
            append!(out, Phi[t+1] * xc0 + Gam[t+1] * u + g[t+1] + ag.E * o[i])
            t < H && append!(out, u[(t*ag.nu+1):((t+1)*ag.nu)])
        end
        return out
    end
    return (H = Hz, g = gz, c = cz[], A = A, b = brows, cones = cones, to_fine = to_fine, nU = nU)
end
