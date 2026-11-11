# analysis.jl: the quantities the checks compare, computed densely on small
# instances: reduced Hessians and their conditioning, the
# strong convexity modulus (Thm 2.7(c)), active sets and the sensitivity matrix
# of Rem 2.8, gradient iteration counts, and the block-local recovery of the
# collapsed-edge multipliers from a coarse solve (Sec. 5).

"""Orthonormal basis of `ker A` (dense SVD, rank tolerance `max(m,n) eps sigma_max`)."""
function nullbasis(A::AbstractMatrix)
    m, n = size(A)
    m == 0 && return Matrix{Float64}(I, n, n)
    F = svd(Matrix(A); full = true)
    isempty(F.S) && return Matrix{Float64}(I, n, n)
    tol = max(m, n) * eps() * F.S[1]
    r = count(>(tol), F.S)
    return F.V[:, (r+1):n]
end

"""
    numerical_rank(A) -> (rank, sigma_kept, sigma_dropped)

Rank by dense SVD with tolerance `max(m,n) eps sigma_max`, with the smallest
singular value counted and the largest one discarded (the gap shows whether
the decision is clean).
"""
function numerical_rank(A::AbstractMatrix)
    m, n = size(A)
    (m == 0 || n == 0) && return (0, Inf, 0.0)
    S = svdvals(Matrix(A))
    tol = max(m, n) * eps() * S[1]
    r = count(>(tol), S)
    return (r, r > 0 ? S[r] : Inf, r < length(S) ? S[r+1] : 0.0)
end

"""Orthonormal basis of `range A`."""
function rangebasis(A::AbstractMatrix)
    m, n = size(A)
    (m == 0 || n == 0) && return zeros(m, 0)
    F = svd(Matrix(A))
    isempty(F.S) && return zeros(m, 0)
    tol = max(m, n) * eps() * F.S[1]
    r = count(>(tol), F.S)
    return F.U[:, 1:r]
end

