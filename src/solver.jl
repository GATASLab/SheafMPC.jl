# solver.jl: ADMM (OSQP's algorithm, generalized to second-order cones) with an
# active-set polish.
#
# On the scaled problem, with per-row penalties rho_i (R = diag(rho)), every
# iteration solves one linear system with the quasi-definite matrix
#
#     [ P + sigma I     A'    ]   [ xt ]   [ sigma x^k - q        ]
#     [ A           -R^{-1}   ] * [ nu ] = [ z^k - R^{-1} y^k     ],
#
# factored once (the factorization changes only when rho does), and then
#
#     zt      = z^k + R^{-1} (nu - y^k)
#     x^{k+1} = alpha xt + (1 - alpha) x^k
#     z^{k+1} = Proj_C(alpha zt + (1 - alpha) z^k + R^{-1} y^k)
#     y^{k+1} = y^k + R (alpha zt + (1 - alpha) z^k - z^{k+1})
#
# (Stellato et al. 2020, Algorithm 1). Proj_C clamps the interval rows and
# projects every translated second-order cone block. The iteration allocates
# nothing.

const ROWT_INEQ = 0x00
const ROWT_EQ = 0x01
const ROWT_FREE = 0x02
const ROWT_SOC = 0x03

# active-set labels
const ACT_NONE = Int8(0)
const ACT_LOWER = Int8(-1)
const ACT_UPPER = Int8(1)
const ACT_EQ = Int8(2)
const ACT_SOC_IN = Int8(3)       # SOC block, inactive
const ACT_SOC_ON = Int8(4)       # SOC block on its boundary (polish not available)

"""
    Solver

A set-up problem: scaled data, the factored KKT system, the polish system,
iterates and workspace. Make one with `setup`, then `solve!`, `update!`,
`warm_start!`.
"""
mutable struct Solver{LS<:LinearSystem}
    settings::Settings
    info::Info
    n::Int
    m::Int
    # scaled data
    P::SpMat
    q::Vector{Float64}
    A::SpMat
    l::Vector{Float64}
    u::Vector{Float64}
    socb::Vector{Float64}
    socs::Vector{UnitRange{Int}}
    kinds::Vector{RowKind}
    rowtype::Vector{UInt8}
    c0::Float64
    scl::Scaling
    Pdiag::Vector{Float64}
    # penalties
    rho::Float64
    rhovec::Vector{Float64}
    rhoinv::Vector{Float64}
    xdiag::Vector{Float64}
    kkt::LS
    pol::LS
    # iterates and workspace
    x::Vector{Float64}
    z::Vector{Float64}
    y::Vector{Float64}
    xprev::Vector{Float64}
    yprev::Vector{Float64}
    w::Vector{Float64}
    rhs::Vector{Float64}
    Ax::Vector{Float64}
    Px::Vector{Float64}
    Aty::Vector{Float64}
    tn::Vector{Float64}
    tm::Vector{Float64}
    # polish
    act::Vector{Int8}
    act_prev::Vector{Int8}
    act_fail::Vector{Int8}
    has_fail::Bool
    pol_act::Vector{Bool}
    pol_valid::Bool
    pdiag::Vector{Float64}
    prhs::Vector{Float64}
    psol::Vector{Float64}
    pres::Vector{Float64}
    px::Vector{Float64}
    py::Vector{Float64}
    pz::Vector{Float64}
    pAx::Vector{Float64}
    pPx::Vector{Float64}
    pAty::Vector{Float64}
    # unscaled solution
    xsol::Vector{Float64}
    ysol::Vector{Float64}
    zsol::Vector{Float64}
    warm_pending::Bool
    has_iterate::Bool
    # second-order cone blocks in the polish: KKT indices of each dense (2,2)
    # block and the boundary parametrization s = tau (1, u), y = eta (1, -u)
    soc_idx::Vector{Matrix{Int}}
    soc_tau::Vector{Float64}
    soc_eta::Vector{Float64}
    soc_u::Vector{Float64}
    warm_fails::Int
    aa::Anderson
    rho0::Float64                 # base rho (spectral estimate or settings.rho)
    lam_min::Float64              # Lanczos estimates of the constraint operator spectrum
    lam_max::Float64
    act_last::Vector{Int8}        # active set of the last accepted polish
    has_last::Bool
    last_fails::Int               # consecutive warm solves whose last-active-set polish failed or was skipped
    # interior-point workspace (ipm.jl, made on first use) and the cost model
    # of the automatic method choice (method.jl)
    ipm::Any
    cost::CostModel
    # the dense active-set path for small polyhedral problems (dual.jl), or nothing
    dual::Any
end

function _rowtypes(l, u, kinds)
    m = length(l)
    rt = Vector{UInt8}(undef, m)
    for i in 1:m
        rt[i] = kinds[i] == ROW_SOC ? ROWT_SOC :
                l[i] == u[i] ? ROWT_EQ :
                (l[i] == -Inf && u[i] == Inf) ? ROWT_FREE : ROWT_INEQ
    end
    return rt
end

