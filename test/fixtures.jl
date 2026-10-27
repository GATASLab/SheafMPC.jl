# fixtures.jl: small fleets and partitions shared by the reduction tests.

srelerr(a, b) = abs(a - b) / max(abs(a), abs(b), 1e-300)

"""Ring, path, grid, complete or random geometric graph on `n` agents, with slots."""
function test_graph(kind::Symbol, n::Int, rng)
    if kind == :grid
        r = floor(Int, sqrt(n)); while n % r != 0; r -= 1; end
        return grid_graph(r, n ÷ r)
    end
    slots = [zeros(2) for _ in 1:n]
    edges = Tuple{Int,Int}[]
    if kind in (:ring, :complete)
        R = n > 2 ? 1 / (2 * sin(pi / n)) : 0.5
        for i in 1:n
            slots[i] = R * [cos(2pi * (i - 1) / n), sin(2pi * (i - 1) / n)]
        end
        if kind == :ring
            for i in 1:n
                j = i == n ? 1 : i + 1
                push!(edges, minmax(i, j))
            end
            edges = unique(edges)
        else
            edges = [(i, j) for i in 1:n for j in (i+1):n]
        end
    elseif kind == :rgg
        for i in 1:n
            slots[i] = sqrt(n) * rand(rng, 2)
        end
        rad = 1.2
        while true
            edges = [(i, j) for i in 1:n for j in (i+1):n if norm(slots[i] - slots[j]) <= rad]
            parent = collect(1:n)
            find(a) = (while parent[a] != a; a = parent[a]; end; a)
            for (i, j) in edges
                parent[find(i)] = find(j)
            end
            length(unique(find.(1:n))) == 1 && break
            rad *= 1.1
        end
    end
    return edges, slots
end

"""
A fleet for the tests: agent kinds (`:quad` or `:rover`), a graph, horizon `H`,
optional per-instant steps (time varying), drift, input scale and switching.
Returns the program with coherent references (formation centre plus slot) or
incoherent ones, and the fleet start on its slots.
"""
function test_program(; n = 4, H = 5, graph = :ring, kinds = :mixed, seed = 1, drift = 0.0, umax_scale = 1.0,
                      time_varying = false, switching = 0.0, absent = :omit, coherent = true, start_in_formation = true,
                      input = :ball)
    rng = Xoshiro(seed)
    edges, slots = test_graph(graph, n, rng)
    h = time_varying ? [0.2 * (0.6 + 0.8 * rand(rng)) for _ in 1:H] : 0.2
    w = drift * normalize(randn(rng, 2))
    ks = [kinds == :mixed ? (isodd(i) ? :quad : :rover) : kinds for i in 1:n]
    mk(k) = k == :quad ? quadrotor(h; umax = 4.0 * umax_scale, drift = w) : ground_vehicle(h; umax = 2.0 * umax_scale, drift = w)
    agents = Agent[mk(k) for k in ks]
    if input == :none
        agents = Agent[Agent(ag.A, ag.B; g = ag.g, C = ag.C, Cr = ag.Cr, Q = ag.Q, R = ag.R, Cf = ag.Cf, Qf = ag.Qf,
                             input = nothing, kind = ag.kind) for ag in agents]
    end
    present = trues(length(edges), H)
    if switching > 0
        for k in eachindex(edges), t in 1:H
            present[k, t] = rand(rng) >= switching
        end
    end
    weights = [0.5 + rand(rng) for _ in edges, _ in 1:H]
    fl = Fleet(agents, edges; H = H, offsets = slots, weights = weights, present = present)
    tau = time_varying ? [0.0; cumsum(h)] : 0.2 .* (0:H)
    refs = Matrix{Float64}[]; term = Vector{Float64}[]
    for i in 1:n
        quad = ks[i] == :quad
        amp, om, ph = 0.3 + 0.5 * rand(rng), 0.5 + rand(rng), 2pi * rand(rng)
        R = zeros(quad ? 3 : 2, H + 1)
        for t in 0:H
            p = [tau[t+1], 0.3 * sin(0.5 * tau[t+1])] + slots[i]
            coherent || (p += amp * [sin(om * tau[t+1] + ph) - sin(ph), cos(om * tau[t+1] + ph) - cos(ph)])
            R[1:2, t+1] = p
            quad && (R[3, t+1] = 1.5)
        end
        v = [1.0, 0.15 * cos(0.5 * tau[end])]
        push!(refs, R); push!(term, quad ? [R[:, end]; v; 0.0] : [R[:, end]; v])
    end
    x0 = [ks[i] == :quad ? [slots[i]; 1.5; 1.0; 0.15; 0.0] : [slots[i]; 1.0; 0.15] for i in 1:n]
    if !start_in_formation
        x0 = [x + 0.2 * randn(rng, length(x)) for x in x0]
    end
    fp = FleetProgram(fl; x0 = x0, references = refs, terminal = term, absent = absent)
    return fp, (refs = refs, terminal = term, x0 = x0, slots = slots, kinds = ks)
end

"""A random interval partition of the instants 0..H."""
function random_blocking(H, rng; p = 0.5)
    beta = ones(Int, H + 1)
    for t in 1:H
        beta[t+1] = beta[t] + (rand(rng) < p ? 1 : 0)
    end
    return beta
end

"""A random clustering of the agents into `k` teams, connected in the graph (region growing)."""
function random_teams(fl::Fleet, rng, k)
    n = nagents(fl)
    adj = [Int[] for _ in 1:n]
    for (i, j) in fl.edges
        push!(adj[i], j); push!(adj[j], i)
    end
    label = zeros(Int, n)
    for (c, s) in enumerate(randperm(rng, n)[1:k])
        label[s] = c
    end
    while any(==(0), label)
        cand = [(v, u) for v in 1:n if label[v] != 0 for u in adj[v] if label[u] == 0]
        isempty(cand) && (label[findfirst(==(0), label)] = rand(rng, 1:k); continue)
        v, u = rand(rng, cand)
        label[u] = label[v]
    end
    return canonical_partition(label)
end

"""Contract every edge of the program independently with probability `p` (connected blocks)."""
function random_contraction(P::SheafProgram, rng; p = 0.4)
    parent = collect(1:nvertices(P))
    find(a) = (while parent[a] != a; parent[a] = parent[parent[a]]; a = parent[a]; end; a)
    for E in P.edges
        rand(rng) < p || continue
        a, b = find(E.tail), find(E.head)
        a != b && (parent[max(a, b)] = min(a, b))
    end
    return canonical_partition([find(v) for v in 1:nvertices(P)])
end

"""The resolutions the tests sweep: time leg, agent leg, corner, teams, product, random contraction."""
function test_resolutions(fp::FleetProgram, rng)
    fl = fp.fleet
    H = fl.H
    return ["time leg" => full_condensing(), "agent leg" => Teams(ones(Int, nagents(fl))),
            "corner" => VertexPartition(ones(Int, nvertices(fp.program))),
            "teams" => Teams(random_teams(fl, rng, 2)),
            "product" => Teams(random_teams(fl, rng, 2)) ⊠ TimeBlocking(random_blocking(H, rng)),
            "random" => VertexPartition(random_contraction(fp.program, rng))]
end

test_solve(P) = solve(P; eps_abs = 1e-9, eps_rel = 1e-9, max_iter = 100_000)
