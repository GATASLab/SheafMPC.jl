# orderings.jl: elimination orders for KKT matrices of multi-agent programs,
# and the cost model that picks one.
#
# Generic orders (work on any matrix): AMD (SuiteSparse, the order of QDLDL and
# OSQP), CliqueTrees' AMF and MMD, and METIS nested dissection when Metis.jl is
# loaded.
#
# Structure-given orders read a label per KKT index: the agent it belongs to
# and its block (time instant, or block of instants after a time pushforward).
#
#  :stage   time-major, Riccati-like: blocks in time order, each block's
#           indices that do not touch the next block first. The front is the
#           stacked state of all agents: the order of HPIPM's Riccati
#           recursion, cubic in the number of agents, best for few agents.
#  :chain   eliminate along every agent's time chain first, then the agent
#           coupling: each agent's interior (the indices coupled to no other
#           agent: velocities, inputs, dynamics rows, input rows) by AMD inside
#           the agent, which condenses the agent onto its coupling indices;
#           the coupling indices by nested dissection of the agent graph on the
#           Schur complement graph.
#  :ndL     agent-major nested dissection of the agent graph x time: vertex
#           separators of the agent graph (BFS level structures from a
#           pseudo-peripheral agent, thinned), the separator agents' coupling
#           indices as separators (their interiors as independent subtrees),
#           leaves of at most L agents ordered whole by AMD with their halo
#           (an approximation of constrained AMD). Fill close to AMD, a
#           balanced elimination tree (short critical path), so it is the
#           order for threads.
#
# The cost model computes the elimination tree and column counts of every
# candidate (about nnz(L) work each) and estimates the time of one
# factorization plus `solves` solves from the flops, nnz(L) and, with threads,
# the critical path of the tree.

"Adjacency of the symmetric matrix with upper triangle K (no diagonal), as CSC pointers and rows."
function sym_adjacency(K::SparseMatrixCSC)
    N = size(K, 1)
    cnt = zeros(Int, N + 1)
    rv = rowvals(K)
    @inbounds for c in 1:N, k in nzrange(K, c)
        r = rv[k]
        r == c && continue
        cnt[r+1] += 1; cnt[c+1] += 1
    end
    cnt[1] = 1
    for j in 1:N
        cnt[j+1] += cnt[j]
    end
    adj = Vector{Int}(undef, cnt[end] - 1)
    nxt = cnt[1:N]
    @inbounds for c in 1:N, k in nzrange(K, c)
        r = rv[k]
        r == c && continue
        adj[nxt[r]] = c; nxt[r] += 1
        adj[nxt[c]] = r; nxt[c] += 1
    end
    return cnt, adj
end

"Full symmetric pattern matrix of the graph (ptr, adj) (for the generic orderings)."
function _pattern_matrix(ptr::Vector{Int}, adj::Vector{Int})
    N = length(ptr) - 1
    # rows sorted per column
    rowval = copy(adj)
    for j in 1:N
        sort!(view(rowval, ptr[j]:(ptr[j+1]-1)))
    end
    return SparseMatrixCSC(N, N, copy(ptr), rowval, ones(length(rowval)))
end

"AMD order of the subgraph induced by `idx` in the graph (ptr, adj); returns a permutation of `idx`."
function _amd_induced(ptr::Vector{Int}, adj::Vector{Int}, idx::Vector{Int}, loc::Vector{Int})
    k = length(idx)
    k <= 2 && return copy(idx)
    @inbounds for (a, i) in enumerate(idx)
        loc[i] = a
    end
    I = Int[]; J = Int[]
    @inbounds for (a, i) in enumerate(idx), p in ptr[i]:(ptr[i+1]-1)
        b = loc[adj[p]]
        b > 0 && b != a && (push!(I, a); push!(J, b))
    end
    @inbounds for i in idx
        loc[i] = 0
    end
    isempty(I) && return copy(idx)
    M = sparse(I, J, ones(length(I)), k, k)
    M = M + sparse(1:k, 1:k, ones(k), k, k)
    p = QDLDL.amd(M)
    return idx[p]
end

