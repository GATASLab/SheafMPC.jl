# controller.jl: receding-horizon control on a reduced program.
#
# The structure of the time-expanded program (its graph, restriction maps,
# costs' Hessians, constraint matrices) does not change between sampling
# instants of an LTI fleet, and neither do the fibers of a resolution, the
# reduced program's Hessian and constraint matrix, or the solver's KKT
# factorization. Only vectors change: the measured states, the references, the
# formation targets and the drifts. A step therefore writes them into the fine
# program, pushes them through the reduction (`update!`, a few sparse
# products), refreshes the reduced QP's linear cost and right-hand side, and
# solves warm, with every factorization kept.
#
# State constraints may also change in place (re-linearized keep-out
# half-spaces, `set_state_set!` or `step!(...; states)`): new values of a node
# matrix on its fixed sparsity pattern. The step then recomputes the coarse
# matrices of the blocks that hold the changed vertices, copies them into the
# reduced QP's constraint matrix, and hands its values to the solver
# (`update!(solver; A)`: the scaling and the symbolic factorization are kept,
# the KKT matrix is refactored numerically).

"""
    StepInfo

What `step!` returns (one object, overwritten by the next step):

* `u[i]`: the input to apply to agent `i` (the first input of its lifted plan);
* `status`, `J` (the objective of the lifted plan, which equals the reduced
  objective), `iter` (ADMM iterations), `polish`;
* `feasible`: false when an affine fiber is empty (a team that cannot reach
  exact formation), then the reduced program is infeasible;
* `gap_upper`: bound (a) of the paper's Thm. 2 on the optimality gap of the
  reduction, from this solve alone (`NaN` when not certified), and
  `gap_residual`, the stationarity residual of the recovered forces;
* the timing breakdown in seconds: `t_construct` (fine data, pushforward update,
  reduced QP vectors), `t_setup` (scaling and factorization on the first step,
  the data update into the solver afterwards), `t_solve`, `t_lift` (lift to
  the fine plan and read the inputs), `t_certify`, and `t_total`.
"""
mutable struct StepInfo
    u::Vector{Vector{Float64}}
    status::Symbol
    J::Float64
    iter::Int
    polish::Symbol
    feasible::Bool
    gap_upper::Float64
    gap_residual::Float64
    t_construct::Float64
    t_setup::Float64
    t_solve::Float64
    t_lift::Float64
    t_certify::Float64
    t_total::Float64
end

"""
    MPCController(fleet, resolution = Fine(); certify = true, dedup = true, basis = :structured, settings...)

A receding-horizon controller for `fleet` that solves, at every step, the
pushforward of the fleet's MPC program along `resolution` (a `Resolution`, or
a vector of them for teams of teams, applied in order) and applies the first
inputs of the lifted plan, which every agent can execute (Cor. 1). The fibers,
the reduced QP's structure and the solver's factorizations are built once;
`step!` updates vectors only and solves warm. With `certify`, every step also
reports bound (a) on the gap of the reduction. `warm = :shift` (the default)
starts each solve from the previous plan moved one instant earlier (for
resolutions without time blocking; otherwise, and with `warm = :previous`,
from the previous plan itself), `warm = :cold` from zero. Other keywords are solver
`Settings` (defaults `eps_abs = eps_rel = 1e-6`, `max_iter = 20000`).
"""
mutable struct MPCController
    fleet::Fleet
    fp::FleetProgram
    resolutions::Vector{Resolution}
    chain::Vector{ReducedProgram}
    qmap::QPMap
    dedup::Bool
    solver::Union{Nothing,Solver}
    settings::Settings
    cert::Union{Nothing,Certifier}
    yfull::Vector{Float64}
    hard_duals::Vector{Float64}
    node_duals::Vector{Float64}
    levels::Vector{Vector{Float64}}        # lifted plan at every level, finest first
    info::StepInfo
    steps::Int
    warm::Symbol
    xmap::Vector{Int}                      # shifted warm start: variable maps (empty when unavailable)
    ymap::Vector{Int}
end

