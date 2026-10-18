# fiber.jl: the affine fiber of one block of a partition, A = xbar + range(N).
#
# A partition of the vertices contracts the edges inside each block. The stalk
# of the coarse vertex is the space of sections of the sheaf over the block's
# fiber: configurations of the block's vertices that satisfy every internal
# edge, D x = r with D the internal coboundary and r the internal targets. The
# affine version is xbar + range(N), N a basis of ker D. Here the particular
# solution is kept as a linear operator of the targets, xbar = X r, so a new
# target (a moved formation slot, a new drift) changes xbar by one sparse
# product and the basis N is reused.
#
# Three bases, any of which gives the same pushforward program up to an
# invertible change of coordinates (the lifted plans, values and fiber
# dimensions are basis independent):
#
# * `:identity` when the block has no internal row;
# * `:structured` (the default): forward substitution along a spanning forest
#   of the block's dynamics edges, which on a time chain is classical
#   condensing (x_t = Phi_t x_0 + Gam_t U + g_t), then the agreement edges
#   between chains solved along a spanning tree of the chains (one small SVD
#   per distinct matrix: identical team members share it). Sparse throughout.
#   Rows left over on cycles that do not hold identically are imposed by one
#   SVD of the leftover rows (kind `:structured_reduced`);
# * `:orthonormal`: a dense SVD of D, the fallback.

"""
    Fiber

The fiber of one block (one coarse vertex): its fine `members` (ascending),
the stalk `offsets` of the members inside the block, the `internal` (collapsed)
edges with row offsets `roffsets`, the internal coboundary `D` (rows: internal
edge rows, columns: the block's stacked stalk), a basis `N` of `ker D` (the
coarse stalk), the particular-solution operator `X` (`xbar = X r` for the
stacked internal targets `r`), the consistency operator `C = D X - I`
(`C r = 0` exactly when the affine fiber is nonempty; empty `C` when `D` has
full row rank), and the basis `kind`.
"""
struct Fiber
    members::Vector{Int}
    offsets::Vector{Int}
    internal::Vector{Int}
    roffsets::Vector{Int}
    D::SpMat
    N::SpMat
    X::SpMat
    C::SpMat
    kind::Symbol
end

"""`fiberdim(F)`: the dimension of the fiber's section space, the coarse stalk."""
fiberdim(F::Fiber) = size(F.N, 2)
Base.length(F::Fiber) = F.offsets[end]

_spI(n) = SpMat(sparse(1.0I, n, n))

"""Sparse internal coboundary `D` of the block and the row offsets of its internal edges."""
function _internal_coboundary(P::SheafProgram, internal::Vector{Int}, local_index::Vector{Int}, offs::Vector{Int})
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    roffs = zeros(Int, length(internal) + 1)
    row = 0
    for (k, e) in enumerate(internal)
        E = P.edges[e]
        _push_block!(I_, J_, V_, row, offs[local_index[E.tail]], E.Ft, -1.0)
        _push_block!(I_, J_, V_, row, offs[local_index[E.head]], E.Fh, 1.0)
        row += edgedim(E)
        roffs[k+1] = row
    end
    return sparse(I_, J_, V_, row, offs[end]), roffs
end

"""
Columns `S` on which the restriction map `F` (`d x n`) is square and
invertible, and the factorized block `F[:, S]`; `nothing` if there are none.
Unit columns covering every row are preferred, so that the identity blocks of
dynamics and agreement maps are used exactly.
"""
function _solve_columns(F::SpMat)
    d, nv = size(F)
    d == 0 && return Int[], Diagonal(Float64[])
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

_ldiv(FS::Diagonal, M::AbstractMatrix) = SpMat(sparse(FS \ M))
_ldiv(FS, M::AbstractMatrix) = SpMat(sparse(FS \ Matrix(M)))

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

_padcols(M::SpMat, w::Int) = size(M, 2) == w ? M : SpMat([M spzeros(size(M, 1), w - size(M, 2))])

"""Selector of the rows `roffs[k]+1:roffs[k+1]` of the stacked targets (`d x m`)."""
_selector(roffs, k, m) = sparse(1:(roffs[k+1]-roffs[k]), (roffs[k]+1):roffs[k+1], 1.0, roffs[k+1] - roffs[k], m)

