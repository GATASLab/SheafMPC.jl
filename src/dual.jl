# dual.jl: a dense active-set path for small polyhedral problems, in the space
# of the inequality multipliers (a Schur complement of the KKT system).
#
# Split the rows of the scaled problem into equality rows E, inequality rows I
# (interval rows that are neither equalities nor free) and free rows. With
#
#     K11 = [ P + delta I    A_E'       ]      (the inequality rows enter K11 as
#           [ A_E           -delta I    ]       decoupled rows, -1/delta)
#
# factored once in `setup`, the equality-constrained QP on an active set
# A of I (each active row at its upper or lower bound c_A),
#
#     P x + q + A_E'y_E + A_A'y_A = 0,   A_E x = b_E,   A_A x = c_A,
#
# reduces to a dense system in y_A alone. Let xbar solve the problem with the
# equality rows only ([xbar; ybar_E] = K11^{-1} [-q; b_E]), g = A_I xbar, and
#
#     Z = A_I (K11^{-1})_xx A_I'   (dense, |I| x |I|, positive semidefinite:
#                                  the inequality rows' operator on null(A_E)),
#
# the same operator whose extreme eigenvalues give the spectral rho (rho.jl).
# Then y_A solves (Z_AA + delta I) y_A = g_A - c_A, and A_I x = g - Z_IA y_A:
# once Z is known, a new active set costs a dense Cholesky factorization of
# size |A| and a product with Z, and no sparse factorization or solve.
#
# The active set is found by primal-dual active-set iterations (Hintermueller,
# Ito and Kunisch 2002; the rule of `_correct_active!`): row i is active at its
# upper bound if y_i + (a_i'x - u_i) > 0, at its lower bound if
# y_i + (a_i'x - l_i) < 0, and inactive otherwise; a repeated active set is the
# solution of the QP. Started from xbar (no inequality active) they converge in
# a few iterations on most MPC problems; they can cycle, and they meet
# dependent active rows (delta keeps the factorization defined) and infeasible
# problems (no fixed point), so every attempt is bounded (`dual_iter`
# iterations, a budget of operations) and a failure falls back to ADMM, which
# seeds the same iteration from its own active-set guess every `dual_interval`
# iterations, and on convergence before the sparse polish. Warm solves seed it
# with the active set of the last accepted solution.
#
# The Cholesky factor of Z_AA + delta I is updated, not recomputed: a row that
# leaves the active set is deleted (a rank-one update of the trailing block), a
# row that enters is appended (a triangular solve), each O(|A|^2); a repeated
# active set (receding horizon) costs nothing. Z is built in `setup` when its
# |I| solves fit `dual_setup_budget`; otherwise a column is computed when its
# row first enters an active set and kept for later solves.
#
# The accepted point is refined against the unregularized KKT system of its
# active set (two K11 solves per step) and checked exactly like a polish
# (`_polish_check`).

