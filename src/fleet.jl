# fleet.jl: multi-agent MPC as a homological program on G box P_H (the
# paper's Def. 3).
#
# Agent i has state x_{i,t} and input u_{i,t}, affine time-varying dynamics
# x_{i,t+1} = A_{i,t} x_{i,t} + B_{i,t} u_{i,t} + g_{i,t}, a measured state
# xhat_i, a formation output C_i x (here a planar position), quadratic stage
# and terminal costs on tracked outputs, an input set and convex state sets.
# At each instant t >= 1 the agents joined by a formation edge ij prefer
# C_j x_{j,t} - C_i x_{i,t} = o_{ij,t}, with weight w_{ij,t}.
#
# On the time-expanded graph, vertex (i, t) holds (x_{i,t}, u_{i,t}) (only the
# state at t = H). The dynamics edge (i,t) -> (i,t+1) is hard, with
# restriction maps [A B] and the projection onto x_{i,t+1}, and target g_{i,t};
# the formation edge (i,t) -> (j,t) is soft, with restriction maps C_i, C_j,
# target o_{ij,t} and stiffness w_{ij,t} I. The vertex (i, 0) also pins the
# initial state, x_{i,0} = xhat_i.

"""`BallSet(radius)`: the inputs with `||u|| <= radius` (a second-order cone)."""
struct BallSet
    radius::Float64
end

"""`BoxSet(lo, hi)`: the inputs with `lo <= u <= hi` componentwise."""
struct BoxSet
    lo::Vector{Float64}
    hi::Vector{Float64}
end

"""
    Polyhedron(G, h; pattern = G .!= 0)

The points `z` with `G z <= h` (a state set, or an input set). `pattern`
(a Boolean matrix the size of `G`) marks the entries of `G` that may be
nonzero: the program keeps exactly these entries in its constraint matrix, so
a state set changed in place later (`set_state_set!`, `step!(...; states)`, a
re-linearized keep-out whose normals rotate) may use any of them. By default
the nonzeros of `G`; give the pattern explicitly when an entry is zero now but
may not be later (for a half-space on a planar position `p = C x`, the support
of `C` in every row).
"""
struct Polyhedron
    G::Matrix{Float64}
    h::Vector{Float64}
    pattern::BitMatrix
    function Polyhedron(G::AbstractMatrix, h::AbstractVector; pattern = nothing)
        size(G, 1) == length(h) || throw(DimensionMismatch("G has $(size(G, 1)) rows, h has $(length(h))"))
        pat = pattern === nothing ? BitMatrix(G .!= 0) : BitMatrix(pattern)
        size(pat) == size(G) || throw(DimensionMismatch("the pattern must be $(size(G, 1)) x $(size(G, 2))"))
        all(pat .| (G .== 0)) || throw(ArgumentError("G has nonzeros outside its pattern"))
        new(Matrix{Float64}(G), Vector{Float64}(h), pat)
    end
end

const InputSet = Union{Nothing,BallSet,BoxSet,Polyhedron}

"""
    Agent(A, B; C, Q, R, Cr = C, g = 0, Cf = Cr, Qf = Q, input = nothing, state = nothing, kind = :agent)

One agent: dynamics `x_{t+1} = A_t x_t + B_t u_t + g_t` (each of `A`, `B`, `g`
a matrix or vector, or a vector of them indexed by `t = 0, ..., H-1`), the
formation output `C` (`p x nx`, the same `p` for every agent), the tracked
output `Cr` with stage weight `Q`, the terminal output `Cf` with weight `Qf`,
the input weight `R` (positive definite), the input set (`BallSet`, `BoxSet`,
`Polyhedron` or `nothing`), and the state set (a `Polyhedron` on `x`, applied
at `t = 1, ..., H`, or a vector of `H` of them, `nothing` entries allowed).

Stage cost at `t < H`: `(1/2)||Cr x_t - r_t||^2_Q + (1/2)||u_t||^2_R`;
terminal cost: `(1/2)||Cf x_H - r_f||^2_{Qf}`. The references `r_t`, `r_f`
are given per solve (`set_references!`).
"""
struct Agent
    nx::Int
    nu::Int
    A::Vector{Matrix{Float64}}
    B::Vector{Matrix{Float64}}
    g::Vector{Vector{Float64}}
    C::Matrix{Float64}
    Cr::Matrix{Float64}
    Q::Matrix{Float64}
    R::Matrix{Float64}
    Cf::Matrix{Float64}
    Qf::Matrix{Float64}
    input::InputSet
    state::Vector{Union{Nothing,Polyhedron}}
    kind::Symbol
