# teams.jl: choosing teams (the paper's Sec. V).
#
# Coherent teams lie inside data classes (agents with the same data). The
# coarsest lossless teams are the coarsest almost equitable partition refining
# the classes (colour refinement of the Laplacian, Prop. "coarsest"). Coarser,
# lossy teams come from quasi-stable colouring: split a team only while its
# members' total weights into some other team spread by more than q times
# their mean; Sec. V bounds their gap after the solve (`team_certificate`).

"""
    data_classes(fleet) -> labels

One class per set of agents that share their data (`same_data`): the coarsest
partition inside which teams can be coherent (references and offsets aside).
"""
function data_classes(fl::Fleet)
    reps = Int[]
    lab = zeros(Int, nagents(fl))
    for (i, ag) in enumerate(fl.agents)
        c = findfirst(r -> same_data(fl.agents[r], ag), reps)
        if c === nothing
            push!(reps, i); c = length(reps)
        end
        lab[i] = c
    end
    return lab
end

_classes(fl::Fleet, classes) = classes === nothing ? data_classes(fl) : canonical_partition(classes)

"""
    lossless_teams(fleet; classes = data_classes(fleet), t = 1, rtol = 1e-9) -> labels

The coarsest lossless teams (the paper's Prop. "coarsest"): the coarsest
almost equitable partition of the formation graph at instant `t` that refines
`classes`, by colour refinement (`colour_refinement`, `within = false`).
"""
lossless_teams(fl::Fleet; classes = nothing, t::Integer = 1, rtol::Real = 1e-9) =
    colour_refinement(fl, _classes(fl, classes); t = t, within = false, rtol = rtol)

"""Totals of every agent into every team: the sparse `n x k` matrix of `sum_j w_ij` over `j` in team `c`."""
function team_totals(n::Integer, edges::AbstractVector, w::AbstractVector, lab::AbstractVector)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for ((i, j), x) in zip(edges, w)
        x == 0 && continue
        push!(I_, i); push!(J_, lab[j]); push!(V_, x)
        push!(I_, j); push!(J_, lab[i]); push!(V_, x)
    end
    return sparse(I_, J_, V_, n, maximum(lab; init = 0))
end

"""
    team_spread(n, edges, weights, labels) -> (q, (P, Q))
    team_spread(fleet, labels; t = 1)

The largest relative spread `(max - min) / mean` of the members' total weights
into another team, over pairs of distinct teams `(P, Q)` (a member with no
edge into `Q` counts 0), and the worst pair: 0 for an almost equitable
partition, at most `q` for a `q`-quasi-stable one.
"""
function team_spread(n::Integer, edges::AbstractVector, weights, lab::AbstractVector)
    w = weights isa Real ? fill(Float64(weights), length(edges)) : Vector{Float64}(weights)
    lab = canonical_partition(lab)
    M = team_totals(n, edges, w, lab)
    k = maximum(lab; init = 0); sz = zeros(Int, k)
    for c in lab
        sz[c] += 1
    end
    mx = Dict{Tuple{Int,Int},Float64}(); mn = Dict{Tuple{Int,Int},Float64}()
    sm = Dict{Tuple{Int,Int},Float64}(); ct = Dict{Tuple{Int,Int},Int}()
    rv = rowvals(M); nz = nonzeros(M)
    for Q in 1:k, p in nzrange(M, Q)
        v = rv[p]; P = lab[v]; P == Q && continue
        key = (P, Q); x = nz[p]
        mx[key] = max(get(mx, key, -Inf), x); mn[key] = min(get(mn, key, Inf), x)
        sm[key] = get(sm, key, 0.0) + x; ct[key] = get(ct, key, 0) + 1
    end
    worst = 0.0; arg = (0, 0)
    for (key, x) in mx
        P = key[1]
        lo = ct[key] < sz[P] ? 0.0 : mn[key]
        r = (x - lo) / (sm[key] / sz[P])
        r > worst && (worst = r; arg = key)
    end
    return worst, arg
end

team_spread(fl::Fleet, lab::AbstractVector; t::Integer = 1) =
    team_spread(nagents(fl), fl.edges, fl.weights[:, t] .* fl.present[:, t], lab)