function _set_rho!(s::Solver, rho::Float64)
    st = s.settings
    s.rho = rho
    @inbounds for i in 1:s.m
        rt = s.rowtype[i]
        r = rt == ROWT_EQ ? st.rho_eq_scale * rho : rt == ROWT_FREE ? st.rho_min : rho
        s.rhovec[i] = r
        s.rhoinv[i] = 1.0 / r
    end
    return s
end

"Refactor the ADMM KKT matrix for the current `rhovec`."
function _refactor_kkt!(s::Solver)
    set_diagonal!(s.kkt.K, s.kkt.diag_idx, s.xdiag, s.rhoinv)
    refactor!(s.kkt)
    return s
end

"""
    setup(problem::ConicQP; settings = Settings(), kwargs...) -> Solver

Scale the problem, order and factor the KKT matrix, and allocate every
workspace. Keyword arguments override fields of `settings`.
"""
function setup(p::ConicQP; settings::Settings = Settings(), kwargs...)
    st = deepcopy(settings)
    for (k, v) in kwargs
        setproperty!(st, k, v)
    end
    t0 = time_ns()
    n, m = nvars(p), nrows(p)
    P = copy(p.P); q = copy(p.q); A = copy(p.A)
    scl = st.scaling > 0 ? ruiz_scale!(P, q, A, p.socs, st.scaling) : identity_scaling(n, m)
    l = scl.E .* p.l
    u = scl.E .* p.u
    socb = scl.E .* p.socb
    rowtype = _rowtypes(l, u, p.kinds)
    Pdiag = Vector{Float64}(diag(P))
    xdiag = Pdiag .+ st.sigma
    K, diag_idx, soc_idx, upd_idx = kkt_pattern(P, A, p.socs)
    rhovec = zeros(m); rhoinv = zeros(m)
    # rho per row
    for i in 1:m
        rt = rowtype[i]
        r = rt == ROWT_EQ ? st.rho_eq_scale * st.rho : rt == ROWT_FREE ? st.rho_min : st.rho
        rhovec[i] = r; rhoinv[i] = 1 / r
    end
    set_diagonal!(K, diag_idx, xdiag, rhoinv)
    # with the spectral rho, the first numerical factorization is the one the
    # Lanczos steps need (see rho.jl); the ADMM values follow once rho is known
    spectral = st.rho_spectral && any(t -> t == ROWT_INEQ || t == ROWT_SOC, rowtype)
    spectral && set_diagonal!(K, diag_idx, Pdiag .+ st.polish_delta,
                              [t == ROWT_EQ ? st.polish_delta : 1 / st.polish_delta for t in rowtype])
    kind = st.linsys
    kkt = nothing
    if kind == :auto
        # engine and order from BlockLDL's cost model (no trial factorizations)
        kkt = make_system(:model, copy(K), diag_idx, n; upd_idx = upd_idx, settings = st)
        kind = system_kind(kkt)
    elseif kind == :timed
        # time a few backends and orderings on this matrix, keep the fastest solve
        best = Inf
        for (k, o) in ((:qdldl, :amd), (:qdldl, :mmd), (:qdldl, :amf), (:cliquetrees, :default))
            S = make_system(k, copy(K), diag_idx, n; ordering = o == :default ? :amd : o, upd_idx = upd_idx)
            t = time_solves(S, 30)
            if t < best
                best = t; kkt = S; kind = k == :qdldl ? Symbol("qdldl_", o) : k
            end
        end
    else
        kkt = make_system(kind, copy(K), diag_idx, n; ordering = st.ordering, upd_idx = upd_idx, settings = st)
    end
    pol = _polish_system(kkt, copy(K), n)
    s = Solver(st, Info(), n, m, P, q, A, l, u, socb, copy(p.socs), copy(p.kinds), rowtype, p.c, scl, Pdiag,
               st.rho, rhovec, rhoinv, xdiag, kkt, pol,
               zeros(n), zeros(m), zeros(m), zeros(n), zeros(m), zeros(m), zeros(n + m),
               zeros(m), zeros(n), zeros(n), zeros(n), zeros(m),
               fill(ACT_NONE, m), fill(Int8(-99), m), fill(ACT_NONE, m), false, fill(false, m), false,
               zeros(m), zeros(n + m), zeros(n + m), zeros(n + m), zeros(n), zeros(m), zeros(m), zeros(m),
               zeros(n), zeros(n),
               zeros(n), zeros(m), zeros(m), false, false,
               soc_idx, zeros(length(p.socs)), zeros(length(p.socs)), zeros(m), 0,
               Anderson(st.anderson, st.anderson > 0 ? n + m : 0), st.rho, NaN, NaN,
               fill(ACT_NONE, m), false, 0, nothing, CostModel(), nothing)
    # the base rho: from the spectrum of the constraint operator (the ADMM system
    # was factored with the values the estimate needs), or the setting
    if spectral
        r = spectral_rho!(s; S = s.kkt, factored = true)
        r === nothing || (s.rho0 = r)
        _set_rho!(s, s.rho0)
        _refactor_kkt!(s)
    end
    s.info.linsys = kind
    s.dual = _dual_setup!(s)
    _cost_setup!(s)
    s.info.setup_time = (time_ns() - t0) / 1e9
    s.info.rho = s.rho0
    return s
