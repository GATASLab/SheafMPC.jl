# E74-mission: formations that are almost equitable because of how fleets are flown, not by construction.
#
# The objection: lossless teams were shown on planted squads (transport-plan edges, squads_dc.jl) and on the
# E26 grid (rows, 4-neighbour springs). Here the formation graph is the sensing graph of a standard geometric
# formation (every pair of vehicles closer than a radius is joined, stiffness 1/d), the data classes are what the
# mission fixes (type, and which vehicles share a reference), and colour refinement (within = false) from the
# classes returns phi*. Nothing is chosen to make phi* coarse. Families (E74_VARIANTS, sizes E74_SIZES):
#
#   lattice, drone light show: a x a x c cubic lattice, spacing 1, every altitude layer flies its own reference
#     (classes = layers)
#     L6      face neighbours only (radius 1.01)
#     L26     face, edge and corner neighbours (radius 1.74), stiffness 1/d: layer boundaries break equitability
#     L26bal  L26 with the stiffness between two adjacent layers balanced (below)
#     Lfig    L6, but the classes are a figure: the drones inside a ball fly one reference, the rest another
#   rings
#     Ccyl    a cylinder show: c stacked rings of m drones (arc spacing 1, layer spacing 1, radius 1.5), classes =
#             rings (rotation makes every ring one orbit even with diagonal springs)
#     Rden    concentric planar rings of uniform density (ring k: 6k drones at radius k, angle 2 pi j / 6k),
#             radius 1.5, classes = rings
#     Rbal    Rden balanced
#   convoy / platoon: 4 lanes of cars (lane width 1.5, gap 2), lanes alternate two car variants, classes = lanes
#     C1      predecessor-follower in a lane, side-by-side across lanes (radius 2.01)
#     C3      plus the diagonal neighbours in the next lane (radius 2.6)
#     C3bal   C3 balanced
#   warehouse: A aisles of ground robots (aisle pitch 3, gap 1), aisles alternate two flow schedules (classes =
#     the 2 aisle parities; colour refinement must find the aisles itself)
#     W1      in-aisle springs (radius 3.01) and the robot at the same rack index in the next aisle
#     W3      plus its two neighbours (radius 3.2)
#     W3bal   W3 balanced between adjacent aisles
#   escort: 4 lanes of cars as C, one drone 1.5 above every car, drones spring-coupled like the cars
#     E1      radius 2.01 (car-car and drone-drone as C1, drone-car vertical), classes = (type, lane)
#     E1t     E1 with classes = (type, variant) only (3 classes; the lanes are not given)
#     E3      radius 2.6 (adds diagonals and the drone to the cars ahead, behind and beside), classes = (type, lane)
#     E3bal   E3 balanced
#
# Balancing (the boundary compensation): for every pair of adjacent groups (classes; aisles for W) the stiffness
# of the edges between them is rescaled by bipartite Sinkhorn scaling, w_e <- r_i w_e c_j, so that every member
# of A has total weight T/|A| into B and every member of B has T/|B| into A, T the total weight before. The
# formation graph, the total stiffness between the groups and the support are unchanged; boundary vehicles get
# stiffer springs. Groups then are almost equitable by construction of the weights (a design rule, not a
# planted graph). The residual marginal error is recorded.
#
# E74_MODE=part   per (variant, size): |V|, |E|, |tau|, |phi*| (colour refinement, within = false), its time
#                 (median of 3 after a warm-up), the equitable count (within = true; a lower bound on the orbits
#                 symmetric MPC would use), spread(phi*) (0 = almost equitable), team sizes
# E74_MODE=solve  per variant at E74_N: the nominal closed loop of team MPC on phi* (E74_STEPS steps). At every
#                 step the full condensed program (Clarabel, tol 1e-9, e63_gap.jl) and the QUOTIENT program of
#                 phi* (one agent per team, an independent build as in e51_symmetric.jl: weights times the team
#                 size, edges between two teams merged), its plan broadcast to the members; gap = J(broadcast) - J*,
#                 the largest input difference, wall times (data, setup and solve); and, with E74_MPC=1, one step
#                 of the package's MPCController (full_condensing, defaults) on the full fleet and on the
#                 quotient, timed, inputs compared.
# E74_MODE=merge  parts -> results/e74_mission.json
#
#   E74_MODE=part E74_SIZES=256 julia --project=env scripts/resolution/experiments/e74_mission.jl
#   E74_MODE=solve E74_N=256 E74_VARIANTS=L26 julia --project=env scripts/resolution/experiments/e74_mission.jl

