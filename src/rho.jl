# rho.jl: the ADMM penalty from the spectrum of the constraint operator.
#
# For a QP with equality rows A_E and inequality (and cone) rows A_I, ADMM's
# linear rate is governed by the operator
#
#     M = A_I Z (Z' P Z)^{-1} Z' A_I',      Z a basis of null(A_E),
#
# and the penalty minimizing the rate bound is rho* = 1 / sqrt(lmin lmax),
# lmin, lmax the extreme nonzero eigenvalues of M (Ghadimi, Teixeira, Shames
# and Johansson 2015, for the inequality-constrained QP; equality rows are
# enforced by their own much larger penalty, rho_eq_scale rho). On the fleet
# MPC family the best fixed rho is within a factor of two of rho* over
# horizon blockings that move rho* by a factor of five.
#
# M is applied with a matrix of the KKT pattern (in `setup`, the first
# numerical factorization of the ADMM system itself, before its rho is known)
# with the equality rows active and every other row inactive: solving
#
#     [ P + delta I     A'                        ] [ x  ]   [ A_I' v ]
#     [ A           -diag(delta on A_E, 1/delta)  ] [ nu ] = [ 0      ]
#
# gives x = (P on null(A_E))^{-1} A_I' v up to O(delta), and M v = A_I x. A
# few Lanczos steps (no reorthogonalization: only the extreme Ritz values are
# used) estimate lmin and lmax; the ADMM system is then refactored for rho.

"""
    spectral_rho!(s::Solver) -> rho or nothing

The spectral penalty `settings.rho_spectral_scale / sqrt(lmin lmax)` (scaled
problem) from `settings.rho_spectral_iter` Lanczos steps on M (see the file
header); `nothing` if there are no inequality or cone rows. Stores the
estimates in `s.lam_min`, `s.lam_max`. Solves with `S` (default the polish
system, which is first factored with the values above; `factored = true`
when `S` already holds them, as the ADMM system does in `setup`).
"""
function spectral_rho!(s::Solver; S::LinearSystem = s.pol, factored::Bool = false)
    st = s.settings
    n, m = s.n, s.m
    # inequality and cone rows with a nonzero row of A (an empty row, such as the
    # constant first row of a cone block t <= b_0, adds a zero eigenvalue)
    nzrow = falses(m)
    Arow = rowvals(s.A)
    @inbounds for k in eachindex(Arow)
        nzrow[Arow[k]] = true
    end
    rows = Int[]
    for i in 1:m
        (s.rowtype[i] == ROWT_INEQ || s.rowtype[i] == ROWT_SOC) && nzrow[i] && push!(rows, i)
    end
    mI = length(rows)
    mI == 0 && return nothing
    del = st.polish_delta
    @inbounds for j in 1:n
        s.tn[j] = s.Pdiag[j] + del
    end
    @inbounds for i in 1:m
        s.pdiag[i] = s.rowtype[i] == ROWT_EQ ? del : 1.0 / del
    end
    if !factored
        set_diagonal!(S.K, S.diag_idx, s.tn, s.pdiag)
        refactor!(S)
        S === s.pol && (s.pol_valid = false)
    end
    # (not capped at mI: without reorthogonalization, copies of converged Ritz
    # values take up dimensions, and the extra steps still sharpen the extremes)
    K = st.rho_spectral_iter
    v = zeros(mI); vprev = zeros(mI); w = zeros(mI)
    full = zeros(m); rhs = zeros(n + m); Ax = zeros(m)
    xv = view(rhs, 1:n)
    function apply_M!(w, v)
        fill!(full, 0.0)
        @inbounds for (k, i) in enumerate(rows)
            full[i] = v[k]
        end
        fill!(rhs, 0.0)
        mul!(xv, transpose(s.A), full)
        solve!(S, rhs)
        mul!(Ax, s.A, xv)
        @inbounds for (k, i) in enumerate(rows)
            w[k] = Ax[i]
        end
        return w
    end
    @inbounds for k in 1:mI                        # deterministic, generic start vector
        w[k] = 1.0 + 0.5 * sin(1.618 * k)
    end
    apply_M!(v, w)                                 # start in the range of M: the Ritz values
    nv = norm(v)                                   # then approximate its nonzero eigenvalues
    nv > 0 || return nothing
    v ./= nv
    alphas = Float64[]; betas = Float64[]
    beta = 0.0
    for _ in 1:K
        apply_M!(w, v)
        a = dot(w, v)
        @inbounds for k in 1:mI
            w[k] -= a * v[k] + beta * vprev[k]
        end
        push!(alphas, a)
        beta = norm(w)
        beta <= 1e-12 * max(abs(a), 1.0) && break
        push!(betas, beta)
        copyto!(vprev, v)
        @inbounds for k in 1:mI
            v[k] = w[k] / beta
        end
    end
    nb = length(alphas) - 1
    ev = eigvals(SymTridiagonal(alphas, betas[1:nb]))
    lmax = maximum(ev)
    lmax <= 0 && return nothing
    lmin = max(minimum(ev), 1e-8 * lmax)
    s.lam_min = lmin; s.lam_max = lmax
    return clamp(st.rho_spectral_scale / sqrt(lmin * lmax), 1e-4, 10.0)
end
