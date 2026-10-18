# polish.jl: active-set polish (OSQP Sec. 4 of Stellato et al. 2020), with the
# multiplier signs checked, primal-dual active-set corrections, and a Newton
# polish for second-order cone blocks on their boundary.
#
# Guess which rows are active at the solution from an ADMM iterate (z, y):
# upper if y_i + (z_i - u_i) > 0, lower if y_i + (z_i - l_i) < 0, equality rows
# always. With the active set fixed the QP is an equality-constrained QP whose
# KKT system
#
#     [ P      A_act' ] [ x     ]   [ -q    ]
#     [ A_act  0      ] [ y_act ] = [ b_act ],   y_inactive = 0,
#
# is solved by iterative refinement with a regularized matrix of the SAME
# sparsity pattern as the ADMM KKT matrix,
#
#     [ P + delta I       A'                   ]
#     [ A            -diag(delta on active rows, 1/delta on inactive rows) ],
#
# so only its numerical factorization is recomputed (the ordering and the
# symbolic analysis are shared with the ADMM system), and not even that when
# the active set is the one factored last time (receding horizon). The result
# is accepted when it satisfies the KKT conditions to the termination tolerance:
# primal residual (inactive rows inside their bounds), dual residual, and
# multipliers of the right sign. Otherwise the active set is corrected from the
# polished point by the same rule (a primal-dual active-set step, Hintermueller,
# Ito and Kunisch 2002) and the solve repeated, a bounded number of times.
#
# Second-order cones (b_B - A_B x = s in K, multiplier y_B in K, s'y = 0). A
# block is inactive (s inside, y = 0: its rows are free, (2,2) block -(1/delta) I),
# at the apex (s = 0: an equality block, -delta I), or on the boundary,
# s = tau (1, u), y = eta (1, -u) with ||u|| = 1. In the orthonormal basis
# e_s = (1, u)/sqrt 2, e_y = (1, -u)/sqrt 2, U (the rest) of the block, the
# linearization of that boundary manifold is: no multiplier along e_s, no slack
# along e_y, and y_U = -(eta/tau) s_U (a rotation of u moves s and y in opposite
# directions). That is the KKT row block A_B x - N y = b_B with the symmetric
# positive definite
#
#     N = (1/delta) e_s e_s' + delta e_y e_y' + (tau/eta) U U',
#
# so the polish system stays quasi-definite with the same pattern (the (2,2)
# block of every SOC block is stored dense), and repeating the solve with
# (tau, eta, u) read off the new point is Newton's method on the KKT conditions
# restricted to the boundary (quadratic convergence near a strictly
# complementary solution).

const ACT_SOC_APEX = Int8(5)

"""
    _soc_classify!(s, k, B, w, y, old, band) -> class

Classify SOC block `k` (rows `B`) from the slack `s_B = b_B - w_B` and the
multiplier `y_B`, by the Moreau decomposition of `v = s - y`: at a solution
`s = Proj_K(v)` and `-y = Proj_{-K}(v)` (complementarity), so `v` interior to
the cone means an inactive block (`y = 0`), `v` in the polar cone an active
apex (`s = 0`), and otherwise the block is on its boundary with
`u = v_1 / ||v_1||`, `s = tau (1, u)`, `y = eta (1, -u)`. This is the cone
version of the rule `y + (z - u) > 0` of the interval rows (a primal-dual
active-set step), and unlike a test on `y` alone it moves a block whose slack
the last polish pushed outside the cone back onto the boundary. `band`
(relative to the size of `s` and `y`) is a hysteresis: a block keeps its
previous class `old` (inactive or boundary) while `v` is within the band of
the boundary, which stops weakly active blocks (both `s` on the boundary and
`y ~ 0`) from flipping between iterations and blocking the polish entry.
"""
function _soc_classify!(s::Solver, k::Int, B::UnitRange{Int}, w::Vector{Float64}, y::Vector{Float64},
                        old::Int8 = ACT_NONE, band::Float64 = 0.0)
    i0 = first(B)
    s0 = s.socb[i0] - w[i0]; y0 = y[i0]
    ns = 0.0; ny = 0.0; nv = 0.0
    @inbounds for i in (i0+1):last(B)
        si = s.socb[i] - w[i]; yi = y[i]
        ns += si * si; ny += yi * yi; nv += (si - yi)^2
    end
    ns = sqrt(ns); ny = sqrt(ny); nv = sqrt(nv)
    v0 = s0 - y0
    scale = max(abs(s0) + ns, abs(y0) + ny)
    hb = band * scale
    thr = old == ACT_SOC_IN ? -hb : (old == ACT_SOC_ON ? hb : 0.0)
    v0 - nv > thr && return ACT_SOC_IN
    # the parts along e_s = (1, u)/sqrt 2 (slack) and e_y = (1, -u)/sqrt 2 (multiplier)
    tauv = 0.5 * (v0 + nv)
    tauv <= 1e-8 * max(1.0, scale) && return ACT_SOC_APEX
    if nv > 0
        @inbounds for i in (i0+1):last(B)
            s.soc_u[i] = ((s.socb[i] - w[i]) - y[i]) / nv
        end
    elseif length(B) > 1
        @inbounds for i in (i0+1):last(B)
            s.soc_u[i] = 0.0
        end
        s.soc_u[i0+1] = 1.0
    end
    su = 0.0; yu = 0.0
    @inbounds for i in (i0+1):last(B)
        su += s.soc_u[i] * (s.socb[i] - w[i])
        yu += s.soc_u[i] * y[i]
    end
    tau = 0.5 * (s0 + su)
    eta = 0.5 * (y0 - yu)
    s.soc_tau[k] = tau > 0 ? tau : tauv
    s.soc_eta[k] = max(eta, 0.0)
    return ACT_SOC_ON
