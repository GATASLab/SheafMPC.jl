# E97-baselines: structure-exploiting centralized solvers on the formations of Table I (E74), on a dedicated node.
#
# The objection: the centralized baseline of Table I is Clarabel on the condensed program, a generic conic interior
# point method. Here every formation of E74 at E97_N vehicles (default 1024) replays E74's closed loop (the same
# instance, seed, references and steps 0..E97_STEPS-1, the team plan applied) and every step is solved by
#
#   centralized (the whole fleet)                          team (the quotient program of phi*, broadcast)
#   clarabel_cond   Clarabel, condensed (E74's arm)        clarabel_cond
#   clarabel_fine   Clarabel, sparse stage-wise program    clarabel_fine
#   osqp_fine       OSQP on the sparse stage-wise program, warm started (previous primal and dual shifted one
#                   instant), polished; input boxes only   osqp_fine
#   sm_fine         TeamMPC's MPCController on the sparse stage-wise program (Fine()), warm :shift
#   sm_cond         TeamMPC's MPCController on the condensed program (full_condensing(), E74's mpc arm)
#   hpipm           HPIPM through acados (env/e55_hpipm_dc.py, unchanged) on the input file written here:
#                   "stacked" (the whole fleet in every stage: the formation couples the vehicles of a stage, so
#                   HPIPM's Riccati recursion factors dense blocks of size n nx) and "team"; input boxes only
#
# Every solver at the relative and absolute tolerance 1e-6 (the paper's), Clarabel at 1e-8 (CLTOL97, see below). Cones (E97_CONES): soc (the input balls of
# Table I) and box (the box inscribed in the ball, ||u||_inf <= umax / sqrt(nu): HPIPM and OSQP take no cones).
#
# Reference optimum J_ref: the team program solved by Clarabel at tol 1e-9 and broadcast (lossless on these
# formations, E74: |J_team - J*| / |J*| <= 6e-10), evaluated on the full program. Every arm's plan is projected onto
# the input sets (clip / ball projection) and scored on the full program, J_arm; dev = |J_arm - J_ref| / |J_ref|.
# An arm is accepted when dev <= 1e-6 at every step.
#
# Timing (wall, per step): the data of the step (condensed: E74's CProg + quad63; fine: the linear cost and the
# equality right-hand side), writing it into the solver, the solve and reading the plan (team: the aggregation
# and the broadcast). The structure (matrices, symbolic analysis, OSQP's first factorization) is built once before
# the loop, as E74 builds Hb outside its timer; Clarabel has no warm start and refactors in every solve.
#
#   E97_VARIANTS=C1,E1t,W1,Ccyl E97_N=1024 E97_CONES=soc,box E97_DIR=<dir> \
#       julia --project=env scripts/resolution/experiments/e97_baselines.jl
#       -> <dir>/e97_<variant>_<cone>_N<N>_t<threads>.json and, for box, <dir>/e55_input_e97_<variant>_N<N>.json
#   E97_ARMS restricts the arms (comma list of names above, with suffix _full / _team), E97_THREADS sets the BLAS and
#   KKT threads (julia -t to match). The HPIPM arm runs from the input files (see the job scripts), the merge is
#   e97_merge.py.

ENV["E74_MODE"] = "none"
include(joinpath(@__DIR__, "e74_mission.jl"))
import OSQP
using Printf, Statistics, LinearAlgebra, SparseArrays, JSON

