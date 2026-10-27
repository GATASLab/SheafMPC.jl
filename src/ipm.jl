# ipm.jl: a primal-dual interior-point method on the same scaled problem and
# the same KKT sparsity pattern as the ADMM.
#
# The conic QP is read in the standard form of Clarabel (Goulart and Chen 2024)
#
#     minimize (1/2) x'Px + q'x   subject to  A_e x + s = b_e,  s in K,
#
# where every row of the problem contributes: an equality row a'x = b a zero
# cone (s = 0); a finite upper bound a'x <= u a nonnegative slack s1 = u - a'x;
# a finite lower bound l <= a'x a nonnegative slack s2 = a'x - l (row -a,
# right-hand side -l); a second-order cone block b_B - A_B x = s_B in SOC; a
# free row nothing. The dual variables are z1 (zero cone, upper bound, SOC) and
# z2 (lower bound); the multiplier of the original row is y = z1 - z2 (the
# convention of the ADMM: P x + q + A'y = 0).
#
# Homogeneous embedding (Clarabel's for quadratic objectives): find
# (x, z, s, tau, kappa) with s in K, z in K*, tau, kappa >= 0 and
#
#     P x + A_e'z + q tau                = 0
#     A_e x + s - b_e tau                = 0
#     q'x + b_e'z + x'Px / tau + kappa   = 0,
#
# solved by Mehrotra's predictor-corrector with Nesterov-Todd scaling W (for a
# nonnegative coordinate W = sqrt(s/z); for a second-order cone block the dense
# W of Vandenberghe's CVXOPT notes with W z = W^{-1} s = lambda). A solution
# with tau > 0 is an optimum (x, z, s)/tau; with kappa > 0 and tau -> 0 the
# iterates carry a certificate of primal (b_e'z < 0, A_e'z = 0) or dual
# (q'x < 0, P x = 0, A_e x + s = 0) infeasibility.
#
# Every Newton step solves, with H = W'W (block diagonal; dense on SOC blocks),
#
#     [ P    A_e' ] [dx]   [ r_x ]
#     [ A_e  -H   ] [dz] = [ r_z ].
#
# The two inequalities of a two-sided row are condensed into ONE row of the
# reduced system: a'dx - h dy = r with h = H1 H2 / (H1 + H2) and dy = dz1 - dz2
# (exact elimination), so the matrix is
#
#     [ P + delta I     A'               ]
#     [ A           -(Hc + delta I)      ]
#
# with the pattern of the ADMM KKT matrix (diagonal (2,2) block and a dense
# block per SOC), and only its numerical factorization is recomputed at every
# iteration: the ordering and the symbolic analysis of the ADMM system are
# reused (`_polish_system`). Each iteration factors once and solves three
# systems (the constant one for the tau direction, the affine predictor and the
# combined corrector), each by a few steps of iterative refinement against the
# unregularized matrix.

"""
Cost model of the automatic method choice (method.jl): seconds per ADMM
iteration, per interior-point solve and per ADMM solve (exponential averages,
measured in `setup` and refreshed by every solve; a solve that crossed over
counts as twice the time its ADMM part took, a censored lower bound). When the
ADMM solves cost more on average than an IPM solve and the last two solves
crossed over (one crossover in a warm sequence is weak evidence), `prefer_ipm` sends the
following solves to the IPM directly, with an ADMM probe every `PROBE_EVERY`
solves (`since` counts them).
"""
mutable struct CostModel
    t_admm_iter::Float64
    t_ipm::Float64
    ipm_runs::Int
    prefer_ipm::Bool
    since::Int
    t_admm_solve::Float64
    ncross::Int                  # consecutive crossovers
    t_factor::Float64            # estimated seconds of a factorization of the ADMM system
end
CostModel() = CostModel(NaN, NaN, 0, false, 0, NaN, 0, NaN)

const IPM_FREE = 0x00
const IPM_EQ = 0x01
const IPM_U = 0x02
const IPM_L = 0x03
const IPM_UL = 0x04
const IPM_SOC = 0x05

mutable struct IPMWork{LS<:LinearSystem}
    sys::LS
    rt::Vector{UInt8}
    nu::Int                      # degree of the cone (nonnegative coordinates + SOC blocks)
    # iterate (scaled problem, homogeneous)
    x::Vector{Float64}
    s1::Vector{Float64}
    z1::Vector{Float64}
    s2::Vector{Float64}
    z2::Vector{Float64}
    tau::Float64
    kappa::Float64
    # scaling
    H1::Vector{Float64}
    H2::Vector{Float64}
    hc::Vector{Float64}          # condensed (2,2) diagonal (without regularization)
    lam1::Vector{Float64}        # lambda: nonnegative coordinates and SOC blocks (rows of the block)
    lam2::Vector{Float64}
    W::Vector{Matrix{Float64}}   # NT scaling per SOC block
    Winv::Vector{Matrix{Float64}}
    Hs::Vector{Matrix{Float64}}  # W^2
    # residuals
    rx::Vector{Float64}
    rz1::Vector{Float64}
    rz2::Vector{Float64}
    rtau::Float64
    # directions: constant system (c), current (d), affine (saved)
    cx::Vector{Float64}
    cz1::Vector{Float64}
    cz2::Vector{Float64}
    dx::Vector{Float64}
    dz1::Vector{Float64}
    dz2::Vector{Float64}
    ds1::Vector{Float64}
    ds2::Vector{Float64}
    dtau::Float64
    dkappa::Float64
    # right-hand sides in lambda space (d_s) and their W (lambda \ d_s)
    q1::Vector{Float64}
    q2::Vector{Float64}
    w1::Vector{Float64}
    w2::Vector{Float64}
    # workspace
    bx::Vector{Float64}
    b1::Vector{Float64}
    b2::Vector{Float64}
    rhs::Vector{Float64}
    sol::Vector{Float64}
    res::Vector{Float64}
    tn::Vector{Float64}
    tn2::Vector{Float64}
    tm::Vector{Float64}
    tm2::Vector{Float64}
    xdiag::Vector{Float64}
    dreg::Vector{Float64}
    blen::Int
    bvec::Vector{Float64}        # small per-block workspace
    bvec2::Vector{Float64}
    bvec3::Vector{Float64}
    iter::Int
    reg::Float64
    nsolves::Int