end

"""
Guess the active set from a point `(z, y)` (an ADMM iterate, or an
interior-point solution in the ADMM convention). `band` is the hysteresis of
the SOC classification (`polish_soc_band` during the ADMM iterations, where
the guess must be stable to trigger the polish).
"""
function _guess_active!(s::Solver, z::Vector{Float64}, y::Vector{Float64}, band::Float64 = 0.0)
    act = s.act; l = s.l; u = s.u; rt = s.rowtype
    @inbounds for i in 1:s.m
        t = rt[i]
        if t == ROWT_EQ
            act[i] = ACT_EQ
        elseif t == ROWT_INEQ
            yi = y[i]; zi = z[i]
            act[i] = yi + (zi - u[i]) > 0 ? ACT_UPPER : (yi + (zi - l[i]) < 0 ? ACT_LOWER : ACT_NONE)
        elseif t == ROWT_FREE
            act[i] = ACT_NONE
        end
    end
    @inbounds for (k, B) in enumerate(s.socs)
        a = _soc_classify!(s, k, B, z, y, act[first(B)], band)
        for i in B
            act[i] = a
        end
    end
    return act
end

@inline _is_active(a::Int8) = a == ACT_LOWER || a == ACT_UPPER || a == ACT_EQ || a == ACT_SOC_APEX || a == ACT_SOC_ON

"Entry (a, b) of the boundary block matrix N of SOC block `k` (rows `B`)."
@inline function _soc_N(s::Solver, k::Int, B::UnitRange{Int}, a::Int, b::Int, del::Float64)
    i0 = first(B)
    r = 0.7071067811865476
    esa = a == 1 ? r : r * s.soc_u[i0+a-1]; esb = b == 1 ? r : r * s.soc_u[i0+b-1]
    eya = a == 1 ? r : -r * s.soc_u[i0+a-1]; eyb = b == 1 ? r : -r * s.soc_u[i0+b-1]
    kap = clamp(s.soc_tau[k] / max(s.soc_eta[k], 1e-300), del, 1 / del)
    return (1 / del - kap) * esa * esb + (del - kap) * eya * eyb + (a == b ? kap : 0.0)
end

function _polish_factor!(s::Solver)
    act = s.act
    same = s.pol_valid
    if same
        @inbounds for i in 1:s.m
            if _is_active(act[i]) != s.pol_act[i] || act[i] == ACT_SOC_ON
                same = false
                break
            end
        end
    end
    same && return false
    del = s.settings.polish_delta
    @inbounds for j in 1:s.n
        s.tn[j] = s.Pdiag[j] + del
    end
    @inbounds for i in 1:s.m
        a = _is_active(act[i])
        s.pdiag[i] = a ? del : 1.0 / del
        s.pol_act[i] = a
    end
    set_diagonal!(s.pol.K, s.pol.diag_idx, s.tn, s.pdiag)
    nz = nonzeros(s.pol.K)
    @inbounds for (k, B) in enumerate(s.socs)
        I = s.soc_idx[k]
        d = length(B)
        if act[first(B)] == ACT_SOC_ON
            for b in 1:d, a in 1:b
                nz[I[a, b]] = -_soc_N(s, k, B, a, b, del)
            end
        else
            for b in 1:d, a in 1:(b-1)
                nz[I[a, b]] = 0.0
            end
        end
    end
    refactor!(s.pol)
    s.pol_valid = true
    s.info.polish_factorizations += 1
    return true
