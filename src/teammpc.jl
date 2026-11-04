# teammpc.jl: team MPC (the paper's Algorithm 1) on the quotient program.
#
# A partition of the agents into teams whose members share their data
# (coherent teams: the same model, costs and input set, references shifted by
# each member's offset Delta_i, A Delta_i = Delta_i) is planned as one agent
# per team. The quotient program (the paper's Prop. "quotient") has one agent
# per team, a copy of its members' agent with every cost weight times the
# team size, and between two adjacent teams one formation edge per compared
# coordinate set, whose weight is the total weight of the edges between them
# and whose target is their weighted mean target relative to the offsets.
# Edges inside a team are dropped: the team plan keeps them at their targets
# (coherence) or pays a constant.
#
# A step projects the measured states onto the formation (the team means of
# x_i - Delta_i, eq. "project"), solves the quotient program warm, broadcasts
# each team's first input to its members and adds the local feedback
# v_i = u_c - K_c (x_i - x~_i), with x~_i = mu_c + Delta_i the projected state
# (eq. "control"). For almost equitable teams and coherent data started in
# formation the applied inputs are those of coordinated MPC (Thm. 1).

"""The offsets `Delta_i = C_i^+ s_i` of formation slots `s_i` (positions in the formation output), checked to be equilibria of `A`."""
function slot_offsets(fl::Fleet, slots::AbstractVector)
    length(slots) == nagents(fl) || throw(DimensionMismatch("need one slot per agent"))
    D = Vector{Vector{Float64}}(undef, nagents(fl))
    for (i, ag) in enumerate(fl.agents)
        D[i] = pinv(ag.C) * Vector{Float64}(slots[i])
    end
    return D
end

_same(a, b) = a == b
_same(a::BallSet, b::BallSet) = a.radius == b.radius
_same(a::BoxSet, b::BoxSet) = a.lo == b.lo && a.hi == b.hi
_same(a::Polyhedron, b::Polyhedron) = a.G == b.G && a.h == b.h
_same(::Nothing, ::Nothing) = true

"""Whether two agents share their data (dynamics, outputs, costs, input and state sets, kind)."""
function same_data(a::Agent, b::Agent)
    a.nx == b.nx && a.nu == b.nu && a.A == b.A && a.B == b.B && a.g == b.g && a.C == b.C && a.Cr == b.Cr &&
        a.Q == b.Q && a.R == b.R && a.Cf == b.Cf && a.Qf == b.Qf && _same(a.input, b.input) && a.kind == b.kind &&
        length(a.state) == length(b.state) && all(_same(x, y) for (x, y) in zip(a.state, b.state))
end

_scaled(ag::Agent, m::Real) = Agent(ag.nx, ag.nu, ag.A, ag.B, ag.g, ag.C, ag.Cr, m * ag.Q, m * ag.R, ag.Cf, m * ag.Qf,
                                    ag.input, ag.state, ag.kind)

"""
    QuotientFleet

The quotient of a fleet by coherent teams: `fleet` (one agent per team),
`teams` (the members of every team), `team[i]` (the team of agent `i`),
`offsets` (`Delta_i`), `merged` (the number of fine edges between teams) and
`residual` (the largest spread of the slot-relative targets merged into one
quotient edge, and of the slot-relative targets of the edges inside a team:
zero when the data are coherent).
"""
struct QuotientFleet
    fleet::Fleet
    teams::Vector{Vector{Int}}
    team::Vector{Int}
    offsets::Vector{Vector{Float64}}
    merged::Int
    residual::Float64
end

