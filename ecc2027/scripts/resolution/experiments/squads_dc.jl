# squads_dc.jl: the irregular squad formation of Sec. VI (shared by the E26/E51 family, e63_time.jl, and the
# E27/E30 family, e63_gap.jl). Needs fleet_dc.jl (drone_dc, car_dc, dc_select, dc_lanes) and TeamMPC as SM.
#
# The fleet is n vehicles in squads of 4 to 16 (sizes drawn per seed). A squad is one type (drone or car) and one
# variant of that type (BENCH_SQ_VARIANTS per type: its own input bound and drag), so the data classes are the
# (type, variant) pairs and, with coherent references, every squad is a coherent team. Squad centres are random
# in a square (density one vehicle per unit area), members random in a disc about their centre (irregular
# slots). Inside a squad: a random spanning tree plus random chords, random stiffness in [0.5, 1.5]. Between
# squads: the squad graph is the Euclidean minimum spanning tree of the centres plus each squad's 3 nearest
# squads; between adjacent squads A and B the edges carry a random total weight T and are drawn by the
# north-west corner rule on random orders of A and B with row sums T/|A| and column sums T/|B|, so every member
# of A has the same total weight into B and conversely, while the individual edges and weights are irregular.
# The squads are then an almost equitable partition (colour refinement from the classes returns them, or a
# coarser one) and the graph has essentially no automorphisms (ordinary colour refinement is nearly discrete).
#
# Variants of the instance:
#   eps     every edge between squads gets the weight factor 1 + eps U(-1, 1): almost equitability fails, the
#           exact teams fragment, and quasi-stable colouring at q of order eps recovers the squads (lossy)
#   spread  every member's drag and input bound get the factor 1 + spread U(-1, 1): near-coherent squads
#
# Teams (labels per vehicle):
#   aep             colour refinement ignoring the edges inside a team (the coarsest almost equitable partition
#                   refining the classes; lossless with coherent data)
#   equitable       ordinary colour refinement (the coarsest equitable partition; symmetry orbits refine it, so
#                   its count is a lower bound on the number of orbits of symmetric MPC)
#   qs<q>           quasi-stable colouring (Kayali and Suciu 2022) from the classes: split a class while, for
#                   some other class, its members' total weights into that class spread by more than q times
#                   their mean; q = 0 is exact colour refinement
#   geo<k>          k-means on the slots inside each class, about k members per team (a heuristic baseline)
#   squads          the generating squads
#   classes         one team per data class (the coarsest coherent choice)

const SQ_VARIANTS = parse(Int, get(ENV, "BENCH_SQ_VARIANTS", "2"))
const SQ_EPS = parse(Float64, get(ENV, "BENCH_SQ_EPS", "0.0"))
const SQ_SPREAD = parse(Float64, get(ENV, "BENCH_SQ_SPREAD", "0.0"))
const SQ_CROSS = parse(Float64, get(ENV, "BENCH_SQ_CROSS", "0.5"))     # mean total weight per member into a neighbouring squad

"""(umax, drag, r) of a (type, variant): drones fast and light, cars slow with drag."""
function sq_params(kind::Symbol, v::Int)
    if kind == :drone
        return v == 1 ? (umax = 4.0, drag = 0.0, r = 0.1) : (umax = 3.0, drag = 0.1, r = 0.1)
    else
        return v == 1 ? (umax = 0.4, drag = 0.3, r = 0.2) : (umax = 0.5, drag = 0.2, r = 0.2)
    end
end

"""Squad sizes in 4:16 summing to n (n >= 4)."""
function sq_sizes(rng, n::Int)
    s = Int[]; rem_ = n
    while rem_ > 16
        k = rand(rng, 4:16)
        rem_ - k < 4 && (k = rem_ - 4)
        push!(s, k); rem_ -= k
    end
    push!(s, rem_)
    return s
end

"""North-west corner rule: a transport plan with row sums rs and column sums cs (same total), random orders."""
function sq_nwcorner(rng, a::Vector{Int}, b::Vector{Int}, T::Float64)
    pa = a[randperm(rng, length(a))]; pb = b[randperm(rng, length(b))]
    ra = fill(T / length(a), length(a)); cb = fill(T / length(b), length(b))
    i = 1; j = 1; out = Tuple{Int,Int,Float64}[]
    while i <= length(pa) && j <= length(pb)
        x = min(ra[i], cb[j])
        x > 1e-12 * T && push!(out, (pa[i], pb[j], x))
        ra[i] -= x; cb[j] -= x
        if ra[i] <= 1e-12 * T && i < length(pa)
            i += 1
        elseif cb[j] <= 1e-12 * T
            j += 1
        else
            i += 1
        end
    end
    return out
