# common_spatial.jl: shared helpers of the spatial experiments E6 (adaptive
# spatial resolution) and E8 (spatial reduced-order models at scale).
#
# * `FleetScenario`, `fleet_spec`: a heterogeneous grid fleet on a rows x cols
#   grid formation, the rows alternating between quadrotors (odd rows) and
#   ground vehicles (even rows), with three levels of data coherence, fixed
#   world obstacles whose keep-out discs are linearized as tangent half-spaces
#   about a nominal plan, and receding-horizon rebuilds (a shifted clock and new
#   measured states) that keep the references and the obstacles fixed in the
#   world.
# * grid clusterings (rows, strips of rows, rectangular blocks, the whole fleet),
#   lifted to the time-expanded graph as the spatial resolution `alpha box id`.
# * the cluster estimator of THEORY Sec. 5 and the manuscript's Sec. VI-F: the
#   minimum W^{-1}-norm internal forces of every rigidified spring, recovered
#   block by block from the coarse solve (`local_multipliers`), summed per
#   cluster over the instants of the horizon.
# * the refinement step of Algorithm alg:refine: Dorfler marking and a minimum
#   cut of a marked cluster's internal graph separating the two endpoints of its
#   highest-estimator spring.
#
# Only the library's public API is used; nothing in src/ is modified.

isdefined(Main, :write_results) || include(joinpath(@__DIR__, "common.jl"))

const ObstacleT = NamedTuple{(:center, :radius, :affects),Tuple{Vector{Float64},Float64,Symbol}}

# ---------------------------------------------------------------------------
# The grid and its clusterings
# ---------------------------------------------------------------------------

"""Index of the agent in row `r`, column `c` of a grid with `cols` columns (row major)."""
sp_index(r::Integer, c::Integer, cols::Integer) = (r - 1) * cols + c
"""`(row, column)` of agent `i`."""
sp_rowcol(i::Integer, cols::Integer) = (div(i - 1, cols) + 1, rem(i - 1, cols) + 1)

"""
    sp_grid(rows, cols; spacing) -> (edges, layout)

The grid formation graph (edges `i < j` between horizontal and vertical
neighbours, the same edge order as `agent_graph(:grid)`) and its shape: agent
`(r, c)` sits at `spacing * (c - (cols+1)/2, r - (rows+1)/2)`, so rows are
lines of constant `y` (lanes along the direction of travel `+x`) and the
formation is centred at the origin.
"""
function sp_grid(rows::Integer, cols::Integer; spacing::Real = 1.0)
    n = rows * cols
    edges = Tuple{Int,Int}[]
    layout = [zeros(2) for _ in 1:n]
    for r in 1:rows, c in 1:cols
        i = sp_index(r, c, cols)
        layout[i] = spacing * [c - (cols + 1) / 2, r - (rows + 1) / 2]
        c < cols && push!(edges, (i, sp_index(r, c + 1, cols)))
        r < rows && push!(edges, (i, sp_index(r + 1, c, cols)))
    end
    return edges, layout
end

"""Agent kind by row: quadrotors on odd rows, ground vehicles (rovers) on even rows."""
sp_kind(r::Integer) = isodd(r) ? :quad : :rover

sp_singletons(rows, cols) = collect(1:(rows*cols))
"""Clustering by rows (almost equitable for uniform weights: one neighbour in each adjacent row)."""
sp_rows(rows, cols) = [sp_rowcol(i, cols)[1] for i in 1:(rows*cols)]
"""Strips of `k` consecutive whole rows (mixed kinds when `k >= 2`; not almost equitable)."""
sp_strips(rows, cols, k) = canonical_partition([cld(sp_rowcol(i, cols)[1], k) for i in 1:(rows*cols)])
"""Rectangular blocks of `a` rows by `b` columns (quadtree levels for `a = b = 2^l`)."""
function sp_blocks(rows, cols, a, b)
    nb = cld(cols, b)
    return canonical_partition([(cld(sp_rowcol(i, cols)[1], a) - 1) * nb + cld(sp_rowcol(i, cols)[2], b) for i in 1:(rows*cols)])
end
sp_whole(rows, cols) = ones(Int, rows * cols)

