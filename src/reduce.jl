# reduce.jl: the pushforward of a program along a partition (the paper's
# Defs. 3 and 4), its lift, and the in-place update of the reduced data.
#
# The partition defines the quotient map of the graph: one coarse vertex per
# block, the edges inside a block collapse, every other edge becomes its own
# coarse edge (a multigraph). Writing each block's variables as
# x_B = X_B r_B + N_B y_B (its affine fiber) turns the fine program with the
# collapsed edges made hard into a program in the coarse coordinates y
# (Thm. 1, contraction makes edges hard):
#
#   coarse node cost   f'_B(y) = sum_{v in B} f_v(x_v(y)),
#   coarse node set    the members' sets, b - A xbar - (A N) y in K,
#   coarse edge e      restriction maps F N, target b_e - (delta xbar)_e.
#
# The basis N and the operator X depend only on the restriction maps of the
# internal edges; the data that change from one MPC step to the next (measured
# states, references, formation targets, drifts) enter the coarse program
# affinely. `update!(reduced)` recomputes the coarse vectors from the fine ones
# with a few sparse products and no allocation.

"""
    ReducedProgram

The pushforward of a program along a resolution: the coarse `program`, the
fibers of its blocks, the lift `x = xbar + N y` (`N`, and `X` with
`xbar = X b`, `b` the fine edge targets), the fine edges behind the coarse
edges (`cross`), the contracted edges (`collapsed`), the coarse `layout` (for
product resolutions), and the `parent` it was reduced from (a `FleetProgram`,
another `ReducedProgram` for teams of teams, or a `SheafProgram`).
`feasible == false` means some affine fiber is empty, so the reduced program
is infeasible (the fine program with the contracted edges made hard is).
"""
mutable struct ReducedProgram
    parent::Any
    fine::SheafProgram
    program::SheafProgram
    resolution::Resolution
    basis::Symbol
    partition::Vector{Int}
    local_index::Vector{Int}
    fibers::Vector{Fiber}
    collapsed::Vector{Int}
    cross::Vector{Int}
    coarse_offsets::Vector{Int}
    N::SpMat
    Nt::SparseMatrixCSC{Float64}
    X::SparseMatrixCSC{Float64}
    Cons::SparseMatrixCSC{Float64}
    layout::Union{FleetLayout,Nothing}
    feasible::Bool
    consistency::Float64
    consistency_tol::Float64
    # in-place update: operators and buffers
    Qn::SparseMatrixCSC{Float64}
    An::SparseMatrixCSC{Float64}
    Dx::SparseMatrixCSC{Float64}
    xrows::Vector{Int}
    rowmap::Vector{Int}
    vertex_block::Vector{Int}
    fd::FlatData
    xbar::Vector{Float64}
    w::Vector{Float64}
    Anx::Vector{Float64}
    Dxx::Vector{Float64}
    qc::Vector{Float64}
    cc::Vector{Float64}
    cons::Vector{Float64}
    # restrict: per fiber, the factorization of its basis (built on first use, `nothing` for an orthonormal basis)
    rfac::Vector{Any}
    rbuf::Vector{Float64}
    # flat copies of the coarse vectors (node rows, edge targets): the input of the next level of a chain
    bnc::Vector{Float64}
    bec::Vector{Float64}
    shared::Bool    # reads its parent's flat vectors instead of gathering them from the parent's program
    lazy::Bool      # a child reads the flat vectors, so `program` is written only when read (see `getproperty`)
    stale::Bool     # `program` is behind the flat vectors
end

"""32-bit indices for the operators applied at every step (a step is memory bound: 12 instead of 16 bytes per entry)."""
_compact(A::SparseMatrixCSC{Float64}) =
    max(nnz(A), size(A, 1), size(A, 2)) < typemax(Int32) ? SparseMatrixCSC{Float64,Int32}(A) : A

# `program` of a level whose child reads the flat vectors is written when it is asked for.
function Base.getproperty(R::ReducedProgram, s::Symbol)
    if s === :program && getfield(R, :stale)
        _scatter!(R)
    end
    if s === :fine
        par = getfield(R, :parent)
        par isa ReducedProgram && getfield(par, :stale) && _scatter!(par)
    end
    return getfield(R, s)
