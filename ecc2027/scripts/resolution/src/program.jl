# program.jl: graph programs and hardening.
#
# A graph program on a graph X = (V, E) puts a vector space on every vertex and
# every edge, and a linear edge map from each vertex space to the space of each
# edge it touches. A vector x picks one vector x_v in every vertex space; the
# edge operator delta measures, edge by edge, how far the two ends disagree
# after the edge maps:
#
#     (delta x)_e = F_{v <| e} x_v - F_{u <| e} x_u      for e : u -> v.
#
# A graph program adds convex data: every vertex carries a convex cost f_v and a
# convex set Omega_v; every edge is either hard ((delta x)_e = b_e exactly) or
# soft (a spring of stiffness W_e pulling (delta x)_e toward b_e, with energy
# (1/2)||(delta x)_e - b_e||^2_{W_e}). Here the costs are convex quadratics and
# the sets are products of the three cones Clarabel supports, so every graph
# program is a conic QP.

"""
    ConeKind

The cones used for node constraints, in Clarabel's convention
`A x + s = b, s in K`:

* `ZERO_CONE`: `s = 0` (equality rows, e.g. the pinned initial state),
* `NONNEG_CONE`: `s >= 0` componentwise (half-spaces),
* `SOC_CONE`: `s = (t, z)` with `||z|| <= t` (second-order cone).
"""
@enum ConeKind ZERO_CONE NONNEG_CONE SOC_CONE

"""A block of rows of a node constraint, all in one cone."""
struct ConeBlock
    kind::ConeKind
    dim::Int
end

zero_cone(d::Integer) = ConeBlock(ZERO_CONE, d)
nonneg_cone(d::Integer) = ConeBlock(NONNEG_CONE, d)
soc_cone(d::Integer) = ConeBlock(SOC_CONE, d)

const SpMat = SparseMatrixCSC{Float64,Int}

"""
    NodeData(Q, q, c, A, b, cones)

The convex data at one vertex `v` of a graph program:

* cost `f_v(x) = (1/2) x'Qx + q'x + c` with `Q` positive semidefinite,
* constraint set `Omega_v = { x : b - A x in K }`, where `K` is the product of
  the cones in `cones` (their dimensions add up to the number of rows of `A`).
"""
struct NodeData
    Q::SpMat
    q::Vector{Float64}
    c::Float64
    A::SpMat
    b::Vector{Float64}
    cones::Vector{ConeBlock}
    function NodeData(Q::AbstractMatrix, q::AbstractVector, c::Real,
                      A::AbstractMatrix, b::AbstractVector, cones::Vector{ConeBlock})
        d = length(q)
        size(Q) == (d, d) || throw(DimensionMismatch("Q is $(size(Q)), space is $d"))
        size(A, 2) == d || throw(DimensionMismatch("A has $(size(A, 2)) columns, space is $d"))
        size(A, 1) == length(b) || throw(DimensionMismatch("A and b rows differ"))
        sum((cb.dim for cb in cones); init = 0) == length(b) ||
            throw(DimensionMismatch("cone dimensions do not add up to the rows of A"))
        new(SpMat(sparse(Q)), Vector{Float64}(q), Float64(c), SpMat(sparse(A)),
            Vector{Float64}(b), cones)
    end
end

"""A node with a quadratic cost and no constraint."""
NodeData(Q::AbstractMatrix, q::AbstractVector, c::Real = 0.0) =
    NodeData(Q, q, c, spzeros(0, length(q)), Float64[], ConeBlock[])

"""
    EdgeTag(kind, i, j, t)

Bookkeeping carried by an edge through every reduction (the coarse edge of a
non-collapsed fine edge keeps its tag). For the MPC model: `kind = :dyn` for the
dynamics edge `d_{i,t}` (then `j == i`), `kind = :form` for the formation edge
`f_{ij,t}`; `kind = :generic` otherwise.
"""
struct EdgeTag
    kind::Symbol
    i::Int
    j::Int
    t::Int
end
EdgeTag() = EdgeTag(:generic, 0, 0, 0)