ENV["BENCH_INSTANCE"] = "squads"
ENV["E63_REG"] = "0"
const E63PATH74 = joinpath(@__DIR__, "e63_gap.jl")
include_string(Main, read(E63PATH74, String), E63PATH74)

const ALLV74 = ["L6", "L26", "L26bal", "Lfig", "Ccyl", "Rden", "Rbal", "C1", "C3", "C3bal", "W1", "W3", "W3bal",
                "E1", "E1t", "E3", "E3bal"]
const MODE74 = get(ENV, "E74_MODE", "part")
const VARIANTS74 = split(get(ENV, "E74_VARIANTS", join(ALLV74, ",")), ",")
const SIZES74 = parse.(Int, split(get(ENV, "E74_SIZES", "256,1024,4096,16384"), ","))
const N74 = parse(Int, get(ENV, "E74_N", "1024"))
const STEPS74 = parse(Int, get(ENV, "E74_STEPS", "3"))
const MPC74 = get(ENV, "E74_MPC", "1") == "1"
const SEED74 = parse(Int, get(ENV, "E74_SEED", "1"))
const PARTDIR74 = get(ENV, "E74_PARTDIR", joinpath(ROOT27, "bench", "irregular", "results", "parts74"))
const OUT74 = get(ENV, "E74_OUT", joinpath(ROOT27, "results", "e74_mission.json"))

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

"""Every pair of points closer than r (cell list), i < j."""
function radius_edges74(P::Vector{Vector{Float64}}, r::Float64)
    cell = Dict{NTuple{3,Int},Vector{Int}}()
    key(p) = (floor(Int, p[1] / r), floor(Int, p[2] / r), floor(Int, p[3] / r))
    for (i, p) in enumerate(P)
        push!(get!(cell, key(p), Int[]), i)
    end
    E = Tuple{Int,Int}[]
    for (i, p) in enumerate(P)
        (a, b, c) = key(p)
        for da in -1:1, db in -1:1, dc in -1:1, j in get(cell, (a + da, b + db, c + dc), Int[])
            j > i && norm(P[j] - P[i]) < r && push!(E, (i, j))
        end
    end
    return sort!(E)
end