"""The spatial resolution `alpha box id` of `G box P_H` for an agent clustering `alpha`."""
spatial_partition(model::MPCModel, alpha::AbstractVector{<:Integer}) =
    product_partition(model, alpha, 1:(model.spec.H+1))

"""Connected components of the subgraph of `edges` induced on `members`."""
function sp_components(members::Vector{Int}, edges::Vector{Tuple{Int,Int}})
    pos = Dict(v => k for (k, v) in enumerate(members))
    parent = collect(1:length(members))
    find(a) = (while parent[a] != a; parent[a] = parent[parent[a]]; a = parent[a]; end; a)
    for (i, j) in edges
        (haskey(pos, i) && haskey(pos, j)) || continue
        a, b = find(pos[i]), find(pos[j])
        a != b && (parent[max(a, b)] = min(a, b))
    end
    comps = Dict{Int,Vector{Int}}()
    for (k, v) in enumerate(members)
        push!(get!(comps, find(k), Int[]), v)
    end
    return sort([sort(c) for c in values(comps)]; by = first)
end

"""True when every cluster of `alpha` induces a connected subgraph of the agent graph."""
function sp_clusters_connected(alpha::AbstractVector{<:Integer}, edges::Vector{Tuple{Int,Int}})
    members = block_members(canonical_partition(alpha))
    return all(m -> length(sp_components(m, edges)) == 1, members)
end

# ---------------------------------------------------------------------------
# The fleet scenario
# ---------------------------------------------------------------------------

"""
    FleetScenario(; kwargs...)

A heterogeneous grid fleet flying a formation in `+x`:

* `rows x cols` agents, `spacing` between neighbours, rows alternating between
  quadrotors (3D double integrators tracking a planar reference and an
  altitude, `||a|| <= 4 abar_scale`) and ground vehicles (planar double
  integrators with drag 0.4, `||a|| <= 2 abar_scale`), the library's agent
  models with their default weights;
* horizon `H`, step `h`; formation springs of weight `wform` on every grid edge,
  targets `o_j - o_i` from the grid shape (realizable around every cycle);
* `coherence`: `:fleet` (every agent tracks the formation centre plus its
  offset; the fleet is coherent), `:rows` (each row tracks its own centre
  trajectory, rows disagreeing in speed, lateral motion and altitude; coherent
  inside every row, THEORY revision item 6), `:agents` (each agent adds its own
  lateral wiggle: incoherent);
* `obstacles`: discs fixed in the world, each keeping out the agents of kind
  `affects` (`:all`, `:quad`, `:rover`); the keep-out is linearized about a
  nominal plan as one tangent half-space per instant at which the nominal
  position is within `radius + margin` of the centre (the model's convention,
  `mpc_spec`);
* the fleet starts in formation at the origin with a common velocity, so every
  clustering is feasible at the first step; `seed` fixes the per-row and per-agent reference parameters.
"""
Base.@kwdef struct FleetScenario
    rows::Int = 6
    cols::Int = 6
    H::Int = 10
    h::Float64 = 0.2
    spacing::Float64 = 1.0
    wform::Float64 = 1.0
    coherence::Symbol = :fleet
    speed::Float64 = 1.0
    abar_scale::Float64 = 1.0
    obstacles::Vector{ObstacleT} = ObstacleT[]
    margin::Float64 = 0.3
    seed::Int = 1
end

nagents(sc::FleetScenario) = sc.rows * sc.cols

scenario_dict(sc::FleetScenario) = Dict{String,Any}(
    "rows" => sc.rows, "cols" => sc.cols, "n" => nagents(sc), "H" => sc.H, "h" => sc.h,
    "spacing" => sc.spacing, "wform" => sc.wform, "coherence" => string(sc.coherence),
    "speed" => sc.speed, "abar_scale" => sc.abar_scale, "margin" => sc.margin, "seed" => sc.seed,
    "obstacles" => [Dict{String,Any}("center" => o.center, "radius" => o.radius, "affects" => string(o.affects))
                    for o in sc.obstacles],
    "kinds" => "odd rows quadrotors (quad_agent), even rows ground vehicles (rover_agent)")