mutable struct DualWork
    sys::QDLDLSystem             # K11 (same pattern and ordering as the ADMM system)
    At::SpMat                    # transpose of the scaled A (rows of A as columns)
    rows::Vector{Int}            # the inequality rows
    Z::Matrix{Float64}
    zok::Vector{Bool}            # columns of Z computed so far
    R::Matrix{Float64}           # upper Cholesky factor of Z_AA + delta I, order of `act`
    act::Vector{Int}             # active positions (into `rows`), factor order
    na::Int                      # length of the active list
    nfac::Int                    # leading columns of R that are valid for `act`
    keep::Vector{Int}
    mark::Vector{Bool}
    side::Vector{Int8}           # per position: 1 upper, -1 lower, 0 inactive
    nside::Vector{Int8}
    pside::Vector{Int8}          # two iterations back (cycle detection)
    g::Vector{Float64}
    v::Vector{Float64}
    y::Vector{Float64}
    w::Vector{Float64}           # dense right-hand side / solution, length |I|
    dy::Vector{Float64}
    xbar::Vector{Float64}        # K11^{-1} [-q; b_E; 0]
    t::Vector{Float64}
    t2::Vector{Float64}
    xbar_ok::Bool                # xbar holds the current q and b_E
    t_fac::Float64               # seconds of a sparse factorization of K11 (measured; the IPM estimate)
    t_solve::Float64             # seconds of a solve with K11 (measured)
    fac_fma::Float64             # multiply-adds of a factorization of K11 and of a solve (from the factor's
    solve_fma::Float64           # column counts: the deterministic cost model of the budgets)
    spent::Float64               # multiply-adds of the current attempt (estimated)
    budget::Float64              # its budget
    t_build::Float64             # seconds spent building Z in setup
    iters::Int                   # active-set iterations of the last solve
    fails::Int                   # consecutive solves in which the path failed (the backoff)
    toobig::Bool                 # an attempt of this solve ran out of budget: the sparse polish takes over
    accepted::Bool               # this solve's point came from the dense path
    tried::Bool                  # this solve made an attempt
    spent_solve::Float64         # work of this solve's attempts (shares one budget of two attempts)
    last_dense::Bool             # so did the last accepted one (its factor is cached)
    cols::Int                    # factor columns computed in the last solve (statistics)
    lastchg::Int                 # changes of the last active-set iteration of an attempt
    stale::Int                   # 0; 1: new matrix values since the last solve; 2: K11 to refactor
    full::Bool                   # Z is built whole (in setup, and again by `_dual_refresh!`)
end

"Multiply-adds per second of a sparse triangular solve assumed by the setup budget."
const DUAL_SOLVE_RATE = 1.5e9
"Cost of a dense multiply-add (contiguous, vectorized) relative to one of a sparse solve, in the budgets."
const DUAL_DENSE_WEIGHT = 0.35

"""
The rows the dense path works on (interval rows that are not equalities or
free), or `nothing` when the problem has second-order cones.
"""
function _dual_rows(s::Solver)
    isempty(s.socs) || return nothing
    rows = Int[]
    @inbounds for i in 1:s.m
        s.rowtype[i] == ROWT_INEQ && push!(rows, i)
    end
    return rows
end

"Fill the diagonal of `K` with the values of K11 (see the header)."
function _k11_values!(s::Solver, K::SpMat, diag_idx::Vector{Int})
    del = s.settings.dual_delta
    nz = nonzeros(K)
    @inbounds for j in 1:s.n
        nz[diag_idx[j]] = s.Pdiag[j] + del
    end
    @inbounds for i in 1:s.m
        nz[diag_idx[s.n+i]] = s.rowtype[i] == ROWT_EQ ? -del : -1.0 / del
    end
    return K
end

_system_perm(S::QDLDLSystem) = S.perm
_system_perm(S::BlockLDLSystem) = S.F.S.perm
_system_perm(S::ChordalSystem) = S.perm
_system_perm(S::LinearSystem) = nothing

"""
    _dual_setup!(s) -> DualWork or nothing

Factor K11 and build Z when the dense path is enabled and its size is within
the limits of `settings` (`dual`, `dual_max_rows`, `dual_setup_budget`).
"""
function _dual_setup!(s::Solver)
    st = s.settings
    st.dual == :off && return nothing
    st.dual in (:auto, :on) || throw(ArgumentError("unknown dual setting $(st.dual) (use :auto, :on or :off)"))
    rows = _dual_rows(s)
    (rows === nothing || isempty(rows)) && return nothing
    mi = length(rows)
    st.dual == :auto && mi > st.dual_max_rows && return nothing
    K = copy(s.kkt.K)
    _k11_values!(s, K, s.kkt.diag_idx)
    perm = _system_perm(s.kkt)
    sys = perm === nothing ? QDLDLSystem(K, s.kkt.diag_idx; logical = true) :
          QDLDLSystem(K, s.kkt.diag_idx; perm = perm, logical = true)
    t0 = time_ns()
    refactor!(sys)
    t_fac = (time_ns() - t0) / 1e9
    ffma, sfma = _ldl_fma(sys)
    N = s.n + s.m
    At = SpMat(sparse(transpose(s.A)))
    w = DualWork(sys, At, rows, zeros(mi, mi), fill(false, mi), zeros(mi, mi), zeros(Int, mi), 0, 0, zeros(Int, mi),
                 fill(false, mi), zeros(Int8, mi), zeros(Int8, mi), zeros(Int8, mi),
                 zeros(mi), zeros(mi), zeros(mi), zeros(mi), zeros(mi),
                 zeros(N), zeros(N), zeros(N), false, t_fac, Inf, ffma, sfma, 0.0, 0.0, 0.0, 0, 0, false, 0, false, false, false, 0.0, 0, 0, false)
    # Z costs one solve per inequality row: all of them in setup when that fits
    # the budget (`dual_setup_budget` seconds), otherwise each column when its
    # row first enters an active set (kept for later solves)
    t1 = time_ns()
    for c in 1:min(2, mi)
        ts = time_ns()
        _dual_column!(w, c)
        w.t_solve = min(w.t_solve, (time_ns() - ts) / 1e9)
    end
    if st.dual == :on || mi * sfma / DUAL_SOLVE_RATE <= st.dual_setup_budget
        w.full = true
        _dual_build!(w, 3)
    end
    w.t_build = (time_ns() - t1) / 1e9
    return w