end

# the polish system shares the ordering and the symbolic factorization of the
# ADMM system; it is factored numerically only when the polish first needs it
# (`pol_valid` is false until then)
function _polish_system(S::QDLDLSystem, K::SpMat, n::Int)
    F = deepcopy(S.F)                  # same permuted pattern, elimination tree and factor pattern
    ws = F.workspace
    return QDLDLSystem(K, S.diag_idx, S.upd_idx, F, S.perm, zeros(size(K, 1)), ws.Ln, ws.Lp, ws.Li, ws.Lx, ws.Dinv)
end
function _polish_system(S::ChordalSystem, K::SpMat, n::Int)
    F = Multifrontal.ChordalLDLt(Hermitian(K, :U), S.F.P, S.F.S)
    N = size(K, 1)
    FWs = Multifrontal.FactorizationWorkspace(F)
    DWs = Multifrontal.DivisionWorkspace{Float64}(Multifrontal.symbolic(F), 1)
    return ChordalSystem(K, S.diag_idx, F, S.L, S.Lt, zeros(N), FWs, DWs, copy(S.signs), Vector{Int}(F.perm), zeros(N))
end

# ---------------------------------------------------------------------------
# one ADMM iteration
# ---------------------------------------------------------------------------

function _project!(s::Solver, z::Vector{Float64})
    l = s.l; u = s.u; rt = s.rowtype
    @inbounds for i in 1:s.m
        if rt[i] != ROWT_SOC
            v = z[i]
            z[i] = v < l[i] ? l[i] : (v > u[i] ? u[i] : v)
        end
    end
    @inbounds for B in s.socs
        project_translated_soc!(z, B, s.socb)
    end
    return z
end

function admm_step!(s::Solver)
    n, m = s.n, s.m
    x = s.x; z = s.z; y = s.y; rhs = s.rhs; w = s.w
    q = s.q; rinv = s.rhoinv; rv = s.rhovec
    sig = s.settings.sigma
    a = s.settings.alpha
    a1 = 1.0 - a
    @inbounds for i in 1:n
        rhs[i] = sig * x[i] - q[i]
    end
    @inbounds for i in 1:m
        rhs[n+i] = z[i] - rinv[i] * y[i]
    end
    solve!(s.kkt, rhs)
    @inbounds for i in 1:n
        x[i] = a * rhs[i] + a1 * x[i]
    end
    @inbounds for i in 1:m
        zt = z[i] + rinv[i] * (rhs[n+i] - y[i])
        zr = a * zt + a1 * z[i]
        w[i] = zr
        z[i] = zr + rinv[i] * y[i]
    end
    _project!(s, z)
    @inbounds for i in 1:m
        y[i] += rv[i] * (w[i] - z[i])
    end
    return nothing
end

"""
Whether the active-set guess has settled since the last early-polish check: at
most `frac` of the inequality and cone rows changed label (0: none). The
polish corrects a few wrong labels itself (primal-dual active-set steps), so
it need not wait for the slow tail of ADMM's identification.
"""
function _act_settled(s::Solver, frac::Float64)
    frac <= 0 && return s.act == s.act_prev
    nchg = 0; nrows = 0
    @inbounds for i in 1:s.m
        s.rowtype[i] == ROWT_INEQ || s.rowtype[i] == ROWT_SOC || continue
        nrows += 1
        nchg += s.act[i] != s.act_prev[i]
    end
    return nchg <= frac * nrows
end

# ---------------------------------------------------------------------------
# residuals, termination, infeasibility, rho
# ---------------------------------------------------------------------------

"""
Unscaled primal and dual residuals of the scaled point `(x, z, y)` and their
normalizations; fills `Ax`, `Px`, `Aty`.
"""
function _residuals!(s::Solver, x, z, y, Ax, Px, Aty)
    mul!(Ax, s.A, x)
    mul!(Px, s.P, x)
    mul!(Aty, transpose(s.A), y)
    D = s.scl.Dinv; Einv = s.scl.Einv; cinv = s.scl.cinv
    pr = 0.0; nAx = 0.0; nz = 0.0
    @inbounds for i in 1:s.m
        e = Einv[i]
        pr = max(pr, abs(e * (Ax[i] - z[i])))
        nAx = max(nAx, abs(e * Ax[i]))
        nz = max(nz, abs(e * z[i]))
    end
    dr = 0.0; nPx = 0.0; nAty = 0.0; nq = 0.0; nPxq = 0.0
    q = s.q
    @inbounds for j in 1:s.n
        d = D[j]
        g = Px[j] + q[j]
        dr = max(dr, abs(d * (g + Aty[j])))
        nPx = max(nPx, abs(d * Px[j]))
        nAty = max(nAty, abs(d * Aty[j]))
        nq = max(nq, abs(d * q[j]))
        nPxq = max(nPxq, abs(d * g))
    end
    # with the gap test, the dual residual is measured against the gradient
    # P x + q and A'y it balances rather than against P x and q separately
    # (termination.jl: when they are large and cancel, the OSQP normalization
    # admits dual residuals that move the objective by r_d'P^+r_d / 2)
    dn = s.settings.check_gap ? max(nAty, nPxq) : max(nPx, nAty, nq)
    return pr, cinv * dr, max(nAx, nz), cinv * dn
