# reduction.jl: the reduction of a graph program along a vertex partition
#, its lift, and partition utilities.
#
# A partition Pi of the vertices defines the quotient graph map
# q_Pi : X -> X/Pi: one coarse vertex per block, the edges inside a block
# collapse, every other edge maps to its own coarse edge (a multigraph). The
# reduced program lives on X/Pi. The space of a coarse vertex is the space
# of vectors on the block's fine vertices that satisfy every internal edge
# exactly; the affine version of that space
# (internal targets b_e instead of 0) is the block's "affine fibre"
# A = xbar + range(N). Writing each block's fine variables as xbar + N y turns
# the fine program restricted to "collapsed edges hard" into a program in the
# coarse coordinates y.
#
# Cost: vertices and edges are bucketed by block in one pass each, and each block
# does linear algebra on its own members and internal edges only; each coarse
# edge touches the two blocks it joins. The total work is linear in the number
# of cells for bounded block sizes. The orthonormal and rref bases are dense per
# block (cubic in the block's space dimension); the structured basis
# (`basis = :structured`) solves the block by forward substitution along its
# dynamics and agreement edges and stays sparse.

# ---------------------------------------------------------------------------
# Partitions
# ---------------------------------------------------------------------------

"""
    canonical_partition(labels)

Relabel block labels by order of first appearance, so the blocks are `1:k` and
block `b` is the `b`-th distinct label met when scanning vertices in order.
"""
function canonical_partition(labels::AbstractVector{<:Integer})
    map = Dict{Int,Int}()
    out = Vector{Int}(undef, length(labels))
    for (v, l) in enumerate(labels)
        out[v] = get!(map, Int(l), length(map) + 1)
    end
    return out
end

nblocks(Pi::AbstractVector{<:Integer}) = isempty(Pi) ? 0 : maximum(Pi)

"""Members of each block of a canonical partition, in ascending vertex order (counting sort)."""
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

"""`Pi <= Pi2` in the refinement order: every block of `Pi` lies in a block of `Pi2`."""
function is_refinement(Pi::AbstractVector{<:Integer}, Pi2::AbstractVector{<:Integer})
    length(Pi) == length(Pi2) || return false
    img = Dict{Int,Int}()
    for v in eachindex(Pi)
        b2 = get!(img, Pi[v], Pi2[v])
        b2 == Pi2[v] || return false
    end
    return true
end

"""Meet (coarsest common refinement): blocks are the nonempty intersections."""
function partition_meet(Pi, Pi2)
    d = Dict{Tuple{Int,Int},Int}()
    return [get!(d, (Int(Pi[v]), Int(Pi2[v])), length(d) + 1) for v in eachindex(Pi)]
end

# union-find
function _find!(parent::Vector{Int}, a::Int)
    while parent[a] != a
        parent[a] = parent[parent[a]]
        a = parent[a]
    end
    return a
end
function _union!(parent::Vector{Int}, a::Int, b::Int)
    ra, rb = _find!(parent, a), _find!(parent, b)
    ra == rb && return false
    parent[max(ra, rb)] = min(ra, rb)
    return true
end
_labels(parent) = canonical_partition([_find!(parent, v) for v in eachindex(parent)])

"""Join (finest common coarsening): the transitive closure of both relations."""
function partition_join(Pi, Pi2)
    n = length(Pi)
    parent = collect(1:n)
    for P in (Pi, Pi2)
        first = Dict{Int,Int}()
        for v in 1:n
            r = get!(first, P[v], v)
            _union!(parent, r, v)
        end
    end
    return _labels(parent)
end

"""
    induced_partition(Pi, Pi2)

For `Pi <= Pi2`, the partition of the coarse vertices of `X/Pi` (block ids of
`canonical_partition(Pi)`) that defines the unique graph map
`r : X/Pi -> X/Pi2` with `q_{Pi2} = r o q_Pi`.
"""
function induced_partition(Pi::AbstractVector{<:Integer}, Pi2::AbstractVector{<:Integer})
    Pc = canonical_partition(Pi)
    r = zeros(Int, nblocks(Pc))
    for v in eachindex(Pc)
        b = Pc[v]
        if r[b] == 0
            r[b] = Pi2[v]
        elseif r[b] != Pi2[v]
            throw(ArgumentError("induced_partition: Pi is not a refinement of Pi2"))
        end
    end
    return canonical_partition(r)
end

"""Pull a partition of the coarse vertices of `X/Pi` back to the fine vertices."""
function pullback_partition(Pi::AbstractVector{<:Integer}, r::AbstractVector{<:Integer})
    Pc = canonical_partition(Pi)
    return canonical_partition([r[Pc[v]] for v in eachindex(Pc)])
end

"""`E_Pi`: the edges whose two endpoints lie in the same block (the collapsed edges)."""
collapsed_edges(P::GraphProgram, Pi::AbstractVector{<:Integer}) =
    [e for (e, E) in enumerate(P.edges) if Pi[E.tail] == Pi[E.head]]