"""
    quasi_stable_teams(n, edges, weights, classes; q) -> labels
    quasi_stable_teams(fleet; q, classes = data_classes(fleet), t = 1) -> labels

Teams by quasi-stable colouring (a relative variant of the greedy refinement
of Kayali and Suciu 2022): starting from `classes`, split a team whenever its
members' totals into some other team spread by more than `q` times their mean
(`team_spread`, a member with no edge into it counts 0), at the largest gap of
the sorted totals, and repeat until no team splits. The result refines
`classes` and is `q`-quasi-stable, not necessarily the coarsest one. `q = 0`
gives the coarsest almost equitable partition (`lossless_teams`).

Teams wait in a queue and a team is checked when it is new or when a team its
members border has split. A check is one pass over the members' edges: it
lists every member's total into every other team, then refines the team
against the other teams (held fixed) until every piece is `q`-quasi-stable
towards them, team by team from the worst spread down, each piece cut at the
largest gap of its sorted totals while their spread exceeds `q`. The pieces
are queued (their totals into each other are new), and so are the teams
bordering the pieces split off (the other teams' totals do not change). On a
geometric formation this takes milliseconds for a thousand agents and seconds
for sixteen thousand.
"""
function quasi_stable_teams(n::Integer, edges::AbstractVector, weights, classes::AbstractVector; q::Real)
    q >= 0 || throw(ArgumentError("q must be nonnegative"))
    length(classes) == n || throw(DimensionMismatch("classes must have one entry per agent ($n)"))
    w = weights isa Real ? fill(Float64(weights), length(edges)) : Vector{Float64}(weights)
    length(w) == length(edges) || throw(DimensionMismatch("weights must have one entry per edge"))
    q == 0 && return colour_refinement(n, edges, w, classes; within = false)
    n == 0 && return Int[]
    # adjacency in compressed form (zero weights and loops are no edges)
    ptr = zeros(Int, n + 1)
    for ((i, j), x) in zip(edges, w)
        (1 <= i <= n && 1 <= j <= n) || throw(ArgumentError("bad edge ($i, $j)"))
        (x == 0 || i == j) && continue
        ptr[i+1] += 1; ptr[j+1] += 1
    end
    ptr[1] = 1
    for v in 1:n
        ptr[v+1] += ptr[v]
    end
    adj = Vector{Int}(undef, ptr[n+1] - 1); aw = Vector{Float64}(undef, ptr[n+1] - 1)
    fp = ptr[1:n]
    for ((i, j), x) in zip(edges, w)
        (x == 0 || i == j) && continue
        adj[fp[i]] = j; aw[fp[i]] = x; fp[i] += 1
        adj[fp[j]] = i; aw[fp[j]] = x; fp[j] += 1
    end
    # teams as ranges of a permutation
    lab = canonical_partition(classes)
    k = maximum(lab)
    elems = sortperm(lab)
    bstart = zeros(Int, k); bend = zeros(Int, k)
    for (p, v) in enumerate(elems)
        c = lab[v]
        bstart[c] == 0 && (bstart[c] = p)
        bend[c] = p
    end
    sizehint!(bstart, n); sizehint!(bend, n)
    queue = collect(1:k); inq = fill(true, k); head = 1     # FIFO: queue[head:end]
    sizehint!(inq, n)
    acc = zeros(n); vmark = zeros(Int, n); vlist = Int[]   # one member's totals into each team
    W = _QSWork(n)
    qf = Float64(q)
    while head <= length(queue)
        P = queue[head]; head += 1; inq[P] = false
        if head > 4096 && 2head > length(queue)           # drop the processed front now and then
            deleteat!(queue, 1:head-1); head = 1
        end
        lo, hi = bstart[P], bend[P]
        s = hi - lo + 1
        s < 2 && continue
        # every member's total into every other team, as triples
        empty!(W.tv); empty!(W.tq); empty!(W.tx)
        for a in lo:hi
            v = elems[a]
            for p in ptr[v]:(ptr[v+1]-1)
                Q = lab[adj[p]]
                Q == P && continue
                vmark[Q] == v || (vmark[Q] = v; push!(vlist, Q))
                acc[Q] += aw[p]
            end
            for Q in vlist
                push!(W.tv, v); push!(W.tq, Q); push!(W.tx, acc[Q])
                acc[Q] = 0.0; vmark[Q] = 0
            end
            empty!(vlist)
        end
        np = _qs_refine!(W, view(elems, lo:hi), qf)
        np == 1 && continue
        # reorder the range by piece (counting sort); piece 1 keeps P, piece j > 1 becomes team k + j - 1
        cnt = W.cnt; resize!(cnt, np + 1); fill!(cnt, 0)
        for a in lo:hi
            cnt[W.pid[elems[a]]+1] += 1
        end
        cnt[1] = lo
        for j in 1:np
            cnt[j+1] += cnt[j]
        end
        buf = W.buf; resize!(buf, s); copyto!(buf, 1, elems, lo, s)
        for v in buf
            j = W.pid[v]
            elems[cnt[j]] = v; cnt[j] += 1
        end
        a = lo
        for j in 1:np
            b = cnt[j] - 1
            if j == 1
                bstart[P] = a; bend[P] = b
            else
                k += 1
                push!(bstart, a); push!(bend, b); push!(inq, true); push!(queue, k)
                for c in a:b
                    lab[elems[c]] = k
                end
            end
            a = b + 1
        end
        inq[P] || (inq[P] = true; push!(queue, P))
        # the teams bordering the pieces split off
        for c in (bend[P]+1):hi, p in ptr[elems[c]]:(ptr[elems[c]+1]-1)
            R = lab[adj[p]]
            inq[R] || (inq[R] = true; push!(queue, R))
        end
    end
    return canonical_partition(lab)