end

"""
Multiply-adds of a numerical LDLt factorization of K11 (the sum of the squared
column counts of L) and of a solve (twice the nonzeros of L, plus the diagonal).
"""
function _ldl_fma(S::QDLDLSystem)
    f = 0.0
    @inbounds for j in 1:S.Ln
        c = S.Lp[j+1] - S.Lp[j]
        f += c * (c + 1) / 2
    end
    return f, 2.0 * length(S.Lx) + S.Ln
end

"Columns `c0:end` of Z by blocked solves."
function _dual_build!(w::DualWork, c0::Int = 1)
    mi = length(w.rows)
    X = zeros(DUAL_BLOCK, size(w.sys.K, 1))
    for c in c0:DUAL_BLOCK:mi
        _dual_columns!(w, c:min(c + DUAL_BLOCK - 1, mi), X)
    end
    return w
end

"Right-hand sides per blocked solve when Z is built in `setup`."
const DUAL_BLOCK = 8

"""
Columns `cs` of Z (at most `DUAL_BLOCK`) by one blocked solve with K11: the
right-hand sides are the rows of `X` (`DUAL_BLOCK x N`), so every entry of L
updates them all with one contiguous multiply-add, about three times faster
than as many single solves.
"""
function _dual_columns!(w::DualWork, cs::AbstractVector{Int}, X::Matrix{Float64})
    S = w.sys; At = w.At; rv = rowvals(At); nz = nonzeros(At)
    nb = length(cs)
    fill!(X, 0.0)
    ip = S.F.iperm === nothing ? nothing : S.F.iperm
    p = S.perm
    # X[b, k] = (P b_col)[k]: the right-hand side of column cs[b] in the permuted order
    i0 = S.Ln
    @inbounds for (b, c) in enumerate(cs)
        for k in nzrange(At, w.rows[c])
            j = rv[k]
            pj = ip === nothing ? j : ip[j]
            X[b, pj] = nz[k]
            i0 = min(i0, pj)
        end
    end
    Lp = S.Lp; Li = S.Li; Lx = S.Lx; Dinv = S.Dinv; n = S.Ln
    @inbounds for i in i0:n                       # L y = b (sparse right-hand sides: skip zero rows)
        nzrow = false
        for b in 1:DUAL_BLOCK
            nzrow |= X[b, i] != 0.0
        end
        nzrow || continue
        for t in Lp[i]:(Lp[i+1]-1)
            r = Li[t]; v = Lx[t]
            @simd for b in 1:DUAL_BLOCK
                X[b, r] -= v * X[b, i]
            end
        end
    end
    @inbounds for i in 1:n                        # D z = y
        d = Dinv[i]
        @simd for b in 1:DUAL_BLOCK
            X[b, i] *= d
        end
    end
    @inbounds for i in n:-1:1                     # L' x = z
        for t in Lp[i]:(Lp[i+1]-1)
            r = Li[t]; v = Lx[t]
            @simd for b in 1:DUAL_BLOCK
                X[b, i] -= v * X[b, r]
            end
        end
    end
    # Z[:, c] = A_I x (x in the original order: x[j] = X[b, iperm[j]])
    Z = w.Z
    @inbounds for (r, i) in enumerate(w.rows)
        for b in 1:nb
            acc = 0.0
            for k in nzrange(At, i)
                j = rv[k]
                acc += nz[k] * X[b, ip === nothing ? j : ip[j]]
            end
            Z[r, cs[b]] = acc
        end
    end
    @inbounds for c in cs
        w.zok[c] = true
    end
    return nothing