const VARIANTS97 = split(get(ENV, "E97_VARIANTS", "C1,E1t,W1,Ccyl"), ",")
const N97 = parse(Int, get(ENV, "E97_N", "1024"))
const STEPS97 = parse(Int, get(ENV, "E97_STEPS", "3"))
const CONES97 = Symbol.(split(get(ENV, "E97_CONES", "soc,box"), ","))
const DIR97 = get(ENV, "E97_DIR", joinpath(ROOT27, "bench", "irregular", "results", "parts97"))
const THREADS97 = parse(Int, get(ENV, "E97_THREADS", "1"))
const TOL97 = 1e-6
# Clarabel at 1e-6 stops strictly inside the input sets with objective errors up to 1e-3 relative on the stage-wise
# form (canary), so its arms run at 1e-8 (E30's Clarabel tolerance) to reach the optimum to 1e-6
const CLTOL97 = parse(Float64, get(ENV, "E97_CLTOL", "1e-8"))
const CAP97 = parse(Float64, get(ENV, "E97_CAP", "900"))       # an arm whose step takes longer is not run again
const ALLARMS97 = ["clarabel_cond", "clarabel_fine", "osqp_fine", "sm_fine", "sm_cond"]
const ARMS97 = let s = get(ENV, "E97_ARMS", "")
    isempty(s) ? vcat([a * "_full" for a in ALLARMS97], [a * "_team" for a in ALLARMS97]) : String.(split(s, ","))
end

# ---------------------------------------------------------------------------
# The sparse stage-wise program of a condensed fleet
# ---------------------------------------------------------------------------
# Variables, vehicle-major: z_i = (u_{i,0}, x_{i,1}, u_{i,1}, x_{i,2}, ..., u_{i,H-1}, x_{i,H}).
# Cost 1/2 z'Pz + q'z (+ a constant): the tracking 1/2||Ct x_t - r_t||_Q^2 at t = 1..H-1 (t = 0 a constant, as
# cfleet63's spec), the terminal 1/2||x_H - rf||_Qf^2, the effort 1/2 u'Ru, the formation
# 1/2 (Mj x_j,t - Mi x_i,t - o_k,t)' W_k,t (...) at t = 1..H. Equalities: x_{i,1} - B u_{i,0} = A x_{i,0} + g and
# x_{i,t+1} - A x_{i,t} - B u_{i,t} = g.

struct Fine97
    cf::CFleet
    off::Vector{Int}           # vehicle i's block starts after off[i]
    nz::Int
    P::SparseMatrixCSC{Float64,Int}
    qform::Vector{Float64}     # the constant (formation target) part of q
    Aeq::SparseMatrixCSC{Float64,Int}
    eoff::Vector{Int}          # vehicle i's equality rows start after eoff[i]
    neq::Int
    ucol::Vector{Int}          # z index of every condensed input coordinate (u = z[ucol])
end

fu97(F::Fine97, i, t) = (ag = F.cf.agents[i]; nu = size(ag.B, 2); nx = size(ag.A, 1); F.off[i] + t * (nu + nx) .+ (1:nu))
fx97(F::Fine97, i, t) = (ag = F.cf.agents[i]; nu = size(ag.B, 2); nx = size(ag.A, 1); F.off[i] + (t - 1) * (nu + nx) + nu .+ (1:nx))

