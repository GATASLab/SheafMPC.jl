# symbolic.jl: the symbolic factorization of a symmetric matrix under a given
# elimination order, in supernodal form.
#
# Input: the upper triangle of K (CSC, every diagonal entry stored) and a
# permutation `perm` (new index -> old index). Steps:
#   1. elimination tree of K[perm, perm] (Liu's algorithm with path compression),
#   2. a postorder of the tree, composed into the permutation (the fill is
#      unchanged, but every subtree becomes a contiguous range of columns),
#   3. column counts of L by row subtrees (each row of L is a subtree of the
#      elimination tree; walking it costs nnz(L) in total),
#   4. fundamental supernodes, then relaxed amalgamation of a supernode with its
#      parent when the explicit zeros this adds stay small (the rules of
#      CHOLMOD's supernodal analysis),
#   5. the row structure below every supernode, the relative indices of each
#      supernode's rows in its parent's frontal matrix (the extend-add maps),
#      the storage layout of L and the map from the stored entries of K to it,
#   6. the offsets of the update matrices on the multifrontal stack.
#
# Storage of L: supernode s with w columns and r rows below has a dense
# column-major block of h = w + r rows and w columns; its first w rows hold the
# unit lower triangle of the diagonal block (upper part unused), the last r rows
# the off-diagonal block L21. The diagonal D is a separate vector.

"Packed per-supernode data of the solve sweeps: first column - 1, width, rows below, offset in str_idx, offset in Lx."
struct SNode
    fo::Int32
    w::Int32
    r::Int32
    rb::Int32
    o::Int64
end

"""
    Symbolic

The supernodal symbolic factorization: permutation, supernode partition and
tree, row structures, the extend-add maps, the layout of L, the assembly map
from `K.nzval`, update-matrix offsets and the operation counts (`nnzL`,
`flops`, `solve_flops`).
"""
struct Symbolic
    N::Int
    perm::Vector{Int}            # new -> old
    iperm::Vector{Int}           # old -> new
    nsup::Int
    sup_ptr::Vector{Int}         # columns of supernode s: sup_ptr[s]:sup_ptr[s+1]-1
    sup_of::Vector{Int}          # column (new index) -> supernode
    parent::Vector{Int}          # supernode tree, 0 at a root
    child_ptr::Vector{Int}       # children of s: child_idx[child_ptr[s]:child_ptr[s+1]-1]
    child_idx::Vector{Int}
    str_ptr::Vector{Int}         # rows below s: str_idx[str_ptr[s]:str_ptr[s+1]-1] (sorted, new indices)
    str_idx::Vector{Int}
    rel_idx::Vector{Int}         # same layout: position of each row in the parent's front (1-based)
    lx_ptr::Vector{Int}          # block of s starts at Lx[lx_ptr[s]]
    nlx::Int
    upd_off::Vector{Int}         # update matrix of s at U[upd_off[s] .+ (1:r^2)] (sequential stack)
    nupd::Int
    max_front::Int               # largest h
    max_r::Int
    amap::Vector{Int}            # K.nzval[k] goes to Lx[amap[k]]
    signs::Vector{Float64}       # expected sign of every pivot (new index)
    nnzL::Int                    # stored entries of L including the unit diagonal (with relaxed zeros)
    nnzL_exact::Int              # entries of the exact (fundamental) pattern
    flops::Float64               # multiply-adds of the numeric factorization (frontal updates)
    solve_flops::Float64         # multiply-adds of one forward plus one backward solve
    sidx::Vector{Int32}          # str_idx in 32 bits (the solves)
    nleaf::Int                   # columns 1:nleaf are leaf pivots (one neighbour, eliminated first)
    leaf_par::Vector{Int32}      # the neighbour (parent column) of every leaf
    leaf_dpos::Vector{Int}       # position in Lx of the parent's diagonal entry
    snd::Vector{SNode}           # packed supernode descriptors
end

# ---------------------------------------------------------------------------
# elimination tree, postorder, column counts
# ---------------------------------------------------------------------------