"""
    GraphEdge(tail, head, Ft, Fh, hard, W, b, tag)

An oriented edge `e : tail -> head` with space `R^{d_e}` (`d_e = length(b)`,
possibly zero), edge maps `Ft = F_{tail <| e}` and `Fh = F_{head <| e}`,
so that `(delta x)_e = Fh x_head - Ft x_tail`, target `b_e`, and, if soft, the
positive definite weight `W` (ignored when `hard`).
"""
struct GraphEdge
    tail::Int
    head::Int
    Ft::SpMat
    Fh::SpMat
    hard::Bool
    W::Matrix{Float64}
    b::Vector{Float64}
    tag::EdgeTag
    function GraphEdge(tail::Integer, head::Integer, Ft::AbstractMatrix, Fh::AbstractMatrix,
                       hard::Bool, W::AbstractMatrix, b::AbstractVector, tag::EdgeTag = EdgeTag())
        tail == head && throw(ArgumentError("self loops are not allowed (edge at vertex $tail)"))
        d = length(b)
        size(Ft, 1) == d && size(Fh, 1) == d ||
            throw(DimensionMismatch("edge maps must have $d rows"))
        size(W) == (d, d) || throw(DimensionMismatch("W must be $d x $d"))
        new(tail, head, SpMat(sparse(Ft)), SpMat(sparse(Fh)), hard, Matrix{Float64}(W),
            Vector{Float64}(b), tag)
    end
end

edgedim(E::GraphEdge) = length(E.b)

"""
    GraphProgram(nodes, edges)

THEORY Def 2.1: the convex program

    minimize  J(x) = sum_v f_v(x_v) + (1/2) sum_{e soft} ||(delta x)_e - b_e||^2_{W_e}
    subject to x_v in Omega_v for all v,  (delta x)_e = b_e for e hard.

Vertices are `1:length(nodes)` with space dimensions `dims[v] = length(nodes[v].q)`.
A vector is stored as one flat vector; `x[vrange(P, v)]` is `x_v`. The graph
is a multigraph (parallel edges allowed), which is what reductions produce.
"""
struct GraphProgram
    dims::Vector{Int}
    nodes::Vector{NodeData}
    edges::Vector{GraphEdge}
    offsets::Vector{Int}
    edge_offsets::Vector{Int}
    function GraphProgram(nodes::Vector{NodeData}, edges::Vector{GraphEdge})
        dims = [length(nd.q) for nd in nodes]
        nv = length(nodes)
        for (k, E) in enumerate(edges)
            (1 <= E.tail <= nv && 1 <= E.head <= nv) ||
                throw(ArgumentError("edge $k has an endpoint outside 1:$nv"))
            size(E.Ft, 2) == dims[E.tail] ||
                throw(DimensionMismatch("edge $k: Ft has $(size(E.Ft, 2)) columns, tail space is $(dims[E.tail])"))
            size(E.Fh, 2) == dims[E.head] ||
                throw(DimensionMismatch("edge $k: Fh has $(size(E.Fh, 2)) columns, head space is $(dims[E.head])"))
        end
        offsets = [0; cumsum(dims)]
        edge_offsets = [0; cumsum([edgedim(E) for E in edges])]
        new(dims, nodes, edges, offsets, edge_offsets)
    end
end

nvertices(P::GraphProgram) = length(P.nodes)
nedges(P::GraphProgram) = length(P.edges)
"""`dim C^0(X; F)`, the number of scalar decision variables."""
c0dim(P::GraphProgram) = P.offsets[end]
"""`dim C^1(X; F)`, the total edge space dimension."""
c1dim(P::GraphProgram) = P.edge_offsets[end]
vrange(P::GraphProgram, v::Integer) = (P.offsets[v]+1):P.offsets[v+1]
erange(P::GraphProgram, e::Integer) = (P.edge_offsets[e]+1):P.edge_offsets[e+1]
hard_edges(P::GraphProgram) = [e for (e, E) in enumerate(P.edges) if E.hard]
soft_edges(P::GraphProgram) = [e for (e, E) in enumerate(P.edges) if !E.hard]
edgedims(P::GraphProgram, S) = sum((edgedim(P.edges[e]) for e in S); init = 0)

"""`(delta x)_e` for one edge."""
function edge_value(P::GraphProgram, e::Integer, x::AbstractVector)
    E = P.edges[e]
    return E.Fh * view(x, vrange(P, E.head)) - E.Ft * view(x, vrange(P, E.tail))
end

"""`(delta x)_e - b_e` for one edge (the defect of the spring or rod `e`)."""
edge_defect(P::GraphProgram, e::Integer, x::AbstractVector) = edge_value(P, e, x) - P.edges[e].b

function _push_block!(I, J, V, r0::Int, c0::Int, M::SparseMatrixCSC, s::Float64)
    rows = rowvals(M)
    vals = nonzeros(M)
    for col in 1:size(M, 2), k in nzrange(M, col)
        push!(I, r0 + rows[k])
        push!(J, c0 + col)
        push!(V, s * vals[k])
    end
end

