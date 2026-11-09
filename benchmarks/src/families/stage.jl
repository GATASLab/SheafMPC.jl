# stage.jl: build the canonical sparse QP of a StageOCP (time-expanded, x_0
# eliminated), its closed-loop sequence, and the shift maps for warm starts.
#
# Variable order (banded): u_0, x_1, u_1, x_2, ..., u_{N-1}, x_N.
# Row order: dynamics x_{k+1} - A_k x_k - B_k u_k = b_k (+ A_0 x0 for k = 0),
# stage by stage; then, stage by stage k = 0..N, the bounded inputs, the bounded
# states (k >= 1) and the general rows of that stage.

"Stage data with every field filled (time-invariant A, B, Q, R; stage-dependent q, r)."
function make_ocp(; N, A, B, Q, R, QN, qx, ru, x0, S = nothing, b = nothing, xlb = nothing, xub = nothing,
                  ulb = nothing, uub = nothing, xboundN = true)
    nx, nu = size(B)
    S === nothing && (S = zeros(nu, nx))
    b === nothing && (b = zeros(nx))
    idx(lb, ub) = lb === nothing ? Int[] : [i for i in eachindex(lb) if isfinite(lb[i]) || isfinite(ub[i])]
    ix = idx(xlb, xub); iu = idx(ulb, uub)
    big(v) = [isfinite(t) ? t : copysign(1e20, t) for t in v]
    xl = xlb === nothing ? Float64[] : big(xlb[ix]); xu = xub === nothing ? Float64[] : big(xub[ix])
    ul = ulb === nothing ? Float64[] : big(ulb[iu]); uu = uub === nothing ? Float64[] : big(uub[iu])
    ocp = StageOCP(N, fill(nx, N + 1), [fill(nu, N); 0],
                   [Matrix{Float64}(A) for _ in 1:N], [Matrix{Float64}(B) for _ in 1:N], [Vector{Float64}(b) for _ in 1:N],
                   [k == N + 1 ? Matrix{Float64}(QN) : Matrix{Float64}(Q) for k in 1:N+1],
                   [k == N + 1 ? zeros(0, nx) : Matrix{Float64}(S) for k in 1:N+1],
                   [k == N + 1 ? zeros(0, 0) : Matrix{Float64}(R) for k in 1:N+1],
                   [Vector{Float64}(qx[k]) for k in 1:N+1], [k == N + 1 ? Float64[] : Vector{Float64}(ru[k]) for k in 1:N+1],
                   [(k == 1 || (k == N + 1 && !xboundN)) ? Int[] : ix for k in 1:N+1],
                   [(k == 1 || (k == N + 1 && !xboundN)) ? Float64[] : xl for k in 1:N+1],
                   [(k == 1 || (k == N + 1 && !xboundN)) ? Float64[] : xu for k in 1:N+1],
                   [k == N + 1 ? Int[] : iu for k in 1:N+1],
                   [k == N + 1 ? Float64[] : ul for k in 1:N+1],
                   [k == N + 1 ? Float64[] : uu for k in 1:N+1],
                   [zeros(0, nx) for _ in 1:N+1], [zeros(0, k == N + 1 ? 0 : nu) for k in 1:N+1],
                   [Float64[] for _ in 1:N+1], [Float64[] for _ in 1:N+1],
                   Vector{Float64}(x0), NTuple{3,Int}[])
    return ocp
end

"Offsets of u_k and x_k in the banded variable order."
function stage_offsets(o::StageOCP)
    N = o.N
    uo = zeros(Int, N + 1); xo = zeros(Int, N + 1)
    p = 0
    for k in 0:N-1
        uo[k+1] = p; p += o.nu[k+1]
        xo[k+2] = p; p += o.nx[k+2]
    end
    return uo, xo, p
end