"Upper triangle pattern of K[perm, perm] without the diagonal: column j holds rows i < j."
function _permuted_upper(K::SparseMatrixCSC, iperm::Vector{Int})
    N = size(K, 1)
    cnt = zeros(Int, N + 1)
    rv = rowvals(K)
    @inbounds for c in 1:N, k in nzrange(K, c)
        r = rv[k]
        r == c && continue
        a = iperm[r]; b = iperm[c]
        cnt[max(a, b) + 1] += 1
    end
    cnt[1] = 1
    @inbounds for j in 1:N
        cnt[j+1] += cnt[j]
    end
    colptr = copy(cnt)
    rowval = Vector{Int}(undef, colptr[end] - 1)
    nzsrc = Vector{Int}(undef, colptr[end] - 1)
    next = colptr[1:N]
    @inbounds for c in 1:N, k in nzrange(K, c)
        r = rv[k]
        r == c && continue
        a = iperm[r]; b = iperm[c]
        col = max(a, b)
        p = next[col]; next[col] = p + 1
        rowval[p] = min(a, b); nzsrc[p] = k
    end
    return colptr, rowval, nzsrc
end

function _etree(N::Int, colptr::Vector{Int}, rowval::Vector{Int})
    parent = zeros(Int, N)
    anc = zeros(Int, N)
    @inbounds for k in 1:N
        for p in colptr[k]:(colptr[k+1]-1)
            i = rowval[p]
            while i != 0 && i < k
                inext = anc[i]
                anc[i] = k
                if inext == 0
                    parent[i] = k
                end
                i = inext
            end
        end
    end
    return parent
end

"Postorder of a forest given by `parent` (children visited in increasing order)."
function _postorder(parent::Vector{Int})
    N = length(parent)
    head = zeros(Int, N); next = zeros(Int, N)
    @inbounds for j in N:-1:1
        p = parent[j]
        p == 0 && continue
        next[j] = head[p]; head[p] = j
    end
    post = Vector{Int}(undef, N)
    stack = Vector{Int}(undef, N)
    k = 0
    @inbounds for j in 1:N
        parent[j] == 0 || continue
        top = 1; stack[1] = j
        while top > 0
            p = stack[top]
            i = head[p]
            if i == 0
                top -= 1
                k += 1; post[k] = p
            else
                head[p] = next[i]
                top += 1; stack[top] = i
            end
        end
    end
    return post
end

"Off-diagonal entries of every column of L, by walking the row subtrees."
function _colcounts(N::Int, parent::Vector{Int}, colptr::Vector{Int}, rowval::Vector{Int})
    cc = zeros(Int, N)
    mark = zeros(Int, N)
    @inbounds for k in 1:N
        mark[k] = k
        for p in colptr[k]:(colptr[k+1]-1)
            i = rowval[p]
            while i != 0 && mark[i] != k
                cc[i] += 1
                mark[i] = k
                i = parent[i]
            end
        end
    end
    return cc
end

# ---------------------------------------------------------------------------
# supernodes
# ---------------------------------------------------------------------------

"""
Relaxation parameters (CHOLMOD's defaults): a child is merged into its parent
when the merged supernode has at most `nrelax[1]` columns, or at most
`nrelax[2]` columns and a fraction of explicit zeros below `zrelax[1]`, or at
most `nrelax[3]` columns and zeros below `zrelax[2]`, or zeros below
`zrelax[3]`.
"""
Base.@kwdef struct Relax
    nrelax::NTuple{3,Int} = (4, 16, 48)
    zrelax::NTuple{3,Float64} = (0.8, 0.1, 0.05)
    maxcols::Int = 256           # never merge beyond this many columns
    maximal::Bool = true         # maximal (not only fundamental) supernodes before relaxation
end

"No relaxation: exact (maximal) supernodes, no explicit zeros."
const EXACT = Relax(nrelax = (0, 0, 0), zrelax = (0.0, 0.0, 0.0))
"Light relaxation for solve-dominated use: few explicit zeros."
const LIGHT = Relax(nrelax = (2, 8, 32), zrelax = (0.3, 0.05, 0.02))