end

function _ipm_rowtypes(s)
    m = s.m
    rt = Vector{UInt8}(undef, m)
    for i in 1:m
        t = s.rowtype[i]
        if t == ROWT_SOC
            rt[i] = IPM_SOC
        elseif t == ROWT_EQ
            rt[i] = IPM_EQ
        elseif t == ROWT_FREE
            rt[i] = IPM_FREE
        else
            fu = s.u[i] < Inf; fl = s.l[i] > -Inf
            rt[i] = fu && fl ? IPM_UL : fu ? IPM_U : fl ? IPM_L : IPM_FREE
        end
    end
    return rt
end

# The IPM's copy of the KKT system: the ordering and symbolic factorization of
# the ADMM system, with dynamic regularization of the pivots (a pivot of the
# wrong sign or smaller than 1e-13 is replaced by 2e-7 with the right sign, as
# Clarabel does with QDLDL): near the solution the scaling blocks of the
# second-order cones have condition numbers ~ 1/mu^2, and an unregularized
# quasi-definite LDLt can meet a zero pivot. Iterative refinement against the
# unregularized matrix removes the perturbation.
const IPM_DYN_EPS = 1e-13
const IPM_DYN_DELTA = 2e-7

function _ipm_system(S::QDLDLSystem, K::SpMat, n::Int)
    N = size(K, 1)
    signs = [i <= n ? 1 : -1 for i in 1:N]
    F = QDLDL.qdldl(K; perm = copy(S.perm), Dsigns = signs, regularize_eps = IPM_DYN_EPS, regularize_delta = IPM_DYN_DELTA)
    ws = F.workspace
    return QDLDLSystem(K, S.diag_idx, S.upd_idx, F, copy(S.perm), zeros(N), ws.Ln, ws.Lp, ws.Li, ws.Lx, ws.Dinv)
end
_ipm_system(S::LinearSystem, K::SpMat, n::Int) = _polish_system(S, K, n)

# BlockLDL (the kernel, src/kkt): a factor on the ADMM system's symbolic
# analysis, with the kernel's sign regularization at a pivot floor sized for
# the IPM (its default 1e-12 suits the ADMM and polish systems), no rank-one
# path (every IPM iteration changes the cone blocks)
const IPM_BLOCK_DELTA = 1e-10
function _ipm_system(S::BlockLDLSystem, K::SpMat, n::Int)
    F = BlockLDL.Factor(S.F.S; delta = IPM_BLOCK_DELTA, nthreads = S.F.nthreads)
    BlockLDL.factor!(F, K)
    return _bls(K, S.diag_idx, F, S.ordering, S.order_table, [S.diag_idx; S.offidx])
end

"A QDLDL system for the IPM with its own fill-reducing ordering (`nothing`: QDLDL's AMD)."
function _ipm_qdldl(K::SpMat, diag_idx::Vector{Int}, upd_idx::Vector{Int}, n::Int, perm)
    N = size(K, 1)
    signs = [i <= n ? 1 : -1 for i in 1:N]
    F = perm === nothing ? QDLDL.qdldl(K; Dsigns = signs, regularize_eps = IPM_DYN_EPS, regularize_delta = IPM_DYN_DELTA) :
        QDLDL.qdldl(K; perm = perm, Dsigns = signs, regularize_eps = IPM_DYN_EPS, regularize_delta = IPM_DYN_DELTA)
    ws = F.workspace
    p = F.perm === nothing ? collect(1:N) : F.perm
    return QDLDLSystem(K, diag_idx, upd_idx, F, p, zeros(N), ws.Ln, ws.Lp, ws.Li, ws.Lx, ws.Dinv)
end

"""
The KKT system of the IPM, built on the first crossover (or in `setup` with
`method = :ipm`). An IPM iteration is dominated by a numerical factorization,
an ADMM iteration by a solve, so with `linsys = :auto` the IPM asks the
kernel's cost model (`BlockLDL.choose_system`, src/kkt: elimination
statistics of the candidate orders, no trial factorization) for the engine and
order of least cost at one factorization per six solves. The ADMM system's
symbolic analysis is reused when its own order is within 10% of that choice;
otherwise the chosen engine (QDLDL or BlockLDL) is set up once. Either way the
iterations only refactor numerically.
"""
function _ipm_choose_system(s)
    n = s.n
    K0 = s.kkt.K
    s.settings.linsys == :auto || return _ipm_system(s.kkt, copy(K0), n)
    N = size(K0, 1)
    nt = s.settings.kkt_threads
    cm = BlockLDL.CostModel(factors = 1.0, solves = 6.0, nthreads = nt)
    perm, name, eng, table, tree, nth = BlockLDL.choose_system(K0; cost = cm)
    perm === nothing && return _ipm_system(s.kkt, copy(K0), n)
    best = minimum(r.est for r in table)
    own, owneng = _factor_stats(s.kkt)
    if BlockLDL.estimate(BlockLDL.CostModel(factors = 1.0, solves = 6.0), own, N, owneng) <= 1.1 * best
        return _ipm_system(s.kkt, copy(K0), n)
    end
    di = s.kkt.diag_idx
    upd = copy(di)
    for (k, B) in enumerate(s.socs), a2 in 1:length(B), a1 in 1:(a2-1)
        push!(upd, s.soc_idx[k][a1, a2])
    end
    eng == :simplicial && return _ipm_qdldl(copy(K0), di, upd, n, perm)
    S = BlockLDLSystem(copy(K0), di, n; settings = s.settings, perm = perm, name = name, tree = tree, threads = nth,
                       upd_idx = upd)
    return _ipm_system(S, copy(K0), n)
end

_ipm_refactor!(S::LinearSystem) = refactor!(S)
function _ipm_refactor!(S::ChordalSystem)
    copyto!(S.F, Hermitian(S.K, :U))
    ldlt!(S.FWs, S.F; signs = S.signs, check = false,
          reg = Multifrontal.DynamicRegularization(; delta = IPM_DYN_DELTA, epsilon = IPM_DYN_EPS))
    S.L = S.F.L
    S.Lt = S.L'
    copyto!(S.d, S.F.d)
    return S