"""
AMD order of `idx` computed on `idx` plus its halo (neighbours outside `idx`),
with the halo removed from the order: an approximation of constrained AMD in
which the halo is eliminated later but its degrees are seen.
"""
function _amd_halo(ptr::Vector{Int}, adj::Vector{Int}, idx::Vector{Int}, loc::Vector{Int})
    k = length(idx)
    k <= 2 && return copy(idx)
    all_ = copy(idx)
    @inbounds for (a, i) in enumerate(idx)
        loc[i] = a
    end
    @inbounds for i in idx, p in ptr[i]:(ptr[i+1]-1)
        j = adj[p]
        if loc[j] == 0
            push!(all_, j); loc[j] = length(all_)
        end
    end
    I = Int[]; J = Int[]
    @inbounds for (a, i) in enumerate(all_), p in ptr[i]:(ptr[i+1]-1)
        b = loc[adj[p]]
        b > 0 && b != a && (push!(I, a); push!(J, b))
    end
    @inbounds for i in all_
        loc[i] = 0
    end
    K = length(all_)
    isempty(I) && return copy(idx)
    M = sparse(I, J, ones(length(I)), K, K) + sparse(1:K, 1:K, ones(K), K, K)
    p = QDLDL.amd(M)
    return [all_[q] for q in p if q <= k]
end

# ---------------------------------------------------------------------------
# generic orders
# ---------------------------------------------------------------------------

order_amd(K::SparseMatrixCSC) = Vector{Int}(QDLDL.amd(K))

function order_cliquetrees(K::SparseMatrixCSC, alg)
    ptr, adj = sym_adjacency(K)
    M = _pattern_matrix(ptr, adj)
    return Vector{Int}(CliqueTrees.permutation(M; alg = alg)[1])
end

"METIS through CliqueTrees, when Metis.jl is loaded (`nothing` otherwise)."
function order_metis(K::SparseMatrixCSC)
    Base.get_extension(CliqueTrees, :MetisExt) === nothing && return nothing
    return order_cliquetrees(K, CliqueTrees.METIS())
end

# ---------------------------------------------------------------------------
# structure
# ---------------------------------------------------------------------------

"""
    KKTStructure(agent, block)

Labels of the KKT indices (variables first, then rows): `agent[i]` in 1:na
(0: shared by all agents) and `block[i]` in 1:nb (time instant or block).
"""
struct KKTStructure
    agent::Vector{Int}
    block::Vector{Int}
end

"""
    infer_structure(A, var_agent, var_block) -> KKTStructure

Row labels from the variables of each row: the agent of the row's variables
(0 if they belong to several agents) and the largest block among them (a
dynamics row defines the state of its last instant).
"""
function infer_structure(A::SparseMatrixCSC, var_agent::AbstractVector{<:Integer}, var_block::AbstractVector{<:Integer})
    m, n = size(A)
    ra = fill(-1, m); rb = zeros(Int, m)
    rv = rowvals(A)
    @inbounds for j in 1:n, k in nzrange(A, j)
        i = rv[k]
        a = var_agent[j]
        ra[i] = ra[i] == -1 ? a : (ra[i] == a ? a : 0)
        rb[i] = max(rb[i], var_block[j])
    end
    @inbounds for i in 1:m
        ra[i] == -1 && (ra[i] = 0)
    end
    return KKTStructure([Vector{Int}(var_agent); ra], [Vector{Int}(var_block); rb])
end

"Time-major (Riccati-like) order."
function order_time(K::SparseMatrixCSC, st::KKTStructure)
    N = size(K, 1)
    ptr, adj = sym_adjacency(K)
    blk = st.block
    nb = maximum(blk)
    byblk = [Int[] for _ in 1:nb+1]
    for i in 1:N
        push!(byblk[blk[i] + 1], i)            # block 0 (unlabelled) first
    end
    loc = zeros(Int, N)
    perm = Int[]
    for b in 0:nb
        idx = byblk[b+1]
        isempty(idx) && continue
        inner = Int[]; outer = Int[]
        for i in idx
            touches = false
            for p in ptr[i]:(ptr[i+1]-1)
                blk[adj[p]] > b && (touches = true; break)
            end
            push!(touches ? outer : inner, i)
        end
        append!(perm, _amd_induced(ptr, adj, inner, loc))
        append!(perm, _amd_induced(ptr, adj, outer, loc))
    end
    return perm
end