"""True when every block induces a connected subgraph of the program's graph."""
function blocks_connected(P::GraphProgram, Pi::AbstractVector{<:Integer})
    parent = collect(1:nvertices(P))
    for E in P.edges
        Pi[E.tail] == Pi[E.head] && _union!(parent, E.tail, E.head)
    end
    root_of_block = Dict{Int,Int}()
    for v in 1:nvertices(P)
        r = _find!(parent, v)
        get!(root_of_block, Pi[v], r) == r || return false
    end
    return true
end

"""Contract each edge independently with probability `p` (blocks are connected)."""
function random_contraction(P::GraphProgram, rng::AbstractRNG; p::Real = 0.3,
                            edge_filter = e -> true)
    parent = collect(1:nvertices(P))
    for (e, E) in enumerate(P.edges)
        edge_filter(e) || continue
        rand(rng) < p && _union!(parent, E.tail, E.head)
    end
    return _labels(parent)
end

"""
    random_coarsening(P, Pi, rng; p = 0.3, jumps = 0)

A random `Pi2 >= Pi`: merge the two blocks of each cross edge with probability
`p`, then merge `jumps` random pairs of blocks (possibly non-adjacent).
"""
function random_coarsening(P::GraphProgram, Pi::AbstractVector{<:Integer}, rng::AbstractRNG;
                           p::Real = 0.3, jumps::Integer = 0)
    Pc = canonical_partition(Pi)
    nb = nblocks(Pc)
    parent = collect(1:nb)
    for E in P.edges
        a, b = Pc[E.tail], Pc[E.head]
        a != b && rand(rng) < p && _union!(parent, a, b)
    end
    for _ in 1:jumps
        nb > 1 && _union!(parent, rand(rng, 1:nb), rand(rng, 1:nb))
    end
    r = _labels(parent)
    return canonical_partition([r[Pc[v]] for v in eachindex(Pc)])
end

"""
    random_maximal_chain(P, rng; adjacent_bias = 0.9)

A maximal chain `bottom = Pi_0 < Pi_1 < ... < Pi_{|V|-1} = top` of the
partition lattice: each step merges two blocks (a covering relation). With
probability `adjacent_bias` the two blocks are the ends of a random cross edge
(so an edge collapses), otherwise two random blocks.
"""
function random_maximal_chain(P::GraphProgram, rng::AbstractRNG; adjacent_bias::Real = 0.9)
    nv = nvertices(P)
    parent = collect(1:nv)
    chain = [collect(1:nv)]
    nb = nv
    while nb > 1
        merged = false
        if rand(rng) < adjacent_bias
            cross = [e for (e, E) in enumerate(P.edges)
                     if _find!(parent, E.tail) != _find!(parent, E.head)]
            if !isempty(cross)
                E = P.edges[rand(rng, cross)]
                merged = _union!(parent, E.tail, E.head)
            end
        end
        while !merged
            merged = _union!(parent, rand(rng, 1:nv), rand(rng, 1:nv))
        end
        nb -= 1
        push!(chain, _labels(parent))
    end
    return chain
end

# ---------------------------------------------------------------------------
# Fibres
# ---------------------------------------------------------------------------

"""
    FibreBlock

One block `B` of the partition (one coarse vertex `v'`): its fine `members`, the
internal (collapsed) edges `E_{v'}`, the stacked internal edge operator system
`D x = r`, a particular solution `xbar` of it, and a basis `N` of `ker D` (the
section space of the fibre, the coarse space). `offsets[l]+1:offsets[l+1]` are
the rows of member `l` inside the block's stacked space. `kind` is the basis
the block got: `:identity` (no internal edge), `:orthonormal`, `:rref`,
`:structured` (forward substitution),
`:structured_reduced` (forward substitution, then the leftover rows imposed on
its coordinates by a small SVD); `N` is sparse for the structured kinds.
"""
struct FibreBlock
    members::Vector{Int}
    offsets::Vector{Int}
    internal::Vector{Int}
    xbar::Vector{Float64}
    N::Union{Matrix{Float64},SpMat}
    rank::Int
    consistency::Float64     # ||D xbar - r||_inf, the affine fibre is empty when large
    rhs_norm::Float64        # ||r||_inf
    sigma_kept::Float64      # smallest singular value counted in the rank (Inf if none)
    sigma_dropped::Float64   # largest singular value counted as zero (0 if none)
    kind::Symbol
end

"""
    ResolutionLift

Everything the reduction along a partition produces besides the coarse
program: the lift `iota(y) = xbar + N y` (global `xbar` and sparse block
diagonal `N`), the fibres, `E_phi` (`collapsed`), and the fine edge behind each
coarse edge (`coarse_edges[k]`). `feasible == false` means some affine fibre is
empty (`empty_block` names the first one); then the coarse program is `nothing`.
"""
struct ResolutionLift
    feasible::Bool
    basis::Symbol
    partition::Vector{Int}
    local_index::Vector{Int}
    blocks::Vector{FibreBlock}
    collapsed::Vector{Int}
    coarse_edges::Vector{Int}
    coarse_offsets::Vector{Int}
    fine_dim::Int
    xbar::Vector{Float64}
    N::SpMat
    empty_block::Int
    fine_offsets::Vector{Int}
