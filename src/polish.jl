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

"Classify SOC block `k` (rows `B`) from the slack `b - w` and multiplier `y`; set its boundary parameters."
function _soc_classify!(s::Solver, k::Int, B::UnitRange{Int}, w::Vector{Float64}, y::Vector{Float64})
    i0 = first(B)
    s0 = s.socb[i0] - w[i0]; y0 = y[i0]
    ns = 0.0; nyv = 0.0
    @inbounds for i in (i0+1):last(B)
        d = s.socb[i] - w[i]
        ns += d * d
        nyv += y[i] * y[i]
    end
    ns = sqrt(ns); nyv = sqrt(nyv)
    ynorm = sqrt(y0 * y0 + nyv * nyv)
    gap = s0 - ns
    if ynorm <= max(gap, 0.0)
        return ACT_SOC_IN
    end
    tau = max(0.5 * (s0 + ns), 0.0)
    eta = max(0.5 * (y0 + nyv), 0.0)
    if tau <= 1e-8 * max(1.0, eta)
        return ACT_SOC_APEX
    end
    # the multiplier along (1, -u_s), u_s = s_1/||s_1||: a negative value means
    # the boundary constraint pulls the wrong way and the block is inactive
    if ns > 0
        ys = y0
        @inbounds for i in (i0+1):last(B)
            ys -= (s.socb[i] - w[i]) / ns * y[i]
        end
        ys <= 0 && return ACT_SOC_IN
    end
    # u along s_1 / tau - y_1 / eta (both point along u at a boundary solution)
    nu = 0.0
    ft = 1.0 / tau; fe = eta > 1e-12 * tau ? 1.0 / eta : 0.0
    @inbounds for i in (i0+1):last(B)
        v = (s.socb[i] - w[i]) * ft - y[i] * fe
        s.soc_u[i] = v
        nu += v * v
    end
    nu = sqrt(nu)
    if nu > 0
        @inbounds for i in (i0+1):last(B)
            s.soc_u[i] /= nu
        end
    elseif length(B) > 1
        s.soc_u[i0+1] = 1.0
    end
    s.soc_tau[k] = tau
    s.soc_eta[k] = eta
    return ACT_SOC_ON
end

function _guess_active!(s::Solver, z::Vector{Float64}, y::Vector{Float64})
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
        a = _soc_classify!(s, k, B, z, y)
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

"Solve the polish system for the current `act` into `px`, `py` (scaled)."
function _polish_solve!(s::Solver)
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
    for _ in 1:s.settings.polish_refine_iter
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
    ok = pr <= _eps_prim(st, pn) && dr <= _eps_dual(st, dn) && sv <= es
    merit = max(pr / _eps_prim(st, pn), dr / _eps_dual(st, dn), sv / es)
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

"Newton update of the SOC blocks from the polished point; returns true if any block is on its boundary or changed class."
function _correct_soc!(s::Solver)
    changed = false
    @inbounds for (k, B) in enumerate(s.socs)
        old = s.act[first(B)]
        a = _soc_classify!(s, k, B, s.pAx, s.py)
        (a != old || a == ACT_SOC_ON) && (changed = true)
        for i in B
            s.act[i] = a
        end
    end
    return changed
end

function _try_polish!(s::Solver; restart::Bool = true)
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
    maxc = has_on ? max(st.polish_corrections, st.polish_soc_newton) : st.polish_corrections
    prev = Inf
    prev_merit = Inf
    for attempt in 0:maxc
        _polish_factor!(s)
        _polish_solve!(s)
        info.polish_attempts += 1
        ok, pr, dr, merit = _polish_check(s)
        last_merit = merit
        st.verbose && @printf("    polish attempt %d: merit %.2e, %d active rows\n", attempt, merit, count(s.pol_act))
        # Newton on the SOC boundary converges fast near the solution or not at
        # all: give up when a step does not cut the primal residual tenfold
        if !ok && has_on && attempt >= st.polish_corrections
            pr > 0.1 * prev && break
        end
        # an active-set correction that does not halve the merit will not converge
        # within the budget: stop paying factorizations for it
        !ok && attempt >= 1 && merit > 0.5 * prev_merit && break
        prev = pr
        prev_merit = merit
        if ok
            copyto!(s.x, s.px); copyto!(s.y, s.py); copyto!(s.z, s.pz)
            info.prim_res = pr; info.dual_res = dr
            info.polish = :success
            info.polish_iter = info.iter
            break
        end
        attempt == maxc && break
        changed = isempty(s.socs) ? false : _correct_soc!(s)
        attempt < st.polish_corrections && (changed |= _correct_active!(s))
        changed || break
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