end

"""
    squads_instance(n, seed; eps, spread) -> NamedTuple

slots (3-vectors, altitude 0), edges, w (stiffness per edge), kinds, variant, squad, class (per vehicle),
params (per vehicle: umax, drag, r), cross (true for an edge between squads), nsquads.
"""
function squads_instance(n::Int, seed::Int; eps::Float64 = SQ_EPS, spread::Float64 = SQ_SPREAD, variants::Int = SQ_VARIANTS)
    rng = Xoshiro(63_000_000 + seed)
    sizes = sq_sizes(rng, n)
    K = length(sizes)
    L = sqrt(n)
    cen = [L .* rand(rng, 2) for _ in 1:K]
    skind = [rand(rng) < 0.5 ? :drone : :car for _ in 1:K]
    svar = [rand(rng, 1:variants) for _ in 1:K]
    squad = reduce(vcat, [fill(k, sizes[k]) for k in 1:K])
    members = [findall(==(k), squad) for k in 1:K]
    slots = Vector{Vector{Float64}}(undef, n)
    for k in 1:K
        rad = sqrt(sizes[k] / pi)
        for i in members[k]
            r = rad * sqrt(rand(rng)); th = 2pi * rand(rng)
            slots[i] = [cen[k][1] + r * cos(th), cen[k][2] + r * sin(th), 0.0]
        end
    end
    edges = Tuple{Int,Int}[]; w = Float64[]; cross = Bool[]
    # inside a squad: random spanning tree plus chords
    for k in 1:K
        m = members[k]
        for q in 2:length(m)
            push!(edges, minmax(m[q], m[rand(rng, 1:(q-1))])); push!(w, 0.5 + rand(rng)); push!(cross, false)
        end
        have = Set(edges[end-length(m)+2:end])
        for a in 1:length(m), b in (a+1):length(m)
            e = (m[a], m[b])
            (e in have) && continue
            rand(rng) < 1.5 / length(m) && (push!(edges, e); push!(w, 0.5 + rand(rng)); push!(cross, false))
        end
    end
    # the squad graph: Euclidean MST (Prim) plus 3 nearest neighbours
    D = [norm(cen[a] - cen[b]) for a in 1:K, b in 1:K]
    sadj = Set{Tuple{Int,Int}}()
    intree = falses(K); intree[1] = true; best = copy(D[1, :]); par = fill(1, K)
    for _ in 2:K
        v = 0; bv = Inf
        for u in 1:K
            !intree[u] && best[u] < bv && (bv = best[u]; v = u)
        end
        intree[v] = true; push!(sadj, minmax(v, par[v]))
        for u in 1:K
            !intree[u] && D[v, u] < best[u] && (best[u] = D[v, u]; par[u] = v)
        end
    end
    for a in 1:K
        for b in sortperm(D[a, :])[2:min(4, K)]
            push!(sadj, minmax(a, b))
        end
    end
    for (a, b) in sort!(collect(sadj))
        T = SQ_CROSS * sqrt(sizes[a] * sizes[b]) * (0.5 + rand(rng))
        for (i, j, x) in sq_nwcorner(rng, members[a], members[b], T)
            push!(edges, minmax(i, j)); push!(w, x * (1 + eps * (2rand(rng) - 1))); push!(cross, true)
        end
    end
    kinds = [skind[squad[i]] for i in 1:n]
    variant = [svar[squad[i]] for i in 1:n]
    class = [(kinds[i] == :drone ? 0 : variants) + variant[i] for i in 1:n]
    params = map(1:n) do i
        p = sq_params(kinds[i], variant[i])
        spread == 0 && return p
        (umax = p.umax * (1 + spread * (2rand(rng) - 1)), drag = p.drag * (1 + spread * (2rand(rng) - 1)), r = p.r)
    end
    return (slots = slots, edges = edges, w = w, kinds = kinds, variant = variant, squad = squad, class = class,
            params = params, cross = cross, nsquads = K, variants = variants, eps = eps, spread = spread)
end

"""The agents of an instance (ball or box limits)."""
sq_agents(inst, h, cone) = [inst.kinds[i] == :drone ? drone_dc(h, inst.params[i].umax, inst.params[i].drag, inst.params[i].r, cone) :
                            car_dc(h, inst.params[i].umax, inst.params[i].drag, inst.params[i].r, cone) for i in eachindex(inst.kinds)]

"""One lane per class, the lane of its type (drone lane 1, car lane 2 of dc_lanes); every class is one type."""
sq_lanes(inst, seed) = (l = dc_lanes(seed); [(i = findfirst(==(c), inst.class); i === nothing || inst.kinds[i] == :drone ? l[1] : l[2])
                                               for c in 1:maximum(inst.class)])

