# Provenance: e30_bounds.jl blob 369046a (main@4ed57a7), the version in every November HPG tree (per-agent input sizes). Unchanged except this header and its include of e27_pareto_dc.jl.
# The October versions under the plain names are the ones the E26-E42 ZOH campaign ran with.
# E30-bounds: an upper bound on the gap of a team structure computed from the
# team solve alone, and the closed loop of team MPC with incoherent teams.
#
# Notation (condensed: the decision is u, every agent's inputs over the
# horizon, the measured state is data). S are the soft formation edges a team
# structure merges, r_S(u) = A_S u - b_S their residuals, W = blkdiag(W_e) their
# stiffness, J = J_rest(u) + (1/2)||r_S(u)||^2_W, U the input balls (and, for
# Part B, the terminal equality). P is the full program, P[S] the team program
# (min J_rest s.t. A_S u = b_S, u in U), gamma = J*(P[S]) - J*(P).
#
# Part A, the bound. With H0 = blkdiag over agents of the agent's own condensed
# Hessian (tracking, effort, terminal; formation terms dropped, they are PSD) and
# z the lifted team plan, for every g in grad J_rest(z) + N_U(z),
#
#     gamma <= Gamma(g) = (1/2) g' H^{-1} g,     H = H0 + A_S' W A_S
#
# (strong convexity of J_rest with modulus H0 and A_S z = b_S; no multiplier of
# the merged edges and no constraint qualification). H is block diagonal over
# the teams. The certificate `Gamma` is the minimum over the normal cone of the
# active input balls (one nonnegative least-squares problem per team in the
# H^{-1} metric, Clarabel; section "The certificate in its multiplier-free
# form"). It needs the team plan only, no duals. Also recorded:
#   Gamma_solver  Gamma(g) at the team solve's own cone duals (TeamMPC's reduced
#                 solve, a merged dual split evenly; or Clarabel's);
#   Gamma_mu      the multiplier form (1/2) mu'(W + Khat^{-1})^{-1} mu, Khat =
#                 A_S H0^{-1} A_S' (equal to Gamma(g) at g = -A_S'mu by Woodbury;
#                 with cycles inside a team computed on range(A_S) through the
#                 eigendecomposition of Khat, eigenvalues below 1e-10 of the
#                 largest dropped), with mu from Clarabel's hardened program P[S]
#                 (condensed, tolerance 1e-8, the package's solve tolerance),
#                 recovered from the team solve by stationarity on the full space
#                 (per team least squares A_T'mu = -(grad J_rest(z) + nu)_T, nu the
#                 reduced solve's cone duals), from the package's Certifier, and
#                 the tightest mu form over the team solve's multipliers
#                 (Gamma_mu_tight). When members saturate together their cone
#                 duals are not unique and the solver's choice can give
#                 Gamma_solver, Gamma_mu > 0 at gamma = 0; the minimum over the
#                 cone removes this.
# And the lower bound of Thm. thm:price (1/2)||s_S||^2_W at the full optimum,
# the old multiplier bound (1/2) mu' W^{-1} mu (least W^{-1}-norm mu; the
# package's gap_bounds `upper`), and, on small random instances, Gamma with H0
# replaced by the exact Hessian of J_rest (equal to gamma when no inequality is
# active: the sanity check of the formula).
#
# Part B, the closed loop of incoherent teams (BENCH_MODE=closedloop): see
# closed-loop section below.
#
#   julia --project=env scripts/resolution/experiments/e30_bounds.jl
#     BENCH_MODE=random      random small fleets (exact gaps, active inputs)          -> <partdir>/e30_random.json
#     BENCH_MODE=fleet       E27's fleet at step 0 and along the rows' closed loop
#                            (BENCH_SIDE, BENCH_SIGMAS, BENCH_SEEDS, BENCH_TEAMS=rows|blocks2, BENCH_CL_STEPS,
#                            BENCH_CLARABEL=1 for the Clarabel duals)             -> <partdir>/e30_fleet_<tag>.json
#     BENCH_MODE=closedloop  Part B (BENCH_SIDE, BENCH_SEEDS)                      -> <partdir>/e30_cl_n<n>_seed<s>.json
#     BENCH_MODE=merge       parts -> results/e30_bounds.json, results/e30_closed_loop.json
#
# The environment is env's (TeamMPC.jl as a sibling checkout,
# Clarabel 0.11.1, JSON). E27's fleet, programs and chains are included from
# e27_pareto.jl (its main is not run).

include(joinpath(@__DIR__, "e27_pareto_dc.jl"))
import Clarabel

const MODE30 = get(ENV, "BENCH_MODE", "fleet")
const PARTDIR30 = get(ENV, "BENCH_PARTDIR", joinpath(ROOT27, "bench", "bounds", "results", "parts"))
const TOL30 = 1e-8                                    # Clarabel tolerances = TeamMPC's solve() defaults
const EIGTOL30 = 1e-10                                # relative eigenvalue cut of Khat (its null space)
const ACTIVE_TOL30 = 1e-6                             # an input ball is active when ||u|| >= (1 - tol) r

# ---------------------------------------------------------------------------
# The condensed fleet
# ---------------------------------------------------------------------------

struct CAgent
    A::Matrix{Float64}
    B::Matrix{Float64}
    g::Vector{Float64}
    C::Matrix{Float64}          # formation output
    Ct::Matrix{Float64}         # tracked output
    Q::Matrix{Float64}
    R::Matrix{Float64}
    Qf::Matrix{Float64}         # terminal weight on the full state (terminal = :cost)
    umax::Float64
end

"""
The cost layout. `track`: instants with the tracking cost 1/2||Ct x_t - r_t||^2_Q
(t = 0 enters as a constant); `form`: instants with formation edges (t = 0 a
constant); `terminal`: `:cost` (1/2||x_H - rf||^2_Qf) or `:equality` (x_H = rf).
E27 (the package's programs): track 1:H-1 plus the constant at 0, form 1:H, cost.
"""
struct CSpec
    H::Int
    track::Vector{Int}
    form::Vector{Int}
    terminal::Symbol
end

struct CFleet
    agents::Vector{CAgent}
    spec::CSpec
    edges::Vector{Tuple{Int,Int}}
    W::Vector{Vector{Matrix{Float64}}}      # W[k][l]: stiffness of edge k at instant spec.form[l]
    o::Vector{Vector{Vector{Float64}}}      # o[k][l]: its target
    Theta::Vector{Vector{Matrix{Float64}}}  # Theta[i][t+1]: x_t = Theta u_i + free_t, t = 0..H
    H0::Vector{Matrix{Float64}}             # the agent's own condensed Hessian
    nu::Int                                 # the largest input dimension
    p::Int                                  # the largest edge dimension
    nus::Vector{Int}                        # every agent's input dimension
    uoff::Vector{Int}                       # the offset of agent i's inputs in u
    Me::Vector{Tuple{Matrix{Float64},Matrix{Float64}}}   # edge k's maps on the states of its ends
    pk::Vector{Int}                         # edge k's dimension
end

nagents(cf::CFleet) = length(cf.agents)
ncols30(cf::CFleet) = cf.uoff[end] + cf.nus[end] * cf.spec.H
ucols(cf::CFleet, i::Int) = (cf.uoff[i]+1):(cf.uoff[i]+cf.nus[i]*cf.spec.H)
uidx(cf::CFleet, i::Int, t::Int) = cf.uoff[i] + t*cf.nus[i] .+ (1:cf.nus[i])           # u_{i,t}, t = 0..H-1

function thetas30(ag::CAgent, H::Int)
    nx, nu = size(ag.B)
    Th = [zeros(nx, nu * H) for _ in 0:H]
    for t in 0:(H-1)
        Th[t+2] .= ag.A * Th[t+1]
        Th[t+2][:, (t*nu+1):((t+1)*nu)] .+= ag.B
    end
    return Th
end

