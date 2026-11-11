# E63-gap: lossy teams on an irregular formation; the true gap, the certificate, a dual bound, kappa, and the
# closed-loop cost of team MPC against coordinated MPC and the lossy baselines.
#
# Instance (squads_dc.jl, BENCH_INSTANCE): natural (default here: random geometric graph, stiffness 1/d, spatial
# regions of one type and variant each = the data classes, nothing planted) or squads (planted, with
# BENCH_SQ_EPS > 0 for perturbed equal totals).
#
# Everything is condensed (E30's CFleet/CProg: the decision is u, every vehicle's inputs over the horizon):
# J(u) = 1/2 u'Hb u + hq'u + c, Hb the full Hessian (own costs and every formation edge), input sets per vehicle
# and instant (balls, or boxes with E63_CONE=box).
#
# Per team choice (E63_CHOICES: qs<q> quasi-stable colouring of the classes, Kayali-Suciu greedy, q relative;
# geo<k> k-means teams inside each class; classes; aep exact colour refinement), the team closed loop of
# E63_STEPS steps (nominal plant; the team plan's first inputs applied; teams stay rigid). At every step:
#   J*        the full program, Clarabel (tol 1e-9)
#   J_team    min J over team plans u = Z v (Z = chi kron I per instant: members copy their team's inputs),
#             Clarabel, one cone per team and instant (identical members: their cones coincide); gap = J_team - J*
#   eta       Thm. thm:cert at the team plan (the measured state: nominal loop, no projection error): per team
#             1/2 g'H_S^{-1}g, g the gradient of J without the team's internal edges, minimized over the normal
#             cone of the active constraints (NNLS per team); its time and per-team time
#   dual      a Lagrangian (aggregation, Zipkin-style) bound: the team solve's cone multipliers split evenly over
#             the members give multipliers of the full program, d(z) = min_u L(u, z) <= J* in closed form
#             (one solve with Hb, which the team method avoids; reported for comparison): J_team - d(z) >= gap
#   kappa     lambda_max(H_S^{-1} Hb) by power iteration (step 0)
#   stage     the stage cost l_k of the applied inputs (formation included), its part across teams (energy of the
#             cross-team residuals rho_k), sigma_k = eta_k / l_k
# Baselines (closed loops of the same length, cost only): coordinated MPC (J* plans), decentralized MPC (every
# class plans alone: edges between classes dropped), move blocking (inputs held over E63_BLOCK instants).
#
#   BENCH_INSTANCE=natural E63_N=256 E63_SEEDS=1 julia --project=env scripts/resolution/experiments/e63_gap.jl

haskey(ENV, "BENCH_INSTANCE") || (ENV["BENCH_INSTANCE"] = "natural")
include(joinpath(@__DIR__, "e30_bounds_dc.jl"))
include(joinpath(@__DIR__, "squads_dc.jl"))
using SparseArrays, LinearAlgebra

const N63G = parse(Int, get(ENV, "E63_N", "256"))
const SEEDS63G = parse.(Int, split(get(ENV, "E63_SEEDS", "1"), ","))
const STEPS63G = parse(Int, get(ENV, "E63_STEPS", "20"))
const CONE63G = Symbol(get(ENV, "E63_CONE", "soc"))
const CHOICES63G = split(get(ENV, "E63_CHOICES", "aep,qs0.5,qs1,qs2,qs4,qs8,geo4,geo8,classes"), ",")
const BASE63G = split(get(ENV, "E63_BASELINES", "coord,decentral,moveblock"), ",")
const BLOCK63G = parse(Int, get(ENV, "E63_BLOCK", "2"))
const TOL63G = 1e-9
const INST63G = get(ENV, "BENCH_INSTANCE", "natural")
const PARTDIR63G = get(ENV, "E63_PARTDIR", joinpath(ROOT27, "bench", "irregular", "results", "parts63g"))
const H63G = 10
const REG63G = get(ENV, "E63_REG", "0") == "1"       # regulation: constant formation-consistent equilibrium, terminal equality
const DT63G = 0.2

# ---------------------------------------------------------------------------
# The condensed program of a fleet and its input constraints
# ---------------------------------------------------------------------------

"""E30's condensed fleet of a TeamMPC fleet (Cf = I, diagonal Q); umax the ball radius or the box half-width."""
function cfleet63(fl::SM.Fleet, H::Int; terminal::Symbol = REG63G ? :equality : :cost)
    ags = [CAgent(ag.A[1], ag.B[1], ag.g[1], ag.C, ag.Cr, ag.Q, ag.R, ag.Cf' * ag.Qf * ag.Cf,
                  ag.input isa SM.BallSet ? ag.input.radius : ag.input.hi[1]) for ag in fl.agents]
    spec = CSpec(H, collect(0:(H-1)), collect(1:H), terminal)
    W = [[fl.weights[k, t] * Matrix(1.0I, size(fl.select[k], 1), size(fl.select[k], 1)) for t in 1:H] for k in eachindex(fl.edges)]
    o = [[fl.select[k] * fl.targets[:, k, t] for t in 1:H] for k in eachindex(fl.edges)]
    return CFleet(ags, spec, fl.edges, W, o; maps = [SM.edge_maps(fl, k) for k in eachindex(fl.edges)])
end