"""Rank of every vehicle inside its team, by slot (x, then y)."""
function sq_ranks(lab, slots)
    rank = zeros(Int, length(lab))
    for b in unique(lab)
        mem = sort(findall(==(b), lab); by = i -> (slots[i][1], slots[i][2]))
        rank[mem] .= 1:length(mem)
    end
    return rank
end

"""Totals M[v, c] of every vehicle's edge weights into every team c (sparse n x k)."""
function sq_totals(n, edges, w, lab)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for ((i, j), x) in zip(edges, w)
        x == 0 && continue
        push!(I_, i); push!(J_, lab[j]); push!(V_, x)
        push!(I_, j); push!(J_, lab[i]); push!(V_, x)
    end
    return sparse(I_, J_, V_, n, maximum(lab))
end

"""
The largest relative spread over pairs of distinct teams (P, Q): (max - min) / mean of the members' totals into
Q, over the members of P (a member with no edge into Q counts 0). 0 for an almost equitable partition.
"""
function sq_spread(n, edges, w, lab)
    M = sq_totals(n, edges, w, lab)
    k = maximum(lab); sz = [count(==(c), lab) for c in 1:k]
    mx = Dict{Tuple{Int,Int},Float64}(); mn = Dict{Tuple{Int,Int},Float64}(); sm = Dict{Tuple{Int,Int},Float64}(); ct = Dict{Tuple{Int,Int},Int}()
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
        mean = sm[key] / sz[P]
        r = (x - lo) / mean
        r > worst && (worst = r; arg = key)
    end
    return worst, arg, M
end

"""
Quasi-stable colouring from the classes (Kayali and Suciu 2022, by rounds): while some pair of teams (P, Q) has
relative spread above q, split P at the largest gap of its members' totals into its worst Q (every violating P
once per round). q = 0 gives the coarsest almost equitable partition (colour refinement, within = false).
Returns the labels and the spread achieved.
"""
function quasi_stable(n, edges, w, classes; q::Float64)
    if q == 0
        lab = SM.canonical_partition(SM.colour_refinement(n, edges, w, classes; within = false))
        return lab, sq_spread(n, edges, w, lab)[1]
    end
    lab = SM.canonical_partition(classes)
    while true
        M = sq_totals(n, edges, w, lab)
        k = maximum(lab)
        mem = [Int[] for _ in 1:k]
        for v in 1:n
            push!(mem[lab[v]], v)
        end
        nxt = k; changed = false
        Mt = sparse(transpose(M))           # rows: teams Q, columns: vehicles
        for P in 1:k
            length(mem[P]) < 2 && continue
            # totals of P's members into every Q
            vals = Dict{Int,Vector{Float64}}()
            for (a, v) in enumerate(mem[P]), p in nzrange(Mt, v)
                Q = rowvals(Mt)[p]; Q == P && continue
                get!(vals, Q, zeros(length(mem[P])))[a] = nonzeros(Mt)[p]
            end
            worst = q; wq = 0
            for (Q, x) in vals
                r = (maximum(x) - minimum(x)) / (sum(x) / length(x))
                r > worst && (worst = r; wq = Q)
            end
            wq == 0 && continue
            x = vals[wq]; o = sortperm(x)
            gaps = diff(x[o]); g = argmax(gaps)
            nxt += 1
            for a in o[(g+1):end]
                lab[mem[P][a]] = nxt
            end
            changed = true
        end
        changed || break
    end
    lab = SM.canonical_partition(lab)
    return lab, sq_spread(n, edges, w, lab)[1]
end

"""k-means on the slots inside every class, about k members per team (Lloyd, 30 rounds, seeded)."""
function sq_geo(inst, k::Int, seed::Int)
    rng = Xoshiro(61_000_000 + seed)
    n = length(inst.class); lab = zeros(Int, n); nxt = 0
    for c in sort(unique(inst.class))
        mem = findall(==(c), inst.class)
        m = max(1, round(Int, length(mem) / k))
        X = [inst.slots[i][1:2] for i in mem]
        cen = X[randperm(rng, length(X))[1:m]]
        a = zeros(Int, length(X))
        for _ in 1:30
            for (q, x) in enumerate(X)
                a[q] = argmin([norm(x - cc) for cc in cen])
            end
            for j in 1:m
                sel = findall(==(j), a)
                isempty(sel) || (cen[j] = sum(X[sel]) / length(sel))
            end
        end
        lab[mem] .= nxt .+ a; nxt += m
    end
    return SM.canonical_partition(lab)
