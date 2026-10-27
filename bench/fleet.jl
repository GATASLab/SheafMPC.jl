# fleet.jl: the fleet QP of bench/central/qp.jl with a measured state x0 and a
# clock t0 (receding horizon), and the shift maps for warm starts.
#
# `blocked_qp_x0(n, N, b; t0, x0)` is qp.jl's `blocked_qp` with the initial
# state x_0 = x0[i] instead of 0 (qp.jl fixes x_0 = 0): x0 propagates through
# the affine part m of the substitution, so it enters q, c and the equality
# right-hand side. At x0 = 0 it is identical to `blocked_qp` (checked in
# `check_fleet`).

function blocked_qp_x0(n, N, b; t0 = 0.4, x0 = [zeros(4) for _ in 1:n])
    N % b == 0 || throw(ArgumentError("b = $b must divide N = $N"))
    Pz, qz, c, X, U = objective_z(n, N; t0 = t0)
    nz1 = 6N
    starts = [k for k in b:b:(N-1)]
    ns = length(starts)
    ny1 = 4ns + 2N
    Yu(i, k) = (i - 1) * ny1 + 4ns + 2k .+ (1:2)
    MI = Int[]; MJ = Int[]; MV = Float64[]; m = zeros(n * nz1)
    EI = Int[]; EJ = Int[]; EV = Float64[]; beq = Float64[]; row = 0
    for i in 1:n
        cols = collect(((i - 1) * ny1 + 1):(i * ny1))
        Mx = zeros(4, ny1); mx = copy(x0[i])
        sidx = Dict(k => j for (j, k) in enumerate(starts))
        for k in 1:N
            Mprev, mprev = Mx, mx
            Su = zeros(2, ny1); Su[:, 4ns + 2(k - 1) .+ (1:2)] .= I(2)
            prop = Adyn * Mprev + Bdyn * Su
            if haskey(sidx, k)
                j = sidx[k]
                Mx = zeros(4, ny1); Mx[:, 4(j - 1) .+ (1:4)] .= I(4); mx = zeros(4)
                for a in 1:4
                    row += 1
                    for cc in 1:ny1
                        v = Mx[a, cc] - prop[a, cc]
                        v != 0 && (push!(EI, row); push!(EJ, cols[cc]); push!(EV, v))
                    end
                    push!(beq, (Adyn * mprev)[a])
                end
            else
                Mx = prop; mx = Adyn * mprev
            end
            zr = X(i, k)
            for a in 1:4, cc in 1:ny1
                Mx[a, cc] != 0 && (push!(MI, zr[a]); push!(MJ, cols[cc]); push!(MV, Mx[a, cc]))
            end
            m[zr] .= mx
        end
        for k in 0:(N-1), a in 1:2
            push!(MI, U(i, k)[a]); push!(MJ, Yu(i, k)[a]); push!(MV, 1.0)
        end
    end
    ny = n * ny1
    M = sparse(MI, MJ, MV, n * nz1, ny)
    P = SparseMatrixCSC(Symmetric(M' * Pz * M, :U)); P = (P + P') / 2
    q = M' * (Pz * m + qz)
    c2 = c + 0.5 * dot(m, Pz * m) + dot(qz, m)
    # the stage-0 cost of x_0 (constant): tracking and formation at t0
    for i in 1:n, a in 1:2
        c2 += 0.5 * H * WP * (x0[i][a]^2 - 2 * x0[i][a] * refpos(n, i, t0)[a])
    end
    for (i, j) in ring(n), a in 1:2
        c2 += 0.5 * H * WF * (x0[i][a] - x0[j][a])^2
    end
    Aeq = sparse(EI, EJ, EV, row, ny)
    ubox = [Yu(i, k)[a] for i in 1:n for k in 0:(N-1) for a in 1:2]
    return BlockedQP(droptol!(P, 1e-14), q, c2, Aeq, beq, ubox, M, m, n, N, b)
end

"Indices of agent i's kept states, inputs and equality rows in the blocked variables `y`."
function fleet_layout(Q)
    n, N, b = Q.n, Q.N, Q.b
    starts = [k for k in b:b:(N-1)]
    ns = length(starts)
    ny1 = 4ns + 2N
    Ys(i, j) = (i - 1) * ny1 + 4(j - 1) .+ (1:4)
    Yu(i, k) = (i - 1) * ny1 + 4ns + 2k .+ (1:2)
    return (; starts, ns, ny1, Ys, Yu)
end

"The first input of every agent in the solution `y`."
first_inputs(Q, y) = (L = fleet_layout(Q); [y[L.Yu(i, 0)] for i in 1:Q.n])

"""
    shift_maps(Q, cone) -> (xmap, ymap)

Index maps for the shifted warm start (`warm_start_shifted!`): the plan moved
one instant earlier, the last instant repeated. Only for b = 1 (every state a
variable) and b = N (inputs only), where a shifted plan is again a vector of the
same blocked variables. Row order: equality rows (agent, kept state, component),
then the input rows (box: agent, instant, component; soc: agent, instant, the
three rows of the cone).
"""
function shift_maps(Q, cone::String)
    n, N, b = Q.n, Q.N, Q.b
    (b == 1 || b == N) || throw(ArgumentError("shift maps for b = 1 or b = N only"))
    L = fleet_layout(Q)
    ny = length(Q.q)
    xmap = zeros(Int, ny)
    for i in 1:n
        for j in 1:L.ns                     # b = 1: kept state j is x_j, j = 1..N-1
            jo = min(j + 1, L.ns)
            xmap[L.Ys(i, j)] .= L.Ys(i, jo)
        end
        for k in 0:(N-1)
            ko = min(k + 1, N - 1)
            xmap[L.Yu(i, k)] .= L.Yu(i, ko)
        end
    end
    me = size(Q.Aeq, 1)
    rows_per_agent = 4 * L.ns
    ymap = Int[]
    for i in 1:n, j in 1:L.ns, a in 1:4
        jo = min(j + 1, L.ns)
        push!(ymap, (i - 1) * rows_per_agent + 4(jo - 1) + a)
    end
    @assert length(ymap) == me
    if cone == "box"
        for i in 1:n, k in 0:(N-1), a in 1:2
            ko = min(k + 1, N - 1)
            push!(ymap, me + ((i - 1) * N + ko) * 2 + a)
        end
    else
        for i in 1:n, k in 0:(N-1), r in 1:3
            ko = min(k + 1, N - 1)
            push!(ymap, me + ((i - 1) * N + ko) * 3 + r)
        end
    end
    return xmap, ymap
end

"Plant step of every agent under its first input."
plant_step(x0, u0) = [Adyn * x0[i] + Bdyn * u0[i] for i in eachindex(x0)]

function check_fleet()
    for n in (1, 4), b in (1, 4, 24)
        Q1 = blocked_qp(n, 24, b); Q2 = blocked_qp_x0(n, 24, b)
        @assert Q1.P ≈ Q2.P && Q1.q ≈ Q2.q && Q1.Aeq ≈ Q2.Aeq && Q1.beq ≈ Q2.beq && Q1.c ≈ Q2.c
    end
    return true
end