function MPCController(fl::Fleet, resolution = Fine(); certify::Bool = true, dedup::Bool = true,
                       basis::Symbol = :structured, absent::Symbol = :omit, warm::Symbol = :shift,
                       settings::Settings = Settings(), kwargs...)
    warm in (:shift, :previous, :cold) || throw(ArgumentError("warm must be :shift, :previous or :cold"))
    fp = FleetProgram(fl; absent = absent)
    ress = resolution isa Resolution ? Resolution[resolution] : Vector{Resolution}(collect(resolution))
    chain = ReducedProgram[]
    prog = fp
    for res in ress
        res isa Fine && continue
        R = reduce(prog, res; basis = basis)
        push!(chain, R)
        prog = R
    end
    Pq = isempty(chain) ? fp.program : chain[end].program
    qmap = QPMap(Pq; dedup = dedup)
    st = deepcopy(settings)
    for (k, v) in pairs(merge((eps_abs = 1e-6, eps_rel = 1e-6, max_iter = 20_000), kwargs))
        setproperty!(st, k, v)
    end
    cert = nothing
    if certify && !isempty(chain)
        R = chain[end]
        P0 = fp.program
        _, coll, _, _ = composite_partition(R)
        any(e -> !P0.edges[e].hard && edgedim(P0.edges[e]) > 0, coll) && (cert = Certifier(R))
    end
    levels = Vector{Float64}[zeros(c0dim(fp.program))]
    for R in chain
        push!(levels, zeros(c0dim(R.program)))
    end
    m = length(qmap.group)
    info = StepInfo([zeros(ag.nu) for ag in fl.agents], :unsolved, NaN, 0, :none, true, NaN, NaN,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    C = MPCController(fl, fp, ress, chain, qmap, dedup, nothing, st, cert, zeros(m), zeros(c1dim(Pq)),
                      zeros(noderows(Pq)), levels, info, 0, warm, Int[], Int[])
    warm == :shift && _shift_maps!(C)
    return C
end

function Base.show(io::IO, C::MPCController)
    Pq = isempty(C.chain) ? C.fp.program : C.chain[end].program
    print(io, "MPCController($(nagents(C.fleet)) agents, H = $(C.fleet.H), ",
          join([string(nameof(typeof(r))) for r in C.resolutions], " then "),
          ", reduced QP: $(c0dim(Pq)) variables, $(nrows(C.qmap.qp)) rows, $(C.steps) steps)")
end

"""
The index maps of the shifted warm start: every coordinate of the reduced
program at (team, t) takes the previous solution's value at (team, t + 1) when
the two vertices have the same fiber (the same members and basis), and keeps
its own value otherwise (the last instants repeat); every multiplier likewise
(dynamics edges by their tag, node rows by vertex). Needs a layout of
(team, instant) vertices, so time blockings fall back to the previous plan.
"""
function _shift_maps!(C::MPCController)
    fp = C.fp
    P = reduced_program(C)
    L = isempty(C.chain) ? fp.layout : C.chain[end].layout
    (L === nothing || ntimes(L) != C.fleet.H + 1) && return C
    same(v, w) = isempty(C.chain) ? P.dims[v] == P.dims[w] :
                 (Fv = C.chain[end].fibers[v]; Fw = C.chain[end].fibers[w];
                  length(Fv.members) == length(Fw.members) && Fv.N == Fw.N && P.dims[v] == P.dims[w])
    # composite fibers of a chain: only the last level is compared, which is enough for teams of teams over instants
    src = collect(1:nvertices(P))
    for a in axes(L.vid, 1), t in 1:(ntimes(L)-1)
        v, w = L.vid[a, t], L.vid[a, t+1]
        (v > 0 && w > 0 && same(v, w)) && (src[v] = w)
    end
    xmap = zeros(Int, c0dim(P))
    for v in 1:nvertices(P), (k, j) in enumerate(vrange(P, v))
        xmap[j] = P.offsets[src[v]] + k
    end
    # multipliers, in the full row order of sheaf_qp: hard edges, then node rows
    M = C.qmap
    bytag = Dict{EdgeTag,Int}()
    for (e, E) in enumerate(P.edges)
        bytag[E.tag] = e
    end
    full = Int[]
    hard = [e for (e, E) in enumerate(P.edges) if E.hard && edgedim(E) > 0]
    hpos = Dict{Int,Int}()
    r = 0
    for e in hard
        hpos[e] = r; r += edgedim(P.edges[e])
    end
    for e in hard
        E = P.edges[e]
        t2 = EdgeTag(E.tag.kind, E.tag.i, E.tag.j, E.tag.t + 1)
        f = get(bytag, t2, 0)
        f = (f > 0 && haskey(hpos, f) && edgedim(P.edges[f]) == edgedim(E)) ? f : e
        append!(full, hpos[f] .+ (1:edgedim(E)))
    end
    nh = r
    for v in 1:nvertices(P)
        w = src[v]
        w2 = length(rrange(P, w)) == length(rrange(P, v)) ? w : v
        append!(full, nh .+ collect(rrange(P, w2)))
    end
    ymap = [M.group[full[i]] for i in M.keep]
    C.xmap = xmap
    C.ymap = ymap
    return C
end

"""The reduced QP's current program (the last level of the reduction)."""
reduced_program(C::MPCController) = isempty(C.chain) ? C.fp.program : C.chain[end].program

"""The QP of `M` with its current vectors (the scaling is computed from the first step's data)."""
function _current_qp(M::QPMap)
    qp = M.qp
    m = nrows(qp)
    l = fill(-Inf, m); u = fill(Inf, m); socb = zeros(m)
    @inbounds for i in 1:m
        k = qp.kinds[i]
        if k == ROW_EQ
            l[i] = M.b[i]; u[i] = M.b[i]
        elseif k == ROW_LEQ
            u[i] = M.b[i]
        else
            socb[i] = M.b[i]
        end
    end
    return ConicQP(qp.P, M.q, qp.A, l, u; c = M.c, socs = qp.socs, socb = socb, kinds = qp.kinds)
end

function _setup!(C::MPCController)
    C.solver = setup(_current_qp(C.qmap); settings = C.settings)
    return C
end

"""
    step!(ctrl, x, refs; terminal = nothing, targets = nothing, drift = nothing, states = nothing) -> StepInfo

One receding-horizon step from the measured states `x[i]` with the references
`refs[i]` (and terminal references, see `set_references!`), optionally new
formation targets (`p x nedges x H`), drifts and state sets (`states`, one
entry per agent as in `set_state_sets!`: `nothing`, a `Polyhedron` for every
instant, or one per instant; each on the rows and pattern the controller was
built with): update the fine data in place, push them through the reduction,
solve the reduced QP warm, lift, and return the inputs to apply with the
diagnostics (`StepInfo`). State sets changed directly with `set_state_set!(ctrl.fp, ...)`
are picked up too.
"""
function step!(C::MPCController, x::AbstractVector, refs::AbstractVector; terminal = nothing, targets = nothing,
               drift = nothing, states = nothing)
    t0 = time_ns()
    info = C.info
    fp = C.fp
    set_state!(fp, x)
    set_references!(fp, refs; terminal = terminal)
    targets === nothing || set_targets!(fp, targets)
    drift === nothing || set_drift!(fp, drift)
    states === nothing || set_state_sets!(fp, states)
    # constraint matrices changed in place: the coarse matrices of every level, then the QP's
    verts = fp.changed
    newA = !isempty(verts)
    if newA
        C.cert === nothing || update_matrices!(C.cert, verts)
        for R in C.chain
            verts = update_matrices!(R, verts)
        end
    end
    feasible = true
    for R in C.chain
        update!(R)
        feasible &= R.feasible
    end
    Pq = reduced_program(C)
    refresh!(C.qmap, Pq)
    newA && refresh_matrices!(C.qmap, Pq, verts)
    empty!(fp.changed)
    if !C.qmap.valid
        # merged duplicate rows stopped agreeing: rebuild the QP without merging
        C.qmap = QPMap(Pq; dedup = false)
        C.dedup = false
        C.yfull = zeros(length(C.qmap.group))
        C.solver = nothing
        C.warm == :shift && _shift_maps!(C)
    end
    t1 = time_ns()
    M = C.qmap
    if C.solver === nothing
        _setup!(C)
        s = C.solver
    else
        s = C.solver
        newA ? update!(s; q = M.q, b = M.b, c = M.c, A = M.qp.A) : update!(s; q = M.q, b = M.b, c = M.c)
        if C.warm == :cold || s.info.status != :solved
            reset!(s)
        elseif C.warm == :shift && !isempty(C.xmap)
            warm_start_shifted!(s, C.xmap, C.ymap)
        end
    end
    t2 = time_ns()
    sinfo = solve!(s)
    t3 = time_ns()
    # lift through the levels to the fine plan
    nl = length(C.chain)
    copyto!(C.levels[nl+1], s.xsol)
    for k in nl:-1:1
        lift!(C.levels[k], C.chain[k], C.levels[k+1])
    end
    xf = C.levels[1]
    P = fp.program
    @inbounds for (i, ag) in enumerate(C.fleet.agents)
        o = P.offsets[fp.vid[i, 1]] + ag.nx
        ui = info.u[i]
        for a in 1:ag.nu
            ui[a] = xf[o+a]
        end
    end
    t4 = time_ns()
    up = NaN; res = NaN
    if C.cert !== nothing && sinfo.status == :solved && feasible
        expand_duals!(C.yfull, M, s.ysol)
        fill!(C.hard_duals, 0.0)
        @inbounds for k in 1:M.nh
            C.hard_duals[M.hard_rows[k]] = C.yfull[k]
        end
        @inbounds for k in eachindex(C.node_duals)
            C.node_duals[k] = C.yfull[M.nh+k]
        end
        up = certify!(C.cert, xf, C.hard_duals, C.node_duals)
        res = C.cert.residual
    end
    t5 = time_ns()
    info.status = feasible ? sinfo.status : :primal_infeasible
    info.J = sinfo.obj - s.c0 + M.c
    info.iter = sinfo.iter
    info.polish = sinfo.polish
    info.feasible = feasible
    info.gap_upper = up
    info.gap_residual = res
    info.t_construct = (t1 - t0) / 1e9
    info.t_setup = (t2 - t1) / 1e9
    info.t_solve = (t3 - t2) / 1e9
    info.t_lift = (t4 - t3) / 1e9
    info.t_certify = (t5 - t4) / 1e9
    info.t_total = (t5 - t0) / 1e9
    C.steps += 1
    return info
end

"""The fine plan of the last step (agent-major, as in `trajectories(ctrl.fp, plan(ctrl))`)."""
plan(C::MPCController) = C.levels[1]

"""Forget the solver's iterate: the next step starts cold (factorizations are kept)."""
function reset!(C::MPCController)
    C.solver === nothing || reset!(C.solver)
    return C
end