"""Regulation references: every vehicle's equilibrium at its slot (a drone at altitude 1.5), at rest (formation-consistent)."""
function refs_reg63(inst, fl, H)
    n = length(inst.kinds)
    refs = Vector{Matrix{Float64}}(undef, n); term = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        ag = fl.agents[i]; d = size(ag.Cr, 1)
        p = (inst.slots[i] + [0.0, 0.0, 1.5])[1:d]
        refs[i] = repeat(p, 1, H + 1); term[i] = [p; zeros(d)]
    end
    return refs, term
end

"""The input constraints A u + s = b, s in K: one block per (vehicle, instant); kinds :soc or :box."""
struct Cons63
    A::SparseMatrixCSC{Float64,Int}
    b::Vector{Float64}
    blocks::Vector{UnitRange{Int}}
    owner::Vector{Tuple{Int,Int}}       # (vehicle, instant) of every block
    cone::Symbol
end

function Cons63(cf::CFleet, cone::Symbol)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]; b = Float64[]; blocks = UnitRange{Int}[]; owner = Tuple{Int,Int}[]; r = 0
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        nu = cf.nus[i]; ix = uidx(cf, i, t); um = cf.agents[i].umax
        if cone == :soc
            push!(b, um); append!(b, zeros(nu))
            for a in 1:nu
                push!(I_, r + 1 + a); push!(J_, ix[a]); push!(V_, -1.0)
            end
            push!(blocks, (r+1):(r+1+nu)); r += 1 + nu
        else
            for a in 1:nu
                push!(I_, r + a); push!(J_, ix[a]); push!(V_, 1.0)
                push!(I_, r + nu + a); push!(J_, ix[a]); push!(V_, -1.0)
            end
            append!(b, fill(um, 2nu))
            push!(blocks, (r+1):(r+2nu)); r += 2nu
        end
        push!(owner, (i, t))
    end
    return Cons63(sparse(I_, J_, V_, r, ncols30(cf)), b, blocks, owner, cone)
end

"""The full quadratic: Hb (sparse), hq, c with J(u) = 1/2 u'Hb u + hq'u + c."""
function quad63(P::CProg, Hb0)
    Hb = Hb0
    hq = P.h - P.A' * (P.Wd * P.b)
    c = P.c + 0.5 * dot(P.b, P.Wd * P.b)
    return Hb, hq, c
end
J63(Hb, hq, c, u) = 0.5 * dot(u, Hb * u) + dot(hq, u) + c