function own_hessian30(ag::CAgent, Th, spec::CSpec)
    H = spec.H; nu = size(ag.B, 2)
    M = kron(Matrix(1.0I, H, H), ag.R)
    for t in spec.track
        t == 0 && continue
        M .+= Th[t+1]' * (ag.Ct' * ag.Q * ag.Ct) * Th[t+1]
    end
    spec.terminal == :cost && (M .+= Th[H+1]' * ag.Qf * Th[H+1])
    return Symmetric((M + M') / 2) |> Matrix
end

function CFleet(agents::Vector{CAgent}, spec::CSpec, edges, W, o; maps = nothing)
    cache = Dict{UInt,Tuple{Vector{Matrix{Float64}},Matrix{Float64}}}()
    Th = Vector{Vector{Matrix{Float64}}}(undef, length(agents)); H0 = Vector{Matrix{Float64}}(undef, length(agents))
    for (i, ag) in enumerate(agents)
        key = hash((ag.A, ag.B, ag.Ct, ag.Q, ag.R, ag.Qf))
        if !haskey(cache, key)
            T = thetas30(ag, spec.H)
            cache[key] = (T, own_hessian30(ag, T, spec))
        end
        Th[i], H0[i] = cache[key]
    end
    nus = [size(ag.B, 2) for ag in agents]
    uoff = [0; cumsum(nus .* spec.H)[1:end-1]]
    E = collect(edges)
    Me = maps === nothing ? [(agents[i].C, agents[j].C) for (i, j) in E] : [(Matrix{Float64}(a), Matrix{Float64}(b)) for (a, b) in maps]
    pk = [size(m[1], 1) for m in Me]
    return CFleet(agents, spec, E, W, o, Th, H0, maximum(nus), maximum(pk; init = 0), nus, uoff, Me, pk)
end

"""The data of one step: measured states, tracking references r[i][t+1] (columns), terminal targets."""
struct CData
    x0::Vector{Vector{Float64}}
    refs::Vector{Matrix{Float64}}
    rf::Vector{Vector{Float64}}
end

# the free responses free[i][t+1]
function frees30(cf::CFleet, d::CData)
    H = cf.spec.H
    out = Vector{Vector{Vector{Float64}}}(undef, nagents(cf))
    for (i, ag) in enumerate(cf.agents)
        f = Vector{Vector{Float64}}(undef, H + 1); f[1] = copy(d.x0[i])
        for t in 1:H
            f[t+1] = ag.A * f[t] + ag.g
        end
        out[i] = f
    end
    return out
end

"""
The condensed program of a step: own quadratic per agent (H0, h, c), the
formation rows A (edge-major: k, then the instants of spec.form; p rows each)
with targets b and stiffness W, residual A u - b; and for terminal = :equality
the terminal rows E u = e per agent.
"""
struct CProg
    cf::CFleet
    h::Vector{Float64}
    c::Float64
    A::SparseMatrixCSC{Float64,Int}
    b::Vector{Float64}
    Wd::SparseMatrixCSC{Float64,Int}
    rowof::Dict{Tuple{Int,Int},UnitRange{Int}}     # (k, t) -> rows
    E::SparseMatrixCSC{Float64,Int}
    e::Vector{Float64}
    free::Vector{Vector{Vector{Float64}}}
end

"""The data part of a step (h, c, b, e, free responses) for the structure `rowof` (online: no matrix is built)."""
function cdata30(cf::CFleet, d::CData, rowof, nrows::Int)
    H = cf.spec.H; n = nagents(cf); N = ncols30(cf)
    fr = frees30(cf, d)
    h = zeros(N); c = 0.0
    for (i, ag) in enumerate(cf.agents)
        Th = cf.Theta[i]; cols = ucols(cf, i)
        for t in cf.spec.track
            e = ag.Ct * fr[i][t+1] - d.refs[i][:, t+1]
            c += 0.5 * dot(e, ag.Q * e)
            t == 0 && continue
            mul!(view(h, cols), Th[t+1]', ag.Ct' * (ag.Q * e), 1.0, 1.0)
        end
        if cf.spec.terminal == :cost
            e = fr[i][H+1] - d.rf[i]
            c += 0.5 * dot(e, ag.Qf * e)
            mul!(view(h, cols), Th[H+1]', ag.Qf * e, 1.0, 1.0)
        end
    end
    b = zeros(nrows)
    for (k, (i, j)) in enumerate(cf.edges), (l, t) in enumerate(cf.spec.form)
        d0 = cf.Me[k][2] * fr[j][t+1] - cf.Me[k][1] * fr[i][t+1] - cf.o[k][l]      # the defect at u = 0
        if t == 0
            c += 0.5 * dot(d0, cf.W[k][l] * d0)          # a constant row: kept with zero coefficients for the layout
        else
            b[rowof[(k, t)]] .= -d0
        end
    end
    e = Float64[]
    if cf.spec.terminal == :equality
        for i in 1:n
            append!(e, d.rf[i] - fr[i][H+1])
        end
    end
    return h, c, b, e, fr
end

function CProg(cf::CFleet, d::CData)
    H = cf.spec.H; n = nagents(cf); N = ncols30(cf)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]; WI = Int[]; WJ = Int[]; WV = Float64[]
    rowof = Dict{Tuple{Int,Int},UnitRange{Int}}()
    r = 0
    for (k, (i, j)) in enumerate(cf.edges), (l, t) in enumerate(cf.spec.form)
        p = cf.pk[k]
        rowof[(k, t)] = (r+1):(r+p)
        Wm = cf.W[k][l]
        if t > 0
            Mi = -cf.Me[k][1] * cf.Theta[i][t+1]; Mj = cf.Me[k][2] * cf.Theta[j][t+1]
            for (M, a) in ((Mi, i), (Mj, j)), q in axes(M, 2), s in axes(M, 1)
                M[s, q] != 0 && (push!(I_, r + s); push!(J_, ucols(cf, a)[q]); push!(V_, M[s, q]))
            end
        end
        for q in 1:p, s in 1:p
            Wm[s, q] != 0 && (push!(WI, r + s); push!(WJ, r + q); push!(WV, (t == 0 ? 0.0 : Wm[s, q])))
        end
        r += p
    end
    A = sparse(I_, J_, V_, r, N); Wd = sparse(WI, WJ, WV, r, r)
    EI = Int[]; EJ = Int[]; EV = Float64[]
    if cf.spec.terminal == :equality
        rr = 0
        for (i, ag) in enumerate(cf.agents)
            T = cf.Theta[i][H+1]
            for q in axes(T, 2), s in axes(T, 1)
                T[s, q] != 0 && (push!(EI, rr + s); push!(EJ, ucols(cf, i)[q]); push!(EV, T[s, q]))
            end
            rr += size(T, 1)
        end
        E = sparse(EI, EJ, EV, rr, N)
    else
        E = spzeros(0, N)
    end
    h, c, b, e, fr = cdata30(cf, d, rowof, r)
    return CProg(cf, h, c, A, b, Wd, rowof, E, e, fr)
end

"""The program of new data on the structure of `base` (online part only)."""
function CProg(base::CProg, d::CData)
    h, c, b, e, fr = cdata30(base.cf, d, base.rowof, size(base.A, 1))
    return CProg(base.cf, h, c, base.A, b, base.Wd, base.rowof, base.E, e, fr)
end

H0blk30(cf::CFleet) = blockdiag((sparse(H) for H in cf.H0)...)

"""Rows of the merged edges of a team structure (labels per agent): all instants of spec.form but 0."""
function srows30(P::CProg, teams::Vector{Int})
    rows = Int[]
    for (k, (i, j)) in enumerate(P.cf.edges)
        teams[i] == teams[j] || continue
        for t in P.cf.spec.form
            t == 0 && continue
            append!(rows, P.rowof[(k, t)])
        end
    end
    return rows
end

softrows30(P::CProg, S::Vector{Int}) = setdiff(1:size(P.A, 1), S)

"""J(u) of the full program (every formation edge soft)."""
function Jfull30(P::CProg, u)
    H0 = H0blk30(P.cf)
    r = P.A * u - P.b
    return 0.5 * dot(u, H0 * u) + dot(P.h, u) + P.c + 0.5 * dot(r, P.Wd * r)
end

"""The gradient of J_rest (own costs plus every formation edge not in S), with its matrices built once (offline)."""
struct RestOp
    H0b::SparseMatrixCSC{Float64,Int}
    keep::Vector{Int}
    As::SparseMatrixCSC{Float64,Int}
    AsT::SparseMatrixCSC{Float64,Int}
    Ws::SparseMatrixCSC{Float64,Int}
end
RestOp(P::CProg, S::Vector{Int}) = (keep = softrows30(P, S); As = P.A[keep, :];
    RestOp(H0blk30(P.cf), keep, As, sparse(As'), P.Wd[keep, keep]))

grad_rest30(op::RestOp, P::CProg, u) = op.H0b * u .+ P.h .+ op.AsT * (op.Ws * (op.As * u .- P.b[op.keep]))
grad_rest30(P::CProg, u, S::Vector{Int}) = grad_rest30(RestOp(P, S), P, u)

# ---------------------------------------------------------------------------
# Clarabel: the full program P and the team program P[S]
# ---------------------------------------------------------------------------

"""
Independent equality rows of a team program (positions in [S rows; terminal rows]): per team, the merged rows of
the team and its members' terminal rows, a pivoted QR (the rows are structural, the data enter only b, and P[S]
is feasible, so dropping dependent rows leaves its feasible set unchanged; a dropped row gets multiplier 0).
"""
function eqkeep30(P::CProg, teams::Vector{Int}, S::Vector{Int})
    cf = P.cf; nS = length(S); nx = size(cf.agents[1].A, 1)
    spos = Dict(r => l for (l, r) in enumerate(S))
    keep = Int[]
    for T in sort(unique(teams))
        mem = findall(==(T), teams)
        rowsS = Int[]
        for (k, (i, j)) in enumerate(cf.edges)
            (teams[i] == T && teams[j] == T && nS > 0) || continue
            for t in cf.spec.form
                t == 0 && continue
                append!(rowsS, [spos[r] for r in P.rowof[(k, t)]])
            end
        end
        rowsE = size(P.E, 1) > 0 ? reduce(vcat, (collect(nS .+ (((i-1)*nx+1):(i*nx))) for i in mem)) : Int[]
        rows = [rowsS; rowsE]
        isempty(rows) && continue
        cols = reduce(vcat, (collect(ucols(cf, i)) for i in mem))
        M = Matrix([P.A[S, :]; P.E][rows, cols])
        F = qr(M', ColumnNorm())
        d = abs.(diag(F.R)); r = count(>(1e-10 * maximum(d; init = 0.0)), d)
        append!(keep, rows[F.p[1:r]])
    end
    return sort(keep)
end

"""
Solve P (S empty: every edge soft) or P[S] (the rows S as equalities) with
Clarabel. Returns u, J (with the constant, the soft edges of S at zero in P[S]),
status, mu (duals of the S rows, sign: stationarity grad + A_S' mu + nu = 0),
nu (the input-cone part of the stationarity, per u entry), lam (terminal rows),
seconds.
"""
function clarabel30(P::CProg, S::Vector{Int}; tol = TOL30, maxit = 400, keep = nothing)
    cf = P.cf; N = size(P.A, 2); H = cf.spec.H
    soft = softrows30(P, S)
    As = P.A[soft, :]; Ws = P.Wd[soft, soft]; bs = P.b[soft]
    Pm = H0blk30(cf) + As' * Ws * As
    q = P.h - As' * (Ws * bs)
    c = P.c + 0.5 * dot(bs, Ws * bs)
    nS = length(S); nE = size(P.E, 1)
    Aeq = [P.A[S, :]; P.E]; beq = [P.b[S]; P.e]
    kp = keep === nothing ? collect(1:(nS + nE)) : keep
    Arows = SparseMatrixCSC{Float64,Int}[sparse(Aeq[kp, :])]; brows = beq[kp]
    cones = Clarabel.SupportedCone[]
    isempty(kp) || push!(cones, Clarabel.ZeroConeT(length(kp)))
    SI = Int[]; SJ = Int[]; SV = Float64[]; sb = Float64[]; r = 0
    for i in 1:nagents(cf), t in 0:(H-1)
        nu = cf.nus[i]
        push!(sb, cf.agents[i].umax); append!(sb, zeros(nu))
        for a in 1:nu
            push!(SI, r + 1 + a); push!(SJ, uidx(cf, i, t)[a]); push!(SV, -1.0)
        end
        push!(cones, Clarabel.SecondOrderConeT(1 + nu)); r += 1 + nu
    end
    push!(Arows, sparse(SI, SJ, SV, r, N)); append!(brows, sb)
    Am = vcat(Arows...)
    st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol, max_iter = maxit)
    solver = Clarabel.Solver()
    t0 = time_ns()
    Clarabel.setup!(solver, sparse(triu(Pm)), q, Am, brows, cones, st)
    sol = Clarabel.solve!(solver)
    secs = sec27(time_ns(), t0)
    u = copy(sol.x); z = copy(sol.z)
    zeq = zeros(nS + nE); zeq[kp] .= z[1:length(kp)]
    mu = zeq[1:nS]; lam = zeq[(nS+1):(nS+nE)]
    nuv = zeros(N); r = length(kp)
    for i in 1:nagents(cf), t in 0:(H-1)
        nu = cf.nus[i]
        nuv[uidx(cf, i, t)] .= -z[(r+2):(r+1+nu)]
        r += 1 + nu
    end
    J = 0.5 * dot(u, Pm * u) + dot(q, u) + c
    return (u = u, J = J, status = string(sol.status), mu = mu, nu = nuv, lam = lam, seconds = secs,
            iters = sol.iterations)
end

# ---------------------------------------------------------------------------
# The bound's operators, per team
# ---------------------------------------------------------------------------

struct TeamOp
    members::Vector{Int}
    rows::Vector{Int}                 # global formation rows (positions in A)
    srows::Vector{Int}                # positions of these rows in the S ordering
    cols::Vector{Int}
    M::Matrix{Float64}                # Gamma = 1/2 mu' M mu
    U0::Matrix{Float64}               # basis of null(A_T')
    pinvAt::Matrix{Float64}           # (A_T')^+ : mu = -pinvAt * (g + nu)_T
    At::SparseMatrixCSC{Float64,Int}  # A_T'
    G::Matrix{Float64}                # pinvAt' M pinvAt: Gamma = 1/2 w' G w for A_T' mu = w
    Iota::Matrix{Float64}             # basis of null(A_T): A_T' mu = w is solvable iff Iota' w = 0
    Winv::Matrix{Float64}
    rank::Int
    lam_max::Float64
end

"""
The team operators of a team structure for the condensed program `P`. `Hinv`
per agent (default H0^{-1}; `restrict = true` replaces it by Z (Z'H0Z)^{-1} Z'
with Z the null space of the agent's terminal rows, the agent's feasible
directions under the terminal equality).
"""
function teamops30(P::CProg, teams::Vector{Int}, S::Vector{Int}; restrict::Bool = false)
    cf = P.cf
    Hinv = Vector{Matrix{Float64}}(undef, nagents(cf))
    cache = Dict{UInt,Matrix{Float64}}()
    for i in 1:nagents(cf)
        key = hash((cf.H0[i], restrict ? cf.Theta[i][end] : 0))
        Hinv[i] = get!(cache, key) do
            if restrict
                Z = nullspace(cf.Theta[i][end])
                Z * ((Z' * cf.H0[i] * Z) \ Z')
            else
                inv(cf.H0[i])
            end
        end
    end
    spos = Dict(r => l for (l, r) in enumerate(S))
    opcache = Dict{UInt,Any}()
    ops = TeamOp[]
    for T in sort(unique(teams))
        mem = findall(==(T), teams)
        rows = Int[]
        for (k, (i, j)) in enumerate(cf.edges)
            (teams[i] == T && teams[j] == T) || continue
            for t in cf.spec.form
                t == 0 && continue
                append!(rows, P.rowof[(k, t)])
            end
        end
        isempty(rows) && continue
        cols = reduce(vcat, (collect(ucols(cf, i)) for i in mem))
        AT = Matrix(P.A[rows, cols])
        Wt = Matrix(P.Wd[rows, rows])
        key = hash((AT, Wt, [hash(Hinv[i]) for i in mem]))
        if !haskey(opcache, key)                       # teams with the same members' dynamics and edges share their operators
            HinvT = zeros(length(cols), length(cols)); off = 0
            for i in mem
                m = cf.nus[i] * cf.spec.H
                HinvT[(off+1):(off+m), (off+1):(off+m)] .= Hinv[i]; off += m
            end
            M, rk, lmax = gamma_operator30(Symmetric(AT * HinvT * AT'), Wt)
            F = svd(AT')                               # AT' = U S V'
            sv = F.S; tolsv = sqrt(EIGTOL30) * maximum(sv; init = 0.0)
            r = count(>(tolsv), sv)
            pinvAt = F.V[:, 1:r] * Diagonal(1 ./ sv[1:r]) * F.U[:, 1:r]'
            U0 = F.V[:, (r+1):end]                     # null(A_T') (A_T' is |cols| x |rows|, |cols| >= |rows| here)
            size(AT, 2) >= size(AT, 1) || (U0 = nullspace(AT'; atol = tolsv))
            G = pinvAt' * M * pinvAt
            opcache[key] = (M, U0, pinvAt, inv(Wt), rk, lmax, (G + G') / 2, nullspace(AT; atol = tolsv))
        end
        M, U0, pinvAt, Wi, rk, lmax, G, Iota = opcache[key]
        push!(ops, TeamOp(mem, rows, [spos[x] for x in rows], cols, M, U0, pinvAt, sparse(AT'), G, Iota, Wi, rk, lmax))
    end
    return ops
end

"""M = Khat^{1/2} (I + Khat^{1/2} W Khat^{1/2})^{-1} Khat^{1/2} through the eigendecomposition of Khat (range only)."""
function gamma_operator30(Kh::Symmetric, W::AbstractMatrix)
    ev = eigen(Kh)
    lmax = maximum(ev.values; init = 0.0)
    keep = ev.values .> EIGTOL30 * lmax
    Ls = ev.vectors[:, keep] * Diagonal(sqrt.(ev.values[keep]))
    Mi = Symmetric(Matrix(1.0I, count(keep), count(keep)) + Ls' * W * Ls)
    M = Ls * (Mi \ Ls')
    return (M + M') / 2, count(keep), lmax
end

"""The bounds from a multiplier mu of the merged rows (in the S ordering): Gamma and the old bound."""
function bounds_from_mu30(ops::Vector{TeamOp}, mu::AbstractVector)
    G = 0.0; old = 0.0; per = Float64[]
    for op in ops
        m = mu[op.srows]
        g = 0.5 * dot(m, op.M * m)
        G += g; push!(per, g)
        # least W^{-1}-norm multiplier among m + null(A_T')
        if size(op.U0, 2) > 0
            a = (op.U0' * op.Winv * op.U0) \ (op.U0' * op.Winv * m)
            m = m - op.U0 * a
        end
        old += 0.5 * dot(m, op.Winv * m)
    end
    return (Gamma = G, old = old, per_team = per)
end

"""mu from stationarity on the full space at the team plan z with cone part nu: per team least squares; the relative residual."""
function recover_mu30(P::CProg, ops::Vector{TeamOp}, S::Vector{Int}, z, nuv; rest::RestOp = RestOp(P, S))
    g = grad_rest30(rest, P, z) .+ nuv
    mu = zeros(length(S)); res = 0.0; gn = 0.0
    for op in ops
        gT = g[op.cols]
        m = -(op.pinvAt * gT)
        mu[op.srows] .= m
        res = max(res, norm(op.At * m .+ gT, Inf)); gn = max(gn, norm(gT, Inf))
    end
    return mu, res / max(gn, 1.0)
end

"""
The tightest Gamma over the multipliers of the team solve. When members share
inputs their input-cone duals are not unique (LICQ fails), and neither is mu;
every KKT pair (mu, nu) at the team plan z gives a valid bound. With nu_it =
nu0_it + delta_it zhat_it on every active ball (zhat = z_it/||z_it||) and
c0_it + delta_it >= 0 (c0 the solver's multiplier), w = g + nu must stay in
range(A_T') (Iota' N delta = 0), and Gamma = 1/2 w' G w is a convex QP in delta,
per team, solved by Clarabel on the null space of Iota' N. Returns Gamma*, mu*,
the number of active balls and the relative stationarity residual of (mu*, nu*).
"""
function tight_gamma30(P::CProg, ops::Vector{TeamOp}, S::Vector{Int}, z, nuv; rest::RestOp = RestOp(P, S), tol = 1e-10)
    cf = P.cf; H = cf.spec.H
    g = grad_rest30(rest, P, z) .+ nuv
    tot = 0.0; mu = zeros(length(S)); nact = 0; res = 0.0; gn = 0.0
    for op in ops
        w0 = g[op.cols]
        pos = Dict(c => l for (l, c) in enumerate(op.cols))
        cols = Vector{Int}[]; dirs = Vector{Float64}[]; c0 = Float64[]
        for i in op.members, t in 0:(H-1)
            ix = uidx(cf, i, t); zi = z[ix]; r = cf.agents[i].umax
            norm(zi) >= (1 - ACTIVE_TOL30) * r || continue
            zh = zi / norm(zi)
            push!(cols, [pos[c] for c in ix]); push!(dirs, zh); push!(c0, max(dot(nuv[ix], zh), 0.0))
        end
        na = length(c0); nact += na
        dl = zeros(na)
        if na > 0
            Nm = zeros(length(op.cols), na)
            for a in 1:na
                Nm[cols[a], a] .= dirs[a]
            end
            X = op.Iota' * Nm
            Z = nullspace(X; atol = 1e-8 * max(opnorm(X), 1.0))
            if size(Z, 2) > 0
                GN = op.G * Nm
                Pq = Symmetric(Z' * (Nm' * GN) * Z); qq = Z' * (GN' * w0)
                solver = Clarabel.Solver()
                st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol, max_iter = 500)
                Clarabel.setup!(solver, sparse(triu(Matrix(Pq))), qq, sparse(-Z), c0, [Clarabel.NonnegativeConeT(na)], st)
                sol = Clarabel.solve!(solver)
                if sol.status == Clarabel.SOLVED
                    eta = sol.x
                    cand = Z * eta
                    w1 = w0 + Nm * cand
                    0.5 * dot(w1, op.G * w1) <= 0.5 * dot(w0, op.G * w0) && (dl = cand)
                end
            end
            w0 = w0 + Nm * dl
        end
        tot += 0.5 * dot(w0, op.G * w0)
        m = -(op.pinvAt * w0)
        mu[op.srows] .= m
        res = max(res, norm(op.At * m .+ w0, Inf)); gn = max(gn, norm(w0, Inf), norm(g[op.cols], Inf))
    end
    return tot, mu, nact, res / max(gn, 1.0)
end

# ---------------------------------------------------------------------------
# The certificate in its multiplier-free form (the primary one)
# ---------------------------------------------------------------------------
#
# For any g in grad J_rest(z) + N_U(z) at the lifted team plan z, strong
# convexity of J_rest with modulus H0 gives, for every u = z + d in U,
# J(u) >= J_rest(z) + <g, d> + 1/2 d'H0 d + 1/2 (A_S d)'W(A_S d) (A_S z = b_S),
# whose minimum over d is J*(P[S]) - 1/2 g'H^{-1}g with H = H0 + A_S'W A_S. So
#
#     gamma <= Gamma(g) = 1/2 g' H^{-1} g,
#
# for every such g; no multiplier of the merged edges and no constraint
# qualification enters. H is block diagonal over the teams (and the agents in no
# team), so Gamma is a sum of per-team terms. The certificate is the minimum
# over the normal cone: nu = sum over the active balls of c_it zhat_it, c >= 0
# (inactive balls contribute 0), a nonnegative least-squares problem per team in
# the H^{-1} metric (Clarabel). With the terminal equality (Part B) d also keeps
# every agent's terminal state: H is restricted to Z = blkdiag(null of the
# members' terminal rows), Gamma = 1/2 g'Z (Z'HZ)^{-1} Z'g (the terminal
# multipliers eliminated). When g = -A_S'mu, Woodbury gives back the mu form
# 1/2 mu'(W + Khat^{-1})^{-1} mu; the minimum over nu is at most the tightest mu
# form (it drops the requirement that g lie in range(A_S')).

struct CertOp
    members::Vector{Int}
    cols::Vector{Int}
    Z::Matrix{Float64}             # empty: no restriction
    L::LowerTriangular{Float64,Matrix{Float64}}    # cholesky factor of (Z'HZ or H)
    R::Matrix{Float64}             # L^{-1} Z' (or L^{-1}): Gamma(g) = 1/2 ||R g_T||^2
end

function certops30(P::CProg, teams::Vector{Int}, S::Vector{Int}; restrict::Bool = false)
    cf = P.cf
    cache = Dict{UInt,Any}(); ops = CertOp[]
    for T in sort(unique(teams))
        mem = findall(==(T), teams)
        cols = reduce(vcat, (collect(ucols(cf, i)) for i in mem))
        rows = Int[]
        for (k, (i, j)) in enumerate(cf.edges)
            (teams[i] == T && teams[j] == T) || continue
            for t in cf.spec.form
                t == 0 && continue
                append!(rows, P.rowof[(k, t)])
            end
        end
        AT = Matrix(P.A[rows, cols]); Wt = Matrix(P.Wd[rows, rows])
        key = hash((AT, Wt, [hash(cf.H0[i]) for i in mem], restrict ? [hash(cf.Theta[i][end]) for i in mem] : 0))
        if !haskey(cache, key)
            Hm = zeros(length(cols), length(cols)); off = 0
            for i in mem
                m = cf.nus[i] * cf.spec.H
                Hm[(off+1):(off+m), (off+1):(off+m)] .= cf.H0[i]; off += m
            end
            Hm .+= AT' * Wt * AT
            Z = zeros(0, 0)
            if restrict
                Z = cat((nullspace(cf.Theta[i][end]) for i in mem)...; dims = (1, 2))
                Hm = Z' * Hm * Z
            end
            L = cholesky(Symmetric((Hm + Hm') / 2)).L
            cache[key] = (Z, L, isempty(Z) ? Matrix(inv(L)) : L \ Matrix(Z'))
        end
        Z, L, R = cache[key]
        push!(ops, CertOp(mem, cols, Z, L, R))
    end
    return ops
end

"""
Lawson-Hanson active-set NNLS on the normal equations: argmin over c >= 0 of
1/2 c'Gc - h'c (G = Y'Y, h = -Y'y0, i.e. 1/2||y0 + Y c||^2). Small dense problems
(the active balls of one team).
"""
function nnls30(G::AbstractMatrix, h::AbstractVector; maxit::Int = 30 * length(h) + 50)
    k = length(h); x = zeros(k); Pset = falses(k)
    tol = 1e-12 * max(maximum(abs, h; init = 0.0), maximum(abs, G; init = 0.0), 1.0)
    w = h - G * x; it = 0
    while it < maxit
        cand = [j for j in 1:k if !Pset[j] && w[j] > tol]
        isempty(cand) && break
        Pset[cand[argmax(w[cand])]] = true
        while it < maxit
            it += 1
            p = findall(Pset)
            zp = Symmetric(G[p, p]) \ h[p]
            if all(>(tol), zp)
                fill!(x, 0.0); x[p] .= zp; break
            end
            alpha = minimum(x[p[a]] / (x[p[a]] - zp[a]) for a in eachindex(p) if zp[a] <= tol)
            z = zeros(k); z[p] .= zp
            x .+= alpha .* (z .- x)
            for j in p
                x[j] <= tol && (Pset[j] = false; x[j] = 0.0)
            end
        end
        w = h - G * x
    end
    return x
end

"""
Gamma(g) per team at g = grad J_rest(z) + nu: with the given nu (`nuv`, e.g.
the solver's duals) and its minimum over the normal cone of the active balls.
Returns (Gamma_given, Gamma_min, active balls, per-team minima).
"""
function cert30(P::CProg, ops::Vector{CertOp}, z, nuv; rest::RestOp, tol = 1e-10, method::Symbol = :lh)
    cf = P.cf; H = cf.spec.H
    g0 = grad_rest30(rest, P, z)
    Gg = 0.0; Gm = 0.0; nact = 0; per = Float64[]
    for op in ops
        gT = g0[op.cols]
        y = op.R * (gT .+ nuv[op.cols])
        Gg += 0.5 * dot(y, y)
        y0 = op.R * gT
        val = 0.5 * dot(y0, y0)
        act = Tuple{UnitRange{Int},Vector{Float64}}[]          # (columns of the ball in the team block, zhat)
        off = 0
        for i in op.members
            nu = cf.nus[i]
            for t in 0:(H-1)
                ix = uidx(cf, i, t); zi = z[ix]
                nz = norm(zi)
                nz >= (1 - ACTIVE_TOL30) * cf.agents[i].umax || continue
                push!(act, (off + t * nu .+ (1:nu), zi / nz))
            end
            off += nu * H
        end
        na = length(act); nact += na
        if na > 0
            Y = zeros(size(op.R, 1), na)                       # R N: the balls' normal directions
            for (k, (rr, zh)) in enumerate(act)
                mul!(view(Y, :, k), view(op.R, :, rr), zh)
            end
            if method == :lh
                c = max.(nnls30(Y' * Y, -(Y' * y0)), 0.0)
            else
                solver = Clarabel.Solver()
                st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol, max_iter = 500)
                Pq = Y' * Y
                Clarabel.setup!(solver, sparse(triu((Pq + Pq') / 2)), Y' * y0, sparse(-1.0I, na, na), zeros(na),
                                [Clarabel.NonnegativeConeT(na)], st)
                c = max.(Clarabel.solve!(solver).x, 0.0)    # in the cone exactly
            end
            yc = y0 + Y * c
            val = min(val, 0.5 * dot(yc, yc))              # c = 0 is always admissible
        end
        Gm += val; push!(per, val)
    end
    return Gg, Gm, nact, per
end

"""The lower bound of Thm. thm:price at the full optimum u*: (1/2)||A_S u* - b_S||^2_W."""
function lower30(P::CProg, S::Vector{Int}, ustar)
    s = P.A[S, :] * ustar - P.b[S]
    return 0.5 * dot(s, P.Wd[S, S] * s)
end

"""Active input balls of a plan (count) and the largest ||u||/r."""
function active30(cf::CFleet, u)
    na = 0; mx = 0.0
    for i in 1:nagents(cf), t in 0:(cf.spec.H-1)
        r = norm(u[uidx(cf, i, t)]) / cf.agents[i].umax
        mx = max(mx, r); r >= 1 - ACTIVE_TOL30 && (na += 1)
    end
    return na, mx
end

"""
Gamma with H0 replaced by the exact Hessian of J_rest (every formation edge not
in S kept): Khat = A_S Hrest^{-1} A_S' over all of S (not block diagonal). Equal
to gamma for a QP whose inequalities are inactive at both optima. Small sizes.
"""
function gamma_exact30(P::CProg, S::Vector{Int}, mu)
    keep = softrows30(P, S)
    As = P.A[keep, :]
    Hr = Matrix(H0blk30(P.cf) + As' * P.Wd[keep, keep] * As)
    AS = Matrix(P.A[S, :])
    M, _, _ = gamma_operator30(Symmetric(AS * (Hr \ AS')), Matrix(P.Wd[S, S]))
    return 0.5 * dot(mu, M * mu)
end

# ---------------------------------------------------------------------------
# E27's fleet as a condensed fleet, its team structures, the package's solves
# ---------------------------------------------------------------------------

function cfleet27(sc::Scenario27)
    fl = sc.fleet; H = sc.H
    for ag in fl.agents
        ag.Cf == Matrix(1.0I, ag.nx, ag.nx) || error("terminal output must be the state")
        isdiag(ag.Q) || error("diagonal Q expected (the package's node constant)")
    end
    ags = [CAgent(ag.A[1], ag.B[1], ag.g[1], ag.C, ag.Cr, ag.Q, ag.R, ag.Cf' * ag.Qf * ag.Cf, ag.input.radius) for ag in fl.agents]
    spec = CSpec(H, collect(0:(H-1)), collect(1:H), :cost)
    W = [[fl.weights[k, t] * Matrix(1.0I, size(fl.select[k], 1), size(fl.select[k], 1)) for t in 1:H] for k in eachindex(fl.edges)]
    o = [[fl.select[k] * fl.targets[:, k, t] for t in 1:H] for k in eachindex(fl.edges)]
    return CFleet(ags, spec, fl.edges, W, o; maps = [SM.edge_maps(fl, k) for k in eachindex(fl.edges)])
end

"""Team labels per vehicle: `rows`, `blocks2` (2 x 2 blocks of the grid: two rows, so both airframes, and a cycle), or
`seg<k>` (k consecutive vehicles of a row, one airframe, a path; seg<side> is rows)."""
function teams27(sc::Scenario27, kind::AbstractString)
    kind == "rows" && return [row27(sc, i) for i in 1:sc.n]
    if kind == "mirror"                       # pairs mirrored in a row: (r, c) with (r, side + 1 - c)
        iseven(sc.side) || error("mirror needs an even side")
        h = div(sc.side, 2)
        return [(row27(sc, i) - 1) * h + min(col27(sc, i), sc.side + 1 - col27(sc, i)) for i in 1:sc.n]
    end
    if startswith(kind, "seg")
        k = min(parse(Int, kind[4:end]), sc.side)      # clamped for the 4 x 4 warm-up fleet
        rem(sc.side, k) == 0 || error("seg$k needs k to divide the side")
        return [(row27(sc, i) - 1) * div(sc.side, k) + div(col27(sc, i) - 1, k) + 1 for i in 1:sc.n]
    end
    if kind == "blocks2"
        iseven(sc.side) || error("blocks2 needs an even side")
        return [div(row27(sc, i) - 1, 2) * div(sc.side, 2) + div(col27(sc, i) - 1, 2) + 1 for i in 1:sc.n]
    end
    error("unknown team structure $kind")
end

"""The package's reduction of the parametric program for a team structure (rows: E27's chain; otherwise condense, then merge)."""
function reduction30(pp::ParamProgram27, sc::Scenario27, kind::AbstractString)
    kind == "rows" && return chain27(pp, sc, "rows")[1]
    teams = teams27(sc, kind)
    R1 = reduce(pp.P, SM.VertexPartition([i for i in 1:sc.n for t in 0:sc.H]))
    SM.nvertices(R1.program) == sc.n || error("unexpected coarse vertex count")
    return SM.ReducedProgram[R1, reduce(R1, SM.VertexPartition(SM.canonical_partition(teams)))]
end

uvec27(pp::ParamProgram27, sc::Scenario27, x) = reduce(vcat, (vec(U) for U in inputs27(pp, sc, x)))

"""The positions of every agent's inputs (condensed order) in a plan of the parametric program: z = x[uindex27(pp, sc)]."""
function uindex27(pp::ParamProgram27, sc::Scenario27)
    idx = Int[]
    for i in 1:sc.n
        nx, nu = sc.fleet.agents[i].nx, sc.fleet.agents[i].nu
        append!(idx, collect(SM.vrange(pp.P, pp.vid[i, 1])))
        for t in 1:(sc.H-1)
            append!(idx, collect(SM.vrange(pp.P, pp.vid[i, t+1]))[(nx+1):(nx+nu)])
        end
    end
    return idx
end

"""The members' input-cone part nu of the stationarity, from the reduced solve's node duals (a merged dual split evenly)."""
function nu_from_reduced30(cf::CFleet, pp::ParamProgram27, sc::Scenario27, R::SM.ReducedProgram, sol)
    P = pp.P
    _, _, _, row_map = SM.composite_partition(R)
    yf = zeros(SM.noderows(P)); yf[row_map] .= sol.node_duals
    nuv = zeros(ncols30(cf))
    for i in 1:sc.n, t in 0:(sc.H-1)
        rr = SM.rrange(P, pp.vid[i, t+1])
        length(rr) == 1 + cf.nus[i] || error("unexpected node rows")
        nuv[uidx(cf, i, t)] .= -yf[rr[2:end]]
    end
    return nuv
end

"""The package Certifier's forces (least W^{-1}-norm, time-expanded) in the S ordering of the condensed program."""
function mu_certifier30(Pc::CProg, sc::Scenario27, C::SM.Certifier, S::Vector{Int})
    mus = SM.multipliers(C); ne = length(sc.fleet.edges)
    mu = zeros(length(S)); pos = Dict(r => l for (l, r) in enumerate(S))
    for (k, (i, j)) in enumerate(sc.fleet.edges), t in 1:sc.H
        e = sc.n * sc.H + (t - 1) * ne + k
        haskey(mus, e) || continue
        for (a, r) in enumerate(Pc.rowof[(k, t)])
            haskey(pos, r) && (mu[pos[r]] = mus[e][a])
        end
    end
    return mu
end

function probe30()
    side = parse(Int, get(ENV, "BENCH_SIDE", "4"))
    for kind in split(get(ENV, "BENCH_TEAMS", "rows"), ","), sigma in (0.0, 0.1)
        sc = Scenario27(side; seed = 1, sigma = sigma, kick = 0.0)
        x0 = start27(sc); refs, term = references27(sc, 0.0)
        pp = ParamProgram27(sc); set_data27!(pp, sc, x0, refs, term)
        chain = reduction30(pp, sc, kind); Rt = chain[end]
        fine0 = SM.solve(pp.P); red0 = SM.solve(Rt)
        C = SM.Certifier(Rt)
        gb = SM.gap_bounds(pp.P, Rt, red0; fine_solution = fine0, cert = C)
        cf = cfleet27(sc); Pc = CProg(cf, CData(x0, refs, term))
        teams = teams27(sc, kind); S = srows30(Pc, teams)
        uf = uvec27(pp, sc, fine0.x); z = uvec27(pp, sc, SM.lift(Rt, red0.x))
        @printf("%s sigma %.2f: J fine pkg %.10g cond %.10g | J team pkg %.10g cond %.10g | team residual %.1e\n", kind, sigma,
                fine0.J, Jfull30(Pc, uf), red0.J, Jfull30(Pc, z), norm(Pc.A[S, :] * z - Pc.b[S], Inf))
        cfull = clarabel30(Pc, Int[]); cteam = clarabel30(Pc, S)
        @printf("   clarabel: J fine %.10g (%s), J team %.10g (%s); |u - pkg| fine %.1e team %.1e\n", cfull.J, cfull.status, cteam.J,
                cteam.status, norm(cfull.u - uf, Inf), norm(cteam.u - z, Inf))
        ops = teamops30(Pc, teams, S)
        murec, res = recover_mu30(Pc, ops, S, z, nu_from_reduced30(cf, pp, sc, Rt, red0))
        mucert = mu_certifier30(Pc, sc, C, S)
        gam = red0.J - fine0.J
        for (nm, mu) in (("clarabel", cteam.mu), ("recovered", murec), ("certifier", mucert))
            bd = bounds_from_mu30(ops, mu)
            @printf("   %-9s  gamma %.6e  lower %.6e  Gamma %.6e  old %.6e   (pkg upper %.6e)  |mu| %.3e\n", nm, gam,
                    lower30(Pc, S, uf), bd.Gamma, bd.old, gb.upper, norm(mu))
        end
        @printf("   recovery residual %.1e; active balls fine %s team %s; Gamma exact-Hessian (clarabel mu) %.6e\n", res,
                active30(cf, uf), active30(cf, z), gamma_exact30(Pc, S, cteam.mu))
        @printf("   rank per team %s of %s rows\n", [op.rank for op in ops], [length(op.rows) for op in ops])
    end
end

# ---------------------------------------------------------------------------
# Part A (a): small random fleets, exact gaps
# ---------------------------------------------------------------------------

"""A random connected partition of the graph (`k` teams grown from random seeds along edges)."""
function random_teams30(rng, n::Int, edges, k::Int)
    nbrs = [Int[] for _ in 1:n]
    for (i, j) in edges
        push!(nbrs[i], j); push!(nbrs[j], i)
    end
    lab = zeros(Int, n)
    for (c, v) in enumerate(randperm(rng, n)[1:k])
        lab[v] = c
    end
    while any(==(0), lab)
        cand = [(v, u) for v in 1:n if lab[v] != 0 for u in nbrs[v] if lab[u] == 0]
        v, u = rand(rng, cand)
        lab[u] = lab[v]
    end
    return SM.canonical_partition(lab)
end

randspd30(rng, d, lo, hi) = (Qm = Matrix(qr(randn(rng, d, d)).Q); Qm * Diagonal(lo .+ (hi - lo) .* rand(rng, d)) * Qm')

"""
A random fleet: n planar double integrators (position output) with their own
drag and input gain, a random connected graph with extra edges (cycles), SPD
edge stiffness W_e (not a multiple of I), formation targets that are
differences of slot paths (consistent around every cycle), a random team
structure, a start on the slots with velocities near the slots' drift (so that
the team programs are feasible), random references. `inactive`: input balls so large that
no inequality is active (the exactness check of the formula with the exact
Hessian); otherwise radii that make some active.
"""
function random_instance30(rng; inactive::Bool)
    n = rand(rng, 4:12); H = rand(rng, 3:8); h = 0.2
    ags = CAgent[]
    for i in 1:n
        d = 0.5 * rand(rng); beta = 0.5 + 1.5 * rand(rng)
        A = [Matrix(1.0I, 2, 2) h*I; zeros(2, 2) (1 - d * h)*I]
        B = beta * [0.5h^2 * Matrix(1.0I, 2, 2); h * Matrix(1.0I, 2, 2)]
        C = [Matrix(1.0I, 2, 2) zeros(2, 2)]
        Q = randspd30(rng, 2, 0.2, 2.0); R = (0.05 + 0.45 * rand(rng)) * Matrix(1.0I, 2, 2)
        Qf = randspd30(rng, 4, 0.5, 5.0)
        push!(ags, CAgent(A, B, zeros(4), C, C, Q, R, Qf, inactive ? 1e4 : 0.3 + 1.2 * rand(rng)))
    end
    edges = Set{Tuple{Int,Int}}()
    perm = randperm(rng, n)
    for a in 2:n
        b = perm[rand(rng, 1:(a-1))]; push!(edges, minmax(perm[a], b))
    end
    for _ in 1:rand(rng, 1:n)
        i, j = rand(rng, 1:n), rand(rng, 1:n)
        i != j && push!(edges, minmax(i, j))
    end
    edges = sort!(collect(edges))
    spec = CSpec(H, collect(0:(H-1)), collect(1:H), :cost)
    slot0 = [3 * randn(rng, 2) for _ in 1:n]; drift = [0.3 * randn(rng, 2) for _ in 1:n]
    slot(i, t) = slot0[i] + t * h * drift[i]
    W = [[(0.3 + 3 * rand(rng)) * randspd30(rng, 2, 0.3, 1.0) for _ in 1:H] for _ in edges]
    o = [[slot(j, t) - slot(i, t) for t in 1:H] for (i, j) in edges]
    cf = CFleet(ags, spec, edges, W, o)
    vc = 0.5 * randn(rng, 2)
    x0 = [[slot0[i]; vc + drift[i] + 0.05 * randn(rng, 2)] for i in 1:n]        # on the slots, velocities near the slots' drift
    refs = Matrix{Float64}[]; rf = Vector{Float64}[]
    for i in 1:n
        R = zeros(2, H + 1); p = slot0[i] + randn(rng, 2)
        for t in 0:H
            R[:, t+1] = p; p = p + h * randn(rng, 2)
        end
        push!(refs, R); push!(rf, [R[:, end]; randn(rng, 2)])
    end
    k = rand(rng, 1:max(1, n ÷ 2))
    teams = random_teams30(rng, n, edges, k)
    return cf, CData(x0, refs, rf), teams
end

function random30()
    N = parse(Int, get(ENV, "BENCH_RANDOM_N", "200"))
    tol = 1e-10
    out = Dict{String,Any}[]
    rng = Xoshiro(30_001)
    it = 0; nsolved = 0
    while nsolved < N
        it += 1
        inactive = it % 4 == 0
        cf, d, teams = random_instance30(rng; inactive = inactive)
        P = CProg(cf, d); S = srows30(P, teams)
        isempty(S) && continue
        fu = clarabel30(P, Int[]; tol = tol, maxit = 1000); te = clarabel30(P, S; tol = tol, maxit = 1000)
        rec = Dict{String,Any}("instance" => it, "n" => nagents(cf), "H" => cf.spec.H, "edges" => length(cf.edges),
            "teams" => maximum(teams), "merged_rows" => length(S), "inactive_design" => inactive,
            "status_full" => fu.status, "status_team" => te.status)
        if fu.status == "SOLVED" && te.status == "SOLVED"
            nsolved += 1
            ops = teamops30(P, teams, S)
            gam = te.J - fu.J
            bd = bounds_from_mu30(ops, te.mu)
            mur, res = recover_mu30(P, ops, S, te.u, te.nu)
            bdr = bounds_from_mu30(ops, mur)
            Gt, _, _, tres = tight_gamma30(P, ops, S, te.u, te.nu)
            rest = RestOp(P, S); cops = certops30(P, teams, S)
            Gsol, Gmin, _, _ = cert30(P, cops, te.u, te.nu; rest = rest)
            Gqp = cert30(P, cops, te.u, te.nu; rest = rest, method = :clarabel)[2]
            # the certificate with the exact Hessian of J (= J_rest's + A_S'WA_S): exact when no inequality is active
            Hfull = Matrix(H0blk30(cf) + P.A' * P.Wd * P.A)
            gs = grad_rest30(rest, P, te.u) .+ te.nu
            Gex = 0.5 * dot(gs, Hfull \ gs)
            naf, mxf = active30(cf, fu.u); nat, mxt = active30(cf, te.u)
            rank_def = sum(length(op.rows) - op.rank for op in ops)
            merge!(rec, Dict{String,Any}("J_full" => fu.J, "J_team" => te.J, "gamma" => gam, "lower" => lower30(P, S, fu.u),
                "Gamma" => Gmin, "Gamma_qp" => Gqp, "Gamma_solver" => Gsol, "Gamma_mu" => bd.Gamma, "Gamma_mu_recovered" => bdr.Gamma, "Gamma_mu_tight" => Gt,
                "tight_residual" => tres, "recovery_residual" => res, "old" => bd.old,
                "Gamma_exact_hessian" => Gex, "Gamma_mu_exact_hessian" => gamma_exact30(P, S, te.mu), "active_full" => naf, "active_team" => nat,
                "rank_deficiency" => rank_def))
            @printf("%3d n %2d H %d teams %d rows %3d (defic %2d) active %2d/%2d: gamma %.4e lower %.4e Gamma %.4e (solver %.4e, mu %.4e, mu tight %.4e) old %.3e exactH %.4e\n",
                    it, nagents(cf), cf.spec.H, maximum(teams), length(S), rank_def, naf, nat, gam, rec["lower"], Gmin, Gsol, bd.Gamma, Gt,
                    bd.old, Gex)
        end
        push!(out, rec)
    end
    write27(joinpath(PARTDIR30, "e30_random.json"), Dict{String,Any}("experiment" => "E30-random", "instances" => out,
        "tol" => tol, "meta" => meta27()))
end

# ---------------------------------------------------------------------------
# Part A (b-d): E27's fleet, step 0 and the team controller's closed loop
# ---------------------------------------------------------------------------

const SIDE30 = parse(Int, get(ENV, "BENCH_SIDE", "4"))
const SIGMAS30 = parse.(Float64, split(get(ENV, "BENCH_SIGMAS", "0,0.01,0.03,0.1,0.3,1"), ","))
const SEEDS30 = parse.(Int, split(get(ENV, "BENCH_SEEDS", "1"), ","))
const KINDS30 = split(get(ENV, "BENCH_TEAMS", "rows"), ",")
const CL_STEPS30 = parse(Int, get(ENV, "BENCH_CL_STEPS", "30"))
const CLARABEL30 = get(ENV, "BENCH_CLARABEL", "0") == "1"
const PARTTAG30 = get(ENV, "BENCH_PARTTAG", "")            # suffix of the part files and their "tag" (e.g. _clar: Clarabel at step 0 only)

"""
One fleet, one team structure: at every step of the team controller's nominal
closed loop (the team program solved by TeamMPC, its first input applied, as
E27's `rows`), the full and team programs are solved (TeamMPC, eps 1e-8, the
package's solve defaults) and recorded: gamma, the lower bound, the old bound
(the package's Certifier, and ours from the same mu), Gamma from the recovered
mu, the recovery residual, active balls, and the times (full solve, team solve,
Gamma online: data, gradient, cone duals, least squares, quadratic forms;
offline: the condensed structure and the team operators). At step 0 with
BENCH_CLARABEL=1 also Clarabel's P and P[S] (condensed) and Gamma from its mu.
"""
function fleet_run30(side::Int, sigma::Float64, seed::Int, kind::AbstractString; steps::Int = CL_STEPS30, clar::Bool = CLARABEL30)
    sc = Scenario27(side; seed = seed, sigma = sigma, kick = 0.0)
    x = start27(sc); refs, term = references27(sc, 0.0)
    pp = ParamProgram27(sc); set_data27!(pp, sc, x, refs, term)
    off = Dict{String,Float64}()
    off["reduction"] = @elapsed chain = reduction30(pp, sc, kind)
    Rt = chain[end]
    cf = cfleet27(sc); teams = teams27(sc, kind)
    off["condensed_structure"] = @elapsed base = CProg(cf, CData(x, refs, term))
    S = srows30(base, teams)
    off["team_operators"] = @elapsed ops = teamops30(base, teams, S)
    off["rest_operator"] = @elapsed rest = RestOp(base, S)
    off["cert_operators"] = @elapsed cops = certops30(base, teams, S)
    off["input_index"] = @elapsed uix = uindex27(pp, sc)
    off["certifier"] = @elapsed cert = SM.Certifier(Rt)
    _, _, _, row_map = SM.composite_partition(Rt)
    recs = Dict{String,Any}[]
    infeasible = 0
    for k in 0:steps
        k > 0 && ((refs, term) = references27(sc, k * sc.h))
        set_data27!(pp, sc, x, refs, term)
        feas = true
        for R in chain
            SM.update!(R); feas &= R.feasible
        end
        GC.gc()
        tf = @elapsed fine = SM.solve(pp.P)
        tr = @elapsed red = SM.solve(Rt)
        rec = Dict{String,Any}("step" => k, "fine_status" => string(fine.status), "team_status" => string(red.status),
                               "team_feasible" => feas, "t_full" => tf, "t_team" => tr, "J_full" => fine.J, "J_team" => red.J)
        if !(feas && SM.isoptimal(red) && SM.isoptimal(fine))
            infeasible += 1; push!(recs, rec)
            @printf("  step %2d: full %s team %s (feasible %s)\n", k, fine.status, red.status, feas)
            break
        end
        xl = SM.lift(Rt, red.x)
        # the certificate online: the step's condensed data, the lifted team plan, per team 1/2 g'H^{-1}g minimized over
        # the normal cone of the active balls (no duals needed)
        GC.gc()                                            # the solves' garbage is not charged to the certificate
        t0 = time_ns()
        Pc = CProg(base, CData(x, refs, term)); t1 = time_ns()
        z = xl[uix]
        Gg0, Gmin, nact, _ = cert30(Pc, cops, z, zeros(length(z)); rest = rest); t2 = time_ns()
        # secondary: the reduced solve's cone duals (a merged dual split evenly), Gamma(g) with them, and the mu forms
        yf = zeros(SM.noderows(pp.P)); yf[row_map] .= red.node_duals
        nuv = zeros(length(z))
        for i in 1:sc.n, t in 0:(sc.H-1)
            rr = SM.rrange(pp.P, pp.vid[i, t+1])
            nuv[uidx(cf, i, t)] .= -view(yf, rr[2:end])
        end
        t3 = time_ns()
        Gsol, _, _, _ = cert30(Pc, cops, z, nuv; rest = rest); t4 = time_ns()
        Gqp = cert30(Pc, cops, z, zeros(length(z)); rest = rest, method = :clarabel)[2]
        mu, res = recover_mu30(Pc, ops, S, z, nuv; rest = rest)
        bd = bounds_from_mu30(ops, mu); t5 = time_ns()
        Gt, mut, _, rest_res = tight_gamma30(Pc, ops, S, z, nuv; rest = rest); t6 = time_ns()
        tcert = @elapsed upk = SM.certify!(cert, xl, red.hard_duals, red.node_duals)
        mucert = mu_certifier30(Pc, sc, cert, S)
        bdc = bounds_from_mu30(ops, mucert)
        uf = fine.x[uix]
        maximum(abs, z - uvec27(pp, sc, xl)) == 0 || error("input index mismatch")
        gam = red.J - fine.J; lo = lower30(Pc, S, uf)
        naf, mxf = active30(cf, uf); nat, mxt = active30(cf, z)
        merge!(rec, Dict{String,Any}("gamma" => gam, "lower" => lo, "Gamma" => Gmin, "Gamma_nu0" => Gg0, "Gamma_solver" => Gsol, "Gamma_qp" => Gqp,
            "Gamma_mu" => bd.Gamma, "Gamma_mu_tight" => Gt, "Gamma_mu_certifier" => bdc.Gamma, "old" => bd.old,
            "old_certifier" => upk, "recovery_residual" => res, "tight_residual" => rest_res,
            "certifier_residual" => cert.residual, "J_full_condensed" => Jfull30(Pc, uf), "J_team_condensed" => Jfull30(Pc, z),
            "team_formation_residual" => norm(Pc.A[S, :] * z - Pc.b[S], Inf), "active_full" => naf, "active_team" => nat,
            "active_balls_cert" => nact, "max_ball_ratio_team" => mxt,
            "t_cert_data" => sec27(t1, t0), "t_cert_bound" => sec27(t2, t1), "t_gamma_online" => sec27(t2, t0),
            "t_duals" => sec27(t3, t2), "t_gamma_solver" => sec27(t4, t3), "t_gamma_mu" => sec27(t5, t4), "t_gamma_mu_tight" => sec27(t6, t5),
            "t_certifier" => tcert, "mu_norm" => norm(mu), "mu_diff_certifier" => norm(mu - mucert) / max(norm(mu), 1e-300)))
        if k == 0 && clar
            GC.gc()
            cfu = clarabel30(Pc, Int[]); cte = clarabel30(Pc, S)
            bdq = bounds_from_mu30(ops, cte.mu)
            Gcs, Gcm, _, _ = cert30(Pc, cops, cte.u, cte.nu; rest = rest)
            merge!(rec, Dict{String,Any}("clarabel_status_full" => cfu.status, "clarabel_status_team" => cte.status,
                "clarabel_J_full" => cfu.J, "clarabel_J_team" => cte.J, "clarabel_gamma" => cte.J - cfu.J,
                "clarabel_Gamma" => Gcm, "clarabel_Gamma_solver" => Gcs, "clarabel_Gamma_mu" => bdq.Gamma,
                "clarabel_Gamma_mu_tight" => tight_gamma30(Pc, ops, S, cte.u, cte.nu; rest = rest)[1], "clarabel_old" => bdq.old,
                "clarabel_t_full" => cfu.seconds, "clarabel_t_team" => cte.seconds,
                "clarabel_mu_diff" => norm(cte.mu - mu) / max(norm(mu), 1e-300),
                "clarabel_Gamma_rel_diff" => abs(Gcm - Gmin) / max(abs(Gmin), 1e-300),
                "clarabel_u_diff_team" => norm(cte.u - z, Inf), "clarabel_u_diff_full" => norm(cfu.u - uf, Inf)))
            @printf("  clarabel: J full %.10g (%s, pkg %.10g), J team %.10g (%s, pkg %.10g), Gamma %.6e (ours %.6e), mu form %.6e (ours %.6e), %.1f + %.1f s\n",
                    cfu.J, cfu.status, fine.J, cte.J, cte.status, red.J, Gcm, Gmin, bdq.Gamma, bd.Gamma, cfu.seconds, cte.seconds)
        end
        push!(recs, rec)
        J = abs(fine.J)
        @printf("  step %2d: gamma/J %.3e lower/J %.3e Gamma/J %.3e (solver duals %.3e, mu %.3e, mu tight %.3e) old/J %.3e | Gamma/gamma %.4f | active %d/%d | full %.2fs team %.2fs Gamma %.1f ms (res %.1e)\n",
                k, gam / J, lo / J, Gmin / J, Gsol / J, bd.Gamma / J, Gt / J, bd.old / J, Gmin / gam, naf, nat, tf, tr, 1e3 * rec["t_gamma_online"], res)
        flush(stdout)
        k == steps && break
        u, _ = clip27(sc, first_inputs27(pp, xl))
        x = plant27(sc, x, u, k)
    end
    return Dict{String,Any}("experiment" => "E30-fleet-part", "side" => side, "n" => sc.n, "sigma" => sigma, "seed" => seed,
        "teams" => kind, "nteams" => maximum(teams), "merged_rows" => length(S), "rank_deficiency" => sum(length(op.rows) - op.rank for op in ops),
        "steps" => recs, "offline" => off, "infeasible_steps" => infeasible, "H" => sc.H, "h" => sc.h,
        "meta" => meta27(), "loadavg" => loadavg27())
end

function fleet30()
    println("E30 fleet: side $SIDE30 (n = $(SIDE30^2)), sigmas $SIGMAS30, seeds $SEEDS30, teams $KINDS30, steps $CL_STEPS30, clarabel $CLARABEL30")
    t = @elapsed for kind in KINDS30                                    # compile on a 4 x 4 fleet (discarded)
        fleet_run30(4, 0.1, 1, kind; steps = 1, clar = CLARABEL30)
    end
    @printf("warm-up %.1f s\n", t); flush(stdout)
    for kind in KINDS30, sigma in SIGMAS30, seed in SEEDS30
        println("teams $kind, sigma $sigma, seed $seed"); flush(stdout)
        part = fleet_run30(SIDE30, sigma, seed, kind)
        part["tag"] = PARTTAG30
        write27(joinpath(PARTDIR30, "e30_fleet_n$(SIDE30^2)_$(kind)_sig$(sigtag27(sigma))_seed$(seed)$(PARTTAG30).json"), part)
    end
end

# ---------------------------------------------------------------------------
# Part B: the closed loop of incoherent teams (regulation, terminal equality)
# ---------------------------------------------------------------------------
#
# An s x s grid of quadrotors (3D double integrators, h = 0.2) whose rows are
# the teams, and whose airframes ALTERNATE ALONG EVERY ROW (light: no drag,
# ||u|| <= UMAX_L30; heavy: linear drag 0.4, ||u|| <= UMAX_H30): the members of
# a team have different dynamics, so no row is coherent and Thm. thm:equitable
# does not apply. Every vehicle regulates to its slot in a hover formation,
# x_s = (slot, 0), u_s = 0 (an equilibrium of both airframes; every formation
# edge, target the slot difference, holds at x_s, so x_s is team feasible).
# Stage cost l(x, u) = 1/2||x - x_s||^2_Q + 1/2 u'Ru + sum over every grid edge
# of 1/2||C x_j - C x_i - o_ij||^2 (positive definite in x - x_s), horizon H,
# terminal equality x_H = x_s; the MPC objective is sum_{t<H} l(x_t, u_t)
# exactly. Coordinated MPC: the full program; team MPC: the formation edges
# inside every row hard from instant 1 on. The start: every row displaced from
# its slots by its own rigid offset (position and velocity, seeded), so each row
# is in formation at t = 0 (team feasible) and the rows are not.
#
# Recorded per seed and size: the team program's status at every step
# (recursive feasibility), ||x_k - x_s|| (convergence), the closed-loop costs of
# team and coordinated MPC over BENCH_CL_STEPS steps (and the tail bound: the
# value of the last state, which bounds the rest), V(x0), V_T(x0) = V(x0) +
# gamma(x0), Gamma(x0), and the per-step decrease V_T(x_{k+1}) <= V_T(x_k) -
# l(x_k, u_k), and (J_cl_team - J_cl_coord)/gamma(x0). Both programs are solved
# by Clarabel (condensed, tolerance 1e-8), with the linearly dependent equality
# rows of each team (its formation rows and its members' terminal rows overlap
# when the airframes differ) dropped once by a pivoted QR: the rows are
# structural, so the feasible set is unchanged (with them Clarabel stalls near
# x_s). Coordinated MPC carries the same terminal equality. Gamma(x0) is the
# certificate with H restricted to the directions that keep every agent's
# terminal equality (Z (Z'HZ)^{-1} Z', Z = blkdiag of the null spaces of the
# terminal rows: the terminal multipliers eliminated); Gamma0_plain is the
# same without the restriction (terminal multipliers 0), Gamma0_mu the mu form.

const UMAX_L30 = parse(Float64, get(ENV, "BENCH_UMAX_LIGHT", "4.0"))
const UMAX_H30 = parse(Float64, get(ENV, "BENCH_UMAX_HEAVY", "1.0"))
const HB30 = parse(Int, get(ENV, "BENCH_H", "15"))

function regfleet30(side::Int; H::Int = HB30, h::Float64 = 0.2)
    n = side^2
    edges, sl = SM.grid_graph(side, side)
    slots = [[s; 1.5] for s in sl]
    I3 = Matrix(1.0I, 3, 3); C = [I3 zeros(3, 3)]
    Q = Matrix(Diagonal([1.0, 1, 1, 0.5, 0.5, 0.5]))
    heavy(i) = iseven(rem(i - 1, side) + 1)                       # alternate along every row
    function ag(i)
        d = heavy(i) ? 0.4 : 0.0
        A, B = dyn27(h, d)
        CAgent(A, B, zeros(6), C, Matrix(1.0I, 6, 6), Q, (heavy(i) ? 0.2 : 0.1) * I3, zeros(6, 6), heavy(i) ? UMAX_H30 : UMAX_L30)
    end
    ags = [ag(i) for i in 1:n]
    spec = CSpec(H, collect(0:(H-1)), collect(0:(H-1)), :equality)
    W = [[Matrix(1.0I, 3, 3) for _ in spec.form] for _ in edges]
    o = [[slots[j] - slots[i] for _ in spec.form] for (i, j) in edges]
    cf = CFleet(ags, spec, edges, W, o)
    xs = [[slots[i]; zeros(3)] for i in 1:n]
    teams = [div(i - 1, side) + 1 for i in 1:n]
    return cf, xs, teams, [heavy(i) for i in 1:n]
end

function regstart30(side::Int, xs, seed::Int)
    rng = Xoshiro(30_303 * seed + side)
    off = [(dp = 0.4 * randn(rng, 3), dv = 0.3 * randn(rng, 3)) for _ in 1:side]
    return [xs[i] + [off[div(i - 1, side) + 1].dp; off[div(i - 1, side) + 1].dv] for i in eachindex(xs)]
end

regdata30(cf::CFleet, xs, x) = CData(x, [repeat(xs[i], 1, cf.spec.H + 1) for i in eachindex(xs)], [copy(v) for v in xs])

"""Stage cost l(x, u) of Part B (every edge)."""
function regstage30(cf::CFleet, xs, x, u)
    c = 0.0
    for (i, ag) in enumerate(cf.agents)
        e = x[i] - xs[i]; c += 0.5 * dot(e, ag.Q * e) + 0.5 * dot(u[i], ag.R * u[i])
    end
    for (k, (i, j)) in enumerate(cf.edges)
        d = cf.agents[j].C * x[j] - cf.agents[i].C * x[i] - cf.o[k][1]
        c += 0.5 * dot(d, cf.W[k][1] * d)
    end
    return c
end

function regplant30(cf::CFleet, x, u)
    return [ag.A * x[i] + ag.B * u[i] + ag.g for (i, ag) in enumerate(cf.agents)]
end

"""
The stated bound (H0^{-1}, not restricted) at its best over the split of the
forces between mu and the terminal duals: mu + delta with A_T' delta in
range(E_T'), i.e. delta in null(Z_T' A_T') (Z_T: the members' null spaces of
their terminal rows); a quadratic in delta, closed form, per team.
"""
function gamma_plain_best30(P::CProg, ops_plain::Vector{TeamOp}, mu)
    cf = P.cf; tot = 0.0
    for op in ops_plain
        Zs = [nullspace(cf.Theta[i][end]) for i in op.members]
        ZT = cat(Zs...; dims = (1, 2))
        X = ZT' * Matrix(op.At)
        Y = nullspace(X; atol = 1e-8 * max(opnorm(X), 1.0))
        m = mu[op.srows]
        if size(Y, 2) > 0
            a = pinv(Symmetric(Y' * op.M * Y)) * (Y' * op.M * m)
            m = m - Y * a
        end
        tot += 0.5 * dot(m, op.M * m)
    end
    return tot
end

function closedloop_run30(side::Int, seed::Int; steps::Int = CL_STEPS30)
    cf, xs, teams, heavy = regfleet30(side)
    x0 = regstart30(side, xs, seed)
    P0 = CProg(cf, regdata30(cf, xs, x0)); S = srows30(P0, teams)
    t_ops = @elapsed begin
        ops_r = teamops30(P0, teams, S; restrict = true)
        ops_p = teamops30(P0, teams, S; restrict = false)
        cops_r = certops30(P0, teams, S; restrict = true)
        cops_p = certops30(P0, teams, S; restrict = false)
        rest = RestOp(P0, S)
    end
    out = Dict{String,Any}("experiment" => "E30-closedloop-part", "side" => side, "n" => side^2, "seed" => seed, "H" => cf.spec.H,
        "umax_light" => UMAX_L30, "umax_heavy" => UMAX_H30, "merged_rows" => length(S), "t_operators" => t_ops)
    # step 0: V, V_T, gamma, Gamma
    kp = eqkeep30(P0, teams, S); kf = eqkeep30(P0, teams, Int[])
    out["eq_rows_team"] = length(S) + size(P0.E, 1); out["eq_rows_team_kept"] = length(kp)
    fu = clarabel30(P0, Int[]; keep = kf); te = clarabel30(P0, S; keep = kp)
    out["status0_full"] = fu.status; out["status0_team"] = te.status
    if !(fu.status == "SOLVED" && te.status == "SOLVED")
        @printf("side %d seed %d: step 0 full %s team %s\n", side, seed, fu.status, te.status)
        return out
    end
    bdr = bounds_from_mu30(ops_r, te.mu); bdp = bounds_from_mu30(ops_p, te.mu)
    Gsol, Gmin, _, _ = cert30(P0, cops_r, te.u, te.nu; rest = rest)
    _, Gplain, _, _ = cert30(P0, cops_p, te.u, te.nu; rest = rest)
    merge!(out, Dict{String,Any}("V0" => fu.J, "VT0" => te.J, "gamma0" => te.J - fu.J, "Gamma0" => Gmin, "Gamma0_solver" => Gsol,
        "Gamma0_plain" => Gplain, "Gamma0_mu" => bdr.Gamma, "Gamma0_mu_plain" => bdp.Gamma,
        "Gamma0_mu_plain_best" => gamma_plain_best30(P0, ops_p, te.mu), "old0" => bdr.old, "lower0" => lower30(P0, S, fu.u)))
    # the two closed loops
    for (name, hard) in (("team", true), ("coordinated", false))
        x = deepcopy(x0); cost = 0.0; recs = Dict{String,Any}[]; infeas = 0
        for k in 0:(steps-1)
            P = CProg(P0, regdata30(cf, xs, x))
            r = clarabel30(P, hard ? S : Int[]; keep = hard ? kp : kf)
            if r.status != "SOLVED"
                infeas += 1
                push!(recs, Dict{String,Any}("step" => k, "status" => r.status)); break
            end
            u = [r.u[uidx(cf, i, 0)] for i in 1:nagents(cf)]
            l = regstage30(cf, xs, x, u)
            rec = Dict{String,Any}("step" => k, "status" => r.status, "V" => r.J, "stage" => l,
                                   "dist" => sqrt(sum(norm(x[i] - xs[i])^2 for i in eachindex(x))),
                                   "max_ball_ratio" => maximum(norm(u[i]) / cf.agents[i].umax for i in eachindex(u)),
                                   "seconds" => r.seconds)
            if hard && k <= 10                                     # the certificate along the loop (first steps)
                fk = clarabel30(P, Int[]; keep = kf)
                if fk.status == "SOLVED"
                    rec["gamma"] = r.J - fk.J; rec["Gamma"] = cert30(P, cops_r, r.u, r.nu; rest = rest)[2]
                    rec["Gamma_mu"] = bounds_from_mu30(ops_r, r.mu).Gamma
                end
            end
            push!(recs, rec)
            cost += l
            x = regplant30(cf, x, u)
        end
        Pend = CProg(P0, regdata30(cf, xs, x))
        rend = clarabel30(Pend, hard ? S : Int[]; keep = hard ? kp : kf)
        dec = [recs[k]["V"] - recs[k+1]["V"] - recs[k]["stage"] for k in 1:(length(recs)-1) if haskey(recs[k+1], "V")]
        out[name] = Dict{String,Any}("closed_loop_cost" => cost, "steps" => recs, "infeasible_steps" => infeas,
            "final_dist" => sqrt(sum(norm(x[i] - xs[i])^2 for i in eachindex(x))),
            "tail_value" => rend.status == "SOLVED" ? rend.J : NaN,          # the program's value at the last state bounds the rest
            "min_decrease_slack" => isempty(dec) ? NaN : minimum(dec))
        @printf("side %d seed %d %-11s: cost %.8g (+ tail %.2e) final |x - xs| %.2e infeasible %d, min slack of V decrease %.2e\n",
                side, seed, name, cost, out[name]["tail_value"], out[name]["final_dist"], infeas, out[name]["min_decrease_slack"])
    end
    out["excess_over_gamma"] = (out["team"]["closed_loop_cost"] + out["team"]["tail_value"] - out["coordinated"]["closed_loop_cost"] -
                                out["coordinated"]["tail_value"]) / out["gamma0"]
    @printf("side %d seed %d: V(x0) %.8g  V_T(x0) %.8g  gamma %.6g  Gamma %.6g (solver duals %.6g, unrestricted %.6g, mu %.6g)  team cost %.8g  coordinated cost %.8g  (J_team - J_coord)/gamma %.4f\n",
            side, seed, out["V0"], out["VT0"], out["gamma0"], out["Gamma0"], out["Gamma0_solver"], out["Gamma0_plain"], out["Gamma0_mu"],
            out["team"]["closed_loop_cost"], out["coordinated"]["closed_loop_cost"], out["excess_over_gamma"])
    flush(stdout)
    return out
end

function closedloop30()
    for side in parse.(Int, split(get(ENV, "BENCH_SIDES", string(SIDE30)), ",")), seed in SEEDS30
        part = closedloop_run30(side, seed)
        part["meta"] = meta27()
        write27(joinpath(PARTDIR30, "e30_cl_n$(side^2)_seed$(seed).json"), part)
    end
end

# ---------------------------------------------------------------------------
# Merge: parts -> results/e30_bounds.json, results/e30_closed_loop.json, figures/data/bounds_new.dat
# ---------------------------------------------------------------------------

const VTOL30 = 1e-7          # a bound holds when it is >= the bounded quantity - VTOL30 max(1, |J*|) (solves to 1e-8)
const RATIO_FLOOR30 = 1e-6   # ratios to gamma only where gamma/|J*| >= this (sigma = 0: gamma is solver noise)
const SIZEWORD30 = Dict(16 => "Sixteen", 64 => "SixtyFour", 256 => "TwoFiftySix", 1024 => "OneK")
const SIGWORD30 = Dict(0.0 => "SigZero", 0.01 => "SigA", 0.03 => "SigB", 0.1 => "SigC", 0.3 => "SigD", 1.0 => "SigE")

fn30(x) = x isa AbstractString ? parse(Float64, x) : Float64(x)
stats30(v) = isempty(v) ? Dict{String,Any}("n" => 0) :
    Dict{String,Any}("n" => length(v), "median" => median(v), "min" => minimum(v), "max" => maximum(v), "mean" => mean(v))

function merge30()
    parts = readdir(PARTDIR30; join = true)
    N = Dict{String,Any}(); NM = Dict{String,Any}()
    num!(k, v, fmt, meaning) = (N[k] = v; NM[k] = [fmt, meaning])
    out = Dict{String,Any}("experiment" => "E30-bounds", "vtol" => VTOL30, "ratio_floor" => RATIO_FLOOR30)
    viol = Dict{String,Any}[]
    holds(b, a, J) = b >= a - VTOL30 * max(1.0, abs(J))
    # (a) random instances
    rf = joinpath(PARTDIR30, "e30_random.json")
    if isfile(rf)
        R = JSON.parsefile(rf); I = [x for x in R["instances"] if haskey(x, "gamma")]
        for x in I, k in ("Gamma", "Gamma_solver", "Gamma_mu", "Gamma_mu_recovered", "Gamma_mu_tight", "old")
            holds(fn30(x[k]), fn30(x["gamma"]), fn30(x["J_full"])) || push!(viol, Dict("where" => "random $(x["instance"])", "what" => "$k >= gamma"))
        end
        for x in I
            holds(fn30(x["gamma"]), fn30(x["lower"]), fn30(x["J_full"])) || push!(viol, Dict("where" => "random $(x["instance"])", "what" => "gamma >= lower"))
        end
        act = [x for x in I if x["active_full"] + x["active_team"] > 0]; ina = [x for x in I if x["active_full"] + x["active_team"] == 0]
        ratr(L, k) = [fn30(x[k]) / fn30(x["gamma"]) for x in L if fn30(x["gamma"]) >= RATIO_FLOOR30 * max(1.0, abs(fn30(x["J_full"])))]
        out["random"] = Dict{String,Any}("instances" => I, "draws" => length(R["instances"]), "solved" => length(I),
            "team_infeasible_draws" => count(x -> get(x, "status_team", "") != "SOLVED", R["instances"]),
            "active" => length(act), "inactive" => length(ina), "rank_deficient" => count(x -> x["rank_deficiency"] > 0, I),
            "ratio_active" => stats30(ratr(act, "Gamma")), "ratio_inactive" => stats30(ratr(ina, "Gamma")),
            "solver_ratio_active" => stats30(ratr(act, "Gamma_solver")), "mu_tight_ratio_active" => stats30(ratr(act, "Gamma_mu_tight")),
            "lower_ratio" => stats30(ratr(I, "lower")),
            "old_ratio" => stats30(ratr(I, "old")),
            "exact_hessian_rel_err_inactive" => maximum(abs(fn30(x["Gamma_exact_hessian"]) - fn30(x["gamma"])) / max(abs(fn30(x["gamma"])), 1e-12) for x in ina),
            "recovered_rel_diff_max" => maximum(abs(fn30(x["Gamma_mu_recovered"]) - fn30(x["Gamma_mu"])) / max(fn30(x["Gamma_mu"]), 1e-300) for x in I),
            "recovery_residual_max" => maximum(fn30(x["recovery_residual"]) for x in I), "tol" => R["tol"])
        rr = out["random"]
        num!("RandSolved", rr["solved"], "fint", "random instances with both programs solved")
        num!("RandActive", rr["active"], "fint", "of them with an input ball active at an optimum")
        num!("RandRankDef", rr["rank_deficient"], "fint", "of them with rank-deficient A_S (a cycle inside a team)")
        num!("RandInactiveMed", rr["ratio_inactive"]["median"], "fratio", "Gamma/gamma, no active ball, median")
        num!("RandInactiveMax", rr["ratio_inactive"]["max"], "fsig", "Gamma/gamma, no active ball, max")
        num!("RandActiveMed", rr["ratio_active"]["median"], "fsig", "Gamma/gamma, active balls, median")
        num!("RandActiveMax", rr["ratio_active"]["max"], "fsig", "Gamma/gamma, active balls, max")
        num!("RandSolverActiveMed", rr["solver_ratio_active"]["median"], "fsig", "Gamma(g) with the solver's cone duals over gamma, active balls, median")
        num!("RandSolverActiveMax", rr["solver_ratio_active"]["max"], "fsci", "the same, max")
        num!("RandOldMed", rr["old_ratio"]["median"], "fsci", "old bound (1/2)mu'W^{-1}mu over gamma, median")
        num!("RandLowerMed", rr["lower_ratio"]["median"], "fsig", "lower bound over gamma, median")
        num!("RandExactErr", rr["exact_hessian_rel_err_inactive"], "fsci", "|Gamma with the exact Hessian - gamma|/gamma, no active ball, max")
        num!("RandInfeasibleDraws", rr["team_infeasible_draws"], "fint", "random draws discarded: team program infeasible")
    end
    # (b-d) the fleet
    allf = [JSON.parsefile(p) for p in parts if occursin("e30_fleet_", basename(p))]
    fparts = [p for p in allf if isempty(get(p, "tag", ""))]                  # the closed-loop parts (one per seed)
    cparts = [p for p in allf if !isempty(get(p, "tag", ""))]                 # step-0-only parts (Clarabel at n = 1024)
    settings = Dict{String,Any}(); figrows = []; records = Dict{String,Any}[]
    for kind in sort(unique(String(p["teams"]) for p in fparts)), n in sort(unique(Int(p["n"]) for p in fparts)),
        sigma in sort(unique(fn30(p["sigma"]) for p in fparts))
        P = [p for p in fparts if p["teams"] == kind && p["n"] == n && fn30(p["sigma"]) == sigma]
        isempty(P) && continue
        Pc = [p for p in cparts if p["teams"] == kind && p["n"] == n && fn30(p["sigma"]) == sigma]
        sort!(P; by = p -> p["seed"])
        tag = "n$(n)_$(kind)_sig$(sigtag27(sigma))"
        S0 = [p["steps"][1] for p in P if haskey(p["steps"][1], "gamma")]
        allst = [st for p in P for st in p["steps"] if haskey(st, "gamma")]
        for p in [P; Pc], st in p["steps"]
            haskey(st, "gamma") || continue
            J = fn30(st["J_full"]); g = fn30(st["gamma"])
            push!(records, Dict{String,Any}("n" => n, "teams" => kind, "sigma" => sigma, "seed" => p["seed"], "tag" => get(p, "tag", ""),
                (k => st[k] for k in ("step", "J_full", "J_team", "gamma", "lower", "Gamma", "Gamma_qp", "Gamma_solver", "Gamma_mu", "Gamma_mu_tight",
                                      "Gamma_mu_certifier", "old", "old_certifier", "clarabel_Gamma", "clarabel_Gamma_solver",
                                      "clarabel_Gamma_mu", "clarabel_Gamma_mu_tight", "clarabel_gamma", "recovery_residual",
                                      "tight_residual", "active_team") if haskey(st, k))...))
            for k in ("Gamma", "Gamma_solver", "Gamma_mu", "Gamma_mu_tight", "Gamma_mu_certifier", "old", "old_certifier", "clarabel_Gamma",
                      "clarabel_Gamma_solver", "clarabel_Gamma_mu", "clarabel_Gamma_mu_tight")
                haskey(st, k) || continue
                holds(fn30(st[k]), g, J) || push!(viol, Dict("where" => "$tag seed $(p["seed"]) step $(st["step"])", "what" => "$k >= gamma"))
            end
            holds(g, fn30(st["lower"]), J) || push!(viol, Dict("where" => "$tag seed $(p["seed"]) step $(st["step"])", "what" => "gamma >= lower"))
        end
        rel(L, k) = [fn30(st[k]) / abs(fn30(st["J_full"])) for st in L]
        rat(L, k) = [fn30(st[k]) / fn30(st["gamma"]) for st in L if fn30(st["gamma"]) >= RATIO_FLOOR30 * abs(fn30(st["J_full"]))]
        D = Dict{String,Any}("n" => n, "teams" => kind, "sigma" => sigma, "seeds" => [p["seed"] for p in P],
            "steps_recorded" => length(allst), "infeasible_steps" => sum(p["infeasible_steps"] for p in P),
            "rank_deficiency" => P[1]["rank_deficiency"], "merged_rows" => P[1]["merged_rows"],
            "step0" => Dict{String,Any}("gamma_rel" => stats30(rel(S0, "gamma")), "lower_rel" => stats30(rel(S0, "lower")),
                "Gamma_rel" => stats30(rel(S0, "Gamma")), "Gamma_solver_rel" => stats30(rel(S0, "Gamma_solver")),
                "Gamma_mu_rel" => stats30(rel(S0, "Gamma_mu")), "Gamma_mu_tight_rel" => stats30(rel(S0, "Gamma_mu_tight")),
                "old_rel" => stats30(rel(S0, "old")), "Gamma_over_gamma" => stats30(rat(S0, "Gamma")),
                "solver_over_gamma" => stats30(rat(S0, "Gamma_solver")), "mu_tight_over_gamma" => stats30(rat(S0, "Gamma_mu_tight")),
                "lower_over_gamma" => stats30(rat(S0, "lower")),
                "old_over_gamma" => stats30(rat(S0, "old")), "active_team" => stats30([fn30(st["active_team"]) for st in S0]),
                "t_full" => stats30([fn30(st["t_full"]) for st in S0]), "t_team" => stats30([fn30(st["t_team"]) for st in S0]),
                "t_gamma_online" => stats30([fn30(st["t_gamma_online"]) for st in S0]),
                "t_gamma_mu" => stats30([fn30(st["t_gamma_mu"]) for st in S0]),
                "recovery_residual" => stats30([fn30(st["recovery_residual"]) for st in S0]),
                "mu_diff_certifier" => stats30([fn30(st["mu_diff_certifier"]) for st in S0])),
            "loop" => Dict{String,Any}("Gamma_over_gamma" => stats30(rat(allst, "Gamma")), "solver_over_gamma" => stats30(rat(allst, "Gamma_solver")),
                "lower_over_gamma" => stats30(rat(allst, "lower")), "old_over_gamma" => stats30(rat(allst, "old")),
                "Gamma_rel" => stats30(rel(allst, "Gamma")), "Gamma_solver_rel" => stats30(rel(allst, "Gamma_solver")),
                "gamma_rel" => stats30(rel(allst, "gamma")),
                "t_full" => stats30([fn30(st["t_full"]) for st in allst if st["step"] > 0]),
                "t_team" => stats30([fn30(st["t_team"]) for st in allst if st["step"] > 0]),
                "t_gamma_online" => stats30([fn30(st["t_gamma_online"]) for st in allst if st["step"] > 0]),
                "t_gamma_mu" => stats30([fn30(st["t_gamma_mu"]) for st in allst if st["step"] > 0]),
                "recovery_residual_max" => maximum(fn30(st["recovery_residual"]) for st in allst),
                "tight_residual_max" => maximum(fn30(get(st, "tight_residual", 0.0)) for st in allst)),
            "offline" => Dict{String,Any}(k => stats30([fn30(p["offline"][k]) for p in P]) for k in keys(P[1]["offline"])),
            "per_seed_step0" => [Dict{String,Any}(k => st[k] for k in keys(st)) for st in S0])
        C = [st for st in [S0; [p["steps"][1] for p in Pc if haskey(p["steps"][1], "gamma")]] if haskey(st, "clarabel_Gamma")]
        Cg = [st for st in C if fn30(st["gamma"]) >= RATIO_FLOOR30 * abs(fn30(st["J_full"]))]     # relative differences only where gamma > 0
        if !isempty(C)
            D["clarabel"] = Dict{String,Any}("count" => length(C), "count_positive_gap" => length(Cg),
                "mu_diff" => stats30([fn30(st["clarabel_mu_diff"]) for st in Cg]),
                "Gamma_rel_diff" => stats30([fn30(st["clarabel_Gamma_rel_diff"]) for st in Cg]),
                "Gamma_mu_rel_diff" => stats30([abs(fn30(st["clarabel_Gamma_mu"]) - fn30(st["Gamma_mu"])) / fn30(st["Gamma_mu"]) for st in Cg]),
                "J_full_rel_diff" => stats30([abs(fn30(st["clarabel_J_full"]) - fn30(st["J_full"])) / abs(fn30(st["J_full"])) for st in C]),
                "J_team_rel_diff" => stats30([abs(fn30(st["clarabel_J_team"]) - fn30(st["J_team"])) / abs(fn30(st["J_full"])) for st in C]),
                "Gamma_over_gamma" => stats30(rat(C, "clarabel_Gamma")), "t_full" => stats30([fn30(st["clarabel_t_full"]) for st in C]),
                "t_team" => stats30([fn30(st["clarabel_t_team"]) for st in C]),
                "Gamma_rel" => stats30(rel(C, "clarabel_Gamma")), "Gamma_mu_rel" => stats30(rel(C, "clarabel_Gamma_mu")))
        end
        haskey(settings, tag) ? merge!(settings[tag], D) : (settings[tag] = D)
        if kind == "rows" && n == 1024 && !isempty(S0)
            push!(figrows, (sigma, D["step0"], D))
        end
    end
    out["fleet"] = settings
    out["records"] = records
    # numbers of the fleet
    for (tag, D) in settings
        haskey(SIZEWORD30, D["n"]) && haskey(SIGWORD30, D["sigma"]) || continue
        w = SIZEWORD30[D["n"]] * (D["teams"] == "rows" ? "" : "Blocks") * SIGWORD30[D["sigma"]]
        s0 = D["step0"]; lp = D["loop"]
        if D["sigma"] == 0 && D["teams"] == "rows"
            num!(w * "GammaRelMax", s0["Gamma_rel"]["max"], "fsci", "Gamma/J* at step 0 (minimum over the normal cone), coherent rows, max over seeds ($tag)")
            num!(w * "SolverRelMax", s0["Gamma_solver_rel"]["max"], "fsci", "Gamma(g)/J* with the team solve's cone duals (a merged dual split evenly), step 0, coherent rows, max ($tag)")
            num!(w * "LoopGammaRelMax", lp["Gamma_rel"]["max"], "fsci", "Gamma/J* over the closed loop, coherent rows, max ($tag)")
            num!(w * "LoopSolverRelMax", lp["Gamma_solver_rel"]["max"], "fsci", "the same with the solver's cone duals, max ($tag)")
            num!(w * "OldRelMed", s0["old_rel"]["median"], "fsig", "old bound over J* at step 0, coherent rows, median ($tag)")
            num!(w * "GapAbsMax", maximum(abs.(fn30.(x["gamma"] for x in D["per_seed_step0"])) ./ abs.(fn30.(x["J_full"] for x in D["per_seed_step0"]))), "fsci", "|gamma|/J* at step 0, coherent rows ($tag)")
            continue
        end
        s0["Gamma_over_gamma"]["n"] > 0 || continue
        num!(w * "RatioMed", s0["Gamma_over_gamma"]["median"], "fratio", "Gamma/gamma at step 0, median over seeds ($tag)")
        num!(w * "RatioMax", s0["Gamma_over_gamma"]["max"], "fratio", "Gamma/gamma at step 0, max over seeds ($tag)")
        num!(w * "SolverMed", s0["solver_over_gamma"]["median"], "fratio", "Gamma(g) with the solver's cone duals over gamma at step 0, median ($tag)")
        num!(w * "LowerMed", s0["lower_over_gamma"]["median"], "fsig", "lower bound/gamma at step 0, median ($tag)")
        num!(w * "OldMed", s0["old_over_gamma"]["median"], "fsci", "old bound/gamma at step 0, median ($tag)")
        num!(w * "GapRelMed", s0["gamma_rel"]["median"], "fsig", "gamma/J* at step 0, median ($tag)")
        num!(w * "LoopRatioMed", lp["Gamma_over_gamma"]["median"], "fratio", "Gamma/gamma over every closed-loop step and seed, median ($tag)")
        num!(w * "LoopRatioMax", lp["Gamma_over_gamma"]["max"], "fratio", "Gamma/gamma over every closed-loop step and seed, max ($tag)")
    end
    for n in (256, 1024), kind in ("rows", "blocks2")
        T = [D for D in values(settings) if D["n"] == n && D["teams"] == kind]
        isempty(T) && continue
        w = SIZEWORD30[n] * (kind == "rows" ? "" : "Blocks")
        tf = median([D["loop"]["t_full"]["median"] for D in T if D["loop"]["t_full"]["n"] > 0])
        tt = median([D["loop"]["t_team"]["median"] for D in T if D["loop"]["t_team"]["n"] > 0])
        tg = median([D["loop"]["t_gamma_online"]["median"] for D in T if D["loop"]["t_gamma_online"]["n"] > 0])
        tq = median([D["loop"]["t_gamma_mu"]["median"] for D in T if D["loop"]["t_gamma_mu"]["n"] > 0])
        to = median([D["offline"]["cert_operators"]["median"] + D["offline"]["condensed_structure"]["median"] + D["offline"]["rest_operator"]["median"] for D in T])
        num!(w * "FullSec", tf, "fsig", "full program solve (TeamMPC, eps 1e-8), s per step, median ($n, $kind)")
        num!(w * "TeamSec", tt, "fsig", "team program solve, s per step, median ($n, $kind)")
        num!(w * "GammaMs", 1e3 * tg, "fsig", "Gamma online from the team plan (data, gradient, one NNLS per team), ms per step, median ($n, $kind)")
        num!(w * "MuMs", 1e3 * tq, "fsig", "the mu form from the recovered forces, ms per step, median ($n, $kind)")
        num!(w * "OfflineSec", to, "fsig", "offline: condensed structure and per-team factorizations, s ($n, $kind)")
        num!(w * "Speedup", tf / tg, "fsig", "full solve time over Gamma's online time ($n, $kind)")
        num!(w * "LoopInfeasible", sum(D["infeasible_steps"] for D in T), "fint", "closed-loop steps with an infeasible team program ($n, $kind)")
    end
    cl = [D["clarabel"] for D in values(settings) if haskey(D, "clarabel") && D["clarabel"]["count_positive_gap"] > 0]
    if !isempty(cl)
        num!("ClarMuDiffMax", maximum(c["mu_diff"]["max"] for c in cl), "fsci", "|mu_Clarabel - mu_recovered|/|mu|, max over every Clarabel run with gamma > 0 (the multipliers are not unique when balls are active)")
        num!("ClarGammaDiffMax", maximum(c["Gamma_rel_diff"]["max"] for c in cl), "fsci", "relative difference of Gamma at Clarabel's and TeamMPC's team plans, max (gamma > 0)")
        num!("ClarMuFormDiffMax", maximum(c["Gamma_mu_rel_diff"]["max"] for c in cl), "fsci", "relative difference of the mu form from the two mu, max (gamma > 0)")
        num!("ClarJDiffMax", maximum(max(c["J_full_rel_diff"]["max"], c["J_team_rel_diff"]["max"]) for c in cl), "fsci", "J* of Clarabel against TeamMPC over |J*|, max")
    end
    qd = [abs(fn30(x["Gamma"]) - fn30(x["Gamma_qp"])) / max(fn30(x["Gamma_qp"]), 1e-300) for x in [records; get(get(out, "random", Dict()), "instances", [])]
          if haskey(x, "Gamma_qp") && fn30(x["gamma"]) >= RATIO_FLOOR30 * max(1.0, abs(fn30(x["J_full"])))]
    isempty(qd) || num!("NnlsQpDiffMax", maximum(qd), "fsci", "|Gamma by Lawson-Hanson - Gamma by Clarabel's QP|/Gamma, max (gamma > 0)")
    out["violations"] = viol
    num!("Violations", length(viol), "fint", "instances or steps where a bound fails (lower <= gamma <= every Gamma)")
    # figure data: rows, n = 1024, sigma > 0, medians (and ranges) over seeds of gamma, lower, Gamma, old over J*
    sort!(figrows; by = first)
    mkpath(joinpath(ROOT27, "figures", "data"))
    open(joinpath(ROOT27, "figures", "data", "bounds_new.dat"), "w") do io
        println(io, "sigma gamma gammalo gammahi lower lowerlo lowerhi Gamma Gammalo Gammahi old oldlo oldhi")
        for (sg, s0, _) in figrows
            sg > 0 || continue
            @printf(io, "%g", sg)
            for k in ("gamma_rel", "lower_rel", "Gamma_rel", "old_rel")
                @printf(io, " %.6e %.6e %.6e", s0[k]["median"], s0[k]["min"], s0[k]["max"])
            end
            println(io)
        end
    end
    # the figure's annotations (figures/fig_bounds_new.tex): the coherent case and the median tightness, rows, n = 1024
    fz = [s0 for (sg, s0, _) in figrows if sg == 0]; fp = [s0 for (sg, s0, _) in figrows if sg > 0]
    fzabs = [maximum(abs(fn30(x["gamma"])) / abs(fn30(x["J_full"])) for x in D["per_seed_step0"]) for (sg, _, D) in figrows if sg == 0]
    texnum(x) = (e = floor(Int, log10(abs(x))); m = round(x / 10.0^e; digits = 0); m >= 10 && (m /= 10; e += 1);
                 "\\ensuremath{$(Int(m))\\times10^{$(e)}}")
    open(joinpath(ROOT27, "figures", "data", "bounds_new.tex"), "w") do io
        println(io, "% GENERATED by scripts/resolution/experiments/e30_bounds.jl (BENCH_MODE=merge) from the E30 parts; rows, n = 1024, step 0.")
        isempty(fz) || println(io, "\\newcommand{\\BnZeroGamma}{", texnum(max(fz[1]["Gamma_rel"]["max"], 1e-300)), "}% largest Gamma/J* at sigma = 0")
        isempty(fz) || println(io, "\\newcommand{\\BnZeroGap}{", texnum(max(fzabs[1], 1e-300)), "}% largest |gamma|/J* at sigma = 0")
        isempty(fp) || @printf(io, "\\newcommand{\\BnRatioMed}{%.2f}%% median over sigma > 0 of the median Gamma/gamma\n", median([x["Gamma_over_gamma"]["median"] for x in fp]))
        isempty(fp) || @printf(io, "\\newcommand{\\BnRatioMax}{%.2f}%% largest Gamma/gamma, sigma > 0\n", maximum([x["Gamma_over_gamma"]["max"] for x in fp]))
        isempty(fp) || println(io, "\\newcommand{\\BnOldMed}{", texnum(median([x["old_over_gamma"]["median"] for x in fp])), "}% median old bound over gamma, sigma > 0")
    end
    out["numbers"] = N; out["number_meta"] = NM
    write27(get(ENV, "BENCH_OUT", joinpath(ROOT27, "results", "e30_bounds.json")), out)
    merge_cl30()
end

function merge_cl30()
    P = [JSON.parsefile(p) for p in readdir(PARTDIR30; join = true) if occursin("e30_cl_", basename(p))]
    isempty(P) && return
    N = Dict{String,Any}(); NM = Dict{String,Any}()
    num!(k, v, fmt, meaning) = (N[k] = v; NM[k] = [fmt, meaning])
    runs = Dict{String,Any}[]; viol = Dict{String,Any}[]
    for p in sort(P; by = p -> (p["n"], p["seed"]))
        haskey(p, "team") || (push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "step 0 not solved")); continue)
        tm, co = p["team"], p["coordinated"]
        J = fn30(p["V0"]); tol = VTOL30 * max(1.0, abs(J))
        ct = fn30(tm["closed_loop_cost"]) + fn30(tm["tail_value"]); cc = fn30(co["closed_loop_cost"]) + fn30(co["tail_value"])
        r = Dict{String,Any}("n" => p["n"], "seed" => p["seed"], "H" => p["H"], "V0" => J, "VT0" => fn30(p["VT0"]),
            "gamma0" => fn30(p["gamma0"]), "Gamma0" => fn30(p["Gamma0"]), "Gamma0_plain" => fn30(p["Gamma0_plain"]),
            "Gamma0_solver" => fn30(p["Gamma0_solver"]), "Gamma0_mu" => fn30(p["Gamma0_mu"]),
            "Gamma0_mu_plain_best" => fn30(p["Gamma0_mu_plain_best"]), "lower0" => fn30(p["lower0"]),
            "excess_over_gamma" => fn30(p["excess_over_gamma"]),
            "team_cost" => fn30(tm["closed_loop_cost"]), "team_tail" => fn30(tm["tail_value"]), "coord_cost" => fn30(co["closed_loop_cost"]),
            "coord_tail" => fn30(co["tail_value"]), "team_infeasible" => tm["infeasible_steps"], "coord_infeasible" => co["infeasible_steps"],
            "team_final_dist" => fn30(tm["final_dist"]), "coord_final_dist" => fn30(co["final_dist"]),
            "team_min_decrease_slack" => fn30(tm["min_decrease_slack"]), "coord_min_decrease_slack" => fn30(co["min_decrease_slack"]),
            "steps" => length(tm["steps"]), "start_dist" => fn30(tm["steps"][1]["dist"]),
            "team_over_coord" => ct / cc, "team_over_VT" => ct / fn30(p["VT0"]), "team_over_bound" => ct / (J + fn30(p["Gamma0"])),
            "Gamma_over_gamma" => fn30(p["Gamma0"]) / fn30(p["gamma0"]), "plain_over_gamma" => fn30(p["Gamma0_plain"]) / fn30(p["gamma0"]),
            "mu_plain_best_over_gamma" => fn30(p["Gamma0_mu_plain_best"]) / fn30(p["gamma0"]),
            "solver_over_gamma" => fn30(p["Gamma0_solver"]) / fn30(p["gamma0"]),
            "loop_certificate" => [(st["step"], st["gamma"], st["Gamma"]) for st in tm["steps"] if haskey(st, "gamma")])
        ct <= fn30(p["VT0"]) + tol || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "team cost + tail <= V_T(x0)"))
        cc <= J + tol || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "coordinated cost + tail <= V(x0)"))
        fn30(p["VT0"]) <= J + fn30(p["Gamma0"]) + tol || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "V_T(x0) <= V(x0) + Gamma(x0)"))
        fn30(p["gamma0"]) >= fn30(p["lower0"]) - tol || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "gamma >= lower"))
        fn30(tm["min_decrease_slack"]) >= -tol || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "V_T(x+) <= V_T(x) - l(x, u)"))
        tm["infeasible_steps"] == 0 || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"])", "what" => "team program feasible at every step"))
        for (k, g, G) in r["loop_certificate"]
            fn30(G) >= fn30(g) - tol || push!(viol, Dict("where" => "n $(p["n"]) seed $(p["seed"]) step $k", "what" => "Gamma >= gamma"))
        end
        push!(runs, r)
    end
    for n in sort(unique(r["n"] for r in runs))
        R = [r for r in runs if r["n"] == n]
        w = SIZEWORD30[n]
        num!(w * "Seeds", length(R), "fint", "seeds (n = $n)")
        num!(w * "TeamOverCoordMed", median(r["team_over_coord"] for r in R), "fratio", "team MPC closed-loop cost over coordinated MPC's, median (n = $n)")
        num!(w * "TeamOverCoordMax", maximum(r["team_over_coord"] for r in R), "fratio", "the same, max (n = $n)")
        num!(w * "TeamOverVTMax", maximum(r["team_over_VT"] for r in R), "fratio", "team closed-loop cost over V_T(x0), max (n = $n)")
        num!(w * "TeamOverBoundMed", median(r["team_over_bound"] for r in R), "fratio", "team closed-loop cost over V(x0) + Gamma(x0), median (n = $n)")
        num!(w * "GammaOverGapMed", median(r["Gamma_over_gamma"] for r in R), "fratio", "Gamma(x0)/gamma(x0), terminal-restricted H0, median (n = $n)")
        num!(w * "GammaOverGapMax", maximum(r["Gamma_over_gamma"] for r in R), "fratio", "the same, max (n = $n)")
        num!(w * "PlainOverGapMed", median(r["plain_over_gamma"] for r in R), "fratio", "Gamma(x0) with H not restricted by the terminal equality over gamma(x0), median (n = $n)")
        num!(w * "MuPlainOverGapMed", median(r["mu_plain_best_over_gamma"] for r in R), "fsci", "the mu form with unrestricted H0 (best split of mu and the terminal duals) over gamma(x0), median (n = $n)")
        num!(w * "ExcessOverGapMed", median(r["excess_over_gamma"] for r in R), "fratio", "(team closed-loop cost - coordinated)/gamma(x0), median (n = $n)")
        num!(w * "ExcessOverGapMin", minimum(r["excess_over_gamma"] for r in R), "fratio", "the same, min (n = $n)")
        num!(w * "ExcessOverGapMax", maximum(r["excess_over_gamma"] for r in R), "fratio", "the same, max (n = $n)")
        num!(w * "GapOverVMed", median(r["gamma0"] / r["V0"] for r in R), "fsig", "gamma(x0)/V(x0), median (n = $n)")
        num!(w * "FinalDistMax", maximum(r["team_final_dist"] for r in R), "fsci", "||x_K - x_s|| of team MPC after the last step, max (n = $n)")
    end
    num!("Violations", length(viol), "fint", "Part B: runs or steps where a claimed inequality fails")
    num!("Steps", maximum(r["steps"] for r in runs), "fint", "closed-loop steps of Part B")
    num!("Horizon", runs[1]["H"], "fint", "horizon of Part B (terminal equality)")
    num!("UmaxHeavy", P[1]["umax_heavy"], "fsig", "input bound of the heavy airframe in Part B")
    out = Dict{String,Any}("experiment" => "E30-closed-loop", "runs" => runs, "violations" => viol, "numbers" => N, "number_meta" => NM,
                           "vtol" => VTOL30, "umax_light" => P[1]["umax_light"], "umax_heavy" => P[1]["umax_heavy"])
    write27(get(ENV, "BENCH_OUT_CL", joinpath(ROOT27, "results", "e30_closed_loop.json")), out)
end

if abspath(PROGRAM_FILE) == @__FILE__
    BLAS.set_num_threads(1)
    MODE30 == "probe" && probe30()
    MODE30 == "random" && random30()
    MODE30 == "fleet" && fleet30()
    MODE30 == "closedloop" && closedloop30()
    MODE30 == "merge" && merge30()
end