end

@inline _eps_prim(st::Settings, pnorm) = st.eps_abs + st.eps_rel * pnorm
@inline _eps_dual(st::Settings, dnorm) = st.eps_abs + st.eps_rel * dnorm

"Primal infeasibility certificate from `dy = y - yprev` (OSQP Sec. 3.4, with SOC blocks)."
function _primal_infeasible(s::Solver)
    st = s.settings
    m = s.m
    m == 0 && return false
    E = s.scl.E; Einv = s.scl.Einv
    dy = s.tm
    @inbounds for i in 1:m
        v = E[i] * (s.y[i] - s.yprev[i])            # unscaled (up to the cost scale)
        rt = s.rowtype[i]
        if rt != ROWT_SOC
            s.u[i] == Inf && (v = min(v, 0.0))
            s.l[i] == -Inf && (v = max(v, 0.0))
        end
        dy[i] = v
    end
    @inbounds for B in s.socs
        project_soc!(dy, B)
    end
    ndy = norm(dy, Inf)
    ndy < 1e-30 && return false
    supp = 0.0
    @inbounds for i in 1:m
        v = dy[i]
        if s.rowtype[i] == ROWT_SOC
            supp += Einv[i] * s.socb[i] * v
        elseif v > 0
            supp += Einv[i] * s.u[i] * v
        elseif v < 0
            supp += Einv[i] * s.l[i] * v
        end
    end
    supp < -st.eps_prim_inf * ndy || return false
    @inbounds for i in 1:m
        dy[i] *= Einv[i]
    end
    mul!(s.tn, transpose(s.A), dy)
    D = s.scl.Dinv
    r = 0.0
    @inbounds for j in 1:s.n
        r = max(r, abs(D[j] * s.tn[j]))
    end
    return r <= st.eps_prim_inf * ndy
end

"Dual infeasibility certificate from `dx = x - xprev`."
function _dual_infeasible(s::Solver)
    st = s.settings
    n = s.n
    D = s.scl.D; Dinv = s.scl.Dinv; Einv = s.scl.Einv; cinv = s.scl.cinv
    dx = s.tn
    ndx = 0.0
    @inbounds for j in 1:n
        dx[j] = s.x[j] - s.xprev[j]
        ndx = max(ndx, abs(D[j] * dx[j]))
    end
    ndx < 1e-30 && return false
    eps = st.eps_dual_inf * ndx
    cinv * dot(s.q, dx) < -eps || return false
    mul!(s.Px, s.P, dx)
    @inbounds for j in 1:n
        abs(cinv * Dinv[j] * s.Px[j]) <= eps || return false
    end
    mul!(s.tm, s.A, dx)
    @inbounds for i in 1:s.m
        rt = s.rowtype[i]
        rt == ROWT_SOC && continue
        v = Einv[i] * s.tm[i]
        s.u[i] < Inf && v > eps && return false
        s.l[i] > -Inf && v < -eps && return false
    end
    @inbounds for B in s.socs
        for i in B
            s.tm[i] *= Einv[i]
        end
        soc_distance(s.tm, B; sign = -1.0) <= eps || return false
    end
    return true
end

"The tolerance factor of the adaptive rho (`adaptive_rho_tolerance`, or `adaptive_rho_tolerance_soc` with cones)."
_rho_tolerance(s::Solver) = isempty(s.socs) ? s.settings.adaptive_rho_tolerance : s.settings.adaptive_rho_tolerance_soc

function _adapt_rho!(s::Solver, pr, dr, pn, dn)
    st = s.settings
    tol = _rho_tolerance(s)
    est = s.rho * sqrt((pr / (pn + 1e-10)) / (dr / (dn + 1e-10) + 1e-10))
    est = clamp(est, st.rho_min, st.rho_max)
    if est > tol * s.rho || est < s.rho / tol
        _set_rho!(s, est)
        _refactor_kkt!(s)
        s.info.rho_updates += 1
        return true
    end
    return false
end

# ---------------------------------------------------------------------------
# solve
# ---------------------------------------------------------------------------

"""
Iterations by which a crossover at iteration `k` is postponed (0: none): when
the residual merit `m2` (at iteration `k2`; `m1` at `k1` before it) decreases
linearly fast enough that the iterations it still needs to reach 1 cost less
than an IPM solve from scratch, ADMM continues for those iterations. The budget alone
is the deterministic ski-rental rule, which loses up to the budget on every
solve that would have converged just after it; the projection keeps the
solves that are visibly about to converge (an early polish usually ends them
even sooner than the residuals predict).
"""
function _budget_extension(s::Solver, k::Int, m1, k1, m2, k2)
    (isfinite(m1) && isfinite(m2) && k2 > k1 && m2 < m1) || return 0
    m2 <= 1 && return s.settings.check_termination
    rate = log(m1 / m2) / (k2 - k1)                  # log decrease per iteration
    need = log(m2) / rate - (k - k2)
    need = max(need, 1.0)
    c = s.cost
    (isfinite(c.t_ipm) && isfinite(c.t_admm_iter)) || return 0
    need * c.t_admm_iter <= c.t_ipm || return 0
    ct = s.settings.check_termination
    return ct * cld(ceil(Int, need), ct)