"""The per-row and per-agent reference parameters, drawn once from the seed."""
function scenario_params(sc::FleetScenario)
    rng = Xoshiro(sc.seed)
    n = nagents(sc)
    row = [(speed = sc.speed * (0.8 + 0.4 * rand(rng)), amp = 0.1 + 0.3 * rand(rng), om = 0.5 + rand(rng),
            ph = 2pi * rand(rng), alt = 1.5 + 0.4 * (rand(rng) - 0.5)) for _ in 1:sc.rows]
    agent = [(amp = 0.3 + 0.5 * rand(rng), om = 0.5 + rand(rng), ph = 2pi * rand(rng),
              ampz = 0.3 * rand(rng), omz = 0.5 + rand(rng), phz = 2pi * rand(rng)) for _ in 1:n]
    return (row = row, agent = agent)
end

_sp_center(sc, tau) = [sc.speed * tau, 0.3 * sin(0.5 * tau)]
_sp_center_vel(sc, tau) = [sc.speed, 0.15 * cos(0.5 * tau)]

"""Planar reference position, velocity and altitude of agent `i` at world time `tau`."""
function reference(sc::FleetScenario, prm, layout, i::Int, tau::Real)
    r, _ = sp_rowcol(i, sc.cols)
    if sc.coherence == :fleet
        return _sp_center(sc, tau) + layout[i], _sp_center_vel(sc, tau), 1.5
    elseif sc.coherence == :rows
        q = prm.row[r]
        p = [q.speed * tau, q.amp * (sin(q.om * tau + q.ph) - sin(q.ph))]
        v = [q.speed, q.amp * q.om * cos(q.om * tau + q.ph)]
        return p + layout[i], v, q.alt
    elseif sc.coherence == :agents
        a = prm.agent[i]
        p = _sp_center(sc, tau) + layout[i] + a.amp * [sin(a.om * tau + a.ph) - sin(a.ph), cos(a.om * tau + a.ph) - cos(a.ph)]
        v = _sp_center_vel(sc, tau) + a.amp * a.om * [cos(a.om * tau + a.ph), -sin(a.om * tau + a.ph)]
        z = 1.5 + a.ampz * (sin(a.omz * tau + a.phz) - sin(a.phz))
        return p, v, z
    else
        throw(ArgumentError("unknown coherence $(sc.coherence)"))
    end
end

"""The measured start: the formation at the origin, common velocity, quadrotors at altitude 1.5."""
function formation_start(sc::FleetScenario, layout)
    v0 = _sp_center_vel(sc, 0.0)
    return [sp_kind(sp_rowcol(i, sc.cols)[1]) == :quad ? [layout[i]; 1.5; v0; 0.0] : [layout[i]; v0]
            for i in 1:nagents(sc)]
end