end

_matvec(M::AbstractMatrix) = [Matrix{Float64}(M)]
_matvec(M::AbstractVector{<:AbstractMatrix}) = [Matrix{Float64}(m) for m in M]
_vecvec(v::AbstractVector{<:Real}) = [Vector{Float64}(v)]
_vecvec(v::AbstractVector{<:AbstractVector}) = [Vector{Float64}(w) for w in v]

function Agent(A, B; C::AbstractMatrix, Q::AbstractMatrix, R::AbstractMatrix, Cr::AbstractMatrix = C, g = nothing,
               Cf::AbstractMatrix = Cr, Qf::AbstractMatrix = Q, input::InputSet = nothing, state = nothing,
               kind::Symbol = :agent)
    As = _matvec(A); Bs = _matvec(B)
    nx = size(As[1], 1)
    nu = size(Bs[1], 2)
    all(a -> size(a) == (nx, nx), As) || throw(DimensionMismatch("every A must be $nx x $nx"))
    all(b -> size(b) == (nx, nu), Bs) || throw(DimensionMismatch("every B must be $nx x $nu"))
    gs = g === nothing ? [zeros(nx)] : _vecvec(g)
    all(v -> length(v) == nx, gs) || throw(DimensionMismatch("every g must have $nx entries"))
    size(C, 2) == nx || throw(DimensionMismatch("C must have $nx columns"))
    size(Cr, 2) == nx && size(Q) == (size(Cr, 1), size(Cr, 1)) || throw(DimensionMismatch("Cr and Q do not match"))
    size(Cf, 2) == nx && size(Qf) == (size(Cf, 1), size(Cf, 1)) || throw(DimensionMismatch("Cf and Qf do not match"))
    size(R) == (nu, nu) || throw(DimensionMismatch("R must be $nu x $nu"))
    isposdef(Symmetric(Matrix{Float64}(R))) || throw(ArgumentError("R must be positive definite"))
    if input isa BoxSet
        length(input.lo) == nu && length(input.hi) == nu || throw(DimensionMismatch("the input box needs $nu bounds"))
    elseif input isa Polyhedron
        size(input.G, 2) == nu || throw(DimensionMismatch("the input polyhedron needs $nu columns"))
    end
    st = state === nothing ? Union{Nothing,Polyhedron}[nothing] :
         state isa Polyhedron ? Union{Nothing,Polyhedron}[state] : Vector{Union{Nothing,Polyhedron}}(state)
    for s in st
        s === nothing || size(s.G, 2) == nx || throw(DimensionMismatch("a state polyhedron needs $nx columns"))
    end
    return Agent(nx, nu, As, Bs, gs, Matrix{Float64}(C), Matrix{Float64}(Cr), Matrix{Float64}(Q), Matrix{Float64}(R),
                 Matrix{Float64}(Cf), Matrix{Float64}(Qf), input, st, kind)
end

_at(v::Vector, t::Int) = length(v) == 1 ? v[1] : v[t+1]
dynamics(ag::Agent, t::Int) = (_at(ag.A, t), _at(ag.B, t), _at(ag.g, t))
_state_set(ag::Agent, t::Int) = t == 0 ? nothing : (length(ag.state) == 1 ? ag.state[1] : ag.state[t])