end

"""
    _admm_solve!(solver, t0, budget) -> status

Run ADMM from the current iterate (a warm start if `settings.warm_start` and
there is one, zero otherwise), with the polish described in `Settings`, for at
most `budget` iterations: `:budget` when they run out (the caller crosses over
to the interior-point method), otherwise the final status, with the unscaled
solution in `solver.xsol`, `solver.ysol`, `solver.zsol`.
"""
function _admm_solve!(s::Solver, t0::UInt64, budget::Int)
    st = s.settings
    info = s.info
    s.has_fail = false
    fill!(s.act_prev, Int8(-99))
    cold = !(st.warm_start && s.has_iterate)
    if cold
        fill!(s.x, 0.0); fill!(s.z, 0.0); fill!(s.y, 0.0)
        s.warm_pending = false
    end
    converged = false
    polished = false
    status = :max_iter
    tlim = st.time_limit
    dw = st.polish && s.m > 0 ? s.dual::Union{Nothing,DualWork} : nothing
    if dw !== nothing
        dw.xbar_ok = false
        dw.iters = 0; dw.cols = 0
        dw.toobig = false
        dw.accepted = false; dw.tried = false
        dw.spent_solve = 0.0
        # after solves in which the dense path failed, it is tried again only
        # after 4, 8, 16, ... more solves (the sparse polish serves the others)
        dw.fails == 0 || (dw.fails >= 4 && ispow2(dw.fails)) || (dw.toobig = true)
        # new matrix values since the last solve: the sparse paths serve this
        # solve, the next one refactors K11 (dual.jl, `_dual_update_matrices!`)
        if dw.stale == 1
            dw.toobig = true
            dw.stale = 2
        elseif dw.stale == 2
            _dual_refresh!(s, dw)
        end
    end
    warm = !cold && st.polish && st.polish_warm && s.m > 0
    retry = max(st.polish_warm_retry, 1)
    ok = false
    # 1. when the sparse polish found the last accepted solution: its active
    # set, unshifted (in steady tracking it stays put in index space), with the
    # polish factorization still cached, and a few corrections (after a failure
    # only every `polish_warm_retry`-th solve, as a failure costs a factorization)
    if warm && s.has_last && (dw === nothing || !dw.last_dense)
        if st.polish_warm_last >= 0 && (s.last_fails == 0 || s.last_fails % retry == 0)
            copyto!(s.act, s.act_last)
            ok = _try_polish!(s; restart = false, corrections = st.polish_warm_last)
            s.last_fails = ok ? 0 : s.last_fails + 1
        else
            s.last_fails += 1
        end
        st.verbose && @printf("  warm polish (last active set) %s\n", ok ? "accepted" : "rejected")
    end
    # 2. the dense path: warm, from the warm iterate's guess (with a shifted
    # warm start, the shifted active set), then from the last accepted active
    # set unshifted; cold, from the equality-only solution
    if !ok && dw !== nothing && !dw.toobig
        if warm
            # a warm start that is close needs few changes (and its factor is
            # cached): a quarter of the budget each, so that a poor one costs
            # little before the sparse paths
            _guess_active!(s, s.z, s.y)
            ok = _try_dual!(s, :act; frac = 0.25)
            if !ok && !dw.toobig && s.has_last && s.act != s.act_last
                copyto!(s.act, s.act_last)
                ok = _try_dual!(s, :act; frac = 0.25)
            end
            # these attempts stand for the warm polish of the last active set:
            # a failure delays its next sparse attempt in the same way
            s.has_last && dw.last_dense && (s.last_fails = ok ? 0 : s.last_fails + 1)
        end
        cold && !ok && (ok = _try_dual!(s, :xbar; frac = 0.5))
    end
    # 3. the sparse polish of the warm iterate's guess, without the dense path
    # or when it found the active sets too large (every `polish_warm_retry`-th
    # solve after a failure: when the warm start's active set is usually right,
    # as in steady receding horizon, it saves the iterations)
    if !ok && warm && (dw === nothing || dw.toobig) && (s.warm_fails == 0 || s.warm_fails % retry == 0)
        _guess_active!(s, s.z, s.y, st.polish_soc_band)
        ok = _try_polish!(s)
        st.verbose && @printf("  warm polish %s\n", ok ? "accepted" : "rejected")
    end
    if ok
        polished = true; converged = true; status = :solved
    end
    warm && (s.warm_fails = ok ? 0 : s.warm_fails + 1)
    s.warm_pending = false
    k = 0
    pint = st.polish_interval
    wait = 2 * pint
    next_dense = 0
    dwait = st.dual_interval
    next_polish = 0
    next_adapt = st.adaptive_rho_first > 0 ? st.adaptive_rho_first : st.adaptive_rho_interval
    use_aa = st.anderson > 0
    use_aa && reset!(s.aa)
    # residual merits (larger residual over its tolerance) at the last two checks,
    # for the budget extension
    m1 = Inf; k1 = 0; m2 = Inf; k2 = 0
    extended = false
    if !polished
        while k < st.max_iter
            if k >= budget
                ext = extended ? 0 : _budget_extension(s, k, m1, k1, m2, k2)
                if ext > 0
                    budget = k + ext; extended = true
                else
                    # a last polish of the current active-set guess before the
                    # crossover (one factorization against an IPM solve): the
                    # polish ends most ADMM solves well before the residuals do
                    if k > 0 && st.polish && s.m > 0
                        _guess_active!(s, s.z, s.y, st.polish_soc_band)
                        if !(s.has_fail && s.act == s.act_fail) && _try_polish!(s; restart = false)
                            polished = true; converged = true; status = :solved
                            st.verbose && @printf("  it %4d  polish at the budget accepted\n", k)
                            break
                        end
                    end
                    status = :budget; break
                end
            end
            k += 1
            check = k % st.check_termination == 0 || k == st.max_iter || (st.adaptive_rho && k == st.adaptive_rho_first)
            if check
                copyto!(s.xprev, s.x); copyto!(s.yprev, s.y)
            end
            use_aa && _aa_load_point!(s.aa.w, s)
            admm_step!(s)
            use_aa && _aa_update!(s.aa, s; extrapolate = !check, safeguard = st.anderson_safeguard)
            info.iter = k
            if dw !== nothing && !dw.toobig
                # dense attempts seeded from the ADMM guess (no factorization:
                # cheap enough to try often, with a doubling wait after a failure)
                if k % st.dual_interval == 0 && k >= next_dense
                    _guess_active!(s, s.z, s.y)
                    # only a guess that has settled (at most 2% of the rows
                    # changed since the last check) is worth an attempt
                    settled = _act_settled(s, 0.02)
                    copyto!(s.act_prev, s.act)
                    if settled && !(s.has_fail && s.act == s.act_fail)
                        copyto!(s.act_fail, s.act)
                        ok = _try_dual!(s, :act)
                        if ok
                            polished = true; converged = true; status = :solved
                            break
                        end
                        # a guess too large for the dense path may still be right: the
                        # sparse polish takes over without remembering it as failed
                        s.has_fail = !dw.toobig
                        next_dense = k + dwait
                        dwait *= 2
                    end
                end
            elseif st.polish && pint > 0 && k % pint == 0 && s.m > 0 && k >= next_polish
                _guess_active!(s, s.z, s.y, st.polish_soc_band)
                gate_ok = true
                if st.polish_gate > 0
                    gpr, gdr, gpn, gdn = _residuals!(s, s.x, s.z, s.y, s.Ax, s.Px, s.Aty)
                    gate_ok = max(gpr / (gpn + 1e-10), gdr / (gdn + 1e-10)) <= st.polish_gate
                end
                if gate_ok && _act_settled(s, st.polish_settle) && !(s.has_fail && s.act == s.act_fail)
                    ok = _try_polish!(s)
                    use_aa && reset!(s.aa)            # a restart moved the iterate off the orbit
                    st.verbose && @printf("  it %4d  early polish %s (%d attempts so far)\n", k, ok ? "accepted" : "rejected", info.polish_attempts)
                    if ok
                        polished = true; converged = true; status = :solved
                        break
                    end
                    # back off: wait twice as long before the next early attempt
                    next_polish = k + wait
                    wait *= 2
                end
                copyto!(s.act_prev, s.act)
            end
            if check
                pr, dr, pn, dn = _residuals!(s, s.x, s.z, s.y, s.Ax, s.Px, s.Aty)
                info.prim_res = pr; info.dual_res = dr
                m1 = m2; k1 = k2
                m2 = max(pr / _eps_prim(st, pn), dr / _eps_dual(st, dn)); k2 = k
                st.verbose && @printf("  it %4d  prim %.2e (tol %.1e)  dual %.2e (tol %.1e)  rho %.2e\n", k, pr, _eps_prim(st, pn), dr, _eps_dual(st, dn), s.rho)
                if pr <= _eps_prim(st, pn) && dr <= _eps_dual(st, dn) && _gap_ok(s, s.x, s.z, s.y, s.Px) && _violation_ok(s, s.Ax)
                    converged = true; status = :solved
                    break
                end
                if _primal_infeasible(s)
                    status = :primal_infeasible; break
                end
                if _dual_infeasible(s)
                    status = :dual_infeasible; break
                end
                if st.adaptive_rho && k >= next_adapt
                    _adapt_rho!(s, pr, dr, pn, dn) && use_aa && reset!(s.aa)
                    next_adapt = k + st.adaptive_rho_interval
                end
            end
            if tlim < Inf && (time_ns() - t0) / 1e9 > tlim
                status = :time_limit; break
            end
        end
    end
    info.iter = k
    if converged && st.polish && !polished && s.m > 0
        _guess_active!(s, s.z, s.y)
        if dw !== nothing && !dw.toobig
            polished = _try_dual!(s, :act)
            polished || _guess_active!(s, s.z, s.y)
        end
        polished || (polished = _try_polish!(s; restart = false))      # keep the converged ADMM point if rejected
        polished || (info.polish = info.polish == :skipped ? :skipped : :failed)
    end
    s.has_iterate = true
    if info.polish == :success
        copyto!(s.act_last, s.act)
        s.has_last = true
        dw === nothing || (dw.last_dense = dw.accepted)
    end
    dw === nothing || (dw.fails = dw.accepted ? 0 : (dw.tried || dw.fails > 0 ? dw.fails + 1 : 0))
    status == :budget && return status
    _finalize!(s, status)
    return status
