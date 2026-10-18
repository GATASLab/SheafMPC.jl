# fleet.jl: the fleet formation MPC QP of the paper (mpc-sheaf-pushforward,
# bench/central/qp.jl), generalized to a measured state x0, a ring or grid
# agent graph, and box or second-order-cone inputs.
#
# n planar double integrators x = (p, v), u = a, step H; stage cost
# H * (1/2)(sum_i WP ||p_i - r_i(t)||^2 + WU ||u||^2 + WF sum_edges ||p_i - p_j||^2),
# terminal cost (1/2) sum_i WP ||p_i||^2 (acados' LINEAR_LS scaling, as in the
# paper); r_i(t) = (cos th_i + 0.5 t, sin th_i) on the ring, (gx_i + 0.5 t, gy_i)
# on the grid (agent i's grid position, unit spacing, centred); inputs
# |u_k^a| <= ABAR (box) or ||u_k|| <= ABAR (soc), ABAR = 1.0 (the paper's
# constrained setting).
#
# Variables of the time-expanded program, agent by agent: x_1..x_N, u_0..u_{N-1}.
# The partially condensed program along a blocking of the horizon into blocks
# of b instants keeps the inputs and the state at the start of every block
# after the first (b = 1 time-expanded, b = N fully condensed); it is the
# paper's `blocked_qp`, reproduced here with x0 (checked against qp.jl at
# x0 = 0 by test/test_families.jl).
#
# Rows: the kept-state equalities (agent, kept state, component), then the
# input rows (box: agent, instant, component; soc: agent, instant, the three
# rows (ABAR; -u^1; -u^2) of the cone ABAR - 0, u in SOC).

const FL_H = 0.1
const FL_WP, FL_WU, FL_WF = 0.3, 1e-3, 0.2
const FL_ABAR = 1.0
const FL_Ad = [1 0 FL_H 0; 0 1 0 FL_H; 0 0 1 0; 0 0 0 1.0]
const FL_Bd = [FL_H^2/2 0; 0 FL_H^2/2; FL_H 0; 0 FL_H]

fl_ring(n) = n > 2 ? [(i, mod1(i + 1, n)) for i in 1:n] : n == 2 ? [(1, 2)] : Tuple{Int,Int}[]
function fl_grid(n)
    s = isqrt(n); s * s == n || throw(ArgumentError("grid fleet needs a square n, got $n"))
    E = Tuple{Int,Int}[]
    idx(r, c) = (r - 1) * s + c
    for r in 1:s, c in 1:s
        c < s && push!(E, (idx(r, c), idx(r, c + 1)))
        r < s && push!(E, (idx(r, c), idx(r + 1, c)))
    end
    return E
end
fl_edges(graph::Symbol, n) = graph == :ring ? fl_ring(n) : fl_grid(n)
function fl_ref(graph::Symbol, n, i, t)
    if graph == :ring
        th = 2pi * (i - 1) / n
        return [cos(th) + 0.5 * t, sin(th)]
    end
    s = isqrt(n); r, c = divrem(i - 1, s)
    return [c - (s - 1) / 2 + 0.5 * t, r - (s - 1) / 2]
end

"Time-expanded objective (1/2) z'Pz + q'z + c, z = (per agent x_1..x_N, u_0..u_{N-1}), with x_0 = x0."
function fl_objective_z(graph, n, N, t0, x0)
    nz1 = 6N
    X(i, k) = (i - 1) * nz1 + 4(k - 1) .+ (1:4)
    U(i, k) = (i - 1) * nz1 + 4N + 2k .+ (1:2)
    I = Int[]; J = Int[]; V = Float64[]; q = zeros(n * nz1); c = 0.0
    add!(a, b, v) = (push!(I, a); push!(J, b); push!(V, v))
    E = fl_edges(graph, n)
    for k in 0:N
        s = k < N ? FL_H : 1.0
        if k == 0
            for i in 1:n, a in 1:2
                r = fl_ref(graph, n, i, t0)[a]
                c += 0.5 * FL_H * FL_WP * (x0[i][a] - r)^2
            end
            for (i, j) in E, a in 1:2
                c += 0.5 * FL_H * FL_WF * (x0[i][a] - x0[j][a])^2
            end
        else
            for i in 1:n
                p = X(i, k)[1:2]
                r = k < N ? fl_ref(graph, n, i, t0 + k * FL_H) : [0.0, 0.0]
                for a in 1:2
                    add!(p[a], p[a], s * FL_WP); q[p[a]] -= s * FL_WP * r[a]; c += 0.5 * s * FL_WP * r[a]^2
                end
            end
            if k < N
                for (i, j) in E, a in 1:2
                    pi_, pj = X(i, k)[a], X(j, k)[a]
                    add!(pi_, pi_, s * FL_WF); add!(pj, pj, s * FL_WF); add!(pi_, pj, -s * FL_WF); add!(pj, pi_, -s * FL_WF)
                end
            end
        end
        if k < N
            for i in 1:n, a in 1:2
                u = U(i, k)[a]; add!(u, u, s * FL_WU)
            end
        end
    end
    return sparse(I, J, V, n * nz1, n * nz1), q, c, X, U