function Fine97(cf::CFleet)
    H = cf.spec.H; n = nagents(cf)
    cf.spec.track == collect(0:(H-1)) && cf.spec.form == collect(1:H) && cf.spec.terminal == :cost ||
        error("Fine97 assumes cfleet63's cost layout")
    d = [size(ag.B, 2) + size(ag.A, 1) for ag in cf.agents]
    off = [0; cumsum(d .* H)[1:end-1]]; nz = sum(d .* H)
    nxs = [size(ag.A, 1) for ag in cf.agents]
    eoff = [0; cumsum(nxs .* H)[1:end-1]]; neq = sum(nxs .* H)
    F0 = Fine97(cf, off, nz, spzeros(0, 0), Float64[], spzeros(0, 0), eoff, neq, Int[])
    PI = Int[]; PJ = Int[]; PV = Float64[]
    addblk!(r, c, M) = for b in axes(M, 2), a in axes(M, 1)
        M[a, b] != 0 && (push!(PI, r[a]); push!(PJ, c[b]); push!(PV, M[a, b]))
    end
    for (i, ag) in enumerate(cf.agents), t in 0:(H-1)
        addblk!(fu97(F0, i, t), fu97(F0, i, t), ag.R)
        t >= 1 && addblk!(fx97(F0, i, t), fx97(F0, i, t), ag.Ct' * ag.Q * ag.Ct)
    end
    for (i, ag) in enumerate(cf.agents)
        addblk!(fx97(F0, i, H), fx97(F0, i, H), ag.Qf)
    end
    qf = zeros(nz)
    for (k, (i, j)) in enumerate(cf.edges), (l, t) in enumerate(cf.spec.form)
        Mi, Mj = cf.Me[k]; W = cf.W[k][l]; o = cf.o[k][l]
        xi = fx97(F0, i, t); xj = fx97(F0, j, t)
        addblk!(xi, xi, Mi' * W * Mi); addblk!(xj, xj, Mj' * W * Mj)
        addblk!(xi, xj, -Mi' * W * Mj); addblk!(xj, xi, -Mj' * W * Mi)
        qf[xi] .+= Mi' * (W * o); qf[xj] .-= Mj' * (W * o)
    end
    P = sparse(PI, PJ, PV, nz, nz)
    AI = Int[]; AJ = Int[]; AV = Float64[]
    adda!(r, c, M) = for b in axes(M, 2), a in axes(M, 1)
        M[a, b] != 0 && (push!(AI, r[a]); push!(AJ, c[b]); push!(AV, M[a, b]))
    end
    for (i, ag) in enumerate(cf.agents), t in 0:(H-1)
        nx = size(ag.A, 1); rows = eoff[i] + t * nx .+ (1:nx)
        adda!(rows, fx97(F0, i, t + 1), Matrix(1.0I, nx, nx))
        adda!(rows, fu97(F0, i, t), -ag.B)
        t >= 1 && adda!(rows, fx97(F0, i, t), -ag.A)
    end
    Aeq = sparse(AI, AJ, AV, neq, nz)
    ucol = zeros(Int, ncols30(cf))
    for i in 1:n, t in 0:(H-1)
        ucol[uidx(cf, i, t)] .= fu97(F0, i, t)
    end
    return Fine97(cf, off, nz, P, qf, Aeq, eoff, neq, ucol)
end

"""The data of a step: the linear cost q and the equality right-hand side beq."""
function fdata97(F::Fine97, d::CData)
    cf = F.cf; H = cf.spec.H
    q = copy(F.qform); beq = zeros(F.neq)
    @inbounds for (i, ag) in enumerate(cf.agents)
        for t in 1:(H-1)
            q[fx97(F, i, t)] .-= ag.Ct' * (ag.Q * d.refs[i][:, t+1])
        end
        q[fx97(F, i, H)] .-= ag.Qf * d.rf[i]
        nx = size(ag.A, 1)
        beq[F.eoff[i] .+ (1:nx)] .= ag.A * d.x0[i] .+ ag.g
        for t in 1:(H-1)
            beq[F.eoff[i] + t * nx .+ (1:nx)] .= ag.g
        end
    end
    return q, beq
end

"""The trajectory z of inputs u (condensed layout) from x0."""
function rollout97(F::Fine97, d::CData, u)
    cf = F.cf; H = cf.spec.H; z = zeros(F.nz)
    for (i, ag) in enumerate(cf.agents)
        x = d.x0[i]
        for t in 0:(H-1)
            ut = u[uidx(cf, i, t)]; z[fu97(F, i, t)] .= ut
            x = ag.A * x + ag.B * ut + ag.g; z[fx97(F, i, t + 1)] .= x
        end
    end
    return z
end

"""Check the fine cost against the condensed one (same quadratic and linear part: J63 - Jfine constant in u)."""
function check97(F::Fine97, d::CData, Hb, hq, c)
    q, _ = fdata97(F, d)
    Jf(z) = 0.5 * dot(z, F.P * z) + dot(q, z)
    rng = Xoshiro(97); diffs = Float64[]; scale = 0.0
    for _ in 1:3
        u = 0.3 * randn(rng, ncols30(F.cf)); z = rollout97(F, d, u)
        Jc = J63(Hb, hq, c, u); push!(diffs, Jc - Jf(z)); scale = max(scale, abs(Jc))
    end
    err = (maximum(diffs) - minimum(diffs)) / scale
    err < 1e-9 || error("the stage-wise cost disagrees with the condensed one ($err)")
    return err
end

"""Project a plan onto the input sets (balls or boxes)."""
function project97(cf::CFleet, cone::Symbol, u)
    v = copy(u)
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        ix = uidx(cf, i, t); um = cf.agents[i].umax
        if cone == :soc
            nr = norm(v[ix]); nr > um && (v[ix] .*= um / nr)
        else
            v[ix] .= clamp.(v[ix], -um, um)
        end
    end
    return v
end

viol97(cf::CFleet, cone::Symbol, u) = maximum(begin
        ix = uidx(cf, i, t); um = cf.agents[i].umax
        cone == :soc ? norm(u[ix]) - um : maximum(abs.(u[ix])) - um
    end for i in 1:nagents(cf), t in 0:(cf.spec.H-1))

# ---------------------------------------------------------------------------
# Solvers on the stage-wise program
# ---------------------------------------------------------------------------

clset97() = Clarabel.Settings(verbose = false, tol_gap_abs = CLTOL97, tol_gap_rel = CLTOL97, tol_feas = CLTOL97, max_iter = 400)

"""Clarabel on the stage-wise program: [Aeq; input rows] z + s = b, s in {0} x cones. Structure built once."""
mutable struct ClFine97
    F::Fine97
    cone::Symbol
    A::SparseMatrixCSC{Float64,Int}
    bin::Vector{Float64}
    cones::Vector{Clarabel.SupportedCone}
    S::Any
    updates::Bool
end

function ClFine97(F::Fine97, cone::Symbol)
    cf = F.cf; I_ = Int[]; J_ = Int[]; V_ = Float64[]; b = Float64[]; r = 0
    cones = Clarabel.SupportedCone[Clarabel.ZeroConeT(F.neq)]
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        cols = fu97(F, i, t); um = cf.agents[i].umax; nu = length(cols)
        if cone == :soc
            push!(b, um); append!(b, zeros(nu))
            for a in 1:nu
                push!(I_, r + 1 + a); push!(J_, cols[a]); push!(V_, -1.0)
            end
            r += 1 + nu; push!(cones, Clarabel.SecondOrderConeT(1 + nu))
        else
            for a in 1:nu
                push!(I_, r + a); push!(J_, cols[a]); push!(V_, 1.0)
                push!(I_, r + nu + a); push!(J_, cols[a]); push!(V_, -1.0)
            end
            append!(b, fill(um, 2nu)); r += 2nu; push!(cones, Clarabel.NonnegativeConeT(2nu))
        end
    end
    A = [F.Aeq; sparse(I_, J_, V_, r, F.nz)]
    return ClFine97(F, cone, A, b, cones, nothing, true)
end

function solve97!(C::ClFine97, q, beq)
    b = [beq; C.bin]
    if C.S === nothing || !C.updates
        C.S = Clarabel.Solver()
        Clarabel.setup!(C.S, sparse(triu(C.F.P)), q, C.A, b, C.cones, clset97())
    else
        try
            Clarabel.update_q!(C.S, q); Clarabel.update_b!(C.S, b)
        catch err
            @warn "Clarabel data update failed, setting up every step" err
            C.updates = false
            C.S = Clarabel.Solver()
            Clarabel.setup!(C.S, sparse(triu(C.F.P)), q, C.A, b, C.cones, clset97())
        end
    end
    sol = Clarabel.solve!(C.S)
    return sol.x[C.F.ucol], string(sol.status), sol.iterations
end

"""OSQP on the stage-wise program with input boxes; warm start from the previous solution shifted one instant."""
mutable struct OsqpFine97
    F::Fine97
    m::Any
    lbox::Vector{Float64}
    shz::Vector{Int}           # z[k] <- zprev[shz[k]] (the shift of every vehicle's block by one instant)
    shy::Vector{Int}
    t_setup::Float64
    prev::Any
end

function shiftperm97(blocks)       # blocks: (start offset, per-instant length, H) per vehicle
    p = Int[]
    for (o, d, H) in blocks, t in 0:(H-1)
        s = min(t + 1, H - 1)
        append!(p, o + s * d .+ (1:d))
    end
    return p
end

function OsqpFine97(F::Fine97)
    cf = F.cf; H = cf.spec.H
    nuz = Int[]; lo = Float64[]
    for i in 1:nagents(cf), t in 0:(H-1)
        cols = fu97(F, i, t); append!(nuz, cols); append!(lo, fill(-cf.agents[i].umax, length(cols)))
    end
    Ab = sparse(1:length(nuz), nuz, ones(length(nuz)), length(nuz), F.nz)
    A = [F.Aeq; Ab]
    blocksz = [(F.off[i], size(ag.B, 2) + size(ag.A, 1), H) for (i, ag) in enumerate(cf.agents)]
    # the box rows are ordered vehicle, instant, coordinate: blocks of nu per instant
    nbx = 0; blocksb = Tuple{Int,Int,Int}[]
    for ag in cf.agents
        nu = size(ag.B, 2); push!(blocksb, (F.neq + nbx, nu, H)); nbx += nu * H
    end
    blockse = [(F.eoff[i], size(ag.A, 1), H) for (i, ag) in enumerate(cf.agents)]
    shz = shiftperm97(blocksz); shy = [shiftperm97(blockse); shiftperm97(blocksb)]
    m = OSQP.Model()
    q0 = zeros(F.nz); l0 = [zeros(F.neq); lo]; u0 = [zeros(F.neq); -lo]
    t = @elapsed OSQP.setup!(m; P = sparse(triu(F.P)), q = q0, A = A, l = l0, u = u0, eps_abs = TOL97, eps_rel = TOL97,
                             polish = true, warm_start = true, verbose = false, max_iter = 200000, check_termination = 25)
    return OsqpFine97(F, m, lo, shz, shy, t, nothing)
end

function solve97!(O::OsqpFine97, q, beq)
    OSQP.update!(O.m; q = q, l = [beq; O.lbox], u = [beq; -O.lbox])
    if O.prev === nothing
        OSQP.warm_start!(O.m; x = zeros(O.F.nz), y = zeros(length(O.shy)))
    else
        zp, yp = O.prev
        OSQP.warm_start!(O.m; x = zp[O.shz], y = yp[O.shy])
    end
    r = OSQP.solve!(O.m)
    st = string(r.info.status)
    O.prev = st == "Solved" ? (copy(r.x), copy(r.y)) : nothing
    return r.x[O.F.ucol], st, r.info.iter
end

# ---------------------------------------------------------------------------
# One formation, one cone
# ---------------------------------------------------------------------------

rows97(M::AbstractMatrix) = [collect(M[i, :]) for i in 1:size(M, 1)]

"""The input file of env/e55_hpipm_dc.py (its format: one entry per vehicle data, the fleet, the teams,
every step's states and references, two check plans)."""
function export97(inst, fl, cf, lab, Q, steps, checks, path)
    types = Dict{String,Any}(); vtype = String[]
    for (i, ag) in enumerate(fl.agents)
        U = ag.input; U isa SM.BoxSet || error("export needs input boxes")
        dd = Dict{String,Any}("nx" => ag.nx, "nu" => ag.nu, "A" => rows97(ag.A[1]), "B" => rows97(ag.B[1]), "g" => ag.g[1],
                              "C" => rows97(ag.C), "Cr" => rows97(ag.Cr), "Q" => rows97(ag.Q), "R" => rows97(ag.R),
                              "Cf" => rows97(ag.Cf), "Qf" => rows97(ag.Qf), "lo" => U.lo, "hi" => U.hi)
        key = "$(ag.kind)_$(inst.variant[i])_$(hash(dd))"
        haskey(types, key) || (types[key] = dd)
        push!(vtype, key)
    end
    size(fl.targets, 1) == 3 || error("targets must be 3-vectors")
    for (k, (i, j)) in enumerate(fl.edges)
        Mi, Mj = SM.edge_maps(fl, k)
        Mi ≈ fl.select[k] * fl.agents[i].C && Mj ≈ fl.select[k] * fl.agents[j].C || error("edge maps are not S C")
    end
    all(fl.targets[:, :, t] == fl.targets[:, :, 1] && fl.weights[:, t] == fl.weights[:, 1] for t in axes(fl.weights, 2)) ||
        error("targets or weights change over the horizon")
    d = Dict{String,Any}("n" => length(fl.agents), "side" => 0, "H" => fl.H, "h" => DT63G, "seed" => SEED74, "cone" => "box",
                         "types" => types, "vtype" => vtype, "slots" => inst.slots, "Delta" => Q.Delta, "team" => lab,
                         "edges" => [[i, j] for (i, j) in fl.edges], "select" => [rows97(S) for S in fl.select],
                         "targets" => [fl.targets[:, k, 1] for k in eachindex(fl.edges)],
                         "weights" => [fl.weights[k, 1] for k in eachindex(fl.edges)], "steps" => steps, "checks" => checks)
    open(io -> JSON.print(io, d), path, "w")
end

function plan_matrix97(cf, u, i)
    nu = cf.nus[i]
    return [collect(u[uidx(cf, i, t)]) for t in 0:(cf.spec.H-1)]       # H rows of nu
end

function smplan97(C, cf)
    X, U = SM.trajectories(C.fp, SM.plan(C))
    u = zeros(ncols30(cf))
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        u[uidx(cf, i, t)] .= U[i][:, t+1]
    end
    return u
end

function run97(v, N, cone; steps = STEPS97, quiet = false, export_path = nothing, arms = ARMS97)
    inst = mission74(v, N); n = length(inst.kinds)
    lab = SM.canonical_partition(SM.colour_refinement(n, inst.edges, inst.w, inst.class; within = false))
    fl = sq_fleet(inst, DT63G, H63G, cone)
    lanes = lanes74(inst, SEED74)
    cf = cfleet63(fl, H63G); K = Cons63(cf, cone)
    x0, _, _ = sq_start(inst, fl, SEED74)
    refsk(k) = sq_references(inst, lanes, fl, k * DT63G, DT63G, H63G)
    r0 = refsk(0)
    res = Dict{String,Any}("variant" => v, "N" => N, "n" => n, "teams" => maximum(lab), "cone" => string(cone), "H" => H63G,
                           "tol" => TOL97, "clarabel_tol" => CLTOL97, "threads" => THREADS97, "arms" => Dict{String,Any}())
    build = Dict{String,Float64}()
    build["cond_full"] = @elapsed begin
        base = CProg(cf, CData(x0, r0[1], r0[2]))
        Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
    end
    build["cond_team"] = @elapsed begin
        Q = quot74(fl, inst, lab)
        cfq = cfleet63(Q.fleet, H63G); Kq = Cons63(cfq, cone)
        xq0, rq0, tq0 = teamdata74(Q, fl, x0, r0[1], r0[2])
        baseq = CProg(cfq, CData(xq0, rq0, tq0))
        Hbq = sparse(H0blk30(cfq) + baseq.A' * baseq.Wd * baseq.A)
    end
    has(a) = a in arms
    anyfine = any(has, ("clarabel_fine_full", "osqp_fine_full")); anyfineq = any(has, ("clarabel_fine_team", "osqp_fine_team"))
    Ff = Fq = nothing
    anyfine && (build["fine_full"] = @elapsed (Ff = Fine97(cf)))
    anyfineq && (build["fine_team"] = @elapsed (Fq = Fine97(cfq)))
    if anyfine
        _, hq0, c0 = quad63(base, Hb); res["fine_check_full"] = check97(Ff, CData(x0, r0[1], r0[2]), Hb, hq0, c0)
    end
    if anyfineq
        _, hq0, c0 = quad63(baseq, Hbq); res["fine_check_team"] = check97(Fq, CData(xq0, rq0, tq0), Hbq, hq0, c0)
    end
    res["vars"] = Dict("cond_full" => ncols30(cf), "cond_team" => ncols30(cfq),
                       "fine_full" => Ff === nothing ? 0 : Ff.nz, "fine_team" => Fq === nothing ? 0 : Fq.nz)
    S = Dict{String,Any}()
    has("clarabel_fine_full") && (build["clarabel_fine_full"] = @elapsed (S["clarabel_fine_full"] = ClFine97(Ff, cone)))
    has("clarabel_fine_team") && (build["clarabel_fine_team"] = @elapsed (S["clarabel_fine_team"] = ClFine97(Fq, cone)))
    if cone == :box
        has("osqp_fine_full") && (build["osqp_fine_full"] = @elapsed (S["osqp_fine_full"] = OsqpFine97(Ff)))
        has("osqp_fine_team") && (build["osqp_fine_team"] = @elapsed (S["osqp_fine_team"] = OsqpFine97(Fq)))
    end
    st = SM.Settings(eps_abs = TOL97, eps_rel = TOL97, kkt_threads = THREADS97)
    has("sm_fine_full") && (build["sm_fine_full"] = @elapsed (S["sm_fine_full"] = SM.MPCController(fl; certify = false, settings = st)))
    has("sm_fine_team") && (build["sm_fine_team"] = @elapsed (S["sm_fine_team"] = SM.MPCController(Q.fleet; certify = false, settings = st)))
    has("sm_cond_full") && (build["sm_cond_full"] = @elapsed (S["sm_cond_full"] = SM.MPCController(fl, SM.full_condensing(); certify = false, settings = st)))
    has("sm_cond_team") && (build["sm_cond_team"] = @elapsed (S["sm_cond_team"] = SM.MPCController(Q.fleet, SM.full_condensing(); certify = false, settings = st)))
    res["build_s"] = build
    recs = Dict{String,Vector{Any}}(a => Any[] for a in arms)
    skipped = Set{String}()
    x = [copy(z) for z in x0]
    exsteps = Any[]; checks = Any[]; refrecs = Any[]
    for k in 0:(steps-1)
        refs, term = refsk(k)
        d = CData(x, refs, term)
        P = CProg(base, d); _, hq, c = quad63(P, Hb)
        # the reference: the team program at tol 1e-9, broadcast (untimed)
        xq, rq, tq = teamdata74(Q, fl, x, refs, term)
        dq = CData(xq, rq, tq)
        Pq = CProg(baseq, dq); _, hqq, cq = quad63(Pq, Hbq)
        tm = solve63(Hbq, hqq, cq, Kq, nothing; tol = 1e-9)
        uref = broadcast74(cf, cfq, lab, tm.u); Jref = J63(Hb, hq, c, uref)
        push!(refrecs, Dict("step" => k, "J_ref" => Jref, "status" => tm.status, "iters" => tm.iters,
                            "viol" => viol97(cf, cone, uref)))
        if export_path !== nothing
            push!(exsteps, Dict{String,Any}("x" => x, "refs" => [rows97(R) for R in refs], "term" => term, "J_ref" => Jref))
            if k < 2
                ucl = project97(cf, :box, uref)
                push!(checks, Dict{String,Any}("step" => k, "U" => [plan_matrix97(cf, uref, i) for i in 1:n],
                                              "J_clip" => J63(Hb, hq, c, ucl), "J_roll" => Jref))
            end
        end
        for a in arms
            (a in skipped || !(haskey(S, a) || startswith(a, "clarabel_cond"))) && continue
            team = endswith(a, "_team")
            GC.gc()
            local u, status, iters; tparts = Dict{String,Any}()
            t = @elapsed begin
                if a == "clarabel_cond_full"
                    P1 = CProg(base, d); _, h1, c1 = quad63(P1, Hb)
                    s = solve63(Hb, h1, c1, K, nothing; tol = CLTOL97); u = s.u; status = s.status; iters = s.iters
                elseif a == "clarabel_cond_team"
                    xq1, rq1, tq1 = teamdata74(Q, fl, x, refs, term)
                    P1 = CProg(baseq, CData(xq1, rq1, tq1)); _, h1, c1 = quad63(P1, Hbq)
                    s = solve63(Hbq, h1, c1, Kq, nothing; tol = CLTOL97)
                    u = broadcast74(cf, cfq, lab, s.u); status = s.status; iters = s.iters
                elseif startswith(a, "clarabel_fine") || startswith(a, "osqp_fine")
                    if team
                        xq1, rq1, tq1 = teamdata74(Q, fl, x, refs, term)
                        q1, b1 = fdata97(Fq, CData(xq1, rq1, tq1))
                        v1, status, iters = solve97!(S[a], q1, b1)
                        u = broadcast74(cf, cfq, lab, v1)
                    else
                        q1, b1 = fdata97(Ff, d)
                        u, status, iters = solve97!(S[a], q1, b1)
                    end
                else                                   # TeamMPC controllers
                    C = S[a]
                    if team
                        xq1, rq1, tq1 = teamdata74(Q, fl, x, refs, term)
                        info = SM.step!(C, xq1, rq1; terminal = tq1)
                        u = broadcast74(cf, cfq, lab, smplan97(C, cfq))
                    else
                        info = SM.step!(C, x, refs; terminal = term)
                        u = smplan97(C, cf)
                    end
                    status = string(info.status); iters = info.iter
                    tparts = Dict{String,Any}(string(f) => getfield(info, f) for f in (:t_construct, :t_setup, :t_solve, :t_lift) if hasfield(typeof(info), f))
                end
            end
            up = project97(cf, cone, u); J = J63(Hb, hq, c, up)
            rec = Dict{String,Any}("step" => k, "t" => t, "status" => status, "iters" => iters, "J" => J, "t_parts" => tparts,
                                   "dev" => abs(J - Jref) / abs(Jref), "viol" => viol97(cf, cone, u),
                                   "du_ref" => maximum(abs.(up - uref)))
            push!(recs[a], rec)
            quiet || @printf("  %-5s %-4s step %d %-20s %10.2f ms  it %4s  dev %.1e  viol %.1e  %s\n", v, cone, k, a, 1e3 * t,
                             string(iters), rec["dev"], rec["viol"], status)
            flush(stdout)
            t > CAP97 && push!(skipped, a)
        end
        x = sq_plant(fl, x, first63(cf, uref))
    end
    for a in arms
        isempty(recs[a]) && continue
        ts = [r["t"] for r in recs[a]]
        res["arms"][a] = Dict{String,Any}("steps" => recs[a], "ms_med" => 1e3 * median(ts), "ms_max" => 1e3 * maximum(ts),
                                          "dev_max" => maximum(r["dev"] for r in recs[a]),
                                          "accepted" => all(r["dev"] <= TOL97 for r in recs[a]),
                                          "nsteps" => length(ts), "capped" => a in skipped)
    end
    res["ref"] = refrecs
    haskey(S, "osqp_fine_full") && (res["osqp_setup_full_s"] = S["osqp_fine_full"].t_setup)
    haskey(S, "osqp_fine_team") && (res["osqp_setup_team_s"] = S["osqp_fine_team"].t_setup)
    export_path === nothing || export97(inst, fl, cf, lab, Q, exsteps, checks, export_path)
    return res
end

function main97()
    BLAS.set_num_threads(THREADS97)
    mkpath(DIR97)
    for cone in CONES97                                # warm-up (compilation), every arm and path
        run97(VARIANTS97[1], 64, cone; steps = 2, quiet = true)
    end
    for v in VARIANTS97, cone in CONES97
        @printf("E97 %s N %d cone %s threads %d\n", v, N97, cone, THREADS97); flush(stdout)
        ex = cone == :box && THREADS97 == 1 ? joinpath(DIR97, "e55_input_e97_$(v)_N$(N97).json") : nothing
        r = run97(v, N97, cone; export_path = ex)
        r["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                         "cpu" => Sys.cpu_info()[1].model, "nodes_cpus" => Sys.CPU_THREADS, "julia_threads" => Threads.nthreads(),
                         "blas_threads" => BLAS.get_num_threads(), "load" => read("/proc/loadavg", String))
        open(io -> JSON.print(io, r, 1), joinpath(DIR97, "e97_$(v)_$(cone)_N$(N97)_t$(THREADS97).json"), "w")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main97()
end