end

"""The entries of the fine vector `x` on the members of block `B`, stacked in the block's order."""
_block_rows(L::ResolutionLift, B, x::AbstractVector) =
    reduce(vcat, (x[(L.fine_offsets[v]+1):L.fine_offsets[v+1]] for v in B.members); init = Float64[])

"""An affine injection `y -> xbar + N y` (used for composed lifts)."""
struct AffineLift
    xbar::Vector{Float64}
    N::SpMat
end

AffineLift(L::ResolutionLift) = AffineLift(L.xbar, L.N)

"""`iota(y) = xbar + N y`."""
lift(L::Union{ResolutionLift,AffineLift}, y::AbstractVector) = L.xbar + L.N * y

"""
    restrict(L, x)

The inverse of the lift on its image: `y = N'(x - xbar)` for an orthonormal
basis (THEORY Thm 2.4 (ii)), least squares otherwise. With `basis =
:structured` it works block by block (`N` is block diagonal): `N_B'` on the
blocks that fell back to the orthonormal basis, a sparse least squares solve on
the others.
"""
function restrict(L::ResolutionLift, x::AbstractVector)
    if L.basis == :orthonormal
        return L.N' * (x - L.xbar)
    elseif L.basis == :structured
        r = x - L.xbar
        y = zeros(L.coarse_offsets[end])
        for (b, B) in enumerate(L.blocks)
            cols = (L.coarse_offsets[b]+1):L.coarse_offsets[b+1]
            isempty(cols) && continue
            rb = _block_rows(L, B, r)
            y[cols] = B.kind in (:orthonormal, :identity) ? B.N' * rb : (B.N isa SpMat ? qr(B.N) \ rb : B.N \ rb)
        end
        return y
    else
        return Matrix(L.N) \ (x - L.xbar)
    end
end
restrict(L::AffineLift, x::AbstractVector) = Matrix(L.N) \ (x - L.xbar)

"""`iota_1 o iota_2`: the lift of a two-step reduction, `x = xbar1 + N1 (xbar2 + N2 z)`."""
compose(L1::Union{ResolutionLift,AffineLift}, L2::Union{ResolutionLift,AffineLift}) =
    AffineLift(L1.xbar + L1.N * L2.xbar, SpMat(L1.N * L2.N))

"""
    rref_nullspace(D, r; tol)

Gauss-Jordan elimination with pivot columns taken left to right: returns the
particular solution with free variables zero and the textbook null space basis
(identity on the free variables, `-R` on the pivots). Not orthonormal; this is
the control basis of THEORY Thm 2.9 (`[x-bar ; rref]`).
"""
function rref_nullspace(D::Matrix{Float64}, r::Vector{Float64}; tol::Real = 0.0)
    m, n = size(D)
    R = [D r]
    tol = tol > 0 ? tol : max(m, n) * eps() * max(1.0, maximum(abs, D; init = 0.0))
    pivots = Int[]
    row = 1
    for col in 1:n
        row > m && break
        p = row - 1 + argmax(abs.(view(R, row:m, col)))
        abs(R[p, col]) <= tol && continue
        if p != row
            R[[row, p], :] = R[[p, row], :]
        end
        R[row, :] ./= R[row, col]
        for i in 1:m
            i == row && continue
            f = R[i, col]
            f != 0 && (R[i, :] .-= f .* R[row, :])
        end
        push!(pivots, col)
        row += 1
    end
    rk = length(pivots)
    free = setdiff(1:n, pivots)
    N = zeros(n, length(free))
    for (k, f) in enumerate(free)
        N[f, k] = 1.0
        for (pi, pc) in enumerate(pivots)
            N[pc, k] = -R[pi, f]
        end
    end
    xbar = zeros(n)
    for (pi, pc) in enumerate(pivots)
        xbar[pc] = R[pi, n+1]
    end
    return xbar, N, rk
end

