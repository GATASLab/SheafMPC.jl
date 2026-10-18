# kkt_baselines.jl: the reference KKT kernels of the benchmark.
#
#   CQDLDL     OSQP's QDLDL: the C code in libosqp (QDLDL_etree, QDLDL_factor,
#              QDLDL_solve, the very calls of OSQP's linear system), on the
#              AMD-permuted upper triangle, as OSQP does
#   QDLDL.jl   the Julia QDLDL (Clarabel's default direct solver) through
#              SheafMPC's QDLDLSystem (AMD, the package's default)
#   ChordalLDLt CliqueTrees' multifrontal LDLt through SheafMPC's
#              ChordalSystem (AMF), and with METIS
#   Riccati    the HPIPM-like reference: the classical Riccati recursion of the
#              stacked fleet (state of all agents, dense, cubic in n) for the
#              LQ problem with hard dynamics
#
# Every kernel exposes symbolic / factor / solve timings and its nnz(L).

import OSQP
using SparseArrays, LinearAlgebra
const libosqp = OSQP.OSQP_jll.osqp
import QDLDL, CliqueTrees

const CInt = Clonglong

mutable struct CQDLDL
    n::Int
    perm::Vector{Int}
    Ap::Vector{CInt}; Ai::Vector{CInt}; Ax::Vector{Float64}
    Lp::Vector{CInt}; Li::Vector{CInt}; Lx::Vector{Float64}
    D::Vector{Float64}; Dinv::Vector{Float64}
    Lnz::Vector{CInt}; etree::Vector{CInt}
    iwork::Vector{CInt}; bwork::Vector{UInt8}; fwork::Vector{Float64}
    work::Vector{Float64}
end

"Symbolic phase of OSQP's linear system: AMD, permuted upper triangle, elimination tree and counts."
function CQDLDL(K::SparseMatrixCSC{Float64,Int})
    n = size(K, 1)
    perm = Vector{Int}(QDLDL.amd(K))
    Kf = K + sparse(transpose(triu(K, 1)))           # full symmetric (sparse; Symmetric indexing is dense)
    Kp = triu(Kf[perm, perm])
    Ap = CInt.(Kp.colptr .- 1); Ai = CInt.(Kp.rowval .- 1); Ax = copy(Kp.nzval)
    Lnz = zeros(CInt, n); etree = zeros(CInt, n); iwork = zeros(CInt, 3n)
    sumLnz = ccall((:QDLDL_etree, libosqp), CInt, (CInt, Ptr{CInt}, Ptr{CInt}, Ptr{CInt}, Ptr{CInt}, Ptr{CInt}),
                   n, Ap, Ai, iwork, Lnz, etree)
    sumLnz < 0 && error("QDLDL_etree failed ($sumLnz)")
    F = CQDLDL(n, perm, Ap, Ai, Ax, zeros(CInt, n + 1), zeros(CInt, sumLnz), zeros(sumLnz), zeros(n), zeros(n),
               Lnz, etree, iwork, zeros(UInt8, n), zeros(n), zeros(n))
    return F
end

function factor!(F::CQDLDL)
    r = ccall((:QDLDL_factor, libosqp), CInt,
              (CInt, Ptr{CInt}, Ptr{CInt}, Ptr{Float64}, Ptr{CInt}, Ptr{CInt}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64},
               Ptr{CInt}, Ptr{CInt}, Ptr{UInt8}, Ptr{CInt}, Ptr{Float64}),
              F.n, F.Ap, F.Ai, F.Ax, F.Lp, F.Li, F.Lx, F.D, F.Dinv, F.Lnz, F.etree, F.bwork, F.iwork, F.fwork)
    r < 0 && error("QDLDL_factor failed ($r)")
    return F
end

function solve!(F::CQDLDL, b::Vector{Float64})
    w = F.work; p = F.perm
    @inbounds for i in eachindex(p)
        w[i] = b[p[i]]
    end
    ccall((:QDLDL_solve, libosqp), Cvoid, (CInt, Ptr{CInt}, Ptr{CInt}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}),
          F.n, F.Lp, F.Li, F.Lx, F.Dinv, w)
    @inbounds for i in eachindex(p)
        b[p[i]] = w[i]
    end
    return b