end

_sheaf(P::SheafProgram) = P
_sheaf(R::ReducedProgram) = R.program
_layout(::SheafProgram) = nothing
_layout(R::ReducedProgram) = R.layout

"""`fiber_kinds(R)`: the basis of every fiber (`:identity`, `:structured`, `:structured_reduced`, `:orthonormal`)."""
fiber_kinds(R::ReducedProgram) = [F.kind for F in R.fibers]

function Base.show(io::IO, R::ReducedProgram)
    P, Pc = R.fine, R.program
    print(io, "ReducedProgram($(nameof(typeof(R.resolution))): $(nvertices(P)) -> $(nvertices(Pc)) vertices, ",
          "dim C^0 $(c0dim(P)) -> $(c0dim(Pc)), $(length(R.collapsed)) edges contracted",
          R.feasible ? "" : ", INFEASIBLE (empty fiber)", ")")
end

"""Rows of the member `l` of a block, as a sparse slice of `N_B` (read through its transpose)."""
_member_basis(NtB::SpMat, lr::UnitRange{Int}) = copy(transpose(NtB[:, lr]))

"""
    reduce(program, resolution; basis = :structured, reuse = nothing, consistency_tol = 1e-8) -> ReducedProgram

The pushforward of `program` (a `FleetProgram`, a `ReducedProgram` or a
`SheafProgram`) along `resolution` (the paper's Def. 4): one coarse vertex per
block, whose stalk is the space of sections of the block's fiber; coarse costs
and constraints by substitution of the lift `x = xbar + N y`; one coarse edge
per edge that is not contracted, same kind and stiffness. By Thm. 1 the
reduced program is the fine one with the contracted edges made hard: same
optimal value, and every lifted plan is feasible for the fine program.

`basis = :structured` (forward substitution, sparse) or `:orthonormal` (dense
SVD per block); the lifted plans and values do not depend on it.
`reuse = R0`, a previous reduction along the same resolution (receding
horizon), keeps every fiber whose internal restriction maps are unchanged: the
targets may change, since the particular solution is an operator of them.
When nothing structural changed (the same node matrices and edge maps), the
coarse matrices and the update operators are shared too, and the reduction
costs one `update!`.
Reducing a `ReducedProgram` composes the reductions (teams of teams, the
paper's Thm. 4): `lift` then lifts level by level.
"""
function Base.reduce(prog::Union{SheafProgram,ReducedProgram}, res::Resolution; basis::Symbol = :structured,
                     reuse = nothing, consistency_tol::Real = 1e-8)
    P = _sheaf(prog)
    labels, clayout = vertex_labels(res, nvertices(P), _layout(prog))
    return _pushforward(prog, P, res, labels, clayout; basis = basis, reuse = reuse, consistency_tol = consistency_tol)
end