"""
    Fleet(agents, edges; H, offsets = nothing, targets = nothing, weights = 1.0, present = nothing)

A fleet over a horizon of `H` steps: the agents, the union formation graph
`edges` (pairs `(i, j)`), and per instant `t = 1, ..., H` which edges are
present (`present[k, t]`, a switching topology; all by default), their targets
`targets[:, k, t]` (the desired `C_j x_j - C_i x_i`; by default `o_j - o_i` from
the slot positions `offsets`, or zero) and weights `weights[k, t]` (a number
for all).
"""
struct Fleet
    agents::Vector{Agent}
    H::Int
    edges::Vector{Tuple{Int,Int}}
    present::BitMatrix
    targets::Array{Float64,3}
    weights::Matrix{Float64}
end

function Fleet(agents::Vector{Agent}, edges::AbstractVector; H::Integer, offsets = nothing, targets = nothing,
               weights = 1.0, present = nothing)
    n = length(agents)
    p = size(agents[1].C, 1)
    all(ag -> size(ag.C, 1) == p, agents) || throw(DimensionMismatch("every formation output must have $p rows"))
    for ag in agents
        for v in (ag.A, ag.B, ag.g)
            length(v) == 1 || length(v) >= H || throw(DimensionMismatch("time-varying data must cover the horizon H = $H"))
        end
        length(ag.state) == 1 || length(ag.state) >= H || throw(DimensionMismatch("time-varying state sets must cover H = $H"))
    end
    E = [(Int(i), Int(j)) for (i, j) in edges]
    for (i, j) in E
        (1 <= i <= n && 1 <= j <= n && i != j) || throw(ArgumentError("bad formation edge ($i, $j)"))
    end
    ne = length(E)
    pres = present === nothing ? trues(ne, H) : BitMatrix(present)
    size(pres) == (ne, H) || throw(DimensionMismatch("present must be $ne x $H"))
    T = zeros(p, ne, H)
    if targets !== nothing
        size(targets) == (p, ne, H) || throw(DimensionMismatch("targets must be $p x $ne x $H"))
        T .= targets
    elseif offsets !== nothing
        for (k, (i, j)) in enumerate(E), t in 1:H
            T[:, k, t] .= offsets[j] .- offsets[i]
        end
    end
    Wm = weights isa Real ? fill(Float64(weights), ne, H) : Matrix{Float64}(weights)
    size(Wm) == (ne, H) || throw(DimensionMismatch("weights must be $ne x $H"))
    return Fleet(agents, Int(H), E, pres, T, Wm)
end

Base.length(f::Fleet) = length(f.agents)
nagents(f::Fleet) = length(f.agents)

colour_refinement(fl::Fleet, classes::AbstractVector; t::Integer = 1, kw...) =
    colour_refinement(nagents(fl), fl.edges, fl.weights[:, t] .* fl.present[:, t], classes; kw...)

"""
    FleetProgram(fleet; x0 = nothing, references = nothing, terminal = nothing, absent = :omit)

The time-expanded program of a fleet (the paper's Def. 3): vertices in agent
major order `(1,0), ..., (1,H), (2,0), ...`, then the dynamics edges (hard),
then the formation edges instant by instant (soft). `vid[i, t+1]`, `dyn[i, t+1]`
and `form[k, t]` index the vertex of `(i, t)`, the dynamics edge from `t`, and
the formation edge `k` at `t` (0 when absent). An absent formation edge is
omitted (`absent = :omit`) or kept with a zero stalk (`:zero`); both give the
same program. The measured states and the references can be changed in place
(`set_state!`, `set_references!`, `set_targets!`, `set_drift!`).
"""
struct FleetProgram
    fleet::Fleet
    program::SheafProgram
    layout::FleetLayout
    vid::Matrix{Int}
    dyn::Matrix{Int}
    form::Matrix{Int}
    CrQ::Vector{Matrix{Float64}}     # Cr'Q per agent
    CfQf::Vector{Matrix{Float64}}    # Cf'Qf per agent
    changed::Vector{Int}             # vertices whose constraint matrices changed in place since the controller last read them