"Fundamental supernodes of a postordered tree: start column of each, then the amalgamated partition."
function _supernodes(N::Int, parent::Vector{Int}, cc::Vector{Int}, relax::Relax, nleaf::Int = 0)
    nchild = zeros(Int, N)
    @inbounds for j in 1:N
        p = parent[j]
        p > 0 && (nchild[p] += 1)
    end
    # maximal supernodes: column j-1 joins j when its structure is {j} and
    # the structure of j (no explicit zeros; j may have other children, which
    # precede j-1 in the postorder)
    starts = Int[1]
    @inbounds for j in 2:N
        if j <= nleaf + 1 || !(parent[j-1] == j && cc[j-1] == cc[j] + 1 && (relax.maximal || nchild[j] == 1))
            push!(starts, j)
        end
    end
    ns = length(starts)
    push!(starts, N + 1)
    sof = Vector{Int}(undef, N)
    @inbounds for s in 1:ns, j in starts[s]:(starts[s+1]-1)
        sof[j] = s
    end
    spar = zeros(Int, ns)
    @inbounds for s in 1:ns
        l = starts[s+1] - 1
        p = parent[l]
        spar[s] = p == 0 ? 0 : sof[p]
    end
    # per supernode: columns w, rows below r, stored entries tot, zeros z
    w = [starts[s+1] - starts[s] for s in 1:ns]
    r = [cc[starts[s+1]-1] for s in 1:ns]
    tot = [w[s] * (w[s] + 1) ÷ 2 + w[s] * r[s] for s in 1:ns]
    z = zeros(Int, ns)
    # relaxed amalgamation: supernode s is merged into s+1 when s is the last
    # child of s+1 (contiguous in the postorder) and the rules allow it; the
    # group of s+1 then carries the merged statistics
    merged_into_next = falses(ns)
    nr1, nr2, nr3 = relax.nrelax
    zr1, zr2, zr3 = relax.zrelax
    @inbounds for s in (nleaf+1):(ns-1)
        spar[s] == s + 1 || continue
        p = s + 1
        wm = w[s] + w[p]
        wm <= relax.maxcols || continue
        totm = wm * (wm + 1) ÷ 2 + wm * r[p]
        zm = z[s] + z[p] + (totm - tot[s] - tot[p])
        zf = zm / totm
        ok = wm <= nr1 || (wm <= nr2 && zf < zr1) || (wm <= nr3 && zf < zr2) || zf < zr3
        if ok
            merged_into_next[s] = true
            w[p] = wm; tot[p] = totm; z[p] = zm
        end
    end
    newstarts = Int[]
    s = 1
    while s <= ns
        push!(newstarts, starts[s])
        while s <= ns && merged_into_next[s]
            s += 1
        end
        s += 1
    end
    push!(newstarts, N + 1)
    return newstarts
end

# ---------------------------------------------------------------------------
# the full symbolic factorization
# ---------------------------------------------------------------------------

"Elimination tree and column counts of an order: `(iperm, parent, cc)` (reused by `symbolic` from the cost model)."
function etree_counts(K::SparseMatrixCSC, perm::AbstractVector{<:Integer})
    N = size(K, 1)
    iperm = invperm(perm)
    colptr, rowval, _ = _permuted_upper(K, iperm)
    parent = _etree(N, colptr, rowval)
    cc = _colcounts(N, parent, colptr, rowval)
    return (iperm = iperm, parent = parent, cc = cc)
end