"""
Bipartite Sinkhorn balancing of the edges between every pair of distinct groups: afterwards every member of A
has total weight T/|A| into B and every member of B T/|B| into A (T the pair's total before). Returns the new
weights, the largest relative spread of the balanced pulls and the number of group pairs with a member that has no edge into
the other group (those cannot be balanced; left as they are).
"""
function balance74(n, edges, w, groups; tol = 1e-14, maxit = 3000)
    w = copy(w); g = groups
    pairs = Dict{Tuple{Int,Int},Vector{Int}}()
    for (k, (i, j)) in enumerate(edges)
        g[i] == g[j] && continue
        push!(get!(pairs, minmax(g[i], g[j]), Int[]), k)
    end
    gsize = Dict{Int,Int}(); for i in 1:n; gsize[g[i]] = get(gsize, g[i], 0) + 1; end
    worst = 0.0; bad = 0
    for ((A, B), ks) in pairs
        ia = [g[i] == A ? i : j for (i, j) in edges[ks]]       # the A end of every edge
        jb = [g[i] == A ? j : i for (i, j) in edges[ks]]
        if length(unique(ia)) < gsize[A] || length(unique(jb)) < gsize[B]
            bad += 1; continue
        end
        T = sum(w[ks]); a = T / gsize[A]; b = T / gsize[B]
        r = ones(n); c = ones(n); w0 = w[ks]
        rs = zeros(n); cs = zeros(n); err = Inf; it = 0
        while err > 1e-11 && it < maxit
            it += 1
            fill!(rs, 0.0)
            for q in eachindex(ks); rs[ia[q]] += w0[q] * c[jb[q]]; end
            for i in unique(ia); r[i] = a / rs[i]; end
            fill!(cs, 0.0)
            for q in eachindex(ks); cs[jb[q]] += r[ia[q]] * w0[q]; end
            for j in unique(jb); c[j] = b / cs[j]; end
            # row error after the column update
            fill!(rs, 0.0)
            for q in eachindex(ks); rs[ia[q]] += r[ia[q]] * w0[q] * c[jb[q]]; end
            err = maximum(abs(rs[i] - a) / a for i in unique(ia))
        end
        # Newton polish (Sinkhorn is slow on long chains): F(r, c) = (r .* (K c) - a, c .* (K' r) - b) = 0 on
        # the vehicles of A and B; the scaling direction (t r, c / t) is a null direction, so a tiny shift
        ua = unique(ia); ub = unique(jb); pa = Dict(i => k for (k, i) in enumerate(ua)); pb = Dict(j => k for (k, j) in enumerate(ub))
        na_ = length(ua); nb_ = length(ub)
        Ks = sparse([pa[i] for i in ia], [pb[j] for j in jb], w0, na_, nb_)
        rv = r[ua]; cv = c[ub]
        for _ in 1:40
            Kc = Ks * cv; Ktr = Ks' * rv
            F = [rv .* Kc .- a; cv .* Ktr .- b]
            err = max(maximum(abs.(F[1:na_])) / a, maximum(abs.(F[na_+1:end])) / b)
            err <= 1e-15 && break
            J = [spdiagm(Kc) spdiagm(rv) * Ks; spdiagm(cv) * Ks' spdiagm(Ktr)] + 1e-13 * I
            d = J \ F
            rv .-= d[1:na_]; cv .-= d[na_+1:end]
        end
        all(>(0), rv) && all(>(0), cv) || error("balancing lost positivity")
        r[ua] .= rv; c[ub] .= cv
        Kc = Ks * cv; Ktr = Ks' * rv
        # the error that matters: the spread of the pulls (a common factor on the total is harmless)
        ra = rv .* Kc; cb = cv .* Ktr
        err = max((maximum(ra) - minimum(ra)) / mean(ra), (maximum(cb) - minimum(cb)) / mean(cb))
        for (q, k) in enumerate(ks)
            w[k] = r[ia[q]] * w0[q] * c[jb[q]]
        end
        worst = max(worst, err)
    end
    return w, worst, bad
end

# ---------------------------------------------------------------------------
# The mission formations
# ---------------------------------------------------------------------------

"""Lattice dimensions (a, a, c) for a target size."""
latdims74(N) = N <= 256 ? (8, 4) : N <= 1024 ? (16, 4) : N <= 4096 ? (16, 16) : (32, 16)

"""
    mission74(variant, N) -> NamedTuple (the fields of squads_instance, plus pos, groups, info)

pos the geometric positions (stiffness 1/d from them), slots the formation slots (= pos), groups the
balancing groups.
"""
function mission74(v::AbstractString, N::Int)
    fam = v[1]
    pos = Vector{Vector{Float64}}(); kinds = Symbol[]; var = Int[]; class = Int[]; groups = Int[]
    radius = 0.0; balance = endswith(v, "bal"); info = Dict{String,Any}()
    if fam == 'L'
        a, c = latdims74(N)
        for z in 1:c, y in 1:a, x in 1:a
            push!(pos, [x, y, z] .- 1.0); push!(kinds, :drone); push!(var, 1); push!(class, z); push!(groups, z)
        end
        radius = v in ("L6", "Lfig") ? 1.01 : 1.74
        if v == "Lfig"
            cen = [(a - 1) / 2 + 0.3, (a - 1) / 2 - 0.2, (c - 1) / 2 + 0.1]; rad = 0.35 * min(a, c) + 0.6
            class = [norm(p - cen) <= rad ? 1 : 2 for p in pos]; groups = copy(class)
        end
        info["dims"] = [a, a, c]
    elseif v == "Ccyl"
        c = 16; m = div(N, c); R = m / (2pi)
        for z in 1:c, j in 0:(m-1)
            push!(pos, [R * cos(2pi * j / m), R * sin(2pi * j / m), z - 1.0]); push!(kinds, :drone); push!(var, 1)
            push!(class, z); push!(groups, z)
        end
        radius = 1.5; info["dims"] = [m, c]
    elseif fam == 'R'
        K = N <= 256 ? 9 : N <= 1024 ? 18 : N <= 4096 ? 37 : 73
        for k in 1:K, j in 0:(6k-1)
            push!(pos, [k * cos(2pi * j / (6k)), k * sin(2pi * j / (6k)), 0.0]); push!(kinds, :drone); push!(var, 1)
            push!(class, k); push!(groups, k)
        end
        radius = 1.5; info["dims"] = [K]
    elseif fam == 'C' || fam == 'E'
        L = 4; M = fam == 'C' ? div(N, L) : div(N, 2L)
        for l in 1:L, j in 1:M
            push!(pos, [2.0 * (j - 1), 1.5 * (l - 1), 0.0]); push!(kinds, :car); push!(var, isodd(l) ? 1 : 2)
            push!(class, l); push!(groups, l)
        end
        if fam == 'E'
            for l in 1:L, j in 1:M
                push!(pos, [2.0 * (j - 1), 1.5 * (l - 1), 1.5]); push!(kinds, :drone); push!(var, 1)
                push!(class, v == "E1t" ? 0 : L + l); push!(groups, L + l)
            end
            # E1t: classes = (type, variant) only (cars of the two variants, drones)
            v == "E1t" && (class = [kinds[i] == :car ? var[i] : 3 for i in eachindex(kinds)])
        end
        radius = v in ("C1", "E1", "E1t") ? 2.01 : 2.6
        info["dims"] = [L, M]
    elseif fam == 'W'
        A = N <= 256 ? 8 : N <= 1024 ? 16 : N <= 4096 ? 32 : 64; S = div(N, A)
        for al in 1:A, j in 1:S
            push!(pos, [3.0 * (al - 1), 1.0 * (j - 1), 0.0]); push!(kinds, :car); push!(var, 1)
            push!(class, isodd(al) ? 1 : 2); push!(groups, al)
        end
        radius = v == "W1" ? 3.01 : 3.2
        info["dims"] = [A, S]
    else
        error("unknown variant $v")
    end
    n = length(pos)
    edges = radius_edges74(pos, radius)
    w = [1 / norm(pos[j] - pos[i]) for (i, j) in edges]
    info["balance_err"] = 0.0; info["balance_bad"] = 0
    if balance
        w0 = copy(w)
        w, err, bad = balance74(n, edges, w, groups)
        info["balance_err"] = err; info["balance_bad"] = bad
        ch = [w[k] / w0[k] for k in eachindex(w) if groups[edges[k][1]] != groups[edges[k][2]]]
        info["balance_factor"] = Dict("min" => minimum(ch), "max" => maximum(ch), "median" => median(ch))
    end
    class = SM.canonical_partition(class)
    params = [sq_params(kinds[i], var[i]) for i in 1:n]
    info["radius"] = radius
    return (slots = [copy(p) for p in pos], pos = pos, edges = edges, w = w, kinds = kinds, variant = var, squad = groups,
            class = class, groups = groups, params = params, cross = [class[i] != class[j] for (i, j) in edges],
            nsquads = maximum(class), variants = 2, eps = 0.0, spread = 0.0, info = info)
end

"""One lane per class (distinct references per class; coherent inside a class)."""
lanes74(inst, seed) = [(i = findfirst(==(c), inst.class); dc_lanes(seed + 101 * c)[inst.kinds[i] == :drone ? 1 : 2])
                       for c in 1:maximum(inst.class)]

# ---------------------------------------------------------------------------
# Partitions
# ---------------------------------------------------------------------------

refines73(fine, coarse) = all(length(unique(coarse[fine .== T])) == 1 for T in unique(fine))

"""Active limits (balls or boxes) of a plan (as e73_exactgap.jl)."""
function active73(cf, K::Cons63, u; tol = 1e-6)
    na = 0
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        ui = u[uidx(cf, i, t)]; um = cf.agents[i].umax
        na += K.cone == :soc ? (norm(ui) >= (1 - tol) * um) : count(abs.(ui) .>= (1 - tol) * um)
    end
    return na
end

function part74(v, N)
    inst = mission74(v, N); n = length(inst.kinds)
    cr() = SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = false))
    cr()
    ts = [@elapsed(cr()) for _ in 1:3]
    aep = cr()
    te = @elapsed (eqp = SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = true)))
    sp = sq_spread(n, inst.edges, inst.w, aep)[1]
    sz = [count(==(c), aep) for c in 1:maximum(aep)]
    return Dict{String,Any}("variant" => v, "N" => N, "n" => n, "edges" => length(inst.edges), "classes" => maximum(inst.class),
        "teams" => maximum(aep), "reduction" => n / maximum(aep), "cr_seconds" => median(ts), "cr_seconds_all" => ts,
        "equitable_teams" => maximum(eqp), "equitable_seconds" => te, "spread" => sp,
        "aep_refines_classes" => refines73(aep, inst.class), "singletons" => count(==(1), sz),
        "team_size" => Dict("min" => minimum(sz), "median" => median(sz), "max" => maximum(sz)),
        "balance_err" => inst.info["balance_err"], "balance_bad" => inst.info["balance_bad"],
        "balance_factor" => get(inst.info, "balance_factor", nothing), "dims" => inst.info["dims"],
        "radius" => inst.info["radius"])