function _structured_fiber(P::SheafProgram, members::Vector{Int}, internal::Vector{Int}, local_index::Vector{Int},
                           offs::Vector{Int}, D::SpMat, roffs::Vector{Int})
    nm = length(members)
    n = offs[end]
    m = roffs[end]
    epos = Dict(e => k for (k, e) in enumerate(internal))
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
    Xl = Vector{SpMat}(undef, nm)          # x_l = Xl[l] r + Nl[l] z_c (z_c: coordinates of tree c)
    Nl = Vector{SpMat}(undef, nm)
    kc = Int[]
    tree = falses(length(internal))
    for root in 1:nm
        comp[root] == 0 || continue
        d0 = P.dims[members[root]]
        push!(kc, d0)
        c = length(kc)
        comp[root] = c
        Xl[root] = spzeros(d0, m)
        Nl[root] = _spI(d0)
        queue = [root]
        head = 1
        while head <= length(queue)
            u = queue[head]; head += 1
            for (e, v) in adj[u]
                comp[v] == 0 || continue
                E = P.edges[e]
                # F x_v = sgn r_e + Fo x_u for the new end v
                F, Fo, sgn = local_index[E.head] == v ? (E.Fh, E.Ft, 1.0) : (E.Ft, E.Fh, -1.0)
                piv = _solve_columns(F)
                piv === nothing && return nothing
                S, FS = piv
                dv = P.dims[members[v]]
                Sc = setdiff(1:dv, S)
                k0 = kc[c]
                f = length(Sc)
                kc[c] += f
                k = epos[e]
                Xv = spzeros(dv, m); Nv = spzeros(dv, kc[c])
                if !isempty(S)
                    XS = _ldiv(FS, sgn * _selector(roffs, k, m) + Fo * Xl[u])
                    FoN = Fo * Nl[u]
                    NS = [_ldiv(FS, FoN) spzeros(length(S), k0 - size(FoN, 2)) (-_ldiv(FS, F[:, Sc]))]
                    p = invperm([S; Sc])
                    Xv = SpMat([XS; spzeros(f, m)][p, :])
                    Nv = SpMat([NS; [spzeros(f, k0) _spI(f)]][p, :])
                else
                    Nv = SpMat([spzeros(f, k0) _spI(f)])
                end
                comp[v] = c; Xl[v] = Xv; Nl[v] = Nv
                tree[k] = true
                push!(queue, v)
            end
        end
    end
    nc = length(kc)
    # pass 2: the edges between trees, solved along a spanning tree of the trees
    groups = Dict{Tuple{Int,Int},Vector{Int}}()
    for (k, e) in enumerate(internal)
        tree[k] && continue
        ca, cb = comp[local_index[P.edges[e].tail]], comp[local_index[P.edges[e].head]]
        ca == cb || push!(get!(groups, minmax(ca, cb), Int[]), e)
    end
    cadj = [Int[] for _ in 1:nc]
    for (a, b) in keys(groups)
        push!(cadj[a], b); push!(cadj[b], a)
    end
    foreach(sort!, cadj)
    Z0 = Vector{SpMat}(undef, nc)          # z_c = Z0[c] r + T[c] zeta (zeta: the block's coordinates)
    T = Vector{SpMat}(undef, nc)
    seen = falses(nc)
    cache = Dict{Matrix{Float64},Any}()
    ncol = 0
    for root in 1:nc
        seen[root] && continue
        seen[root] = true
        Z0[root] = spzeros(kc[root], m)
        T[root] = SpMat([spzeros(kc[root], ncol) _spI(kc[root])])
        ncol += kc[root]
        queue = [root]
        head = 1
        while head <= length(queue)
            a = queue[head]; head += 1
            for b in cadj[a]
                seen[b] && continue
                # stacked constraints Gb z_b - Ga z_a = Gr r of the edges between trees a and b
                Gb = Matrix{Float64}[]; Ga = Matrix{Float64}[]; Gr = SpMat[]
                for e in groups[minmax(a, b)]
                    E = P.edges[e]
                    lt, lh = local_index[E.tail], local_index[E.head]
                    Gh = Matrix(E.Fh * Nl[lh]); Gt = Matrix(E.Ft * Nl[lt])
                    ge = _selector(roffs, epos[e], m) - E.Fh * Xl[lh] + E.Ft * Xl[lt]
                    if comp[lh] == b
                        push!(Gb, Gh); push!(Ga, Gt); push!(Gr, ge)
                    else
                        push!(Gb, Gt); push!(Ga, Gh); push!(Gr, -ge)
                    end
                end
                pad(M, w) = size(M, 2) == w ? M : [M zeros(size(M, 1), w - size(M, 2))]
                Gbm = reduce(vcat, (pad(M, kc[b]) for M in Gb))
                Gam = reduce(vcat, (pad(M, kc[a]) for M in Ga))
                Grm = SpMat(reduce(vcat, Gr))
                pinvG, K, rk = _small_svd!(cache, Gbm)
                if size(Gam) == size(Gbm) && norm(Gam - Gbm, Inf) <= 1e-12 * max(1.0, norm(Gbm, Inf))
                    # identical members: z_b = z_a + G^+ g + K w_b
                    Z0[b] = SpMat(Z0[a] + sparse(pinvG * Grm))
                    Tb = T[a]
                else
                    rk == size(Gbm, 1) || continue                 # left to the leftover rows
                    Z0[b] = SpMat(sparse(pinvG * (Grm + Gam * Z0[a])))
                    Tb = SpMat(sparse(pinvG * (Gam * T[a])))
                end
                T[b] = SpMat([Tb spzeros(size(Tb, 1), ncol - size(Tb, 2)) sparse(K)])
                ncol += size(K, 2)
                seen[b] = true
                push!(queue, b)
            end
        end
    end
    # assemble x = X r + N zeta over the block
    XI = Int[]; XJ = Int[]; XV = Float64[]
    NI = Int[]; NJ = Int[]; NV = Float64[]
    for l in 1:nm
        c = comp[l]
        Nlc = _padcols(Nl[l], kc[c])
        Xb = Xl[l] + Nlc * Z0[c]
        Nb = Nlc * _padcols(T[c], ncol)
        ii, jj, vv = findnz(Xb); append!(XI, offs[l] .+ ii); append!(XJ, jj); append!(XV, vv)
        ii, jj, vv = findnz(Nb); append!(NI, offs[l] .+ ii); append!(NJ, jj); append!(NV, vv)
    end
    X = dropzeros!(sparse(XI, XJ, XV, n, m))
    N = dropzeros!(sparse(NI, NJ, NV, n, ncol))
    # the leftover rows: zero on the parametrization, or imposed on its coordinates
    kind = :structured
    scale = max(1.0, maximum(abs, nonzeros(D); init = 0.0)) * max(1.0, maximum(abs, nonzeros(N); init = 0.0))
    tol = 1e-11 * scale
    R = D * N
    if maximum(abs, nonzeros(R); init = 0.0) > tol
        Rd = Matrix(R)
        keep = [i for i in axes(Rd, 1) if maximum(abs, view(Rd, i, :)) > tol]
        Rd = Rd[keep, :]
        Sop = (sparse(1.0I, m, m) - D * X)[keep, :]                # s = r - D xbar on the kept rows
        F = svd(Rd; full = true)
        smax = isempty(F.S) ? 0.0 : F.S[1]
        rk = count(>(max(tol, maximum(size(Rd)) * eps() * smax)), F.S)
        Z = F.V[:, 1:rk] * (Diagonal(1 ./ F.S[1:rk]) * (F.U[:, 1:rk]' * Matrix(Sop)))
        X = dropzeros!(SpMat(X + sparse(N * Z)))
        N = dropzeros!(SpMat(sparse(N * F.V[:, (rk+1):end])))
        kind = :structured_reduced
        R = D * N
        maximum(abs, nonzeros(R); init = 0.0) <= tol || return nothing
    end
    return X, N, kind
end

function _orthonormal_fiber(D::SpMat)
    m, n = size(D)
    F = svd(Matrix(D); full = true)
    smax = isempty(F.S) ? 0.0 : F.S[1]
    rk = count(>(max(m, n) * eps() * smax), F.S)
    X = F.V[:, 1:rk] * (Diagonal(1 ./ F.S[1:rk]) * F.U[:, 1:rk]')
    N = F.V[:, (rk+1):n]
    return SpMat(sparse(X)), SpMat(sparse(N)), :orthonormal
end

"""
    _make_fiber(P, members, internal, local_index, basis) -> Fiber

The fiber of one block. `basis` is `:structured` (falls back to
`:orthonormal` when forward substitution fails) or `:orthonormal`.
"""
function _make_fiber(P::SheafProgram, members::Vector{Int}, internal::Vector{Int}, local_index::Vector{Int},
                     basis::Symbol)
    offs = zeros(Int, length(members) + 1)
    for (l, v) in enumerate(members)
        offs[l+1] = offs[l] + P.dims[v]
    end
    n = offs[end]
    D, roffs = _internal_coboundary(P, internal, local_index, offs)
    m = size(D, 1)
    if m == 0
        return Fiber(members, offs, internal, roffs, D, _spI(n), spzeros(n, 0), spzeros(0, 0), :identity)
    end
    res = nothing
    if basis == :structured
        res = _structured_fiber(P, members, internal, local_index, offs, D, roffs)
    elseif basis != :orthonormal
        throw(ArgumentError("unknown basis $basis (use :structured or :orthonormal)"))
    end
    res === nothing && (res = _orthonormal_fiber(D))
    X, N, kind = res
    C = droptol!(SpMat(D * X - sparse(1.0I, m, m)), 1e-12 * max(1.0, maximum(abs, nonzeros(D); init = 0.0)))
    return Fiber(members, offs, internal, roffs, D, N, X, C, kind)
end

"""True when the internal edges of `F` have the same endpoints and restriction maps in `P` as in `Pp` (targets may differ)."""
function _same_maps(P::SheafProgram, Pp::SheafProgram, internal)
    for e in internal
        E = P.edges[e]; G = Pp.edges[e]
        (E.tail == G.tail && E.head == G.head && E.Ft == G.Ft && E.Fh == G.Fh && E.hard == G.hard &&
         E.tag.kind == G.tag.kind) || return false
    end
    return true
end
