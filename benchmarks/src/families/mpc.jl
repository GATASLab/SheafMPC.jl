# mpc.jl: single-agent and textbook MPC families, all through StageOCP and
# stage_canonical (time-expanded, x_0 substituted, banded variable order).
#
# double integrator (di): 3-D point mass, x = (p, v) in R^6, u = a in R^3,
#   step 0.1; cost Q = diag(10 I, I), R = 0.1 I, Q_N = Q; reference p_r = (1, 1, 1)
#   (as the linear term -Q x_r); box variant: |u_i| <= 1 and |v_i| <= 2 on
#   x_1..x_N; soc variant: ||u|| <= 1 only (equalities and cones).
# quadrotor (quad): the linearized quadcopter of the OSQP documentation's MPC
#   example (12 states, 4 inputs, hover-relative), Q = diag(0,0,10,10,10,10,0,0,0,5,5,5),
#   R = 0.1 I, Q_N = Q, reference x_r = e_3 (climb to z = 1), input box
#   [9.6, 13] - 10.5916, attitude bounds |phi|, |theta| <= pi/6, and
#   x_6 >= -1 on x_1..x_N.
# chain of masses (chain): the mass-spring test problem of HPIPM
#   (test_problems/test_d_ocp.c, mass_spring_system): M unit masses in a row
#   between two walls, unit springs, Ts = 0.5 (exact discretization), nx = 2M,
#   nu = M - 1 forces on the first M - 1 masses; Q = I, R = 2 I (HPIPM's R),
#   Q_N = Q; |u| <= 0.5 and positions |p| <= 4 (the bounds of Wang and Boyd's
#   oscillating masses); x_0 = (2.5, 2.5, 0, ...) as in HPIPM's test.
# OSQP random MPC (osqprand): Stellato et al. 2020, osqp_benchmarks
#   problem_classes/control.py, reproduced bit for bit from numpy's RandomState
#   in gen/osqp_random.py (A, B, Q, Q_N, R, bounds, x0 per size and seed); the
#   QP is built exactly as control.py builds it (x_0 as a variable fixed by an
#   equality, P = 2 blkdiag(Q, ..., Q_N, R, ...), state bounds on x_0..x_T,
#   input bounds), T = 10. Its stage form (for HPIPM) eliminates x_0.

function di_ocp(; N, x0, cone = :box)
    h = 0.1
    A = [I(3) h*I(3); zeros(3, 3) I(3)] |> Matrix{Float64}
    B = [h^2/2*I(3); h*I(3)] |> Matrix{Float64}
    Q = Matrix(Diagonal([fill(10.0, 3); fill(1.0, 3)])); R = 0.1 * Matrix(I(3))
    xr = [1.0, 1, 1, 0, 0, 0]
    qx = [-(Q * xr) for _ in 1:N+1]
    if cone == :box
        return make_ocp(N = N, A = A, B = B, Q = Q, R = R, QN = Q, qx = qx, ru = [zeros(3) for _ in 1:N+1], x0 = x0,
                        ulb = fill(-1.0, 3), uub = fill(1.0, 3),
                        xlb = [fill(-Inf, 3); fill(-2.0, 3)], xub = [fill(Inf, 3); fill(2.0, 3)])
    end
    return make_ocp(N = N, A = A, B = B, Q = Q, R = R, QN = Q, qx = qx, ru = [zeros(3) for _ in 1:N+1], x0 = x0)
end

"Add ||u_k|| <= 1 cones (k = 0..N-1) to a banded canonical QP without input rows."
function add_input_balls(p::QP; ubar = 1.0)
    o = p.stage
    uo, _, n = stage_offsets(o)
    m0 = ncons(p); nu = o.nu[1]
    I = Int[]; J = Int[]; V = Float64[]; sb = Float64[]; socs = UnitRange{Int}[]; r = 0
    for k in 0:o.N-1
        push!(socs, (m0 + r + 1):(m0 + r + 1 + nu))
        r += 1; push!(sb, ubar)
        for i in 1:nu
            r += 1; push!(I, r); push!(J, uo[k+1] + i); push!(V, -1.0); push!(sb, 0.0)
        end
    end
    A = [p.A; sparse(I, J, V, r, n)]
    return QP(p.name, p.P, p.q, A, [p.l; fill(-Inf, r)], [p.u; fill(Inf, r)]; c = p.c, socs = socs,
              socb = [zeros(m0); sb], stage = nothing, meta = p.meta)