"""
    fleet_spec(sc; xhat, t0, nominal, with_obstacles) -> MPCSpec

The explicit data of THEORY Def 4.1 for the scenario at world time `t0` with
measured states `xhat` (default: the formation start). The keep-out discs are
linearized about `nominal[i]` (a `2 x (H+1)` array of planar positions per
agent; default: the optimal plan of the same problem without obstacles), one
tangent half-space `a' C x_{i,t} >= a' c + radius` per affected agent and
instant `t >= 1` at which the nominal is within `radius + margin` of the centre
`c`, with `a` the unit vector from `c` to the nominal position.
"""
function fleet_spec(sc::FleetScenario; xhat = nothing, t0::Real = 0.0, nominal = nothing,
                    with_obstacles::Bool = true, prm = scenario_params(sc))
    n, H = nagents(sc), sc.H
    hv = fill(sc.h, H)
    gedges, layout = sp_grid(sc.rows, sc.cols; spacing = sc.spacing)
    kinds = [sp_kind(sp_rowcol(i, sc.cols)[1]) for i in 1:n]
    agents = [k == :quad ? quad_agent(hv; abar = Resolution.QUAD_ABAR * sc.abar_scale) :
              rover_agent(hv; abar = Resolution.ROVER_ABAR * sc.abar_scale) for k in kinds]
    tau = t0 .+ sc.h .* (0:H)
    offsets = zeros(2, n, H + 1)
    for i in 1:n, t in 0:H
        offsets[:, i, t+1] = layout[i]
    end
    ftarget = zeros(2, length(gedges), H)
    for (k, (i, j)) in enumerate(gedges), t in 1:H
        ftarget[:, k, t] = layout[j] - layout[i]
    end
    fweight = fill(sc.wform, length(gedges), H)
    ref = Vector{Matrix{Float64}}(undef, n)
    vref = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        ny = size(agents[i].Cr, 1)
        R = zeros(ny, H + 1)
        for t in 0:H
            p, _, z = reference(sc, prm, layout, i, tau[t+1])
            R[1:2, t+1] = p
            ny == 3 && (R[3, t+1] = z)
        end
        ref[i] = R
        _, v, _ = reference(sc, prm, layout, i, tau[end])
        vref[i] = kinds[i] == :quad ? [v; 0.0] : v
    end
    xh = xhat === nothing ? formation_start(sc, layout) : [copy(x) for x in xhat]
    halfspaces = [Tuple{Int,Vector{Float64},Float64}[] for _ in 1:n]
    cfg = scenario_dict(sc)
    cfg["t0"] = t0
    mk(hs, obs) = MPCSpec(n, H, hv, agents, gedges, trues(length(gedges), H), ftarget, fweight, xh, ref, vref,
                          hs, :hard, 10.0, :omit, offsets, obs, cfg)
    (with_obstacles && !isempty(sc.obstacles)) || return mk(halfspaces, ObstacleT[])
    if nominal === nothing
        free = build_model(mk(halfspaces, ObstacleT[]))
        sol = solve_direct(free.program)
        isoptimal(sol) || throw(ErrorException("obstacle-free problem not solved: $(sol.status)"))
        nominal = planned_positions(free, sol.x)
    end
    for ob in sc.obstacles, i in 1:n
        (ob.affects == :all || ob.affects == kinds[i]) || continue
        for t in 1:H
            d = nominal[i][:, t+1] - ob.center
            norm(d) <= ob.radius + sc.margin || continue
            a = norm(d) > 1e-9 ? d / norm(d) : [0.0, 1.0]
            push!(halfspaces[i], (t, a, dot(a, ob.center) + ob.radius))
        end
    end
    return mk(halfspaces, copy(sc.obstacles))
end

"""Planar positions `p_{i,t}` (a `2 x (H+1)` array per agent) of a flat plan of the fine program."""
function planned_positions(model::MPCModel, x::AbstractVector)
    P = model.program
    return [reduce(hcat, [x[P.offsets[model.vid[i, t+1]] .+ (1:2)] for t in 0:model.spec.H]) for i in 1:model.spec.n]
end

"""States `x_{i,t}` and inputs `u_{i,t}` of agent `i` read off a flat plan."""
function agent_state(model::MPCModel, x::AbstractVector, i::Int, t::Int)
    ag = model.spec.agents[i]
    r = vrange(model.program, model.vid[i, t+1])
    return x[r[1:ag.nx]], (t < model.spec.H ? x[r[(ag.nx+1):end]] : Float64[])
end

"""The shifted plan used as the next nominal: positions at `t+1..H`, the last one extrapolated."""
function shifted_nominal(pos::Vector{Matrix{Float64}})
    return [hcat(p[:, 2:end], 2 * p[:, end] - p[:, end-1]) for p in pos]
end

"""
Minimum planar clearance `||p - c|| - radius` over the members of a cluster and
the instants of a plan (negative inside the disc), for one obstacle.
"""
function clearance(pos::Vector{Matrix{Float64}}, members, ob::ObstacleT)
    return minimum(minimum(norm(pos[i][:, t] - ob.center) - ob.radius for t in axes(pos[i], 2)) for i in members)
end

# ---------------------------------------------------------------------------
# Timing and sizes
# ---------------------------------------------------------------------------

"""Median wall time of `k` runs of `f()` (after one untimed warm-up if `warm`), and the last value."""
function timed_median(f, k::Int; warm::Bool = false)
    warm && f()
    ts = Float64[]
    val = nothing
    for _ in 1:k
        GC.gc(false)
        t = @elapsed val = f()
        push!(ts, t)
    end
    return median(ts), ts, val
end