end

function _ipm_work(s; sys = nothing)
    n, m = s.n, s.m
    sys === nothing && (sys = _ipm_choose_system(s))
    rt = _ipm_rowtypes(s)
    nb = length(s.socs)
    dmax = nb == 0 ? 1 : maximum(length, s.socs)
    W = [zeros(length(B), length(B)) for B in s.socs]
    Wi = [zeros(length(B), length(B)) for B in s.socs]
    Hs = [zeros(length(B), length(B)) for B in s.socs]
    z() = zeros(m)
    w = IPMWork(sys, rt, 0, zeros(n), z(), z(), z(), z(), 1.0, 1.0,
                z(), z(), z(), z(), z(), W, Wi, Hs,
                zeros(n), z(), z(), 0.0,
                zeros(n), z(), z(), zeros(n), z(), z(), z(), z(), 0.0, 0.0,
                z(), z(), z(), z(),
                zeros(n), z(), z(), zeros(n + m), zeros(n + m), zeros(n + m), zeros(n), zeros(n), z(), z(),
                zeros(n), zeros(m), dmax, zeros(dmax), zeros(dmax), zeros(dmax), 0, 0.0, 0)
    _ipm_refresh_types!(w, s)
    return w
end

"Row types and cone degree from the current bounds (after `update!` they may change)."
function _ipm_refresh_types!(w::IPMWork, s)
    w.rt = _ipm_rowtypes(s)
    nu = length(s.socs)
    @inbounds for i in 1:s.m
        t = w.rt[i]
        nu += t == IPM_U || t == IPM_L ? 1 : t == IPM_UL ? 2 : 0
    end
    w.nu = nu
    return w
end

# ---------------------------------------------------------------------------
# second-order cone algebra (blocks of rows B of vectors of length m)
# ---------------------------------------------------------------------------

"Smallest eigenvalue t - ||x|| of the SOC block `v[B]`."
@inline function _soc_mineig(v::AbstractVector{Float64}, B::UnitRange{Int})
    i0 = first(B)
    ns = 0.0
    @inbounds for i in (i0+1):last(B)
        ns += v[i] * v[i]
    end
    return v[i0] - sqrt(ns)
end

"`t^2 - ||x||^2` of the block."
@inline function _soc_det(v::AbstractVector{Float64}, B::UnitRange{Int})
    i0 = first(B)
    ns = 0.0
    @inbounds for i in (i0+1):last(B)
        ns += v[i] * v[i]
    end
    return v[i0]^2 - ns
end

"Largest `a` with `v + a dv` in the SOC block (`v` interior), `Inf` if unbounded."
function _soc_step(v::AbstractVector{Float64}, dv::AbstractVector{Float64}, B::UnitRange{Int})
    i0 = first(B)
    a = dv[i0]^2; b = v[i0] * dv[i0]; c = v[i0]^2
    @inbounds for i in (i0+1):last(B)
        a -= dv[i]^2; b -= v[i] * dv[i]; c -= v[i]^2
    end
    b *= 2
    c = max(c, 0.0)
    # f(t) = a t^2 + b t + c, f(0) = c >= 0; also v0 + t dv0 >= 0
    tmax = dv[i0] < 0 ? -v[i0] / dv[i0] : Inf
    if abs(a) <= 1e-300
        r = b < 0 ? -c / b : Inf
        return min(r, tmax)
    end
    disc = b * b - 4 * a * c
    if disc < 0
        return a > 0 ? tmax : 0.0
    end
    sq = sqrt(disc)
    qq = -0.5 * (b + (b >= 0 ? sq : -sq))
    r1 = qq / a
    r2 = qq != 0 ? c / qq : Inf
    r = Inf
    r1 > 0 && (r = min(r, r1))
    r2 > 0 && (r = min(r, r2))
    return min(r, tmax)
end

"Nesterov-Todd scaling of the SOC pair (s, z) (both interior): fills W, W^{-1}, W^2 and lambda = W z."
function _soc_nt!(W::Matrix{Float64}, Wi::Matrix{Float64}, Hs::Matrix{Float64}, lam::AbstractVector{Float64},
                  s::AbstractVector{Float64}, z::AbstractVector{Float64}, B::UnitRange{Int}, wv::Vector{Float64})
    d = length(B); i0 = first(B)
    ns = sqrt(max(_soc_det(s, B), 1e-300)); nz = sqrt(max(_soc_det(z, B), 1e-300))
    sz = 0.0
    @inbounds for i in B
        sz += s[i] * z[i]
    end
    g = sqrt(max((1 + sz / (ns * nz)) / 2, 1e-300))
    eta = sqrt(ns / nz)
    # w = (s/ns + J z/nz) / (2 g)
    @inbounds wv[1] = (s[i0] / ns + z[i0] / nz) / (2g)
    @inbounds for a in 2:d
        wv[a] = (s[i0+a-1] / ns - z[i0+a-1] / nz) / (2g)
    end
    w0 = wv[1]
    f = 1 / (1 + w0)
    @inbounds begin
        W[1, 1] = eta * w0; Wi[1, 1] = w0 / eta
        for a in 2:d
            W[a, 1] = eta * wv[a]; W[1, a] = eta * wv[a]
            Wi[a, 1] = -wv[a] / eta; Wi[1, a] = -wv[a] / eta
            for b in 2:d
                v = wv[a] * wv[b] * f + (a == b ? 1.0 : 0.0)
                W[a, b] = eta * v
                Wi[a, b] = v / eta
            end
        end
        # H = W^2 = eta^2 (2 w w' - J), formed directly (the product W W loses
        # the small eigenvalues of a block near the boundary of the cone)
        e2 = eta * eta
        for b in 1:d, a in 1:d
            Hs[a, b] = e2 * (2 * wv[a] * wv[b] - (a == b ? (a == 1 ? 1.0 : -1.0) : 0.0))
        end
        for a in 1:d
            t = 0.0
            for k in 1:d
                t += W[a, k] * z[i0+k-1]
            end
            lam[i0+a-1] = t
        end
    end
    return nothing
