# program.jl: homological programs on cellular sheaves (the paper's Def. 2).
#
# A cellular sheaf on a graph G = (V, E) puts a vector space (a stalk) on every
# vertex and every edge, and a linear restriction map from each vertex stalk to
# the stalk of each edge it touches (Curry 2014; Hansen and Ghrist 2019). A
# 0-cochain x picks one vector x_v in every vertex stalk; the coboundary delta
# measures, edge by edge, how far the two ends disagree after restriction:
#
#     (delta x)_e = F_{head <| e} x_head - F_{tail <| e} x_tail.
#
# A program adds convex data: every vertex carries a convex quadratic cost f_v
# and a conic constraint set Omega_v; every edge is either hard ((delta x)_e =
# b_e exactly) or soft (a spring of stiffness W_e pulling (delta x)_e toward
# b_e, with energy (1/2)||(delta x)_e - b_e||^2_{W_e}). The node sets are
# products of the zero, nonnegative and second-order cones, so every program is
# a conic QP (`sheaf_qp`).

"""
    ConeKind

The cones of node constraints, in the convention `b - A x in K`:

* `ZERO_CONE`: `b - A x = 0` (equality rows, such as the pinned initial state),
* `NONNEG_CONE`: `b - A x >= 0` componentwise (half-spaces, boxes),
* `SOC_CONE`: `s = b - A x = (t, z)` with `||z|| <= t` (second-order cone,
  such as a ball of inputs).
"""
@enum ConeKind ZERO_CONE NONNEG_CONE SOC_CONE

"""A block of `dim` consecutive constraint rows, all in one cone."""
struct ConeBlock
    kind::ConeKind
    dim::Int
end

"""`zero_cone(d)`: `d` equality rows."""
zero_cone(d::Integer) = ConeBlock(ZERO_CONE, d)
"""`nonneg_cone(d)`: `d` half-space rows."""
nonneg_cone(d::Integer) = ConeBlock(NONNEG_CONE, d)
"""`soc_cone(d)`: one second-order cone of dimension `d` (`d - 1` entries bounded in norm by the first)."""
soc_cone(d::Integer) = ConeBlock(SOC_CONE, d)

# matrices are shared, not copied (they are never changed in place); vectors are copied
_spmat(M::SpMat) = M
_spmat(M::AbstractMatrix) = SpMat(sparse(M))

"""
    NodeData(Q, q, c, A, b, cones)
    NodeData(Q, q, c = 0)

The convex data at one vertex `v` of a program:

* the cost `f_v(x) = (1/2) x'Qx + q'x + c`, `Q` positive semidefinite;
* the constraint set `Omega_v = { x : b - A x in K }`, `K` the product of the
  cones in `cones` (their dimensions add up to the number of rows of `A`).

The vectors `q`, `b` and the constant `c` may be changed in place between
solves (receding horizon); the matrices are fixed (and shared, not copied,
when given as sparse matrices).
"""
mutable struct NodeData
    Q::SpMat
    q::Vector{Float64}
    c::Float64
    A::SpMat
    b::Vector{Float64}
    cones::Vector{ConeBlock}
    function NodeData(Q::AbstractMatrix, q::AbstractVector, c::Real,
                      A::AbstractMatrix, b::AbstractVector, cones::Vector{ConeBlock})
        d = length(q)
        size(Q) == (d, d) || throw(DimensionMismatch("Q is $(size(Q)), the stalk has dimension $d"))
        size(A, 2) == d || throw(DimensionMismatch("A has $(size(A, 2)) columns, the stalk has dimension $d"))
        size(A, 1) == length(b) || throw(DimensionMismatch("A has $(size(A, 1)) rows, b has $(length(b))"))
        sum((cb.dim for cb in cones); init = 0) == length(b) ||
            throw(DimensionMismatch("the cone dimensions do not add up to the rows of A"))
        new(_spmat(Q), Vector{Float64}(q), Float64(c), _spmat(A), Vector{Float64}(b), cones)
    end
end

NodeData(Q::AbstractMatrix, q::AbstractVector, c::Real = 0.0) =
    NodeData(Q, q, c, spzeros(0, length(q)), Float64[], ConeBlock[])