end

struct _QSWork
    tv::Vector{Int}; tq::Vector{Int}; tx::Vector{Float64}   # a team's triples (member, other team, total)
    li::Vector{Int}                                         # other team -> local index (0: none)
    qs::Vector{Int}; qr::Vector{Float64}; ord::Vector{Int}  # local index -> team, initial spread; worst first
    gptr::Vector{Int}; gE::Vector{Tuple{Int,Float64}}       # the triples grouped by other team
    pid::Vector{Int}; psz::Vector{Int}                      # member -> piece, piece sizes
    vals::Vector{Float64}; mult::Vector{Int}; src::Vector{Int}   # one piece's sorted totals (zeros as one entry)
    ps::Vector{Float64}; pm::Vector{Int}; stack::Vector{Tuple{Int,Int}}; leaves::Vector{Tuple{Int,Int}}
    cnt::Vector{Int}; buf::Vector{Int}
end
_QSWork(n) = _QSWork(Int[], Int[], Float64[], zeros(Int, n), Int[], Float64[], Int[], Int[], Tuple{Int,Float64}[],
                     zeros(Int, n), Int[], Float64[], Int[], Int[], Float64[], Int[], Tuple{Int,Int}[], Tuple{Int,Int}[],
                     Int[], Int[])

"""
Refine one team (`members`, its triples in `W`) against the other teams until
every piece is `q`-quasi-stable towards each of them; sets `W.pid` (1 for the
piece that keeps the team's id) and returns the number of pieces.
"""
function _qs_refine!(W::_QSWork, members::AbstractVector{Int}, q::Float64)
    s = length(members)
    for v in members
        W.pid[v] = 1
    end
    empty!(W.psz); push!(W.psz, s)
    isempty(W.tq) && return 1
    # the other teams, with the spread of the team's totals into each
    empty!(W.qs)
    for Q in W.tq
        W.li[Q] == 0 && (push!(W.qs, Q); W.li[Q] = length(W.qs))
    end
    m = length(W.qs)
    resize!(W.qr, m); resize!(W.gptr, m + 1); fill!(W.gptr, 0)
    for Q in W.tq
        W.gptr[W.li[Q]+1] += 1
    end
    W.gptr[1] = 1
    for i in 1:m
        W.gptr[i+1] += W.gptr[i]
    end
    resize!(W.gE, length(W.tq))
    for (v, Q, x) in zip(W.tv, W.tq, W.tx)
        i = W.li[Q]
        W.gE[W.gptr[i]] = (v, x); W.gptr[i] += 1
    end
    for i in m:-1:1
        W.gptr[i+1] = W.gptr[i]
    end
    W.gptr[1] = 1
    viol = false
    for i in 1:m
        r = W.gptr[i]:(W.gptr[i+1]-1)
        top = -Inf; bot = Inf; sm = 0.0
        for (_, x) in view(W.gE, r)
            top = max(top, x); bot = min(bot, x); sm += x
        end
        length(r) < s && (top = max(top, 0.0); bot = min(bot, 0.0))
        W.qr[i] = (top - bot) / (sm / s)
        viol |= W.qr[i] > q
    end
    for Q in W.qs
        W.li[Q] = 0
    end
    viol || return 1
    resize!(W.ord, m)
    sortperm!(W.ord, W.qr; rev = true)
    # sweeps over the other teams, worst first, until no piece splits
    pid = W.pid
    bykey = let pid = pid; e -> (pid[e[1]], e[2]); end
    while true
        split = false
        for i in W.ord
            r = W.gptr[i]:(W.gptr[i+1]-1)
            g = view(W.gE, r)
            if length(r) <= 32
                sort!(g; by = bykey, alg = InsertionSort)
            else
                sort!(g; by = bykey, alg = QuickSort)
            end
            a = first(r)
            while a <= last(r)
                X = pid[W.gE[a][1]]; b = a
                while b < last(r) && pid[W.gE[b+1][1]] == X
                    b += 1
                end
                split |= _qs_split_piece!(W, X, a, b, q)
                a = b + 1
            end
        end
        split || break
    end
    return length(W.psz)