# ---------------------------------------------------------------------------
# The structured fibre basis
# ---------------------------------------------------------------------------
#
# Every contracted fibre of the paper's programs is a ladder: time chains of
# dynamics edges (x_{t+1} = A x_t + B u_t + c, the identity on x_{t+1}) and, in
# a team block, agreement edges between the chains (C x_{j,t} - C x_{i,t} = b).
# `basis = :structured` solves such a fibre in two passes, never forming the
# dense internal edge operator:
#
# 1. Forward substitution along a spanning forest of the block's dynamics edges
#    (of all its internal edges when it has none): the root of each tree is
#    free, and each tree edge solves for the newly reached vertex on a square
#    invertible block of its edge map (the identity on x_{t+1}, or on the
#    planar position of an agreement edge); the other coordinates (u_t) are new
#    free coordinates. On a time chain this is classical condensing,
#    x_t = Phi_t x_0 + Gam_t U + g_t.
# 2. The other edges between two trees, stacked per pair of trees, are affine
#    constraints G_b z_b - G_a z_a = g on the trees' coordinates. Along a
#    spanning tree of the trees: if G_a = G_b = M (identical members),
#    z_b = z_a + M^+ g + K w_b with K an orthonormal basis of ker M; otherwise,
#    if G_b has full row rank, z_b = G_b^+ (g + G_a z_a) + K_b w_b. One small SVD
#    per distinct matrix (cached), so the work does not grow with the number of
#    identical members.
#
# The edges left over (cycles of the team graph, non-tree edges inside a tree)
# hold identically on this parametrization whenever the agreement maps along
# each cycle cancel (identical members, or members whose stacked agreement maps
# have full row rank). When they do not, they are imposed on the coordinates by
# one SVD of the leftover rows (kind `:structured_reduced`). A final sparse
# check D N = 0 guards the result; on failure the block falls back to the dense
# orthonormal basis.

"""
Columns `S` on which the edge map `F` (`d x n`) is square and
invertible, and the factorized block `F[:, S]`; `nothing` if there are none.
Unit columns (one nonzero) covering every row are preferred, so the identity
blocks of dynamics and agreement maps are used exactly.
"""
function _solve_columns(F::SpMat)
    d, nv = size(F)
    d == 0 && return Int[], nothing
    d > nv && return nothing
    rows = rowvals(F); vals = nonzeros(F)
    S = zeros(Int, d)
    for c in 1:nv
        rg = nzrange(F, c)
        (length(rg) == 1 && vals[first(rg)] != 0) || continue
        r = rows[first(rg)]
        S[r] == 0 && (S[r] = c)
    end
    all(>(0), S) && return S, Diagonal([F[r, S[r]] for r in 1:d])
    Fd = Matrix(F)
    q = qr(Fd, ColumnNorm())
    Rd = abs.(diag(q.R))
    (length(Rd) >= d && Rd[d] > 1e-10 * Rd[1]) || return nothing
    S = sort(q.p[1:d])
    return S, lu(Fd[:, S])
end

"""Pseudo-inverse, orthonormal kernel basis and rank of a small dense matrix, cached by value."""
function _small_svd!(cache::Dict{Matrix{Float64},Any}, G::Matrix{Float64})
    get!(cache, G) do
        m, k = size(G)
        m == 0 && return (zeros(k, 0), Matrix{Float64}(I, k, k), 0)
        F = svd(G; full = true)
        smax = isempty(F.S) ? 0.0 : F.S[1]
        rk = count(>(max(m, k) * eps() * smax), F.S)
        pinvG = F.V[:, 1:rk] * Diagonal(1 ./ F.S[1:rk]) * F.U[:, 1:rk]'
        return (pinvG, F.V[:, (rk+1):k], rk)
    end
end

"""Sparse internal edge operator `D` (rows of `internal`, columns of the block's stacked space) and its targets `r`."""
function _internal_edge_operator(P::GraphProgram, internal::Vector{Int}, local_index::Vector{Int}, offs::Vector{Int})
    I_ = Int[]; J_ = Int[]; V_ = Float64[]; r = Float64[]
    row = 0
    for e in internal
        E = P.edges[e]
        _push_block!(I_, J_, V_, row, offs[local_index[E.tail]], E.Ft, -1.0)
        _push_block!(I_, J_, V_, row, offs[local_index[E.head]], E.Fh, 1.0)
        append!(r, E.b)
        row += edgedim(E)
    end
    return sparse(I_, J_, V_, row, offs[end]), r
end

"""
The stacked constraints of the edges `es` between tree `a` (parametrized) and
tree `b` (new), oriented as `Gb z_b - Ga z_a = g`.
"""
function _pair_constraint(P, es, b, comp, local_index, xb, Nl, wa::Int, wb::Int)
    Gb = Matrix{Float64}[]; Ga = Matrix{Float64}[]; g = Float64[]
    for e in es
        E = P.edges[e]
        lt, lh = local_index[E.tail], local_index[E.head]
        Gh = Matrix(E.Fh * Nl[lh]); Gt = Matrix(E.Ft * Nl[lt])
        ge = E.b - E.Fh * xb[lh] + E.Ft * xb[lt]          # Gh z_head - Gt z_tail = ge
        if comp[lh] == b
            push!(Gb, Gh); push!(Ga, Gt); append!(g, ge)
        else
            push!(Gb, Gt); push!(Ga, Gh); append!(g, -ge)
        end
    end
    # the members of a tree see only the coordinates introduced before them: pad to the tree's width
    pad(M, w) = size(M, 2) == w ? M : [M zeros(size(M, 1), w - size(M, 2))]
    return reduce(vcat, (pad(M, wb) for M in Gb)), reduce(vcat, (pad(M, wa) for M in Ga)), g
