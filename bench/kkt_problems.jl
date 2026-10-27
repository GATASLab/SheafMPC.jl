# kkt_problems.jl: the multi-agent MPC programs of the KKT kernel benchmark and
# their KKT matrices.
#
# `fleet_problem(n, N; graph, b, dyn)` is the fleet QP of the paper's
# centralized benchmark (bench/central/qp.jl: stage cost h * (1/2)(WP ||p - r||^2
# + WU ||u||^2 + WF sum_edges ||p_i - p_j||^2), terminal (1/2) WP ||p||^2, x_0 = 0,
# box inputs), generalized to
#   graph  :ring (the paper's) or :grid (sqrt(n) x sqrt(n), 4-neighbour),
#   dyn    :di (planar double integrator, 4 + 2) or :quad (hover-linearized
#          quadrotor, 12 + 4, formation on the 3 positions),
#   b      the time blocking of the pushforward: b = 1 is the time-expanded
#          program, b = N full condensing (inputs only), between partial.
# For graph = :ring, dyn = :di it reproduces qp.jl's `blocked_qp` (checked by
# `check_against_paper`). Every variable and row carries its (agent, block)
# label, the structure the structured orderings read.

using SparseArrays, LinearAlgebra
import SheafMPC

const HS = 0.1
const W_P, W_U, W_F = 0.3, 1e-3, 0.2
const UBOX = 1.0

ring_edges(n) = n > 2 ? [(i, mod1(i + 1, n)) for i in 1:n] : n == 2 ? [(1, 2)] : Tuple{Int,Int}[]

function grid_edges(n)
    s = isqrt(n)
    s * s == n || throw(ArgumentError("grid needs a square number of agents, got $n"))
    id(a, b) = (a - 1) * s + b
    E = Tuple{Int,Int}[]
    for a in 1:s, b in 1:s
        a < s && push!(E, (id(a, b), id(a + 1, b)))
        b < s && push!(E, (id(a, b), id(a, b + 1)))
    end
    return E
end

function dynamics(dyn::Symbol)
    if dyn == :di
        A = [1 0 HS 0; 0 1 0 HS; 0 0 1 0; 0 0 0 1.0]
        B = [HS^2/2 0; 0 HS^2/2; HS 0; 0 HS]
        return A, B, 1:2
    elseif dyn == :quad
        # x = (p, v, (roll, pitch, yaw), rates), u = (thrust, torques); hover linearization
        g = 9.81; m = 0.5; J = [0.01, 0.01, 0.02]
        Ac = zeros(12, 12); Bc = zeros(12, 4)
        Ac[1:3, 4:6] = I(3)
        Ac[4, 8] = g; Ac[5, 7] = -g
        Ac[7:9, 10:12] = I(3)
        Bc[6, 1] = 1 / m
        for a in 1:3
            Bc[9+a, 1+a] = 1 / J[a]
        end
        M = exp([Ac Bc; zeros(4, 16)] * HS)
        return M[1:12, 1:12], M[1:12, 13:16], 1:3
    end
    throw(ArgumentError("unknown dynamics $dyn"))
end

refpos(n, i, t, d) = (th = 2pi * (i - 1) / n; d == 2 ? [cos(th) + 0.5 * t, sin(th)] : [cos(th) + 0.5 * t, sin(th), 0.0])