end

"`out[B] = M * v[B]` for a dense block matrix."
@inline function _blk_mul!(out::AbstractVector{Float64}, M::Matrix{Float64}, v::AbstractVector{Float64}, B::UnitRange{Int})
    i0 = first(B); d = length(B)
    @inbounds for a in 1:d
        t = 0.0
        for k in 1:d
            t += M[a, k] * v[i0+k-1]
        end
        out[i0+a-1] = t
    end
    return out
end

"Jordan product `out[B] = u[B] o v[B]` = (u'v, u0 v1 + v0 u1)."
@inline function _jprod!(out::AbstractVector{Float64}, u::AbstractVector{Float64}, v::AbstractVector{Float64}, B::UnitRange{Int})
    i0 = first(B)
    t = 0.0
    @inbounds for i in B
        t += u[i] * v[i]
    end
    u0 = u[i0]; v0 = v[i0]
    @inbounds for i in (i0+1):last(B)
        out[i] = u0 * v[i] + v0 * u[i]
    end
    @inbounds out[i0] = t
    return out
end

"Inverse Jordan product: `out[B]` with `lam o out = v` on the block."
@inline function _jdiv!(out::AbstractVector{Float64}, lam::AbstractVector{Float64}, v::AbstractVector{Float64}, B::UnitRange{Int})
    i0 = first(B)
    l0 = lam[i0]
    rho = l0 * l0; lv = 0.0
    @inbounds for i in (i0+1):last(B)
        rho -= lam[i] * lam[i]
        lv += lam[i] * v[i]
    end
    u0 = (l0 * v[i0] - lv) / rho
    @inbounds for i in (i0+1):last(B)
        out[i] = (v[i] - u0 * lam[i]) / l0
    end
    @inbounds out[i0] = u0
    return out
end

# ---------------------------------------------------------------------------
# the iteration
# ---------------------------------------------------------------------------

"Right-hand side value of row i in the standard form (b_e of the z1 constraint)."
@inline _b1(s, w::IPMWork, i::Int) = w.rt[i] == IPM_SOC ? s.socb[i] : s.u[i]   # EQ: l = u

"Residuals of the homogeneous system at the current iterate."
function _ipm_residuals!(w::IPMWork, s)
    n, m = s.n, s.m
    x = w.x; tau = w.tau
    mul!(w.tn, s.P, x)                       # P x
    mul!(w.tm, s.A, x)                       # A x
    # y = z1 - z2 into tm2
    y = w.tm2
    @inbounds for i in 1:m
        t = w.rt[i]
        y[i] = t == IPM_L ? -w.z2[i] : t == IPM_UL ? w.z1[i] - w.z2[i] : t == IPM_FREE ? 0.0 : w.z1[i]
    end
    mul!(w.rx, transpose(s.A), y)
    @inbounds for j in 1:n
        w.rx[j] += w.tn[j] + s.q[j] * tau
    end
    bz = 0.0
    @inbounds for i in 1:m
        t = w.rt[i]; ax = w.tm[i]
        w.rz1[i] = 0.0; w.rz2[i] = 0.0
        if t == IPM_EQ
            w.rz1[i] = ax - s.u[i] * tau
            bz += s.u[i] * w.z1[i]
        elseif t == IPM_SOC
            w.rz1[i] = ax + w.s1[i] - s.socb[i] * tau
            bz += s.socb[i] * w.z1[i]
        else
            if t == IPM_U || t == IPM_UL
                w.rz1[i] = ax + w.s1[i] - s.u[i] * tau
                bz += s.u[i] * w.z1[i]
            end
            if t == IPM_L || t == IPM_UL
                w.rz2[i] = -ax + w.s2[i] + s.l[i] * tau
                bz -= s.l[i] * w.z2[i]
            end
        end
    end
    xPx = dot(x, w.tn); qx = dot(s.q, x)
    w.rtau = qx + bz + xPx / tau + w.kappa
    return xPx, qx, bz
end

"Complementarity s'z (nonnegative coordinates and SOC blocks)."
function _ipm_sz(w::IPMWork, s)
    t = 0.0
    @inbounds for i in 1:s.m
        r = w.rt[i]
        (r == IPM_U || r == IPM_UL || r == IPM_SOC) && (t += w.s1[i] * w.z1[i])
        (r == IPM_L || r == IPM_UL) && (t += w.s2[i] * w.z2[i])
    end
    return t
end

"NT scaling at the current iterate, the KKT values, and the numerical factorization."
function _ipm_scale_factor!(w::IPMWork, s)
    n, m = s.n, s.m
    reg = w.reg
    @inbounds for i in 1:m
        t = w.rt[i]
        if t == IPM_U || t == IPM_UL
            w.H1[i] = w.s1[i] / w.z1[i]
            w.lam1[i] = sqrt(w.s1[i] * w.z1[i])
        end
        if t == IPM_L || t == IPM_UL
            w.H2[i] = w.s2[i] / w.z2[i]
            w.lam2[i] = sqrt(w.s2[i] * w.z2[i])
        end
        w.hc[i] = t == IPM_U ? w.H1[i] : t == IPM_L ? w.H2[i] :
                  t == IPM_UL ? w.H1[i] * w.H2[i] / (w.H1[i] + w.H2[i]) :
                  t == IPM_EQ ? 0.0 : t == IPM_FREE ? 1.0 / reg : 0.0
        w.dreg[i] = w.hc[i] + reg
    end
    @inbounds for (k, B) in enumerate(s.socs)
        _soc_nt!(w.W[k], w.Winv[k], w.Hs[k], w.lam1, w.s1, w.z1, B, w.bvec)
        for i in B
            w.hc[i] = 0.0
        end
    end
    @inbounds for j in 1:n
        w.xdiag[j] = s.Pdiag[j] + reg
    end
    K = w.sys.K
    set_diagonal!(K, w.sys.diag_idx, w.xdiag, w.dreg)
    nz = nonzeros(K)
    @inbounds for (k, B) in enumerate(s.socs)
        I = s.soc_idx[k]; H = w.Hs[k]; d = length(B)
        for b in 1:d, a in 1:b
            nz[I[a, b]] = -(H[a, b] + (a == b ? reg : 0.0))
        end
    end
    _ipm_refactor!(w.sys)
    return nothing
