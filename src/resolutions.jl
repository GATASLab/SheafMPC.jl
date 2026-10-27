# resolutions.jl: partitions of the time-expanded graph G box P_H.
#
# A resolution is a partition of the vertices of a program's graph into blocks
# (the paper's Sec. III-D); the quotient map contracts the edges inside each
# block. On the time-expanded graph of multi-agent MPC two kinds matter, and
# they commute (the paper's eq. (3)):
#
# * a time blocking beta of the horizon, applied to every agent (id box beta):
#   it contracts dynamics edges only, which are hard, so it is exact. One
#   block per agent is full condensing; blocks of nu instants are partial
#   condensing;
# * a team clustering alpha of the agents, applied at every instant
#   (alpha box id): it contracts formation edges only, which are soft, so it
#   has an optimality gap, bounded by `gap_bounds`.
#
# Their product alpha box beta does both; a mixed resolution is any other
# partition (for example teams that form only from instant t0 on).

"""
    FleetLayout(vid)

The grid structure of a time-expanded graph: `vid[i, t+1]` is the vertex of
agent (or team) `i` at instant (or time block) `t`, 0 when absent. Programs
built from a `Fleet` have one, and so have their reductions along product
resolutions (agents become teams, instants become time blocks), so that
reductions can be applied again (teams of teams).
"""
struct FleetLayout
    vid::Matrix{Int}
    agent::Vector{Int}        # agent (or team) of every vertex
    time::Vector{Int}         # instant (or block) of every vertex, from 0
end

function FleetLayout(vid::Matrix{Int})
    nv = count(>(0), vid)
    agent = zeros(Int, nv); time = zeros(Int, nv)
    for i in axes(vid, 1), t in axes(vid, 2)
        v = vid[i, t]
        v == 0 && continue
        agent[v] = i; time[v] = t - 1
    end
    return FleetLayout(vid, agent, time)
end

"""`nagents(x)`: the number of agents of a fleet, scenario or layout (teams, for a reduced layout)."""
nagents(L::FleetLayout) = size(L.vid, 1)
ntimes(L::FleetLayout) = size(L.vid, 2)

"""
    Resolution

A partition of the vertices of a program, applied with `reduce(program,
resolution)`. Concrete resolutions: `Fine`, `TimeBlocking` (condensing),
`Teams`, their product `teams ⊠ blocking` (also `Product`), `Mixed` (any rule
on (agent, instant)) and `VertexPartition` (explicit labels).
"""
abstract type Resolution end

"""`Fine()`: the identity resolution (every vertex its own block)."""
struct Fine <: Resolution end

"""
    TimeBlocking(labels)
    TimeBlocking(nu::Integer)

A blocking of the horizon into consecutive blocks, applied to every agent
(`id box beta`). `labels[t+1]` is the block of instant `t` (blocks must be
intervals); an integer `nu` makes blocks of `nu` instants (partial condensing,
`nu = 1` is no blocking). `full_condensing()` is one block. Every blocking is
exact: it contracts only hard dynamics edges (the paper's Prop. 4).
"""
struct TimeBlocking <: Resolution
    labels::Vector{Int}
    nu::Int
end
TimeBlocking(labels::AbstractVector{<:Integer}) = TimeBlocking(Vector{Int}(labels), 0)
TimeBlocking(nu::Integer) = (nu >= 1 || throw(ArgumentError("nu must be positive")); TimeBlocking(Int[], Int(nu)))

"""`full_condensing()`: one time block per agent, `id box !` (fully condensed MPC)."""
full_condensing() = TimeBlocking(typemax(Int))
"""`partial_condensing(nu)`: blocks of `nu` instants (`id box beta`, partial condensing)."""
partial_condensing(nu::Integer) = TimeBlocking(nu)

function _time_labels(B::TimeBlocking, T::Int)
    if isempty(B.labels)
        return [t ÷ min(B.nu, T + 1) + 1 for t in 0:T]
    end
    length(B.labels) == T + 1 || throw(DimensionMismatch("the blocking has $(length(B.labels)) labels, the horizon has $(T + 1) instants"))
    all(t -> B.labels[t+1] == B.labels[t] || B.labels[t+1] ∉ B.labels[1:t], 1:T) ||
        throw(ArgumentError("time blocks must be intervals of consecutive instants"))
    return canonical_partition(B.labels)
end

"""
    Teams(alpha; from = 0)

A clustering of the agents into teams, `alpha[i]` the team of agent `i`,
applied at every instant `t >= from` (`alpha box id`). Contracting a team at an
instant hardens the formation edges inside it: the team becomes one agent whose
state is its members' stacked states, confined to the agreement subspace on
which every internal formation edge holds exactly (the paper's Prop. 5).
Teams should be connected in the formation graph. With `from > 0` the
vertices before `from` stay singletons (a mixed resolution: the teams form
after `from` instants, which leaves a disturbed team time to regroup).
"""
struct Teams <: Resolution
    alpha::Vector{Int}
    from::Int