"""
    QuotientFleet(fleet, teams; offsets = nothing, check = true)

Build the quotient program of `fleet` by the partition `teams` (a label per
agent). `offsets[i]` is agent `i`'s offset state `Delta_i` (zeros by default;
see `slot_offsets`). With `check`, every team must share its agent data and
every offset must be an equilibrium of its dynamics (`A Delta = Delta`, `g`
aside).
"""
function QuotientFleet(fl::Fleet, teams::AbstractVector; offsets = nothing, check::Bool = true)
    n = nagents(fl)
    length(teams) == n || throw(DimensionMismatch("need one team label per agent"))
    team = canonical_partition(teams)
    nt = maximum(team; init = 0)
    members = [Int[] for _ in 1:nt]
    for i in 1:n
        push!(members[team[i]], i)
    end
    D = offsets === nothing ? [zeros(ag.nx) for ag in fl.agents] : [Vector{Float64}(d) for d in offsets]
    length(D) == n || throw(DimensionMismatch("need one offset per agent"))
    if check
        for m in members, i in m
            same_data(fl.agents[i], fl.agents[m[1]]) ||
                throw(ArgumentError("agents $(m[1]) and $i are in one team but do not share their data"))
        end
        for (i, ag) in enumerate(fl.agents)
            length(D[i]) == ag.nx || throw(DimensionMismatch("offset $i needs $(ag.nx) entries"))
            for A in ag.A
                norm(A * D[i] - D[i]) <= 1e-9 * (1 + norm(D[i])) ||
                    throw(ArgumentError("the offset of agent $i is not an equilibrium (A Delta != Delta)"))
            end
        end
    end
    H = fl.H
    p = size(fl.agents[1].C, 1)
    # one quotient edge per (team pair, compared coordinates)
    keyof = Dict{Tuple{Int,Int,Matrix{Float64}},Int}()
    pairs = Tuple{Int,Int}[]; sel = Matrix{Float64}[]
    W = Vector{Vector{Float64}}(); Wb = Vector{Matrix{Float64}}()
    lo = Vector{Matrix{Float64}}(); hi = Vector{Matrix{Float64}}()
    merged = 0
    inside = 0.0
    for (k, (i, j)) in enumerate(fl.edges)
        a, b = team[i], team[j]
        S = fl.select[k]
        rel = fl.agents[j].C * D[j] - fl.agents[i].C * D[i]
        if a == b
            for t in 1:H
                (fl.present[k, t] && fl.weights[k, t] > 0) || continue
                inside = max(inside, norm(S * (fl.targets[:, k, t] - rel)))
            end
            continue
        end
        merged += 1
        s = 1.0
        if a > b
            a, b = b, a; s = -1.0
        end
        e = get!(keyof, (a, b, S)) do
            push!(pairs, (a, b)); push!(sel, S); push!(W, zeros(H)); push!(Wb, zeros(p, H))
            push!(lo, fill(Inf, p, H)); push!(hi, fill(-Inf, p, H))
            length(pairs)
        end
        for t in 1:H
            (fl.present[k, t] && fl.weights[k, t] > 0) || continue
            w = fl.weights[k, t]
            o = s .* (fl.targets[:, k, t] .- rel)
            W[e][t] += w
            Wb[e][:, t] .+= w .* o
            lo[e][:, t] .= min.(lo[e][:, t], S' * (S * o)); hi[e][:, t] .= max.(hi[e][:, t], S' * (S * o))
        end
    end
    ne = length(pairs)
    Wm = zeros(ne, H); T = zeros(p, ne, H); pres = falses(ne, H)
    spread = inside
    for e in 1:ne, t in 1:H
        W[e][t] > 0 || continue
        Wm[e, t] = W[e][t]; pres[e, t] = true
        T[:, e, t] .= Wb[e][:, t] ./ W[e][t]
        spread = max(spread, maximum(hi[e][:, t] .- lo[e][:, t]))
    end
    agents = [_scaled(fl.agents[first(m)], length(m)) for m in members]
    fq = Fleet(agents, pairs; H = H, targets = T, weights = Wm, present = pres, select = sel)
    return QuotientFleet(fq, members, team, D, merged, spread)
end

