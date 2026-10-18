# polish.jl: active-set polish (OSQP Sec. 4 of Stellato et al. 2020), with the
# multiplier signs checked and primal-dual active-set corrections.
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
# Second-order cones: a block whose slack is strictly inside the cone with a
# zero multiplier is inactive (its rows are free in the polish system); a block
# on its boundary makes the active set non-polyhedral and the polish is skipped.

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
    @inbounds for B in s.socs
        i0 = first(B)
        st0 = s.socb[i0] - z[i0]
        ns = 0.0; ny = y[i0]^2
        for i in (i0+1):last(B)
            d = s.socb[i] - z[i]
            ns += d * d
            ny += y[i]^2
        end
        gap = st0 - sqrt(ns)
        a = sqrt(ny) > gap ? ACT_SOC_ON : ACT_SOC_IN
        for i in B
            act[i] = a
        end
    end
    return act
end

@inline _is_active(a::Int8) = a == ACT_LOWER || a == ACT_UPPER || a == ACT_EQ

function _polish_factor!(s::Solver)
    act = s.act
    same = s.pol_valid
    if same
        @inbounds for i in 1:s.m
            if _is_active(act[i]) != s.pol_act[i]
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
    refactor!(s.pol)
    s.pol_valid = true
    s.info.polish_factorizations += 1
    return true
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
        rhs[n+i] = a == ACT_LOWER || a == ACT_EQ ? s.l[i] : (a == ACT_UPPER ? s.u[i] : 0.0)
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
    return nothing
end

"""
Check the polished point against the termination tolerance (primal and dual
residuals, multiplier signs). Fills `pz` with the projection of `A px`.
"""
function _polish_check(s::Solver)
    st = s.settings
    mul!(s.pAx, s.A, s.px)
    copyto!(s.pz, s.pAx)
    _project!(s, s.pz)
    pr, dr, pn, dn = _residuals!(s, s.px, s.pz, s.py, s.pAx, s.pPx, s.pAty)
    E = s.scl.E; cinv = s.scl.cinv
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
    ok = pr <= _eps_prim(st, pn) && dr <= _eps_dual(st, dn) && sv <= st.eps_abs + st.eps_rel * ny
    return ok, pr, dr
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

function _try_polish!(s::Solver; restart::Bool = true)
    t0 = time_ns()
    info = s.info
    @inbounds for i in 1:s.m
        if s.act[i] == ACT_SOC_ON
            info.polish = :skipped
            return false
        end
    end
    copyto!(s.act_fail, s.act)       # remembered as failed unless accepted below
    ok = false
    for attempt in 0:s.settings.polish_corrections
        _polish_factor!(s)
        _polish_solve!(s)
        info.polish_attempts += 1
        ok, pr, dr = _polish_check(s)
        if ok
            copyto!(s.x, s.px); copyto!(s.y, s.py); copyto!(s.z, s.pz)
            info.prim_res = pr; info.dual_res = dr
            info.polish = :success
            info.polish_iter = info.iter
            break
        end
        attempt == s.settings.polish_corrections && break
        _correct_active!(s) || break
    end
    s.has_fail = !ok
    !ok && restart && s.settings.polish_restart && _restart_from_polish!(s)
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