end

_sheaf(F::FleetProgram) = F.program
_layout(F::FleetProgram) = F.layout
c0dim(F::FleetProgram) = c0dim(F.program)

Base.show(io::IO, F::FleetProgram) = print(io, "FleetProgram($(nagents(F.fleet)) agents, H = $(F.fleet.H), ", F.program, ")")

function _stage_node(ag::Agent, t::Int, H::Int)
    nx, nu = ag.nx, ag.nu
    du = t < H ? nu : 0
    d = nx + du
    Q = zeros(d, d)
    if t < H
        Q[1:nx, 1:nx] .= ag.Cr' * ag.Q * ag.Cr
        Q[(nx+1):d, (nx+1):d] .= ag.R
    else
        Q .= ag.Cf' * ag.Qf * ag.Cf
    end
    Ablocks = Matrix{Float64}[]; b = Float64[]; cones = ConeBlock[]
    if t == 0
        push!(Ablocks, [Matrix{Float64}(I, nx, nx) zeros(nx, du)]); append!(b, zeros(nx)); push!(cones, zero_cone(nx))
    end
    if du > 0
        U = ag.input
        if U isa BallSet
            push!(Ablocks, [zeros(1, d); zeros(nu, nx) -Matrix{Float64}(I, nu, nu)])
            append!(b, [U.radius; zeros(nu)]); push!(cones, soc_cone(1 + nu))
        elseif U isa BoxSet
            push!(Ablocks, [zeros(nu, nx) Matrix{Float64}(I, nu, nu); zeros(nu, nx) -Matrix{Float64}(I, nu, nu)])
            append!(b, [U.hi; -U.lo]); push!(cones, nonneg_cone(2nu))
        elseif U isa Polyhedron
            push!(Ablocks, [zeros(size(U.G, 1), nx) U.G]); append!(b, U.h); push!(cones, nonneg_cone(length(U.h)))
        end
    end
    X = _state_set(ag, t)
    if X !== nothing && !isempty(X.h)
        push!(Ablocks, [X.G zeros(size(X.G, 1), du)]); append!(b, X.h); push!(cones, nonneg_cone(length(X.h)))
    end
    A = isempty(Ablocks) ? zeros(0, d) : reduce(vcat, Ablocks)
    # the stored entries: the nonzeros, and the whole pattern of the state rows (the last rows), so that the
    # state set can change in place on that pattern
    keep = A .!= 0
    if X !== nothing && !isempty(X.h)
        m = length(X.h)
        keep[(end-m+1):end, 1:ag.nx] .|= X.pattern
    end
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for j in 1:d, i in axes(A, 1)
        keep[i, j] && (push!(I_, i); push!(J_, j); push!(V_, A[i, j]))
    end
    return NodeData(Q, zeros(d), 0.0, sparse(I_, J_, V_, size(A, 1), d), b, cones)
end