end

function _finalize!(s::Solver, status::Symbol)
    info = s.info
    info.status = status
    info.rho = s.rho
    sc = s.scl
    @inbounds for j in 1:s.n
        s.xsol[j] = sc.D[j] * s.x[j]
    end
    @inbounds for i in 1:s.m
        s.ysol[i] = sc.cinv * sc.E[i] * s.y[i]
        s.zsol[i] = sc.Einv[i] * s.z[i]
    end
    if status == :solved || status == :max_iter || status == :time_limit
        mul!(s.Px, s.P, s.x)
        info.obj = sc.cinv * (0.5 * dot(s.x, s.Px) + dot(s.q, s.x)) + s.c0
    elseif status == :primal_infeasible
        info.obj = Inf
    elseif status == :dual_infeasible
        info.obj = -Inf
    end
    if status != :solved || info.polish != :success
        # residuals of the returned point (already exact for an accepted polish)
        pr, dr, _, _ = _residuals!(s, s.x, s.z, s.y, s.Ax, s.Px, s.Aty)
        info.prim_res = pr; info.dual_res = dr
        info.gap = _point_gap(s)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# updates and warm start
# ---------------------------------------------------------------------------

"""
    update!(solver; q = nothing, l = nothing, u = nothing, b = nothing, c = nothing, P = nothing, A = nothing)

New linear cost and/or constraint data (unscaled), keeping the factorization,
and optionally the constant `c` of the objective (it enters the reported
objective and the relative part of the duality gap test, termination.jl; in
receding horizon pass it, or the gap test is relative to the first problem's
constant).
`b` is the right-hand side in the convention of the constructor (`b - A x in
K`): it sets `l = u = b` on equality rows, `u = b` on nonnegative-cone rows and
the shift of every SOC block. A change that turns rows into equality or free
rows (or back) changes their rho and costs one refactorization.

`P` and `A` (unscaled, `P` full symmetric or a triangle, as for `ConicQP`)
replace the values of the matrices on the same sparsity pattern (linear
time-varying or relinearized MPC): the scaling of `setup` is kept, every
factorization is recomputed numerically (no ordering or symbolic work), the
interior-point system is rebuilt on its next use, and the dense active-set
path (dual.jl) refactors its K11 and turns its Z lazy (each column recomputed
when its row next enters an active set).
"""
function update!(s::Solver; q = nothing, l = nothing, u = nothing, b = nothing, c = nothing, P = nothing, A = nothing)
    sc = s.scl
    (P !== nothing || A !== nothing) && _update_matrices!(s, P, A)
    c === nothing || (s.c0 = Float64(c))
    if q !== nothing
        length(q) == s.n || throw(DimensionMismatch("q must have $(s.n) entries"))
        @inbounds for j in 1:s.n
            s.q[j] = sc.c * sc.D[j] * q[j]
        end
    end
    if l !== nothing
        @inbounds for i in 1:s.m
            s.l[i] = sc.E[i] * l[i]
        end
    end
    if u !== nothing
        @inbounds for i in 1:s.m
            s.u[i] = sc.E[i] * u[i]
        end
    end
    if b !== nothing
        length(b) == s.m || throw(DimensionMismatch("b must have $(s.m) entries"))
        @inbounds for i in 1:s.m
            k = s.kinds[i]
            v = sc.E[i] * b[i]
            if k == ROW_EQ
                s.l[i] = v; s.u[i] = v
            elseif k == ROW_LEQ
                s.u[i] = v
            elseif k == ROW_SOC
                s.socb[i] = v
            else
                throw(ArgumentError("row $i was given as an interval; update it with l and u"))
            end
        end
    end
    if l !== nothing || u !== nothing
        rt = _rowtypes(s.l, s.u, s.kinds)
        if rt != s.rowtype
            s.rowtype = rt
            s.has_last = false
            s.dual = nothing                 # its rows and Z were built for the old row types
            _set_rho!(s, s.rho)
            _refactor_kkt!(s)
        end
    end
    return s