# nested dissection tree of the agent graph: nodes with an agent set (the
# separator, or the whole set at a leaf) and children
struct _NDNode
    agents::Vector{Int}
    children::Vector{Int}
end

function _bfs_levels(gptr, gadj, set::Vector{Int}, inset::Vector{Int}, tag::Int, src::Int, lev::Vector{Int})
    for a in set
        lev[a] = -1
    end
    lev[src] = 0
    q = [src]; h = 1
    while h <= length(q)
        a = q[h]; h += 1
        for p in gptr[a]:(gptr[a+1]-1)
            b = gadj[p]
            if inset[b] == tag && lev[b] < 0
                lev[b] = lev[a] + 1; push!(q, b)
            end
        end
    end
    return q
end

"""
Nested dissection of the agent graph (gptr, gadj) with vertex weights `wt`:
recursive bisection by the best level of a BFS level structure from a
pseudo-peripheral agent. Sets of at most `leaf` agents are leaves.
"""
function _agent_nd(gptr::Vector{Int}, gadj::Vector{Int}, wt::Vector{Float64}, na::Int; leaf::Int = 1)
    nodes = _NDNode[]
    inset = zeros(Int, na); lev = zeros(Int, na)
    tagc = Ref(0)
    function build(set::Vector{Int})
        if length(set) <= leaf
            push!(nodes, _NDNode(set, Int[])); return length(nodes)
        end
        tagc[] += 1; tag = tagc[]
        for a in set
            inset[a] = tag
        end
        # connected components
        q = _bfs_levels(gptr, gadj, set, inset, tag, set[1], lev)
        if length(q) < length(set)
            comps = Vector{Int}[]
            seen = falses(na)
            for a in set
                seen[a] && continue
                tagc[] += 1; t2 = tagc[]
                for b in set
                    inset[b] = t2
                end
                qa = _bfs_levels(gptr, gadj, set, inset, t2, a, lev)
                for b in qa
                    seen[b] = true
                end
                push!(comps, sort(qa))
            end
            ch = [build(c) for c in comps]
            push!(nodes, _NDNode(Int[], ch)); return length(nodes)
        end
        # pseudo-peripheral source: two sweeps
        src = q[end]
        for _ in 1:2
            q = _bfs_levels(gptr, gadj, set, inset, tag, src, lev)
            src = q[end]
        end
        q = _bfs_levels(gptr, gadj, set, inset, tag, src, lev)
        L = lev[q[end]]
        if L < 2
            push!(nodes, _NDNode(set, Int[])); return length(nodes)
        end
        lw = zeros(L + 1)
        for a in set
            lw[lev[a]+1] += wt[a]
        end
        tot = sum(lw)
        best = -1; bestc = Inf; cum = 0.0
        for l in 1:(L-1)                       # separator level l (0-based), both sides non-empty
            cum += lw[l]
            left = cum; right = tot - cum - lw[l+1]
            imb = max(left, right) / max(min(left, right), 1e-12)
            c = lw[l+1] * (1 + 0.25 * max(imb - 1.0, 0.0))
            if c < bestc
                bestc = c; best = l
            end
        end
        sep = [a for a in set if lev[a] == best]
        A1 = [a for a in set if lev[a] < best]
        A2 = [a for a in set if lev[a] > best]
        # thin the separator: an agent with no neighbour in A2 can join A1
        for a in A2
            inset[a] = -tag
        end
        keep = Int[]
        for a in sep
            hasA2 = false
            for p in gptr[a]:(gptr[a+1]-1)
                inset[gadj[p]] == -tag && (hasA2 = true; break)
            end
            hasA2 ? push!(keep, a) : push!(A1, a)
        end
        sep = keep
        c1 = build(sort(A1)); c2 = build(sort(A2))
        push!(nodes, _NDNode(sep, [c1, c2])); return length(nodes)
    end
    root = build(collect(1:na))
    return nodes, root
end