"""
    EdgeTag(kind, i, j, t)

Bookkeeping an edge keeps through every pushforward (a coarse edge is a fine
edge that survived). For multi-agent MPC: `kind = :dyn` for the dynamics edge
of agent `i` from instant `t` to `t + 1` (`j == i`), `kind = :form` for the
formation edge `ij` at instant `t`; `kind = :generic` otherwise. The
structured fiber basis reads `:dyn` to condense along time first.
"""
struct EdgeTag
    kind::Symbol
    i::Int
    j::Int
    t::Int
end
EdgeTag() = EdgeTag(:generic, 0, 0, 0)

"""
    SheafEdge(tail, head, Ft, Fh, hard, W, b, tag = EdgeTag())

An oriented edge `e : tail -> head` with stalk `R^{d_e}` (`d_e = length(b)`,
possibly zero), restriction maps `Ft = F_{tail <| e}` and `Fh = F_{head <| e}`,
so that `(delta x)_e = Fh x_head - Ft x_tail`, target `b_e`, and, for a soft
edge, the stiffness `W` (positive definite; ignored when `hard`). The target
`b` may be changed in place between solves.
"""
struct SheafEdge
    tail::Int
    head::Int
    Ft::SpMat
    Fh::SpMat
    hard::Bool
    W::Matrix{Float64}
    b::Vector{Float64}
    tag::EdgeTag
    function SheafEdge(tail::Integer, head::Integer, Ft::AbstractMatrix, Fh::AbstractMatrix,
                       hard::Bool, W::AbstractMatrix, b::AbstractVector, tag::EdgeTag = EdgeTag())
        tail == head && throw(ArgumentError("self loops are not allowed (edge at vertex $tail)"))
        d = length(b)
        size(Ft, 1) == d && size(Fh, 1) == d || throw(DimensionMismatch("restriction maps must have $d rows"))
        size(W) == (d, d) || throw(DimensionMismatch("W must be $d x $d"))
        new(tail, head, _spmat(Ft), _spmat(Fh), hard, Matrix{Float64}(W), Vector{Float64}(b), tag)
    end
end

"""`edgedim(E)`: the dimension of the edge stalk (0 for an absent edge)."""
edgedim(E::SheafEdge) = length(E.b)

"""
    SheafProgram(nodes, edges)

A homological program (the paper's Def. 2):

    minimize  J(x) = sum_v f_v(x_v) + (1/2) sum_{e soft} ||(delta x)_e - b_e||^2_{W_e}
    subject to x_v in Omega_v for every vertex,  (delta x)_e = b_e for every hard edge.

Vertices are `1:length(nodes)` with stalk dimensions `dims[v]`. A 0-cochain is
one flat vector; `x[vrange(P, v)]` is `x_v`. The graph may have parallel edges
(pushforwards make them). `row_offsets[v]+1 : row_offsets[v+1]` are the node
constraint rows of vertex `v` when all are stacked in vertex order.
"""
struct SheafProgram
    dims::Vector{Int}
    nodes::Vector{NodeData}
    edges::Vector{SheafEdge}
    offsets::Vector{Int}
    edge_offsets::Vector{Int}
    row_offsets::Vector{Int}
    function SheafProgram(nodes::Vector{NodeData}, edges::Vector{SheafEdge})
        dims = [length(nd.q) for nd in nodes]
        nv = length(nodes)
        for (k, E) in enumerate(edges)
            (1 <= E.tail <= nv && 1 <= E.head <= nv) || throw(ArgumentError("edge $k has an endpoint outside 1:$nv"))
            size(E.Ft, 2) == dims[E.tail] ||
                throw(DimensionMismatch("edge $k: Ft has $(size(E.Ft, 2)) columns, the tail stalk has $(dims[E.tail])"))
            size(E.Fh, 2) == dims[E.head] ||
                throw(DimensionMismatch("edge $k: Fh has $(size(E.Fh, 2)) columns, the head stalk has $(dims[E.head])"))
        end
        offsets = [0; cumsum(dims)]
        edge_offsets = [0; cumsum([edgedim(E) for E in edges])]
        row_offsets = [0; cumsum([length(nd.b) for nd in nodes])]
        new(dims, nodes, edges, offsets, edge_offsets, row_offsets)
    end
