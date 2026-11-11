# teamcert.jl: the per-team certificate of the paper's Thm. 2 on the condensed QP.
#
# Condensing eliminates the states, x = x0-response + M u, and leaves the QP
# J(u) = 1/2 u'Hu + q'u + c over the input sets (eq. "qp"). For teams S (the
# formation edges inside teams), H_S = H_0 + (the Hessian of the edges of S),
# with H_0 the agents' own condensed tracking and effort Hessians, is block
# diagonal by team, and for any feasible plan u and subgradient g of J at u,
#     J(u) - J* <= cert(g) = 1/2 g' H_S^{-1} g          (Thm. 2(i)).
# The subgradients are grad J(u) + N c, c >= 0, with N the outward normals of
# the input constraints active at u; the multiplier-free certificate minimizes
# cert over c team by team (a small nonnegative least-squares problem each).

"""
    CondensedQP(fleet, x0, refs; terminal = nothing)

The condensed QP of `fleet`'s MPC program from the measured states `x0[i]`
with the references `refs[i]` (as for `step!`): `H` (sparse), `q`, `c` with
`J(u) = u'Hu/2 + q'u + c`, the inputs ordered agent by agent and instant by
instant (`uidx(cq, i, t)`, `t = 0, ..., H-1`), the agents' own Hessian blocks
`H0` (tracking and effort) and the formation Hessian of every edge. Input sets
only: agents with state sets are rejected.
"""
struct CondensedQP
    fleet::Fleet
    off::Vector{Int}                        # input offset of every agent
    H::SparseMatrixCSC{Float64,Int}
    q::Vector{Float64}
    c::Float64
    H0::Vector{Matrix{Float64}}             # own blocks
    edge_terms::Vector{Tuple{Int,Int,Matrix{Float64},Matrix{Float64},Matrix{Float64}}}   # (i, j, Hii, Hij, Hjj) per edge
end

uidx(cq::CondensedQP, i::Integer, t::Integer) = (nu = cq.fleet.agents[i].nu; cq.off[i] .+ (t * nu .+ (1:nu)))

"""Free response and input-to-state map of one agent: `X[:, t]` = `f[t] + M[t] u` for `t = 1..H`."""
function _condense_agent(ag::Agent, x0::AbstractVector, H::Int)
    nx, nu = ag.nx, ag.nu
    Ms = [zeros(nx, nu * H) for _ in 1:H]
    fs = [zeros(nx) for _ in 1:H]
    xprev = Vector{Float64}(x0); Mprev = zeros(nx, nu * H)
    for t in 0:(H-1)
        A, B, g = dynamics(ag, t)
        f = A * xprev + g
        M = A * Mprev
        M[:, t*nu .+ (1:nu)] .+= B
        fs[t+1] = f; Ms[t+1] = M
        xprev = f; Mprev = M
    end
    return fs, Ms
end