"""
    order_agent_nd(K, st; leaf = 1) -> perm

Agent-major nested dissection (see the file header).
"""
function order_agent_nd(K::SparseMatrixCSC, st::KKTStructure; leaf::Int = 1, leaf_amd::Bool = true)
    N = size(K, 1)
    ptr, adj = sym_adjacency(K)
    ag = st.agent
    na = maximum(ag)
    na <= 1 && return order_amd(K)
    # boundary indices: coupled to another agent (or shared, agent 0)
    bnd = falses(N)
    @inbounds for i in 1:N
        ag[i] == 0 && (bnd[i] = true; continue)
        for p in ptr[i]:(ptr[i+1]-1)
            if ag[adj[p]] != ag[i]
                bnd[i] = true; break
            end
        end
    end
    # agent graph and boundary weights
    E = Set{Tuple{Int,Int}}()
    wt = zeros(na)
    @inbounds for i in 1:N
        a = ag[i]
        a == 0 && continue
        bnd[i] && (wt[a] += 1)
        for p in ptr[i]:(ptr[i+1]-1)
            b = ag[adj[p]]
            b != 0 && b != a && push!(E, (min(a, b), max(a, b)))
        end
    end
    gcnt = zeros(Int, na + 1)
    for (a, b) in E
        gcnt[a+1] += 1; gcnt[b+1] += 1
    end
    gcnt[1] = 1
    for a in 1:na
        gcnt[a+1] += gcnt[a]
    end
    gadj = Vector{Int}(undef, gcnt[end] - 1); gn = gcnt[1:na]
    for (a, b) in E
        gadj[gn[a]] = b; gn[a] += 1
        gadj[gn[b]] = a; gn[b] += 1
    end
    # per agent: interior and boundary indices; Schur complement graph on the
    # boundary: original boundary edges plus a clique on the boundary
    # neighbourhood of every connected component of an agent's interior
    interior = [Int[] for _ in 1:na]; boundary = [Int[] for _ in 1:na]
    shared = Int[]
    for i in 1:N
        a = ag[i]
        if a == 0
            push!(shared, i)
        elseif bnd[i]
            push!(boundary[a], i)
        else
            push!(interior[a], i)
        end
    end
    SI = Int[]; SJ = Int[]
    @inbounds for i in 1:N
        bnd[i] || continue
        for p in ptr[i]:(ptr[i+1]-1)
            j = adj[p]
            bnd[j] && (push!(SI, i); push!(SJ, j))
        end
    end
    seen = falses(N); mark = zeros(Int, N); stamp = 0
    q = Int[]; nb = Int[]
    for a in 1:na, i0 in interior[a]
        seen[i0] && continue
        empty!(q); push!(q, i0); seen[i0] = true; h = 1
        stamp += 1; empty!(nb)
        while h <= length(q)
            i = q[h]; h += 1
            for p in ptr[i]:(ptr[i+1]-1)
                j = adj[p]
                if bnd[j]
                    mark[j] != stamp && (mark[j] = stamp; push!(nb, j))
                elseif !seen[j]
                    seen[j] = true; push!(q, j)
                end
            end
        end
        for x in nb, y in nb
            x != y && (push!(SI, x); push!(SJ, y))
        end
    end
    Sg = sparse(SI, SJ, trues(length(SI)), N, N)
    sptr = Sg.colptr; sadj = Sg.rowval
    nodes, root = _agent_nd(gcnt, gadj, wt, na; leaf = leaf)
    loc = zeros(Int, N)
    perm = Int[]
    isleaf = [isempty(nd.children) for nd in nodes]
    function emit(k)
        nd = nodes[k]
        for c in nd.children
            emit(c)
        end
        if isleaf[k] && leaf_amd
            # a leaf: all its indices by AMD on the leaf plus its halo (the
            # indices adjacent to it, ordered later), the halo dropped
            idx = Int[]
            for a in nd.agents
                append!(idx, interior[a]); append!(idx, boundary[a])
            end
            append!(perm, _amd_halo(ptr, adj, idx, loc))
            return
        end
        for a in nd.agents
            append!(perm, _amd_induced(ptr, adj, interior[a], loc))
        end
        bidx = Int[]
        for a in nd.agents
            append!(bidx, boundary[a])
        end
        append!(perm, _amd_induced(sptr, sadj, bidx, loc))
    end
    emit(root)
    append!(perm, shared)
    length(perm) == N || error("agent ND order covers $(length(perm)) of $N indices")
    return perm
end

# ---------------------------------------------------------------------------
# cost model
# ---------------------------------------------------------------------------