end

"""
Make the next `refactor!` of `S` read every value of `S.K` (after values off
the diagonal changed): QDLDL keeps a permuted copy of the matrix, the rank-one
path of BlockLDL only looks at the diagonal.
"""
function _load_values!(S::QDLDLSystem)
    QDLDL.update_values!(S.F, 1:nnz(S.K), nonzeros(S.K))
    return S
end
_load_values!(S::BlockLDLSystem) = (S.nupd = LOWRANK_BUDGET; S)
_load_values!(S::LinearSystem) = S

"Refactor `S` with every value of `S.K`."
_reload!(S::LinearSystem) = refactor!(_load_values!(S))

"New values of `P` and `A` on the pattern of `setup` (see `update!`)."
function _update_matrices!(s::Solver, P, A)
    sc = s.scl
    if P !== nothing
        Pf = _symmetric_full(P)
        (Pf.colptr == s.P.colptr && Pf.rowval == s.P.rowval) ||
            throw(ArgumentError("P must have the sparsity pattern of the problem given to setup"))
        nzP = nonzeros(s.P); rv = rowvals(Pf); v = nonzeros(Pf)
        @inbounds for j in 1:s.n, k in nzrange(Pf, j)
            nzP[k] = sc.c * sc.D[rv[k]] * v[k] * sc.D[j]
        end
        @inbounds for j in 1:s.n
            d = 0.0
            for k in nzrange(s.P, j)
                rowvals(s.P)[k] == j && (d = nzP[k])
            end
            s.Pdiag[j] = d
            s.xdiag[j] = d + s.settings.sigma
        end
    end
    if A !== nothing
        As = SpMat(sparse(A))
        (size(As) == size(s.A) && As.colptr == s.A.colptr && As.rowval == s.A.rowval) ||
            throw(ArgumentError("A must have the sparsity pattern of the problem given to setup"))
        nzA = nonzeros(s.A); rv = rowvals(As); v = nonzeros(As)
        @inbounds for j in 1:s.n, k in nzrange(As, j)
            nzA[k] = sc.E[rv[k]] * v[k] * sc.D[j]
        end
    end
    # the KKT values off the diagonal, through the pattern of `setup`
    K2, = kkt_pattern(s.P, s.A, s.socs)
    for S in (s.kkt, s.pol)
        (K2.colptr == S.K.colptr && K2.rowval == S.K.rowval) || error("KKT pattern changed")
        copyto!(nonzeros(S.K), nonzeros(K2))
    end
    set_diagonal!(s.kkt.K, s.kkt.diag_idx, s.xdiag, s.rhoinv)
    _reload!(s.kkt)
    _load_values!(s.pol)
    s.pol_valid = false                  # the polish factorization is redone on its next use
    s.ipm = nothing                      # and the interior-point system
    s.dual === nothing || _dual_update_matrices!(s, s.dual::DualWork)
    return s