end

"`out = K_true * v` for the reduced KKT matrix without regularization (free rows keep theirs)."
function _ipm_kmul!(out::Vector{Float64}, w::IPMWork, s, v::Vector{Float64})
    n, m = s.n, s.m
    vx = view(v, 1:n); vy = view(v, (n+1):(n+m))
    ox = view(out, 1:n); oy = view(out, (n+1):(n+m))
    mul!(ox, s.P, vx)
    mul!(ox, transpose(s.A), vy, 1.0, 1.0)
    mul!(oy, s.A, vx)
    @inbounds for i in 1:m
        oy[i] -= w.hc[i] * vy[i]
    end
    @inbounds for (k, B) in enumerate(s.socs)
        H = w.Hs[k]; i0 = first(B); d = length(B)
        for a in 1:d
            t = 0.0
            for b in 1:d
                t += H[a, b] * vy[i0+b-1]
            end
            oy[i0+a-1] -= t
        end
    end
    return out
end

"Solve the reduced system with `rhs` (length n + m) into `sol` by refinement against K_true."
function _ipm_linsolve!(w::IPMWork, s)
    rhs = w.rhs; sol = w.sol; res = w.res
    copyto!(sol, rhs)
    solve!(w.sys, sol)
    nb = norm(rhs, Inf)
    prev = Inf
    # Clarabel's rule: refine until the residual is below 1e-12 + 1e-13 ||rhs||,
    # stops improving fivefold, or 10 steps
    for _ in 1:10
        _ipm_kmul!(res, w, s, sol)
        @inbounds for k in eachindex(res)
            res[k] = rhs[k] - res[k]
        end
        nr = norm(res, Inf)
        (nr <= 1e-12 + 1e-13 * nb || nr > prev / 5) && break
        prev = nr
        solve!(w.sys, res)
        @inbounds for k in eachindex(sol)
            sol[k] += res[k]
        end
        w.nsolves += 1
    end
    w.nsolves += 1
    return sol
end

"""
Solve the expanded Newton system for the x right-hand side `bx` and the
constraint right-hand sides `b1` (z1 rows), `b2` (z2 rows): fills `ox`, `oz1`, `oz2`.
"""
function _ipm_newton!(ox, oz1, oz2, w::IPMWork, s)
    n, m = s.n, s.m
    rhs = w.rhs
    @inbounds for j in 1:n
        rhs[j] = w.bx[j]
    end
    @inbounds for i in 1:m
        t = w.rt[i]
        rhs[n+i] = t == IPM_L ? -w.b2[i] :
                   t == IPM_UL ? w.hc[i] * (w.b1[i] / w.H1[i] - w.b2[i] / w.H2[i]) :
                   t == IPM_FREE ? 0.0 : w.b1[i]
    end
    _ipm_linsolve!(w, s)
    sol = w.sol
    @inbounds for j in 1:n
        ox[j] = sol[j]
    end
    mul!(w.tm, s.A, ox)
    @inbounds for i in 1:m
        t = w.rt[i]; dy = sol[n+i]
        oz1[i] = 0.0; oz2[i] = 0.0
        if t == IPM_L
            oz2[i] = -dy
        elseif t == IPM_UL
            # the inactive side (larger H) from its own row, the other from
            # dy = dz1 - dz2 (dividing by the small H of an active side would
            # amplify the error of a'dx)
            v = w.tm[i]
            if w.H1[i] >= w.H2[i]
                oz1[i] = (v - w.b1[i]) / w.H1[i]
                oz2[i] = oz1[i] - dy
            else
                oz2[i] = (-v - w.b2[i]) / w.H2[i]
                oz1[i] = dy + oz2[i]
            end
        elseif t != IPM_FREE
            oz1[i] = dy
        end
    end
    return nothing
end

"b_e'z for an expanded z."
function _ipm_bz(w::IPMWork, s, z1, z2)
    t = 0.0
    @inbounds for i in 1:s.m
        r = w.rt[i]
        if r == IPM_SOC
            t += s.socb[i] * z1[i]
        elseif r == IPM_EQ || r == IPM_U || r == IPM_UL
            t += s.u[i] * z1[i]
        end
        (r == IPM_L || r == IPM_UL) && (t -= s.l[i] * z2[i])
    end
    return t
end