"""
    edge_operator(P, edge_ids = 1:nedges(P); homogeneous = false)

The rows `delta_S` of the edge operator for the edges `S = edge_ids`, stacked in
the given order, as a sparse matrix with `c0dim(P)` columns. Returns the matrix
only; `targets(P, S)` gives the matching right-hand side `b_S`.
"""
function edge_operator(P::GraphProgram, edge_ids = 1:nedges(P))
    I = Int[]; J = Int[]; V = Float64[]
    row = 0
    for e in edge_ids
        E = P.edges[e]
        _push_block!(I, J, V, row, P.offsets[E.head], E.Fh, 1.0)
        _push_block!(I, J, V, row, P.offsets[E.tail], E.Ft, -1.0)
        row += edgedim(E)
    end
    return sparse(I, J, V, row, c0dim(P))
end

targets(P::GraphProgram, edge_ids = 1:nedges(P)) =
    reduce(vcat, (P.edges[e].b for e in edge_ids); init = Float64[])

"""Block diagonal weight matrix of the edges `S` (all soft)."""
function weight_matrix(P::GraphProgram, edge_ids)
    blocks = [sparse(P.edges[e].W) for e in edge_ids]
    isempty(blocks) && return spzeros(0, 0)
    return blockdiag(blocks...)
end