"""
Median over `k` runs of `f()` of the wall time, of the time outside garbage
collection and of the bytes allocated (`@timed`), and the last value.
"""
function timed_median_gc(f, k::Int)
    ts = Float64[]; ng = Float64[]; gcs = Float64[]; by = Float64[]
    val = nothing
    for _ in 1:k
        GC.gc()
        st = @timed f()
        val = st.value
        push!(ts, st.time); push!(ng, st.time - st.gctime); push!(gcs, st.gctime); push!(by, st.bytes)
    end
    return (time = median(ts), nogc = median(ng), gc = median(gcs), bytes = median(by), times = ts, nogc_times = ng), val
end

"""
Free dimension of a program: the number of independent decisions, `dim C^0`
minus the rank (sparse QR) of its equality rows (hard edges and zero-cone node
rows). For the MPC graph it is the number of free inputs: `(2n + n_quads) H` for
the fine fleet, `(2k + n_quads) H` for `k` rigid clusters (each keeps its common
planar acceleration, every quadrotor its altitude input).
"""
function free_dimension(P::GraphProgram)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    A0, _ = node_equalities(P)
    A = [edge_operator(P, hard); A0]
    return c0dim(P) - (size(A, 1) == 0 ? 0 : rank(qr(A)))
end

"""Program size: vertices, variables (`dim C^0`), edges, hard and soft edges, `dim C^1`, Hessian and constraint nonzeros."""
function program_size(P::GraphProgram)
    Hq, _, _ = quadratic_form(P)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    An, _, _, _ = node_constraints(P)
    Dh = edge_operator(P, hard)
    return Dict{String,Any}("vertices" => nvertices(P), "variables" => c0dim(P), "edges" => nedges(P),
                            "hard_edges" => length(hard_edges(P)), "soft_edges" => length(soft_edges(P)),
                            "c1" => c1dim(P), "hard_rows" => size(Dh, 1), "cone_rows" => size(An, 1),
                            "nnz_hessian" => nnz(Hq), "nnz_constraints" => nnz(Dh) + nnz(An))
end

# ---------------------------------------------------------------------------
# The cluster estimator and the refinement step (Algorithm alg:refine)
# ---------------------------------------------------------------------------

"""
    cluster_estimator(model, alpha, Pc, L, solc) -> NamedTuple

The estimator of the manuscript's Sec. VI-F for the spatial resolution of the
agent clustering `alpha`: the minimum W^{-1}-norm internal forces of the
rigidified formation springs, recovered block by block from the coarse solve
(`local_multipliers`, normal cone a variable); per spring `f_{ij,t}` the energy
`eta = (1/2)||mu||^2_{W^{-1}}`; per agent-graph edge `ij` the sum over the
instants of the horizon (the spring `ij` of the reduced agent `c`); per
cluster `eta_B`, the sum over its springs. Returns `eta_cluster` (by canonical
cluster id), `eta_edge` (a Dict from `(i, j)` to its estimator), `mu` (the raw
multipliers by fine edge), the worst stationarity residual and the recovery's
fallback count.
"""
function cluster_estimator(model::MPCModel, alpha::AbstractVector{<:Integer}, Pc::GraphProgram,
                           L::ResolutionLift, solc::DirectSolution)
    P = model.program
    f0 = Resolution.FALLBACKS[]
    mu, eta_blocks, resid = local_multipliers(P, L, Pc, solc)
    ac = canonical_partition(alpha)
    eta_cluster = zeros(maximum(ac))
    eta_edge = Dict{Tuple{Int,Int},Float64}()
    for (e, m) in mu
        E = P.edges[e]
        (E.hard || edgedim(E) == 0 || E.tag.kind != :form) && continue
        val = 0.5 * dot(m, E.W \ m)
        key = (E.tag.i, E.tag.j)
        eta_edge[key] = get(eta_edge, key, 0.0) + val
        eta_cluster[ac[E.tag.i]] += val
    end
    return (eta_cluster = eta_cluster, eta_edge = eta_edge, mu = mu, residual = resid,
            eta_blocks_total = sum(eta_blocks), fallbacks = Resolution.FALLBACKS[] - f0)
end

"""
    dorfler_mark(eta, theta) -> Vector{Int}

A smallest set of clusters carrying at least the fraction `theta` of the total
estimator [Dorfler 1996]: the clusters in decreasing order of `eta` (ties by
index) until the running sum reaches `theta * sum(eta)`. Only clusters with a
positive estimator are ever marked.
"""
function dorfler_mark(eta::AbstractVector{<:Real}, theta::Real)
    order = sortperm(collect(eta); rev = true, alg = MergeSort)   # stable: ties keep index order
    total = sum(eta)
    marked = Int[]
    acc = 0.0
    for b in order
        eta[b] > 0 || break
        push!(marked, b)
        acc += eta[b]
        acc >= theta * total && break
    end
    return marked