end

# ---------------------------------------------------------------------------
# The quotient program of a coherent partition (generic form of e51_symmetric.jl's Quot51)
# ---------------------------------------------------------------------------

function scaled51(ag::SM.Agent, m::Real)
    return SM.Agent(ag.A[1], ag.B[1]; C = ag.C, Cr = ag.Cr, Q = m * ag.Q, R = m * ag.R, Cf = ag.Cf, Qf = m * ag.Qf,
                    g = ag.g[1], input = ag.input, kind = ag.kind)
end

"""MPCController on the condensed program, the package's default accuracy and warm start (as e51)."""
controller51(fl::SM.Fleet; settings = SM.Settings()) = SM.MPCController(fl, SM.full_condensing(); certify = false, settings = settings)

slotstate74(inst, ag, i) = (d = div(ag.nx, 2); [inst.slots[i][1:d]; zeros(ag.nx - d)])

function quot74(fl::SM.Fleet, inst, lab::Vector{Int})
    nt = maximum(lab); H = fl.H; p = size(fl.agents[1].C, 1)
    teams = [findall(==(c), lab) for c in 1:nt]
    for m in teams
        all(i -> inst.class[i] == inst.class[m[1]] && fl.agents[i].kind == fl.agents[m[1]].kind &&
                 inst.params[i] == inst.params[m[1]], m) ||
            error("team mixes data classes")
    end
    Delta = [slotstate74(inst, fl.agents[i], i) for i in eachindex(lab)]
    ags = [scaled51(fl.agents[first(m)], length(m)) for m in teams]
    acc = Dict{Tuple{Int,Int},Any}()
    for (k, (i, j)) in enumerate(fl.edges)
        a, b = lab[i], lab[j]
        a == b && continue
        s = 1.0
        a > b && ((a, b) = (b, a); s = -1.0)
        rel = fl.agents[j].C * Delta[j] - fl.agents[i].C * Delta[i]
        e = get!(acc, (a, b), (W = zeros(H), Wb = zeros(p, H), S = fl.select[k]))
        e.S == fl.select[k] || error("edges between two teams compare different coordinates")
        for t in 1:H
            fl.present[k, t] || continue
            e.W[t] += fl.weights[k, t]
            e.Wb[:, t] .+= fl.weights[k, t] .* (s .* (fl.targets[:, k, t] .- rel))
        end
    end
    qedges = sort!(collect(keys(acc))); ne = length(qedges)
    Wm = zeros(ne, H); T = zeros(p, ne, H)
    for (k, key) in enumerate(qedges)
        e = acc[key]; Wm[k, :] .= e.W
        for t in 1:H
            T[:, k, t] .= e.W[t] > 0 ? e.Wb[:, t] ./ e.W[t] : 0.0
        end
    end
    fq = SM.Fleet(ags, qedges; H = H, targets = T, weights = Wm, select = [acc[key].S for key in qedges])
    return (fleet = fq, teams = teams, lab = lab, Delta = Delta)
