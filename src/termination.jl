# termination.jl: the duality gap test, next to OSQP's residual tests.
#
# OSQP stops when the unscaled residuals are small RELATIVE to the terms they
# are made of,
#
#     ||A x - z||          <= eps_abs + eps_rel max(||A x||, ||z||),
#     ||P x + q + A'y||    <= eps_abs + eps_rel max(||P x||, ||A'y||, ||q||).
#
# When P x and q are large and cancel (a quadratic tracking cost with a large
# weight: the pushed-forward team programs, where a team's cost sums the costs
# of its members, have ||P x|| ~ ||q|| ~ 1e3 against ||A'y|| ~ 4 at the
# optimum), the dual tolerance is set by ||q|| and is orders of magnitude
# looser than the stationarity error that moves the objective: residuals at
# 1e-7 left the objective 1e-5 off. Interior-point codes (Clarabel, PIQP)
# also require a small duality gap. For an ADMM iterate the gap is exact and
# cheap: y lies in the normal cone of C at z (the projection step guarantees it),
# so the support function of C at y is y'z and
#
#     gap = (x'Px + q'x) + y'z  (= x'(P x + q + A'y) - y'(A x - z)),
#
# the primal minus the dual objective at (x, y). The test is Clarabel's,
#
#     |gap| <= eps_abs + eps_rel min(|f_p|, |f_d|),
#
# with min(|f_p|, |f_d|) taken over the objectives with and without the
# constant c of the problem (the objective the caller reports includes it;
# Clarabel's and the benchmark harness's do not; the constant cancels in the
# gap itself). It bounds the
# objective error by the gap up to the dual residual, which is what the
# residual tests alone do not do. Polished points are held to the same test,
# with the support function evaluated explicitly (their multipliers are not
# tied to a projection).
#
# The gap alone is not enough either: the computed dual objective
# -x'Px/2 - S_C(y) is the dual function at y only when P x + q + A'y = 0, and
# in general it is off by r_d'P^+ r_d / 2, which is large when P is badly
# conditioned (the team programs again: large weights along some directions,
# small along others). So with `check_gap` the dual residual is normalized by
# max(||A'y||, ||P x + q||), the two sides of the stationarity equation, instead
# of OSQP's max(||P x||, ||A'y||, ||q||), which the cancelling terms inflate
# (by ~250x on the team programs at abar scale 0.3).

"Primal and dual objectives (unscaled, with the constant) of the scaled ADMM point; needs `Px = P x`."
@inline function _admm_objectives(s, x::Vector{Float64}, z::Vector{Float64}, y::Vector{Float64}, Px::Vector{Float64})
    xPx = dot(x, Px); qx = dot(s.q, x); yz = dot(y, z)
    ci = s.scl.cinv
    return ci * (0.5 * xPx + qx) + s.c0, ci * (-0.5 * xPx - yz) + s.c0
end

"""
Tolerance of the gap test: relative to the smaller of the objectives with and
without the constant `c0`, so that the objective meets eps in both conventions
(the caller's, with the constant; Clarabel's and the benchmark harness's,
without it).
"""
@inline _gap_tol(st, fp, fd, c0 = 0.0) = st.eps_abs + st.eps_rel * min(abs(fp), abs(fd), abs(fp - c0), abs(fd - c0))

"Gap test of the scaled ADMM point (after `_residuals!`, which fills `Px`)."
function _gap_ok(s, x, z, y, Px)
    st = s.settings
    fp, fd = _admm_objectives(s, x, z, y, Px)
    gap = abs(fp - fd)
    s.info.gap = gap
    return !st.check_gap || gap <= _gap_tol(st, fp, fd, s.c0)
end

"""
Support function of C at the scaled multiplier `y`, sum of `u_i y_i` (y_i > 0)
and `l_i y_i` (y_i < 0) over the interval rows and `b_B'y_B` over the SOC
blocks (finite when the signs and the cone membership of `y` are right, which
the polish check tests separately; rows with a wrong sign against an infinite
bound are skipped here).
"""
function _support(s, y::Vector{Float64})
    t = 0.0
    @inbounds for i in 1:s.m
        s.rowtype[i] == ROWT_SOC && continue
        v = y[i]
        if v > 0
            s.u[i] < Inf && (t += s.u[i] * v)
        elseif v < 0
            s.l[i] > -Inf && (t += s.l[i] * v)
        end
    end
    @inbounds for B in s.socs, i in B
        t += s.socb[i] * y[i]
    end
    return t
end

"Duality gap and its tolerance at a polished point (`pPx = P px` filled)."
function _polish_gap(s)
    st = s.settings
    xPx = dot(s.px, s.pPx); qx = dot(s.q, s.px)
    ci = s.scl.cinv
    fp = ci * (0.5 * xPx + qx) + s.c0
    fd = ci * (-0.5 * xPx - _support(s, s.py)) + s.c0
    return abs(fp - fd), _gap_tol(st, fp, fd, s.c0)
end

"Duality gap of the returned scaled point `(x, y)` (after `_residuals!` filled `Px`), unscaled."
function _point_gap(s)
    xPx = dot(s.x, s.Px); qx = dot(s.q, s.x)
    return abs(s.scl.cinv * (xPx + qx + _support(s, s.y)))
end

# Primal feasibility in the problem's own metric. OSQP's primal residual is the
# distance ||A x - Proj_C(A x)|| (row by row, unscaled) against
# eps_abs + eps_rel max(||A x||, ||z||). Callers measure feasibility as the
# violation of the constraints, max(l - a'x, a'x - u) on the interval rows and
# ||s_1|| - s_0 (s = b - A_B x) on the cones, relative to the size of A x and
# of the bounds (`violation`, and the benchmark harness's check). For a cone
# the largest component of the projection residual is about half the
# violation, and the additive tolerance is up to twice the relative one, so a
# point can pass the residual test and violate the constraints by up to ~4 eps.
# Every accepted point (ADMM termination, polish, IPM) also passes
#
#     violation <= max(eps_abs, eps_rel max(||A x||, ||bounds||)).

"Unscaled violation of the constraints at the scaled `Ax` (= A x), and its tolerance."
function _violation(s, Ax::Vector{Float64})
    st = s.settings
    Einv = s.scl.Einv
    v = 0.0; nAx = 0.0; bnd = 0.0
    @inbounds for i in 1:s.m
        e = Einv[i]
        a = e * Ax[i]
        nAx = max(nAx, abs(a))
        s.rowtype[i] == ROWT_SOC && continue
        l = s.l[i]; u = s.u[i]
        l > -Inf && (v = max(v, e * l - a); bnd = max(bnd, abs(e * l)))
        u < Inf && (v = max(v, a - e * u); bnd = max(bnd, abs(e * u)))
    end
    @inbounds for B in s.socs
        i0 = first(B)
        e = Einv[i0]                          # uniform on the block
        ns = 0.0
        for i in (i0+1):last(B)
            ns += (s.socb[i] - Ax[i])^2
            bnd = max(bnd, abs(e * s.socb[i]))
        end
        bnd = max(bnd, abs(e * s.socb[i0]))
        v = max(v, e * (sqrt(ns) - (s.socb[i0] - Ax[i0])))
    end
    return max(v, 0.0), max(st.eps_abs, st.eps_rel * max(nAx, bnd))
end

@inline _violation_ok(s, Ax::Vector{Float64}) = ((v, tol) = _violation(s, Ax); v <= tol)
