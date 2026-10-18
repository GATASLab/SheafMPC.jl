# parallel.jl: factorization and solves over independent subtrees of the
# supernodal elimination tree.
#
# Schedule: the tree is cut into a "top" part (processed sequentially, last
# in the factorization and the forward sweep, first in the backward sweep) and
# disjoint subtrees below it, found by repeatedly splitting the subtree of
# largest work until every subtree carries at most a fraction of the work. The
# subtrees are packed into one bin per thread (largest work first, into the
# lightest bin), and every bin is one task with a stack of its own. The update
# matrix of a subtree root goes to a buffer of its own; the top part has its
# own stack. In the forward sweep, a subtree writes only rows inside it to x and
# accumulates the rows of its root's structure in a buffer, which is added to
# x before the top part runs; in the backward sweep subtrees only read rows
# above them. No locks, no atomics.

struct Schedule
    tasks::Vector{Vector{Int}}           # subtree roots of every task
    first::Vector{Int}                   # first (postorder) supernode of each subtree, by supernode
    top::Vector{Int}                     # supernodes of the top part, postorder
    uoff::Vector{Int}                    # update matrix offset of every supernode (all stacks and buffers)
    nupd::Int
    nin::Vector{Int}                     # per supernode in a subtree: structure rows inside the subtree
    extpos::Vector{Int}                  # str_idx layout: position in the subtree root's structure (outside rows)
    sroot::Vector{Int}                   # per supernode: root of its subtree (0 in the top part)
    xbuf::Vector{Vector{Float64}}        # per subtree root (indexed by position in `roots`)
    roots::Vector{Int}
    rootpos::Vector{Int}                 # supernode -> index in roots (0 otherwise)
    tmp::Vector{Vector{Float64}}         # per task solve scratch
    blas_top::Int                        # BLAS threads in the top part
end

function _work(S::Symbolic)
    ns = S.nsup
    wk = zeros(ns)
    @inbounds for s in 1:ns
        w = S.sup_ptr[s+1] - S.sup_ptr[s]
        r = S.str_ptr[s+1] - S.str_ptr[s]
        h = w + r
        fl = 0.0
        for k in 1:w
            rem = h - k
            fl += rem * (rem + 1) / 2
        end
        wk[s] = fl + h * w + 50.0
    end
    sw = copy(wk)
    @inbounds for s in 1:ns
        p = S.parent[s]
        p > 0 && (sw[p] += sw[s])
    end
    return wk, sw
end

"""
    schedule_tree(S, nt; split = 4) -> Schedule

Subtrees for `nt` threads: split until the largest subtree has at most
`1 / (split * nt)` of the total work (or no split is possible), then pack.
"""
function schedule_tree(S::Symbolic, nt::Int; split::Int = 4, blas_top::Int = nt)
    ns = S.nsup
    wk, sw = _work(S)
    total = sum(wk)
    cand = [s for s in 1:ns if S.parent[s] == 0]
    istop = falses(ns)
    target = total / (split * nt)
    for _ in 1:(4 * ns)
        isempty(cand) && break
        jm = argmax(i -> sw[cand[i]], eachindex(cand))
        s = cand[jm]
        sw[s] <= target && break
        nc = S.child_ptr[s+1] - S.child_ptr[s]
        nc == 0 && break
        istop[s] = true
        deleteat!(cand, jm)
        for c in S.child_ptr[s]:(S.child_ptr[s+1]-1)
            push!(cand, S.child_idx[c])
        end
    end
    # first descendant (postorder ranges)
    first = collect(1:ns)
    @inbounds for s in 1:ns
        p = S.parent[s]
        p > 0 && (first[p] = min(first[p], first[s]))
    end
    # pack subtrees into nt bins, heaviest first
    order = sort(cand; by = s -> -sw[s])
    bins = [Int[] for _ in 1:nt]; load = zeros(nt)
    for s in order
        b = argmin(load)
        push!(bins[b], s); load[b] += sw[s]
    end
    tasks = [sort(b) for b in bins if !isempty(b)]
    roots = sort(cand)
    rootpos = zeros(Int, ns)
    for (k, s) in enumerate(roots)
        rootpos[s] = k
    end
    sroot = zeros(Int, ns)
    for t in roots, s in first[t]:t
        sroot[s] = t
    end
    top = [s for s in 1:ns if sroot[s] == 0]
    # update offsets: one stack per task, a buffer per subtree root, the top stack
    uoff = fill(-1, ns)
    off = 0
    rsz(s) = (r = S.str_ptr[s+1] - S.str_ptr[s]; r * r)
    for tk in tasks
        peak = 0
        for t in tk
            top_ = off; stk = Int[]
            for s in first[t]:(t-1)
                base = top_
                for c in S.child_ptr[s]:(S.child_ptr[s+1]-1)
                    pop!(stk)
                end
                # the children of s are the top entries: their region starts at the first child's offset
                nc = S.child_ptr[s+1] - S.child_ptr[s]
                if nc > 0
                    base = uoff[S.child_idx[S.child_ptr[s]]]
                    for c in S.child_ptr[s]:(S.child_ptr[s+1]-1)
                        base = min(base, uoff[S.child_idx[c]])
                    end
                end
                uoff[s] = base
                top_ = base + rsz(s)
                push!(stk, s)
                peak = max(peak, top_ - off)
            end
        end
        off += peak
    end
    for t in roots
        if S.parent[t] != 0
            uoff[t] = off
            off += rsz(t)
        end
    end
    top_ = off; peak = off
    for s in top
        S.parent[s] == 0 && continue
        base = top_
        for c in S.child_ptr[s]:(S.child_ptr[s+1]-1)
            ch = S.child_idx[c]
            sroot[ch] == 0 && (base = min(base, uoff[ch]))
        end
        uoff[s] = base
        top_ = base + rsz(s)
        peak = max(peak, top_)
    end
    nupd = max(peak, off)
    # forward-sweep maps: rows of a subtree supernode outside its subtree
    nin = zeros(Int, ns)
    extpos = zeros(Int, length(S.str_idx))
    for t in roots
        lt = S.sup_ptr[t+1] - 1
        rt = S.str_ptr[t]:(S.str_ptr[t+1]-1)
        for s in first[t]:t
            q1 = S.str_ptr[s]; q2 = S.str_ptr[s+1] - 1
            k = q1
            while k <= q2 && S.str_idx[k] <= lt
                k += 1
            end
            nin[s] = k - q1
            for q in k:q2
                extpos[q] = searchsortedfirst(view(S.str_idx, rt), S.str_idx[q])
            end
        end
    end
    xbuf = [zeros(S.str_ptr[t+1] - S.str_ptr[t]) for t in roots]
    tmp = [zeros(max(S.max_r, 1)) for _ in 1:(length(tasks)+1)]
    return Schedule(tasks, first, top, uoff, nupd, nin, extpos, sroot, xbuf, roots, rootpos, tmp, blas_top)