end

cqdldl_nnz(F::CQDLDL) = length(F.Lx) + F.n

# ---------------------------------------------------------------------------
# Riccati recursion of the stacked fleet (HPIPM-like reference)
# ---------------------------------------------------------------------------

"""
    RiccatiLQ

min sum_{k=0}^{N-1} (1/2 x_k'Q_k x_k + q_k'x_k + 1/2 u_k'R u_k + r_k'u_k) + 1/2 x_N'Q_N x_N + q_N'x_N
s.t. x_{k+1} = A x_k + B u_k, x_0 given; Q_k (k = 1..N), R dense. The
factorization is the backward recursion of the cost-to-go Hessians P_k and
gains K_k (nx^3 work per stage, nx = 4n for the fleet); the solve the vector
recursion and the forward rollout (nx^2 per stage).
"""
mutable struct RiccatiLQ
    A::Matrix{Float64}; B::Matrix{Float64}
    Q::Vector{Matrix{Float64}}            # Q[k] for x_k, k = 1..N
    R::Matrix{Float64}
    N::Int
    P::Vector{Matrix{Float64}}            # P[k], k = 1..N
    Kg::Vector{Matrix{Float64}}           # gain of stage k = 0..N-1 (index k+1)
    Rc::Vector{Matrix{Float64}}           # Cholesky factor of R + B'P B per stage
    BtPA::Vector{Matrix{Float64}}
    BtP::Matrix{Float64}; AtP::Matrix{Float64}
    pv::Vector{Vector{Float64}}; dv::Vector{Vector{Float64}}
    tx::Vector{Float64}; tu::Vector{Float64}
end

function RiccatiLQ(A, B, Q, R, N)
    nx, nu = size(B)
    return RiccatiLQ(A, B, Q, R, N, [zeros(nx, nx) for _ in 1:N], [zeros(nu, nx) for _ in 1:N],
                     [zeros(nu, nu) for _ in 1:N], [zeros(nu, nx) for _ in 1:N], zeros(nu, nx), zeros(nx, nx),
                     [zeros(nx) for _ in 1:N], [zeros(nu) for _ in 1:N], zeros(nx), zeros(nu))
end

function riccati_factor!(W::RiccatiLQ)
    A, B, N = W.A, W.B, W.N
    copyto!(W.P[N], W.Q[N])
    for k in (N-1):-1:0
        Pn = W.P[k+1]
        mul!(W.BtP, transpose(B), Pn)                    # B'P
        Rk = W.Rc[k+1]
        copyto!(Rk, W.R); mul!(Rk, W.BtP, B, 1.0, 1.0)   # R + B'PB
        BtPA = W.BtPA[k+1]; mul!(BtPA, W.BtP, A)
        C = cholesky!(Hermitian(Rk, :U))
        Kg = W.Kg[k+1]; copyto!(Kg, BtPA); ldiv!(C, Kg)  # K = (R + B'PB) \ B'PA
        if k >= 1
            Pk = W.P[k]
            mul!(W.AtP, transpose(A), Pn)
            copyto!(Pk, W.Q[k]); mul!(Pk, W.AtP, A, 1.0, 1.0)
            mul!(Pk, transpose(BtPA), Kg, -1.0, 1.0)     # Q + A'PA - (B'PA)'K
        end
    end
    return W
end

