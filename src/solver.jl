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
    kind = st.linsys
    kkt = nothing
    if kind == :auto
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
        kkt = make_system(kind, copy(K), diag_idx, n; ordering = st.ordering, upd_idx = upd_idx)
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
               soc_idx, zeros(length(p.socs)), zeros(length(p.socs)), zeros(m), 0)
    s.info.setup_time = (time_ns() - t0) / 1e9
    s.info.linsys = kind
    s.info.rho = st.rho
    return s
end

# the polish system shares the ordering (and, for the supernodal backend, the
# symbolic factorization) of the ADMM system
_polish_system(S::QDLDLSystem, K::SpMat, n::Int) = QDLDLSystem(K, S.diag_idx, S.upd_idx; perm = copy(S.perm))
function _polish_system(S::ChordalSystem, K::SpMat, n::Int)
    F = Multifrontal.ChordalLDLt(Hermitian(K, :U), S.F.P, S.F.S)
    N = size(K, 1)
    FWs = Multifrontal.FactorizationWorkspace(F)
    DWs = Multifrontal.DivisionWorkspace{Float64}(Multifrontal.symbolic(F), 1)
    T = ChordalSystem(K, S.diag_idx, F, S.L, S.Lt, zeros(N), FWs, DWs, copy(S.signs), Vector{Int}(F.perm), zeros(N))
    _factor!(T)
    return T
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
    dr = 0.0; nPx = 0.0; nAty = 0.0; nq = 0.0
    q = s.q
    @inbounds for j in 1:s.n
        d = D[j]
        dr = max(dr, abs(d * (Px[j] + q[j] + Aty[j])))
        nPx = max(nPx, abs(d * Px[j]))
        nAty = max(nAty, abs(d * Aty[j]))
        nq = max(nq, abs(d * q[j]))
    end
    return pr, cinv * dr, max(nAx, nz), cinv * max(nPx, nAty, nq)
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

function _adapt_rho!(s::Solver, pr, dr, pn, dn)
    st = s.settings
    est = s.rho * sqrt((pr / (pn + 1e-10)) / (dr / (dn + 1e-10) + 1e-10))
    est = clamp(est, st.rho_min, st.rho_max)
    if est > st.adaptive_rho_tolerance * s.rho || est < s.rho / st.adaptive_rho_tolerance
        _set_rho!(s, est)
        _refactor_kkt!(s)
        s.info.rho_updates += 1
    end
    return nothing
end

# ---------------------------------------------------------------------------
# solve
# ---------------------------------------------------------------------------

"""
    solve!(solver) -> Info

Run ADMM from the current iterate (a warm start if `settings.warm_start` and
there is one, zero otherwise), with the polish described in `Settings`. The
unscaled solution is in `solver.xsol`, `solver.ysol`, `solver.zsol`.
"""
function solve!(s::Solver)
    t0 = time_ns()
    st = s.settings
    info = s.info
    info.status = :unsolved
    info.iter = 0
    info.rho_updates = 0
    info.polish = :none
    info.polish_attempts = 0
    info.polish_factorizations = 0
    info.polish_iter = -1
    info.polish_time = 0.0
    s.has_fail = false
    fill!(s.act_prev, Int8(-99))
    if !(st.warm_start && s.has_iterate)
        fill!(s.x, 0.0); fill!(s.z, 0.0); fill!(s.y, 0.0)
        s.warm_pending = false
    end
    converged = false
    polished = false
    status = :max_iter
    tlim = st.time_limit
    if st.polish && st.polish_warm && st.warm_start && s.has_iterate && s.m > 0
        # skip the warm polish after a failure, retrying every 4th solve (a
        # failure costs a factorization; when the warm start's active set is
        # usually right, as in steady receding horizon, it saves the iterations)
        if s.warm_fails == 0 || s.warm_fails % 4 == 0
            _guess_active!(s, s.z, s.y)
            if _try_polish!(s)
                polished = true; converged = true; status = :solved
                s.warm_fails = 0
            else
                s.warm_fails += 1
            end
        else
            s.warm_fails += 1
        end
    end
    s.warm_pending = false
    k = 0
    pint = st.polish_interval
    wait = 2 * pint
    next_polish = 0
    next_adapt = st.adaptive_rho_first > 0 ? st.adaptive_rho_first : st.adaptive_rho_interval
    if !polished
        while k < st.max_iter
            k += 1
            check = k % st.check_termination == 0 || k == st.max_iter || (st.adaptive_rho && k == st.adaptive_rho_first)
            if check
                copyto!(s.xprev, s.x); copyto!(s.yprev, s.y)
            end
            admm_step!(s)
            info.iter = k
            if st.polish && pint > 0 && k % pint == 0 && s.m > 0 && k >= next_polish
                _guess_active!(s, s.z, s.y)
                gate_ok = true
                if st.polish_gate > 0
                    gpr, gdr, gpn, gdn = _residuals!(s, s.x, s.z, s.y, s.Ax, s.Px, s.Aty)
                    gate_ok = max(gpr / (gpn + 1e-10), gdr / (gdn + 1e-10)) <= st.polish_gate
                end
                if gate_ok && s.act == s.act_prev && !(s.has_fail && s.act == s.act_fail)
                    if _try_polish!(s)
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
                if pr <= _eps_prim(st, pn) && dr <= _eps_dual(st, dn)
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
                    _adapt_rho!(s, pr, dr, pn, dn)
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
        polished = _try_polish!(s; restart = false)      # keep the converged ADMM point if rejected
        polished || (info.polish = info.polish == :skipped ? :skipped : :failed)
    end
    s.has_iterate = true
    _finalize!(s, status)
    info.solve_time = (time_ns() - t0) / 1e9
    return info
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
    end
    return nothing
end

# ---------------------------------------------------------------------------
# updates and warm start
# ---------------------------------------------------------------------------

"""
    update!(solver; q = nothing, l = nothing, u = nothing, b = nothing)

New linear cost and/or constraint data (unscaled), keeping the factorization.
`b` is the right-hand side in the convention of the constructor (`b - A x in
K`): it sets `l = u = b` on equality rows, `u = b` on nonnegative-cone rows and
the shift of every SOC block. A change that turns rows into equality or free
rows (or back) changes their rho and costs one refactorization.
"""
function update!(s::Solver; q = nothing, l = nothing, u = nothing, b = nothing)
    sc = s.scl
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
            _set_rho!(s, s.rho)
            _refactor_kkt!(s)
        end
    end
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
    if st.warm_reset_rho && (s.rho > st.adaptive_rho_tolerance * st.rho || s.rho < st.rho / st.adaptive_rho_tolerance)
        _set_rho!(s, st.rho)
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
rho back to `settings.rho` (refactoring the KKT matrix if it had changed), and
the cached polish factorization dropped. The ordering and symbolic
factorization are kept.
"""
function reset!(s::Solver)
    fill!(s.x, 0.0); fill!(s.z, 0.0); fill!(s.y, 0.0)
    s.has_iterate = false
    s.warm_pending = false
    s.pol_valid = false
    s.has_fail = false
    if s.rho != s.settings.rho
        _set_rho!(s, s.settings.rho)
        _refactor_kkt!(s)
    end
    return s
end

"Unscaled solution `(x, y, z)` of the last solve (copies)."
solution(s::Solver) = (x = copy(s.xsol), y = copy(s.ysol), z = copy(s.zsol))