function CondensedQP(fl::Fleet, x0::AbstractVector, refs::AbstractVector; terminal = nothing)
    n = nagents(fl); H = fl.H
    all(ag -> all(s -> s === nothing, ag.state), fl.agents) ||
        throw(ArgumentError("the condensed certificate supports input sets only"))
    off = zeros(Int, n + 1)
    for (i, ag) in enumerate(fl.agents)
        off[i+1] = off[i] + ag.nu * H
    end
    N = off[n+1]
    resp = [_condense_agent(ag, x0[i], H) for (i, ag) in enumerate(fl.agents)]
    blocks = Dict{Tuple{Int,Int},Matrix{Float64}}()
    q = zeros(N); c = 0.0
    H0 = Vector{Matrix{Float64}}(undef, n)
    for (i, ag) in enumerate(fl.agents)
        fs, Ms = resp[i]; R = refs[i]; nu = ag.nu
        Hi = zeros(nu * H, nu * H); qi = zeros(nu * H)
        # t = 0: the tracking term of x0 is a constant
        r0 = view(R, :, 1); e0 = ag.Cr * x0[i] - r0
        c += 0.5 * dot(e0, ag.Q * e0)
        for t in 0:(H-1)
            Hi[t*nu .+ (1:nu), t*nu .+ (1:nu)] .+= ag.R
        end
        for t in 1:(H-1)
            a = ag.Cr * Ms[t]; b = ag.Cr * fs[t] - view(R, :, t + 1)
            Hi .+= a' * ag.Q * a; qi .+= a' * (ag.Q * b); c += 0.5 * dot(b, ag.Q * b)
        end
        rf = terminal === nothing ? view(R, :, H + 1) : terminal[i]
        a = ag.Cf * Ms[H]; b = ag.Cf * fs[H] - rf
        Hi .+= a' * ag.Qf * a; qi .+= a' * (ag.Qf * b); c += 0.5 * dot(b, ag.Qf * b)
        H0[i] = Hi
        blocks[(i, i)] = copy(Hi)
        q[off[i]+1:off[i+1]] .= qi
    end
    terms = Tuple{Int,Int,Matrix{Float64},Matrix{Float64},Matrix{Float64}}[]
    for (k, (i, j)) in enumerate(fl.edges)
        S = fl.select[k]; fi, Mi = resp[i]; fj, Mj = resp[j]
        Ci = S * fl.agents[i].C; Cj = S * fl.agents[j].C
        Hii = zeros(off[i+1] - off[i], off[i+1] - off[i]); Hjj = zeros(off[j+1] - off[j], off[j+1] - off[j])
        Hij = zeros(off[i+1] - off[i], off[j+1] - off[j])
        for t in 1:H
            (fl.present[k, t] && fl.weights[k, t] > 0) || continue
            w = fl.weights[k, t]
            ai = -Ci * Mi[t]; aj = Cj * Mj[t]
            b = Cj * fj[t] - Ci * fi[t] - S * fl.targets[:, k, t]
            Hii .+= w .* (ai' * ai); Hjj .+= w .* (aj' * aj); Hij .+= w .* (ai' * aj)
            q[off[i]+1:off[i+1]] .+= w .* (ai' * b); q[off[j]+1:off[j+1]] .+= w .* (aj' * b)
            c += 0.5 * w * dot(b, b)
        end
        push!(terms, (i, j, Hii, Hij, Hjj))
        blocks[(i, i)] .+= Hii; blocks[(j, j)] .+= Hjj
        B = get!(() -> zeros(size(Hij)), blocks, (i, j)); B .+= Hij
        Bt = get!(() -> zeros(size(Hij, 2), size(Hij, 1)), blocks, (j, i)); Bt .+= Hij'
    end
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for ((i, j), B) in blocks, b in axes(B, 2), a in axes(B, 1)
        B[a, b] == 0 && continue
        push!(I_, off[i] + a); push!(J_, off[j] + b); push!(V_, B[a, b])
    end
    Hs = sparse(I_, J_, V_, N, N)
    return CondensedQP(fl, off[1:n], Hs, q, c, H0, terms)
end

objective(cq::CondensedQP, u::AbstractVector) = 0.5 * dot(u, cq.H * u) + dot(cq.q, u) + cq.c

"""Stack per-agent input plans (`nu x H` matrices) into the condensed QP's input vector."""
function stack_inputs(cq::CondensedQP, U::AbstractVector)
    u = zeros(length(cq.q))
    for (i, ag) in enumerate(cq.fleet.agents), t in 0:(cq.fleet.H-1)
        u[uidx(cq, i, t)] .= view(U[i], :, t + 1)
    end
    return u
end

"""Lawson-Hanson nonnegative least squares: `argmin_{c >= 0} ||Y c + y||`."""
function _nnls(Y::AbstractMatrix, y::AbstractVector; tol::Real = 1e-12, maxit::Integer = 500)
    m = size(Y, 2)
    c = zeros(m); P = falses(m)
    for _ in 1:maxit
        w = -(Y' * (Y * c + y))
        j = 0; best = tol
        for k in 1:m
            !P[k] && w[k] > best && (best = w[k]; j = k)
        end
        j == 0 && break
        P[j] = true
        while true
            idx = findall(P)
            z = zeros(m)
            z[idx] = -(Y[:, idx] \ y)
            if all(z[idx] .> 0)
                c = z; break
            end
            alpha = minimum((c[k] / (c[k] - z[k]) for k in idx if z[k] <= 0); init = 1.0)
            c .+= alpha .* (z .- c)
            for k in idx
                c[k] <= tol && (P[k] = false; c[k] = 0.0)
            end
        end
    end
    return c
end

"""Outward normals (columns, team-local) of the input constraints of agent `i` active at `u` (relative tolerance `tol`)."""
function _active_normals!(out, cq::CondensedQP, i::Int, u::AbstractVector, loc::Int, tol::Real)
    ag = cq.fleet.agents[i]; U = ag.input; nu = ag.nu
    U === nothing && return out
    for t in 0:(cq.fleet.H-1)
        ui = u[uidx(cq, i, t)]; cols = loc + t * nu .+ (1:nu)
        if U isa BallSet
            nz = norm(ui)
            nz >= (1 - tol) * U.radius && nz > 0 && push!(out, (collect(cols), ui ./ nz))
        elseif U isa BoxSet
            for a in 1:nu
                span = max(U.hi[a] - U.lo[a], 1.0)
                ui[a] >= U.hi[a] - tol * span && push!(out, ([cols[a]], [1.0]))
                ui[a] <= U.lo[a] + tol * span && push!(out, ([cols[a]], [-1.0]))
            end
        elseif U isa Polyhedron
            r = U.G * ui .- U.h
            for k in axes(U.G, 1)
                r[k] >= -tol * (1 + abs(U.h[k])) && push!(out, (collect(cols), U.G[k, :]))
            end
        end
    end
    return out
end

"""
    team_certificate(cq, teams, u; tol = 1e-6) -> (cert, per_team, cert_no_normals)

The multiplier-free certificate of Thm. 2 at the feasible plan `u` (a
condensed input vector, e.g. a lifted team plan) for the teams `teams` (one
label per agent): with `H_S` the agents' own Hessians plus the formation
Hessian of the edges inside teams (block diagonal by team) and `g = grad J(u)
+ N c` over the outward normals `N` of the active input constraints, the sum
over teams of `min_{c >= 0} g' H_S^{-1} g / 2`. Bounds `J(u) - J*` from above.
"""
function team_certificate(cq::CondensedQP, teams::AbstractVector, u::AbstractVector; tol::Real = 1e-6)
    fl = cq.fleet; lab = canonical_partition(teams)
    k = maximum(lab; init = 0)
    mem = [Int[] for _ in 1:k]
    for (i, c) in enumerate(lab)
        push!(mem[c], i)
    end
    g0 = cq.H * u .+ cq.q
    total = 0.0; total0 = 0.0; per = zeros(k)
    for c in 1:k
        m = mem[c]
        loc = zeros(Int, length(m) + 1)
        for (a, i) in enumerate(m)
            loc[a+1] = loc[a] + (cq.off[i] + fl.agents[i].nu * fl.H - cq.off[i])
        end
        nS = loc[end]
        HS = zeros(nS, nS)
        pos = Dict(i => a for (a, i) in enumerate(m))
        for (a, i) in enumerate(m)
            HS[loc[a]+1:loc[a+1], loc[a]+1:loc[a+1]] .+= cq.H0[i]
        end
        for (i, j, Hii, Hij, Hjj) in cq.edge_terms
            (haskey(pos, i) && haskey(pos, j)) || continue
            a, b = pos[i], pos[j]
            ri = loc[a]+1:loc[a+1]; rj = loc[b]+1:loc[b+1]
            HS[ri, ri] .+= Hii; HS[rj, rj] .+= Hjj; HS[ri, rj] .+= Hij; HS[rj, ri] .+= Hij'
        end
        L = cholesky(Symmetric(HS)).L
        g = zeros(nS)
        for (a, i) in enumerate(m)
            g[loc[a]+1:loc[a+1]] .= g0[cq.off[i]+1:cq.off[i]+fl.agents[i].nu*fl.H]
        end
        y0 = L \ g
        val0 = 0.5 * dot(y0, y0); val = val0
        normals = Tuple{Vector{Int},Vector{Float64}}[]
        for (a, i) in enumerate(m)
            _active_normals!(normals, cq, i, u, loc[a], tol)
        end
        if !isempty(normals)
            Nm = zeros(nS, length(normals))
            for (kk, (cols, d)) in enumerate(normals)
                Nm[cols, kk] .= d
            end
            Y = L \ Nm
            cc = _nnls(Y, y0)
            yc = y0 + Y * cc
            val = min(val, 0.5 * dot(yc, yc))
        end
        per[c] = val; total += val; total0 += val0
    end
    return total, per, total0
end

"""
    team_kappa(cq, teams; iters = 100) -> kappa

`lambda_max(H_S^{-1} H)` (Remark 2's ratio of the certificate to the gap when
the active limits of both plans agree), by power iteration.
"""
function team_kappa(cq::CondensedQP, teams::AbstractVector; iters::Integer = 100)
    fl = cq.fleet; lab = canonical_partition(teams)
    k = maximum(lab; init = 0); N = length(cq.q)
    facs = []
    for c in 1:k
        m = findall(==(c), lab)
        idx = reduce(vcat, [collect(cq.off[i]+1:cq.off[i]+fl.agents[i].nu*fl.H) for i in m])
        HS = zeros(length(idx), length(idx))     # the members' own blocks and the edges inside the team
        pos = Dict(i => a for (a, i) in enumerate(m))
        loc = cumsum([0; [fl.agents[i].nu * fl.H for i in m]])
        for (a, i) in enumerate(m)
            HS[loc[a]+1:loc[a+1], loc[a]+1:loc[a+1]] .+= cq.H0[i]
        end
        for (i, j, Hii, Hij, Hjj) in cq.edge_terms
            (haskey(pos, i) && haskey(pos, j)) || continue
            a, b = pos[i], pos[j]
            ri = loc[a]+1:loc[a+1]; rj = loc[b]+1:loc[b+1]
            HS[ri, ri] .+= Hii; HS[rj, rj] .+= Hjj; HS[ri, rj] .+= Hij; HS[rj, ri] .+= Hij'
        end
        push!(facs, (idx, cholesky(Symmetric(HS)).L))
    end
    Linv(y) = (z = zeros(N); for (idx, L) in facs; z[idx] .= L \ y[idx]; end; z)
    Linvt(y) = (z = zeros(N); for (idx, L) in facs; z[idx] .= L' \ y[idx]; end; z)
    x = randn(Xoshiro(5), N); x ./= norm(x); lam = 0.0
    for _ in 1:iters
        y = Linv(cq.H * Linvt(x))
        lam = dot(x, y); x = y / norm(y)
    end
    return lam
end

"""
    team_plan(ctrl::TeamController) -> U

The lifted open-loop plan of the last step of a `TeamController`: every member gets
its team's input sequence (`nu x H` per agent).
"""
function team_plan(C::TeamController)
    _, Uq = trajectories(C.inner.fp, plan(C.inner))
    return [copy(Uq[C.quotient.team[i]]) for i in 1:nagents(C.fleet)]
end

"""
    certificate(ctrl::TeamController, x, refs; terminal = nothing, tol = 1e-6) -> (cert, J_team, cq)

Thm. 2 for the last step of `ctrl` taken from the measured states `x`: the
certificate of the lifted team plan from the projected states on the fleet's
condensed QP (`CondensedQP` from `project(ctrl, x)`), its objective, and the
QP (for the coordinated optimum, solve it or use `MPCController`).
"""
function certificate(C::TeamController, x::AbstractVector, refs::AbstractVector; terminal = nothing, tol::Real = 1e-6)
    xt = project(C, x)
    cq = CondensedQP(C.fleet, xt, refs; terminal = terminal)
    u = stack_inputs(cq, team_plan(C))
    cert, _, _ = team_certificate(cq, C.quotient.team, u; tol = tol)
    return cert, objective(cq, u), cq
end