end

"""`nvertices(P)`: the number of vertices."""
nvertices(P::SheafProgram) = length(P.nodes)
"""`nedges(P)`: the number of edges."""
nedges(P::SheafProgram) = length(P.edges)
"""`dim C^0`, the number of scalar decision variables."""
c0dim(P::SheafProgram) = P.offsets[end]
"""`dim C^1`, the total edge stalk dimension."""
c1dim(P::SheafProgram) = P.edge_offsets[end]
"""The number of node constraint rows."""
noderows(P::SheafProgram) = P.row_offsets[end]
"""`vrange(P, v)`: the entries of vertex `v` in a flat 0-cochain."""
vrange(P::SheafProgram, v::Integer) = (P.offsets[v]+1):P.offsets[v+1]
"""`erange(P, e)`: the entries of edge `e` in a flat 1-cochain (and in the stacked edge targets)."""
erange(P::SheafProgram, e::Integer) = (P.edge_offsets[e]+1):P.edge_offsets[e+1]
rrange(P::SheafProgram, v::Integer) = (P.row_offsets[v]+1):P.row_offsets[v+1]
"""`hard_edges(P)`, `soft_edges(P)`: the indices of the hard (constraint) and soft (spring) edges."""
hard_edges(P::SheafProgram) = [e for (e, E) in enumerate(P.edges) if E.hard]
@doc (@doc hard_edges) soft_edges(P::SheafProgram) = [e for (e, E) in enumerate(P.edges) if !E.hard]
edgedims(P::SheafProgram, S) = sum((edgedim(P.edges[e]) for e in S); init = 0)

"""`(delta x)_e` for one edge."""
function edge_value(P::SheafProgram, e::Integer, x::AbstractVector)
    E = P.edges[e]
    return E.Fh * view(x, vrange(P, E.head)) - E.Ft * view(x, vrange(P, E.tail))
end

"""`(delta x)_e - b_e`, the defect of edge `e` at `x`."""
edge_defect(P::SheafProgram, e::Integer, x::AbstractVector) = edge_value(P, e, x) - P.edges[e].b

# `_push_block!(I, J, V, r0, c0, M, s)` (sheaf.jl) appends the triplets of `s * M` at offset `(r0, c0)`.

"""
    coboundary(P, edge_ids = 1:nedges(P))

The rows `delta_S` of the coboundary for the edges `S = edge_ids`, stacked in
the given order, as a sparse matrix with `c0dim(P)` columns; `targets(P, S)`
is the matching right-hand side `b_S`.
"""
function coboundary(P::SheafProgram, edge_ids = 1:nedges(P))
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

"""`targets(P, S)`: the stacked targets `b_S` of the edges `S`."""
targets(P::SheafProgram, edge_ids = 1:nedges(P)) = reduce(vcat, (P.edges[e].b for e in edge_ids); init = Float64[])

"""Block diagonal stiffness of the edges `S` (as a sparse matrix)."""
function weight_matrix(P::SheafProgram, edge_ids)
    I = Int[]; J = Int[]; V = Float64[]
    row = 0
    for e in edge_ids
        W = P.edges[e].W
        d = size(W, 1)
        for jj in 1:d, ii in 1:d
            W[ii, jj] != 0 && (push!(I, row + ii); push!(J, row + jj); push!(V, W[ii, jj]))
        end
        row += d
    end
    return sparse(I, J, V, row, row)
end

"""The block diagonal of the node Hessians `Q_v` (`c0dim x c0dim`)."""
function node_hessian(P::SheafProgram)
    I = Int[]; J = Int[]; V = Float64[]
    for (v, nd) in enumerate(P.nodes)
        _push_block!(I, J, V, P.offsets[v], P.offsets[v], nd.Q, 1.0)
    end
    return sparse(I, J, V, c0dim(P), c0dim(P))
end