end

function teamdata74(Q, fl, x, refs, term)
    nt = length(Q.teams)
    xq = Vector{Vector{Float64}}(undef, nt); rq = Vector{Matrix{Float64}}(undef, nt); tq = Vector{Vector{Float64}}(undef, nt)
    @inbounds for (c, m) in enumerate(Q.teams)
        ag = fl.agents[m[1]]; w = 1.0 / length(m)
        xc = zeros(ag.nx); Rc = zeros(size(refs[m[1]])); tc = zeros(length(term[m[1]]))
        for i in m
            D = Q.Delta[i]
            xc .+= w .* (x[i] .- D); Rc .+= w .* (refs[i] .- ag.Cr * D); tc .+= w .* (term[i] .- ag.Cf * D)
        end
        xq[c] = xc; rq[c] = Rc; tq[c] = tc
    end
    return xq, rq, tq
end

function broadcast74(cf, cfq, lab, uq)
    u = zeros(ncols30(cf))
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        u[uidx(cf, i, t)] .= uq[uidx(cfq, lab[i], t)]
    end
    return u
end

function solve74(v, N; steps = STEPS74, seed = SEED74, mpc = MPC74, quiet = false)
    inst = mission74(v, N); n = length(inst.kinds)
    lab = SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = false))
    fl = sq_fleet(inst, DT63G, H63G, CONE63G)
    lanes = lanes74(inst, seed)
    cf = cfleet63(fl, H63G); K = Cons63(cf, CONE63G)
    x0, _, _ = sq_start(inst, fl, seed)
    refsk(k) = sq_references(inst, lanes, fl, k * DT63G, DT63G, H63G)
    r0 = refsk(0)
    tb_full = @elapsed begin
        base = CProg(cf, CData(x0, r0[1], r0[2]))
        Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
    end
    tb_team = @elapsed begin
        Q = quot74(fl, inst, lab)
        cfq = cfleet63(Q.fleet, H63G); Kq = Cons63(cfq, CONE63G)
        xq0, rq0, tq0 = teamdata74(Q, fl, x0, r0[1], r0[2])
        baseq = CProg(cfq, CData(xq0, rq0, tq0))
        Hbq = sparse(H0blk30(cfq) + baseq.A' * baseq.Wd * baseq.A)
    end
    res = Dict{String,Any}("variant" => v, "N" => N, "n" => n, "teams" => maximum(lab), "classes" => maximum(inst.class),
                           "edges" => length(inst.edges), "quotient_edges" => length(Q.fleet.edges),
                           "vars_full" => ncols30(cf), "vars_team" => ncols30(cfq), "build_full_s" => tb_full,
                           "build_team_s" => tb_team, "cone" => string(CONE63G), "H" => H63G)
    Cc = Cq = nothing
    if mpc
        res["mpc_build_full_s"] = @elapsed (Cc = controller51(fl))
        res["mpc_build_team_s"] = @elapsed (Cq = controller51(Q.fleet))
    end
    x = [copy(z) for z in x0]; recs = Dict{String,Any}[]
    for k in 0:(steps-1)
        refs, term = refsk(k)
        GC.gc()
        t_full = @elapsed begin
            P = CProg(base, CData(x, refs, term)); _, hq, c = quad63(P, Hb)
            full = solve63(Hb, hq, c, K, nothing; E = P.E, e = P.e)
        end
        GC.gc()
        t_team = @elapsed begin
            xq, rq, tq = teamdata74(Q, fl, x, refs, term)
            Pq = CProg(baseq, CData(xq, rq, tq)); _, hqq, cq = quad63(Pq, Hbq)
            tm = solve63(Hbq, hqq, cq, Kq, nothing; E = Pq.E, e = Pq.e)
            ub = broadcast74(cf, cfq, lab, tm.u)
        end
        Jb = J63(Hb, hq, c, ub)
        rec = Dict{String,Any}("step" => k, "Jstar" => full.J, "Jteam" => Jb, "gap" => Jb - full.J,
            "gap_rel" => (Jb - full.J) / abs(full.J), "input_diff" => maximum(abs.(ub - full.u)),
            "input_scale" => maximum(abs.(full.u)), "active_full" => active73(cf, K, full.u),
            "t_full" => t_full, "t_team" => t_team, "t_solve_full" => full.seconds, "t_solve_team" => tm.seconds,
            "iters" => [full.iters, tm.iters], "status" => [full.status, tm.status])
        if mpc
            GC.gc()
            tc = @elapsed (ic = SM.step!(Cc, x, refs; terminal = term))
            GC.gc()
            tt = @elapsed begin
                xq, rq, tq = teamdata74(Q, fl, x, refs, term)
                iq = SM.step!(Cq, xq, rq; terminal = tq)
                uqm = [iq.u[lab[i]] for i in 1:n]
            end
            rec["mpc_t_full"] = tc; rec["mpc_t_team"] = tt
            rec["mpc_input_diff"] = maximum(maximum(abs.(uqm[i] - ic.u[i])) for i in 1:n)
            rec["mpc_status"] = [string(ic.status), string(iq.status)]
        end
        push!(recs, rec)
        quiet || @printf("  %-6s n %5d teams %4d step %d  gap/J* %.1e  du %.1e (|u| %.2f)  active %d  t full %.3f s team %.4f s%s\n",
                         v, n, maximum(lab), k, rec["gap_rel"], rec["input_diff"], rec["input_scale"], rec["active_full"],
                         t_full, t_team, mpc ? @sprintf("  mpc full %.3f team %.4f du %.1e", rec["mpc_t_full"], rec["mpc_t_team"], rec["mpc_input_diff"]) : "")
        flush(stdout)
        x = sq_plant(fl, x, first63(cf, ub))
    end
    res["steps"] = recs
    return res
end

# ---------------------------------------------------------------------------

function main74()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR74)
    if MODE74 == "part"
        part74("L26", 256)
        for v in VARIANTS74, N in SIZES74
            r = part74(v, N)
            @printf("%-6s N %5d n %5d |E| %6d |tau| %4d |phi*| %5d  red %7.1f  cr %.4f s  equitable %5d  spread %.1e  singletons %d  bal %.1e/%d\n",
                    v, N, r["n"], r["edges"], r["classes"], r["teams"], r["reduction"], r["cr_seconds"], r["equitable_teams"],
                    r["spread"], r["singletons"], r["balance_err"], r["balance_bad"]); flush(stdout)
            open(io -> JSON.print(io, r, 1), joinpath(PARTDIR74, "part_$(v)_N$(N).json"), "w")
        end
    else
        solve74("L26", 64; steps = 1, quiet = true, mpc = MPC74)      # warm-up
        for v in VARIANTS74
            @printf("E74 solve %s N %d\n", v, N74); flush(stdout)
            r = solve74(v, N74)
            r["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                             "cpu" => Sys.cpu_info()[1].model)
            open(io -> JSON.print(io, r, 1), joinpath(PARTDIR74, "solve_$(v)_N$(N74).json"), "w")
        end
    end
end

function merge74()
    parts = Dict{String,Any}(); solves = Dict{String,Any}()
    for f in sort(readdir(PARTDIR74))
        endswith(f, ".json") || continue
        r = JSON.parsefile(joinpath(PARTDIR74, f))
        key = "$(r["variant"])_N$(r["N"])"
        startswith(f, "part_") ? (parts[key] = r) : (solves[key] = r)
    end
    for r in values(solves)
        st = r["steps"]
        r["summary"] = Dict{String,Any}(
            "gap_rel_max" => maximum(abs(s["gap_rel"]) for s in st), "input_diff_max" => maximum(s["input_diff"] for s in st),
            "active_full_max" => maximum(s["active_full"] for s in st),
            "t_full_med" => median([s["t_full"] for s in st]), "t_team_med" => median([s["t_team"] for s in st]),
            "speedup_med" => median([s["t_full"] / s["t_team"] for s in st]),
            "all_solved" => all(all(==("SOLVED"), uppercase.(string.(s["status"]))) for s in st))
        if haskey(st[1], "mpc_t_full")
            r["summary"]["mpc_t_full_med"] = median([s["mpc_t_full"] for s in st])
            r["summary"]["mpc_t_team_med"] = median([s["mpc_t_team"] for s in st])
            r["summary"]["mpc_speedup_med"] = median([s["mpc_t_full"] / s["mpc_t_team"] for s in st])
            r["summary"]["mpc_input_diff_max"] = maximum(s["mpc_input_diff"] for s in st)
        end
    end
    out = Dict{String,Any}("experiment" => "E74 mission formations: colour refinement from mission classes on geometric sensing graphs (stiffness 1/d), lossless team MPC vs centralized",
                           "partitions" => parts, "solves" => solves)
    open(io -> JSON.print(io, out, 1), OUT74, "w")
    println("wrote $OUT74")
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE74 == "merge" ? merge74() : main74()
end