function FleetProgram(fleet::Fleet; x0 = nothing, references = nothing, terminal = nothing, absent::Symbol = :omit)
    absent in (:omit, :zero) || throw(ArgumentError("absent must be :omit or :zero"))
    n, H = nagents(fleet), fleet.H
    vid = zeros(Int, n, H + 1)
    nodes = NodeData[]
    for i in 1:n, t in 0:H
        push!(nodes, _stage_node(fleet.agents[i], t, H))
        vid[i, t+1] = length(nodes)
    end
    edges = SheafEdge[]
    dyn = zeros(Int, n, H)
    for i in 1:n, t in 0:(H-1)
        ag = fleet.agents[i]
        A, B, g = dynamics(ag, t)
        dh = t + 1 < H ? ag.nu : 0
        push!(edges, SheafEdge(vid[i, t+1], vid[i, t+2], [A B], [Matrix{Float64}(I, ag.nx, ag.nx) zeros(ag.nx, dh)],
                               true, Matrix{Float64}(I, ag.nx, ag.nx), g, EdgeTag(:dyn, i, i, t)))
        dyn[i, t+1] = length(edges)
    end
    form = zeros(Int, length(fleet.edges), H)
    p = size(fleet.agents[1].C, 1)
    for t in 1:H, (k, (i, j)) in enumerate(fleet.edges)
        ai, aj = fleet.agents[i], fleet.agents[j]
        di = t < H ? ai.nx + ai.nu : ai.nx
        dj = t < H ? aj.nx + aj.nu : aj.nx
        if fleet.present[k, t]
            push!(edges, SheafEdge(vid[i, t+1], vid[j, t+1], [ai.C zeros(p, di - ai.nx)], [aj.C zeros(p, dj - aj.nx)],
                                   false, fleet.weights[k, t] * Matrix{Float64}(I, p, p), fleet.targets[:, k, t],
                                   EdgeTag(:form, i, j, t)))
            form[k, t] = length(edges)
        elseif absent == :zero
            push!(edges, SheafEdge(vid[i, t+1], vid[j, t+1], zeros(0, di), zeros(0, dj), false, zeros(0, 0), Float64[],
                                   EdgeTag(:form, i, j, t)))
            form[k, t] = length(edges)
        end
    end
    F = FleetProgram(fleet, SheafProgram(nodes, edges), FleetLayout(vid), vid, dyn, form,
                     [ag.Cr' * ag.Q for ag in fleet.agents], [ag.Cf' * ag.Qf for ag in fleet.agents], Int[])
    x0 === nothing || set_state!(F, x0)
    references === nothing || set_references!(F, references; terminal = terminal)
    return F
end

"""
    set_state!(fp, x0)

Set the measured states `x0[i]` (the pinned initial states `x_{i,0}`) in place.
"""
function set_state!(F::FleetProgram, x0::AbstractVector)
    length(x0) == nagents(F.fleet) || throw(DimensionMismatch("need one state per agent"))
    for i in eachindex(x0)
        nd = F.program.nodes[F.vid[i, 1]]
        nx = F.fleet.agents[i].nx
        length(x0[i]) == nx || throw(DimensionMismatch("agent $i has $nx states"))
        @inbounds for k in 1:nx
            nd.b[k] = x0[i][k]
        end
    end
    return F
end

"""`y[1:size(M, 1)] = -M r` for a small dense `M` (no BLAS call)."""
@inline function _neg_matvec!(y::AbstractVector, M::Matrix{Float64}, r::AbstractVector)
    @inbounds for k in axes(M, 1)
        s = 0.0
        for j in axes(M, 2)
            s += M[k, j] * r[j]
        end
        y[k] = -s
    end
    return y
end

@inline function _quad(Q::Matrix{Float64}, r::AbstractVector)
    s = 0.0
    @inbounds for j in eachindex(r), i in eachindex(r)
        s += r[i] * Q[i, j] * r[j]
    end
    return s
end

function _set_terminal!(nd::NodeData, CfQf::Matrix{Float64}, Qf::Matrix{Float64}, rf::AbstractVector)
    _neg_matvec!(nd.q, CfQf, rf)
    nd.c = 0.5 * _quad(Qf, rf)
    return nd
end