"""
Newton direction with residual weight `eta` and complementarity right-hand
sides (lambda space) `q1`, `q2` and `dk` (for tau kappa): fills dx, dz, ds, dtau, dkappa.
"""
function _ipm_direction!(w::IPMWork, s, eta::Float64, dk::Float64)
    n, m = s.n, s.m
    # w = W (lambda \ d_s): nonnegative: d_s / z; SOC: W (lam \ d_s)
    @inbounds for i in 1:m
        t = w.rt[i]
        (t == IPM_U || t == IPM_UL) && (w.w1[i] = w.q1[i] / w.z1[i])
        (t == IPM_L || t == IPM_UL) && (w.w2[i] = w.q2[i] / w.z2[i])
    end
    @inbounds for (k, B) in enumerate(s.socs)
        _jdiv!(w.tm2, w.lam1, w.q1, B)
        _blk_mul!(w.w1, w.W[k], w.tm2, B)
    end
    # system 2: bx = -eta r_x, b = -eta r_z + w
    @inbounds for j in 1:n
        w.bx[j] = -eta * w.rx[j]
    end
    @inbounds for i in 1:m
        t = w.rt[i]
        w.b1[i] = -eta * w.rz1[i] + (t == IPM_U || t == IPM_UL || t == IPM_SOC ? w.w1[i] : 0.0)
        w.b2[i] = -eta * w.rz2[i] + (t == IPM_L || t == IPM_UL ? w.w2[i] : 0.0)
    end
    _ipm_newton!(w.dx, w.dz1, w.dz2, w, s)
    # dtau
    tau = w.tau
    mul!(w.tn, s.P, w.x)                     # P x
    num = -eta * w.rtau + dk / tau
    @inbounds for j in 1:n
        num -= (s.q[j] + 2 * w.tn[j] / tau) * w.dx[j]
    end
    num -= _ipm_bz(w, s, w.dz1, w.dz2)
    # denominator: -( (cx - x/tau)'P(cx - x/tau) + cz'H cz + kappa/tau )
    @inbounds for j in 1:n
        w.tn2[j] = w.cx[j] - w.x[j] / tau
    end
    mul!(w.tn, s.P, w.tn2)
    den = dot(w.tn2, w.tn) + w.kappa / tau
    @inbounds for i in 1:m
        t = w.rt[i]
        (t == IPM_U || t == IPM_UL) && (den += w.H1[i] * w.cz1[i]^2)
        (t == IPM_L || t == IPM_UL) && (den += w.H2[i] * w.cz2[i]^2)
    end
    @inbounds for (k, B) in enumerate(s.socs)
        _blk_mul!(w.tm2, w.Hs[k], w.cz1, B)
        for i in B
            den += w.cz1[i] * w.tm2[i]
        end
    end
    dtau = num / (-den)
    w.dtau = dtau
    @inbounds for j in 1:n
        w.dx[j] += dtau * w.cx[j]
    end
    @inbounds for i in 1:m
        w.dz1[i] += dtau * w.cz1[i]
        w.dz2[i] += dtau * w.cz2[i]
    end
    # ds = -W (lambda \ d_s) - H dz
    @inbounds for i in 1:m
        t = w.rt[i]
        w.ds1[i] = (t == IPM_U || t == IPM_UL) ? -w.w1[i] - w.H1[i] * w.dz1[i] : 0.0
        w.ds2[i] = (t == IPM_L || t == IPM_UL) ? -w.w2[i] - w.H2[i] * w.dz2[i] : 0.0
    end
    @inbounds for (k, B) in enumerate(s.socs)
        _blk_mul!(w.tm2, w.Hs[k], w.dz1, B)
        for i in B
            w.ds1[i] = -w.w1[i] - w.tm2[i]
        end
    end
    w.dkappa = -(dk + w.kappa * dtau) / tau
    return nothing
end

"Largest step in (0, 1] keeping the iterate in the cone (times nothing: the caller applies the fraction)."
function _ipm_step_length(w::IPMWork, s)
    a = Inf
    @inbounds for i in 1:s.m
        t = w.rt[i]
        if t == IPM_U || t == IPM_UL
            w.ds1[i] < 0 && (a = min(a, -w.s1[i] / w.ds1[i]))
            w.dz1[i] < 0 && (a = min(a, -w.z1[i] / w.dz1[i]))
        end
        if t == IPM_L || t == IPM_UL
            w.ds2[i] < 0 && (a = min(a, -w.s2[i] / w.ds2[i]))
            w.dz2[i] < 0 && (a = min(a, -w.z2[i] / w.dz2[i]))
        end
    end
    @inbounds for B in s.socs
        a = min(a, _soc_step(w.s1, w.ds1, B), _soc_step(w.z1, w.dz1, B))
    end
    w.dtau < 0 && (a = min(a, -w.tau / w.dtau))
    w.dkappa < 0 && (a = min(a, -w.kappa / w.dkappa))
    return min(a, 1.0)
end

"Shift the nonnegative coordinates and every SOC block of (v1, v2) into the interior (Clarabel's initialization)."
function _ipm_shift!(w::IPMWork, s, v1, v2)
    amin = Inf
    @inbounds for i in 1:s.m
        t = w.rt[i]
        (t == IPM_U || t == IPM_UL) && (amin = min(amin, v1[i]))
        (t == IPM_L || t == IPM_UL) && (amin = min(amin, v2[i]))
    end
    if amin < sqrt(eps())
        sh = 1.0 - amin
        @inbounds for i in 1:s.m
            t = w.rt[i]
            (t == IPM_U || t == IPM_UL) && (v1[i] += sh)
            (t == IPM_L || t == IPM_UL) && (v2[i] += sh)
        end
    end
    @inbounds for B in s.socs
        a = _soc_mineig(v1, B)
        a < sqrt(eps()) && (v1[first(B)] += 1.0 - a)
    end
    return nothing
end

function _ipm_init!(w::IPMWork, s)
    n, m = s.n, s.m
    reg = w.reg
    # H = I on every cone (zero on the zero cone)
    @inbounds for i in 1:m
        t = w.rt[i]
        w.H1[i] = 1.0; w.H2[i] = 1.0
        w.hc[i] = t == IPM_UL ? 0.5 : (t == IPM_U || t == IPM_L) ? 1.0 : t == IPM_FREE ? 1.0 / reg : 0.0
        w.dreg[i] = w.hc[i] + reg
    end
    @inbounds for (k, B) in enumerate(s.socs)
        H = w.Hs[k]
        fill!(H, 0.0)
        for a in 1:length(B)
            H[a, a] = 1.0
        end
        for i in B
            w.hc[i] = 0.0; w.dreg[i] = 1.0 + reg
        end
    end
    @inbounds for j in 1:n
        w.xdiag[j] = s.Pdiag[j] + reg
    end
    K = w.sys.K
    set_diagonal!(K, w.sys.diag_idx, w.xdiag, w.dreg)
    nz = nonzeros(K)
    @inbounds for (k, B) in enumerate(s.socs)
        I = s.soc_idx[k]; d = length(B)
        for b in 1:d, a in 1:(b-1)
            nz[I[a, b]] = 0.0
        end
    end
    _ipm_refactor!(w.sys)
    @inbounds for j in 1:n
        w.bx[j] = -s.q[j]
    end
    @inbounds for i in 1:m
        w.b1[i] = _b1(s, w, i)
        w.b2[i] = -s.l[i]
        w.rt[i] == IPM_L || w.rt[i] == IPM_UL || (w.b2[i] = 0.0)
        (w.rt[i] == IPM_L || w.rt[i] == IPM_FREE) && (w.b1[i] = 0.0)
    end
    _ipm_newton!(w.x, w.z1, w.z2, w, s)
    # s = -z, then both shifted into the interior
    @inbounds for i in 1:m
        w.s1[i] = -w.z1[i]; w.s2[i] = -w.z2[i]
        w.rt[i] == IPM_EQ && (w.s1[i] = 0.0)
    end
    _ipm_shift!(w, s, w.s1, w.s2)
    _ipm_shift!(w, s, w.z1, w.z2)
    @inbounds for i in 1:m
        t = w.rt[i]
        t == IPM_EQ || t == IPM_SOC || t == IPM_U || t == IPM_UL || (w.s1[i] = 0.0; w.z1[i] = 0.0)
        t == IPM_L || t == IPM_UL || (w.s2[i] = 0.0; w.z2[i] = 0.0)
        t == IPM_EQ && (w.s1[i] = 0.0)
    end
    w.tau = 1.0; w.kappa = 1.0
    return nothing