"""
    CostModel(; factors, solves, nthreads, coefficients)

Estimated time of `factors` numeric factorizations plus `solves` solves with
an elimination order, for the two engines:

* `:simplicial` (QDLDL, up-looking, column by column):
  factor `q[1] N + q[2] flops`, solve `q[3] N + q[4] nnz(L)`;
* `:multifrontal` (BlockLDL): factor `b[1] N + b[2] flops`, solve
  `b[3] N + b[4] nnz(L)`; with threads the flops term is
  `max(flops / nthreads, critical path)` and the solve term likewise.

The coefficients are least-squares fits (seconds per unit) to measured times on
the fleet KKT matrices (bench/kkt_calibrate.jl, AMD EPYC 7702, one thread).
Defaults: 4 factorizations (setup, a rho update, two polish attempts) and 60
solves (ADMM iterations and polish refinement) per cold solve.
"""
Base.@kwdef struct CostModel
    factors::Float64 = 4.0
    solves::Float64 = 60.0
    nthreads::Int = 1
    q::NTuple{4,Float64} = (QCOEF[1], QCOEF[2], QCOEF[3], QCOEF[4])
    b::NTuple{4,Float64} = (BCOEF[1], BCOEF[2], BCOEF[3], BCOEF[4])
    par_overhead::NTuple{2,Float64} = (1.5e-4, 1e-4)   # task start-up per threaded factor / solve (s), EPYC 7702
end

# fitted coefficients (seconds per column, per flop, per column, per entry of L);
# BlockLDL refitted after the blocked Schur updates and light relaxation
# (bench/kkt_calibrate.jl, relative least squares, scaled by the QDLDL times of
# the same run against the original fit to remove the node's load)
const QCOEF = (2.63e-8, 1.20e-9, 1.92e-9, 1.85e-9)
const BCOEF = (6.84e-8, 2.46e-10, 1.07e-8, 7.50e-10)

function estimate(cm::CostModel, s, N::Int, engine::Symbol)
    if engine == :simplicial
        c = cm.q
        tf = c[1] * N + c[2] * s.flops
        ts = c[3] * N + c[4] * s.nnzL
    else
        c = cm.b
        nt = cm.nthreads
        par = nt > 1 ? max(1 / nt, s.critical / max(s.flops, 1.0)) : 1.0
        tf = c[1] * N * (nt > 1 ? par : 1.0) + c[2] * s.flops * par
        ts = (c[3] * N + c[4] * s.nnzL) * (nt > 1 ? par : 1.0)
        if nt > 1
            tf += cm.par_overhead[1]
            # solves stay sequential below PAR_SOLVE_NNZ
            s.nnzL < PAR_SOLVE_NNZ[] ? (ts = (c[3] * N + c[4] * s.nnzL)) : (ts += cm.par_overhead[2])
        end
    end
    return cm.factors * tf + cm.solves * ts
end

"""
nnz(L), flops and the critical path (flops along the heaviest root-to-leaf
path) of an order; with `nthreads > 1` the flops of columns with at least
`blas_cols` entries (dense fronts, where BLAS runs threaded) count `1 / nthreads`
on the path.
"""
function order_stats(K::SparseMatrixCSC, perm::AbstractVector{<:Integer}; nthreads::Int = 1, blas_cols::Int = 96)
    N = size(K, 1)
    iperm = invperm(perm)
    colptr, rowval, _ = _permuted_upper(K, iperm)
    parent = _etree(N, colptr, rowval)
    cc = _colcounts(N, parent, colptr, rowval)
    fl = 0.0
    cp = zeros(N)
    @inbounds for j in 1:N
        f = cc[j] * (cc[j] + 1) / 2 + 1
        fl += f
        cp[j] += cc[j] >= blas_cols ? f / nthreads : f
        p = parent[j]
        p > 0 && (cp[p] = max(cp[p], cp[j]))
    end
    crit = 0.0
    @inbounds for j in 1:N
        parent[j] == 0 && (crit = max(crit, cp[j]))
    end
    return (nnzL = N + sum(cc), flops = fl, critical = crit, tree = (iperm = iperm, parent = parent, cc = cc))
end