end

"Residual of SOC block `k` on its boundary for the exact target system (see the header)."
@inline function _soc_residual!(res, s::Solver, k::Int, B::UnitRange{Int}, n::Int, del::Float64)
    i0 = first(B)
    r = 0.7071067811865476
    # projections of y on e_s and e_y, of the slack residual b - A x on e_s
    ys = r * s.py[i0]; yy = r * s.py[i0]; gs = r * (s.socb[i0] - s.pAx[i0])
    @inbounds for i in (i0+1):last(B)
        ys += r * s.soc_u[i] * s.py[i]
        yy -= r * s.soc_u[i] * s.py[i]
        gs += r * s.soc_u[i] * (s.socb[i] - s.pAx[i])
    end
    kap = clamp(s.soc_tau[k] / max(s.soc_eta[k], 1e-300), del, 1 / del)
    @inbounds for i in B
        es = i == i0 ? r : r * s.soc_u[i]
        ey = i == i0 ? r : -r * s.soc_u[i]
        g = s.socb[i] - s.pAx[i]
        # (I - e_s e_s')(b - Ax) + e_s (e_s'y)/delta + kap (I - e_s e_s' - e_y e_y') y
        res[n+i] = (g - es * gs) + es * ys / del + kap * (s.py[i] - es * ys - ey * yy)
    end
    return nothing
end

"""
Solve the polish system for the current `act` into `px`, `py` (scaled), by
`refine` steps of iterative refinement against the unregularized target
system for the current active set and boundary parameters.
"""
function _polish_solve!(s::Solver; refine::Int = s.settings.polish_refine_iter)
    n, m = s.n, s.m
    act = s.act
    rhs = s.prhs; sol = s.psol; res = s.pres
    del = s.settings.polish_delta
    @inbounds for j in 1:n
        rhs[j] = -s.q[j]
    end
    @inbounds for i in 1:m
        a = act[i]
        rhs[n+i] = a == ACT_LOWER || a == ACT_EQ ? s.l[i] : a == ACT_UPPER ? s.u[i] :
                   (a == ACT_SOC_ON || a == ACT_SOC_APEX) ? s.socb[i] : 0.0
    end
    copyto!(sol, rhs)
    solve!(s.pol, sol)
    for _ in 1:refine
        # residual of the unregularized target system
        @inbounds for j in 1:n
            s.px[j] = sol[j]
        end
        @inbounds for i in 1:m
            s.py[i] = sol[n+i]
        end
        mul!(s.pPx, s.P, s.px)
        mul!(s.pAty, transpose(s.A), s.py)
        mul!(s.pAx, s.A, s.px)
        @inbounds for j in 1:n
            res[j] = rhs[j] - s.pPx[j] - s.pAty[j]
        end
        @inbounds for i in 1:m
            res[n+i] = s.pol_act[i] ? rhs[n+i] - s.pAx[i] : s.py[i] / del
        end
        @inbounds for (k, B) in enumerate(s.socs)
            act[first(B)] == ACT_SOC_ON && _soc_residual!(res, s, k, B, n, del)
        end
        solve!(s.pol, res)
        @inbounds for k in eachindex(sol)
            sol[k] += res[k]
        end
    end
    @inbounds for j in 1:n
        s.px[j] = sol[j]
    end
    @inbounds for i in 1:m
        s.py[i] = s.pol_act[i] ? sol[n+i] : 0.0
    end
    # no multiplier along e_s on a boundary block
    r = 0.7071067811865476
    @inbounds for B in s.socs
        i0 = first(B)
        act[i0] == ACT_SOC_ON || continue
        ys = r * s.py[i0]
        for i in (i0+1):last(B)
            ys += r * s.soc_u[i] * s.py[i]
        end
        for i in B
            s.py[i] -= ys * (i == i0 ? r : r * s.soc_u[i])
        end
    end
    return nothing
end