end

"""
After new matrix values (`update!` with `P` or `A`): Z and the dense factor
are dropped, and the dense path steps aside for the next solve, which the
sparse paths serve: with matrices that change at every step (linear
time-varying MPC) a refactorization of K11 and a new Z would cost more than
they save. The first solve after a step with unchanged matrices refactors K11
and rebuilds Z (whole if `setup` built it whole, otherwise lazily), and uses
the dense path again.
"""
function _dual_update_matrices!(s::Solver, w::DualWork)
    fill!(w.zok, false)
    w.na = 0; w.nfac = 0
    w.xbar_ok = false
    w.last_dense = false
    w.fails = 0
    w.stale = 1
    return nothing
end

"Refactor K11 for the current matrix values (after `_dual_update_matrices!`)."
function _dual_refresh!(s::Solver, w::DualWork)
    copyto!(nonzeros(w.sys.K), nonzeros(s.kkt.K))
    _k11_values!(s, w.sys.K, w.sys.diag_idx)
    _reload!(w.sys)
    w.At = SpMat(sparse(transpose(s.A)))
    w.full && _dual_build!(w)              # whole again, as `setup` built it
    w.stale = 0
    return nothing
end

"Column `c` of Z (one solve with K11)."
function _dual_column!(w::DualWork, c::Int)
    t = w.t2
    fill!(t, 0.0)
    At = w.At
    @inbounds for k in nzrange(At, w.rows[c])
        t[rowvals(At)[k]] = nonzeros(At)[k]
    end
    solve!(w.sys, t)
    _rows_times!(view(w.Z, :, c), At, w.rows, t)
    w.zok[c] = true
    return nothing
end

"`out[r] = a_{rows[r]}' x` for the first `n` entries of `x`."
function _rows_times!(out::AbstractVector{Float64}, At::SpMat, rows::Vector{Int}, x::Vector{Float64})
    rv = rowvals(At); nz = nonzeros(At)
    @inbounds for (r, i) in enumerate(rows)
        acc = 0.0
        for k in nzrange(At, i)
            acc += nz[k] * x[rv[k]]
        end
        out[r] = acc
    end
    return out
end

"`x[1:n] -= sum over the active positions of y_r a_{rows[r]}`."
function _sub_rows_t!(x::Vector{Float64}, w::DualWork, y::Vector{Float64})
    At = w.At; rv = rowvals(At); nz = nonzeros(At)
    @inbounds for p in 1:w.na
        r = w.act[p]
        yr = y[r]
        yr == 0.0 && continue
        for k in nzrange(At, w.rows[r])
            x[rv[k]] -= nz[k] * yr
        end
    end
    return x
end

"xbar and g = A_I xbar for the current q and equality right-hand sides."
function _dual_xbar!(s::Solver, w::DualWork)
    n = s.n
    xb = w.xbar
    @inbounds for j in 1:n
        xb[j] = -s.q[j]
    end
    @inbounds for i in 1:s.m
        xb[n+i] = s.rowtype[i] == ROWT_EQ ? s.l[i] : 0.0
    end
    solve!(w.sys, xb)
    _rows_times!(w.g, w.At, w.rows, xb)
    w.xbar_ok = true
    return nothing
end

