# certificates.jl: the optimality gap of a reduction, bounded from the
# reduced and the fine solves (the paper's Thm. 2), the gap kernel that gives
# the gap of every team structure of an equality-constrained QP at once
# (Prop. 7), and the team selector built on it.
#
# Let S be the soft edges a reduction contracts (it makes them hard) and
# Gamma_S = J*(P[S]) - J*(P) its gap.
#
# (a) Upper bound, from the reduced solve alone. A multiplier mu of P[S] is the
#     force each newly hard edge carries; Gamma_S <= sum_{e in S} (1/2)||mu_e||^2
#     in the W_e^{-1} norm, the energy the spring would store under that force.
#     At the lifted plan x = iota(y*), stationarity of P[S] on each block B
#     reads D_B' nu = -(grad_B J(x) + (surviving hard edges)' lambda + A_B' z),
#     with lambda and z the reduced solve's multipliers; with cycles inside a
#     team nu is not unique (a statically indeterminate truss) and the least
#     W^{-1}-norm solution is the tightest. One small sparse solve per block.
# (b) Lower bound, from the fine solve: Gamma_S >= sum_{e in S} (1/2)||s_e||^2_{W_e}
#     with s_e = (delta x*)_e - b_e the defects at the fine optimum x*.

# ---------------------------------------------------------------------------
# Least-norm multipliers, block by block
# ---------------------------------------------------------------------------

struct CertBlock
    vars::Vector{Int}                 # fine variables of the block (stacked members)
    edges::Vector{Int}                # internal (contracted) fine edges
    roffs::Vector{Int}
    soft::Vector{Bool}
    Winv::Vector{Matrix{Float64}}
    D::SpMat                          # m x n
    Dt::SpMat
    K::SpMat                          # [Winv + reg, D; D', -delta I] (full, for refinement products)
    F::Any                            # QDLDL factorization of K
    rhs::Vector{Float64}
    sol::Vector{Float64}
    res::Vector{Float64}
    tmp::Vector{Float64}
    delta::Float64
    T::Matrix{Float64}                # the least-norm operator nu = T rhs (empty for large blocks)
end

"""Least `W^{-1}`-norm solution of `D' nu = rhs` (in `B.sol[1:m]`): regularized solve and refinement."""
function _least_norm!(B::CertBlock, refine::Int, gn::Float64)
    m = B.roffs[end]
    n = length(B.vars)
    copyto!(B.sol, B.rhs)
    QDLDL.solve!(B.F, B.sol)
    # iterative refinement against [Winv D; D' 0]: the constraint D'nu = rhs exactly
    for _ in 1:refine
        mul!(B.res, B.K, B.sol)
        @inbounds for i in (m+1):(m+n)
            B.res[i] += B.delta * B.sol[i]
        end
        @inbounds for i in eachindex(B.res)
            B.res[i] = B.rhs[i] - B.res[i]
        end
        maximum(abs, B.res) <= 1e-14 * max(1.0, gn) && break
        QDLDL.solve!(B.F, B.res)
        B.sol .+= B.res
    end
    return B
end

"""
    Certifier(reduced)

The precomputed part of the upper bound of `gap_bounds` for a reduction (or a
chain of them, seen as one pushforward of the finest program): the blocks
whose contracted edges include soft ones, each with its internal coboundary
and a factorized least-norm system, and the maps from the reduced program's
multipliers to the finest program. `certify!(cert, sol)` evaluates the bound
for a reduced solution without allocating much.
"""
mutable struct Certifier
    P0::SheafProgram
    labels::Vector{Int}
    collapsed::Vector{Int}
    edge_map::Vector{Int}
    row_map::Vector{Int}
    qmap::QPMap                       # the finest program's QP: gradient H x + g
    hard_coarse::Vector{Int}          # coarse edges that are hard (with their fine edges)
    Dh::SpMat                         # coboundary rows of their fine edges (rows in coarse C^1 order of those edges)
    hrows::Vector{Int}                # positions in the coarse C^1 of those rows
    An::SpMat
    blocks::Vector{CertBlock}
    grad::Vector{Float64}
    lam::Vector{Float64}
    zf::Vector{Float64}
    x::Vector{Float64}
    per_block::Vector{Float64}
    residual::Float64
end