end
Teams(alpha::AbstractVector{<:Integer}; from::Integer = 0) = Teams(canonical_partition(alpha), Int(from))

"""
    Product(teams, blocking)
    teams ⊠ blocking

The product resolution `alpha box beta`: vertex `(i, t)` goes to block
`(alpha[i], beta[t])`. It equals reducing by the teams and then by the blocking,
in either order (the paper's eq. (3)), and its gap is the gap of the teams.
"""
struct Product <: Resolution
    teams::Teams
    blocking::TimeBlocking
end
"""`teams ⊠ blocking`: the product resolution `alpha box beta` (see `Product`)."""
⊠(a::Teams, b::TimeBlocking) = Product(a, b)
⊠(b::TimeBlocking, a::Teams) = Product(a, b)

"""
    Mixed(f)

The resolution that merges vertices `(i, t)` with equal labels `f(i, t)`
(any hashable value): the most general resolution of a time-expanded graph.
"""
struct Mixed{F} <: Resolution
    f::F
end

"""`VertexPartition(labels)`: explicit block labels, one per vertex of the program."""
struct VertexPartition <: Resolution
    labels::Vector{Int}
end

"""
    canonical_partition(labels)

Relabel block labels by order of first appearance (blocks `1:k`).
"""
function canonical_partition(labels::AbstractVector)
    map = Dict{eltype(labels),Int}()
    out = Vector{Int}(undef, length(labels))
    for (v, l) in enumerate(labels)
        out[v] = get!(map, l, length(map) + 1)
    end
    return out
end

nblocks(Pi::AbstractVector{<:Integer}) = isempty(Pi) ? 0 : maximum(Pi)

"""Members of each block of a canonical partition, ascending (counting sort)."""
function block_members(Pi::AbstractVector{<:Integer})
    nb = nblocks(Pi)
    counts = zeros(Int, nb)
    for b in Pi
        counts[b] += 1
    end
    members = [Vector{Int}(undef, c) for c in counts]
    fill!(counts, 0)
    for (v, b) in enumerate(Pi)
        counts[b] += 1
        members[b][counts[b]] = v
    end
    return members
end

_need_layout(L, res) = L === nothing && throw(ArgumentError("$(nameof(typeof(res))) needs a program with a fleet layout; use VertexPartition"))

"""
    vertex_labels(resolution, nv, layout) -> (labels, coarse_layout)

Block labels of the `nv` vertices and, for product resolutions, the layout of
the coarse graph (teams by time blocks), `nothing` otherwise.
"""
function vertex_labels(::Fine, nv::Int, L)
    return collect(1:nv), L
end

function vertex_labels(res::VertexPartition, nv::Int, L)
    length(res.labels) == nv || throw(DimensionMismatch("the partition has $(length(res.labels)) labels, the program has $nv vertices"))
    return canonical_partition(res.labels), nothing
end

function vertex_labels(res::Mixed, nv::Int, L)
    _need_layout(L, res)
    return canonical_partition([res.f(L.agent[v], L.time[v]) for v in 1:nv]), nothing
end

function _product_labels(alpha::Vector{Int}, beta::Vector{Int}, L::FleetLayout)
    nv = length(L.agent)
    keys_ = [(alpha[L.agent[v]], beta[L.time[v]+1]) for v in 1:nv]
    labels = canonical_partition(keys_)
    na, nt = maximum(alpha), maximum(beta)
    vid = zeros(Int, na, nt)
    for v in 1:nv
        a, k = keys_[v]
        vid[a, k] = labels[v]
    end
    return labels, FleetLayout(vid)
end

function vertex_labels(res::Teams, nv::Int, L)
    _need_layout(L, res)
    length(res.alpha) == nagents(L) || throw(DimensionMismatch("the teams label $(length(res.alpha)) agents, the program has $(nagents(L))"))
    if res.from <= 0
        return _product_labels(res.alpha, collect(1:ntimes(L)), L)
    end
    keys_ = [L.time[v] >= res.from ? (res.alpha[L.agent[v]], L.time[v], 0) : (L.agent[v], L.time[v], 1) for v in 1:nv]
    return canonical_partition(keys_), nothing
end

function vertex_labels(res::TimeBlocking, nv::Int, L)
    _need_layout(L, res)
    return _product_labels(collect(1:nagents(L)), _time_labels(res, ntimes(L) - 1), L)
end

function vertex_labels(res::Product, nv::Int, L)
    _need_layout(L, res)
    res.teams.from == 0 || throw(ArgumentError("a product needs teams over the whole horizon (from = 0); use Mixed"))
    length(res.teams.alpha) == nagents(L) || throw(DimensionMismatch("the teams label $(length(res.teams.alpha)) agents, the program has $(nagents(L))"))
    return _product_labels(res.teams.alpha, _time_labels(res.blocking, ntimes(L) - 1), L)
end
