# distributed.jl: distributed MPC by consensus ADMM over agents or teams.
#
# The program is the fully condensed pushforward along (alpha box !): one
# vertex u per agent (alpha = singletons) or per team, with its own costs, its
# own input and state constraints, and soft formation springs to its
# neighbours (every dynamics edge is contracted). For a neighbour pair (u, v),
# the interface y_{u->v} = R x_u is the part of x_u that enters the springs
# between u and v (independent rows of their restriction maps, by pivoted QR).
# General-form consensus ADMM (Boyd et al. 2011, Sec. 7.2; Summers and Lygeros
# 2012): u owns y_{u->v}, v holds a copy c_{v,u}, both must equal a global
# z_{u->v}. Every iteration, each u solves
#
#   min  f_u(x_u) + sum_v (1/2) Phi_uv(y_{u->v}(x_u), c_{u,v})
#        + rho/2 sum_v ||R x_u - z_{u->v} + lam_{u->v}||^2 + ||c_{u,v} - z_{v->u} + mu_{u,v}||^2
#   s.t. x_u in Omega_u,
#
# with Phi_uv the springs between u and v (each end carries half). The local
# Hessian is fixed, so each local QP is set up once (the package's solver) and
# only its linear cost changes between iterations and MPC steps. Then each pair
# exchanges y + lam and c + mu (one round), both ends set z to the average, and
# update their scaled duals. Stopping: Boyd's primal and dual residuals.
#
# Receding horizon (`warm = :shift`, the default): every step starts from the
# previous step's plan moved one instant earlier (the last input held, the last
# state propagated by the dynamics, the first state the measured one), restricted
# to the current reduced coordinates (`restrict!`, least squares per fiber), so
# z is the interface value of that plan, and the scaled duals of every
# interface moved one instant too (the rows of instant t take the values of
# instant t + 1, the last instant keeps its own). The first step starts from
# the free response (zero inputs from the measured states). The reduction here
# always condenses fully in time, so every interface row belongs to one formation
# edge at one instant and the shift of the duals is exact bookkeeping; rows
# whose instant t + 1 has a different number of rows (a switching topology)
# keep their values.

struct Interface
    u::Int                            # owner
    v::Int                            # the neighbour holding the copy
    R::Matrix{Float64}                # r x d_u: y_{u->v} = R x_u
    edges::Vector{Int}                # coarse edges between u and v
    X::Vector{Matrix{Float64}}        # F_{u <| e} = X[k] R for edges[k]
    sgn::Vector{Float64}              # +1 when u is the head of edges[k], -1 when the tail
    shift::Vector{Int}                # shifted duals: row j takes the value of row shift[j] (itself when held)
end
idim(I::Interface) = size(I.R, 1)