end

"""
Split piece `X`, whose members with an edge into one other team are the
entries `a:b` of `W.gE` (sorted by total), at the largest gap of its sorted
totals (members without an edge count 0) while their spread exceeds `q`. The
piece holding the zeros (or else the largest) keeps `X`; returns whether it split.
"""
function _qs_split_piece!(W::_QSWork, X::Int, a::Int, b::Int, q::Float64)
    z = W.psz[X] - (b - a + 1)
    vals = W.vals; mult = W.mult; src = W.src
    empty!(vals); empty!(mult); empty!(src)
    zi = 0
    for e in a:b
        x = W.gE[e][2]
        if z > 0 && zi == 0 && x > 0
            push!(vals, 0.0); push!(mult, z); push!(src, 0); zi = length(vals)
        end
        push!(vals, x); push!(mult, 1); push!(src, e)
    end
    z > 0 && zi == 0 && (push!(vals, 0.0); push!(mult, z); push!(src, 0); zi = length(vals))
    L = length(vals)
    ps = W.ps; pm = W.pm
    resize!(ps, L + 1); resize!(pm, L + 1); ps[1] = 0.0; pm[1] = 0
    for t in 1:L
        ps[t+1] = ps[t] + vals[t] * mult[t]; pm[t+1] = pm[t] + mult[t]
    end
    spread(c, d) = (vals[d] - vals[c]) / ((ps[d+1] - ps[c]) / (pm[d+1] - pm[c]))
    spread(1, L) > q || return false
    stack = W.stack; leaves = W.leaves
    empty!(stack); empty!(leaves); push!(stack, (1, L))
    while !isempty(stack)
        c, d = pop!(stack)
        if c < d && spread(c, d) > q
            g = c; gap = -Inf
            for t in c:(d-1)
                vals[t+1] - vals[t] > gap && (gap = vals[t+1] - vals[t]; g = t)
            end
            push!(stack, (g + 1, d)); push!(stack, (c, g))
        else
            push!(leaves, (c, d))
        end
    end
    keep = 0; best = -1
    for (l, (c, d)) in enumerate(leaves)
        if zi > 0
            c <= zi <= d && (keep = l)
        elseif pm[d+1] - pm[c] > best
            best = pm[d+1] - pm[c]; keep = l
        end
    end
    for (l, (c, d)) in enumerate(leaves)
        l == keep && continue
        push!(W.psz, pm[d+1] - pm[c]); np = length(W.psz)
        W.psz[X] -= pm[d+1] - pm[c]
        for t in c:d
            W.pid[W.gE[src[t]][1]] = np
        end
    end
    return true
end

"""Quasi-stable teams by rounds (the reference implementation): every round rebuilds the totals and splits each violating team once."""
function quasi_stable_teams_rounds(n::Integer, edges::AbstractVector, weights, classes::AbstractVector; q::Real)
    q >= 0 || throw(ArgumentError("q must be nonnegative"))
    w = weights isa Real ? fill(Float64(weights), length(edges)) : Vector{Float64}(weights)
    q == 0 && return colour_refinement(n, edges, w, classes; within = false)
    lab = canonical_partition(classes)
    while true
        M = team_totals(n, edges, w, lab)
        k = maximum(lab; init = 0)
        mem = [Int[] for _ in 1:k]
        for v in 1:n
            push!(mem[lab[v]], v)
        end
        nxt = k; changed = false
        Mt = sparse(transpose(M))                 # rows: teams, columns: agents
        rv = rowvals(Mt); nz = nonzeros(Mt)
        for P in 1:k
            length(mem[P]) < 2 && continue
            vals = Dict{Int,Vector{Float64}}()
            for (a, v) in enumerate(mem[P]), p in nzrange(Mt, v)
                Q = rv[p]; Q == P && continue
                get!(() -> zeros(length(mem[P])), vals, Q)[a] = nz[p]
            end
            worst = Float64(q); wq = 0
            for (Q, x) in vals
                r = (maximum(x) - minimum(x)) / (sum(x) / length(x))
                r > worst && (worst = r; wq = Q)
            end
            wq == 0 && continue
            x = vals[wq]; o = sortperm(x)
            g = argmax(diff(x[o]))
            nxt += 1
            for a in o[(g+1):end]
                lab[mem[P][a]] = nxt
            end
            changed = true
        end
        changed || break
    end
    return canonical_partition(lab)
end

quasi_stable_teams(fl::Fleet; q::Real, classes = nothing, t::Integer = 1) =
    quasi_stable_teams(nagents(fl), fl.edges, fl.weights[:, t] .* fl.present[:, t], _classes(fl, classes); q = q)