"""
    quadratic_form(P) -> (H, g, c)

The objective as one quadratic, `J(x) = (1/2) x'Hx + g'x + c`, with `H =
blockdiag(Q_v) + delta_s' W delta_s` (the node costs plus the weighted sheaf
Laplacian of the soft edges), `g = q - delta_s' W b_s` and `c = sum c_v +
(1/2) b_s' W b_s`.
"""
function quadratic_form(P::SheafProgram)
    Qb = node_hessian(P)
    q = reduce(vcat, (nd.q for nd in P.nodes); init = Float64[])
    c = sum((nd.c for nd in P.nodes); init = 0.0)
    S = [e for e in soft_edges(P) if edgedim(P.edges[e]) > 0]
    isempty(S) && return SpMat((Qb + Qb') / 2), q, c
    Ds = coboundary(P, S); bs = targets(P, S); Ws = weight_matrix(P, S)
    H = Qb + Ds' * (Ws * Ds)
    g = q - Ds' * (Ws * bs)
    c += 0.5 * dot(bs, Ws * bs)
    return SpMat((H + H') / 2), g, c
end

"""
    objective(P::SheafProgram, x)

`J(x)` evaluated term by term (node costs plus soft edge energies), without
the constraints.
"""
function objective(P::SheafProgram, x::AbstractVector)
    J = 0.0
    for v in 1:nvertices(P)
        nd = P.nodes[v]
        xv = view(x, vrange(P, v))
        J += 0.5 * dot(xv, nd.Q * xv) + dot(nd.q, xv) + nd.c
    end
    for (e, E) in enumerate(P.edges)
        (E.hard || edgedim(E) == 0) && continue
        r = edge_defect(P, e, x)
        J += 0.5 * dot(r, E.W * r)
    end
    return J
end

"""
    node_constraints(P) -> (A, b, cones)

All node constraints stacked in vertex order: `x in Omega` iff `b - A x in K`;
`rrange(P, v)` are the rows of vertex `v`.
"""
function node_constraints(P::SheafProgram)
    I = Int[]; J = Int[]; V = Float64[]
    b = Float64[]; cones = ConeBlock[]
    for (v, nd) in enumerate(P.nodes)
        _push_block!(I, J, V, P.row_offsets[v], P.offsets[v], nd.A, 1.0)
        append!(b, nd.b)
        append!(cones, nd.cones)
    end
    return sparse(I, J, V, noderows(P), c0dim(P)), b, cones
end

"""
Copy the values of `src` onto the stored entries of `dst` (same size; the
entries of `dst` that `src` does not store become zero). Throws when `src` has
a nonzero outside the pattern of `dst`: the pattern of a constraint matrix is
fixed once a solver has been set up on it.
"""
function _copy_values!(dst::SparseMatrixCSC, src::SparseMatrixCSC)
    size(dst) == size(src) || throw(DimensionMismatch("sizes $(size(dst)) and $(size(src)) differ"))
    rd = rowvals(dst); vd = nonzeros(dst); rs = rowvals(src); vs = nonzeros(src)
    @inbounds for j in 1:size(dst, 2)
        kd = first(nzrange(dst, j)); ed = last(nzrange(dst, j))
        for k in kd:ed
            vd[k] = 0.0
        end
        for k in nzrange(src, j)
            v = vs[k]
            r = rs[k]
            while kd <= ed && rd[kd] < r
                kd += 1
            end
            if kd <= ed && rd[kd] == r
                vd[kd] = v
            elseif v != 0
                throw(ArgumentError("a nonzero at ($r, $j) lies outside the fixed sparsity pattern"))
            end
        end
    end
    return dst
end

"""
Refresh the rows of the vertices `verts` in `An`, the matrix of
`node_constraints(P)` (or one with its pattern), from the current node
matrices of `P` (changed in place on their patterns).
"""
function _refresh_node_rows!(An::SparseMatrixCSC, P::SheafProgram, verts)
    rv = rowvals(An); nz = nonzeros(An)
    for v in verts
        A = P.nodes[v].A
        r0 = P.row_offsets[v]; c0 = P.offsets[v]
        ra = rowvals(A); va = nonzeros(A)
        @inbounds for j in 1:size(A, 2)
            rng = nzrange(An, c0 + j)
            for k in nzrange(A, j)
                r = r0 + ra[k]
                p = searchsortedfirst(view(rv, rng), r)
                (p <= length(rng) && rv[rng[p]] == r) ||
                    throw(ArgumentError("the node matrix of vertex $v left its sparsity pattern"))
                nz[rng[p]] = va[k]
            end
        end
    end
    return An
end

"""Violation of one cone by the slack `s` (0 when `s` lies in the cone)."""
function cone_violation(kind::ConeKind, s::AbstractVector)
    isempty(s) && return 0.0
    kind == ZERO_CONE && return maximum(abs, s)
    kind == NONNEG_CONE && return max(0.0, -minimum(s))
    return max(0.0, norm(view(s, 2:length(s))) - s[1])
end

"""
    feasibility(P, x) -> NamedTuple

Residuals of `x`: `hard`, the largest `|(delta x)_e - b_e|` over hard edges, and
`cone`, the largest violation of a node constraint.
"""
function feasibility(P::SheafProgram, x::AbstractVector)
    hard = 0.0
    for (e, E) in enumerate(P.edges)
        (E.hard && edgedim(E) > 0) || continue
        hard = max(hard, maximum(abs, edge_defect(P, e, x)))
    end
    cone = 0.0
    for v in 1:nvertices(P)
        nd = P.nodes[v]
        isempty(nd.b) && continue
        s = nd.b - nd.A * view(x, vrange(P, v))
        r = 0
        for cb in nd.cones
            cone = max(cone, cone_violation(cb.kind, view(s, (r+1):(r+cb.dim))))
            r += cb.dim
        end
    end
    return (hard = hard, cone = cone)
end

"""
    harden(P, S)

`P[S]`: the program `P` with every edge in `S` made hard (the paper's notation
`P[S]`). The stiffnesses of `S` are kept but ignored.
"""
function harden(P::SheafProgram, S)
    mark = falses(nedges(P))
    for e in S
        mark[e] = true
    end
    edges = [mark[e] && !E.hard ? SheafEdge(E.tail, E.head, E.Ft, E.Fh, true, E.W, E.b, E.tag) : E
             for (e, E) in enumerate(P.edges)]
    return SheafProgram(P.nodes, edges)
end

"""Copy of a program whose vectors (`q`, `c`, `b` of nodes and edges) can be changed independently."""
function Base.copy(P::SheafProgram)
    nodes = [NodeData(nd.Q, copy(nd.q), nd.c, nd.A, copy(nd.b), copy(nd.cones)) for nd in P.nodes]
    edges = [SheafEdge(E.tail, E.head, E.Ft, E.Fh, E.hard, E.W, copy(E.b), E.tag) for E in P.edges]
    return SheafProgram(nodes, edges)
end

function Base.show(io::IO, P::SheafProgram)
    nh = count(E -> E.hard, P.edges)
    print(io, "SheafProgram($(nvertices(P)) vertices, $(nedges(P)) edges ($nh hard), dim C^0 = $(c0dim(P)), ",
          "$(noderows(P)) node rows)")
end

# ---------------------------------------------------------------------------
# The program's data as flat vectors (what changes between receding-horizon
# steps): node linear costs q (dim C^0), the sum of the node constants, node
# right-hand sides b (stacked in vertex order) and edge targets (dim C^1).
# ---------------------------------------------------------------------------

"""Flat copies of a program's vectors: `q` (stacked node costs), `c`, `bn` (node rows), `be` (edge targets)."""
mutable struct FlatData
    q::Vector{Float64}
    c::Float64
    bn::Vector{Float64}
    be::Vector{Float64}
end

FlatData(P::SheafProgram) = gather!(FlatData(zeros(c0dim(P)), 0.0, zeros(noderows(P)), zeros(c1dim(P))), P)

"""Read the program's vectors into `fd` (no allocation)."""
function gather!(fd::FlatData, P::SheafProgram)
    c = 0.0
    @inbounds for (v, nd) in enumerate(P.nodes)
        o = P.offsets[v]
        for k in eachindex(nd.q)
            fd.q[o+k] = nd.q[k]
        end
        r = P.row_offsets[v]
        for k in eachindex(nd.b)
            fd.bn[r+k] = nd.b[k]
        end
        c += nd.c
    end
    fd.c = c
    @inbounds for (e, E) in enumerate(P.edges)
        o = P.edge_offsets[e]
        for k in eachindex(E.b)
            fd.be[o+k] = E.b[k]
        end
    end
    return fd
end