end

"""
    _ipm_solve!(s::Solver) -> status

Run the interior-point method on the scaled problem of `s` (cold start) and
leave the solution in `s.x`, `s.y`, `s.z` (scaled, in the ADMM convention).
"""
function _ipm_solve!(s, t0::UInt64)
    s.ipm === nothing && (s.ipm = _ipm_work(s))
    return _ipm_run!(s.ipm, s, t0)
end

function _ipm_run!(w::IPMWork{LS}, s, t0::UInt64) where {LS}
    st = s.settings
    info = s.info
    n, m = s.n, s.m
    _ipm_refresh_types!(w, s)
    w.reg = st.ipm_reg
    w.nsolves = 0
    _ipm_init!(w, s)
    sc = s.scl
    cinv = sc.cinv
    status = :max_iter
    k = 0
    npol = 0
    nsmall = 0
    while true
        xPx, qx, bz = _ipm_residuals!(w, s)
        tau = w.tau
        # termination on the unscaled problem
        pobj = cinv * (0.5 * xPx / tau^2 + qx / tau) + s.c0
        dobj = cinv * (-0.5 * xPx / tau^2 - bz / tau) + s.c0
        gap = abs(pobj - dobj)
        pr = 0.0; pn = 0.0
        @inbounds for i in 1:m
            e = sc.Einv[i]
            pr = max(pr, e * abs(w.rz1[i]) / tau, e * abs(w.rz2[i]) / tau)
            pn = max(pn, e * abs(w.tm[i]) / tau)
        end
        # y into tm2 (from _ipm_residuals!): A'y
        mul!(w.tn2, transpose(s.A), w.tm2)
        mul!(w.tn, s.P, w.x)
        dr = 0.0; dn = 0.0
        @inbounds for j in 1:n
            d = sc.Dinv[j]
            dr = max(dr, d * abs(w.rx[j]) / tau)
            dn = max(dn, d * abs(w.tn[j]) / tau, d * abs(w.tn2[j]) / tau, d * abs(s.q[j]))
        end
        dr *= cinv; dn *= cinv
        info.prim_res = pr; info.dual_res = dr; info.gap = gap
        st.verbose && @printf("ipm %3d  pobj % .8e  dobj % .8e  gap %.2e  pr %.2e  dr %.2e  tau %.2e  kappa %.2e\n",
                              k, pobj, dobj, gap, pr, dr, w.tau, w.kappa)
        if pr <= _eps_prim(st, pn) && dr <= _eps_dual(st, dn) &&
           gap <= _gap_tol(st, pobj, dobj, s.c0) && _ipm_violation_ok(w, s)
            status = :solved
            break
        end
        # early polish: once the gap is small the active set read off the
        # iterate is usually the final one, and the active-set solve (exact)
        # replaces the last interior-point iterations
        if st.ipm_polish && st.polish && npol < st.ipm_polish_tries && k > 0 &&
           gap <= st.ipm_polish_gap * max(1.0, min(abs(pobj), abs(dobj))) && pr <= sqrt(_eps_prim(st, pn)) && dr <= sqrt(_eps_dual(st, dn))
            npol += 1
            _ipm_to_admm!(w, s)
            _guess_active!(s, s.z, s.y)
            if _try_polish!(s; restart = false, newton = st.ipm_polish_newton)
                status = :solved_polished
                break
            end
        end
        # infeasibility certificates (the homogeneous iterate, tau -> 0)
        inf = _ipm_infeasible!(w, s, bz, qx)
        if inf != :none
            status = inf
            break
        end
        k >= st.ipm_max_iter && break
        if st.time_limit < Inf && (time_ns() - t0) / 1e9 > st.time_limit
            status = :time_limit; break
        end
        k += 1
        sz = _ipm_sz(w, s)
        mu = (sz + w.tau * w.kappa) / (w.nu + 1)
        _ipm_scale_factor!(w, s)
        # constant system: [-q; b_e]
        @inbounds for j in 1:n
            w.bx[j] = -s.q[j]
        end
        @inbounds for i in 1:m
            t = w.rt[i]
            w.b1[i] = (t == IPM_L || t == IPM_FREE) ? 0.0 : _b1(s, w, i)
            w.b2[i] = (t == IPM_L || t == IPM_UL) ? -s.l[i] : 0.0
        end
        _ipm_newton!(w.cx, w.cz1, w.cz2, w, s)
        # affine direction: d_s = lambda o lambda
        @inbounds for i in 1:m
            t = w.rt[i]
            w.q1[i] = (t == IPM_U || t == IPM_UL) ? w.lam1[i]^2 : 0.0
            w.q2[i] = (t == IPM_L || t == IPM_UL) ? w.lam2[i]^2 : 0.0
        end
        @inbounds for B in s.socs
            _jprod!(w.q1, w.lam1, w.lam1, B)
        end
        _ipm_direction!(w, s, 1.0, w.tau * w.kappa)
        aa = _ipm_step_length(w, s)
        sigma = (1 - aa)^3
        # combined: d_s = lambda o lambda + (W^{-1} ds_a) o (W dz_a) - sigma mu e
        dta = w.dtau; dka = w.dkappa
        @inbounds for i in 1:m
            t = w.rt[i]
            (t == IPM_U || t == IPM_UL) && (w.q1[i] = w.lam1[i]^2 + w.ds1[i] * w.dz1[i] - sigma * mu)
            (t == IPM_L || t == IPM_UL) && (w.q2[i] = w.lam2[i]^2 + w.ds2[i] * w.dz2[i] - sigma * mu)
        end
        @inbounds for (kk, B) in enumerate(s.socs)
            _blk_mul!(w.tm, w.Winv[kk], w.ds1, B)          # W^{-1} ds
            _blk_mul!(w.tm2, w.W[kk], w.dz1, B)            # W dz
            _jprod!(w.res, w.tm, w.tm2, B)                 # (res as scratch, rows B)
            _jprod!(w.q1, w.lam1, w.lam1, B)
            for i in B
                w.q1[i] += w.res[i]
            end
            w.q1[first(B)] -= sigma * mu
        end
        _ipm_direction!(w, s, 1.0 - sigma, w.tau * w.kappa + dta * dka - sigma * mu)
        a = min(1.0, st.ipm_step_fraction * _ipm_step_length(w, s))
        if a < 0.1 * aa
            # the corrector broke down (its second-order term amplifies the
            # error of an inaccurate KKT solve): take the predictor instead
            @inbounds for i in 1:m
                t = w.rt[i]
                w.q1[i] = (t == IPM_U || t == IPM_UL) ? w.lam1[i]^2 : 0.0
                w.q2[i] = (t == IPM_L || t == IPM_UL) ? w.lam2[i]^2 : 0.0
            end
            @inbounds for B in s.socs
                _jprod!(w.q1, w.lam1, w.lam1, B)
            end
            _ipm_direction!(w, s, 1.0, w.tau * w.kappa)
            a = min(1.0, st.ipm_step_fraction * _ipm_step_length(w, s))
        end
        st.verbose && @printf("      sigma %.2e  affine step %.3e  step %.3e  mu %.2e\n", sigma, aa, a, mu)
        if a < 1e-3 && w.reg < 1e-6
            # the directions are unreliable (inaccurate KKT solves, e.g. a rank
            # deficient P): retry the iteration with more static regularization,
            # which the iterative refinement removes from the solution
            w.reg = min(100 * w.reg, 1e-6)
            st.verbose && @printf("      step collapsed: regularization raised to %.0e\n", w.reg)
            continue
        end
        @inbounds for j in 1:n
            w.x[j] += a * w.dx[j]
        end
        @inbounds for i in 1:m
            w.s1[i] += a * w.ds1[i]; w.z1[i] += a * w.dz1[i]
            w.s2[i] += a * w.ds2[i]; w.z2[i] += a * w.dz2[i]
        end
        w.tau += a * w.dtau
        w.kappa += a * w.dkappa
        # stall: steps collapse when the KKT solves have lost the accuracy the
        # tolerance needs (the caller falls back to the polish and ADMM)
        nsmall = a < 1e-3 ? nsmall + 1 : 0
        if nsmall >= 2
            status = :stalled
            break
        end
    end
    w.iter = k
    status == :solved_polished && return :solved_polished     # s.x, s.y, s.z hold the polished point
    _ipm_to_admm!(w, s)
    return status