end

"""
    min_cut_split(members, edges, cap, s, t) -> (parts, cut)

A minimum `s`-`t` cut of the subgraph induced on `members` with edge capacities
`cap(i, j)` (Edmonds-Karp), and the connected components left after removing the
cut edges (exactly two when every capacity is positive: both sides of a minimum
cut are connected). `cut` lists the removed edges.
"""
function min_cut_split(members::Vector{Int}, edges::Vector{Tuple{Int,Int}}, cap, s::Int, t::Int)
    pos = Dict(v => k for (k, v) in enumerate(members))
    m = length(members)
    inner = [(i, j) for (i, j) in edges if haskey(pos, i) && haskey(pos, j)]
    C = zeros(m, m)
    for (i, j) in inner
        c = cap(i, j)
        C[pos[i], pos[j]] += c
        C[pos[j], pos[i]] += c
    end
    F = zeros(m, m)
    src, snk = pos[s], pos[t]
    reach = falses(m)
    while true
        prev = zeros(Int, m)
        prev[src] = src
        queue = [src]
        while !isempty(queue) && prev[snk] == 0
            u = popfirst!(queue)
            for v in 1:m
                if prev[v] == 0 && C[u, v] - F[u, v] > 1e-15 * max(1.0, C[u, v])
                    prev[v] = u
                    push!(queue, v)
                end
            end
        end
        if prev[snk] == 0
            reach .= prev .!= 0
            break
        end
        aug = Inf
        v = snk
        while v != src
            u = prev[v]
            aug = min(aug, C[u, v] - F[u, v])
            v = u
        end
        v = snk
        while v != src
            u = prev[v]
            F[u, v] += aug
            F[v, u] -= aug
            v = u
        end
    end
    cut = [(i, j) for (i, j) in inner if reach[pos[i]] != reach[pos[j]]]
    keep = [(i, j) for (i, j) in inner if reach[pos[i]] == reach[pos[j]]]
    return sp_components(members, keep), cut
end

"""
    refine_split(alpha, marked, eta_edge, edges) -> (alpha_new, splits)

Split every marked cluster of `alpha` along a minimum cut of its internal graph
that separates the two endpoints of its highest-estimator spring (capacities:
the springs' estimators plus `1e-9` of the cluster's largest, so that springs
carrying no force are cut as few as possible), into the connected components
left by the cut. Returns the new clustering (canonical labels) and one record
per split.
"""
function refine_split(alpha::AbstractVector{<:Integer}, marked::Vector{Int}, eta_edge::Dict{Tuple{Int,Int},Float64},
                      edges::Vector{Tuple{Int,Int}})
    ac = canonical_partition(alpha)
    members = block_members(ac)
    newlab = copy(ac)
    next = maximum(ac)
    splits = Dict{String,Any}[]
    for b in marked
        mem = members[b]
        inner = [(i, j) for (i, j) in edges if ac[i] == b && ac[j] == b]
        isempty(inner) && continue
        vals = [get(eta_edge, e, 0.0) for e in inner]
        k = argmax(vals)                       # first maximal edge in edge order (deterministic)
        s, t = inner[k]
        top = vals[k]
        delta = 1e-9 * max(top, floatmin(Float64))
        parts, cut = min_cut_split(mem, inner, (i, j) -> get(eta_edge, (i, j), 0.0) + delta, s, t)
        for (pk, part) in enumerate(parts)
            pk == 1 && continue
            next += 1
            for v in part
                newlab[v] = next
            end
        end
        push!(splits, Dict{String,Any}("cluster" => b, "members" => mem, "size" => length(mem),
                                       "edge" => [s, t], "edge_eta" => top, "cut" => [[i, j] for (i, j) in cut],
                                       "cut_eta" => sum(get(eta_edge, e, 0.0) for e in cut),
                                       "parts" => parts, "n_parts" => length(parts)))
    end
    return canonical_partition(newlab), splits
end