end

"""Team labels for a choice name (aep, equitable, qs<q>, geo<k>, squads, classes) and the seconds it took."""
function sq_teams(inst, choice::AbstractString, seed::Int)
    n = length(inst.class)
    t = @elapsed lab = if choice == "aep"
        SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = false))
    elseif choice == "equitable"
        SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = true))
    elseif startswith(choice, "qs")
        quasi_stable(n, inst.edges, inst.w, inst.class; q = parse(Float64, choice[3:end]))[1]
    elseif startswith(choice, "geo")
        sq_geo(inst, parse(Int, choice[4:end]), seed)
    elseif choice == "squads"
        SM.canonical_partition(inst.squad)
    elseif choice == "classes"
        SM.canonical_partition(inst.class)
    else
        error("unknown team choice $choice")
    end
    return lab, t
end

"""Zero-stiffness joins between consecutive ranks of every team (every team connected, Lemma lem:onevehicle)."""
function sq_joins(lab, rank)
    joins = Tuple{Int,Int}[]
    for b in unique(lab)
        mem = sort(findall(==(b), lab); by = i -> rank[i])
        for q in 1:(length(mem)-1)
            push!(joins, minmax(mem[q], mem[q+1]))
        end
    end
    return joins
end

# ---------------------------------------------------------------------------
# The fleet, references, plant and stage cost of an instance (shared by e63_time.jl and e63_gap.jl)
# ---------------------------------------------------------------------------

"""Per-vehicle parameters of the instance, or the nominal ones of its (type, variant) when `nominal`."""
sq_params_of(inst, i; nominal::Bool = false) = nominal ? sq_params(inst.kinds[i], inst.variant[i]) : inst.params[i]

"""The TeamMPC fleet of an instance (cone :soc or :box), every formation edge with its stiffness at every instant."""
function sq_fleet(inst, h, H, cone; nominal::Bool = false)
    ags = map(eachindex(inst.kinds)) do i
        p = sq_params_of(inst, i; nominal = nominal)
        inst.kinds[i] == :drone ? drone_dc(h, p.umax, p.drag, p.r, cone) : car_dc(h, p.umax, p.drag, p.r, cone)
    end
    W = repeat(inst.w, 1, H)
    return SM.Fleet(ags, inst.edges; H = H, offsets = inst.slots, weights = W, select = dc_select(inst.edges, inst.kinds))
end

"""Reference position and velocity of vehicle i (its class's lane shifted by its slot; coherent)."""
function sq_reference(inst, lanes, ag, i, tau)
    q = lanes[inst.class[i]]
    p = [q.speed * tau, q.amp * (sin(q.om * tau + q.ph) - sin(q.ph)), q.alt] + inst.slots[i]
    v = [q.speed, q.amp * q.om * cos(q.om * tau + q.ph), 0.0]
    d = size(ag.Cr, 1)
    return p[1:d], v[1:d]
end

"""refs[i] (ny x (H+1) positions) and term[i] (terminal position and velocity) of the step at time t0."""
function sq_references(inst, lanes, fl, t0, h, H)
    n = length(inst.kinds)
    refs = Vector{Matrix{Float64}}(undef, n); term = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        ag = fl.agents[i]; d = size(ag.Cr, 1)
        R = zeros(d, H + 1)
        for t in 0:H
            R[:, t+1] = sq_reference(inst, lanes, ag, i, t0 + h * t)[1]
        end
        refs[i] = R
        term[i] = [R[:, end]; sq_reference(inst, lanes, ag, i, t0 + h * H)[2]]
    end
    return refs, term
end

"""The start: on the slot (a drone at altitude 1.5) with velocity (1, 0.15), plus a rigid perturbation from the seed."""
function sq_start(inst, fl, seed)
    rngs = Xoshiro(7919 * seed)
    dp = 0.3 * randn(rngs, 2); dv = 0.15 * randn(rngs, 2)
    return [fl.agents[i].nx == 6 ? [inst.slots[i] + [dp; 1.5]; [1.0, 0.15] + dv; 0.0] :
            [inst.slots[i][1:2] + dp; [1.0, 0.15] + dv] for i in eachindex(inst.kinds)], dp, dv
end

sq_plant(fl, x, u) = [ag.A[1] * x[i] + ag.B[1] * u[i] + ag.g[1] for (i, ag) in enumerate(fl.agents)]