end

const QUAD_Ad = [
    1.0 0 0 0 0 0 0.1 0 0 0 0 0
    0 1 0 0 0 0 0 0.1 0 0 0 0
    0 0 1 0 0 0 0 0 0.1 0 0 0
    0.0488 0 0 1 0 0 0.0016 0 0 0.0992 0 0
    0 -0.0488 0 0 1 0 0 -0.0016 0 0 0.0992 0
    0 0 0 0 0 1 0 0 0 0 0 0.0992
    0 0 0 0 0 0 1 0 0 0 0 0
    0 0 0 0 0 0 0 1 0 0 0 0
    0 0 0 0 0 0 0 0 1 0 0 0
    0.9734 0 0 0 0 0 0.0488 0 0 0.9846 0 0
    0 -0.9734 0 0 0 0 0 -0.0488 0 0 0.9846 0
    0 0 0 0 0 0 0 0 0 0 0 0.9846]
const QUAD_Bd = [
    0 -0.0726 0 0.0726
    -0.0726 0 0.0726 0
    -0.0152 0.0152 -0.0152 0.0152
    0 -0.0006 -0.0000 0.0006
    0.0006 0 -0.0006 0
    0.0106 0.0106 0.0106 0.0106
    0 -1.4512 0 1.4512
    -1.4512 0 1.4512 0
    -0.3049 0.3049 -0.3049 0.3049
    0 -0.0236 0 0.0236
    0.0236 0 -0.0236 0
    0.2107 0.2107 0.2107 0.2107]

function quad_ocp(; N, x0)
    u0 = 10.5916
    Q = Matrix(Diagonal([0, 0, 10, 10, 10, 10, 0, 0, 0, 5, 5, 5.0])); R = 0.1 * Matrix(I(4))
    xr = zeros(12); xr[3] = 1.0
    qx = [-(Q * xr) for _ in 1:N+1]
    xlb = [-pi/6, -pi/6, -Inf, -Inf, -Inf, -1, -Inf, -Inf, -Inf, -Inf, -Inf, -Inf]
    xub = [pi/6, pi/6, Inf, Inf, Inf, Inf, Inf, Inf, Inf, Inf, Inf, Inf]
    return make_ocp(N = N, A = QUAD_Ad, B = QUAD_Bd, Q = Q, R = R, QN = Q, qx = qx, ru = [zeros(4) for _ in 1:N+1],
                    x0 = x0, ulb = fill(9.6 - u0, 4), uub = fill(13.0 - u0, 4), xlb = xlb, xub = xub)
end

"Exact zero-order-hold discretization of x' = Ac x + Bc u (Ac invertible)."
function c2d(Ac, Bc, Ts)
    Ad = exp(Ts * Ac)
    Bd = (Ad - I) * (Ac \ Bc)
    return Ad, Bd
end

function chain_dynamics(M)
    nx = 2M; nu = M - 1
    T = Matrix(SymTridiagonal(fill(-2.0, M), ones(M - 1)))
    Ac = [zeros(M, M) I(M); T zeros(M, M)]
    Bc = zeros(nx, nu); for i in 1:nu; Bc[M+i, i] = 1.0; end
    return c2d(Ac, Bc, 0.5)
end

function chain_ocp(; M, N, x0)
    A, B = chain_dynamics(M)
    nx, nu = size(B)
    Q = Matrix(1.0I, nx, nx); R = 2.0 * Matrix(I(nu))
    return make_ocp(N = N, A = A, B = B, Q = Q, R = R, QN = Q, qx = [zeros(nx) for _ in 1:N+1], ru = [zeros(nu) for _ in 1:N+1],
                    x0 = x0, ulb = fill(-0.5, nu), uub = fill(0.5, nu),
                    xlb = [fill(-4.0, M); fill(-Inf, M)], xub = [fill(4.0, M); fill(Inf, M)])
end
chain_x0(M) = (x = zeros(2M); x[1] = 2.5; x[2] = 2.5; x)

# ---------------------------------------------------------------------------
# OSQP random MPC (Stellato et al. 2020)
# ---------------------------------------------------------------------------