end

function _factor_parallel!(F::Factor)
    S = F.S; sc = F.sched::Schedule
    nb = BLAS.get_num_threads()
    BLAS.set_num_threads(1)
    nregs = zeros(Int, length(sc.tasks))
    @sync for (ti, tk) in enumerate(sc.tasks)
        Threads.@spawn begin
            local T = F.T[ti]
            local W = F.W[ti]
            local nr = 0
            for t in tk, s in sc.first[t]:t
                uo = S.parent[s] == 0 ? -1 : sc.uoff[s]
                nr += _factor_supernode!(F, s, uo, sc.uoff, T, W)
            end
            nregs[ti] = nr
        end
    end
    sc.blas_top > 1 && BLAS.set_num_threads(sc.blas_top)
    Tt = F.T[end]; Wt = F.W[end]
    nrt = sum(nregs)
    for s in sc.top
        uo = S.parent[s] == 0 ? -1 : sc.uoff[s]
        nrt += _factor_supernode!(F, s, uo, sc.uoff, Tt, Wt)
    end
    BLAS.set_num_threads(nb)
    F.nreg = nrt
    return F
end

"Forward sweep of one subtree supernode: rows outside the subtree go to the root's buffer."
@inline function _forward_sub!(F::Factor, sc::Schedule, x::Vector{Float64}, tmp::Vector{Float64}, s::Int,
                               buf::Vector{Float64})
    S = F.S; Lx = F.Lx; dinv = F.dinv
    @inbounds begin
        f = S.sup_ptr[s]; w = S.sup_ptr[s+1] - f
        rb = S.str_ptr[s] - 1; r = S.str_ptr[s+1] - S.str_ptr[s]
        h = w + r
        o = S.lx_ptr[s] - 1
        fo = f - 1
        w > 1 && _diag_fwd!(x, Lx, o, h, fo, w)
        if r > 0
            ni = sc.nin[s]
            if ni == r
                _fwd_offdiag!(x, Lx, tmp, S.str_idx, rb, r, o + w, h, fo, w)
            else
                _fwd_acc!(x, Lx, tmp, r, o + w, h, fo, w)
                for i in 1:ni
                    x[S.str_idx[rb+i]] -= tmp[i]
                end
                for i in (ni+1):r
                    buf[sc.extpos[rb+i]] += tmp[i]
                end
            end
        end
        for k in 1:w
            x[fo+k] *= dinv[fo+k]
        end
    end
    return nothing
end

function _solve_parallel!(F::Factor, x::Vector{Float64})
    S = F.S; sc = F.sched::Schedule
    @sync for (ti, tk) in enumerate(sc.tasks)
        Threads.@spawn begin
            local tmp = sc.tmp[ti]
            for t in tk
                local buf = sc.xbuf[sc.rootpos[t]]
                for s in sc.first[t]:t
                    _forward_sub!(F, sc, x, tmp, s, buf)
                end
            end
        end
    end
    @inbounds for (k, t) in enumerate(sc.roots)
        buf = sc.xbuf[k]
        rb = S.str_ptr[t] - 1
        for i in eachindex(buf)
            x[S.str_idx[rb+i]] -= buf[i]
            buf[i] = 0.0
        end
    end
    tmpt = sc.tmp[end]
    for s in sc.top
        _forward_range!(F, x, tmpt, s, s)
    end
    for k in length(sc.top):-1:1
        _backward_range!(F, x, tmpt, sc.top[k], sc.top[k])
    end
    @sync for (ti, tk) in enumerate(sc.tasks)
        Threads.@spawn begin
            local tmp = sc.tmp[ti]
            for t in Iterators.reverse(tk)
                _backward_range!(F, x, tmp, sc.first[t], t)
            end
        end
    end
    return x
end