"""
Make `act` the positions with `nside != 0` and update the Cholesky factor
`R'R = Z_AA + delta I`: a row that leaves is deleted from the factor (its row
of R becomes a rank-one update of the trailing block), a row that enters is
appended (one triangular solve). Returns false if the factorization breaks
down, or (with `w.toobig` set) if the new columns would exceed the budget of
the attempt; the factor then stays valid for `act[1:na]`.
"""
function _dual_factor!(w::DualWork, del::Float64)
    act = w.act; side = w.nside; Z = w.Z; R = w.R
    mi = length(w.rows)
    na = w.na
    # deletions, from the last position back
    @inbounds for p in na:-1:1
        side[act[p]] != 0 && continue
        w.spent += DUAL_DENSE_WEIGHT * (na - p) * (na - p)
        _chol_delete!(R, p, na, w.dy)
        for q in p:(na-1)
            act[q] = act[q+1]
        end
        na -= 1
    end
    w.na = na
    # additions at the end
    mark = w.mark
    @inbounds for p in 1:na
        mark[act[p]] = true
    end
    nadd = 0
    @inbounds for r in 1:mi
        side[r] != 0 && !mark[r] && (nadd += 1)
    end
    fma = 0.0; nlazy = 0
    @inbounds for j in (na+1):(na+nadd)
        fma += 0.5 * j * j + mi
    end
    @inbounds for r in 1:mi
        side[r] != 0 && !mark[r] && !w.zok[r] && (nlazy += 1)
    end
    fma = DUAL_DENSE_WEIGHT * fma + nlazy * w.solve_fma
    if w.spent + fma > w.budget
        @inbounds for p in 1:na
            mark[act[p]] = false
        end
        w.toobig = true
        return false
    end
    ok = true
    @inbounds for r in 1:mi
        (side[r] == 0 || mark[r]) && continue
        if ok
            w.zok[r] || _dual_column!(w, r)
            j = na + 1
            act[j] = r
            for i in 1:(j-1)                 # R[1:j-1, j] = R' \ Z[act, r]
                acc = Z[act[i], r]
                @simd for k in 1:(i-1)
                    acc -= R[k, i] * R[k, j]
                end
                R[i, j] = acc / R[i, i]
            end
            acc = Z[r, r] + del
            @simd for k in 1:(j-1)
                acc -= R[k, j] * R[k, j]
            end
            if acc > 1e-14 * (Z[r, r] + del)
                R[j, j] = sqrt(acc)
                na = j
            else
                ok = false
            end
        end
    end
    @inbounds for p in 1:na
        mark[act[p]] = false
    end
    w.cols += nadd
    w.spent += fma
    w.na = na
    w.nfac = na
    return ok
end

"""
Delete row and column `p` from the upper Cholesky factor `R[1:na, 1:na]`:
shift the later columns left and up, then restore the triangle of the trailing
block by a rank-one update with the deleted row (`x` is workspace).
"""
function _chol_delete!(R::Matrix{Float64}, p::Int, na::Int, x::Vector{Float64})
    @inbounds for j in (p+1):na
        x[j-p] = R[p, j]
    end
    @inbounds for j in (p+1):na
        for i in 1:(p-1)
            R[i, j-1] = R[i, j]
        end
        for i in (p+1):j
            R[i-1, j-1] = R[i, j]
        end
    end
    # R22'R22 + x x' with R22 = R[p:na-1, p:na-1] upper triangular
    nt = na - p
    @inbounds for k in 1:nt
        kk = p + k - 1
        rkk = R[kk, kk]; xk = x[k]
        r = sqrt(rkk * rkk + xk * xk)
        c = r / rkk; sn = xk / rkk
        R[kk, kk] = r
        for j in (k+1):nt
            jj = p + j - 1
            v = (R[kk, jj] + sn * x[j]) / c
            R[kk, jj] = v
            x[j] = c * x[j] - sn * v
        end
    end
    return R
end

"Solve `(Z_AA + delta I) w = rhs` with the factor, in place on `x[1:na]`."
function _dual_chol_solve!(w::DualWork, x::Vector{Float64})
    R = w.R; na = w.na
    @inbounds for j in 1:na                 # R' u = x
        acc = x[j]
        @simd for k in 1:(j-1)
            acc -= R[k, j] * x[k]
        end
        x[j] = acc / R[j, j]
    end
    @inbounds for j in na:-1:1              # R v = u
        xj = x[j] / R[j, j]
        x[j] = xj
        @simd for k in 1:(j-1)
            x[k] -= R[k, j] * xj
        end
    end
    return x