"""
    reduced_hessian(P; node_equalities = false) -> (Hr, Z)

`Z' Hq Z` with `Hq` the Hessian of `J` and `Z` an orthonormal basis of
`ker delta_{E_h}`, or of the kernel of the hard rows together
with the zero-cone node rows (`node_equalities = true`, the affine hull of the
equality constraints, used for the strong convexity modulus).
"""
function reduced_hessian(P::GraphProgram; node_equalities::Bool = false)
    Hq, _, _ = quadratic_form(P)
    rows = edge_operator(P, hard_edges(P))
    if node_equalities
        A0, _ = node_equalities_rows(P)
        rows = [rows; A0]
    end
    Z = nullbasis(rows)
    Hr = Matrix(Symmetric(Z' * (Hq * Z)))
    return Hr, Z
end

node_equalities_rows(P::GraphProgram) = node_equalities(P)

"""
    cost_factor(P) -> F

A factor `F` with `F'F = Hq` (the Hessian of `J`): per vertex the square root of
`Q_v` (from its eigendecomposition), per soft edge `W_e^{1/2} delta_e`. With it,
`kappa(T' Hq T) = kappa(F T)^2` is computed from singular values, which stays
accurate when the condition number is far beyond what an eigensolver on
`T' Hq T` could resolve.
"""
function cost_factor(P::GraphProgram)
    blocks = Matrix{Float64}[]
    rowsF = Int[]; colsF = Int[]; valsF = Float64[]
    row = 0
    for v in 1:nvertices(P)
        Q = Matrix(P.nodes[v].Q)
        size(Q, 1) == 0 && continue
        F = eigen(Symmetric(Q))
        keep = findall(>(max(1e-14 * maximum(abs, F.values; init = 0.0), 0.0)), F.values)
        Fv = Diagonal(sqrt.(F.values[keep])) * F.vectors[:, keep]'
        for (ii, jj) in Iterators.product(1:size(Fv, 1), 1:size(Fv, 2))
            Fv[ii, jj] != 0 && (push!(rowsF, row + ii); push!(colsF, P.offsets[v] + jj); push!(valsF, Fv[ii, jj]))
        end
        row += size(Fv, 1)
    end
    Fn = sparse(rowsF, colsF, valsF, row, c0dim(P))
    S = soft_edges(P)
    if !isempty(S) && edgedims(P, S) > 0
        Ws = Matrix(weight_matrix(P, S))
        Fe = sparse(sqrt(Symmetric(Ws))) * edge_operator(P, S)
        return [Fn; Fe]
    end
    return Fn
end

"""`kappa(T' Hq T)` from the singular values of `F T` (`F = cost_factor(P)`)."""
function kappa_factor(F::AbstractMatrix, T::AbstractMatrix)
    sv = svdvals(Matrix(F * T))
    return (sv[1] / sv[end])^2
end

"""`(lambda_min, lambda_max, kappa)` of a symmetric matrix."""
function spectrum(H::AbstractMatrix)
    size(H, 1) == 0 && return (lmin = NaN, lmax = NaN, kappa = NaN)
    ev = eigvals(Symmetric(Matrix(H)))
    return (lmin = ev[1], lmax = ev[end], kappa = ev[end] / ev[1])
end

"""Strong convexity modulus of `J` on the affine hull of the equality constraints of `P`."""
strong_convexity(P::GraphProgram) = spectrum(reduced_hessian(P; node_equalities = true)[1]).lmin

"""
    gd_iterations(H, g; rtol = 1e-6)

Iterations of gradient descent with step `1/lambda_max` on `(1/2) z'Hz + g'z`
from `z = 0` until `||z_k - z*|| <= rtol ||z*||`, computed exactly from the
eigendecomposition (the error in eigendirection `k` contracts by
`1 - lambda_k / lambda_max` per step). Graph diffusion is this iteration.
"""
function gd_iterations(H::AbstractMatrix, g::AbstractVector; rtol::Real = 1e-6, maxit::Integer = 10^12)
    F = eigen(Symmetric(Matrix(H)))
    lam = F.values
    L = lam[end]
    c = F.vectors' * (Symmetric(Matrix(H)) \ g)
    nrm0 = norm(c)
    nrm0 == 0 && return 0
    err(t) = sqrt(sum(abs2(c[k]) * (1 - lam[k] / L)^(2t) for k in eachindex(lam)))
    err(0) <= rtol * nrm0 && return 0
    hi = 1
    while err(hi) > rtol * nrm0
        hi *= 2
        hi > maxit && return maxit
    end
    lo = hi ÷ 2
    while hi - lo > 1
        mid = (lo + hi) ÷ 2
        err(mid) > rtol * nrm0 ? (lo = mid) : (hi = mid)
    end
    return hi
end

"""
    reduced_problem(P; node_equalities = true) -> (Hr, gr, Z, x0)

The smooth part of `P` restricted to its equality constraints,
`x = x0 + Z z`: `(1/2) z' Hr z + gr' z + const`. Inequalities are ignored.
"""
function reduced_problem(P::GraphProgram; node_equalities::Bool = true)
    Hq, g, _ = quadratic_form(P)
    hard = hard_edges(P)
    rows = edge_operator(P, hard); rhs = targets(P, hard)
    if node_equalities
        A0, b0 = node_equalities_rows(P)
        rows = [rows; A0]; rhs = [rhs; b0]
    end
    Z = nullbasis(rows)
    x0 = size(rows, 1) == 0 ? zeros(c0dim(P)) : Matrix(rows) \ rhs
    Hr = Matrix(Symmetric(Z' * (Hq * Z)))
    gr = Z' * (Hq * x0 + g)
    return Hr, gr, Z, x0
end

# ---------------------------------------------------------------------------
# Active sets and the sensitivity of Rem 2.8
# ---------------------------------------------------------------------------

"""
    active_set(P, x; tol = 1e-7) -> NamedTuple

Active node constraints at `x`: `nonneg` (global row indices of active
half-space rows, in `node_constraints` order) and `soc` (indices of SOC blocks
on the boundary `||z|| = t`), with the slack margins used.
"""
function active_set(P::GraphProgram, x::AbstractVector; tol::Real = 1e-7)
    A, b, cones, _ = node_constraints(P)
    s = b - A * x
    nn = Int[]; soc = Int[]
    r = 0
    for (k, cb) in enumerate(cones)
        rr = (r+1):(r+cb.dim)
        if cb.kind == NONNEG_CONE
            for i in rr
                s[i] <= tol * max(1.0, abs(b[i])) && push!(nn, i)
            end
        elseif cb.kind == SOC_CONE
            t = s[rr[1]]
            (t - norm(view(s, rr[2:end]))) <= tol * max(1.0, t) && push!(soc, k)
        end
        r += cb.dim
    end
    return (nonneg = nn, soc = soc)
end

"""
    price_sensitivity(P, S, act) -> NamedTuple

For `S` = collapsed soft edges and a fixed polyhedral active set `act` (from
`active_set`, with no active SOC), the value function of THEORY Rem 2.8,
`p(s) = inf { J_0(x) : x in feas(P) with the active rows as equalities,
delta_S x - b_S = s }`, is quadratic on the subspace `range(B)`,
`B = delta_S Z_E` (`Z_E` an orthonormal basis of the equality rows) and
`+Inf` off it. With `Hz = Z_E' H_0 Z_E` (`H_0` the Hessian of `J_0`) and `K` an
orthonormal basis of `ker B`, its Hessian in the right-hand side `c` of
`B z = c` is `B^+' (Hz - Hz K (K'Hz K)^{-1} K'Hz) B^+` (the Schur complement;
it equals `(B Hz^{-1} B')^+` when `Hz` is invertible, and needs only
`K'Hz K` positive definite, i.e. `P[S]` strictly convex). Returns `R`
(orthonormal basis of `range(B)`), `Msig = R' M R`, `Wsig = R' W_S R`,
`rank_deficiency` (rows of `S` minus `rank B`: positive when the collapsed rows
are dependent, e.g. a cycle of formation edges), and `lmin_KHK`.
"""
function price_sensitivity(P::GraphProgram, S::Vector{Int}, act)
    return price_sensitivity(P, S, sensitivity_basis(P, act)...)
end

"""
    sensitivity_basis(P, act) -> (ZE, HZ)

Orthonormal basis `ZE` of the equality rows (hard edges, zero-cone node rows,
the active half-space rows of `act`) and `HZ = ZE' Hq ZE`, reusable for every
collapse of the same program with the same active set.
"""
function sensitivity_basis(P::GraphProgram, act)
    Hq, _, _ = quadratic_form(P)
    An, _, _, _ = node_constraints(P)
    A0, _ = node_equalities(P)
    rows = [edge_operator(P, hard_edges(P)); A0; An[act.nonneg, :]]
    ZE = nullbasis(rows)
    HZ = Matrix(Symmetric(ZE' * (Hq * ZE)))
    return ZE, HZ
end

function price_sensitivity(P::GraphProgram, S::Vector{Int}, ZE::Matrix{Float64}, HZ::Matrix{Float64})
    Ds = edge_operator(P, S)
    Ws = Matrix(weight_matrix(P, S))
    B = Matrix(Ds * ZE)
    Hz = HZ - B' * Ws * B            # Hessian of J_0 (the springs of S removed) on ZE
    Hz = (Hz + Hz') / 2
    R = rangebasis(B)
    K = nullbasis(B)
    Bp = pinv(B)
    if size(K, 2) > 0
        KHK = Symmetric(K' * Hz * K)
        lmin = eigmin(KHK)
        Sch = Hz - Hz * K * (KHK \ (K' * Hz))
    else
        lmin = Inf
        Sch = Hz
    end
    Mc = Bp' * Sch * Bp
    Msig = R' * Mc * R
    Wsig = R' * Ws * R
    return (R = R, Msig = (Msig + Msig') / 2, Wsig = (Wsig + Wsig') / 2, Ws = Ws,
            rank_deficiency = size(B, 1) - size(R, 2), lmin_KHK = lmin)
end

"""
    sensitivity_report(sens, mu, s) -> NamedTuple

Given the sensitivity on `range(B)`, the multiplier `mu` (stacked over `S`) and
the fine defect `s`: predicted price `(1/2) m'(Msig + Wsig)^{-1} m` with
`m = R'mu`, predicted defect, the least `W^{-1}`-norm multiplier and its bound,
the stiffness ratio bound `(1 + lambda_max(M~))^2` with
`M~ = Wsig^{-1/2} Msig Wsig^{-1/2}`, and how far `s` is from `range(B)`.
"""
function sensitivity_report(sens, mu::Vector{Float64}, s::Vector{Float64})
    R, Msig, Wsig, Ws = sens.R, sens.Msig, sens.Wsig, sens.Ws
    m = R' * mu
    K = Symmetric(Msig + Wsig)
    sig = K \ m
    gamma_pred = 0.5 * dot(m, sig)
    s_pred = R * sig
    mu_min = Ws * (R * (Symmetric(Wsig) \ m))
    upper_min = 0.5 * dot(mu_min, Ws \ mu_min)
    Wh = sqrt(Symmetric(Wsig))
    Mt = Symmetric(Wh \ (Msig / Wh))
    lmax = size(Mt, 1) == 0 ? 0.0 : eigmax(Mt)
    return (gamma_pred = gamma_pred, s_pred_err = norm(s_pred - s) / max(norm(s), 1e-300),
            upper_min = upper_min, stiffness_bound = (1 + lmax)^2, lambda_max_Mt = lmax,
            s_off_range = norm(s - R * (R' * s)) / max(norm(s), 1e-300), mu_min = mu_min)
end

# ---------------------------------------------------------------------------
# Block-local multipliers from the coarse solve
# ---------------------------------------------------------------------------

"""
    local_multipliers(P, L, Pc, solc; normal_cone = :variable) -> (mu, eta_B, residual)

Recover, block by block from a coarse solution alone, multipliers of the
collapsed rows. At `x = iota(y*)` the fine
stationarity on block `B` reads

    grad_B J(x) + (cross hard edges)' lambda_c + delta_{E_B}' nu + nu_Omega = 0,

where `nu = (mu on the collapsed soft rows, lambda on the collapsed hard rows)`,
`nu_Omega = A_B' z` is an element of the normal cone of `Omega_B` at `x_B`, and
`lambda_c` are the multipliers of the non-collapsed hard edges incident to `B`,
taken from the coarse solve (they are coarse edge duals, shared with the
neighbouring block). With `normal_cone = :variable` (the default) the forces are

    argmin (1/2) sum_{e in E_B soft} ||mu_e||^2_{W_e^{-1}}  over (mu, lambda, z)

subject to that equation and `z` in the normal-cone multiplier set at `x_B`
(zero rows free; a half-space row: `z >= 0` if active, `z = 0` if not; a
second-order cone: `z = 0` in the interior, `z = eta (s0, -s1)` with `eta >= 0`
on the boundary, `z` in the cone at the apex), a small conic QP per block. This
is the minimum `W^{-1}`-norm force given the cross duals, canonical even when
the node constraints are degenerate. With `normal_cone = :fixed` the node
duals are fixed to the coarse solver's (not canonical: with degenerate node
constraints the solver's split of the duals can report a positive force when
the price and the minimum-norm force are zero; kept as the control).
Returns `mu[e]` for every collapsed edge `e`, `eta_B = sum_{e in E_B soft}
(1/2)||mu_e||^2_{W_e^{-1}}` per block, and the worst stationarity residual.
"""
function local_multipliers(P::GraphProgram, L::ResolutionLift, Pc::GraphProgram, solc::DirectSolution;
                           normal_cone::Symbol = :variable, act_tol::Real = 1e-7)
    x = lift(L, solc.x)
    Hq, g, _ = quadratic_form(P)
    r = Hq * x + g
    for (k, e) in enumerate(L.coarse_edges)
        E = P.edges[e]
        E.hard || continue
        lam = solc.edge_duals[k]
        isempty(lam) && continue
        r[vrange(P, E.head)] .+= E.Fh' * lam
        r[vrange(P, E.tail)] .-= E.Ft' * lam
    end
    mu = Dict{Int,Vector{Float64}}()
    eta = zeros(length(L.blocks))
    worst = 0.0
    for (b, B) in enumerate(L.blocks)
        isempty(B.internal) && continue
        n = B.offsets[end]
        rows = reduce(vcat, [collect(vrange(P, v)) for v in B.members])
        rB = r[rows]
        m = edgedims(P, B.internal)
        # sparse internal edge operator D (m x n) and W^{-1} on its soft rows
        DI = Int[]; DJ = Int[]; DV = Float64[]
        WI = Int[]; WJ = Int[]; WV = Float64[]
        row = 0
        for e in B.internal
            E = P.edges[e]
            d = edgedim(E)
            lt, lh = L.local_index[E.tail], L.local_index[E.head]
            _push_block!(DI, DJ, DV, row, B.offsets[lt], E.Ft, -1.0)
            _push_block!(DI, DJ, DV, row, B.offsets[lh], E.Fh, 1.0)
            if !E.hard && d > 0
                Wi = inv(E.W)
                for ii in 1:d, jj in 1:d
                    Wi[ii, jj] != 0 && (push!(WI, row + ii); push!(WJ, row + jj); push!(WV, Wi[ii, jj]))
                end
            end
            row += d
        end
        D = sparse(DI, DJ, DV, m, n)
        Winv = sparse(WI, WJ, WV, m, m)
        # the members' node constraints, stacked (sparse), and their slacks at x
        AI_ = Int[]; AJ_ = Int[]; AV_ = Float64[]; cones = ConeBlock[]; sl = Float64[]
        arow = 0
        for (l, v) in enumerate(B.members)
            nd = P.nodes[v]
            isempty(nd.b) && continue
            _push_block!(AI_, AJ_, AV_, arow, B.offsets[l], nd.A, 1.0)
            append!(cones, nd.cones); append!(sl, nd.b - nd.A * x[vrange(P, v)])
            arow += size(nd.A, 1)
        end
        AB = sparse(AI_, AJ_, AV_, arow, n)
        zc = solc.node_duals[b]
        fixed_solution() = (rhs = -(rB + (isempty(zc) ? zeros(n) : AB' * zc)); nu = _least_winv_solution(D, Winv, rhs);
                            (nu, norm(D' * nu - rhs, Inf)))
        if normal_cone == :fixed || size(AB, 1) == 0
            nu, res = fixed_solution()
        else
            nu, res, okq = _normal_cone_recovery(D, Winv, AB, cones, sl, zc, rB, act_tol)
            if !okq
                nu, res = fixed_solution()
                FALLBACKS[] += 1
            end
        end
        worst = max(worst, res)
        row = 0
        for e in B.internal
            d = edgedim(P.edges[e])
            mu[e] = nu[(row+1):(row+d)]
            if !P.edges[e].hard && d > 0
                eta[b] += 0.5 * dot(mu[e], P.edges[e].W \ mu[e])
            end
            row += d
        end
    end
    return mu, eta, worst
end

"""
Least `Winv`-weighted solution of `D' nu = rhs` (hard rows free, a tiny ridge for
uniqueness); for large blocks a sparse least-squares solution instead.
"""
function _least_winv_solution(D, Winv, rhs)
    m, n = size(D)
    if m * n > 4_000_000
        return Vector{Float64}(sparse(D') \ rhs)
    end
    Dd = Matrix(D); Wd = Matrix(Winv)
    nu0 = pinv(Dd') * rhs
    K = nullbasis(Dd')
    size(K, 2) == 0 && return nu0
    Mk = K' * Wd * K
    w = (Symmetric(Mk) + 1e-12 * I) \ (-(K' * (Wd * nu0)))
    return nu0 + K * w
end

"""Number of blocks where the conic recovery was not solved and the fixed-dual solution was used."""
const FALLBACKS = Ref(0)

"""
The per-block conic QP of `local_multipliers` with the normal-cone element free
(sparse): variables `nu` (collapsed rows), the node multipliers (parametrized
by the active structure at the slack `sl`, a row being active when its slack is
below the tolerance or its coarse dual `zc` exceeds its slack), and a residual
`t` of the stationarity equation `D'nu + Z zeta + rB = t`, penalized by
`rho ||t||^2` so that the problem stays feasible at an interior-point (inexact)
point. Returns `(nu, ||t||_inf, solved)`.
"""
function _normal_cone_recovery(D::SparseMatrixCSC, Winv::SparseMatrixCSC, AB::SparseMatrixCSC, cones, sl, zc, rB,
                               act_tol; rho = 1e12)
    m, n = size(D)
    ZI = Int[]; ZJ = Int[]; ZV = Float64[]
    kinds = Symbol[]; dims = Int[]
    col = 0
    ABt = SparseMatrixCSC(AB')
    addcol!(vec) = begin
        col += 1
        for (i, v) in zip(findnz(sparse(vec))...)
            push!(ZI, i); push!(ZJ, col); push!(ZV, v)
        end
    end
    r = 0
    for cb in cones
        rr = (r+1):(r+cb.dim)
        s = sl[rr]
        z = isempty(zc) ? zeros(cb.dim) : zc[rr]
        scale = max(1.0, maximum(abs, s; init = 0.0))
        if cb.kind == ZERO_CONE
            for i in rr
                addcol!(ABt[:, i])
            end
            push!(kinds, :free); push!(dims, cb.dim)
        elseif cb.kind == NONNEG_CONE
            for (ii, i) in enumerate(rr)
                (s[ii] <= act_tol * scale || z[ii] >= s[ii]) || continue
                addcol!(ABt[:, i]); push!(kinds, :nonneg); push!(dims, 1)
            end
        else
            gap = s[1] - norm(view(s, 2:length(s)))
            if s[1] <= act_tol * scale
                for i in rr
                    addcol!(ABt[:, i])
                end
                push!(kinds, :soc); push!(dims, cb.dim)              # apex: z in the cone
            elseif gap <= act_tol * scale || z[1] >= gap
                Js = [s[1]; -s[2:end]]
                addcol!(ABt[:, rr] * Js); push!(kinds, :nonneg); push!(dims, 1)   # z = eta J s
            end
        end
        r += cb.dim
    end
    kz = col
    Z = sparse(ZI, ZJ, ZV, n, kz)
    nv = m + kz + n
    Pq = blockdiag(Winv + 1e-12 * sparse(I, m, m), 1e-12 * sparse(I, kz, kz), rho * sparse(I, n, n))
    Aeq = [SparseMatrixCSC(D') Z -sparse(I, n, n)]
    AI_ = Int[]; AJ_ = Int[]; AV_ = Float64[]
    brows = Float64[]; cl = ConeBlock[]
    off = m; crow = 0
    for (k, kd) in enumerate(kinds)
        d = dims[k]
        if kd == :nonneg || kd == :soc
            for ii in 1:d
                push!(AI_, crow + ii); push!(AJ_, off + ii); push!(AV_, -1.0)
            end
            append!(brows, zeros(d)); push!(cl, kd == :nonneg ? nonneg_cone(d) : soc_cone(d))
            crow += d
        end
        off += d
    end
    Acone = sparse(AI_, AJ_, AV_, crow, nv)
    res = solve_qp(Pq, zeros(nv), 0.0, [Aeq; Acone], [-rB; brows], [zero_cone(n); cl];
                   opts = SolverOptions(tol = 1e-12, infeas_tol = 1e-12, polish = true))
    ok = res.status in (:optimal, :almost_optimal) && all(isfinite, res.x)
    v = res.x
    return v[1:m], ok ? norm(v[(m+kz+1):nv], Inf) : Inf, ok
end