"""
    choose_ordering(K; structure = nothing, candidates = :auto, cost = CostModel()) -> (perm, name, table)

Order candidates for `K` and keep the one of least estimated cost. `table`
lists every candidate's statistics and estimate. `candidates` is `:auto` or a
list among `:amd, :amf, :mmd, :metis, :stage, :chain, :nd2, :nd4, :nd8, :nd16`.
"""
function choose_ordering(K::SparseMatrixCSC; structure::Union{Nothing,KKTStructure} = nothing,
                         candidates = :auto, cost::CostModel = CostModel(), engines = (:multifrontal,))
    best, name, _, table, _, _ = choose_system(K; structure = structure, candidates = candidates, cost = cost, engines = engines)
    return best, name, table
end

"""
    choose_system(K; structure, candidates, cost, engines) -> (perm, ordering, engine, table, tree, threads)

With `cost.nthreads > 1` every candidate is also estimated on one thread
(thread start-up costs more than it saves on small systems); `threads` is the
count to use.

The order and the engine (`:simplicial` or `:multifrontal`) of least estimated
cost. Generic candidates `:amd, :amf, :mmd` (`:metis` on request, with Metis.jl loaded),
with `structure` also the structure-given ones; the time-major `:stage` and
`:chain` orders only for few agents (their fronts grow with the agent count).
"""
function choose_system(K::SparseMatrixCSC; structure::Union{Nothing,KKTStructure} = nothing,
                       candidates = :auto, cost::CostModel = CostModel(), engines = (:simplicial, :multifrontal))
    N = size(K, 1)
    if candidates === :auto
        # MMD only at moderate sizes (its time grows faster than AMD's)
        cands = nnz(K) <= 200_000 ? [:amd, :amf, :mmd] : [:amd, :amf]
        # METIS is not a default candidate: on these KKTs it pivots on primal
        # variables with only sigma on the diagonal before their dynamics rows
        # (residuals 1e-10 before refinement, against 1e-14 for AMD)
        # structure-given orders when threads can use their balanced trees
        # (one thread: they are within a few percent of AMD in fill, and cost
        # more to compute)
        if structure !== nothing && cost.nthreads > 1
            na = maximum(structure.agent)
            na <= 8 && push!(cands, :stage)
            na > 1 && push!(cands, :nd4, :nd16)
        end
    else
        cands = collect(candidates)
    end
    best = nothing; bestc = Inf; name = :none; eng = :multifrontal; besttree = nothing; bestnt = 1
    table = Any[]
    cost1 = CostModel(cost.factors, cost.solves, 1, cost.q, cost.b, cost.par_overhead)
    for c in cands
        t = @elapsed p = make_ordering(K, c; structure = structure)
        p === nothing && continue
        s = order_stats(K, p; nthreads = cost.nthreads)
        for e in engines, nt in unique((1, cost.nthreads))
            (e == :simplicial && nt > 1) && continue
            est = estimate(nt == 1 ? cost1 : cost, s, N, e)
            # at equal fill, QDLDL runs measurably faster on MMD orders (their
            # locality: calibration data, solves up to 1.7x on small systems)
            (e == :simplicial && c == :mmd) && (est *= 0.9)
            push!(table, (name = c, engine = e, threads = nt, nnzL = s.nnzL, flops = s.flops, critical = s.critical,
                          est = est, time = t))
            if est < bestc
                bestc = est; best = p; name = c; eng = e; besttree = s.tree; bestnt = nt
            end
        end
    end
    return best, name, eng, table, besttree, bestnt
end

function make_ordering(K::SparseMatrixCSC, c::Symbol; structure::Union{Nothing,KKTStructure} = nothing)
    c == :amd && return order_amd(K)
    c == :amf && return order_cliquetrees(K, CliqueTrees.AMF())
    c == :mmd && return order_cliquetrees(K, CliqueTrees.MMD())
    c == :metis && return order_metis(K)
    structure === nothing && return nothing
    c == :stage && return order_time(K, structure)
    c == :chain && return order_agent_nd(K, structure; leaf = 1, leaf_amd = false)
    c == :nd2 && return order_agent_nd(K, structure; leaf = 2)
    c == :nd4 && return order_agent_nd(K, structure; leaf = 4)
    c == :nd8 && return order_agent_nd(K, structure; leaf = 8)
    c == :nd16 && return order_agent_nd(K, structure; leaf = 16)
    throw(ArgumentError("unknown ordering $c"))
end