end

"The IPM iterate (x, z1 - z2)/tau in the ADMM convention, into the scaled `s.x`, `s.y`, `s.z = Proj(A x)`."
function _ipm_to_admm!(w::IPMWork, s)
    tau = w.tau
    @inbounds for j in 1:s.n
        s.x[j] = w.x[j] / tau
    end
    mul!(s.z, s.A, s.x)
    @inbounds for i in 1:s.m
        t = w.rt[i]
        s.y[i] = (t == IPM_L ? -w.z2[i] : t == IPM_UL ? w.z1[i] - w.z2[i] : t == IPM_FREE ? 0.0 : w.z1[i]) / tau
    end
    _project!(s, s.z)
    return nothing
end

"The violation test of termination.jl at the iterate x / tau (`tm` holds A x)."
function _ipm_violation_ok(w::IPMWork, s)
    @inbounds for i in 1:s.m
        w.tm2[i] = w.tm[i] / w.tau
    end
    v, tol = _violation(s, w.tm2)
    _ipm_residuals!(w, s)                    # restores tm2 (y) and the residuals
    return v <= tol
end

"Primal or dual infeasibility certificate of the iterate (:none, :primal_infeasible, :dual_infeasible)."
function _ipm_infeasible!(w::IPMWork, s, bz::Float64, qx::Float64)
    st = s.settings
    epsi = st.ipm_eps_infeas
    sc = s.scl
    w.kappa > w.tau || return :none
    # primal: b_e'z < 0 and A'y ~ 0 (unscaled up to the common factor cinv)
    if bz < 0
        mul!(w.tn2, transpose(s.A), w.tm2)
        r = 0.0
        @inbounds for j in 1:s.n
            r = max(r, sc.Dinv[j] * abs(w.tn2[j]))
        end
        r <= -epsi * bz && return :primal_infeasible
    end
    if qx < 0
        mul!(w.tn, s.P, w.x)
        r = 0.0
        @inbounds for j in 1:s.n
            r = max(r, sc.Dinv[j] * abs(w.tn[j]))
        end
        if r <= -epsi * qx
            # A_e x + s = r_z + b_e tau ~ 0 (rows unscaled; the cost scale enters q'x)
            rr = 0.0
            @inbounds for i in 1:s.m
                t = w.rt[i]
                e = sc.Einv[i]
                v1 = w.rz1[i] + (t == IPM_SOC ? s.socb[i] : (t == IPM_EQ || t == IPM_U || t == IPM_UL) ? s.u[i] : 0.0) * w.tau
                v2 = w.rz2[i] - ((t == IPM_L || t == IPM_UL) ? s.l[i] : 0.0) * w.tau
                rr = max(rr, e * abs(v1), e * abs(v2))
            end
            rr <= -epsi * sc.cinv * qx && return :dual_infeasible
        end
    end
    return :none
end