end

"Bound of an active position: u for the upper side, l for the lower."
@inline _dual_bound(s::Solver, w::DualWork, r::Int) = w.side[r] > 0 ? s.u[w.rows[r]] : s.l[w.rows[r]]

"""
Primal-dual active-set iterations from the sides in `w.nside`; true when the
active set repeats (a solution of the QP up to the regularization).
"""
function _dual_iterate!(s::Solver, w::DualWork, maxit::Int)
    del = s.settings.dual_delta
    mi = length(w.rows)
    side = w.side; nside = w.nside; pside = w.pside
    fill!(side, Int8(0)); fill!(pside, Int8(0))
    it = 0
    tau = 0.1 * min(s.settings.eps_abs, s.settings.eps_rel)
    lim = typemax(Int)              # changes allowed per iteration (see below)
    pchg = typemax(Int)
    w.lastchg = typemax(Int)        # stays so unless the iterations stop at `maxit`
    while true
        it += 1
        w.iters += 1
        _dual_factor!(w, del) || (w.lastchg = typemax(Int); return false)
        copyto!(side, nside)
        # y_A from the factor, v = g - Z_IA y_A
        @inbounds for p in 1:w.na
            r = w.act[p]
            w.w[p] = w.g[r] - _dual_bound(s, w, r)
        end
        _dual_chol_solve!(w, w.w)
        fill!(w.y, 0.0)
        copyto!(w.v, w.g)
        Z = w.Z
        @inbounds for p in 1:w.na
            c = w.act[p]
            yc = w.w[p]
            w.y[c] = yc
            @simd for r in 1:mi
                w.v[r] -= Z[r, c] * yc
            end
        end
        # the next sides, and a score of each change (violation, wrong-signed multiplier)
        same = true; cyc = it >= 2; nchg = 0
        score = w.dy
        @inbounds for r in 1:mi
            i = w.rows[r]
            yr = w.y[r]; vr = w.v[r]
            # the rule y + (a'x - u) > 0 (upper), y + (a'x - l) < 0 (lower), with a
            # hysteresis: an active row does not leave for a multiplier of the
            # wrong sign within the tolerance, an inactive row does not enter
            # for a violation within it (weakly active rows of a degenerate
            # solution would flip forever; either side passes the final check)
            sd = yr + (vr - s.u[i]) > 0 ? Int8(1) : (yr + (vr - s.l[i]) < 0 ? Int8(-1) : Int8(0))
            sr = side[r]
            if sd == 0 && sr != 0 && abs(yr) <= tau
                sd = sr
            elseif sr == 0 && sd != 0 && max(vr - s.u[i], s.l[i] - vr) <= tau
                sd = Int8(0)
            end
            same &= sd == side[r]
            cyc &= sd == pside[r]
            nside[r] = sd
            if sd != side[r]
                nchg += 1
                score[r] = abs(yr) + max(vr - s.u[i], s.l[i] - vr, 0.0)
            end
        end
        s.settings.verbose && @printf("      active-set iteration %d: %d active, %d changes\n", it, w.na, nchg)
        w.lastchg = nchg
        same && return true
        w.spent += DUAL_DENSE_WEIGHT * (w.na + 2) * mi
        w.spent > w.budget && (w.toobig = true; w.lastchg = typemax(Int); return false)
        it >= maxit && return false
        # safeguards of the plain iteration, which can oscillate near a
        # degenerate solution: once the changes are few (at most 5% of the rows)
        # their number may not grow (only the largest are taken), and a cycle
        # (the sides of two iterations back again) halves it
        nchg > pchg && pchg <= max(2, mi ÷ 20) && (lim = min(lim, pchg))
        cyc && (lim = max(1, min(lim, nchg) ÷ 2))
        pchg = min(nchg, lim)
        nchg > lim && _dual_limit!(w, lim, nchg)
        copyto!(pside, side)
    end
end