"""
min J(Z v) s.t. the input constraints on u = Z v, with Clarabel; identical constraint blocks after the
substitution are merged (`rep`). Returns u = Z v, J, status, seconds, the multipliers of the full blocks
(a merged block's multiplier split evenly over its copies), the number of cones.
"""
function solve63(Hb, hq, c, K::Cons63, Z; tol = TOL63G, E = nothing, e = nothing)
    t0 = time_ns()
    AZ = Z === nothing ? K.A : K.A * Z
    # terminal equality rows (identical rows after the substitution merged; their multipliers split evenly)
    erep = Int[]; ekept = Int[]; EZr = spzeros(0, size(AZ, 2)); er = Float64[]
    if E !== nothing && size(E, 1) > 0
        EZ = Z === nothing ? E : E * Z
        EZt = sparse(EZ'); seenE = Dict{Any,Int}(); erep = collect(1:size(EZ, 1))
        for i in 1:size(EZ, 1)
            key = (rowvals(EZt)[nzrange(EZt, i)], round.(nonzeros(EZt)[nzrange(EZt, i)]; digits = 10), round(e[i]; digits = 8))
            j = get(seenE, key, 0)
            j == 0 ? (seenE[key] = i; push!(ekept, i)) : (erep[i] = j)
        end
        EZr = EZ[ekept, :]; er = e[ekept]
    end
    nb = length(K.blocks)
    rep = collect(1:nb); seen = Dict{Any,Int}()
    AZt = sparse(AZ')
    for (k, B) in enumerate(K.blocks)
        key = ([(rowvals(AZt)[nzrange(AZt, i)], round.(nonzeros(AZt)[nzrange(AZt, i)]; digits = 12)) for i in B], K.b[B])
        j = get(seen, key, 0)
        j == 0 ? (seen[key] = k) : (rep[k] = j)
    end
    kept = [k for k in 1:nb if rep[k] == k]
    rows = reduce(vcat, (collect(K.blocks[k]) for k in kept))
    Ar = [EZr; AZ[rows, :]]; br = [er; K.b[rows]]
    cones = Clarabel.SupportedCone[]
    isempty(ekept) || push!(cones, Clarabel.ZeroConeT(length(ekept)))
    for k in kept
        L = length(K.blocks[k])
        push!(cones, K.cone == :soc ? Clarabel.SecondOrderConeT(L) : Clarabel.NonnegativeConeT(L))
    end
    Pm = Z === nothing ? Hb : sparse(Z' * Hb * Z)
    q = Z === nothing ? hq : Z' * hq
    st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol, max_iter = 400)
    S = Clarabel.Solver()
    Clarabel.setup!(S, sparse(triu((Pm + Pm') / 2)), q, sparse(Ar), br, cones, st)
    sol = Clarabel.solve!(S)
    secs = (time_ns() - t0) / 1e9
    v = copy(sol.x); u = Z === nothing ? v : Z * v
    ne = length(ekept)
    lam = zeros(length(erep))
    if ne > 0
        ecnt = zeros(Int, length(erep)); for i in eachindex(erep); ecnt[erep[i]] += 1; end
        epos = Dict(k => a for (a, k) in enumerate(ekept))
        for i in eachindex(erep)
            lam[i] = sol.z[epos[erep[i]]] / ecnt[erep[i]]
        end
    end
    zr = sol.z[(ne+1):end]
    cnt = zeros(Int, nb)
    for k in 1:nb
        cnt[rep[k]] += 1
    end
    pos = Dict{Int,UnitRange{Int}}(); off = 0
    for k in kept
        L = length(K.blocks[k]); pos[k] = (off+1):(off+L); off += L
    end
    zf = zeros(length(K.b))
    for k in 1:nb
        zf[K.blocks[k]] .= zr[pos[rep[k]]] ./ cnt[rep[k]]
    end
    return (u = u, J = J63(Hb, hq, c, u), status = string(sol.status), seconds = secs, zf = zf, lam = lam, cones = length(kept), iters = sol.iterations)
end

"""Z of a team map: every member's inputs at every instant equal its team's (members of a team share a type)."""
function teamZ63(cf::CFleet, lab::Vector{Int})
    H = cf.spec.H
    teams = sort(unique(lab)); col = Dict{Int,Int}(); off = 0
    for T in teams
        i = findfirst(==(T), lab); col[T] = off; off += cf.nus[i] * H
    end
    I_ = Int[]; J_ = Int[]
    for i in 1:nagents(cf), t in 0:(H-1), a in 1:cf.nus[i]
        push!(I_, uidx(cf, i, t)[a]); push!(J_, col[lab[i]] + t * cf.nus[i] + a)
    end
    return sparse(I_, J_, ones(length(I_)), ncols30(cf), off)
end

"""Z of move blocking: every vehicle's inputs held over blocks of `blk` instants."""
function blockZ63(cf::CFleet, blk::Int)
    H = cf.spec.H; nbk = cld(H, blk)
    I_ = Int[]; J_ = Int[]; off = 0
    for i in 1:nagents(cf)
        nu = cf.nus[i]
        for t in 0:(H-1), a in 1:nu
            push!(I_, uidx(cf, i, t)[a]); push!(J_, off + div(t, blk) * nu + a)
        end
        off += nbk * nu
    end
    return sparse(I_, J_, ones(length(I_)), ncols30(cf), off)
end

"""Lagrangian bound: d(z) = min_u J(u) + z'(A u - b) = c - 1/2 w'Hb^{-1} w - z'b, w = hq + A'z (z in the dual cone)."""
function dual63(F, hq, c, K::Cons63, z; E = nothing, e = nothing, lam = nothing)
    w = hq + K.A' * z
    E === nothing || size(E, 1) == 0 || (w .+= E' * lam)
    d = c - 0.5 * dot(w, F \ w) - dot(z, K.b)
    E === nothing || size(E, 1) == 0 || (d -= dot(lam, e))
    return d
end

"""lambda_max(AX H_S^{-1} AX'): power iteration, H_S^{-1} by the unrestricted team blocks."""
function nu63(ops::Vector{CertOp}, AX; iters::Int = 60)
    size(AX, 1) == 0 && return 0.0
    N = size(AX, 2)
    Hsinv(y) = (z = zeros(N); for op in ops; z[op.cols] .= op.L' \ (op.L \ y[op.cols]); end; z)
    x = randn(Xoshiro(7), size(AX, 1)); x ./= norm(x); lam = 0.0
    for _ in 1:iters
        y = AX * Hsinv(AX' * x)
        lam = dot(x, y); x = y / norm(y)
    end
    return lam
end

"""
Thm. thm:cert at the plan u: per team 1/2 ||R (g_T + N c)||^2 minimized over c >= 0 (NNLS), N the outward
normals of the active constraints of the team's members. Returns (eta, eta with c = 0, active, per-team
seconds).
"""
function cert63(P::CProg, ops::Vector{CertOp}, rest::RestOp, K::Cons63, u; tol = 1e-6)
    cf = P.cf; H = cf.spec.H
    g0 = grad_rest30(rest, P, u)
    eta = 0.0; eta0 = 0.0; nact = 0; tper = Float64[]
    for op in ops
        t0 = time_ns()
        y0 = op.R * g0[op.cols]
        val0 = 0.5 * dot(y0, y0); val = val0
        normals = Tuple{Vector{Int},Vector{Float64}}[]          # (team-local columns, direction)
        off = 0
        for i in op.members
            nu = cf.nus[i]; um = cf.agents[i].umax
            for t in 0:(H-1)
                ui = u[uidx(cf, i, t)]; cols = collect(off + t * nu .+ (1:nu))
                if K.cone == :soc
                    nz = norm(ui)
                    nz >= (1 - tol) * um && push!(normals, (cols, ui / nz))
                else
                    for a in 1:nu
                        ui[a] >= (1 - tol) * um && push!(normals, ([cols[a]], [1.0]))
                        ui[a] <= -(1 - tol) * um && push!(normals, ([cols[a]], [-1.0]))
                    end
                end
            end
            off += nu * H
        end
        na = length(normals); nact += na
        if na > 0
            Y = zeros(size(op.R, 1), na)
            for (k, (cc, d)) in enumerate(normals)
                mul!(view(Y, :, k), view(op.R, :, cc), d)
            end
            cc = max.(nnls30(Y' * Y, -(Y' * y0)), 0.0)
            yc = y0 + Y * cc
            val = min(val, 0.5 * dot(yc, yc))
        end
        eta += val; eta0 += val0
        push!(tper, (time_ns() - t0) / 1e9)
    end
    return eta, eta0, nact, tper
end

"""kappa = lambda_max(H_S^{-1} Hb): power iteration on L^{-1} Hb L^{-T} (L the team blocks' Cholesky factors)."""
function kappa63(ops::Vector{CertOp}, Hb; iters::Int = 60)
    N = size(Hb, 1)
    x = randn(Xoshiro(5), N); x ./= norm(x); lam = 0.0
    Linvt(y) = (z = zeros(N); for op in ops; z[op.cols] .= op.L' \ y[op.cols]; end; z)
    Linv(y) = (z = zeros(N); for op in ops; z[op.cols] .= op.L \ y[op.cols]; end; z)
    for _ in 1:iters
        y = Linv(Hb * Linvt(x))
        lam = dot(x, y); x = y / norm(y)
    end
    return lam
end

# ---------------------------------------------------------------------------
# Thm. thm:qbound at the team plan (E65): B1 (imbalance y), B2 (spread s_cb), B3 (beta d q^2 E)
# ---------------------------------------------------------------------------

"""
The offline part of Thm. thm:qbound for a team map: r (smallest eigenvalue of the R_i), alpha (Q_{i,t} >= alpha
Ct'Ct for t >= 1, the terminal Qf included), sigma (largest norm of a vehicle's input-to-position map over t = 1..H),
per team lambda_c (algebraic connectivity of the edges inside it), beta_c, the totals w_phi(i, b), their means
wbar_cb, squared coefficients of variation s2_cb, dbar_c, d, and the cross edges.
"""
function qbound_setup63(cf::CFleet, lab::Vector{Int}, q::Float64)
    n = length(lab); H = cf.spec.H; k = maximum(lab)
    mem = [findall(==(c), lab) for c in 1:k]
    w = [cf.W[e][1][1, 1] for e in eachindex(cf.edges)]
    r = minimum(eigmin(Symmetric(ag.R)) for ag in cf.agents)
    alpha = minimum(eigmin(Symmetric(ag.Q)) for ag in cf.agents)
    alpha_ok = cf.spec.terminal == :cost &&
               all(eigmin(Symmetric(ag.Qf - alpha * ag.Ct' * ag.Ct)) >= -1e-12 for ag in cf.agents)
    G = [reduce(vcat, (cf.agents[i].Ct * cf.Theta[i][t+1] for t in 1:H)) for i in 1:n]
    sigma = maximum(opnorm(g) for g in unique(G))
    lam = zeros(k)
    for c in 1:k
        length(mem[c]) < 2 && continue
        pos = Dict(v => a for (a, v) in enumerate(mem[c])); L = zeros(length(mem[c]), length(mem[c]))
        for (e, (i, j)) in enumerate(cf.edges)
            (lab[i] == c && lab[j] == c) || continue
            a, b = pos[i], pos[j]
            L[a, a] += w[e]; L[b, b] += w[e]; L[a, b] -= w[e]; L[b, a] -= w[e]
        end
        lam[c] = max(eigvals(Symmetric(L))[2], 0.0)
    end
    betac = [sigma^2 / (2 * (r + (alpha + lam[c]) * sigma^2)) for c in 1:k]
    beta = sigma^2 / (2 * (r + alpha * sigma^2))
    M = Matrix(sq_totals(n, cf.edges, w, lab))           # n x k (small: n <= 1024)
    wbar = zeros(k, k); s2 = zeros(k, k); dbar = zeros(k)
    for c in 1:k
        Mc = M[mem[c], :]
        for b in 1:k
            b == c && continue
            m = mean(Mc[:, b]); wbar[c, b] = m
            m > 0 && (s2[c, b] = mean((Mc[:, b] .- m) .^ 2) / m^2)
        end
        dbar[c] = mean(sum(Mc[a, b] for b in 1:k if b != c; init = 0.0) for a in 1:length(mem[c]))
    end
    cross = [e for (e, (i, j)) in enumerate(cf.edges) if lab[i] != lab[j]]
    # E65b, B1x: per team, F_c = (H_c + lambda_c K_c) with H_c a member's own condensed Hessian and K_c the (unit
    # weight) Gram of the intra-team edge map over the horizon; checks: members share H_c, every intra edge has the
    # same Gram at both ends (then H_S = I x H_c + L_c x K_c on the team)
    Fc = Vector{Any}(undef, k); hdev = 0.0; kdev = 0.0
    for c in 1:k
        Hc = cf.H0[mem[c][1]]
        hdev = max(hdev, maximum(opnorm(cf.H0[i] - Hc) for i in mem[c]) / opnorm(Hc))
        Kc = nothing
        for (e, (i, j)) in enumerate(cf.edges)
            (lab[i] == c && lab[j] == c) || continue
            Ke = [sum(((cf.Me[e][a] * cf.Theta[v][t+1])' * cf.W[e][t] * (cf.Me[e][a] * cf.Theta[v][t+1]) for t in 1:H)) / w[e] for (a, v) in ((1, i), (2, j))]
            kdev = max(kdev, opnorm(Ke[1] - Ke[2]) / max(opnorm(Ke[1]), 1e-300))
            Kc === nothing ? (Kc = Ke[1]) : (kdev = max(kdev, opnorm(Ke[1] - Kc) / opnorm(Kc)))
        end
        Fc[c] = cholesky(Symmetric(Kc === nothing ? Hc : Hc + lam[c] * Kc))
    end
    s2max = [maximum((s2[c, b] for b in 1:k if b != c && wbar[c, b] > 0); init = 0.0) for c in 1:k]
    m2g = maximum(betac[c] * dbar[c] * s2max[c] for c in 1:k)
    return (lab = lab, mem = mem, w = w, r = r, alpha = alpha, alpha_ok = alpha_ok, sigma = sigma, lam = lam,
            betac = betac, beta = beta, wbar = wbar, s2 = s2, dbar = dbar, d = maximum(dbar), q = q, cross = cross, G = G,
            Fc = Fc, own_dev = hdev, intra_gram_dev = kdev, m2g = m2g)
end

"""
B1, B2, B3 of Thm. thm:qbound at the team plan u of the program P, with the hypothesis checks: the spread of the
members' own gradients (coherence), of the residuals of the edges from c to b (coherence and formation), of the
members' states in deviation coordinates (formation), and sum_c sum_b |c| wbar_cb ||rho_cb||^2 / 4E.
"""
function qbound63(P::CProg, Hown, qs, u, slots; J0 = NaN)
    cf = P.cf; H = cf.spec.H; lab = qs.lab; n = length(lab)
    R = P.A * u .- P.b
    dpos(i) = size(cf.agents[i].Ct, 1)
    f = [zeros(dpos(i) * H) for i in 1:n]
    rho = Dict{Tuple{Int,Int},Vector{Float64}}(); rhodev = 0.0; rhoscale = 0.0
    E = 0.0
    for e in qs.cross
        (i, j) = cf.edges[e]; we = qs.w[e]
        Li = cf.Me[e][1] * cf.agents[i].Ct'; Lj = cf.Me[e][2] * cf.agents[j].Ct'
        re = reduce(vcat, (R[P.rowof[(e, t)]] for t in 1:H))
        E += 0.5 * we * dot(re, re)
        for t in 1:H
            rt = R[P.rowof[(e, t)]]
            f[i][((t-1)*dpos(i)+1):(t*dpos(i))] .-= we .* (Li' * rt)
            f[j][((t-1)*dpos(j)+1):(t*dpos(j))] .+= we .* (Lj' * rt)
        end
        for (key, v) in (((lab[i], lab[j]), -re), ((lab[j], lab[i]), re))
            if haskey(rho, key)
                rhodev = max(rhodev, norm(v - rho[key]))
            else
                rho[key] = v
            end
            rhoscale = max(rhoscale, norm(v))
        end
    end
    g = Hown * u .+ P.h
    B1 = 0.0; B1x = 0.0; owndev = 0.0; ownscale = 0.0; formdev = 0.0
    for (c, m) in enumerate(qs.mem)
        fbar = sum(f[i] for i in m) / length(m)
        B1 += qs.betac[c] * sum(sum(abs2, f[i] - fbar) for i in m)
        for i in m
            gi = qs.G[i]' * (f[i] - fbar)
            B1x += 0.5 * dot(gi, qs.Fc[c] \ gi)
        end
        gs = [g[ucols(cf, i)] for i in m]; gbar = sum(gs) / length(m)
        owndev = max(owndev, maximum(norm(x - gbar) for x in gs)); ownscale = max(ownscale, maximum(norm, gs))
        dev = [P.free[i][1] - cf.agents[i].Ct' * slots[i][1:dpos(i)] for i in m]; dbar_ = sum(dev) / length(m)
        formdev = max(formdev, maximum(norm(x - dbar_) for x in dev))
    end
    B2 = 0.0; S4 = 0.0
    for ((c, b), v) in rho
        nr = dot(v, v); sz = length(qs.mem[c])
        B2 += qs.betac[c] * qs.dbar[c] * qs.s2[c, b] * sz * qs.wbar[c, b] * nr
        S4 += sz * qs.wbar[c, b] * nr
    end
    B3 = qs.beta * qs.d * qs.q^2 * E
    return Dict{String,Any}("B1" => B1, "B2" => B2, "B3" => B3, "E_qb" => E,
                            "B1x" => B1x, "B2g" => 4 * qs.m2g * E, "B2gJ0" => 4 * qs.m2g * J0, "J0" => J0, "fourE_ratio" => E > 0 ? S4 / (4E) : nothing,
                            "coh_own_rel" => owndev / max(ownscale, 1e-300), "coh_rho_rel" => rhodev / max(rhoscale, 1e-300),
                            "form_dev" => formdev)
end

"""Summary of a bound over the steps: ratios B/gap where gap > 1e-9 |J*|; violations where B < gap - 1e-8 |J*|."""
function qbound_summary63(recs, key)
    rat = [r[key] / r["gap"] for r in recs if r["gap"] > 1e-9 * abs(r["Jstar"])]
    viol = count(r -> r[key] < r["gap"] - 1e-8 * abs(r["Jstar"]), recs)
    d = isempty(rat) ? Dict{String,Any}() : sumstats26_(rat)
    d["violations"] = viol; d["steps"] = length(recs)
    return d
end

"""The applied first inputs of a plan u."""
first63(cf::CFleet, u) = [u[uidx(cf, i, 0)] for i in 1:nagents(cf)]

# ---------------------------------------------------------------------------
# One seed
# ---------------------------------------------------------------------------

function run63g(n::Int, seed::Int; steps::Int = STEPS63G, choices = CHOICES63G, baselines = BASE63G, quiet::Bool = false)
    inst = sq_instance(n, seed); n = length(inst.kinds)
    fl = sq_fleet(inst, DT63G, H63G, CONE63G)
    lanes = sq_lanes(inst, seed)
    cf = cfleet63(fl, H63G)
    K = Cons63(cf, CONE63G)
    x0, dp, dv = sq_start(inst, fl, seed)
    if REG63G         # near the equilibrium, nearly at rest: the terminal equality is feasible for the cars
        x0 = [fl.agents[i].nx == 6 ? [inst.slots[i] + [0.5dp; 1.5]; [0.3dv; 0.0]] : [inst.slots[i][1:2] + 0.5dp; 0.3dv] for i in 1:n]
    end
    refsk(k) = REG63G ? refs_reg63(inst, fl, H63G) : sq_references(inst, lanes, fl, k * DT63G, DT63G, H63G)
    refs0, term0 = refsk(0)
    base = CProg(cf, CData(x0, refs0, term0))
    Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
    tf = @elapsed (Fb = cholesky(Symmetric(Hb)))
    Hown = H0blk30(cf)
    res = Dict{String,Any}("instance" => INST63G, "n_requested" => N63G, "seed" => seed, "n" => n, "edges" => length(inst.edges), "classes" => maximum(inst.class),
                           "cone" => string(CONE63G), "steps" => steps, "eps" => inst.eps, "hb_factor_seconds" => tf,
                           "choices" => Dict{String,Any}(), "baselines" => Dict{String,Any}())
    progk(x, k) = (r = refsk(k); (CProg(base, CData(x, r[1], r[2])), r[1]))
    res["regulation"] = REG63G
    # the closed loop of a planner: plan(P, k) -> (u, extra record)
    function loop(plan; lab = nothing)
        x = [copy(v) for v in x0]; cost = 0.0; recs = Dict{String,Any}[]
        for k in 0:(steps-1)
            P, refs = progk(x, k)
            u, rec = plan(P, k)
            ua = first63(cf, u)
            l, form, cross = sq_stage(fl, x, ua, refs; lab = lab)
            rec["stage"] = l; rec["form"] = form; rec["cross"] = cross; rec["step"] = k
            rec["stage_J"] = l - form                    # the program's stage-0 cost: tracking at x_k and effort (no formation at t = 0)
            rec["intra"] = form - cross
            cost += l
            push!(recs, rec)
            x = sq_plant(fl, x, ua)
        end
        _, refs = progk(x, steps)
        cost += sq_stage(fl, x, nothing, refs)[1]
        return cost, recs
    end
    # coordinated MPC
    Jc = NaN
    if "coord" in baselines
        Jc, recs = loop() do P, k
            _, hq, c = quad63(P, Hb)
            s = solve63(Hb, hq, c, K, nothing; E = P.E, e = P.e)
            (s.u, Dict{String,Any}("J" => s.J, "t" => s.seconds, "status" => s.status))
        end
        res["baselines"]["coord"] = Dict("closed_loop_cost" => Jc, "steps" => recs)
    end
    if "decentral" in baselines
        crossrows = Int[]
        for (k, (i, j)) in enumerate(cf.edges)
            inst.class[i] == inst.class[j] && continue
            for t in cf.spec.form
                t == 0 && continue
                append!(crossrows, base.rowof[(k, t)])
            end
        end
        mask = ones(size(base.A, 1)); mask[crossrows] .= 0.0
        Hd = sparse(H0blk30(cf) + base.A' * spdiagm(mask) * base.Wd * spdiagm(mask) * base.A)
        Jd, recs = loop() do P, k
            Wm = spdiagm(mask) * P.Wd * spdiagm(mask)
            hq = P.h - P.A' * (Wm * P.b)
            s = solve63(Hd, hq, 0.0, K, nothing; E = P.E, e = P.e)
            (s.u, Dict{String,Any}("t" => s.seconds, "status" => s.status))
        end
        res["baselines"]["decentral"] = Dict("closed_loop_cost" => Jd, "cost_ratio" => Jd / Jc, "steps" => recs)
    end
    if "moveblock" in baselines
        Zb = blockZ63(cf, BLOCK63G)
        Jm, recs = loop() do P, k
            _, hq, c = quad63(P, Hb)
            s = solve63(Hb, hq, c, K, Zb; E = P.E, e = P.e)
            (s.u, Dict{String,Any}("t" => s.seconds, "status" => s.status, "J" => s.J))
        end
        res["baselines"]["moveblock"] = Dict("closed_loop_cost" => Jm, "cost_ratio" => Jm / Jc, "block" => BLOCK63G, "steps" => recs)
    end
    for ch in choices
        lab, tcr = sq_teams(inst, ch, seed)
        S = srows30(base, lab)
        rest = RestOp(base, S)
        tops = @elapsed (ops = certops30(base, lab, S; restrict = REG63G))
        opsU = REG63G ? certops30(base, lab, S) : ops
        # the cross-team rows (unweighted residual maps) and their stiffness, d_max, nu
        xrows = Int[]
        for (k, (i, j)) in enumerate(cf.edges)
            lab[i] == lab[j] && continue
            for t in cf.spec.form
                t == 0 && continue
                append!(xrows, base.rowof[(k, t)])
            end
        end
        AX = base.A[xrows, :]; WX = base.Wd[xrows, xrows]
        nuX = nu63(opsU, AX)
        tot = zeros(n)
        for ((i, j), w) in zip(inst.edges, inst.w)
            lab[i] == lab[j] && continue
            tot[i] += w; tot[j] += w
        end
        dmax = maximum(mean(tot[lab .== T]) for T in unique(lab))
        Z = teamZ63(cf, lab)
        kap = CONE63G == :box || get(ENV, "E63_KAPPA_SOC", "1") == "1" ? kappa63(opsU, Hb) : NaN
        qs = sq_spread(n, inst.edges, inst.w, lab)[1]
        qb = qbound_setup63(cf, lab, qs)
        Jt, recs = loop(; lab = lab) do P, k
            _, hq, c = quad63(P, Hb)
            full = solve63(Hb, hq, c, K, nothing; E = P.E, e = P.e)
            tm = solve63(Hb, hq, c, K, Z; E = P.E, e = P.e)
            tc = @elapsed ((eta, eta0, nact, tper) = cert63(P, ops, rest, K, tm.u))
            td = @elapsed (dlo = dual63(Fb, hq, c, K, tm.zf; E = P.E, e = P.e, lam = tm.lam))
            rX = AX * tm.u - P.b[xrows]
            Eplan = 0.5 * dot(rX, WX * rX)
            gap = tm.J - full.J
            tq = @elapsed (qbr = qbound63(P, Hown, qb, tm.u, inst.slots; J0 = c))
            qbr["t_qbound"] = tq
            (tm.u, Dict{String,Any}("Jstar" => full.J, "Jteam" => tm.J, "gap" => gap, "eta" => eta, "eta_nu0" => eta0, "active" => nact,
                                    "dual_gap_bound" => tm.J - dlo, "t_team" => tm.seconds, "t_full" => full.seconds,
                                    "t_cert" => tc, "t_cert_team_max" => maximum(tper; init = 0.0), "t_dual" => td,
                                    "team_cones" => tm.cones, "full_cones" => full.cones, "status_team" => tm.status, "status_full" => full.status,
                                    "E_plan" => Eplan, qbr...))
        end
        for r in recs
            r["sigma"] = r["eta"] / r["stage"]
            r["sigma_J"] = r["eta"] / r["stage_J"]
        end
        for k in 1:(length(recs)-1)                    # the decrease W(x_{k+1}) <= W(x_k) - l_k of the theorem (nominal)
            recs[k]["W_decrease_slack"] = recs[k]["Jteam"] - recs[k]["stage_J"] - recs[k+1]["Jteam"]
        end
        rat = [r["eta"] / r["gap"] for r in recs if r["gap"] > 1e-7 * abs(r["Jstar"])]
        drat = [r["dual_gap_bound"] / r["gap"] for r in recs if r["gap"] > 1e-7 * abs(r["Jstar"])]
        res["choices"][ch] = Dict{String,Any}("teams" => maximum(lab), "q_achieved" => qs, "refine_seconds" => tcr,
            "cert_setup_seconds" => tops, "kappa" => kap, "d_max" => dmax, "nu" => nuX,
            "sigma_theory" => 2 * nuX * dmax * qs^2, "V0" => recs[1]["Jstar"], "W0" => recs[1]["Jteam"], "eta0" => recs[1]["eta"],
            "gap0" => recs[1]["gap"], "E_plan0" => recs[1]["E_plan"], "coord_closed_loop_cost" => Jc,
            "sum_stage_J" => sum(r["stage_J"] for r in recs), "closed_loop_cost" => Jt, "cost_ratio" => Jt / Jc,
            "eta_over_gap" => isempty(rat) ? Dict() : sumstats26_(rat), "dual_over_gap" => isempty(drat) ? Dict() : sumstats26_(drat),
            "gap_rel" => sumstats26_([r["gap"] / abs(r["Jstar"]) for r in recs]), "sigma" => sumstats26_([r["sigma"] for r in recs]),
            "steps" => recs,
            "qbound" => Dict{String,Any}("r" => qb.r, "alpha" => qb.alpha, "alpha_terminal_ok" => qb.alpha_ok, "sigma" => qb.sigma,
                "beta" => qb.beta, "betac_min" => minimum(qb.betac), "lambda_c_median" => median(qb.lam), "d" => qb.d, "q" => qb.q,
                "B1_over_gap" => qbound_summary63(recs, "B1"), "B2_over_gap" => qbound_summary63(recs, "B2"),
                "B3_over_gap" => qbound_summary63(recs, "B3"),
                "B1x_over_gap" => qbound_summary63(recs, "B1x"), "B2g_over_gap" => qbound_summary63(recs, "B2g"),
                "B2gJ0_over_gap" => qbound_summary63(recs, "B2gJ0"),
                "own_dev" => qb.own_dev, "intra_gram_dev" => qb.intra_gram_dev, "m2g" => qb.m2g,
                "B1x_le_B1_viol" => count(r -> r["B1x"] > r["B1"] * (1 + 1e-9) + 1e-12, recs),
                "eta_le_B1x_viol" => count(r -> r["eta"] > r["B1x"] * (1 + 1e-6) + 1e-9 * abs(r["Jstar"]), recs),
                "B2g_le_B3_viol" => count(r -> r["B2g"] > r["B3"] * (1 + 1e-9) + 1e-12, recs),
                "E_le_J0_viol" => count(r -> r["E_qb"] > r["J0"] * (1 + 1e-9), recs),
                "coh_own_rel_max" => maximum(r["coh_own_rel"] for r in recs), "coh_rho_rel_max" => maximum(r["coh_rho_rel"] for r in recs),
                "form_dev_max" => maximum(r["form_dev"] for r in recs),
                "fourE_ratio_range" => (fr = [r["fourE_ratio"] for r in recs if r["fourE_ratio"] !== nothing]; isempty(fr) ? [] : [minimum(fr), maximum(fr)]),
                "B1_le_B2_viol" => count(r -> r["B1"] > r["B2"] * (1 + 1e-9) + 1e-12, recs),
                "B2_le_B3_viol" => count(r -> r["B2"] > r["B3"] * (1 + 1e-9) + 1e-12, recs)))
        if !quiet
            qq = res["choices"][ch]["qbound"]
            @printf("  %-8s qbound-b: B1x/gap med %s min %s  B2g/gap med %s min %s  B2gJ0/gap med %s min %s  viol %d/%d/%d  own dev %.1e gram dev %.1e\n",
                    ch, fmt63(get(qq["B1x_over_gap"], "median", NaN)), fmt63(get(qq["B1x_over_gap"], "min", NaN)),
                    fmt63(get(qq["B2g_over_gap"], "median", NaN)), fmt63(get(qq["B2g_over_gap"], "min", NaN)),
                    fmt63(get(qq["B2gJ0_over_gap"], "median", NaN)), fmt63(get(qq["B2gJ0_over_gap"], "min", NaN)),
                    qq["B1x_over_gap"]["violations"], qq["B2g_over_gap"]["violations"], qq["B2gJ0_over_gap"]["violations"],
                    qq["own_dev"], qq["intra_gram_dev"])
            @printf("  %-8s qbound: B1/gap med %s min %s  B2/gap med %s min %s  B3/gap med %s min %s  viol %d/%d/%d  coh own %.1e rho %.1e form %.1e  4E %s\n",
                    ch, fmt63(get(qq["B1_over_gap"], "median", NaN)), fmt63(get(qq["B1_over_gap"], "min", NaN)),
                    fmt63(get(qq["B2_over_gap"], "median", NaN)), fmt63(get(qq["B2_over_gap"], "min", NaN)),
                    fmt63(get(qq["B3_over_gap"], "median", NaN)), fmt63(get(qq["B3_over_gap"], "min", NaN)),
                    qq["B1_over_gap"]["violations"], qq["B2_over_gap"]["violations"], qq["B3_over_gap"]["violations"],
                    qq["coh_own_rel_max"], qq["coh_rho_rel_max"], qq["form_dev_max"], string(qq["fourE_ratio_range"]))
        end
        if !quiet
            o = res["choices"][ch]
            @printf("  %-8s teams %4d q %.3f  gap/J* med %.2e  eta/gap med %s max %s  dual/gap med %s  kappa %.2f  sigma max %.3f  CL ratio %.6f  t team %.1f ms full %.1f ms cert %.1f ms\n",
                    ch, o["teams"], qs, o["gap_rel"]["median"], fmt63(get(o["eta_over_gap"], "median", NaN)), fmt63(get(o["eta_over_gap"], "max", NaN)),
                    fmt63(get(o["dual_over_gap"], "median", NaN)), kap, o["sigma"]["max"], o["cost_ratio"],
                    1e3 * median(r["t_team"] for r in recs), 1e3 * median(r["t_full"] for r in recs), 1e3 * median(r["t_cert"] for r in recs))
            flush(stdout)
        end
    end
    if !quiet
        for (k, o) in res["baselines"]
            k == "coord" && continue
            @printf("  baseline %-10s CL ratio %.6f\n", k, o["cost_ratio"])
        end
    end
    return res
end

fmt63(x) = isfinite(x) ? @sprintf("%.2f", x) : "  - "
sumstats26_(v) = Dict{String,Any}("median" => median(v), "min" => minimum(v), "max" => maximum(v), "mean" => mean(v), "n" => length(v))

function main63g()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR63G)
    get(ENV, "E63_WARMUP", "1") == "1" && run63g(32, 1; steps = 2, choices = ["qs0.25"], quiet = true)        # warm-up
    for seed in SEEDS63G
        @printf("E63-gap %s n=%d seed %d cone %s\n", INST63G, N63G, seed, CONE63G); flush(stdout)
        res = run63g(N63G, seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "eps" => SQ_EPS)
        path = joinpath(PARTDIR63G, @sprintf("e63g_%s_n%d_eps%g_%s_reg%d_seed%d.json", INST63G, N63G, SQ_EPS, CONE63G, Int(REG63G), seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main63g()
end