"""
    fleet_problem(n, N; graph = :ring, b = 1, dyn = :di, t0 = 0.4) -> (qp, labels)

The fleet QP as a `ConicQP` (equality rows first, then the box rows on the
inputs) and `labels = (var_agent, var_block, row_agent, row_block)`.
"""
function fleet_problem(n::Int, N::Int; graph::Symbol = :ring, b::Int = 1, dyn::Symbol = :di, t0 = 0.4)
    N % b == 0 || throw(ArgumentError("b = $b must divide N = $N"))
    Ad, Bd, pidx = dynamics(dyn)
    nx, nu = size(Bd)
    np = length(pidx)
    E = graph == :ring ? ring_edges(n) : graph == :grid ? grid_edges(n) : throw(ArgumentError("graph $graph"))
    # time-expanded objective in z = (per agent x_1..x_N, u_0..u_{N-1})
    nz1 = (nx + nu) * N
    X(i, k) = (i - 1) * nz1 + nx * (k - 1) .+ (1:nx)
    U(i, k) = (i - 1) * nz1 + nx * N + nu * k .+ (1:nu)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]; qz = zeros(n * nz1)
    add!(a, c, v) = (push!(I_, a); push!(J_, c); push!(V_, v))
    for k in 1:N
        s = k < N ? HS : 1.0
        for i in 1:n
            p = X(i, k)[pidx]
            r = k < N ? refpos(n, i, t0 + k * HS, np) : zeros(np)
            for a in 1:np
                add!(p[a], p[a], s * W_P); qz[p[a]] -= s * W_P * r[a]
            end
        end
        k < N || continue
        for (i, j) in E, a in 1:np
            pi_, pj = X(i, k)[pidx[a]], X(j, k)[pidx[a]]
            add!(pi_, pi_, s * W_F); add!(pj, pj, s * W_F); add!(pi_, pj, -s * W_F); add!(pj, pi_, -s * W_F)
        end
    end
    for k in 0:(N-1), i in 1:n, a in 1:nu
        u = U(i, k)[a]; add!(u, u, HS * W_U)
    end
    Pz = sparse(I_, J_, V_, n * nz1, n * nz1)
    # pushforward along the time blocking (kept states at the block starts after the first)
    starts = [k for k in b:b:(N-1)]
    ns = length(starts)
    ny1 = nx * ns + nu * N
    Ys(i, j) = (i - 1) * ny1 + nx * (j - 1) .+ (1:nx)
    Yu(i, k) = (i - 1) * ny1 + nx * ns + nu * k .+ (1:nu)
    MI = Int[]; MJ = Int[]; MV = Float64[]
    EI = Int[]; EJ = Int[]; EV = Float64[]; row = 0
    row_agent = Int[]; row_block = Int[]
    var_agent = zeros(Int, n * ny1); var_block = zeros(Int, n * ny1)
    sidx = Dict(k => j for (j, k) in enumerate(starts))
    for i in 1:n
        cols = ((i - 1) * ny1 + 1):(i * ny1)
        for j in 1:ns
            var_agent[Ys(i, j)] .= i; var_block[Ys(i, j)] .= j + 1
        end
        for k in 0:(N-1)
            var_agent[Yu(i, k)] .= i; var_block[Yu(i, k)] .= k ÷ b + 1
        end
        Mx = zeros(nx, ny1)
        for k in 1:N
            Su = zeros(nu, ny1); Su[:, nx * ns + nu * (k - 1) .+ (1:nu)] .= I(nu)
            prop = Ad * Mx + Bd * Su
            if haskey(sidx, k)
                j = sidx[k]
                Mx = zeros(nx, ny1); Mx[:, nx * (j - 1) .+ (1:nx)] .= I(nx)
                for a in 1:nx
                    row += 1
                    for cc in 1:ny1
                        v = Mx[a, cc] - prop[a, cc]
                        abs(v) > 1e-15 && (push!(EI, row); push!(EJ, cols[cc]); push!(EV, v))
                    end
                    push!(row_agent, i); push!(row_block, j + 1)
                end
            else
                Mx = prop
            end
            zr = X(i, k)
            for a in 1:nx, cc in 1:ny1
                abs(Mx[a, cc]) > 1e-15 && (push!(MI, zr[a]); push!(MJ, cols[cc]); push!(MV, Mx[a, cc]))
            end
        end
        for k in 0:(N-1), a in 1:nu
            push!(MI, U(i, k)[a]); push!(MJ, Yu(i, k)[a]); push!(MV, 1.0)
        end
    end
    ny = n * ny1
    M = sparse(MI, MJ, MV, n * nz1, ny)
    P = SparseMatrixCSC(Symmetric(M' * Pz * M, :U)); P = (P + P') / 2
    droptol!(P, 1e-14)
    q = M' * qz
    Aeq = sparse(EI, EJ, EV, row, ny)
    ubox = [Yu(i, k)[a] for i in 1:n for k in 0:(N-1) for a in 1:nu]
    nb = length(ubox)
    Ab = sparse(1:nb, ubox, ones(nb), nb, ny)
    append!(row_agent, var_agent[ubox]); append!(row_block, var_block[ubox])
    A = [Aeq; Ab]
    me = size(Aeq, 1)
    l = [zeros(me); fill(-UBOX, nb)]; u = [zeros(me); fill(UBOX, nb)]
    kinds = [fill(SheafMPC.ROW_EQ, me); fill(SheafMPC.ROW_INTERVAL, nb)]
    qp = SheafMPC.ConicQP(P, q, A, l, u; kinds = kinds)
    return qp, (var_agent = var_agent, var_block = var_block, row_agent = row_agent, row_block = row_block,
                nagents = n, nblocks = N ÷ b, edges = E)
end

"""
    kkt_matrix(qp; rho = 0.1, sigma = 1e-6) -> (K, n, diag_idx)

The ADMM KKT matrix of SheafMPC's setup (Ruiz-scaled data, rho per row type)
as an upper triangular CSC with every diagonal entry stored.
"""
function kkt_matrix(qp::SheafMPC.ConicQP; settings = SheafMPC.Settings())
    st = settings
    n, m = SheafMPC.nvars(qp), SheafMPC.nrows(qp)
    P = copy(qp.P); q = copy(qp.q); A = copy(qp.A)
    scl = st.scaling > 0 ? SheafMPC.ruiz_scale!(P, q, A, qp.socs, st.scaling) : SheafMPC.identity_scaling(n, m)
    l = scl.E .* qp.l; u = scl.E .* qp.u
    rt = SheafMPC._rowtypes(l, u, qp.kinds)
    xdiag = Vector{Float64}(diag(P)) .+ st.sigma
    res = SheafMPC.kkt_pattern(P, A, qp.socs)
    K, diag_idx = res[1], res[2]
    rinv = [rt[i] == SheafMPC.ROWT_EQ ? 1 / (st.rho_eq_scale * st.rho) : rt[i] == SheafMPC.ROWT_FREE ? 1 / st.rho_min :
            1 / st.rho for i in 1:m]
    SheafMPC.set_diagonal!(K, diag_idx, xdiag, rinv)
    return K, n, diag_idx
end

"Agent and block of every KKT index (variables, then rows)."
kkt_labels(lab) = (agent = [lab.var_agent; lab.row_agent], block = [lab.var_block; lab.row_block],
                   nagents = lab.nagents, nblocks = lab.nblocks, edges = lab.edges)

"qp.jl's `blocked_qp` (the paper's fleet) equals `fleet_problem(...; graph = :ring, dyn = :di)`."
function check_against_paper(paper_dir; ns = (1, 4, 6), bs = (1, 4, 24))
    haskey(ENV, "BENCH_ABAR") || (ENV["BENCH_ABAR"] = "1.0")
    isdefined(Main, :blocked_qp) || Base.include(Main, joinpath(paper_dir, "bench", "central", "qp.jl"))
    ok = true
    for n in ns, b in bs
        Q = Base.invokelatest(Main.blocked_qp, n, 24, b)
        qp, _ = fleet_problem(n, 24; b = b)
        me = size(Q.Aeq, 1)
        ok &= isapprox(Q.P, qp.P; rtol = 1e-12, atol = 1e-12) && isapprox(Q.q, qp.q; atol = 1e-12) &&
              isapprox(Q.Aeq, qp.A[1:me, :]; atol = 1e-12)
    end
    return ok
end