"Keep the `lim` changes of `nside` against `side` with the largest scores (`w.dy`); revert the rest."
function _dual_limit!(w::DualWork, lim::Int, nchg::Int)
    side = w.side; nside = w.nside; score = w.dy; buf = w.w
    k = 0
    @inbounds for r in eachindex(side)
        nside[r] != side[r] && (k += 1; buf[k] = score[r])
    end
    thr = partialsort!(view(buf, 1:k), lim; rev = true)
    kept = 0
    @inbounds for r in eachindex(side)
        if nside[r] != side[r]
            if score[r] >= thr && kept < lim
                kept += 1
            else
                nside[r] = side[r]
            end
        end
    end
    return nothing
end

"""
The point of the active set in `w` into `px`, `py`, `act`, refined against the
unregularized KKT system of that active set; then the polish check.
"""
function _dual_finish!(s::Solver, w::DualWork)
    st = s.settings
    n, m = s.n, s.m
    del = st.dual_delta
    # x, y_E from K11 with the active rows' multipliers moved to the right
    t = w.t
    @inbounds for j in 1:n
        t[j] = -s.q[j]
    end
    @inbounds for i in 1:m
        t[n+i] = s.rowtype[i] == ROWT_EQ ? s.l[i] : 0.0
    end
    _sub_rows_t!(t, w, w.y)
    solve!(w.sys, t)
    @inbounds for j in 1:n
        s.px[j] = t[j]
    end
    @inbounds for i in 1:m
        rt = s.rowtype[i]
        if rt == ROWT_EQ
            s.py[i] = t[n+i]; s.act[i] = ACT_EQ
        else
            s.py[i] = 0.0; s.act[i] = ACT_NONE
        end
    end
    @inbounds for p in 1:w.na
        r = w.act[p]; i = w.rows[r]
        s.py[i] = w.y[r]
        s.act[i] = w.side[r] > 0 ? ACT_UPPER : ACT_LOWER
    end
    # iterative refinement: residual of the exact system, a correction through
    # K11 and the dense factor (two solves), until the residual is a tenth of
    # the tolerance; then the check, and if it fails, more refinement
    tol = 0.1 * min(st.eps_abs, st.eps_rel)
    _dual_refine!(s, w, tol, st.polish_refine_iter)
    r = _polish_check(s)
    r[1] && return r
    # a point that misses the check: two more steps toward a much smaller residual
    _dual_refine!(s, w, 1e-4 * tol, 2) > 0 || return r
    return _polish_check(s)
end

"Refinement steps (at most `steps`) of the point in `px`, `py` until the KKT residual is below `tol`; the number taken."
function _dual_refine!(s::Solver, w::DualWork, tol::Float64, steps::Int)
    n, m = s.n, s.m
    t = w.t
    taken = 0
    for _ in 1:steps
        mul!(s.pPx, s.P, s.px)
        mul!(s.pAty, transpose(s.A), s.py)
        mul!(s.pAx, s.A, s.px)
        rmax = 0.0
        @inbounds for j in 1:n
            v = -s.q[j] - s.pPx[j] - s.pAty[j]
            t[j] = v
            rmax = max(rmax, abs(v))
        end
        @inbounds for i in 1:m
            if s.rowtype[i] == ROWT_EQ
                v = s.l[i] - s.pAx[i]
                t[n+i] = v
                rmax = max(rmax, abs(v))
            else
                t[n+i] = 0.0
            end
        end
        @inbounds for p in 1:w.na
            r = w.act[p]; i = w.rows[r]
            w.dy[r] = _dual_bound(s, w, r) - s.pAx[i]          # r_A
            rmax = max(rmax, abs(w.dy[r]))
        end
        rmax <= tol && break
        taken += 1
        copyto!(w.t2, t)
        solve!(w.sys, w.t2)
        _rows_times!(w.v, w.At, w.rows, w.t2)
        @inbounds for p in 1:w.na
            r = w.act[p]
            w.w[p] = w.v[r] - w.dy[r]
        end
        _dual_chol_solve!(w, w.w)
        fill!(w.dy, 0.0)
        @inbounds for p in 1:w.na
            w.dy[w.act[p]] = w.w[p]
        end
        _sub_rows_t!(t, w, w.dy)
        solve!(w.sys, t)
        @inbounds for j in 1:n
            s.px[j] += t[j]
        end
        @inbounds for i in 1:m
            s.rowtype[i] == ROWT_EQ && (s.py[i] += t[n+i])
        end
        @inbounds for p in 1:w.na
            r = w.act[p]
            s.py[w.rows[r]] += w.dy[r]
        end
    end
    return taken