"Model data written by gen/osqp_random.py: A, B, Q (diag), QN, R, umin, umax, xmin, xmax, x0."
function read_osqprand(path)
    d = JSON.parsefile(path)
    mat(v) = reduce(hcat, [Float64.(r) for r in v])'  |> Matrix{Float64}
    return (nx = d["nx"], nu = d["nu"], T = d["T"], seed = d["seed"], A = mat(d["A"]), B = mat(d["B"]),
            Q = Float64.(d["Qdiag"]), QN = mat(d["QN"]), R = mat(d["R"]),
            umin = Float64.(d["umin"]), umax = Float64.(d["umax"]), xmin = Float64.(d["xmin"]),
            xmax = Float64.(d["xmax"]), x0 = Float64.(d["x0"]), scipy = get(d, "scipy", ""), numpy = get(d, "numpy", ""))
end

"""
    osqprand_qp(m, x0) -> QP

control.py's QP: variables (x_0..x_T, u_0..u_{T-1}); rows: dynamics with x_0 = x0
(l = u = (-x0, 0, ..., 0)), state bounds on x_0..x_T, input bounds; P = 2 blkdiag(kron(I_T, Q), QN, kron(I_T, R)).
"""
function osqprand_qp(m, x0)
    nx, nu, T = m.nx, m.nu, m.T
    Px = kron(sparse(1.0I, T, T), spdiagm(m.Q))
    Pu = kron(sparse(1.0I, T, T), sparse(m.R))
    P = 2.0 * blockdiag(Px, sparse(m.QN), Pu)
    nv = (T + 1) * nx + T * nu
    q = zeros(nv)
    Ax = kron(sparse(1.0I, T + 1, T + 1), -sparse(1.0I, nx, nx)) + kron(spdiagm(-1 => ones(T)), sparse(m.A))
    Au = kron([spzeros(1, T); sparse(1.0I, T, T)], sparse(m.B))
    Adyn = [Ax Au]
    beq = [-x0; zeros(T * nx)]
    A = [Adyn; sparse(1.0I, nv, nv)]
    l = [beq; repeat(m.xmin, T + 1); repeat(m.umin, T)]
    u = [beq; repeat(m.xmax, T + 1); repeat(m.umax, T)]
    # stage form: x_0 eliminated (its equality and bounds), stage costs Q, Q_N and R (times 2)
    o = make_ocp(N = T, A = m.A, B = m.B, Q = 2.0 * Matrix(Diagonal(m.Q)), R = 2.0 * m.R, QN = 2.0 * m.QN,
                 qx = [zeros(nx) for _ in 1:T+1], ru = [zeros(nu) for _ in 1:T+1], x0 = x0,
                 ulb = m.umin, uub = m.umax, xlb = m.xmin, xub = m.xmax)
    cmap = Vector{NTuple{3,Int}}(undef, nv)
    for k in 0:T, i in 1:nx; cmap[k*nx+i] = (k, 1, i); end
    for k in 0:T-1, i in 1:nu; cmap[(T+1)*nx+k*nu+i] = (k, 2, i); end
    st = StageOCP(ntuple(j -> getfield(o, j), fieldcount(StageOCP) - 1)..., cmap)
    meta = Dict{String,Any}("family" => "osqprand", "nx" => nx, "nu" => nu, "T" => T, "seed" => m.seed)
    return QP("osqprand_nx$(nx)_s$(m.seed)", P, q, A, l, u; stage = st, meta = meta)
end

"Warm-start maps for control.py's variable and row order (one stage earlier, last repeated)."
function osqprand_shift_maps(p::QP)
    nx, nu, T = p.meta["nx"], p.meta["nu"], p.meta["T"]
    nv = (T + 1) * nx + T * nu
    xmap = zeros(Int, nv)
    for k in 0:T, i in 1:nx; xmap[k*nx+i] = min(k + 1, T) * nx + i; end
    for k in 0:T-1, i in 1:nu; xmap[(T+1)*nx+k*nu+i] = (T + 1) * nx + min(k + 1, T - 1) * nu + i; end
    me = (T + 1) * nx
    ymap = zeros(Int, me + nv)
    for k in 0:T, i in 1:nx; ymap[k*nx+i] = min(k + 1, T) * nx + i; end
    for j in 1:nv; ymap[me+j] = me + xmap[j]; end
    return xmap, ymap
end
osqprand_first_input(p::QP, x) = (o = p.meta; x[(o["T"]+1)*o["nx"] .+ (1:o["nu"])])