"""
Check the polished point against the termination tolerance (primal and dual
residuals, multiplier signs, and for SOC blocks dual cone membership and
complementarity). Fills `pz` with the projection of `A px`.
"""
function _polish_check(s::Solver)
    st = s.settings
    mul!(s.pAx, s.A, s.px)
    copyto!(s.pz, s.pAx)
    _project!(s, s.pz)
    pr, dr, pn, dn = _residuals!(s, s.px, s.pz, s.py, s.pAx, s.pPx, s.pAty)
    E = s.scl.E; Einv = s.scl.Einv; cinv = s.scl.cinv
    sv = 0.0; ny = 0.0
    @inbounds for i in 1:s.m
        a = s.act[i]
        yi = cinv * E[i] * s.py[i]
        ny = max(ny, abs(yi))
        if a == ACT_LOWER
            sv = max(sv, yi)
        elseif a == ACT_UPPER
            sv = max(sv, -yi)
        end
    end
    @inbounds for B in s.socs
        i0 = first(B)
        (s.act[i0] == ACT_SOC_ON || s.act[i0] == ACT_SOC_APEX) || continue
        f = cinv * E[i0]
        sv = max(sv, f * soc_distance(s.py, B))
        sy = 0.0; smax = 0.0
        for i in B
            si = Einv[i] * (s.socb[i] - s.pz[i])
            sy += si * f * s.py[i]
            smax = max(smax, abs(si))
        end
        sv = max(sv, abs(sy) / max(1.0, smax))
    end
    es = st.eps_abs + st.eps_rel * ny
    gap, gtol = _polish_gap(s)
    gmerit = st.check_gap ? gap / gtol : 0.0
    viol, vtol = _violation(s, s.pAx)          # the constraints' own metric (termination.jl)
    ok = pr <= _eps_prim(st, pn) && dr <= _eps_dual(st, dn) && sv <= es && gmerit <= 1 && viol <= vtol
    merit = max(pr / _eps_prim(st, pn), dr / _eps_dual(st, dn), sv / es, gmerit, viol / vtol)
    ok && (s.info.gap = gap)
    return ok, pr, dr, merit
end

"Primal-dual active-set correction from the polished point; returns true if `act` changed."
function _correct_active!(s::Solver)
    changed = false
    act = s.act
    @inbounds for i in 1:s.m
        s.rowtype[i] == ROWT_INEQ || continue
        yi = s.py[i]; zi = s.pAx[i]
        a = yi + (zi - s.u[i]) > 0 ? ACT_UPPER : (yi + (zi - s.l[i]) < 0 ? ACT_LOWER : ACT_NONE)
        if a != act[i]
            act[i] = a
            changed = true
        end
    end
    return changed
end

"""
Newton update of the SOC blocks from the polished point: reclassify every
block (no hysteresis) and read the boundary parameters off the new point.
Returns `(class_changed, any_on)`.
"""
function _correct_soc!(s::Solver)
    changed = false; anyon = false
    @inbounds for (k, B) in enumerate(s.socs)
        old = s.act[first(B)]
        a = _soc_classify!(s, k, B, s.pAx, s.py)
        a != old && (changed = true)
        a == ACT_SOC_ON && (anyon = true)
        for i in B
            s.act[i] = a
        end
    end
    return changed, anyon
end