"Pivoted-QR choice of independent rows of `F`; returns `(R, E, rows)` with `F = E R` and `R = F[rows, :]`."
function _independent_rows(F::Matrix{Float64}; tol = 1e-10)
    size(F, 1) == 0 && return zeros(0, size(F, 2)), zeros(0, 0), Int[]
    q = qr(Matrix(F'), ColumnNorm())
    d = abs.(diag(q.R))
    r = isempty(d) ? 0 : count(>(tol * max(d[1], eps())), d)
    rows = sort(q.p[1:r])
    R = F[rows, :]
    E = F * pinv(R)
    return R, E, rows
end

"""
The shift of an interface's rows by one instant: `inst[j]` is the instant of
row `j`; the rows of instant `t` (in order) take the values of the rows of
`t + 1` when both instants have as many rows, and keep their own otherwise.
"""
function _shift_rows(inst::Vector{Int})
    shift = collect(eachindex(inst))
    byt = Dict{Int,Vector{Int}}()
    for (j, t) in enumerate(inst)
        push!(get!(byt, t, Int[]), j)
    end
    for (t, rows) in byt
        nxt = get(byt, t + 1, nothing)
        (nxt === nothing || length(nxt) != length(rows)) && continue
        shift[rows] .= nxt
    end
    return shift
end

function _interfaces(Pc::SheafProgram)
    bypair = Dict{Tuple{Int,Int},Vector{Int}}()
    for (e, E) in enumerate(Pc.edges)
        edgedim(E) == 0 && continue
        E.hard && throw(ArgumentError("a hard edge joins two vertices: distributed MPC needs soft coupling (condense in time)"))
        push!(get!(bypair, minmax(E.tail, E.head), Int[]), e)
    end
    ifs = Interface[]
    for (a, b) in sort!(collect(keys(bypair)))
        es = bypair[(a, b)]
        for (u, v) in ((a, b), (b, a))
            Fs = [Matrix(Pc.edges[e].tail == u ? Pc.edges[e].Ft : Pc.edges[e].Fh) for e in es]
            R, Emap, rows = _independent_rows(reduce(vcat, Fs))
            X = Matrix{Float64}[]; ro = 0
            inst_of_row = Int[]
            for (k, F) in enumerate(Fs)
                push!(X, Emap[(ro+1):(ro+size(F, 1)), :]); ro += size(F, 1)
                append!(inst_of_row, fill(Pc.edges[es[k]].tag.t, size(F, 1)))
            end
            push!(ifs, Interface(u, v, R, es, X, [Pc.edges[e].head == u ? 1.0 : -1.0 for e in es],
                                 _shift_rows(inst_of_row[rows])))
        end
    end
    return ifs
end

mutable struct LocalQP
    u::Int
    d::Int                            # dim x_u
    own::Vector{Int}                  # interfaces u -> v
    inc::Vector{Int}                  # interfaces v -> u (copies held by u), aligned with own
    cblk::Vector{UnitRange{Int}}      # copy blocks, aligned with own
    Ms::Vector{Tuple{Int,SpMat}}      # (coarse edge, M) with the spring residual M w - b_e
    solver::Solver
    q::Vector{Float64}
end

"""
    DistributedMPC(fleet, teams = 1:n; rho = 1.0, eps_abs = 1e-6, eps_rel = 1e-4, maxit = 3000, budget = 0,
                   warm = :shift, time_limit = Inf, settings...)

Distributed MPC of `fleet` over agents (`teams = 1:n`, the default) or teams:
consensus ADMM on the fully condensed pushforward along `Teams(teams) ⊠
full_condensing()` (see the file header). Every vertex is one agent or one
team; it solves its own QP (its dynamics, constraints and half of each spring)
and exchanges its interface (the positions its neighbours' springs read) with
each neighbour once per iteration. `budget > 0` runs exactly that many
iterations per step instead of iterating to the tolerances. `step!` returns
the inputs with the iterations, the floats exchanged and the timing.

`warm` sets how each step starts: `:shift` (the default) from the previous
plan and scaled duals moved one instant earlier (see the file header),
`:previous` from the previous step's consensus iterates as they are (in the
previous step's coordinates), `:cold` from zero. Other keywords are `Settings`
of the local solvers (defaults `eps_abs = eps_rel = 1e-9`, `max_iter = 20000`).

Every step ends, with its outcome in `info.status`: `:solved` (converged to
the tolerances, or the budget run with every local QP solved), `:max_iter` (the
`maxit` iterations ran out before the tolerances, or a local QP stopped at its
own `max_iter`), `:time_limit` (the step took more than `time_limit` seconds,
checked after every iteration), `:primal_infeasible` or `:dual_infeasible` (a
local QP is, the iteration stops at once) and `:numerical_error` (a residual or
a local solution is not finite; the iterates are reset, so the next step starts
from the free response). `dmpc.local_failures` counts the local solves of the
step that did not end `:solved`.
"""
mutable struct DistributedMPC
    fleet::Fleet
    fp::FleetProgram
    R::ReducedProgram
    ifs::Vector{Interface}
    locals::Vector{LocalQP}
    rho::Float64
    eps_abs::Float64
    eps_rel::Float64
    maxit::Int
    budget::Int
    warm::Symbol
    z::Vector{Vector{Float64}}
    lam::Vector{Vector{Float64}}
    mu::Vector{Vector{Float64}}
    a::Vector{Vector{Float64}}
    c::Vector{Vector{Float64}}
    y::Vector{Float64}                # the assembled reduced plan
    x::Vector{Float64}                # the lifted fine plan
    xs::Vector{Float64}               # the warm start's fine plan (shifted, or the free response)
    y0::Vector{Float64}               # its reduced coordinates
    info::StepInfo
    iterations::Int
    converged::Bool
    floats::Int
    t_parallel::Float64
    t_warm::Float64
    time_limit::Float64
    local_failures::Int
    healthy::Bool                     # false after a numerical failure: the next step restarts the iterates
    steps::Int
end

function DistributedMPC(fl::Fleet, teams = collect(1:nagents(fl)); rho::Real = 1.0, eps_abs::Real = 1e-6,
                        eps_rel::Real = 1e-4, maxit::Integer = 3000, budget::Integer = 0, basis::Symbol = :structured,
                        warm::Symbol = :shift, time_limit::Real = Inf, kwargs...)
    warm in (:shift, :previous, :cold) || throw(ArgumentError("warm must be :shift, :previous or :cold"))
    (isfinite(rho) && rho > 0) || throw(ArgumentError("rho must be positive and finite, got $rho"))
    maxit >= 1 || throw(ArgumentError("maxit must be at least 1"))
    budget >= 0 || throw(ArgumentError("budget must be nonnegative"))
    time_limit > 0 || throw(ArgumentError("time_limit must be positive"))
    fp = FleetProgram(fl)
    R = reduce(fp, Teams(teams) ⊠ full_condensing(); basis = basis)
    Pc = R.program
    ifs = _interfaces(Pc)
    nv = nvertices(Pc)
    own = [Int[] for _ in 1:nv]
    pairid = Dict{Tuple{Int,Int},Int}()
    for (k, I) in enumerate(ifs)
        push!(own[I.u], k); pairid[(I.u, I.v)] = k
    end
    st = Settings()
    for (k, v) in pairs(merge((eps_abs = 1e-9, eps_rel = 1e-9, max_iter = 20_000), kwargs))
        setproperty!(st, k, v)
    end
    locals = LocalQP[]
    for u in 1:nv
        nd = Pc.nodes[u]
        d = length(nd.q)
        inc = [pairid[(ifs[k].v, u)] for k in own[u]]
        cblk = UnitRange{Int}[]; oc = 0
        for k in inc
            push!(cblk, (oc+1):(oc+idim(ifs[k]))); oc += idim(ifs[k])
        end
        nw = d + oc
        PI = Int[]; PJ = Int[]; PV = Float64[]
        _push_block!(PI, PJ, PV, 0, 0, nd.Q, 1.0)
        P = sparse(PI, PJ, PV, nw, nw)
        Ms = Tuple{Int,SpMat}[]
        for (kk, ko) in enumerate(own[u])
            Io, Ii = ifs[ko], ifs[inc[kk]]
            RoS = SpMat(sparse(Io.R))
            for (j, e) in enumerate(Io.edges)
                W = Pc.edges[e].W
                ji = findfirst(==(e), Ii.edges)
                Mx = Io.sgn[j] * (sparse(Io.X[j]) * RoS)
                Mc = spzeros(size(Mx, 1), oc)
                Mc[:, cblk[kk]] = Ii.sgn[ji] * sparse(Ii.X[ji])
                M = SpMat([Mx Mc])
                push!(Ms, (e, M))
                P += 0.5 * (M' * (W * M))
            end
            P += rho * blockdiag(SpMat(RoS' * RoS), spzeros(oc, oc))
            for jj in cblk[kk]
                P[d+jj, d+jj] += rho
            end
        end
        P = SpMat((P + P') / 2)
        A = [nd.A spzeros(size(nd.A, 1), oc)]
        cones = Tuple{Symbol,Int}[]
        for cb in nd.cones
            cb.dim == 0 && continue
            k = cb.kind == ZERO_CONE ? :zero : cb.kind == NONNEG_CONE ? :nonneg : :soc
            k != :soc && !isempty(cones) && cones[end][1] == k ? (cones[end] = (k, cones[end][2] + cb.dim)) : push!(cones, (k, cb.dim))
        end
        qp = ConicQP(P, zeros(nw), A, copy(nd.b), cones)
        push!(locals, LocalQP(u, d, own[u], inc, cblk, Ms, setup(qp; settings = st), zeros(nw)))
    end
    z = [zeros(idim(I)) for I in ifs]
    info = StepInfo([zeros(ag.nu) for ag in fl.agents], :unsolved, NaN, 0, :none, true, NaN, NaN,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    nfine = c0dim(fp.program)
    return DistributedMPC(fl, fp, R, ifs, locals, Float64(rho), Float64(eps_abs), Float64(eps_rel), Int(maxit),
                          Int(budget), warm, z, deepcopy(z), deepcopy(z), deepcopy(z), deepcopy(z), zeros(c0dim(Pc)),
                          zeros(nfine), zeros(nfine), zeros(c0dim(Pc)), info, 0, false, 0, 0.0, 0.0, Float64(time_limit),
                          0, true, 0)
end

function Base.show(io::IO, D::DistributedMPC)
    print(io, "DistributedMPC($(nagents(D.fleet)) agents in $(length(D.locals)) local problems, ",
          "$(length(D.ifs)) interfaces, $(floats_per_iteration(D)) floats per iteration)")
end

"Floats exchanged per iteration: each interface sends `y + lam` one way and `c + mu` the other."
floats_per_iteration(D::DistributedMPC) = sum((2 * idim(I) for I in D.ifs); init = 0)

"`v[j] = v[shift[j]]` for every row, through the buffer `tmp`."
function _shift_values!(v::Vector{Float64}, shift::Vector{Int}, tmp::Vector{Float64})
    copyto!(tmp, v)
    @inbounds for j in eachindex(v)
        v[j] = tmp[shift[j]]
    end
    return v
end

"""
The warm start of a step (after the reduction's data were updated): the
consensus targets from the previous plan shifted one instant (the free response
at the first step) restricted to the current reduced coordinates, and the
scaled duals shifted one instant. Each vertex does its own part of this (its
rows of the plan and of the restriction, its interfaces). The local solvers
keep their own warm starts (their previous solutions).
"""
function _shift_warm!(D::DistributedMPC, x::AbstractVector)
    fp, R = D.fp, D.R
    Pc = R.program
    started = D.steps > 0 && D.healthy
    started ? shift_plan!(D.xs, fp, D.x, x) : free_response!(D.xs, fp, x)
    restrict!(D.y0, R, D.xs)
    for (k, I) in enumerate(D.ifs)
        mul!(D.z[k], I.R, view(D.y0, vrange(Pc, I.u)))
        if started
            _shift_values!(D.lam[k], I.shift, D.a[k])
            _shift_values!(D.mu[k], I.shift, D.a[k])
        else
            fill!(D.lam[k], 0.0); fill!(D.mu[k], 0.0)
        end
    end
    return D
end

"""
    step!(dmpc::DistributedMPC, x, refs; terminal = nothing, targets = nothing, drift = nothing, states = nothing) -> StepInfo

One distributed receding-horizon step: update the data, iterate consensus ADMM
(warm started as `dmpc.warm` says) to the tolerances or the budget, and
return the inputs. `info.iter` is the number of ADMM iterations (communication
rounds), `info.t_solve` the sequential time of all local solves (the parallel
time, the slowest local solve per iteration summed, is `dmpc.t_parallel`),
`info.t_construct` includes the warm start (`dmpc.t_warm` alone), and
`dmpc.converged`, `dmpc.floats` record the outcome and the communication.
New state sets (`states`, as for `MPCController`, or `set_state_set!(dmpc.fp, ...)`)
change the constraint matrices of the local QPs in place: only the agents or
teams that hold a changed vertex recompute their coarse matrix and hand it to
their solver (`update!(solver; A)`, a numerical refactorization).
"""
function step!(D::DistributedMPC, x::AbstractVector, refs::AbstractVector; terminal = nothing, targets = nothing,
               drift = nothing, states = nothing)
    t0 = time_ns()
    fp, R = D.fp, D.R
    Pc = R.program
    set_state!(fp, x)
    set_references!(fp, refs; terminal = terminal)
    targets === nothing || set_targets!(fp, targets)
    drift === nothing || set_drift!(fp, drift)
    states === nothing || set_state_sets!(fp, states)
    if !isempty(fp.changed)
        for u in update_matrices!(R, fp.changed)
            L = D.locals[u]
            Au = Pc.nodes[u].A
            update!(L.solver; A = [Au spzeros(size(Au, 1), length(L.q) - L.d)])
        end
        empty!(fp.changed)
    end
    update!(R)
    for L in D.locals
        update!(L.solver; b = Pc.nodes[L.u].b)
    end
    tw = time_ns()
    if D.warm == :shift
        _shift_warm!(D, x)
    elseif D.warm == :cold || !D.healthy
        for k in eachindex(D.z)
            fill!(D.z[k], 0.0); fill!(D.lam[k], 0.0); fill!(D.mu[k], 0.0)
        end
    end
    if !D.healthy
        for L in D.locals
            reset!(L.solver)
        end
        D.healthy = true
    end
    t1 = time_ns()
    D.t_warm = (t1 - tw) / 1e9
    rho = D.rho
    pdim = floats_per_iteration(D)
    maxit = D.budget > 0 ? D.budget : D.maxit
    it = 0; converged = false; tseq = 0.0; tpar = 0.0
    nfail = 0; lstatus = :solved; stop = :none
    while it < maxit
        it += 1
        tmax = 0.0
        for L in D.locals
            ts = time_ns()
            nd = Pc.nodes[L.u]
            q = L.q
            fill!(q, 0.0)
            @inbounds for j in 1:L.d
                q[j] = nd.q[j]
            end
            for (e, M) in L.Ms                       # half of each spring: -(1/2) M'W b_e
                E = Pc.edges[e]
                mul!(q, transpose(M), E.W * E.b, -0.5, 1.0)
            end
            for (kk, ko) in enumerate(L.own)
                Io = D.ifs[ko]
                ki = L.inc[kk]
                mul!(view(q, 1:L.d), transpose(Io.R), D.z[ko] .- D.lam[ko], -rho, 1.0)
                @inbounds for (jj, j) in enumerate(L.cblk[kk])
                    q[L.d+j] -= rho * (D.z[ki][jj] - D.mu[ki][jj])
                end
            end
            update!(L.solver; q = q)
            si = solve!(L.solver)
            if si.status != :solved
                nfail += 1
                lstatus = si.status
                si.status in (:primal_infeasible, :dual_infeasible) && (stop = si.status)
            end
            w = L.solver.xsol
            # a NaN makes every later local solve run to its max_iter: stop here
            stop == :none && !all(isfinite, w) && (stop = :numerical_error)
            copyto!(view(D.y, vrange(Pc, L.u)), view(w, 1:L.d))
            for (kk, ko) in enumerate(L.own)
                mul!(D.a[ko], D.ifs[ko].R, view(w, 1:L.d))
                copyto!(D.c[L.inc[kk]], view(w, L.d .+ L.cblk[kk]))
            end
            dt = (time_ns() - ts) / 1e9
            tseq += dt; tmax = max(tmax, dt)
            stop == :none || break
        end
        tpar += tmax
        stop == :none || break
        r2 = 0.0; s2 = 0.0; an2 = 0.0; zn2 = 0.0; yn2 = 0.0
        for k in eachindex(D.ifs)
            z, lam, mu, a, c = D.z[k], D.lam[k], D.mu[k], D.a[k], D.c[k]
            @inbounds for j in eachindex(z)
                zn = 0.5 * ((a[j] + lam[j]) + (c[j] + mu[j]))
                s2 += 2 * (zn - z[j])^2
                lam[j] += a[j] - zn
                mu[j] += c[j] - zn
                z[j] = zn
                r2 += (a[j] - zn)^2 + (c[j] - zn)^2
                an2 += a[j]^2 + c[j]^2; zn2 += 2 * zn^2; yn2 += lam[j]^2 + mu[j]^2
            end
        end
        if !(isfinite(r2) && isfinite(s2) && isfinite(an2) && isfinite(yn2))
            stop = :numerical_error                # a NaN would disable the test below
            break
        end
        epri = sqrt(pdim) * D.eps_abs + D.eps_rel * max(sqrt(an2), sqrt(zn2))
        edua = sqrt(pdim) * D.eps_abs + D.eps_rel * rho * sqrt(yn2)
        if D.budget == 0 && sqrt(r2) <= epri && rho * sqrt(s2) <= edua
            converged = true
            break
        end
        if D.time_limit < Inf && (time_ns() - t1) / 1e9 > D.time_limit
            stop = :time_limit
            break
        end
    end
    status = stop != :none ? stop : D.budget == 0 && !converged ? :max_iter : lstatus
    if stop == :numerical_error || !all(isfinite, D.y)
        status = :numerical_error
        D.healthy = false
    end
    t2 = time_ns()
    lift!(D.x, R, D.y)
    P = fp.program
    info = D.info
    @inbounds for (i, ag) in enumerate(D.fleet.agents)
        o = P.offsets[fp.vid[i, 1]] + ag.nx
        for a in 1:ag.nu
            info.u[i][a] = D.x[o+a]
        end
    end
    t3 = time_ns()
    D.iterations = it; D.converged = converged || (D.budget > 0 && stop == :none); D.floats = it * pdim; D.t_parallel = tpar
    D.local_failures = nfail
    info.status = status; info.J = objective(Pc, D.y); info.iter = it; info.polish = :none; info.feasible = R.feasible
    info.gap_upper = NaN; info.gap_residual = NaN
    info.t_construct = (t1 - t0) / 1e9; info.t_setup = 0.0; info.t_solve = tseq; info.t_lift = (t3 - t2) / 1e9
    info.t_certify = 0.0; info.t_total = (t3 - t0) / 1e9
    D.steps += 1
    return info
end

plan(D::DistributedMPC) = D.x