"""Stage cost of inputs u at states x (u = nothing: terminal), formation included; and the formation parts
(all edges, the edges between teams `lab`) as energies 1/2 sum w ||res||^2."""
function sq_stage(fl, x, u, refs; lab = nothing)
    c = 0.0
    for (i, ag) in enumerate(fl.agents)
        e = ag.Cr * x[i] - refs[i][:, 1]
        c += 0.5 * dot(e, ag.Q * e)
        u === nothing || (c += 0.5 * dot(u[i], ag.R * u[i]))
    end
    form = 0.0; cross = 0.0
    for (k, (i, j)) in enumerate(fl.edges)
        d = SM.edge_residual(fl, k, x[i], x[j], 1)
        e = 0.5 * fl.weights[k, 1] * dot(d, d)
        form += e
        (lab !== nothing && lab[i] != lab[j]) && (cross += e)
    end
    return c + form, form, cross
end

# ---------------------------------------------------------------------------
# The natural irregular formation (NOT built to be almost equitable): the lossy instance
# ---------------------------------------------------------------------------

"""
    natural_instance(n, seed; radius, regionsize, variants) -> NamedTuple (the fields of squads_instance)

n random slots (density one per unit area), the random geometric graph of radius `radius` (largest connected
component), stiffness 1/d per edge; the slots are cut into spatial regions of about `regionsize` (k-means), and
every region is one type (drone or car) and one variant, with identical data inside it: the data classes are
the regions. Nothing is planted: the coarsest almost equitable partition is generically near the singletons,
so teams are lossy and come from quasi-stable colouring or geometry.
"""
function natural_instance(n::Int, seed::Int; radius::Float64 = parse(Float64, get(ENV, "BENCH_NAT_RADIUS", "1.5")),
                          regionsize::Int = parse(Int, get(ENV, "BENCH_NAT_REGION", "12")), variants::Int = SQ_VARIANTS)
    rng = Xoshiro(64_000_000 + seed)
    L = sqrt(n)
    pts = [L .* rand(rng, 2) for _ in 1:n]
    cell = Dict{Tuple{Int,Int},Vector{Int}}()
    key(p) = (floor(Int, p[1] / radius), floor(Int, p[2] / radius))
    for (i, p) in enumerate(pts)
        push!(get!(cell, key(p), Int[]), i)
    end
    E = Tuple{Int,Int}[]
    for (i, p) in enumerate(pts)
        (a, b) = key(p)
        for da in -1:1, db in -1:1, j in get(cell, (a + da, b + db), Int[])
            j > i && norm(pts[j] - p) < radius && push!(E, (i, j))
        end
    end
    parent = collect(1:n)
    f(x) = (while parent[x] != x; parent[x] = parent[parent[x]]; x = parent[x]; end; x)
    for (i, j) in E
        a, b = f(i), f(j); a != b && (parent[a] = b)
    end
    roots = [f(i) for i in 1:n]
    big = argmax(r -> count(==(r), roots), unique(roots))
    keep = findall(==(big), roots)
    idx = zeros(Int, n); idx[keep] .= 1:length(keep)
    edges = [(idx[i], idx[j]) for (i, j) in E if idx[i] > 0 && idx[j] > 0]
    P = pts[keep]; m = length(P)
    w = [1 / norm(P[j] - P[i]) for (i, j) in edges]
    # spatial regions: Lloyd's k-means, about regionsize slots each
    K = max(1, round(Int, m / regionsize))
    cen = P[randperm(rng, m)[1:K]]; reg = zeros(Int, m)
    for _ in 1:40
        for q in 1:m
            reg[q] = argmin([norm(P[q] - c) for c in cen])
        end
        for k in 1:K
            sel = findall(==(k), reg)
            isempty(sel) || (cen[k] = sum(P[sel]) / length(sel))
        end
    end
    reg = SM.canonical_partition(reg); K = maximum(reg)
    rkind = [rand(rng) < 0.5 ? :drone : :car for _ in 1:K]
    rvar = [rand(rng, 1:variants) for _ in 1:K]
    kinds = [rkind[reg[i]] for i in 1:m]
    variant = [rvar[reg[i]] for i in 1:m]
    params = [sq_params(kinds[i], variant[i]) for i in 1:m]
    cross = [reg[i] != reg[j] for (i, j) in edges]
    return (slots = [[p; 0.0] for p in P], edges = edges, w = w, kinds = kinds, variant = variant, squad = reg, class = copy(reg),
            params = params, cross = cross, nsquads = K, variants = variants, eps = 0.0, spread = 0.0)
end

"""The instance of a run: BENCH_INSTANCE = squads (planted, lossless) or natural (lossy)."""
sq_instance(n, seed) = get(ENV, "BENCH_INSTANCE", "squads") == "natural" ? natural_instance(n, seed) : squads_instance(n, seed)