"Solve for the stage vectors q[k] (k = 1..N), r[k] (k = 0..N-1, index k+1) from x0; returns (x, u, lambda)."
function riccati_solve!(W::RiccatiLQ, q::Vector{Vector{Float64}}, r::Vector{Vector{Float64}}, x0::Vector{Float64},
                        x::Vector{Vector{Float64}}, u::Vector{Vector{Float64}}, lam::Vector{Vector{Float64}})
    A, B, N = W.A, W.B, W.N
    copyto!(W.pv[N], q[N])
    for k in (N-1):-1:0
        pn = W.pv[k+1]
        d = W.dv[k+1]
        mul!(d, transpose(B), pn); d .+= r[k+1]
        ldiv!(Cholesky(W.Rc[k+1], 'U', 0), d)  # d = (R + B'PB) \ (r + B'p)
        if k >= 1
            pk = W.pv[k]
            mul!(pk, transpose(A), pn); pk .+= q[k]
            mul!(pk, transpose(W.BtPA[k+1]), d, -1.0, 1.0)
        end
    end
    xk = x0
    for k in 0:(N-1)
        uk = u[k+1]
        mul!(uk, W.Kg[k+1], xk); uk .+= W.dv[k+1]; uk .*= -1
        xn = x[k+1]
        mul!(xn, A, xk); mul!(xn, B, uk, 1.0, 1.0)
        l = lam[k+1]; mul!(l, W.P[k+1], xn); l .+= W.pv[k+1]
        xk = xn
    end
    return x, u, lam
end

"""
    fleet_riccati(n, N; graph, dyn, rho_box, sigma) -> (W, q, r, kkt)

The stacked fleet LQ problem of `fleet_problem(n, N; b = 1)` (hard dynamics,
the input box rows as the penalty rho_box I of the ADMM system, sigma I on all
variables), and its KKT matrix in the variables (per stage x_k, u_{k-1}) for
the residual check.
"""
function fleet_riccati(n::Int, N::Int; graph::Symbol = :ring, dyn::Symbol = :di, rho_box = 0.1, sigma = 1e-6, t0 = 0.4)
    Ad, Bd, pidx = dynamics(dyn)
    nx1, nu1 = size(Bd); np = length(pidx)
    E = graph == :ring ? ring_edges(n) : grid_edges(n)
    nx, nu = n * nx1, n * nu1
    A = kron(Matrix(1.0I, n, n), Ad); B = kron(Matrix(1.0I, n, n), Bd)
    Lap = zeros(n, n)
    for (i, j) in E
        Lap[i, i] += 1; Lap[j, j] += 1; Lap[i, j] -= 1; Lap[j, i] -= 1
    end
    Pi = zeros(nx1, nx1)
    for a in pidx
        Pi[a, a] = 1
    end
    Qs = HS * (W_P * kron(Matrix(1.0I, n, n), Pi) + W_F * kron(Lap, Pi)) + sigma * I
    QN = W_P * kron(Matrix(1.0I, n, n), Pi) + sigma * I
    Q = [k < N ? copy(Qs) : copy(QN) for k in 1:N]
    R = (HS * W_U + rho_box + sigma) * Matrix(1.0I, nu, nu)
    W = RiccatiLQ(A, B, Q, R, N)
    q = [zeros(nx) for _ in 1:N]; r = [zeros(nu) for _ in 1:N]
    for k in 1:(N-1), i in 1:n
        rp = refpos(n, i, t0 + k * HS, np)
        for (a, c) in enumerate(pidx)
            q[k][(i-1)*nx1+c] = -HS * W_P * rp[a]
        end
    end
    return W, q, r
end

"Residual of a Riccati solution in the KKT conditions of the LQ problem (stationarity and dynamics)."
function riccati_residual(W::RiccatiLQ, q, r, x0, x, u, lam)
    A, B, N = W.A, W.B, W.N
    res = 0.0; scale = 0.0
    for k in 0:(N-1)
        xk = k == 0 ? x0 : x[k]
        # dynamics
        res = max(res, norm(x[k+1] - A * xk - B * u[k+1], Inf))
        # stationarity in u_k: R u + r + B' lam_{k+1} = 0
        res = max(res, norm(W.R * u[k+1] + r[k+1] + B' * lam[k+1], Inf))
        scale = max(scale, norm(r[k+1], Inf))
    end
    for k in 1:N
        # stationarity in x_k: Q x + q - lam_k + A' lam_{k+1} = 0
        g = W.Q[k] * x[k] + q[k] - lam[k]
        k < N && (g .+= A' * lam[k+1])
        res = max(res, norm(g, Inf))
        scale = max(scale, norm(q[k], Inf))
    end
    return res / max(scale, 1e-300)
end