"""
    quadratic_form(P) -> (Hq, g, c)

The objective of `P` as one quadratic, `J(x) = (1/2) x'Hq x + g'x + c`, with
`Hq = blockdiag(Q_v) + delta_s' W delta_s` (the node costs plus the weighted
Laplacian of the soft subprogram), `g = q - delta_s' W b_s`, `c = sum c_v +
(1/2) b_s' W b_s`. `Hq` is exactly symmetric.
"""
function quadratic_form(P::GraphProgram)
    n = c0dim(P)
    Qb = isempty(P.nodes) ? spzeros(0, 0) : blockdiag((nd.Q for nd in P.nodes)...)
    q = reduce(vcat, (nd.q for nd in P.nodes); init = Float64[])
    c = sum((nd.c for nd in P.nodes); init = 0.0)
    S = soft_edges(P)
    Ds = edge_operator(P, S)
    bs = targets(P, S)
    Ws = weight_matrix(P, S)
    if isempty(S) || size(Ds, 1) == 0
        Hq = SpMat(Qb)
        g = q
    else
        WD = Ws * Ds
        Hq = SpMat(Qb + Ds' * WD)
        g = q - Ds' * (Ws * bs)
        c += 0.5 * dot(bs, Ws * bs)
    end
    Hq = SpMat((Hq + Hq') / 2)
    return Hq, g, c
end

"""
    objective(P, x)

`J(x)` evaluated term by term from the data (node costs plus soft edge energies),
independently of `quadratic_form`.
"""
function objective(P::GraphProgram, x::AbstractVector)
    J = 0.0
    for v in 1:nvertices(P)
        nd = P.nodes[v]
        xv = view(x, vrange(P, v))
        J += 0.5 * dot(xv, nd.Q * xv) + dot(nd.q, xv) + nd.c
    end
    for (e, E) in enumerate(P.edges)
        E.hard && continue
        edgedim(E) == 0 && continue
        r = edge_defect(P, e, x)
        J += 0.5 * dot(r, E.W * r)
    end
    return J
end

"""
    node_constraints(P) -> (A, b, cones, row_offsets)

All node constraints stacked in vertex order: `x in Omega` iff `b - A x in K`.
`row_offsets[v]+1 : row_offsets[v+1]` are the rows of vertex `v`.
"""
function node_constraints(P::GraphProgram)
    nv = nvertices(P)
    I = Int[]; J = Int[]; V = Float64[]
    b = Float64[]
    cones = ConeBlock[]
    row_offsets = zeros(Int, nv + 1)
    row = 0
    for v in 1:nv
        nd = P.nodes[v]
        _push_block!(I, J, V, row, P.offsets[v], nd.A, 1.0)
        append!(b, nd.b)
        append!(cones, nd.cones)
        row += size(nd.A, 1)
        row_offsets[v+1] = row
    end
    return sparse(I, J, V, row, c0dim(P)), b, cones, row_offsets
end

"""The zero-cone (equality) rows among the node constraints, as `(A0, b0)`."""
function node_equalities(P::GraphProgram)
    A, b, cones, _ = node_constraints(P)
    rows = Int[]
    r = 0
    for cb in cones
        cb.kind == ZERO_CONE && append!(rows, (r+1):(r+cb.dim))
        r += cb.dim
    end
    return A[rows, :], b[rows]
end

"""Violation of one cone by the slack vector `s` (0 when `s` is in the cone)."""
function cone_violation(kind::ConeKind, s::AbstractVector)
    isempty(s) && return 0.0
    if kind == ZERO_CONE
        return maximum(abs, s)
    elseif kind == NONNEG_CONE
        return max(0.0, -minimum(s))
    else
        return max(0.0, norm(view(s, 2:length(s))) - s[1])
    end
end

"""
    feasibility(P, x) -> NamedTuple

Residuals of `x` for `P`: `hard` = largest `|(delta x)_e - b_e|` over hard
edges; `zero`, `nonneg`, `soc` = largest violation of each cone type among the
node constraints; `cone` = the largest of the three.
"""
function feasibility(P::GraphProgram, x::AbstractVector)
    hard = 0.0
    for (e, E) in enumerate(P.edges)
        (E.hard && edgedim(E) > 0) || continue
        hard = max(hard, maximum(abs, edge_defect(P, e, x)))
    end
    viol = Dict(ZERO_CONE => 0.0, NONNEG_CONE => 0.0, SOC_CONE => 0.0)
    for v in 1:nvertices(P)
        nd = P.nodes[v]
        isempty(nd.b) && continue
        s = nd.b - nd.A * view(x, vrange(P, v))
        r = 0
        for cb in nd.cones
            viol[cb.kind] = max(viol[cb.kind], cone_violation(cb.kind, view(s, (r+1):(r+cb.dim))))
            r += cb.dim
        end
    end
    return (hard = hard, zero = viol[ZERO_CONE], nonneg = viol[NONNEG_CONE],
            soc = viol[SOC_CONE], cone = max(values(viol)...))
end

"""
    harden(P, S)

THEORY Def 2.2: `P[S]`, the program `P` with every edge in `S` made hard. The
weights of `S` are kept in the data structure but are ignored once hard.
"""
function harden(P::GraphProgram, S)
    Sset = falses(nedges(P))
    for e in S
        Sset[e] = true
    end
    edges = [Sset[e] && !E.hard ? GraphEdge(E.tail, E.head, E.Ft, E.Fh, true, E.W, E.b, E.tag) : E
             for (e, E) in enumerate(P.edges)]
    return GraphProgram(P.nodes, edges)
end

"""
    reweight(P, S, w)

`P_w` of THEORY Prop 2.6: the weights of the soft edges in `S` multiplied by `w`.
"""
function reweight(P::GraphProgram, S, w::Real)
    Sset = falses(nedges(P))
    for e in S
        Sset[e] = true
    end
    edges = [Sset[e] && !E.hard ? GraphEdge(E.tail, E.head, E.Ft, E.Fh, false, w * E.W, E.b, E.tag) : E
             for (e, E) in enumerate(P.edges)]
    return GraphProgram(P.nodes, edges)
end

"""
    reverse_edge(E)

The same edge with the opposite reference orientation: the two
edge maps swap and the target changes sign, so the constraint and the
energy are unchanged.
"""
reverse_edge(E::GraphEdge) = GraphEdge(E.head, E.tail, E.Fh, E.Ft, E.hard, E.W, -E.b, E.tag)

"""
    merge_parallel_edges(P) -> (Pm, groups)

Merge every family of parallel edges of the same type (all hard, or all soft)
between the same two vertices into one edge whose space is the direct sum of
theirs (one summand per original edge, nothing combined; weights become block
diagonal). This is the "one coarse edge per edge of the image graph" reading of
THEORY Def 2.3; it gives the same program. `groups[k]` lists the original edges
of merged edge `k`. Tags of merged edges become `EdgeTag(kind, i, j, -1)`.
"""
function merge_parallel_edges(P::GraphProgram)
    key(E) = (min(E.tail, E.head), max(E.tail, E.head), E.hard)
    order = Dict{Tuple{Int,Int,Bool},Int}()
    groups = Vector{Vector{Int}}()
    for (e, E) in enumerate(P.edges)
        k = key(E)
        g = get!(order, k) do
            push!(groups, Int[])
            length(groups)
        end
        push!(groups[g], e)
    end
    edges = GraphEdge[]
    for grp in groups
        E1 = P.edges[grp[1]]
        u, v = min(E1.tail, E1.head), max(E1.tail, E1.head)
        parts = [P.edges[e].tail == u ? P.edges[e] : reverse_edge(P.edges[e]) for e in grp]
        Ft = reduce(vcat, (p.Ft for p in parts))
        Fh = reduce(vcat, (p.Fh for p in parts))
        b = reduce(vcat, (p.b for p in parts))
        d = length(b)
        W = d == 0 ? zeros(0, 0) : Matrix(blockdiag((sparse(p.W) for p in parts)...))
        tag = length(grp) == 1 ? E1.tag : EdgeTag(E1.tag.kind, E1.tag.i, E1.tag.j, -1)
        push!(edges, GraphEdge(u, v, Ft, Fh, E1.hard, W, b, tag))
    end
    return GraphProgram(P.nodes, edges), groups
end
