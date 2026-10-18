# sheaf.jl: a sheaf program as a conic QP.
#
# A sheaf program on a graph (Hansen and Ghrist 2019; the paper's Def 2.1) puts
# a convex quadratic cost f_v and a conic constraint set Omega_v on every vertex
# stalk, and on every edge e : u -> v either a hard constraint
# (delta x)_e = F_{v<|e} x_v - F_{u<|e} x_u = b_e or a soft spring with energy
# (1/2) ||(delta x)_e - b_e||^2_{W_e}. As a conic QP:
#
#   P = blockdiag(Q_v) + delta_s' W delta_s,   q = (q_v) - delta_s' W b_s,
#   c = sum c_v + (1/2) b_s' W b_s,
#
# rows: the hard edges first (equality rows, in edge order), then the node
# constraints of every vertex in vertex order (rows of `b_v - A_v x_v in K_v`).
# This is the row order of the paper's `solve_direct`, so the multipliers line
# up one to one.
#
# The program is read by its fields only (duck typing): `nodes` with fields
# `Q, q, c, A, b, cones` (each cone with `kind` named ZERO_CONE, NONNEG_CONE or
# SOC_CONE and `dim`), `edges` with `tail, head, Ft, Fh, hard, W, b`, and the
# stalk `offsets` (`offsets[v] + 1 : offsets[v + 1]` are the rows of x_v). Both a
# fine program and any of its pushforwards have this shape.

function _push_block!(I, J, V, r0::Int, c0::Int, M::SparseMatrixCSC, s::Float64)
    rows = rowvals(M); vals = nonzeros(M)
    for col in 1:size(M, 2), k in nzrange(M, col)
        push!(I, r0 + rows[k]); push!(J, c0 + col); push!(V, s * vals[k])
    end
end

_cone_symbol(kind) = (s = string(Symbol(kind)); s == "ZERO_CONE" ? :zero : s == "NONNEG_CONE" ? :nonneg :
                      s == "SOC_CONE" ? :soc : throw(ArgumentError("unknown cone kind $kind")))

"""
    sheaf_qp(prog; dedup = false) -> ConicQP

The conic QP of a sheaf program (fine or pushed forward): node costs, soft edges
as quadratic penalties, hard edges and node constraints as rows (hard edges
first). See the file header for the conventions. With `dedup = true` exact
duplicate constraints are dropped (`dedup_rows`); the rows then no longer map
one to one onto the program's edges and node cones.
"""
function sheaf_qp(prog; dedup::Bool = false)
    offs = prog.offsets
    n = offs[end]
    nodes = prog.nodes
    edges = prog.edges
    # objective: node blocks
    I = Int[]; J = Int[]; V = Float64[]
    q = zeros(n); c = 0.0
    for (v, nd) in enumerate(nodes)
        _push_block!(I, J, V, offs[v], offs[v], SpMat(sparse(nd.Q)), 1.0)
        q[(offs[v]+1):offs[v+1]] .+= nd.q
        c += nd.c
    end
    # soft edges: (1/2)||D x - b||_W^2 = (1/2) x'D'WDx - b'WDx + (1/2) b'Wb
    DI = Int[]; DJ = Int[]; DV = Float64[]
    WI = Int[]; WJ = Int[]; WV = Float64[]; bs = Float64[]
    row = 0
    for E in edges
        (E.hard || length(E.b) == 0) && continue
        d = length(E.b)
        _push_block!(DI, DJ, DV, row, offs[E.head], SpMat(sparse(E.Fh)), 1.0)
        _push_block!(DI, DJ, DV, row, offs[E.tail], SpMat(sparse(E.Ft)), -1.0)
        W = Matrix{Float64}(E.W)
        for jj in 1:d, ii in 1:d
            W[ii, jj] != 0 && (push!(WI, row + ii); push!(WJ, row + jj); push!(WV, W[ii, jj]))
        end
        append!(bs, E.b)
        row += d
    end
    P = sparse(I, J, V, n, n)
    if row > 0
        Ds = sparse(DI, DJ, DV, row, n)
        Ws = sparse(WI, WJ, WV, row, row)
        WD = Ws * Ds
        P = P + Ds' * WD
        q .-= Ds' * (Ws * bs)
        c += 0.5 * dot(bs, Ws * bs)
    end
    # rows: hard edges, then node constraints
    AI = Int[]; AJ = Int[]; AV = Float64[]; b = Float64[]
    cones = Tuple{Symbol,Int}[]
    row = 0
    nh = 0
    for E in edges
        (E.hard && length(E.b) > 0) || continue
        _push_block!(AI, AJ, AV, row, offs[E.head], SpMat(sparse(E.Fh)), 1.0)
        _push_block!(AI, AJ, AV, row, offs[E.tail], SpMat(sparse(E.Ft)), -1.0)
        append!(b, E.b)
        row += length(E.b); nh += length(E.b)
    end
    nh > 0 && push!(cones, (:zero, nh))
    for (v, nd) in enumerate(nodes)
        size(nd.A, 1) == 0 && continue
        _push_block!(AI, AJ, AV, row, offs[v], SpMat(sparse(nd.A)), 1.0)
        append!(b, nd.b)
        for cb in nd.cones
            cb.dim == 0 && continue
            k = _cone_symbol(cb.kind)
            if k != :soc && !isempty(cones) && cones[end][1] == k
                cones[end] = (k, cones[end][2] + cb.dim)       # merge runs of the same polyhedral cone
            else
                push!(cones, (k, cb.dim))
            end
        end
        row += size(nd.A, 1)
    end
    A = sparse(AI, AJ, AV, row, n)
    p = ConicQP(P, q, A, b, cones; c = c)
    return dedup ? dedup_rows(p)[1] : p
end