"""
    set_references!(fp, refs; terminal = nothing)

Set the tracking references in place: `refs[i]` is a matrix with `H + 1`
columns, column `t + 1` the reference `r_{i,t}` of the tracked output `Cr x`
at instant `t`; the terminal reference of the output `Cf x` is `terminal[i]`,
by default the last column of `refs[i]` (when `Cf` has as many rows as `Cr`).
"""
function set_references!(F::FleetProgram, refs::AbstractVector; terminal = nothing)
    fl = F.fleet
    H = fl.H
    length(refs) == nagents(fl) || throw(DimensionMismatch("need one reference per agent"))
    for (i, ag) in enumerate(fl.agents)
        R = refs[i]
        ny = size(ag.Cr, 1)
        size(R, 1) == ny && size(R, 2) >= H || throw(DimensionMismatch("agent $i: references must be $ny x $(H + 1)"))
        for t in 0:(H-1)
            nd = F.program.nodes[F.vid[i, t+1]]
            r = view(R, :, t + 1)
            _neg_matvec!(nd.q, F.CrQ[i], r)
            nd.c = 0.5 * _quad(ag.Q, r)
        end
        nd = F.program.nodes[F.vid[i, H+1]]
        if terminal === nothing
            size(ag.Cf, 1) == ny || throw(ArgumentError("agent $i: give its terminal reference (Cf has $(size(ag.Cf, 1)) rows)"))
            _set_terminal!(nd, F.CfQf[i], ag.Qf, view(R, :, H + 1))
        else
            length(terminal[i]) == size(ag.Cf, 1) ||
                throw(DimensionMismatch("agent $i: the terminal reference needs $(size(ag.Cf, 1)) entries"))
            _set_terminal!(nd, F.CfQf[i], ag.Qf, terminal[i])
        end
    end
    return F
end

"""
    set_targets!(fp, targets)

Set the formation targets `targets[:, k, t]` (`p x nedges x H`) in place.
"""
function set_targets!(F::FleetProgram, T::AbstractArray{<:Real,3})
    for t in axes(F.form, 2), k in axes(F.form, 1)
        e = F.form[k, t]
        e == 0 && continue
        b = F.program.edges[e].b
        @inbounds for a in eachindex(b)
            b[a] = T[a, k, t]
        end
    end
    return F
end

"""
    set_drift!(fp, g)

Set the affine dynamics terms `g[i][:, t+1]` (or `g[i]`, one vector for every
instant) in place: the targets of the hard dynamics edges.
"""
function set_drift!(F::FleetProgram, g::AbstractVector)
    for i in axes(F.dyn, 1), t in axes(F.dyn, 2)
        b = F.program.edges[F.dyn[i, t]].b
        gi = g[i]
        @inbounds for a in eachindex(b)
            b[a] = gi isa AbstractMatrix ? gi[a, t] : gi[a]
        end
    end
    return F
end

"""
    set_state_bound!(fp, i, t, h)

Replace the right-hand side `h` of agent `i`'s state polyhedron `G x <= h` at
instant `t` in place (same `G`).
"""
function set_state_bound!(F::FleetProgram, i::Integer, t::Integer, h::AbstractVector)
    nd = F.program.nodes[F.vid[i, t+1]]
    m = length(h)
    @inbounds for k in 1:m
        nd.b[end-m+k] = h[k]
    end
    return F
end