end

"The active set of `w.side` (and the equality rows) as `s.act`."
function _dual_sides_to_act!(s::Solver, w::DualWork)
    @inbounds for i in 1:s.m
        s.act[i] = s.rowtype[i] == ROWT_EQ ? ACT_EQ : ACT_NONE
    end
    @inbounds for (r, i) in enumerate(w.rows)
        sd = w.side[r]
        sd != 0 && (s.act[i] = sd > 0 ? ACT_UPPER : ACT_LOWER)
    end
    return nothing
end

"""
    _try_dual!(s, seed) -> Bool

One attempt of the dense path: active-set iterations seeded from xbar
(`seed = :xbar`: the rows xbar violates), from `s.act` (`:act`: an ADMM guess
or the last accepted active set), then the refined point and the polish check;
`frac` scales the budget of the attempt.
An accepted point becomes the iterate, like an accepted polish.
"""
function _try_dual!(s::Solver, seed::Symbol; frac::Float64 = 1.0)
    s.dual === nothing && return false
    return _try_dual!(s, s.dual::DualWork, seed, frac)
end

function _try_dual!(s::Solver, w::DualWork, seed::Symbol, frac::Float64)
    t0 = time_ns()
    st = s.settings
    info = s.info
    w.xbar_ok || _dual_xbar!(s, w)
    nside = w.nside
    if seed == :xbar
        @inbounds for (r, i) in enumerate(w.rows)
            gr = w.g[r]
            nside[r] = gr > s.u[i] ? Int8(1) : (gr < s.l[i] ? Int8(-1) : Int8(0))
        end
    else
        @inbounds for (r, i) in enumerate(w.rows)
            a = s.act[i]
            nside[r] = a == ACT_UPPER ? Int8(1) : (a == ACT_LOWER ? Int8(-1) : Int8(0))
        end
    end
    # a budget of multiply-adds (deterministic): `dual_budget` times a sparse
    # factorization of K11 plus 20 solves, against which a failed attempt is
    # cheaper than the ADMM iterations and sparse polish it replaces; all the
    # attempts of a solve draw on twice that
    w.spent = 0.0
    full = st.dual_budget * (w.fac_fma + 20 * w.solve_fma)
    w.budget = min(frac * full, 2 * full - w.spent_solve)
    if w.budget <= 0
        w.toobig = true
        return false
    end
    w.tried = true
    info.polish_attempts += 1
    ok = _dual_iterate!(s, w, st.dual_iter)
    w.spent_solve += w.spent
    # a start from xbar that runs out of budget says little about the active
    # sets ADMM will guess; a guess that does means the active sets are too
    # large for the dense path, and the sparse polish takes over for the solve
    seed == :xbar && w.spent_solve < 2 * full && (w.toobig = false)
    if ok
        ok, pr, dr, _ = _dual_finish!(s, w)
        if ok
            copyto!(s.x, s.px); copyto!(s.y, s.py); copyto!(s.z, s.pz)
            info.prim_res = pr; info.dual_res = dr
            info.polish = :success
            info.polish_iter = info.iter
            w.accepted = true
        end
        st.verbose && @printf("    dense active set (%s): %d rows, %s\n", seed, w.na, ok ? "accepted" : "rejected")
    else
        st.verbose && @printf("    dense active set (%s): no convergence after %d iterations\n", seed, w.iters)
        # an iteration that stopped a few changes short of a fixed point (a
        # nearly degenerate solution, where it oscillates): the sparse polish
        # with its primal-dual corrections from that active set
        if w.lastchg <= max(3, length(w.rows) ÷ 50)
            _dual_sides_to_act!(s, w)
            ok = _try_polish!(s; restart = false)
            st.verbose && @printf("    sparse polish from the dense active set: %s\n", ok ? "accepted" : "rejected")
        end
    end
    info.polish_time += (time_ns() - t0) / 1e9
    return ok
end
