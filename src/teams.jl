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
of Kayali and Suciu 2022): starting from `classes`, in rounds, split every
team whose members' totals into some other team spread by more than `q` times
their mean (`team_spread`), at the largest gap of the sorted totals into its
worst team; stop when no team splits. The result refines `classes` and is
`q`-quasi-stable, not necessarily the coarsest one. `q = 0` gives the coarsest
almost equitable partition (`lossless_teams`). Each round is linear in
`n + |edges|` and at most `n` rounds split, so the cost is `O(n (n + |edges|))`,
once, offline.
"""
function quasi_stable_teams(n::Integer, edges::AbstractVector, weights, classes::AbstractVector; q::Real)
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