"""
    set_state_set!(fp, i, t, G, h)
    set_state_set!(fp, i, t, X::Polyhedron)

Replace agent `i`'s state polyhedron `G x <= h` at instant `t` (`1 <= t <= H`)
in place: new half-space normals and offsets on the same number of rows, with
the nonzeros of `G` inside the pattern the program was built with (see
`Polyhedron`; an inactive half-space can be a zero row with a positive
offset). The constraint matrix of vertex `(i, t)` changes in place and the
vertex is recorded in `fp.changed`, from which `MPCController` and
`DistributedMPC` update their reduced programs, fibers and solvers on the next
`step!` without rebuilding (programs that share this program's matrices see
the change too).
"""
function set_state_set!(F::FleetProgram, i::Integer, t::Integer, G::AbstractMatrix, h::AbstractVector)
    H = F.fleet.H
    1 <= i <= nagents(F.fleet) || throw(ArgumentError("no agent $i"))
    1 <= t <= H || throw(ArgumentError("state sets apply at t = 1, ..., $H, not $t"))
    ag = F.fleet.agents[i]
    m = length(h)
    size(G) == (m, ag.nx) || throw(DimensionMismatch("G must be $m x $(ag.nx)"))
    v = F.vid[i, t+1]
    nd = F.program.nodes[v]
    X = _state_set(ag, t)
    (X !== nothing && length(X.h) == m) ||
        throw(ArgumentError("agent $i has $(X === nothing ? 0 : length(X.h)) state rows at t = $t, not $m: the rows are fixed when the program is built"))
    r0 = size(nd.A, 1) - m
    A = nd.A
    rv = rowvals(A); nz = nonzeros(A)
    written = 0
    @inbounds for j in 1:ag.nx, k in nzrange(A, j)
        r = rv[k] - r0
        r >= 1 || continue
        nz[k] = G[r, j]
        G[r, j] != 0 && (written += 1)
    end
    written == count(!=(0), G) ||
        throw(ArgumentError("G has nonzeros outside the pattern of agent $i's state set at t = $t (give Polyhedron a pattern)"))
    @inbounds for k in 1:m
        nd.b[r0+k] = h[k]
    end
    v in F.changed || push!(F.changed, v)
    return F
end
set_state_set!(F::FleetProgram, i::Integer, t::Integer, X::Polyhedron) = set_state_set!(F, i, t, X.G, X.h)

"""
Apply `states` (one entry per agent: `nothing` to keep its sets, a `Polyhedron`
for every instant, or a vector of `H` entries, `nothing` keeping that instant)
with `set_state_set!`.
"""
function set_state_sets!(F::FleetProgram, states::AbstractVector)
    length(states) == nagents(F.fleet) || throw(DimensionMismatch("need one entry per agent (nothing to keep its sets)"))
    for (i, S) in enumerate(states)
        S === nothing && continue
        if S isa Polyhedron
            for t in 1:F.fleet.H
                set_state_set!(F, i, t, S)
            end
        else
            length(S) == F.fleet.H || throw(DimensionMismatch("agent $i: give one state set per instant t = 1, ..., $(F.fleet.H)"))
            for t in 1:F.fleet.H
                S[t] === nothing || set_state_set!(F, i, t, S[t])
            end
        end
    end
    return F
end

function Base.reduce(F::FleetProgram, res::Resolution; basis::Symbol = :structured, reuse = nothing,
                     consistency_tol::Real = 1e-8)
    labels, clayout = vertex_labels(res, nvertices(F.program), F.layout)
    return _pushforward(F, F.program, res, labels, clayout; basis = basis, reuse = reuse, consistency_tol = consistency_tol)
end

solve(F::FleetProgram; kwargs...) = solve(F.program; kwargs...)
objective(F::FleetProgram, x::AbstractVector) = objective(F.program, x)

"""
    trajectories(fp, x) -> (states, inputs)

Agent `i`'s planned states `states[i]` (`nx x (H+1)`) and inputs `inputs[i]`
(`nu x H`) read off a plan `x` of the fine program.
"""
function trajectories(F::FleetProgram, x::AbstractVector)
    fl = F.fleet; H = fl.H; P = F.program
    X = [zeros(ag.nx, H + 1) for ag in fl.agents]
    U = [zeros(ag.nu, H) for ag in fl.agents]
    for (i, ag) in enumerate(fl.agents), t in 0:H
        r = vrange(P, F.vid[i, t+1])
        X[i][:, t+1] .= view(x, r[1:ag.nx])
        t < H && (U[i][:, t+1] .= view(x, r[(ag.nx+1):end]))
    end
    return X, U
end