function _pushforward(parent, P::SheafProgram, res::Resolution, Pi::Vector{Int}, clayout;
                      basis::Symbol = :structured, reuse = nothing, consistency_tol::Real = 1e-8)
    nv = nvertices(P)
    nb = nblocks(Pi)
    members = block_members(Pi)
    local_index = zeros(Int, nv)
    for mem in members, (l, v) in enumerate(mem)
        local_index[v] = l
    end
    internal = [Int[] for _ in 1:nb]
    cross = Int[]
    for (e, E) in enumerate(P.edges)
        bt, bh = Pi[E.tail], Pi[E.head]
        bt == bh ? push!(internal[bt], e) : push!(cross, e)
    end
    collapsed = sort!(reduce(vcat, internal; init = Int[]))
    R0 = reuse
    reusable = R0 isa ReducedProgram && R0.basis == basis && R0.partition == Pi && R0.fine.dims == P.dims &&
               nedges(R0.fine) == nedges(P)
    fibers = Vector{Fiber}(undef, nb)
    for b in 1:nb
        if reusable && R0.fibers[b].internal == internal[b] && _same_maps(P, R0.fine, internal[b])
            fibers[b] = R0.fibers[b]
        else
            fibers[b] = _make_fiber(P, members[b], internal[b], local_index, basis)
        end
    end
    if reusable && all(b -> fibers[b] === R0.fibers[b], 1:nb) && _same_structure(P, R0.fine, cross)
        # nothing structural changed: share the coarse matrices and operators, recompute the vectors
        return _reuse_structure(parent, P, res, R0, clayout)
    end
    kdims = [fiberdim(F) for F in fibers]
    coarse_offsets = [0; cumsum(kdims)]
    # the global lift: N (fine x coarse), X (fine x C^1 of the fine program), consistency rows
    NI = Int[]; NJ = Int[]; NV = Float64[]
    XI = Int[]; XJ = Int[]; XV = Float64[]
    CI = Int[]; CJ = Int[]; CV = Float64[]
    crow = 0
    for b in 1:nb
        F = fibers[b]
        rowmap = Vector{Int}(undef, length(F))
        for (l, v) in enumerate(F.members)
            rowmap[(F.offsets[l]+1):F.offsets[l+1]] .= vrange(P, v)
        end
        colmap = Vector{Int}(undef, F.roffsets[end])
        for (k, e) in enumerate(F.internal)
            colmap[(F.roffsets[k]+1):F.roffsets[k+1]] .= erange(P, e)
        end
        ii, jj, vv = findnz(F.N)
        append!(NI, rowmap[ii]); append!(NJ, coarse_offsets[b] .+ jj); append!(NV, vv)
        ii, jj, vv = findnz(F.X)
        append!(XI, rowmap[ii]); append!(XJ, colmap[jj]); append!(XV, vv)
        if nnz(F.C) > 0
            ii, jj, vv = findnz(F.C)
            append!(CI, crow .+ ii); append!(CJ, colmap[jj]); append!(CV, vv)
            crow += size(F.C, 1)
        end
    end
    n = c0dim(P)
    N = sparse(NI, NJ, NV, n, coarse_offsets[end])
    X = sparse(XI, XJ, XV, n, c1dim(P))
    Cons = sparse(CI, CJ, CV, crow, c1dim(P))
    # coarse nodes: Hessians and constraint matrices by substitution (vectors set by update!)
    cnodes = Vector{NodeData}(undef, nb)
    NtB = Vector{SpMat}(undef, nb)
    vertex_block = Pi
    rowmap = Int[]
    for b in 1:nb
        F = fibers[b]
        NB = F.N
        NtB[b] = SpMat(transpose(NB))
        QI = Int[]; QJ = Int[]; QV = Float64[]
        AI = Int[]; AJ = Int[]; AV = Float64[]
        cones = ConeBlock[]
        arow = 0
        for (l, v) in enumerate(F.members)
            nd = P.nodes[v]
            _push_block!(QI, QJ, QV, F.offsets[l], F.offsets[l], nd.Q, 1.0)
            if !isempty(nd.b)
                _push_block!(AI, AJ, AV, arow, F.offsets[l], nd.A, 1.0)
                append!(rowmap, rrange(P, v))
                append!(cones, nd.cones)
                arow += length(nd.b)
            end
        end
        QB = sparse(QI, QJ, QV, length(F), length(F))
        AB = sparse(AI, AJ, AV, arow, length(F))
        Qc = NtB[b] * (QB * NB)
        Qc = SpMat((Qc + Qc') / 2)
        Ac = SpMat(AB * NB)
        cnodes[b] = NodeData(Qc, zeros(kdims[b]), 0.0, Ac, zeros(arow), cones)
    end
    # coarse edges: one per edge that is not contracted
    cedges = Vector{SheafEdge}(undef, length(cross))
    xrows = Int[]
    member_rows = Dict{Tuple{Int,Int},SpMat}()
    for (k, e) in enumerate(cross)
        E = P.edges[e]
        bt, bh = Pi[E.tail], Pi[E.head]
        Ft, Fh = fibers[bt], fibers[bh]
        lt = (Ft.offsets[local_index[E.tail]]+1):Ft.offsets[local_index[E.tail]+1]
        lh = (Fh.offsets[local_index[E.head]]+1):Fh.offsets[local_index[E.head]+1]
        Nt_ = get!(() -> _member_basis(NtB[bt], lt), member_rows, (bt, local_index[E.tail]))
        Nh_ = get!(() -> _member_basis(NtB[bh], lh), member_rows, (bh, local_index[E.head]))
        Ftc = E.Ft * Nt_
        Fhc = E.Fh * Nh_
        cedges[k] = SheafEdge(bt, bh, Ftc, Fhc, E.hard, E.W, zeros(edgedim(E)), E.tag)
        append!(xrows, erange(P, e))
    end
    Pc = SheafProgram(cnodes, cedges)
    Qn = node_hessian(P)
    An, _, _ = node_constraints(P)
    Dx = coboundary(P, cross)
    R = ReducedProgram(parent, P, Pc, res, basis, Pi, local_index, fibers, collapsed, cross, coarse_offsets,
                       N, _compact(SpMat(transpose(N))), _compact(X), _compact(Cons), clayout, true, 0.0, Float64(consistency_tol),
                       _compact(Qn), _compact(An), _compact(Dx), xrows, rowmap, vertex_block, FlatData(P), zeros(n), zeros(n), zeros(noderows(P)),
                       zeros(c1dim(Pc)), zeros(c0dim(Pc)), zeros(nb), zeros(size(Cons, 1)), Any[], zeros(n),
                       zeros(noderows(Pc)), zeros(c1dim(Pc)), false, false, false)
    _link!(R)
    update!(R)
    return R
end

"""True when the node matrices of `P` and `Pp` agree and the edges `cross` have the same maps, kind and stiffness."""
function _same_structure(P::SheafProgram, Pp::SheafProgram, cross)
    for v in 1:nvertices(P)
        a, b = P.nodes[v], Pp.nodes[v]
        (a.Q === b.Q || a.Q == b.Q) && (a.A === b.A || a.A == b.A) && a.cones == b.cones || return false
    end
    for e in cross
        E, G = P.edges[e], Pp.edges[e]
        (E.tail == G.tail && E.head == G.head && E.hard == G.hard && E.W == G.W && (E.Ft === G.Ft || E.Ft == G.Ft) &&
         (E.Fh === G.Fh || E.Fh == G.Fh) && E.tag == G.tag) || return false
    end
    return true
end

function _reuse_structure(parent, P::SheafProgram, res::Resolution, R0::ReducedProgram, clayout)
    P0c = R0.program
    cnodes = [NodeData(nd.Q, zeros(length(nd.q)), 0.0, nd.A, zeros(length(nd.b)), nd.cones) for nd in P0c.nodes]
    cedges = [SheafEdge(E.tail, E.head, E.Ft, E.Fh, E.hard, E.W, zeros(edgedim(E)), E.tag) for E in P0c.edges]
    Pc = SheafProgram(cnodes, cedges)
    n = c0dim(P)
    R = ReducedProgram(parent, P, Pc, res, R0.basis, R0.partition, R0.local_index, R0.fibers, R0.collapsed, R0.cross,
                       R0.coarse_offsets, R0.N, R0.Nt, R0.X, R0.Cons, clayout, true, 0.0, R0.consistency_tol,
                       R0.Qn, R0.An, R0.Dx, R0.xrows, R0.rowmap, R0.vertex_block, FlatData(P), zeros(n), zeros(n),
                       zeros(noderows(P)), zeros(c1dim(Pc)), zeros(c0dim(Pc)), zeros(nvertices(Pc)), zeros(size(R0.Cons, 1)),
                       R0.rfac, zeros(n), zeros(noderows(Pc)), zeros(c1dim(Pc)), false, false, false)
    _link!(R)
    update!(R)
    return R
end

"""
    update!(reduced::ReducedProgram) -> reduced

Recompute the coarse program's vectors (node costs and constants, node
right-hand sides, edge targets) and the base point `xbar` from the current
vectors of the fine program, after these changed in place (new measured
states, references, targets): `xbar = X b`, coarse costs `N'(Q xbar + q)`,
right-hand sides `b - A xbar`, edge targets `b_e - (delta xbar)_e`. Sparse
products only, no allocation. Also re-checks that every affine fiber is
nonempty (`reduced.feasible`).
"""
function update!(R::ReducedProgram)
    P = getfield(R, :fine)
    shared = R.shared
    fd = shared ? R.fd : gather!(R.fd, P)
    cpar = shared ? (R.parent::ReducedProgram).cc : Float64[]
    be = fd.be
    if size(R.Cons, 1) > 0
        mul!(R.cons, R.Cons, be)
        nb = 0.0
        @inbounds for i in eachindex(be)
            nb = max(nb, abs(be[i]))
        end
        R.consistency = maximum(abs, R.cons)
        R.feasible = R.consistency <= R.consistency_tol * max(1.0, nb)
    end
    xbar = R.xbar
    mul!(xbar, R.X, be)
    w = R.w
    mul!(w, R.Qn, xbar)
    # constants: sum_v (1/2) xbar_v'Q_v xbar_v + q_v'xbar_v + c_v, per block
    cc = R.cc
    fill!(cc, 0.0)
    nodes = P.nodes
    @inbounds for v in 1:nvertices(P)
        s = shared ? cpar[v] : nodes[v].c
        for j in vrange(P, v)
            s += (0.5 * w[j] + fd.q[j]) * xbar[j]
        end
        cc[R.vertex_block[v]] += s
    end
    @inbounds for j in eachindex(w)
        w[j] += fd.q[j]
    end
    mul!(R.qc, R.Nt, w)
    mul!(R.Anx, R.An, xbar)
    mul!(R.Dxx, R.Dx, xbar)
    # flat coarse vectors (the next level reads these)
    bnc, bec, rowmap, xrows, Anx, Dxx = R.bnc, R.bec, R.rowmap, R.xrows, R.Anx, R.Dxx
    @inbounds for i in eachindex(bnc)
        j = rowmap[i]
        bnc[i] = fd.bn[j] - Anx[j]
    end
    @inbounds for i in eachindex(bec)
        bec[i] = be[xrows[i]] - Dxx[i]
    end
    if R.lazy
        R.stale = true
    else
        _scatter!(R)
    end
    return R
end

"""Write the flat coarse vectors into the coarse program's nodes and edges."""
function _scatter!(R::ReducedProgram)
    Pc = getfield(R, :program)
    qc, cc, bnc, bec = R.qc, R.cc, R.bnc, R.bec
    row = 0
    @inbounds for (b, nd) in enumerate(Pc.nodes)
        o = Pc.offsets[b]
        for k in eachindex(nd.q)
            nd.q[k] = qc[o+k]
        end
        nd.c = cc[b]
        for k in eachindex(nd.b)
            nd.b[k] = bnc[row+k]
        end
        row += length(nd.b)
    end
    @inbounds for (k, E) in enumerate(Pc.edges)
        o = Pc.edge_offsets[k]
        for a in eachindex(E.b)
            E.b[a] = bec[o+a]
        end
    end
    R.stale = false
    return R
end

"""A reduction of a reduction reads its parent's flat vectors, so the parent writes its program only when it is read."""
function _link!(R::ReducedProgram)
    par = R.parent
    par isa ReducedProgram || return R
    R.fd = FlatData(par.qc, 0.0, par.bnc, par.bec)
    R.shared = true
    par.lazy = true
    return R
end

"""
    update_matrices!(reduced, verts) -> blocks

After the constraint matrices of the fine vertices `verts` changed in place
(on their sparsity patterns, as `set_state_set!` does), recompute what depends
on them: the stacked fine constraint matrix behind the right-hand sides
`b - A xbar`, and the coarse constraint matrix `A_B N_B` of every block that
holds one of them (the fibers do not depend on node constraints, so nothing
else changes). Returns the coarse vertices whose matrices changed; call
`update!(reduced)` afterwards for the vectors. Coarse programs that share
their matrices with this one (`reduce(...; reuse)` when nothing structural
changed) see the change too.
"""
function update_matrices!(R::ReducedProgram, verts)
    P, Pc = R.fine, R.program
    isempty(verts) && return Int[]
    _refresh_node_rows!(R.An, P, verts)
    blocks = sort!(unique(R.vertex_block[v] for v in verts))
    for b in blocks
        F = R.fibers[b]
        AI = Int[]; AJ = Int[]; AV = Float64[]
        arow = 0
        for (l, v) in enumerate(F.members)
            nd = P.nodes[v]
            isempty(nd.b) && continue
            _push_block!(AI, AJ, AV, arow, F.offsets[l], nd.A, 1.0)
            arow += length(nd.b)
        end
        AB = sparse(AI, AJ, AV, arow, length(F))
        _copy_values!(Pc.nodes[b].A, AB * F.N)
    end
    return blocks
end

"""
    lift(reduced, y) -> x

The lift `x = xbar + N y` of a coarse cochain to the program `reduced` was
reduced from; for teams of teams, `lift(reduced, y; to = :root)` (the
default) lifts through every level to the finest program, `to = :parent` one
level only. A lifted plan satisfies every contracted edge and has the coarse
objective value (Thm. 1).
"""
function lift(R::ReducedProgram, y::AbstractVector; to::Symbol = :root)
    x = R.xbar + R.N * y
    (to == :parent || !(R.parent isa ReducedProgram)) && return x
    return lift(R.parent, x; to = to)
end

"""In-place one-level lift `x = xbar + N y`."""
function lift!(x::AbstractVector, R::ReducedProgram, y::AbstractVector)
    copyto!(x, R.xbar)
    mul!(x, R.N, y, 1.0, 1.0)
    return x
end

"""
    restrict(reduced, x) -> y
    restrict!(y, reduced, x) -> y

The inverse of the lift on its image: the coarse coordinates of a fine plan
that satisfies every contracted edge (least squares per block, so for any
other plan the coordinates of the nearest lifted plan, block by block). The
factorization of every fiber's basis is computed on the first call and kept
(the fibers do not change between receding-horizon steps), so later calls cost
one triangular solve per block.
"""
restrict(R::ReducedProgram, x::AbstractVector) = restrict!(zeros(R.coarse_offsets[end]), R, x)

function restrict!(y::AbstractVector, R::ReducedProgram, x::AbstractVector)
    P = R.fine
    length(x) == c0dim(P) || throw(DimensionMismatch("x must have $(c0dim(P)) entries"))
    length(y) == R.coarse_offsets[end] || throw(DimensionMismatch("y must have $(R.coarse_offsets[end]) entries"))
    if length(R.rfac) != length(R.fibers)
        R.rfac = Any[F.kind in (:identity, :orthonormal) || fiberdim(F) == 0 ? nothing : qr(F.N) for F in R.fibers]
    end
    r = R.rbuf
    @inbounds for j in eachindex(r)
        r[j] = x[j] - R.xbar[j]
    end
    for (b, F) in enumerate(R.fibers)
        cols = (R.coarse_offsets[b]+1):R.coarse_offsets[b+1]
        isempty(cols) && continue
        rb = Vector{Float64}(undef, length(F))
        @inbounds for (l, v) in enumerate(F.members)
            o = F.offsets[l]
            for (k, j) in enumerate(vrange(P, v))
                rb[o+k] = r[j]
            end
        end
        fq = R.rfac[b]
        if fq === nothing
            mul!(view(y, cols), transpose(F.N), rb)
        else
            copyto!(view(y, cols), fq \ rb)
        end
    end
    return y
end

"""The chain of reductions from the finest program to `R` (finest first)."""
function reduction_chain(R::ReducedProgram)
    chain = ReducedProgram[R]
    while chain[1].parent isa ReducedProgram
        pushfirst!(chain, chain[1].parent)
    end
    return chain
end

"""The finest program a reduction (or a chain of them) starts from."""
root_program(R::ReducedProgram) = reduction_chain(R)[1].fine

"""
    composite_partition(R) -> (labels, collapsed, edge_map, row_map)

The reduction `R` (possibly a chain) seen as one pushforward of the finest
program (Thm. 4): block labels of the finest vertices, the finest edges it
contracts, the finest edge behind every coarse edge, and the finest node row
behind every coarse node row.
"""
function composite_partition(R::ReducedProgram)
    chain = reduction_chain(R)
    labels = copy(chain[1].partition)
    edge_map = copy(chain[1].cross)
    row_map = copy(chain[1].rowmap)
    for k in 2:length(chain)
        Rk = chain[k]
        labels = [Rk.partition[l] for l in labels]
        edge_map = edge_map[Rk.cross]
        row_map = row_map[Rk.rowmap]
    end
    P0 = chain[1].fine
    collapsed = [e for (e, E) in enumerate(P0.edges) if labels[E.tail] == labels[E.head]]
    return labels, collapsed, edge_map, row_map
end