function _try_polish!(s::Solver; restart::Bool = true, corrections::Int = s.settings.polish_corrections, newton::Int = -1)
    t0 = time_ns()
    info = s.info
    st = s.settings
    has_on = false
    @inbounds for B in s.socs
        s.act[first(B)] == ACT_SOC_ON && (has_on = true; break)
    end
    copyto!(s.act_fail, s.act)       # remembered as failed unless accepted below
    ok = false
    last_merit = Inf
    maxc = isempty(s.socs) ? corrections : max(corrections, newton >= 0 ? newton : st.polish_soc_newton)
    prev = Inf
    prev_merit = Inf
    # A semismooth Newton method on the KKT conditions of every cone: each
    # attempt solves the polish system for the current active set and boundary
    # parameters, then reclassifies the interval rows (primal-dual active-set
    # step) and the SOC blocks (Moreau rule, new boundary parameters).
    #   * a new classification needs a factorization; after the first
    #     correction, corrections continue only while they halve the KKT merit;
    #   * the same classification with new boundary parameters is a Newton step
    #     (a factorization: the system's 1/delta terms along e_s make an
    #     outdated factorization a poor preconditioner, so chord steps are kept
    #     for the tightening of an accepted point, `_polish_tighten!`); a step
    #     that does not cut the primal residual tenfold ends the polish.
    # At most `maxc` steps; on failure the caller falls back (ADMM restart,
    # more ADMM or IPM iterations).
    chord = false
    for attempt in 0:maxc
        chord || _polish_factor!(s)
        _polish_solve!(s; refine = chord ? 3 * max(st.polish_refine_iter, 1) : st.polish_refine_iter)
        info.polish_attempts += 1
        ok, pr, dr, merit = _polish_check(s)
        st.verbose && @printf("      polish %d%s: ok %s  pr %.2e  dr %.2e  merit %.2e\n", attempt, chord ? " (chord)" : "", ok, pr, dr, merit)
        last_merit = merit
        if ok
            copyto!(s.x, s.px); copyto!(s.y, s.py); copyto!(s.z, s.pz)
            info.prim_res = pr; info.dual_res = dr
            info.polish = :success
            info.polish_iter = info.iter
            _polish_tighten!(s, pr)
            break
        end
        attempt == maxc && break
        cs, anyon = isempty(s.socs) ? (false, false) : _correct_soc!(s)
        ci = attempt < corrections ? _correct_active!(s) : false
        if cs || ci
            attempt >= 1 && merit > 0.5 * prev_merit && break
            chord = false
        elseif anyon
            # same classes, new boundary parameters: a Newton step, which must
            # cut the primal residual tenfold to continue
            pr > 0.1 * prev && break
        else
            break
        end
        prev = pr
        prev_merit = merit
    end
    s.has_fail = !ok
    if !ok && restart && st.polish_restart
        # restart only from a polished point that is closer to optimal than the
        # current iterate (merit: the larger residual relative to its tolerance)
        pr0, dr0, pn0, dn0 = _residuals!(s, s.x, s.z, s.y, s.Ax, s.Px, s.Aty)
        merit0 = max(pr0 / _eps_prim(st, pn0), dr0 / _eps_dual(st, dn0))
        last_merit < merit0 && _restart_from_polish!(s)
    end
    info.polish_time += (time_ns() - t0) / 1e9
    return ok
end

"""
An accepted polish with boundary SOC blocks is exact only up to the Newton
linearization: when its primal residual `pr` is above 10% of the tolerance, one
chord step (new boundary parameters, the same factorization, solves only)
usually gains several digits; it is kept if it passes the check and is better.
"""
function _polish_tighten!(s::Solver, pr::Float64)
    st = s.settings
    mul!(s.Ax, s.A, s.x)
    pn = 0.0
    @inbounds for i in 1:s.m
        pn = max(pn, abs(s.scl.Einv[i] * s.Ax[i]))
    end
    viol, vtol = _violation(s, s.Ax)
    pr <= 0.1 * _eps_prim(st, pn) && viol <= 0.1 * vtol && return false
    any(B -> s.act[first(B)] == ACT_SOC_ON, s.socs) || return false
    cs, _ = _correct_soc!(s)
    cs && return false                    # a class changed: the accepted point stays
    _polish_solve!(s; refine = 2 * max(st.polish_refine_iter, 1))
    s.info.polish_attempts += 1
    ok2, pr2, dr2, _ = _polish_check(s)
    st.verbose && @printf("      polish tighten: ok %s  pr %.2e\n", ok2, pr2)
    if ok2 && pr2 < pr
        copyto!(s.x, s.px); copyto!(s.y, s.py); copyto!(s.z, s.pz)
        s.info.prim_res = pr2; s.info.dual_res = dr2
        return true
    end
    return false
end

"""
Restart ADMM from a rejected polished point `(px, py)`: `x = px`, and the pair
`(z, y)` from the Moreau decomposition of `v = A px + R^{-1} py`,
`z = Proj_C(v)`, `y = R (v - z)`, so that `y` lies in the normal cone of `C` at
`z` (the invariant of an ADMM iterate). Rows the polish violated enter with a
positive multiplier estimate, rows with a multiplier of the wrong sign leave:
the active-set correction, smoothed by rho, carried out by the next ADMM
iterations.
"""
function _restart_from_polish!(s::Solver)
    copyto!(s.x, s.px)
    @inbounds for i in 1:s.m
        s.z[i] = s.pAx[i] + s.rhoinv[i] * s.py[i]
    end
    copyto!(s.w, s.z)
    _project!(s, s.z)
    @inbounds for i in 1:s.m
        s.y[i] = s.rhovec[i] * (s.w[i] - s.z[i])
    end
    return nothing
end