end

function _structured_fibre(P::GraphProgram, members::Vector{Int}, internal::Vector{Int},
                           local_index::Vector{Int}, offs::Vector{Int}, D::SpMat, r::Vector{Float64})
    nm = length(members)
    n = offs[end]
    # pass 1: forward substitution along a spanning forest of the dynamics edges
    chain = [e for e in internal if P.edges[e].tag.kind == :dyn]
    isempty(chain) && (chain = internal)
    adj = [Tuple{Int,Int}[] for _ in 1:nm]
    for e in chain
        E = P.edges[e]
        a, b = local_index[E.tail], local_index[E.head]
        push!(adj[a], (e, b)); push!(adj[b], (e, a))
    end
    comp = zeros(Int, nm)
    xb = Vector{Vector{Float64}}(undef, nm)
    Nl = Vector{SpMat}(undef, nm)               # x_l = xb[l] + Nl[l] z_c, z_c the coordinates of tree c
    kc = Int[]
    tree = Set{Int}()
    for root in 1:nm
        comp[root] == 0 || continue
        d0 = P.dims[members[root]]
        push!(kc, d0)
        c = length(kc)
        comp[root] = c
        xb[root] = zeros(d0); Nl[root] = sparse(1.0I, d0, d0)
        queue = [root]
        while !isempty(queue)
            u = popfirst!(queue)
            for (e, v) in adj[u]
                comp[v] == 0 || continue
                E = P.edges[e]
                # solve F x_v = rb + Fo x_u for the new end v
                F, Fo, rb = local_index[E.head] == v ? (E.Fh, E.Ft, E.b) : (E.Ft, E.Fh, -E.b)
                piv = _solve_columns(F)
                piv === nothing && return nothing
                S, FS = piv
                dv = P.dims[members[v]]
                Sc = setdiff(1:dv, S)
                k0 = kc[c]
                f = length(Sc)
                kc[c] += f
                X = zeros(dv)
                # rows S: solved from the edge; rows Sc: new free coordinates k0+1:k0+f
                MS = spzeros(0, kc[c])
                if !isempty(S)
                    X[S] = FS \ (rb + Fo * xb[u])
                    FoN = Fo * Nl[u]
                    A1 = FS isa Diagonal ? FS \ FoN : sparse(FS \ Matrix(FoN))
                    A2 = FS isa Diagonal ? -(FS \ F[:, Sc]) : sparse(-(FS \ Matrix(F[:, Sc])))
                    MS = [A1 spzeros(length(S), k0 - size(FoN, 2)) A2]
                end
                MSc = [spzeros(f, k0) sparse(1.0I, f, f)]
                comp[v] = c; xb[v] = X; Nl[v] = SpMat([MS; MSc][invperm([S; Sc]), :])
                push!(tree, e); push!(queue, v)
            end
        end
    end
    nc = length(kc)
    # pass 2: the edges between trees, solved along a spanning tree of the trees
    groups = Dict{Tuple{Int,Int},Vector{Int}}()
    for e in internal
        e in tree && continue
        ca, cb = comp[local_index[P.edges[e].tail]], comp[local_index[P.edges[e].head]]
        ca == cb || push!(get!(groups, minmax(ca, cb), Int[]), e)
    end
    cadj = [Int[] for _ in 1:nc]
    for (a, b) in keys(groups)
        push!(cadj[a], b); push!(cadj[b], a)
    end
    foreach(sort!, cadj)
    z0 = Vector{Vector{Float64}}(undef, nc)
    T = Vector{SpMat}(undef, nc)                 # z_c = z0[c] + T[c] zeta, zeta the block's coordinates
    seen = falses(nc)
    cache = Dict{Matrix{Float64},Any}()
    ncol = 0
    for root in 1:nc
        seen[root] && continue
        seen[root] = true
        z0[root] = zeros(kc[root])
        T[root] = [spzeros(kc[root], ncol) sparse(1.0I, kc[root], kc[root])]
        ncol += kc[root]
        queue = [root]
        while !isempty(queue)
            a = popfirst!(queue)
            for b in cadj[a]
                seen[b] && continue
                Gb, Ga, g = _pair_constraint(P, groups[minmax(a, b)], b, comp, local_index, xb, Nl, kc[a], kc[b])
                if size(Ga) == size(Gb) && norm(Ga - Gb, Inf) <= 1e-12 * max(1.0, norm(Gb, Inf))
                    pinvG, K, _ = _small_svd!(cache, Gb)
                    zb = z0[a] + pinvG * g
                    Tb = T[a]
                else
                    pinvG, K, rk = _small_svd!(cache, Gb)
                    rk == size(Gb, 1) || continue            # left to the leftover check
                    zb = pinvG * (g + Ga * z0[a])
                    Tb = sparse(pinvG * (Ga * T[a]))
                end
                z0[b] = zb
                T[b] = [Tb spzeros(size(Tb, 1), ncol - size(Tb, 2)) sparse(K)]
                ncol += size(K, 2)
                seen[b] = true
                push!(queue, b)
            end
        end
    end
    # assemble x = xbar + N zeta over the block
    xbar = zeros(n)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for l in 1:nm
        c = comp[l]
        w = size(Nl[l], 2)
        lr = (offs[l]+1):offs[l+1]
        xbar[lr] = xb[l] + Nl[l] * z0[c][1:w]
        NT = (w == kc[c] ? Nl[l] : [Nl[l] spzeros(size(Nl[l], 1), kc[c] - w)]) * T[c]
        ii, jj, vv = findnz(NT)
        append!(I_, offs[l] .+ ii); append!(J_, jj); append!(V_, vv)
    end
    N = dropzeros!(sparse(I_, J_, V_, n, ncol))
    # the leftover rows: zero on the parametrization, or imposed on its coordinates
    kind = :structured
    scale = max(1.0, maximum(abs, nonzeros(D); init = 0.0)) * max(1.0, maximum(abs, nonzeros(N); init = 0.0))
    tol = 1e-11 * scale
    R = D * N
    if maximum(abs, nonzeros(R); init = 0.0) > tol
        # rows that vanish on the parametrization (to rounding) are dropped, not ranked
        Rd = Matrix(R)
        keep = [i for i in axes(Rd, 1) if maximum(abs, view(Rd, i, :)) > tol]
        Rd = Rd[keep, :]
        s = (r - D * xbar)[keep]
        F = svd(Rd; full = true)
        smax = isempty(F.S) ? 0.0 : F.S[1]
        rk = count(>(max(tol, max(size(Rd)...) * eps() * smax)), F.S)
        zeta0 = F.V[:, 1:rk] * ((F.U[:, 1:rk]' * s) ./ F.S[1:rk])
        xbar += N * zeta0
        N = sparse(N * F.V[:, (rk+1):end])
        kind = :structured_reduced
        R = D * N
        maximum(abs, nonzeros(R); init = 0.0) <= tol || return nothing
    end
    cons = isempty(r) ? 0.0 : maximum(abs, D * xbar - r)
    return FibreBlock(members, offs, internal, xbar, N, n - size(N, 2), cons,
                      isempty(r) ? 0.0 : maximum(abs, r), NaN, NaN, kind)
end

function _fibre_block(P::GraphProgram, members::Vector{Int}, internal::Vector{Int},
                      local_index::Vector{Int}, basis::Symbol)
    offs = zeros(Int, length(members) + 1)
    for (l, v) in enumerate(members)
        offs[l+1] = offs[l] + P.dims[v]
    end
    n = offs[end]
    m = edgedims(P, internal)
    if m == 0
        # no internal constraint: the section space is the whole space and the
        # identity is an orthonormal basis (and is exact in floating point)
        Id = basis == :structured ? SpMat(sparse(1.0I, n, n)) : Matrix{Float64}(I, n, n)
        return FibreBlock(members, offs, internal, zeros(n), Id, 0, 0.0, 0.0, Inf, 0.0, :identity)
    end
    if basis == :structured
        Ds, rs = _internal_edge_operator(P, internal, local_index, offs)
        B = _structured_fibre(P, members, internal, local_index, offs, Ds, rs)
        B === nothing || return B
        basis = :orthonormal                                  # the fallback
    end
    D = zeros(m, n)
    r = zeros(m)
    row = 0
    for e in internal
        E = P.edges[e]
        d = edgedim(E)
        lt, lh = local_index[E.tail], local_index[E.head]
        rows = (row+1):(row+d)
        D[rows, (offs[lt]+1):offs[lt+1]] .-= Matrix(E.Ft)
        D[rows, (offs[lh]+1):offs[lh+1]] .+= Matrix(E.Fh)
        r[rows] .= E.b
        row += d
    end
    if basis == :orthonormal
        F = svd(D; full = true)
        S = F.S
        smax = isempty(S) ? 0.0 : S[1]
        tol = max(m, n) * eps() * smax
        rk = count(>(tol), S)
        V = F.V
        U = F.U
        xbar = V[:, 1:rk] * ((U[:, 1:rk]' * r) ./ S[1:rk])
        N = V[:, (rk+1):n]
        skept = rk > 0 ? S[rk] : Inf
        sdrop = rk < length(S) ? S[rk+1] : 0.0
    elseif basis == :rref
        xbar, N, rk = rref_nullspace(D, r)
        skept, sdrop = NaN, NaN
    else
        throw(ArgumentError("unknown basis $basis (use :orthonormal, :rref or :structured)"))
    end
    cons = isempty(r) ? 0.0 : maximum(abs, D * xbar - r)
    return FibreBlock(members, offs, internal, xbar, N, rk, cons,
                      isempty(r) ? 0.0 : maximum(abs, r), skept, sdrop, basis)
end

"""Rows of member vertex `v` inside its block's stacked space."""
_member_rows(B::FibreBlock, l::Int) = (B.offsets[l]+1):B.offsets[l+1]

"""
    coarsen(P, Pi; basis = :orthonormal, consistency_tol = 1e-8, reuse = nothing) -> (Pc, L)

THEORY Def 2.3 for the quotient map `q_Pi` of the partition `Pi` (a vector of
block labels, one per vertex of `P`):

* one coarse vertex per block, with space the section space of the block's
  fibre (coordinates `y`, basis `N`);
* coarse node cost and constraints by substitution `x = xbar + N y`;
* one coarse edge per non-collapsed fine edge, same type and weight, restriction
  maps `F N` and target `b - (delta xbar)_e`.

The fibre basis is orthonormal (dense SVD per block), `:rref` (dense
Gauss-Jordan, the control of Thm 2.9), or `:structured` (forward substitution
along the block's dynamics and agreement edges, sparse, not orthonormal; see
`_structured_fibre`). Thm 2.4 holds for any basis: the coarse value, the lifted
plans and the fibre dimensions do not depend on it.

`reuse = (Pprev, Lprev)`, a previous program and its reduction along the same
partition with the same basis (receding horizon), keeps every fibre whose
internal edges (endpoints, edge maps, targets) are unchanged and
recomputes only the coarse node data and coarse edges by substitution.

Returns the coarse `GraphProgram` (or `nothing` if some affine fibre is empty,
which makes `phi_* P` infeasible) and the `ResolutionLift`. An affine fibre is
declared empty when the particular solution leaves an internal residual above
`consistency_tol * max(1, ||b_internal||_inf)`.
"""
function coarsen(P::GraphProgram, Pi::AbstractVector{<:Integer};
                     basis::Symbol = :orthonormal, consistency_tol::Real = 1e-8, reuse = nothing)
    nv = nvertices(P)
    length(Pi) == nv || throw(DimensionMismatch("partition has $(length(Pi)) labels, program has $nv vertices"))
    Pc = canonical_partition(Pi)
    nb = nblocks(Pc)
    members = block_members(Pc)
    local_index = zeros(Int, nv)
    for mem in members, (l, v) in enumerate(mem)
        local_index[v] = l
    end
    # bucket the edges by block in one pass
    internal = [Int[] for _ in 1:nb]
    cross = Int[]
    for (e, E) in enumerate(P.edges)
        bt, bh = Pc[E.tail], Pc[E.head]
        bt == bh ? push!(internal[bt], e) : push!(cross, e)
    end
    collapsed = sort!(reduce(vcat, internal; init = Int[]))
    Pp, Lp = reuse === nothing ? (nothing, nothing) : reuse
    reusable = Lp !== nothing && Lp.basis == basis && Lp.partition == Pc && Pp.dims == P.dims &&
               nedges(Pp) == nedges(P)
    blocks = Vector{FibreBlock}(undef, nb)
    empty_block = 0
    for b in 1:nb
        if reusable && Lp.blocks[b].internal == internal[b] && _same_edges(P, Pp, internal[b])
            blocks[b] = Lp.blocks[b]
        else
            blocks[b] = _fibre_block(P, members[b], internal[b], local_index, basis)
        end
        B = blocks[b]
        if empty_block == 0 && B.consistency > consistency_tol * max(1.0, B.rhs_norm)
            empty_block = b
        end
    end
    kdims = [size(B.N, 2) for B in blocks]
    coarse_offsets = [0; cumsum(kdims)]
    # global lift
    xbar = zeros(c0dim(P))
    I = Int[]; J = Int[]; V = Float64[]
    for b in 1:nb
        B = blocks[b]
        rowmap = Vector{Int}(undef, B.offsets[end])
        for (l, v) in enumerate(B.members)
            lr = _member_rows(B, l)
            xbar[vrange(P, v)] .= view(B.xbar, lr)
            rowmap[lr] .= vrange(P, v)
        end
        Nb = B.N isa SpMat ? B.N : sparse(B.N)
        rv = rowvals(Nb); nzv = nonzeros(Nb)
        for jj in 1:size(Nb, 2), p in nzrange(Nb, jj)
            nzv[p] != 0 && (push!(I, rowmap[rv[p]]); push!(J, coarse_offsets[b] + jj); push!(V, nzv[p]))
        end
    end
    Ng = sparse(I, J, V, c0dim(P), coarse_offsets[end])
    L = ResolutionLift(empty_block == 0, basis, Pc, local_index, blocks, collapsed, cross,
                       coarse_offsets, c0dim(P), xbar, Ng, empty_block, copy(P.offsets))
    empty_block == 0 || return nothing, L
    # rows of a sparse basis are read through its transpose (column slices of a CSC matrix are cheap)
    Nt = [B.N isa SpMat ? SpMat(copy(transpose(B.N))) : nothing for B in blocks]
    member_basis(b, lr) = Nt[b] === nothing ? blocks[b].N[lr, :] : SpMat(transpose(Nt[b][:, lr]))
    # coarse node data by substitution
    cnodes = Vector{NodeData}(undef, nb)
    for b in 1:nb
        B = blocks[b]
        k = kdims[b]
        if B.N isa SpMat
            cnodes[b] = _substitute_sparse(P, B)
            continue
        end
        Qc = zeros(k, k); qc = zeros(k); cc = 0.0
        Ablocks = Matrix{Float64}[]; bc = Float64[]; cones = ConeBlock[]
        for (l, v) in enumerate(B.members)
            nd = P.nodes[v]
            lr = _member_rows(B, l)
            Nv = member_basis(b, lr)
            xv = B.xbar[lr]
            QN = nd.Q * Nv
            Qc .+= Nv' * QN
            Qx = nd.Q * xv
            qc .+= Nv' * (Qx + nd.q)
            cc += 0.5 * dot(xv, Qx) + dot(nd.q, xv) + nd.c
            if !isempty(nd.b)
                push!(Ablocks, Matrix(nd.A * Nv))
                append!(bc, nd.b - nd.A * xv)
                append!(cones, nd.cones)
            end
        end
        Qc = (Qc + Qc') / 2
        Ac = isempty(Ablocks) ? zeros(0, k) : reduce(vcat, Ablocks)
        cnodes[b] = NodeData(Qc, qc, cc, Ac, bc, cones)
    end
    # one coarse edge per non-collapsed fine edge
    cedges = Vector{GraphEdge}(undef, length(cross))
    for (k, e) in enumerate(cross)
        E = P.edges[e]
        bt, bh = Pc[E.tail], Pc[E.head]
        Bt, Bh = blocks[bt], blocks[bh]
        lt, lh = _member_rows(Bt, local_index[E.tail]), _member_rows(Bh, local_index[E.head])
        Ftc = E.Ft * member_basis(bt, lt)
        Fhc = E.Fh * member_basis(bh, lh)
        bcoarse = E.b - (E.Fh * Bh.xbar[lh] - E.Ft * Bt.xbar[lt])
        cedges[k] = GraphEdge(bt, bh, Ftc, Fhc, E.hard, E.W, bcoarse, E.tag)
    end
    return GraphProgram(cnodes, cedges), L
end

"""Coarse node data of a block with a sparse basis: one sparse product over the whole block."""
function _substitute_sparse(P::GraphProgram, B::FibreBlock)
    nds = [P.nodes[v] for v in B.members]
    QB = blockdiag((nd.Q for nd in nds)...)
    qB = reduce(vcat, (nd.q for nd in nds))
    QN = QB * B.N
    Qc = B.N' * QN
    Qx = QB * B.xbar
    qc = Vector(B.N' * (Qx + qB))
    cc = 0.5 * dot(B.xbar, Qx) + dot(qB, B.xbar) + sum(nd.c for nd in nds)
    AB = blockdiag((nd.A for nd in nds)...)
    Ac = AB * B.N
    bc = reduce(vcat, (nd.b for nd in nds); init = Float64[]) - AB * B.xbar
    cones = reduce(vcat, (nd.cones for nd in nds); init = ConeBlock[])
    return NodeData((Qc + Qc') / 2, qc, cc, Ac, bc, cones)
end

"""True when the edges `es` have the same endpoints, edge maps and targets in `P` and `Pp`."""
_same_edges(P::GraphProgram, Pp::GraphProgram, es) =
    all(e -> (E = P.edges[e]; F = Pp.edges[e];
              E.tail == F.tail && E.head == F.head && E.Ft == F.Ft && E.Fh == F.Fh && E.b == F.b), es)

"""
    coarsen_two_step(P, Pi, Pi2; kwargs...) -> (P2, L12, P1, L1, L2)

`r_* (q_Pi)_* P` for `Pi <= Pi2`, with the composed lift `iota_{Pi} o iota_r`
.
"""
function coarsen_two_step(P::GraphProgram, Pi, Pi2; kwargs...)
    P1, L1 = coarsen(P, Pi; kwargs...)
    P1 === nothing && return nothing, nothing, nothing, L1, nothing
    r = induced_partition(Pi, Pi2)
    P2, L2 = coarsen(P1, r; kwargs...)
    P2 === nothing && return nothing, nothing, P1, L1, L2
    return P2, compose(L1, L2), P1, L1, L2
end

"""
    fibre_dims(L) -> NamedTuple

The counts of THEORY Prop 2.10 read off a reduction: coarse `dim C^0`,
coarse `dim C^1` (sum over non-collapsed edges), number of blocks, and the
rank of the internal edge operator summed over blocks.
"""
function fibre_dims(P::GraphProgram, L::ResolutionLift)
    return (c0 = L.coarse_offsets[end],
            c1 = edgedims(P, L.coarse_edges),
            nblocks = length(L.blocks),
            rank_internal = sum((B.rank for B in L.blocks); init = 0),
            collapsed_dim = edgedims(P, L.collapsed))
end