"""
    lqr_gain(A, B, Q, R; iters = 10_000, tol = 1e-12) -> K

The discrete LQR gain `K = (R + B'PB) \\ B'PA` of the Riccati fixed point `P`
(value iteration from `P = Q`).
"""
function lqr_gain(A::AbstractMatrix, B::AbstractMatrix, Q::AbstractMatrix, R::AbstractMatrix; iters::Integer = 10_000,
                  tol::Real = 1e-12)
    P = Matrix{Float64}(Q)
    K = zeros(size(B, 2), size(A, 1))
    for _ in 1:iters
        K = (R + B' * P * B) \ (B' * P * A)
        Pn = Q + A' * P * (A - B * K)
        Pn = (Pn + Pn') / 2
        if norm(Pn - P) <= tol * (1 + norm(P))
            P = Pn
            break
        end
        P = Pn
    end
    return (R + B' * P * B) \ (B' * P * A)
end

"""
    TeamMPC(fleet, teams; offsets = nothing, gains = :lqr, resolution = full_condensing(), check = true, settings...)

Team MPC (the paper's Algorithm 1): the quotient program of `fleet` by the
coherent `teams` (one label per agent; see `lossless_teams` and
`quasi_stable_teams`), solved by a warm-started `MPCController` along
`resolution` (fully condensed by default), with the projection onto the
formation, the broadcast of each team's input and the local feedback
`v_i = u_c - K_c (x_i - x~_i)`. `offsets[i]` is the offset state `Delta_i`
(see `slot_offsets`). `gains` is `:lqr` (the LQR gain of the team's agent
with state weight `Cr'Q Cr + 1e-6 I` and input weight `R`), `nothing` (no
feedback) or one gain matrix per team. Other keywords go to the solver.
"""
mutable struct TeamMPC
    fleet::Fleet
    quotient::QuotientFleet
    inner::MPCController
    gains::Vector{Matrix{Float64}}
    # preallocated step data
    xq::Vector{Vector{Float64}}
    rq::Vector{Matrix{Float64}}
    tq::Vector{Vector{Float64}}
    u::Vector{Vector{Float64}}
    dev::Vector{Vector{Float64}}
    CrD::Vector{Vector{Float64}}          # Cr Delta_i and Cf Delta_i, precomputed
    CfD::Vector{Vector{Float64}}
    t_team::Float64
end

function TeamMPC(fl::Fleet, teams::AbstractVector; offsets = nothing, gains = :lqr, resolution = full_condensing(),
                 check::Bool = true, certify::Bool = false, kwargs...)
    Q = QuotientFleet(fl, teams; offsets = offsets, check = check)
    inner = MPCController(Q.fleet, resolution; certify = certify, kwargs...)
    nt = length(Q.teams)
    K = Vector{Matrix{Float64}}(undef, nt)
    for (c, m) in enumerate(Q.teams)
        ag = fl.agents[m[1]]
        if gains === nothing
            K[c] = zeros(ag.nu, ag.nx)
        elseif gains === :lqr
            A, B, _ = dynamics(ag, 0)
            K[c] = lqr_gain(A, B, ag.Cr' * ag.Q * ag.Cr + 1e-6 * I, ag.R)
        else
            K[c] = Matrix{Float64}(gains[c])
            size(K[c]) == (ag.nu, ag.nx) || throw(DimensionMismatch("gain $c must be $(ag.nu) x $(ag.nx)"))
        end
    end
    xq = [zeros(fl.agents[m[1]].nx) for m in Q.teams]
    rq = [zeros(size(fl.agents[m[1]].Cr, 1), fl.H + 1) for m in Q.teams]
    tq = [zeros(size(fl.agents[m[1]].Cf, 1)) for m in Q.teams]
    u = [zeros(ag.nu) for ag in fl.agents]
    dev = [zeros(ag.nx) for ag in fl.agents]
    CrD = [ag.Cr * Q.offsets[i] for (i, ag) in enumerate(fl.agents)]
    CfD = [ag.Cf * Q.offsets[i] for (i, ag) in enumerate(fl.agents)]
    return TeamMPC(fl, Q, inner, K, xq, rq, tq, u, dev, CrD, CfD, 0.0)
end

function Base.show(io::IO, C::TeamMPC)
    print(io, "TeamMPC($(nagents(C.fleet)) agents in $(length(C.quotient.teams)) teams, H = $(C.fleet.H), ",
          "$(length(C.quotient.fleet.edges)) quotient edges)")
end

"""The teams of a `TeamMPC` (one vector of members per team)."""
teams(C::TeamMPC) = C.quotient.teams

"""
    project(ctrl, x) -> xtilde

The projection of the measured states onto the formation: every member of
team `c` gets `mu_c + Delta_i`, with `mu_c` the team mean of `x_i - Delta_i`.
"""
function project(C::TeamMPC, x::AbstractVector)
    _team_means!(C, x)
    Q = C.quotient
    return [C.xq[Q.team[i]] .+ Q.offsets[i] for i in eachindex(x)]
end

function _team_means!(C::TeamMPC, x::AbstractVector)
    Q = C.quotient
    @inbounds for (c, m) in enumerate(Q.teams)
        xc = C.xq[c]; fill!(xc, 0.0); w = 1.0 / length(m)
        for i in m
            xi = x[i]; D = Q.offsets[i]
            for a in eachindex(xc)
                xc[a] += w * (xi[a] - D[a])
            end
        end
    end
    return C.xq
end

"""
    step!(ctrl::TeamMPC, x, refs; terminal = nothing) -> inputs

One step of Algorithm 1 from the measured states `x[i]` with the references
`refs[i]` (`ny x (H+1)` matrices, as for `MPCController`) and optional
terminal references: project onto the formation, solve the quotient program
from the team means (the team references are the member means of
`refs[i] - Cr Delta_i`), broadcast, and add the local feedback. Returns the
inputs to apply, one vector per agent (overwritten by the next step); the
solver's diagnostics are `ctrl.inner.info`, the projection, broadcast and
feedback time `ctrl.t_team`.
"""
function step!(C::TeamMPC, x::AbstractVector, refs::AbstractVector; terminal = nothing)
    fl = C.fleet; Q = C.quotient
    length(x) == nagents(fl) && length(refs) == nagents(fl) || throw(DimensionMismatch("need one state and one reference per agent"))
    t0 = time_ns()
    _team_means!(C, x)
    @inbounds for (c, m) in enumerate(Q.teams)
        w = 1.0 / length(m)
        Rc = C.rq[c]; fill!(Rc, 0.0)
        for i in m
            Ri = refs[i]; CD = C.CrD[i]
            size(Ri, 2) >= fl.H || throw(DimensionMismatch("agent $i: references need $(fl.H + 1) columns"))
            for t in 1:min(size(Ri, 2), fl.H + 1), a in axes(Rc, 1)
                Rc[a, t] += w * (Ri[a, t] - CD[a])
            end
        end
        if terminal !== nothing
            tc = C.tq[c]; fill!(tc, 0.0)
            for i in m
                Ti = terminal[i]; CfD = C.CfD[i]
                for a in eachindex(tc)
                    tc[a] += w * (Ti[a] - CfD[a])
                end
            end
        end
    end
    t1 = time_ns()
    info = step!(C.inner, C.xq, C.rq; terminal = terminal === nothing ? nothing : C.tq)
    t2 = time_ns()
    @inbounds for (i, ag) in enumerate(fl.agents)
        c = Q.team[i]
        uc = info.u[c]; K = C.gains[c]; d = C.dev[i]; ui = C.u[i]
        xi = x[i]; D = Q.offsets[i]; mu = C.xq[c]
        for a in eachindex(d)
            d[a] = xi[a] - mu[a] - D[a]
        end
        copyto!(ui, uc)
        mul!(ui, K, d, -1.0, 1.0)
    end
    C.t_team = ((t1 - t0) + (time_ns() - t2)) / 1e9
    return C.u
end

"""The solver diagnostics of the last step of a `TeamMPC` (the inner controller's `StepInfo`)."""
stepinfo(C::TeamMPC) = C.inner.info