end

"""
    warm_start!(solver; x = nothing, y = nothing)

Start the next `solve!` from the unscaled primal `x` and multipliers `y` (either
may be omitted: the current iterate is kept). The constraint iterate is set to
the projection of `A x`. With `settings.polish_warm`, the next solve first tries
the polish on the active set read off this point.
"""
function warm_start!(s::Solver; x = nothing, y = nothing)
    sc = s.scl
    if x !== nothing
        @inbounds for j in 1:s.n
            s.x[j] = sc.Dinv[j] * x[j]
        end
    end
    if y !== nothing
        @inbounds for i in 1:s.m
            s.y[i] = sc.c * sc.Einv[i] * y[i]
        end
    end
    mul!(s.z, s.A, s.x)
    _project!(s, s.z)
    s.has_iterate = true
    s.warm_pending = true
    # start the next solve from the default rho (one refactorization if the
    # previous solve had adapted it by more than the tolerance factor)
    st = s.settings
    tol = _rho_tolerance(s)
    if st.warm_reset_rho && (s.rho > tol * s.rho0 || s.rho < s.rho0 / tol)
        _set_rho!(s, s.rho0)
        _refactor_kkt!(s)
    end
    return s
end

"""
    warm_start_shifted!(solver, xmap, ymap)

Warm start from the previous solution moved along the index maps: the new
`x[j]` is the previous `xsol[xmap[j]]` (and `0` where `xmap[j] == 0`), likewise
`y` with `ymap`. For receding-horizon MPC the maps shift the plan by one stage
and repeat the last stage.
"""
function warm_start_shifted!(s::Solver, xmap::AbstractVector{<:Integer}, ymap::AbstractVector{<:Integer})
    xs = s.tn; ys = s.tm
    @inbounds for j in 1:s.n
        k = xmap[j]
        xs[j] = k == 0 ? 0.0 : s.xsol[k]
    end
    @inbounds for i in 1:s.m
        k = ymap[i]
        ys[i] = k == 0 ? 0.0 : s.ysol[k]
    end
    # warm_start! reads its arguments before it overwrites tn and tm
    copyto!(s.pPx, xs)
    copyto!(s.pz, ys)
    return warm_start!(s; x = s.pPx, y = s.pz)
end

"""
    reset!(solver)

Forget the previous solve: zero iterate (the next `solve!` is a cold start),
rho back to its base value (`settings.rho` or the spectral estimate; refactoring the KKT matrix if it had changed), and
the cached polish factorization dropped. The ordering and symbolic
factorization are kept.
"""
function reset!(s::Solver)
    fill!(s.x, 0.0); fill!(s.z, 0.0); fill!(s.y, 0.0)
    s.has_iterate = false
    s.warm_pending = false
    s.pol_valid = false
    s.has_fail = false
    s.has_last = false
    if s.rho != s.rho0
        _set_rho!(s, s.rho0)
        _refactor_kkt!(s)
    end
    return s
end

"Unscaled solution `(x, y, z)` of the last solve (copies)."
solution(s::Solver) = (x = copy(s.xsol), y = copy(s.ysol), z = copy(s.zsol))