"""
    shift_plan!(out, fp, x, x0) -> out
    shift_plan(fp, x, x0)

The fine plan `x` moved one instant earlier, the receding-horizon warm start:
every agent's state and input at instant `t` take their values at `t + 1`, the
last input is held, the last state is propagated by the dynamics of instant
`H - 1` from the previous last state and the held input, and the first state is
the measured `x0[i]`. The result satisfies every dynamics edge except the
first (the measured state need not be the predicted one); `restrict` maps it to
the coordinates of a reduction (the nearest plan of every fiber).
"""
function shift_plan!(out::AbstractVector, F::FleetProgram, x::AbstractVector, x0::AbstractVector)
    fl = F.fleet; H = fl.H; P = F.program
    length(out) == length(x) == c0dim(P) || throw(DimensionMismatch("plans must have $(c0dim(P)) entries"))
    out === x && throw(ArgumentError("out must not be x"))
    @inbounds for (i, ag) in enumerate(fl.agents)
        nx, nu = ag.nx, ag.nu
        for t in 0:(H-1)
            ro = P.offsets[F.vid[i, t+1]]
            rn = P.offsets[F.vid[i, t+2]]
            for k in 1:nx
                out[ro+k] = x[rn+k]
            end
            src = t + 1 < H ? rn : ro                 # the last input is held
            for k in 1:nu
                out[ro+nx+k] = x[src+nx+k]
            end
        end
        A, B, g = dynamics(ag, H - 1)
        rH = P.offsets[F.vid[i, H+1]]
        rl = P.offsets[F.vid[i, H]]
        for k in 1:nx
            s = g[k]
            for j in 1:nx
                s += A[k, j] * x[rH+j]
            end
            for j in 1:nu
                s += B[k, j] * x[rl+nx+j]
            end
            out[rH+k] = s
        end
        r0 = P.offsets[F.vid[i, 1]]
        for k in 1:nx
            out[r0+k] = x0[i][k]
        end
    end
    return out
end
shift_plan(F::FleetProgram, x::AbstractVector, x0::AbstractVector) = shift_plan!(similar(x, Float64), F, x, x0)

"""
    free_response!(out, fp, x0) -> out

The plan with zero inputs from the measured states `x0[i]` (each agent's free
response, its drift included): the warm start when there is no previous plan.
"""
function free_response!(out::AbstractVector, F::FleetProgram, x0::AbstractVector)
    fl = F.fleet; H = fl.H; P = F.program
    length(out) == c0dim(P) || throw(DimensionMismatch("the plan must have $(c0dim(P)) entries"))
    fill!(out, 0.0)
    @inbounds for (i, ag) in enumerate(fl.agents)
        nx = ag.nx
        r = P.offsets[F.vid[i, 1]]
        for k in 1:nx
            out[r+k] = x0[i][k]
        end
        for t in 0:(H-1)
            A, _, g = dynamics(ag, t)
            ro = P.offsets[F.vid[i, t+1]]
            rn = P.offsets[F.vid[i, t+2]]
            for k in 1:nx
                s = g[k]
                for j in 1:nx
                    s += A[k, j] * out[ro+j]
                end
                out[rn+k] = s
            end
        end
    end
    return out
end

"""`first_inputs(fp, x)`: every agent's input at instant 0 in the plan `x` (what receding horizon applies)."""
function first_inputs(F::FleetProgram, x::AbstractVector)
    P = F.program
    return [x[P.offsets[F.vid[i, 1]] .+ ((ag.nx+1):(ag.nx+ag.nu))] for (i, ag) in enumerate(F.fleet.agents)]
end

"""`plant_step(fleet, x, u; t = 0)`: the nominal next state of every agent under the inputs `u`."""
function plant_step(fl::Fleet, x::AbstractVector, u::AbstractVector; t::Integer = 0)
    return [(ABg = dynamics(ag, t); ABg[1] * x[i] + ABg[2] * u[i] + ABg[3]) for (i, ag) in enumerate(fl.agents)]
end