"""
    stage_canonical(name, ocp; meta) -> QP

The time-expanded canonical QP of `ocp` (x_0 = ocp.x0 substituted), with
`ocp.cmap` filled in and `stage = ocp`. The constant collects the x_0 terms.
"""
function stage_canonical(name, o::StageOCP; meta = Dict{String,Any}())
    N = o.N
    uo, xo, n = stage_offsets(o)
    cmap = Vector{NTuple{3,Int}}(undef, n)
    for k in 0:N-1
        for i in 1:o.nu[k+1]; cmap[uo[k+1]+i] = (k, 2, i); end
        for i in 1:o.nx[k+2]; cmap[xo[k+2]+i] = (k + 1, 1, i); end
    end
    I = Int[]; J = Int[]; V = Float64[]; q = zeros(n); c = 0.0
    function blk!(r0, c0, M, s = 1.0)
        for jj in 1:size(M, 2), ii in 1:size(M, 1)
            v = M[ii, jj]; v == 0 && continue
            push!(I, r0 + ii); push!(J, c0 + jj); push!(V, s * v)
        end
    end
    x0 = o.x0
    for k in 0:N
        Q = o.Q[k+1]; qx = o.qx[k+1]
        if k == 0
            c += 0.5 * dot(x0, Q * x0) + dot(qx, x0)
            if o.nu[1] > 0
                blk!(uo[1], uo[1], o.R[1])
                q[uo[1] .+ (1:o.nu[1])] .+= o.ru[1] .+ o.S[1] * x0
            end
        else
            blk!(xo[k+1], xo[k+1], Q)
            q[xo[k+1] .+ (1:o.nx[k+1])] .+= qx
            if k < N && o.nu[k+1] > 0
                blk!(uo[k+1], uo[k+1], o.R[k+1])
                blk!(uo[k+1], xo[k+1], o.S[k+1])          # u'S x: the (u, x) block S and its transpose
                blk!(xo[k+1], uo[k+1], Matrix(o.S[k+1]'))
                q[uo[k+1] .+ (1:o.nu[k+1])] .+= o.ru[k+1]
            end
        end
    end
    P = sparse(I, J, V, n, n)
    AI = Int[]; AJ = Int[]; AV = Float64[]; l = Float64[]; u = Float64[]; row = 0
    ablk!(r0, c0, M, s) = for jj in 1:size(M, 2), ii in 1:size(M, 1)
        v = M[ii, jj]; v == 0 && continue
        push!(AI, r0 + ii); push!(AJ, c0 + jj); push!(AV, s * v)
    end
    for k in 0:N-1
        nxk1 = o.nx[k+2]
        for i in 1:nxk1; push!(AI, row + i); push!(AJ, xo[k+2] + i); push!(AV, 1.0); end
        ablk!(row, uo[k+1], o.B[k+1], -1.0)
        rhs = copy(o.b[k+1])
        if k == 0
            rhs .+= o.A[1] * x0
        else
            ablk!(row, xo[k+1], o.A[k+1], -1.0)
        end
        append!(l, rhs); append!(u, rhs); row += nxk1
    end
    unb(v) = abs(v) >= 1e19 ? copysign(Inf, v) : v
    for k in 0:N
        for (t, i) in enumerate(o.idxbu[k+1])
            row += 1; push!(AI, row); push!(AJ, uo[k+1] + i); push!(AV, 1.0)
            push!(l, unb(o.lbu[k+1][t])); push!(u, unb(o.ubu[k+1][t]))
        end
        if k >= 1
            for (t, i) in enumerate(o.idxbx[k+1])
                row += 1; push!(AI, row); push!(AJ, xo[k+1] + i); push!(AV, 1.0)
                push!(l, unb(o.lbx[k+1][t])); push!(u, unb(o.ubx[k+1][t]))
            end
        end
        ng = length(o.lg[k+1])
        if ng > 0
            C = o.C[k+1]; D = o.D[k+1]
            k >= 1 && ablk!(row, xo[k+1], C, 1.0)
            k < N && ablk!(row, uo[k+1], D, 1.0)
            off = k == 0 ? C * x0 : zeros(ng)
            append!(l, o.lg[k+1] .- off); append!(u, o.ug[k+1] .- off); row += ng
        end
    end
    A = sparse(AI, AJ, AV, row, n)
    o2 = StageOCP(ntuple(i -> getfield(o, i), fieldcount(StageOCP) - 1)..., cmap)
    return QP(name, P, q, A, l, u; c = c, stage = o2, meta = meta)
end

"""
    stage_shift_maps(qp) -> (xmap, ymap)

Warm-start maps of the banded canonical QP: the plan moved one stage earlier,
the last stage repeated (x_N kept, u_{N-1} kept), for rows likewise (dynamics
row block k+1 -> k, bound rows of stage k+1 -> k). Requires time-invariant
row patterns, which `make_ocp` produces.
"""
function stage_shift_maps(p::QP)
    o = p.stage
    N = o.N
    uo, xo, n = stage_offsets(o)
    xmap = zeros(Int, n)
    for k in 0:N-1
        ks = min(k + 1, N - 1)
        for i in 1:o.nu[k+1]; xmap[uo[k+1]+i] = uo[ks+1] + i; end
        kx = min(k + 2, N)
        for i in 1:o.nx[k+2]; xmap[xo[k+2]+i] = xo[kx+1] + i; end
    end
    # rows: dynamics blocks (nx each), then per stage k: nbu, nbx (k >= 1), ng
    nx = o.nx[2]
    m = ncons(p)
    ymap = zeros(Int, m)
    for k in 0:N-1, i in 1:nx
        ymap[k*nx+i] = min(k + 1, N - 1) * nx + i
    end
    starts = Int[]; lens = Int[]; r = N * nx
    for k in 0:N
        len = length(o.idxbu[k+1]) + (k >= 1 ? length(o.idxbx[k+1]) : 0) + length(o.lg[k+1])
        push!(starts, r); push!(lens, len); r += len
    end
    for k in 0:N
        ks = k == 0 ? 0 : min(k + 1, N)
        # stage 0 has no state rows; map stage k's rows to stage k+1's when the patterns agree
        for t in 1:lens[k+1]
            ymap[starts[k+1]+t] = (k >= 1 && lens[ks+1] == lens[k+1]) ? starts[ks+1] + t :
                                  (k == 0 && lens[2] >= lens[1]) ? starts[2] + t : 0
        end
    end
    return xmap, ymap
end

"First input u_0 of a banded canonical solution."
first_input(p::QP, x) = x[1:p.stage.nu[1]]