function Certifier(R::ReducedProgram; delta::Real = 1e-9, max_dense::Integer = 250_000)
    P0 = root_program(R)
    labels, collapsed, edge_map, row_map = composite_partition(R)
    Pc = R.program
    hard_coarse = [k for (k, E) in enumerate(Pc.edges) if E.hard && edgedim(E) > 0]
    Dh = coboundary(P0, edge_map[hard_coarse])
    hrows = reduce(vcat, (collect(erange(Pc, k)) for k in hard_coarse); init = Int[])
    An, _, _ = node_constraints(P0)
    members = block_members(labels)
    inblock = [Int[] for _ in members]
    for e in collapsed
        push!(inblock[labels[P0.edges[e].tail]], e)
    end
    blocks = CertBlock[]
    for (b, mem) in enumerate(members)
        es = inblock[b]
        any(e -> !P0.edges[e].hard && edgedim(P0.edges[e]) > 0, es) || continue
        vars = reduce(vcat, (collect(vrange(P0, v)) for v in mem))
        local_index = Dict(v => l for (l, v) in enumerate(mem))
        offs = [0; cumsum([P0.dims[v] for v in mem])]
        I_ = Int[]; J_ = Int[]; V_ = Float64[]
        roffs = [0]; soft = Bool[]; Winv = Matrix{Float64}[]
        row = 0
        for e in es
            E = P0.edges[e]
            _push_block!(I_, J_, V_, row, offs[local_index[E.tail]], E.Ft, -1.0)
            _push_block!(I_, J_, V_, row, offs[local_index[E.head]], E.Fh, 1.0)
            row += edgedim(E)
            push!(roffs, row); push!(soft, !E.hard)
            push!(Winv, E.hard ? zeros(0, 0) : inv(E.W))
        end
        m, n = row, offs[end]
        D = sparse(I_, J_, V_, m, n)
        WI = Int[]; WJ = Int[]; WV = Float64[]
        scale = 1.0
        for (k, e) in enumerate(es)
            soft[k] && (scale = max(scale, maximum(abs, Winv[k]; init = 0.0)))
        end
        dl = delta * scale
        for (k, e) in enumerate(es)
            r0 = roffs[k]; d = roffs[k+1] - r0
            if soft[k]
                for jj in 1:d, ii in 1:d
                    Winv[k][ii, jj] != 0 && (push!(WI, r0 + ii); push!(WJ, r0 + jj); push!(WV, Winv[k][ii, jj]))
                end
            else
                for ii in 1:d
                    push!(WI, r0 + ii); push!(WJ, r0 + ii); push!(WV, dl)
                end
            end
        end
        Wm = sparse(WI, WJ, WV, m, m)
        K = SpMat([Wm D; SpMat(D') -dl * sparse(1.0I, n, n)])
        F = QDLDL.qdldl(SpMat(triu(K)))
        B = CertBlock(vars, es, roffs, soft, Winv, D, SpMat(D'), K, F, zeros(m + n), zeros(m + n),
                      zeros(m + n), zeros(m + n), dl, zeros(0, 0))
        if m * n <= max_dense
            # the forces are linear in the right-hand side: tabulate the operator once
            T = zeros(m, n)
            for l in 1:n
                fill!(B.rhs, 0.0); B.rhs[m+l] = 1.0
                _least_norm!(B, 8, 1.0)
                T[:, l] .= view(B.sol, 1:m)
            end
            B = CertBlock(vars, es, roffs, soft, Winv, D, SpMat(D'), K, F, zeros(m + n), zeros(m + n),
                          zeros(m + n), zeros(m + n), dl, T)
        end
        push!(blocks, B)
    end
    qmap = QPMap(P0; dedup = false)
    return Certifier(P0, labels, collapsed, edge_map, row_map, qmap, hard_coarse, Dh, hrows, An, blocks,
                     zeros(c0dim(P0)), zeros(length(hrows)), zeros(noderows(P0)), zeros(c0dim(P0)),
                     zeros(length(blocks)), 0.0)
end

"""
    update_matrices!(cert::Certifier, verts) -> cert

After the constraint matrices of the finest program's vertices `verts` changed
in place (`set_state_set!`): refresh the stacked node matrix the certificate
uses for the node multipliers.
"""
function update_matrices!(C::Certifier, verts)
    _refresh_node_rows!(C.An, C.P0, verts)
    refresh_matrices!(C.qmap, C.P0, verts)
    return C
end

"""
    certify!(cert, x, hard_duals, node_duals) -> upper

The upper bound (a) at the finest plan `x` (the lifted reduced solution) from
the reduced program's multipliers: hard edge duals laid out over its `C^1`
and node duals over its node rows.
"""
function certify!(C::Certifier, x::AbstractVector, hard_duals::AbstractVector, node_duals::AbstractVector;
                  refine::Int = 8)
    P0 = C.P0
    refresh!(C.qmap, P0)
    g = C.grad
    mul!(g, C.qmap.qp.P, x)
    g .+= C.qmap.q
    @inbounds for (k, r) in enumerate(C.hrows)
        C.lam[k] = hard_duals[r]
    end
    mul!(g, transpose(C.Dh), C.lam, 1.0, 1.0)
    @inbounds for (j, r) in enumerate(C.row_map)
        C.zf[r] = node_duals[j]
    end
    mul!(g, transpose(C.An), C.zf, 1.0, 1.0)
    total = 0.0
    worst = 0.0
    for (b, B) in enumerate(C.blocks)
        m = B.roffs[end]
        n = length(B.vars)
        fill!(B.rhs, 0.0)
        gn = 0.0
        @inbounds for (l, j) in enumerate(B.vars)
            B.rhs[m+l] = -g[j]
            gn = max(gn, abs(g[j]))
        end
        if isempty(B.T)
            _least_norm!(B, refine, gn)
        else
            mul!(view(B.sol, 1:m), B.T, view(B.rhs, (m+1):(m+n)))
        end
        # stationarity residual of the multipliers
        r = 0.0
        @inbounds for l in 1:n
            s = 0.0
            for p in nzrange(B.D, l)
                s += nonzeros(B.D)[p] * B.sol[rowvals(B.D)[p]]
            end
            r = max(r, abs(s - B.rhs[m+l]))
        end
        worst = max(worst, r / max(1.0, gn))
        eta = 0.0
        @inbounds for k in eachindex(B.soft)
            B.soft[k] || continue
            r0 = B.roffs[k]; d = B.roffs[k+1] - r0
            Wi = B.Winv[k]
            for jj in 1:d, ii in 1:d
                eta += 0.5 * B.sol[r0+ii] * Wi[ii, jj] * B.sol[r0+jj]
            end
        end
        C.per_block[b] = eta
        total += eta
    end
    C.residual = worst
    return total
end

"""The least-norm multiplier `mu_e` of every contracted edge from the last `certify!` (a Dict by finest edge)."""
function multipliers(C::Certifier)
    mu = Dict{Int,Vector{Float64}}()
    for B in C.blocks, (k, e) in enumerate(B.edges)
        mu[e] = B.sol[(B.roffs[k]+1):B.roffs[k+1]]
    end
    return mu
end

"""
    gap_lower_bound(P, collapsed, xstar)

`(1/2) sum_{e in S soft} ||(delta x*)_e - b_e||^2_{W_e}`: bound (b) of the paper's
Thm. 2, the energy the contracted springs store at the fine optimum.
"""
function gap_lower_bound(P::SheafProgram, collapsed, xstar::AbstractVector)
    tot = 0.0
    for e in collapsed
        E = P.edges[e]
        (E.hard || edgedim(E) == 0) && continue
        s = edge_defect(P, e, xstar)
        tot += 0.5 * dot(s, E.W * s)
    end
    return tot
end

"""
    gap_bounds(fine, reduced, sol; fine_solution = nothing) -> NamedTuple

Certify the optimality gap `Gamma = J*(reduced) - J*(fine)` of a reduction
(the paper's Thm. 2). `fine` is the finest program (a `FleetProgram` or a
`SheafProgram`), `reduced` the `ReducedProgram` (possibly teams of teams),
`sol` its solution (`solve(reduced)`).

* `upper`: bound (a), from the reduced solve alone. The multipliers of the
  contracted soft edges (the internal forces of the teams) are recovered team
  by team from stationarity at the lifted plan, least `W^{-1}`-norm when a team
  has cycles, and `upper = sum_e (1/2)||mu_e||^2_{W_e^{-1}}`. It certifies the
  reduced plan without solving the fine program. `residual` is the relative
  stationarity residual of the recovered forces (small when the reduced
  multipliers are accurate).
* `lower`: bound (b), `sum_e (1/2)||s_e||^2_{W_e}` over the contracted soft
  edges with the defects `s_e` at the fine optimum; needs `fine_solution`
  (`NaN` without it).
* `gap`: the true gap `J(reduced) - J(fine)` when `fine_solution` is given.

`per_block` lists the upper bound's share of every block that contracts a
soft edge (one block per team and instant for `Teams`).
"""
function gap_bounds(fine, R::ReducedProgram, sol::ProgramSolution; fine_solution = nothing, cert = nothing)
    P0 = root_program(R)
    _sheaf(fine) === P0 || throw(ArgumentError("`fine` must be the program the reduction starts from"))
    C = cert === nothing ? Certifier(R) : cert
    x = lift(R, sol.x)
    up = isoptimal(sol) ? certify!(C, x, sol.hard_duals, sol.node_duals) : Inf
    lo, gp = NaN, NaN
    if fine_solution !== nothing
        lo = gap_lower_bound(P0, C.collapsed, fine_solution.x)
        gp = sol.J - fine_solution.J
    end
    return (lower = lo, upper = up, gap = gp, per_block = copy(C.per_block), residual = C.residual, x = x)
end

# ---------------------------------------------------------------------------
# The gap kernel (the paper's Prop. 7)
# ---------------------------------------------------------------------------

"""
    GapKernel

The gap kernel of a program at its fine minimizer `x*`. Contracting the hard
edges is free, so the vertices joined by hard edges form the base vertices
(for MPC: one agent's path over the horizon, so base vertex `i` is agent `i`),
and a team structure is a partition `alpha` of the base vertices. With `s` the
defects of the soft edges at `x*`, `Z` a basis of the directions of the
equality constraints, `H` the reduced Hessian and `D` the soft coboundary,
`K = D Z H^{-1} Z' D'` and, for the soft edges `S` a team structure contracts,

    Gamma_S = (1/2) s_S' K_SS^+ s_S       (infinite when s_S is not in range K_SS).

Exact for equality-constrained QPs; the half-spaces active at `x*` are kept as
equalities. When the reduced minimizer activates new inequalities (or any
second-order cone is active) the formula is a lower bound on the true gap.
"""
struct GapKernel
    comp::Vector{Int}                       # base vertex of every vertex of the program
    nb::Int
    bedges::Vector{Tuple{Int,Int}}          # base edges (a < b) carrying soft rows
    rows::Vector{Vector{Int}}               # kernel rows of each base edge
    intra::Vector{Int}                      # kernel rows of soft edges inside one base vertex
    adj::Vector{Vector{Tuple{Int,Int}}}     # (neighbour, base edge)
    G::Matrix{Float64}                      # the kernel D Z H^{-1} Z' D'
    s::Vector{Float64}                      # soft defects at x*
    xstar::Vector{Float64}
    Jstar::Float64
    base_gap::Float64
    tol::Float64
    active_soc::Int
    active_nonneg::Int
    mode::Symbol
end

const INCONSISTENT = 1e-6

function _union_find_roots(nv, pairs)
    par = collect(1:nv)
    find(a) = (while par[a] != a; par[a] = par[par[a]]; a = par[a]; end; a)
    for (a, b) in pairs
        ra, rb = find(a), find(b)
        ra != rb && (par[max(ra, rb)] = min(ra, rb))
    end
    return [find(v) for v in 1:nv]
end

"""Active node constraints at `x`: half-space rows (node row indices) and SOC blocks on their boundary."""
function _active(P::SheafProgram, x::AbstractVector; tol::Real = 1e-7)
    A, b, cones = node_constraints(P)
    s = b - A * x
    nn = Int[]; nsoc = 0
    r = 0
    for cb in cones
        rr = (r+1):(r+cb.dim)
        if cb.kind == NONNEG_CONE
            for i in rr
                s[i] <= tol * max(1.0, abs(b[i])) && push!(nn, i)
            end
        elseif cb.kind == SOC_CONE
            t = s[rr[1]]
            (t - norm(view(s, rr[2:end]))) <= tol * max(1.0, t) && (nsoc += 1)
        end
        r += cb.dim
    end
    return nn, nsoc
end

"""
    gap_kernel(program, xstar) -> GapKernel

Assemble the gap kernel of `program` (a `FleetProgram` or `SheafProgram`) at
its fine minimizer `xstar` (`solve(program).x`): one sparse factorization of
the KKT matrix of the equality constraints (hard edges, pinned states, active
half-spaces) and one solve per soft row. Then `gap(kernel, teams)` costs a
small Cholesky factorization and no pushforward or solve.
"""
gap_kernel(F::FleetProgram, xstar::AbstractVector) = gap_kernel(F.program, xstar)

function gap_kernel(P::SheafProgram, xstar::AbstractVector)
    nv = nvertices(P)
    Jstar = objective(P, xstar)
    roots = _union_find_roots(nv, [(E.tail, E.head) for E in P.edges if E.hard])
    comp = canonical_partition(roots)
    nb = maximum(comp)
    soft = [e for e in soft_edges(P) if edgedim(P.edges[e]) > 0]
    key = Dict{Tuple{Int,Int},Int}()
    bedges = Tuple{Int,Int}[]; erows = Vector{Vector{Int}}(); intra = Int[]
    offs = [0; cumsum([edgedim(P.edges[e]) for e in soft])]
    for (k, e) in enumerate(soft)
        E = P.edges[e]
        a, b = comp[E.tail], comp[E.head]
        r = collect((offs[k]+1):offs[k+1])
        if a == b
            append!(intra, r)
        else
            kk = get!(key, minmax(a, b)) do
                push!(bedges, minmax(a, b)); push!(erows, Int[]); length(bedges)
            end
            append!(erows[kk], r)
        end
    end
    adj = [Tuple{Int,Int}[] for _ in 1:nb]
    for (k, (a, b)) in enumerate(bedges)
        push!(adj[a], (b, k)); push!(adj[b], (a, k))
    end
    D = coboundary(P, soft)
    s = D * xstar - targets(P, soft)
    Hq, _, _ = quadratic_form(P)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    An, _, cones = node_constraints(P)
    zrows = Int[]
    r = 0
    for cb in cones
        cb.kind == ZERO_CONE && append!(zrows, (r+1):(r+cb.dim))
        r += cb.dim
    end
    act, nsoc = _active(P, xstar)
    A = [coboundary(P, hard); An[zrows, :]; An[act, :]]
    n, m = size(Hq, 1), size(A, 1)
    K = [Hq SpMat(A'); A spzeros(m, m)]
    F = try
        lu(K)
    catch
        lu(K - blockdiag(spzeros(n, n), 1e-10 * sparse(1.0I, m, m)))
    end
    R = size(D, 1)
    G = zeros(R, R)
    Dt = SpMat(D')
    for c in Iterators.partition(1:R, 256)
        rhs = zeros(n + m, length(c))
        rhs[1:n, :] .= Matrix(Dt[:, c])
        Y = F \ rhs
        G[:, c] .= D * Y[1:n, :]
    end
    G .= (G .+ G') ./ 2
    tol = 1e-9 * max(maximum(diag(G); init = 0.0), eps())
    K0 = GapKernel(comp, nb, bedges, erows, intra, adj, G, s, Vector{Float64}(xstar), Jstar, 0.0, tol, nsoc, length(act), :all)
    bg = isempty(intra) ? 0.0 : _gap_rows(K0, intra)
    # spanning trees of the teams suffice when every cycle's rows are implied by its tree
    mode = :tree
    rng = Xoshiro(0)
    tests = [[ones(Int, nb)]; [_random_connected(adj, nb, rng, rand(rng, 1:max(1, nb ÷ 2))) for _ in 1:4]]
    for a in tests
        gt = _gap_rows(K0, _partition_rows(K0, a; mode = :tree))
        ga = _gap_rows(K0, _partition_rows(K0, a; mode = :all))
        same = isinf(gt) == isinf(ga) && (isinf(ga) || abs(gt - ga) <= 1e-9 * max(abs(Jstar), abs(ga), 1.0))
        same || (mode = :all; break)
    end
    return GapKernel(comp, nb, bedges, erows, intra, adj, G, s, Vector{Float64}(xstar), Jstar, bg, tol, nsoc,
                     length(act), mode)
end

function Base.show(io::IO, K::GapKernel)
    print(io, "GapKernel($(K.nb) base vertices, $(length(K.bedges)) base edges, $(length(K.s)) soft rows, J* = ",
          @sprintf("%.6g", K.Jstar), K.active_soc + K.active_nonneg > 0 ?
          ", $(K.active_soc) active cones and $(K.active_nonneg) active half-spaces at x*: gaps are lower bounds" : "", ")")
end

function _random_connected(adj, nb::Int, rng, k::Int)
    lab = zeros(Int, nb)
    for (c, v) in enumerate(randperm(rng, nb)[1:k])
        lab[v] = c
    end
    while any(==(0), lab)
        cand = [(v, u) for v in 1:nb if lab[v] != 0 for (u, _) in adj[v] if lab[u] == 0]
        isempty(cand) && (lab[findfirst(==(0), lab)] = rand(rng, 1:k); continue)
        v, u = rand(rng, cand)
        lab[u] = lab[v]
    end
    return canonical_partition(lab)
end

"""`(1/2) d' M^+ d` for symmetric PSD `M`, the relative size of `d` off the range of `M`, and `M^+`."""
function _quadpinv(M::AbstractMatrix, d::AbstractVector, tol::Real)
    isempty(d) && return 0.0, 0.0, zeros(0, 0)
    ev = eigen(Symmetric(Matrix(M)))
    keep = ev.values .> tol
    V = ev.vectors[:, keep]
    Mp = V * Diagonal(1 ./ ev.values[keep]) * V'
    off = norm(d - V * (V' * d)) / max(norm(d), 1e-300)
    return 0.5 * dot(d, Mp * d), off, Mp
end

"""Exact gap of hardening the kernel rows `rows` (pivoted Cholesky; `Inf` when they are inconsistent)."""
function _gap_rows(K::GapKernel, rows::AbstractVector{<:Integer})
    isempty(rows) && return 0.0
    M = Symmetric(K.G[rows, rows])
    F = cholesky(M, RowMaximum(); tol = K.tol, check = false)
    r = F.rank
    r == 0 && return norm(K.s[rows]) > INCONSISTENT * max(norm(K.s), 1.0) ? Inf : 0.0
    p = F.p[1:r]
    U = UpperTriangular(F.U[1:r, 1:r])
    sS = K.s[rows]
    z = U' \ sS[p]
    if r < length(rows)
        q = F.p[(r+1):end]
        res = sS[q] - M[q, p] * (U \ z)
        norm(res) > INCONSISTENT * max(norm(sS), 1.0) && return Inf
    end
    return 0.5 * dot(z, z)
end

function _partition_rows(K::GapKernel, alpha::AbstractVector{<:Integer}; mode::Symbol = K.mode)
    rows = copy(K.intra)
    if mode == :all
        for (k, (a, b)) in enumerate(K.bedges)
            alpha[a] == alpha[b] && append!(rows, K.rows[k])
        end
        return rows
    end
    seen = falses(K.nb)
    for v0 in 1:K.nb
        seen[v0] && continue
        seen[v0] = true
        queue = [v0]; head = 1
        while head <= length(queue)
            v = queue[head]; head += 1
            for (u, k) in K.adj[v]
                (alpha[u] == alpha[v0] && !seen[u]) || continue
                seen[u] = true; push!(queue, u); append!(rows, K.rows[k])
            end
        end
    end
    return rows
end

"""
    gap(kernel, teams) -> Float64

The gap of the team structure `teams` (one label per base vertex; for a fleet,
one per agent) by the closed form of the paper's Prop. 7, relative to the
fine optimum the kernel was built at. `Inf` when the teams' affine fibers are
empty (the reduced program is infeasible). Teams must be connected.
"""
gap(K::GapKernel, alpha::AbstractVector{<:Integer}) = _gap_rows(K, _partition_rows(K, canonical_partition(alpha)))

"""
    gap(kernel, teams::Teams)

The same for a `Teams` resolution (over the whole horizon).
"""
gap(K::GapKernel, T::Teams) = (T.from == 0 || throw(ArgumentError("the kernel gives the gap of teams over the whole horizon"));
                               gap(K, T.alpha))

# ---------------------------------------------------------------------------
# Choosing the teams: agglomeration by exact gap increments
# ---------------------------------------------------------------------------

# Merging two adjacent teams hardens the rows N between them; the increment is
# a Gaussian conditioning of the kernel and the defects conditioned on the
# rows hardened so far:
#   Delta gamma = (1/2) d_N' C_NN^+ d_N,  C <- C - C_.N C_NN^+ C_N.,  d <- d - C_.N C_NN^+ d_N.

struct _SelState
    gamma::Float64
    alpha::Vector{Int}
    C::Matrix{Float64}
    d::Vector{Float64}
end

function _condition!(C::Matrix{Float64}, d::Vector{Float64}, N::Vector{Int}, Mp::Matrix{Float64})
    isempty(N) && return
    CN = C[:, N]
    X = CN * Mp
    dN = d[N]
    mul!(C, X, CN', -1.0, 1.0)
    d .-= X * dN
    return
end

function _bridge_rows(K::GapKernel, labels::Vector{Int}, a::Int, b::Int)
    rows = Int[]
    for (k, (u, v)) in enumerate(K.bedges)
        ((labels[u] == a && labels[v] == b) || (labels[u] == b && labels[v] == a)) && append!(rows, K.rows[k])
    end
    return rows
end

function _candidate_pairs(pairs, labels)
    out = Set{Tuple{Int,Int}}()
    for (u, v) in pairs
        la, lb = labels[u], labels[v]
        la != lb && push!(out, minmax(la, lb))
    end
    return sort!(collect(out))
end

"""Merge clusters `b` into `a` and relabel canonically."""
_merge(labels, a, b) = canonical_partition([l == b ? a : l for l in labels])

"""
    team_front(kernel; beam = 1, graph = nothing) -> Dict(k => (gap, teams))

Agglomerate from singletons down to one team, merging at each level the
adjacent pair of least exact gap increment (Ward's agglomeration with the gap
as the cost): a maximal chain of the lattice, teams of teams. With `beam > 1`
the `beam` best clusterings are kept at every level. Adjacency is the
kernel's base graph, or the agent pairs in `graph`.
"""
function team_front(K::GapKernel; beam::Integer = 1, graph = nothing)
    pairs = graph === nothing ? K.bedges : [minmax(Int(a), Int(b)) for (a, b) in graph]
    C0 = copy(K.G); d0 = copy(K.s)
    if !isempty(K.intra)
        _, _, Mp = _quadpinv(C0[K.intra, K.intra], d0[K.intra], K.tol)
        _condition!(C0, d0, K.intra, Mp)
    end
    states = [_SelState(K.base_gap, collect(1:K.nb), C0, d0)]
    front = Dict{Int,Tuple{Float64,Vector{Int}}}(K.nb => (K.base_gap, collect(1:K.nb)))
    for k in (K.nb-1):-1:1
        cands = Dict{Vector{Int},Tuple{Float64,Int,Vector{Int}}}()
        for (p, st) in enumerate(states)
            for (a, b) in _candidate_pairs(pairs, st.alpha)
                N = _bridge_rows(K, st.alpha, a, b)
                dg, off, _ = _quadpinv(st.C[N, N], st.d[N], K.tol)
                (off > INCONSISTENT || !isfinite(dg)) && continue
                child = _merge(st.alpha, a, b)
                g = st.gamma + dg
                (!haskey(cands, child) || g < cands[child][1]) && (cands[child] = (g, p, N))
            end
        end
        isempty(cands) && break
        best = first(sort!(collect(cands); by = kv -> (kv[2][1], kv[1])), beam)
        newstates = _SelState[]
        for (child, (g, p, N)) in best
            st = states[p]
            C = copy(st.C); d = copy(st.d)
            if !isempty(N)
                _, _, Mp = _quadpinv(C[N, N], d[N], K.tol)
                _condition!(C, d, N, Mp)
            end
            push!(newstates, _SelState(g, child, C, d))
        end
        states = newstates
        front[k] = (states[1].gamma, states[1].alpha)
    end
    return front
end

function _connected_without(nbrs, alpha, c::Int, skip::Int)
    mem = [v for v in eachindex(alpha) if alpha[v] == c && v != skip]
    isempty(mem) && return false
    seen = Set([mem[1]]); queue = [mem[1]]; head = 1
    while head <= length(queue)
        v = queue[head]; head += 1
        for u in nbrs[v]
            (u != skip && alpha[u] == c && !(u in seen)) || continue
            push!(seen, u); push!(queue, u)
        end
    end
    return length(seen) == length(mem)
end

"""Best-improvement moves of one base vertex to an adjacent team at a fixed number of teams."""
function _refine_moves(K::GapKernel, nbrs, alpha0::Vector{Int}; maxsweeps::Int = 20)
    alpha = copy(canonical_partition(alpha0))
    g = gap(K, alpha)
    for _ in 1:maxsweeps
        best = (g, 0, 0)
        for v in 1:K.nb
            a = alpha[v]
            count(==(a), alpha) == 1 && continue
            _connected_without(nbrs, alpha, a, v) || continue
            for b in unique(alpha[u] for u in nbrs[v] if alpha[u] != a)
                alpha[v] = b
                g2 = gap(K, alpha)
                alpha[v] = a
                g2 < best[1] - 1e-12 * max(1.0, abs(K.Jstar)) && (best = (g2, v, b))
            end
        end
        best[2] == 0 && break
        alpha[best[2]] = best[3]
        g = best[1]
    end
    return canonical_partition(alpha), g
end

"""Every split of the connected set `U` into two connected parts (as the part containing `minimum(U)`)."""
function _connected_bipartitions(nbrs, U::Vector{Int})
    inU = Set(U)
    v = minimum(U)
    nb(w) = [u for u in nbrs[w] if u in inU]
    function isconn(S)
        isempty(S) && return false
        Ss = Set(S); seen = Set([S[1]]); q = [S[1]]; head = 1
        while head <= length(q)
            w = q[head]; head += 1
            for u in nb(w)
                (u in Ss && !(u in seen)) && (push!(seen, u); push!(q, u))
            end
        end
        return length(seen) == length(S)
    end
    out = Vector{Vector{Int}}()
    function extend(S, ext, nbhd)
        rest = [u for u in U if !(u in S)]
        !isempty(rest) && isconn(rest) && push!(out, copy(S))
        ext = copy(ext)
        while !isempty(ext)
            w = pop!(ext)
            newn = copy(nbhd); ext2 = copy(ext)
            for u in nb(w)
                (u > v && !(u in nbhd)) && push!(ext2, u)
                push!(newn, u)
            end
            extend([S; w], ext2, newn)
        end
    end
    extend([v], [u for u in nb(v) if u > v], Set([v; nb(v)]))
    return out
end

"""Re-split the union of two adjacent teams (at most `maxsize` base vertices) in every connected way; keep the best."""
function _refine_pairs(K::GapKernel, nbrs, pairs, alpha0::Vector{Int}; maxsize::Int = 14, maxsweeps::Int = 20)
    alpha = collect(canonical_partition(alpha0))
    g = gap(K, alpha)
    for _ in 1:maxsweeps
        best = (g, Int[])
        for (a, b) in _candidate_pairs(pairs, alpha)
            U = [v for v in 1:K.nb if alpha[v] == a || alpha[v] == b]
            length(U) <= maxsize || continue
            for S in _connected_bipartitions(nbrs, U)
                trial = copy(alpha)
                Sset = Set(S)
                for u in U
                    trial[u] = u in Sset ? a : b
                end
                g2 = gap(K, trial)
                g2 < best[1] - 1e-12 * max(1.0, abs(K.Jstar)) && (best = (g2, trial))
            end
        end
        if isempty(best[2])
            a2, g2 = _refine_moves(K, nbrs, alpha; maxsweeps = maxsweeps)
            g2 < g - 1e-12 * max(1.0, abs(K.Jstar)) || break
            alpha, g = collect(a2), g2
            continue
        end
        alpha = collect(canonical_partition(best[2])); g = best[1]
    end
    return canonical_partition(alpha), g
end

"""
    select_teams(kernel[, graph]; k = nothing, budget = nothing, beam = 1, refine = :moves) -> NamedTuple

Choose a team structure by its gap (the paper's selector, Sec. IV-C), from a
`gap_kernel`: agglomerate from singletons by the least exact gap increment
(`beam` clusterings kept per level; `beam = 1` is greedy), then polish the
chosen level by local search at a fixed number of teams (`refine = :moves`,
single agents move to an adjacent team; `:pairs`, the union of two adjacent
teams is re-split in every connected way, then moves; `:none`). The paper's
selector is `beam = 8, refine = :pairs`.

Give `k` (the number of teams) or `budget` (the coarsest structure with
`gap <= budget`; for a relative budget use `eps * abs(kernel.Jstar)`).
Adjacency is the kernel's base graph (the formation graph), or the agent pairs
`graph`. Returns `teams` (labels per agent), its `gap`, `k`, and the `front`
(`Dict(k => (gap, teams))` of the search before polishing).
"""
function select_teams(K::GapKernel, graph = nothing; k = nothing, budget = nothing, beam::Integer = 1,
                      refine::Symbol = :moves, maxsize::Integer = 14)
    (k === nothing) == (budget === nothing) && throw(ArgumentError("give exactly one of k or budget"))
    refine in (:none, :moves, :pairs) || throw(ArgumentError("refine must be :none, :moves or :pairs"))
    pairs = graph === nothing ? K.bedges : [minmax(Int(a), Int(b)) for (a, b) in graph]
    nbrs = [Int[] for _ in 1:K.nb]
    for (a, b) in pairs
        push!(nbrs[a], b); push!(nbrs[b], a)
    end
    front = team_front(K; beam = beam, graph = graph)
    if k !== nothing
        haskey(front, k) || throw(ArgumentError("no connected structure with $k teams was reached"))
        kk = k
    else
        ok = [kk for (kk, (g, _)) in front if g <= budget]
        isempty(ok) && throw(ArgumentError("no structure meets the budget (the singletons have gap $(K.base_gap))"))
        kk = minimum(ok)
    end
    g, alpha = front[kk]
    if refine == :moves
        a2, g2 = _refine_moves(K, nbrs, alpha)
        g2 < g && ((g, alpha) = (g2, a2))
    elseif refine == :pairs
        a2, g2 = _refine_pairs(K, nbrs, pairs, alpha; maxsize = Int(maxsize))
        g2 < g && ((g, alpha) = (g2, a2))
    end
    return (teams = collect(alpha), gap = g, k = kk, front = front)
end