"""
    symbolic(K, perm, signs_old; relax = Relax()) -> Symbolic

Supernodal symbolic factorization of the symmetric matrix with upper triangle
`K` (CSC, all diagonal entries stored) in the elimination order `perm` (new ->
old), postordered. `signs_old[i]` is the sign the pivot of row `i` must have
(+1 or -1; quasi-definite matrices have known pivot signs).
"""
function symbolic(K::SparseMatrixCSC, perm0::AbstractVector{<:Integer}, signs_old::AbstractVector{<:Real};
                  relax::Relax = Relax(), leaves::Bool = true, tree = nothing)
    N = size(K, 1)
    perm1 = Vector{Int}(perm0)
    tr = tree === nothing ? etree_counts(K, perm1) : tree
    parent1 = tr.parent; cc1 = tr.cc
    # the postorder, with the leaf pivots (one neighbour in the graph: a column
    # of L with one off-diagonal entry and no children) moved first, is a
    # topological order of the same elimination tree: the tree and the column
    # counts are relabelled, not recomputed, and neither the fill nor the
    # factor changes; the leaves are then handled by a vectorized pass
    post = _postorder(parent1)
    nleaf = 0
    if leaves
        haschild = falses(N)
        @inbounds for j in 1:N
            parent1[j] > 0 && (haschild[parent1[j]] = true)
        end
        order = Vector{Int}(undef, N)
        @inbounds for j in post
            (cc1[j] == 1 && !haschild[j]) && (nleaf += 1; order[nleaf] = j)
        end
        k = nleaf
        @inbounds for j in post
            (cc1[j] == 1 && !haschild[j]) || (k += 1; order[k] = j)
        end
    else
        order = post
    end
    newidx = invperm(order)                 # old (perm1) position -> new position
    perm = perm1[order]
    iperm = invperm(perm)
    parent = zeros(Int, N); cc = Vector{Int}(undef, N)
    @inbounds for j in 1:N
        nj = newidx[j]
        parent[nj] = parent1[j] == 0 ? 0 : newidx[parent1[j]]
        cc[nj] = cc1[j]
    end
    colptr, rowval, nzsrc = _permuted_upper(K, iperm)
    nnzL_exact = N + sum(cc)
    starts = _supernodes(N, parent, cc, relax, nleaf)
    ns = length(starts) - 1
    sof = Vector{Int}(undef, N)
    @inbounds for s in 1:ns, j in starts[s]:(starts[s+1]-1)
        sof[j] = s
    end
    spar = zeros(Int, ns)
    @inbounds for s in 1:ns
        p = parent[starts[s+1]-1]
        spar[s] = p == 0 ? 0 : sof[p]
    end
    # children lists
    nch = zeros(Int, ns + 1)
    @inbounds for s in (nleaf+1):ns
        spar[s] > 0 && (nch[spar[s]+1] += 1)
    end
    child_ptr = cumsum([1; nch[2:end]])
    child_idx = Vector{Int}(undef, child_ptr[end] - 1)
    fillp = copy(child_ptr)
    @inbounds for s in (nleaf+1):ns
        p = spar[s]
        p == 0 && continue
        child_idx[fillp[p]] = s; fillp[p] += 1
    end
    # lower pattern by columns (rows > col): transpose of the permuted upper pattern
    lcnt = zeros(Int, N + 1)
    @inbounds for j in 1:N, p in colptr[j]:(colptr[j+1]-1)
        lcnt[rowval[p]+1] += 1
    end
    lcnt[1] = 1
    for j in 1:N
        lcnt[j+1] += lcnt[j]
    end
    lrow = Vector{Int}(undef, lcnt[end] - 1)
    lsrc = Vector{Int}(undef, lcnt[end] - 1)
    lnext = lcnt[1:N]
    @inbounds for j in 1:N, p in colptr[j]:(colptr[j+1]-1)
        i = rowval[p]                   # entry (j, i) of the lower triangle, j > i
        q = lnext[i]; lnext[i] = q + 1
        lrow[q] = j; lsrc[q] = nzsrc[p]
    end
    # row structures (postorder: children first)
    str_ptr = Vector{Int}(undef, ns + 1)
    str_ptr[1] = 1
    str_idx = Int[]
    mark = zeros(Int, N)
    buf = Int[]
    @inbounds for s in 1:ns
        f = starts[s]; l = starts[s+1] - 1
        empty!(buf)
        for j in f:l, p in lcnt[j]:(lcnt[j+1]-1)
            i = lrow[p]
            if i > l && mark[i] != s
                mark[i] = s; push!(buf, i)
            end
        end
        for c in child_ptr[s]:(child_ptr[s+1]-1)
            ch = child_idx[c]
            for p in str_ptr[ch]:(str_ptr[ch+1]-1)
                i = str_idx[p]
                if i > l && mark[i] != s
                    mark[i] = s; push!(buf, i)
                end
            end
        end
        sort!(buf)
        append!(str_idx, buf)
        str_ptr[s+1] = length(str_idx) + 1
    end
    # relative indices into the parent's front, storage layout, update stack
    rel_idx = zeros(Int, length(str_idx))
    pos = zeros(Int, N)
    lx_ptr = Vector{Int}(undef, ns + 1)
    lx_ptr[1] = 1
    nnzL = 0; flops = 0.0; sflops = 0.0
    max_front = 0; max_r = 0
    @inbounds for s in 1:ns
        f = starts[s]; l = starts[s+1] - 1
        w = l - f + 1; r = str_ptr[s+1] - str_ptr[s]
        h = w + r
        lx_ptr[s+1] = lx_ptr[s] + h * w
        nnzL += w * (w + 1) ÷ 2 + w * r
        # frontal LDLt of the w columns plus the update of the r x r block
        for k in 1:w
            rem = h - k
            flops += rem * (rem + 1) / 2
        end
        sflops += 2.0 * (w * (w - 1) / 2 + w * r)
        max_front = max(max_front, h); max_r = max(max_r, r)
    end
    @inbounds for p in 1:ns
        f = starts[p]; l = starts[p+1] - 1
        w = l - f + 1
        for j in f:l
            pos[j] = j - f + 1
        end
        for (k, q) in enumerate(str_ptr[p]:(str_ptr[p+1]-1))
            pos[str_idx[q]] = w + k
        end
        for c in child_ptr[p]:(child_ptr[p+1]-1)
            ch = child_idx[c]
            for q in str_ptr[ch]:(str_ptr[ch+1]-1)
                rel_idx[q] = pos[str_idx[q]]
            end
        end
    end
    # update matrices on a stack in postorder: the children of s are the top
    # entries when s is factored; the update of s replaces them
    upd_off = zeros(Int, ns)
    top = 0; peak = 0
    stk = Int[]
    @inbounds for s in (nleaf+1):ns
        nc = child_ptr[s+1] - child_ptr[s]
        base = top
        for _ in 1:nc
            c = pop!(stk)
            base = upd_off[c]
        end
        r = str_ptr[s+1] - str_ptr[s]
        if spar[s] != 0 && r > 0
            upd_off[s] = base
            top = base + r * r
            push!(stk, s)
        else
            top = base
            if spar[s] != 0
                upd_off[s] = base
                push!(stk, s)
            end
        end
        peak = max(peak, top)
    end
    # assembly map of the stored entries of K: the diagonal directly, the
    # entries below it supernode by supernode through a scatter of positions
    amap = zeros(Int, nnz(K))
    rv = rowvals(K)
    @inbounds for c in 1:N, k in nzrange(K, c)
        if rv[k] == c
            jn = iperm[c]; s = sof[jn]; f = starts[s]
            h = (starts[s+1] - f) + (str_ptr[s+1] - str_ptr[s])
            amap[k] = lx_ptr[s] + (jn - f) * h + (jn - f)
        end
    end
    @inbounds for s in 1:ns
        f = starts[s]; l = starts[s+1] - 1
        w = l - f + 1; h = w + str_ptr[s+1] - str_ptr[s]
        for (kq, q) in enumerate(str_ptr[s]:(str_ptr[s+1]-1))
            pos[str_idx[q]] = w + kq
        end
        for j in f:l, p in lcnt[j]:(lcnt[j+1]-1)
            i = lrow[p]
            ir = i <= l ? i - f + 1 : pos[i]
            amap[lsrc[p]] = lx_ptr[s] + (j - f) * h + ir - 1
        end
    end
    signs = Vector{Float64}(undef, N)
    @inbounds for i in 1:N
        signs[i] = signs_old[perm[i]]
    end
    leaf_par = Vector{Int32}(undef, nleaf); leaf_dpos = Vector{Int}(undef, nleaf)
    @inbounds for j in 1:nleaf
        p = str_idx[str_ptr[j]]
        t = sof[p]; f = starts[t]; h = (starts[t+1] - f) + (str_ptr[t+1] - str_ptr[t])
        leaf_par[j] = p
        leaf_dpos[j] = lx_ptr[t] + (p - f) * h + (p - f)
    end
    return Symbolic(N, perm, iperm, ns, starts, sof, spar, child_ptr, child_idx, str_ptr, str_idx, rel_idx,
                    lx_ptr, lx_ptr[end] - 1, upd_off, peak, max_front, max_r, amap, signs, nnzL, nnzL_exact,
                    flops, sflops, Vector{Int32}(str_idx), nleaf, leaf_par, leaf_dpos,
                    [SNode(starts[s] - 1, starts[s+1] - starts[s], str_ptr[s+1] - str_ptr[s], str_ptr[s] - 1, lx_ptr[s] - 1)
                     for s in 1:ns])
end

"""
    fill_stats(K, perm) -> (nnzL, flops)

Entries of L (with the diagonal) and multiply-adds of the factorization for the
elimination order `perm`, from the elimination tree and column counts only (no
supernodes). This is the cost model's input; it costs about nnz(L).
"""
function fill_stats(K::SparseMatrixCSC, perm::AbstractVector{<:Integer})
    N = size(K, 1)
    iperm = invperm(perm)
    colptr, rowval, _ = _permuted_upper(K, iperm)
    parent = _etree(N, colptr, rowval)
    cc = _colcounts(N, parent, colptr, rowval)
    fl = 0.0
    @inbounds for j in 1:N
        fl += cc[j] * (cc[j] + 1) / 2
    end
    return N + sum(cc), fl
end