end

"""
    fleet_qp(; n, N = 24, b = 1, graph = :ring, cone = :box, t0 = 0.4, x0 = zeros) -> QP

The fleet program pushed forward along the blocking of the horizon into
blocks of b instants (b divides N). For b = 1 and box inputs the QP carries
its stage-wise form (the fleet stacked into every stage, as acados needs).
"""
function fleet_qp(; n, N = 24, b = 1, graph = :ring, cone = :box, t0 = 0.4, x0 = [zeros(4) for _ in 1:n])
    N % b == 0 || throw(ArgumentError("b = $b must divide N = $N"))
    Pz, qz, c, X, U = fl_objective_z(graph, n, N, t0, x0)
    nz1 = 6N
    starts = [k for k in b:b:(N-1)]
    ns = length(starts)
    ny1 = 4ns + 2N
    Yu(i, k) = (i - 1) * ny1 + 4ns + 2k .+ (1:2)
    MI = Int[]; MJ = Int[]; MV = Float64[]; mvec = zeros(n * nz1)
    EI = Int[]; EJ = Int[]; EV = Float64[]; beq = Float64[]; row = 0
    sidx = Dict(k => j for (j, k) in enumerate(starts))
    for i in 1:n
        cols = collect(((i - 1) * ny1 + 1):(i * ny1))
        Mx = zeros(4, ny1); mx = copy(x0[i])
        for k in 1:N
            Mprev, mprev = Mx, mx
            Su = zeros(2, ny1); Su[:, 4ns + 2(k - 1) .+ (1:2)] .= I(2)
            prop = FL_Ad * Mprev + FL_Bd * Su
            if haskey(sidx, k)
                j = sidx[k]
                Mx = zeros(4, ny1); Mx[:, 4(j - 1) .+ (1:4)] .= I(4); mx = zeros(4)
                for a in 1:4
                    row += 1
                    for cc in 1:ny1
                        v = Mx[a, cc] - prop[a, cc]
                        v != 0 && (push!(EI, row); push!(EJ, cols[cc]); push!(EV, v))
                    end
                    push!(beq, (FL_Ad * mprev)[a])
                end
            else
                Mx = prop; mx = FL_Ad * mprev
            end
            zr = X(i, k)
            for a in 1:4, cc in 1:ny1
                Mx[a, cc] != 0 && (push!(MI, zr[a]); push!(MJ, cols[cc]); push!(MV, Mx[a, cc]))
            end
            mvec[zr] .= mx
        end
        for k in 0:(N-1), a in 1:2
            push!(MI, U(i, k)[a]); push!(MJ, Yu(i, k)[a]); push!(MV, 1.0)
        end
    end
    ny = n * ny1
    M = sparse(MI, MJ, MV, n * nz1, ny)
    P = SparseMatrixCSC(Symmetric(M' * Pz * M, :U)); P = (P + P') / 2
    droptol!(P, 1e-14)
    q = M' * (Pz * mvec + qz)
    c2 = c + 0.5 * dot(mvec, Pz * mvec) + dot(qz, mvec)
    Aeq = sparse(EI, EJ, EV, row, ny)
    ubox = [Yu(i, k)[a] for i in 1:n for k in 0:(N-1) for a in 1:2]
    nb = length(ubox)
    meta = Dict{String,Any}("family" => "fleet", "n" => n, "N" => N, "b" => b, "graph" => string(graph),
                            "cone" => string(cone), "t0" => t0, "abar" => FL_ABAR)
    name = "fleet_$(graph)_$(cone)_n$(n)_N$(N)_b$(b)"
    if cone == :box
        Ab = sparse(1:nb, ubox, ones(nb), nb, ny)
        A = [Aeq; Ab]; l = [beq; fill(-FL_ABAR, nb)]; u = [beq; fill(FL_ABAR, nb)]
        stage = b == 1 ? fleet_stage(graph, n, N, t0, x0) : nothing
        return QP(name, P, q, A, l, u; c = c2, stage = stage, meta = meta)
    end
    SI = Int[]; SJ = Int[]; SV = Float64[]; sb = Float64[]; r = 0; socs = UnitRange{Int}[]
    me = size(Aeq, 1)
    for p in 1:2:nb
        push!(socs, (me + r + 1):(me + r + 3))
        r += 1; push!(sb, FL_ABAR)
        for a in 0:1
            r += 1; push!(SI, r); push!(SJ, ubox[p+a]); push!(SV, -1.0); push!(sb, 0.0)
        end
    end
    A = [Aeq; sparse(SI, SJ, SV, r, ny)]
    l = [beq; fill(-Inf, r)]; u = [beq; fill(Inf, r)]
    return QP(name, P, q, A, l, u; c = c2, socs = socs, socb = [zeros(me); sb], meta = meta)
end

"Stage-wise form of the time-expanded box fleet (agents stacked into every stage), with the cmap of fleet_qp's variable order."
function fleet_stage(graph, n, N, t0, x0)
    nx, nu = 4n, 2n
    A = kron(I(n), FL_Ad); B = kron(I(n), FL_Bd)
    Lap = zeros(n, n)
    for (i, j) in fl_edges(graph, n)
        Lap[i, i] += 1; Lap[j, j] += 1; Lap[i, j] -= 1; Lap[j, i] -= 1
    end
    Ppos = zeros(4, 4); Ppos[1, 1] = Ppos[2, 2] = 1
    Qrun = FL_H * (FL_WP * kron(I(n), Ppos) + FL_WF * kron(Lap, Ppos))
    QN = FL_WP * kron(I(n), Ppos)
    R = FL_H * FL_WU * Matrix(I(nu))
    qx = Vector{Vector{Float64}}(undef, N + 1)
    for k in 0:N
        v = zeros(nx)
        if 1 <= k < N
            for i in 1:n
                v[4(i-1) .+ (1:2)] .= -FL_H * FL_WP .* fl_ref(graph, n, i, t0 + k * FL_H)
            end
        end
        qx[k+1] = v
    end
    o = make_ocp(N = N, A = A, B = B, Q = Qrun, R = R, QN = QN, qx = qx, ru = [zeros(nu) for _ in 1:N+1],
                 x0 = reduce(vcat, x0), ulb = fill(-FL_ABAR, nu), uub = fill(FL_ABAR, nu))
    # b = 1 keeps x_1..x_{N-1} (x_N is substituted), then u_0..u_{N-1}, agent by agent
    ns = N - 1; ny1 = 4ns + 2N
    cmap = Vector{NTuple{3,Int}}(undef, n * ny1)
    for i in 1:n
        for k in 1:ns, a in 1:4
            cmap[(i-1)*ny1+4(k-1)+a] = (k, 1, 4(i-1) + a)
        end
        for k in 0:N-1, a in 1:2
            cmap[(i-1)*ny1+4ns+2k+a] = (k, 2, 2(i-1) + a)
        end
    end
    return StageOCP(ntuple(j -> getfield(o, j), fieldcount(StageOCP) - 1)..., cmap)
end

"Indices of agent i's first input in fleet_qp's variables."
function fleet_first_inputs(p::QP)
    n, N, b = p.meta["n"], p.meta["N"], p.meta["b"]
    ns = length(b:b:(N-1)); ny1 = 4ns + 2N
    return [(i - 1) * ny1 + 4ns .+ (1:2) for i in 1:n]
end

"""
Warm-start maps (the plan moved one instant earlier, the last instant
repeated) for b = 1 and b = N; `nothing` for other blockings.
"""
function fleet_shift_maps(p::QP)
    n, N, b = p.meta["n"], p.meta["N"], p.meta["b"]
    (b == 1 || b == N) || return nothing
    starts = [k for k in b:b:(N-1)]; ns = length(starts); ny1 = 4ns + 2N
    Ys(i, j) = (i - 1) * ny1 + 4(j - 1) .+ (1:4)
    Yu(i, k) = (i - 1) * ny1 + 4ns + 2k .+ (1:2)
    xmap = zeros(Int, n * ny1)
    for i in 1:n
        for j in 1:ns; xmap[Ys(i, j)] .= Ys(i, min(j + 1, ns)); end
        for k in 0:N-1; xmap[Yu(i, k)] .= Yu(i, min(k + 1, N - 1)); end
    end
    me = 4 * n * ns
    ymap = Int[]
    for i in 1:n, j in 1:ns, a in 1:4
        push!(ymap, (i - 1) * 4ns + 4(min(j + 1, ns) - 1) + a)
    end
    w = p.meta["cone"] == "box" ? 2 : 3
    for i in 1:n, k in 0:N-1, r in 1:w
        push!(ymap, me + ((i - 1) * N + min(k + 1, N - 1)) * w + r)
    end
    return xmap, ymap
end
