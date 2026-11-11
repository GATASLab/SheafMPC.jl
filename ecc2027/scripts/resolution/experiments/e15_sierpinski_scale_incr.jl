# E15-sierpinski-scale, incremental assembly: the closed loop of
# e15_sierpinski_scale.jl (Sierpinski fleets of 3^d ground vehicles, every level
# of the hierarchy of teams fully condensed, keep-out disc above the apex, the
# time-expanded fine program as the baseline) with every program assembled the
# way a receding-horizon controller assembles it, and every timed quantity
# measured with one estimator.
#
#   BENCH_DEPTH=4 julia --project=bench/central/envs/teammpc scripts/resolution/experiments/e15_sierpinski_scale_incr.jl
#
# (any environment with the packages of bench/mpc runs it; with TeamMPC in the
# active project it also records the TeamMPC column, E15_TEAMMPC=0 turns that off.)
#
# Fixed and changing data. Over the closed loop the dynamics, the team
# structure, the condensing operators, the formation offsets and weights and the
# sparsity of every matrix are fixed; the measured states, the references, the
# formation targets and the keep-out half-spaces (which vehicle-instants are
# near the disc, and their tangent directions) change. Every program is
#
#     min (1/2) U'HU + g'U + c   s.t.   b - A U in K,
#
# and for a level (teams = clusters) the cost is a weighted least-squares
# residual r = Lu U + r0 with r0 = Rx xc + rfix - d, where xc stacks the teams'
# measured states and d the references and targets (written in place). So H is
# fixed, g = Lu'W r0 and c = (1/2) r0'W r0 cost two sparse products, the input
# cones are fixed, and the keep-out rows are -K S with S the fixed sparse
# operator of the planned positions (one row pair per vehicle-instant) and K
# the tangent directions of the active half-spaces (two entries per row). The
# time-expanded program is the same with H fixed (node costs plus the weighted
# Laplacian of the formation springs), g = Gd d, the dynamics rows fixed, the
# initial-state rows written in place, and the keep-out rows -K S on the
# position coordinates. Offline construction (once per level, outside the loop)
# builds these operators; it is timed and reported separately.
#
# Estimator: at the timed steps TIMED15 the per-step assembly and the solve (the
# solver of the figure, solve_qp with OPTS15_TIMING, Clarabel, for every level
# and for the time-expanded program) each run, after a garbage collection, once
# untimed and then NREP15I times, timed with @elapsed inside a function; the record holds every sample
# and the median, min and max over all timed samples of the level. The offline
# construction is measured the same way. The load average is recorded.
#
# Checks, at every step of every level: the incremental program equals the
# from-scratch build (reduced15) to round-off in every matrix and vector, and
# both solved at OPTS15 have the same optimal value to round-off. At the timed
# steps the incremental time-expanded program equals the library's build_model
# (rows permuted) and its optimal value equals solve_direct's; the agents level
# plan equals the time-expanded plan (as in E15). The closed loop is driven by
# the incremental programs, so the d = 3 positions are compared with E14 by
# e15_summary.jl as before.
#
# TeamMPC column (extra, not in the figure): every level is also solved by
# TeamMPC.jl's conic ADMM (setup once on the first step's program, then per
# step update! of q, b, c and of the values of A, a warm start from the previous
# solution shifted by one instant, and solve!). TeamMPC keeps the sparsity of
# setup, so its keep-out block has one row per screened vehicle-instant (the
# vehicles whose reference line passes within the disc radius plus margin plus
# SCREEN15 of the centre, every instant); a row that is not active at a step
# holds zeros and b = 1 (the trivial 0 <= 1). Accuracy: its objective against
# the OPTS15 optimum and its constraint violation on the true program.
#
# Writes results/e15_sierpinski_scale_d<d>_incr.json.

include(joinpath(@__DIR__, "e15_sierpinski_scale.jl"))

const SpMat = SparseMatrixCSC{Float64,Int}
const NREP15I = parse(Int, get(ENV, "BENCH_REPS", "5"))
const SCREEN15 = 1.0                                    # TeamMPC keep-out screen, m beyond radius + margin
const TEAMMPC15 = get(ENV, "E15_TEAMMPC", "1") == "1" && let p = Base.active_project()
    p !== nothing && isfile(p) && occursin(r"(?m)^TeamMPC\s*=", read(p, String))
end
TEAMMPC15 && @eval import TeamMPC
const SM_EPS15 = parse(Float64, get(ENV, "E15_SM_EPS", "1e-8"))

"""Collect garbage, run `f` once untimed, then `nrep` times timed; the samples in seconds."""
function sample15(f, nrep::Int = NREP15I)
    GC.gc()
    f()
    return Float64[@elapsed(f()) for _ in 1:nrep]
end
stats15(v) = Dict{String,Any}("median" => median(v), "min" => minimum(v), "max" => maximum(v), "n" => length(v))
maxabs15(A, B) = (isempty(A) && isempty(B)) ? 0.0 : maximum(abs, A - B)
loadavg15() = collect(Sys.loadavg())

# ---------------------------------------------------------------------------
# The data that change: references, terminal velocities, formation targets
# ---------------------------------------------------------------------------

struct Layout15
    n::Int; H::Int; ne::Int; nd::Int
end
Layout15(n, H, ne) = Layout15(n, H, ne, 2n * (H + 1) + 2n + 2ne * H)
iref(L::Layout15, i, t) = 2 * ((i - 1) * (L.H + 1) + t)
ivref(L::Layout15, i) = 2L.n * (L.H + 1) + 2 * (i - 1)
iform(L::Layout15, e, t) = 2L.n * (L.H + 1) + 2L.n + 2 * ((t - 1) * L.ne + (e - 1))
iko(L::Layout15, i, t) = 2 * ((i - 1) * L.H + (t - 1))           # keep-out row pair of (i, t), t = 1..H

function fill_data!(d::Vector{Float64}, L::Layout15, spec::MPCSpec)
    @inbounds for i in 1:L.n
        R = spec.ref[i]
        for t in 0:L.H
            o = iref(L, i, t); d[o+1] = R[1, t+1]; d[o+2] = R[2, t+1]
        end
        o = ivref(L, i); v = spec.vref[i]; d[o+1] = v[1]; d[o+2] = v[2]
    end
    @inbounds for t in 1:L.H, e in 1:L.ne
        o = iform(L, e, t); d[o+1] = spec.ftarget[1, e, t]; d[o+2] = spec.ftarget[2, e, t]
    end
    return d
end

"""Block-diagonal weight of the data: stage and terminal tracking, terminal velocity, formation springs."""
function data_weight(L::Layout15, spec::MPCSpec)
    ag = spec.agents[1]
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    blk!(o, W) = for b in 1:2, a in 1:2
        W[a, b] != 0 && (push!(I_, o + a); push!(J_, o + b); push!(V_, W[a, b]))
    end
    for i in 1:L.n, t in 0:L.H
        blk!(iref(L, i, t), t < L.H ? ag.Q : ag.Qf)
    end
    for i in 1:L.n
        blk!(ivref(L, i), ag.qv * Matrix{Float64}(I, 2, 2))
    end
    for t in 1:L.H, e in 1:L.ne
        blk!(iform(L, e, t), spec.fweight[e, t] * Matrix{Float64}(I, 2, 2))
    end
    return sparse(I_, J_, V_, L.nd, L.nd)
end

function check_spec15(spec::MPCSpec)
    ag = spec.agents[1]
    all(a -> a === ag || (a.A == ag.A && a.B == ag.B && a.c == ag.c), spec.agents) || error("heterogeneous fleet")
    (size(ag.Cr, 1) == 2 && size(ag.C, 1) == 2 && length(ag.vel) == 2) || error("planar outputs expected")
    all(spec.present) || error("absent formation edges are not handled")
    return ag
end

"""Push the nonzeros of the dense block `M` at (r0, c0) with factor s."""
function push_dense!(I_, J_, V_, r0::Int, c0::Int, M::AbstractMatrix, s::Float64 = 1.0)
    @inbounds for j in axes(M, 2), i in axes(M, 1)
        v = M[i, j]
        v != 0 && (push!(I_, r0 + i); push!(J_, c0 + j); push!(V_, s * v))
    end
end

"""The keep-out rows of the active half-spaces: K' (2nH x nh, the tangent directions) and b's ingredients."""
function keepout_K(L::Layout15, spec::MPCSpec)
    nh = sum(length, spec.halfspaces)
    rowval = Vector{Int}(undef, 2nh); nzval = Vector{Float64}(undef, 2nh)
    j = 0
    @inbounds for i in 1:L.n, (t, a, _) in spec.halfspaces[i]
        j += 1; o = iko(L, i, t)
        rowval[2j-1] = o + 1; rowval[2j] = o + 2; nzval[2j-1] = a[1]; nzval[2j] = a[2]
    end
    return SparseMatrixCSC(2L.n * L.H, nh, collect(1:2:(2nh+1)), rowval, nzval), nh
end

"""`A_ko = (St Kt)'` without zeros created by a zero tangent component."""
function keepout_rows(St::SpMat, Kt::SpMat)
    AT = St * Kt
    return dropzeros!(SpMat(copy(transpose(AT))))
end

# ---------------------------------------------------------------------------
# A level (clusters = teams): the operators and the per-step update
# ---------------------------------------------------------------------------

struct Level15
    L::Layout15
    label::Vector{Int}; k::Int; m::Int; nx::Int; rep::Vector{Int}; delta::Vector{Vector{Float64}}
    H::SpMat; LtW::SpMat; Wd::SpMat; Rx::SpMat; rfix::Vector{Float64}
    Acone::SpMat; bcone::Vector{Float64}; cones::Vector{ConeBlock}
    St::SpMat; Pko::SpMat; pko0::Vector{Float64}
    E::Matrix{Float64}
    d::Vector{Float64}; r::Vector{Float64}; Wr::Vector{Float64}; Xc::Vector{Float64}; g::Vector{Float64}; pfree::Vector{Float64}
end

"""Offline construction of a level: everything that does not change over the closed loop."""
function build_level15(spec::MPCSpec, label::Vector{Int}, cond, L::Layout15)
    ag = check_spec15(spec)
    n, H = spec.n, spec.H
    nx, nu = ag.nx, ag.nu; m = nu * H
    Phi, Gam, gg = cond
    k = maximum(label)
    rep = [findfirst(==(c), label) for c in 1:k]
    delta = [spec.offsets[:, i, 1] - spec.offsets[:, rep[label[i]], 1] for i in 1:n]
    Sv = zeros(length(ag.vel), nx)
    for (q, idx) in enumerate(ag.vel)
        Sv[q, idx] = 1.0
    end
    CrG = [ag.Cr * Gam[t+1] for t in 0:H]; CG = [ag.C * Gam[t+1] for t in 0:H]
    CrP = [ag.Cr * Phi[t+1] for t in 0:H]; CP = [ag.C * Phi[t+1] for t in 0:H]
    LI = Int[]; LJ = Int[]; LV = Float64[]
    XI = Int[]; XJ = Int[]; XV = Float64[]
    rfix = zeros(L.nd)
    for i in 1:n
        c = label[i]
        for t in 0:H
            o = iref(L, i, t)
            push_dense!(LI, LJ, LV, o, (c - 1) * m, CrG[t+1])
            push_dense!(XI, XJ, XV, o, (c - 1) * nx, CrP[t+1])
            rfix[o.+(1:2)] = ag.Cr * (gg[t+1] + ag.E * delta[i])
        end
        o = ivref(L, i)
        push_dense!(LI, LJ, LV, o, (c - 1) * m, Sv * Gam[H+1])
        push_dense!(XI, XJ, XV, o, (c - 1) * nx, Sv * Phi[H+1])
        rfix[o.+(1:2)] = Sv * gg[H+1]
    end
    for (e, (i, j)) in enumerate(spec.gedges), t in 1:H
        ci, cj = label[i], label[j]
        o = iform(L, e, t)
        rfix[o.+(1:2)] = ag.C * ag.E * (delta[j] - delta[i])
        ci == cj && continue                     # inside a team: a constant (zero for exact targets)
        push_dense!(LI, LJ, LV, o, (cj - 1) * m, CG[t+1]); push_dense!(LI, LJ, LV, o, (ci - 1) * m, CG[t+1], -1.0)
        push_dense!(XI, XJ, XV, o, (cj - 1) * nx, CP[t+1]); push_dense!(XI, XJ, XV, o, (ci - 1) * nx, CP[t+1], -1.0)
    end
    Lu = sparse(LI, LJ, LV, L.nd, k * m)
    Rx = sparse(XI, XJ, XV, L.nd, k * nx)
    Wd = data_weight(L, spec)
    LtW = SpMat(Lu' * Wd)
    cnt = zeros(Int, k)
    for i in 1:n
        cnt[label[i]] += 1
    end
    KR = kron(Matrix{Float64}(I, H, H), ag.R)
    HI = Int[]; HJ = Int[]; HV = Float64[]
    for c in 1:k
        push_dense!(HI, HJ, HV, (c - 1) * m, (c - 1) * m, KR, Float64(cnt[c]))
    end
    Hm = LtW * Lu + sparse(HI, HJ, HV, k * m, k * m)
    Hm = dropzeros!(SpMat((Hm + Hm') / 2))
    # input cones: fixed (the rows of reduced15, in its order)
    AI = Int[]; AJ = Int[]; AV = Float64[]; bc = Float64[]; cones = ConeBlock[]
    row = 0
    for c in 1:k, t in 0:(H-1)
        push!(bc, ag.abar); append!(bc, zeros(nu))
        for q in 1:nu
            push!(AI, row + 1 + q); push!(AJ, (c - 1) * m + t * nu + q); push!(AV, -1.0)
        end
        row += 1 + nu; push!(cones, soc_cone(1 + nu))
    end
    Acone = sparse(AI, AJ, AV, row, k * m)
    # keep-out operators: planned position of (i, t) = C Gam u_c + C Phi xc + C (g + E delta_i)
    SI = Int[]; SJ = Int[]; SV = Float64[]
    PI = Int[]; PJ = Int[]; PV = Float64[]
    pko0 = zeros(2n * H)
    for i in 1:n, t in 1:H
        c = label[i]; o = iko(L, i, t)
        push_dense!(SI, SJ, SV, (c - 1) * m, o, transpose(CG[t+1]), -1.0)
        push_dense!(PI, PJ, PV, o, (c - 1) * nx, CP[t+1])
        pko0[o.+(1:2)] = ag.C * (gg[t+1] + ag.E * delta[i])
    end
    St = sparse(SI, SJ, SV, k * m, 2n * H)
    Pko = sparse(PI, PJ, PV, 2n * H, k * nx)
    return Level15(L, label, k, m, nx, rep, delta, Hm, LtW, Wd, Rx, rfix, Acone, bc, cones, St, Pko, pko0, ag.E,
                   zeros(L.nd), zeros(L.nd), zeros(L.nd), zeros(k * nx), zeros(k * m), zeros(2n * H))
end

"""The program of one step from the operators: (H, g, c, A, b, cones); vectors written in place, rows by sparse products."""
function assemble15!(lv::Level15, spec::MPCSpec)
    n, nx = lv.L.n, lv.nx
    @inbounds for i in 1:n                               # members in formation with the cluster's velocity
        xi = spec.xhat[i]; xr = spec.xhat[lv.rep[lv.label[i]]]; di = lv.delta[i]
        for a in 1:nx
            s = xr[a]
            for q in 1:2
                s += lv.E[a, q] * di[q]
            end
            abs(xi[a] - s) <= 1e-8 || error("member $i is not in formation with its cluster")
        end
    end
    @inbounds for c in 1:lv.k
        xr = spec.xhat[lv.rep[c]]
        for a in 1:nx
            lv.Xc[(c-1)*nx+a] = xr[a]
        end
    end
    fill_data!(lv.d, lv.L, spec)
    r = lv.r
    mul!(r, lv.Rx, lv.Xc)
    @inbounds for j in eachindex(r)
        r[j] += lv.rfix[j] - lv.d[j]
    end
    mul!(lv.Wr, lv.Wd, r)
    mul!(lv.g, lv.LtW, r)
    cz = 0.5 * dot(r, lv.Wr)
    mul!(lv.pfree, lv.Pko, lv.Xc)
    lv.pfree .+= lv.pko0
    Kt, nh = keepout_K(lv.L, spec)
    bko = Vector{Float64}(undef, nh)
    j = 0
    @inbounds for i in 1:n, (t, a, beta) in spec.halfspaces[i]
        j += 1; o = iko(lv.L, i, t)
        bko[j] = a[1] * lv.pfree[o+1] + a[2] * lv.pfree[o+2] - beta
    end
    A = nh == 0 ? lv.Acone : vcat(lv.Acone, keepout_rows(lv.St, Kt))
    b = nh == 0 ? lv.bcone : vcat(lv.bcone, bko)
    cones = nh == 0 ? lv.cones : vcat(lv.cones, ConeBlock[nonneg_cone(1) for _ in 1:nh])
    return lv.H, lv.g, cz, A, b, cones
end

"""Planned positions and first inputs from the level's solution (as unpack15)."""
function unpack_incr(lv::Level15, U, cond, spec)
    ag = spec.agents[1]; m = lv.m
    Phi, Gam, gg = cond
    xc = [spec.xhat[lv.rep[c]] for c in 1:lv.k]
    uc = [U[((c-1)*m+1):(c*m)] for c in 1:lv.k]
    pos = [reduce(hcat, [ag.C * (Phi[t+1] * xc[lv.label[i]] + Gam[t+1] * uc[lv.label[i]] + gg[t+1]) + lv.delta[i]
                         for t in 0:spec.H]) for i in 1:spec.n]
    u0 = [uc[lv.label[i]][1:ag.nu] for i in 1:spec.n]
    return pos, u0
end

# ---------------------------------------------------------------------------
# The time-expanded fine program: operators and per-step update
# ---------------------------------------------------------------------------

struct Fine15
    L::Layout15
    Hq::SpMat; Gd::SpMat; gfix::Vector{Float64}; cfix::Float64; Wd::SpMat
    Afix::SpMat; bfix::Vector{Float64}; cones::Vector{ConeBlock}; nhard::Int
    initrows::Vector{Int}; St::SpMat; vid::Matrix{Int}; offsets::Vector{Int}
    d::Vector{Float64}; Wdd::Vector{Float64}; g::Vector{Float64}; b::Vector{Float64}
end

"""Offline construction of the time-expanded program from a step without half-spaces (build_model's layout)."""
function build_fine15(spec0::MPCSpec, L::Layout15)
    ag = check_spec15(spec0)
    all(isempty, spec0.halfspaces) || error("the fine template must have no half-spaces")
    model = build_model(spec0)
    P = model.program
    n, H, nx = spec0.n, spec0.H, ag.nx
    Hq, g0, c0 = quadratic_form(P)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    all(E.hard || E.tag.kind == :form for E in P.edges) || error("unexpected soft edge")
    Dh = edge_operator(P, hard); bh = targets(P, hard)
    An, bn, cn, roff = node_constraints(P)
    Afix = SpMat([Dh; An]); bfix = [bh; bn]
    cones = ConeBlock[]
    length(bh) > 0 && push!(cones, zero_cone(length(bh)))
    append!(cones, cn)
    initrows = Int[]
    for i in 1:n
        append!(initrows, length(bh) + roff[model.vid[i, 1]] .+ (1:nx))
    end
    Sv = zeros(2, nx)
    for (q, idx) in enumerate(ag.vel)
        Sv[q, idx] = 1.0
    end
    GI = Int[]; GJ = Int[]; GV = Float64[]
    for i in 1:n, t in 0:H
        Wt = t < H ? ag.Q : ag.Qf
        push_dense!(GI, GJ, GV, P.offsets[model.vid[i, t+1]], iref(L, i, t), ag.Cr' * Wt, -1.0)
    end
    for i in 1:n
        push_dense!(GI, GJ, GV, P.offsets[model.vid[i, H+1]], ivref(L, i), ag.qv * Sv', -1.0)
    end
    for t in 1:H, (k, (i, j)) in enumerate(spec0.gedges)
        E = P.edges[model.form[k, t]]
        push_dense!(GI, GJ, GV, P.offsets[E.head], iform(L, k, t), E.Fh' * E.W, -1.0)
        push_dense!(GI, GJ, GV, P.offsets[E.tail], iform(L, k, t), E.Ft' * E.W, 1.0)
    end
    Gd = sparse(GI, GJ, GV, c0dim(P), L.nd)
    Wd = data_weight(L, spec0)
    d0 = fill_data!(zeros(L.nd), L, spec0)
    gfix = g0 - Gd * d0
    cfix = c0 - 0.5 * dot(d0, Wd * d0)
    SI = Int[]; SJ = Int[]; SV = Float64[]
    for i in 1:n, t in 1:H
        push_dense!(SI, SJ, SV, P.offsets[model.vid[i, t+1]], iko(L, i, t), transpose(ag.C), -1.0)
    end
    St = sparse(SI, SJ, SV, c0dim(P), 2n * H)
    return Fine15(L, Hq, Gd, gfix, cfix, Wd, Afix, bfix, cones, length(bh), initrows, St, model.vid, P.offsets,
                  zeros(L.nd), zeros(L.nd), zeros(c0dim(P)), copy(bfix))
end

"""The time-expanded program of one step: hard rows, node rows, then the keep-out rows."""
function assemble_fine15!(fo::Fine15, spec::MPCSpec)
    fill_data!(fo.d, fo.L, spec)
    mul!(fo.g, fo.Gd, fo.d)
    fo.g .+= fo.gfix
    mul!(fo.Wdd, fo.Wd, fo.d)
    c = fo.cfix + 0.5 * dot(fo.d, fo.Wdd)
    nx = length(spec.xhat[1])
    @inbounds for i in 1:fo.L.n, a in 1:nx
        fo.b[fo.initrows[(i-1)*nx+a]] = spec.xhat[i][a]
    end
    Kt, nh = keepout_K(fo.L, spec)
    bko = Float64[-beta for i in 1:fo.L.n for (_, _, beta) in spec.halfspaces[i]]
    A = nh == 0 ? fo.Afix : vcat(fo.Afix, keepout_rows(fo.St, Kt))
    b = nh == 0 ? fo.b : vcat(fo.b, bko)
    cones = nh == 0 ? fo.cones : vcat(fo.cones, ConeBlock[nonneg_cone(1) for _ in 1:nh])
    return fo.Hq, fo.g, c, A, b, cones
end

"""The library's flat QP of `model` (solve_direct's assembly), rows permuted to the order of assemble_fine15!."""
function library_fine_qp(model::MPCModel)
    P = model.program
    Hq, g, c = quadratic_form(P)
    hard = [e for e in hard_edges(P) if edgedim(P.edges[e]) > 0]
    Dh = edge_operator(P, hard); bh = targets(P, hard)
    An, bn, cn, roff = node_constraints(P)
    nko = zeros(Int, nvertices(P))
    for v in 1:nvertices(P), cb in P.nodes[v].cones
        cb.kind == NONNEG_CONE && (nko[v] += cb.dim)
    end
    fixed = Int[]; ko = Int[]
    for v in 1:nvertices(P)
        rr = (roff[v]+1):roff[v+1]
        append!(fixed, rr[1:(length(rr)-nko[v])]); append!(ko, rr[(length(rr)-nko[v]+1):end])
    end
    perm = [collect(1:length(bh)); length(bh) .+ fixed; length(bh) .+ ko]
    return Hq, g, c, SpMat([Dh; An][perm, :]), [bh; bn][perm]
end

"""Largest cone violation of b - A x."""
function violation15(A, b, cones, x)
    s = b - A * x
    v = 0.0; r = 0
    for cb in cones
        v = max(v, Resolution.cone_violation(cb.kind, view(s, (r+1):(r+cb.dim)))); r += cb.dim
    end
    return v
end

# ---------------------------------------------------------------------------
# TeamMPC column: setup once, update! values, warm start shifted, solve!
# ---------------------------------------------------------------------------

mutable struct SM15
    s::Any
    A::SpMat
    ncone::Int
    cand::Dict{Tuple{Int,Int},Int}
    nzpos::Vector{Vector{Int}}; cx::Vector{Vector{Float64}}; cy::Vector{Vector{Float64}}
    b::Vector{Float64}
    xmap::Vector{Int}; ymap::Vector{Int}
    lastA::Bool
    settings::Any
end

function screen15(layout, ob)
    return [i for i in eachindex(layout) if abs(layout[i][2] - ob.center[2]) <= ob.radius + MARGIN15 + SCREEN15]
end

"""The TeamMPC problem of a level with one keep-out row per candidate (vehicle, instant), and setup on the current step."""
function sm_setup15(lv::Level15, cand_i::Vector{Int}, H::Int, g, c, spec)
    L = lv.L; ncone = size(lv.Acone, 1)
    cands = [(i, t) for i in cand_i for t in 1:H]
    cand = Dict(ct => r for (r, ct) in enumerate(cands))
    CI = Int[]; CJ = Int[]; CV = Float64[]
    for (r, (i, t)) in enumerate(cands)
        o = iko(L, i, t)
        for col in (o + 1, o + 2), kk in nzrange(lv.St, col)
            push!(CI, r); push!(CJ, rowvals(lv.St)[kk]); push!(CV, 1.0)
        end
    end
    Cm = sparse(CI, CJ, CV, length(cands), size(lv.St, 1), (a, b) -> 1.0)
    A = SpMat(vcat(lv.Acone, Cm))
    nzpos = [Int[] for _ in cands]; cx = [Float64[] for _ in cands]; cy = [Float64[] for _ in cands]
    St = lv.St
    for col in 1:size(A, 2), kk in nzrange(A, col)
        row = rowvals(A)[kk]
        row > ncone || continue
        r = row - ncone; (i, t) = cands[r]; o = iko(L, i, t)
        push!(nzpos[r], kk); push!(cx[r], St[col, o+1]); push!(cy[r], St[col, o+2])
    end
    b = [lv.bcone; ones(length(cands))]
    sm = SM15(nothing, A, ncone, cand, nzpos, cx, cy, b, Int[], Int[], false, nothing)
    sm_write!(sm, lv, spec)
    # warm-start maps: inputs and cone rows of (team, t) <- (team, t + 1), keep-out rows (i, t) <- (i, t + 1)
    k, m, nu = lv.k, lv.m, lv.m ÷ H
    sm.xmap = [((c - 1) * m + min(t + 1, H - 1) * nu + q) for c in 1:k for t in 0:(H-1) for q in 1:nu]
    sm.ymap = [((c - 1) * H * (1 + nu) + min(t + 1, H - 1) * (1 + nu) + q) for c in 1:k for t in 0:(H-1) for q in 1:(1+nu)]
    for (i, t) in cands
        push!(sm.ymap, ncone + cand[(i, min(t + 1, H))])
    end
    st = TeamMPC.Settings()
    st.eps_abs = SM_EPS15; st.eps_rel = SM_EPS15; st.max_iter = 100_000; st.time_limit = 600.0
    sm.settings = st
    cones = Tuple{Symbol,Int}[(:soc, cb.dim) for cb in lv.cones]
    all(cb -> cb.kind == SOC_CONE, lv.cones) || error("input cones must be second-order cones")
    isempty(cands) || push!(cones, (:nonneg, length(cands)))
    qp = TeamMPC.ConicQP(lv.H, g, sm.A, sm.b, cones; c = c)
    t = @elapsed sm.s = TeamMPC.setup(qp; settings = st)
    return sm, t
end

"""Write this step's keep-out rows into the candidate block (zeros and b = 1 where inactive). True if A changed."""
function sm_write!(sm::SM15, lv::Level15, spec)
    nz = nonzeros(sm.A)
    any_active = false
    for r in eachindex(sm.nzpos)
        for kk in sm.nzpos[r]
            nz[kk] = 0.0
        end
        sm.b[sm.ncone+r] = 1.0
    end
    for i in 1:lv.L.n, (t, a, beta) in spec.halfspaces[i]
        r = get(sm.cand, (i, t), 0)
        r == 0 && return :missing
        o = iko(lv.L, i, t)
        pos = sm.nzpos[r]; cx = sm.cx[r]; cy = sm.cy[r]
        @inbounds for q in eachindex(pos)
            nz[pos[q]] = a[1] * cx[q] + a[2] * cy[q]
        end
        sm.b[sm.ncone+r] = a[1] * lv.pfree[o+1] + a[2] * lv.pfree[o+2] - beta
        any_active = true
    end
    changed = any_active || sm.lastA
    sm.lastA = any_active
    return changed
end

"""One TeamMPC step: (t_update, t_solve, info). `lv` must hold this step's assembly (pfree)."""
function sm_step15!(sm::SM15, lv::Level15, spec, g, c)
    t1 = @elapsed begin
        ch = sm_write!(sm, lv, spec)
        ch === :missing && error("a keep-out row outside the TeamMPC screen")
        TeamMPC.update!(sm.s; q = g, b = sm.b, c = c, A = ch ? sm.A : nothing)
        TeamMPC.warm_start_shifted!(sm.s, sm.xmap, sm.ymap)
    end
    t2 = @elapsed info = TeamMPC.solve!(sm.s)
    return t1, t2, info
end

# ---------------------------------------------------------------------------
# The closed loop of one level
# ---------------------------------------------------------------------------

function run_level15_incr(layout, edges, label, ob; steps = STEPS15, time_fine = false)
    n = length(layout); H = H15
    ag0 = rover_agent(fill(DT15, H)); cond = condensing_matrices(ag0, H)
    L = Layout15(n, H, length(edges))
    x = [[layout[i]; SPEED15; 0.0] for i in 1:n]
    spec0 = spec15(layout, edges; xhat = x, t0 = 0.0, nominal = nothing, ob = ob)
    # the first nominal: the obstacle-free optimum of the agents level (= the fine program), as E15
    R0 = reduced15(spec0, collect(1:n), cond)
    s0 = solve_qp(R0.H, R0.g, R0.c, R0.A, R0.b, R0.cones; opts = OPTS15)
    nom = unpack15(R0, s0.x, cond, spec0)[1]
    # offline construction of the level (and of the time-expanded program), measured like everything else
    t_off = sample15(() -> build_level15(spec0, label, cond, L))
    lv = build_level15(spec0, label, cond, L)
    fo = nothing; t_off_fine = Float64[]
    if time_fine
        t_off_fine = sample15(() -> build_fine15(spec0, L))
        fo = build_fine15(spec0, L)
    end
    sm = nothing; t_sm_setup = NaN; sm_cand = Int[]
    rec = Dict{String,Any}[]; fine = Dict{String,Any}[]; cost = 0.0
    asm_all = Float64[]; sol_all = Float64[]; smu_all = Float64[]; sms_all = Float64[]
    for kstep in 0:(steps-1)
        t0 = kstep * DT15
        timed = kstep in TIMED15
        spec = spec15(layout, edges; xhat = x, t0 = t0, nominal = nom, ob = ob)
        ta = @elapsed (Hm, g, cz, A, b, cones) = assemble15!(lv, spec)
        tsc = @elapsed R = reduced15(spec, label, cond)
        size(A) == size(R.A) || error("keep-out rows differ from the from-scratch build")
        dd = Dict{String,Any}("H" => maxabs15(Hm, R.H), "g" => maxabs15(g, R.g), "c" => abs(cz - R.c),
                              "A" => maxabs15(A, R.A), "b" => maxabs15(b, R.b), "nnz_H" => [nnz(Hm), nnz(R.H)],
                              "nnz_A" => [nnz(A), nnz(R.A)])
        sol = solve_qp(Hm, g, cz, A, b, cones; opts = OPTS15)
        sol.status in (:optimal, :almost_optimal) || error("level $(maximum(label)) clusters, step $kstep: $(sol.status)")
        solR = solve_qp(R.H, R.g, R.c, R.A, R.b, R.cones; opts = OPTS15)
        objrel = relerr(sol.obj, solR.obj)
        # the solve of the figure: untimed once in the loop, then NREP15I timed repeats at the timed steps
        soltime = solve_qp(Hm, g, cz, A, b, cones; opts = OPTS15_TIMING)
        r = Dict{String,Any}("step" => kstep, "positions" => [xi[1:2] for xi in x], "vars" => size(Hm, 1), "rows" => size(A, 1),
            "nnz_H" => nnz(Hm), "t_assemble" => ta, "t_assemble_scratch" => tsc, "timed" => timed,
            "iters_timing" => soltime.iterations, "obj" => sol.obj, "obj_scratch" => solR.obj, "obj_rel_scratch" => objrel,
            "obj_rel_timing" => relerr(soltime.obj, sol.obj), "data_diff" => dd,
            "halfspaces" => sum(length(h) for h in spec.halfspaces), "loadavg" => loadavg15())
        if timed
            ts_asm = sample15(() -> assemble15!(lv, spec))
            ts_sol = sample15(() -> solve_qp(Hm, g, cz, A, b, cones; opts = OPTS15_TIMING))
            r["t_assemble_samples"] = ts_asm; r["t_solve_samples"] = ts_sol
            r["t_solve_timing"] = median(ts_sol); r["t_assemble_timing"] = median(ts_asm)
            append!(asm_all, ts_asm); append!(sol_all, ts_sol)
            (Hm, g, cz, A, b, cones) = assemble15!(lv, spec)      # the buffers hold this step again
        end
        # TeamMPC column
        if TEAMMPC15
            if sm === nothing
                sm_cand = screen15(layout, ob)
                sm, t_sm_setup = sm_setup15(lv, sm_cand, H, g, cz, spec)
                t2 = @elapsed info = TeamMPC.solve!(sm.s)
                tsm = (0.0, t2, info)
            else
                saved = timed ? deepcopy(sm.s) : nothing
                tsm = sm_step15!(sm, lv, spec, g, cz)
                if timed
                    live = sm.s; ups = Float64[]; sls = Float64[]
                    for _ in 1:NREP15I
                        sm.s = deepcopy(saved)
                        u_, s_, _ = sm_step15!(sm, lv, spec, g, cz)
                        push!(ups, u_); push!(sls, s_)
                    end
                    sm.s = live
                    r["teammpc_update_samples"] = ups; r["teammpc_solve_samples"] = sls
                    append!(smu_all, ups); append!(sms_all, sls)
                end
            end
            xs = copy(sm.s.xsol)
            objs = 0.5 * dot(xs, Hm * xs) + dot(g, xs) + cz
            r["teammpc"] = Dict{String,Any}("status" => string(tsm[3].status), "iter" => tsm[3].iter,
                "method" => string(tsm[3].method), "polish" => string(tsm[3].polish), "t_update" => tsm[1], "t_solve" => tsm[2],
                "obj_rel" => relerr(objs, sol.obj), "violation" => violation15(A, b, cones, xs))
        end
        pos, u0 = unpack_incr(lv, sol.x, cond, spec)
        r["stage_cost"] = stage_cost(spec, x, u0)
        r["clearance"] = minimum(norm(xi[1:2] - ob.center) - ob.radius for xi in x)
        r["input_margin"] = minimum(ag0.abar - norm(u) for u in u0)
        if time_fine && timed
            tb = @elapsed model = build_model(spec)
            tfl = @elapsed lib = library_fine_qp(model)
            (Hf, gf, cf, Af, bf, cof) = assemble_fine15!(fo, spec)
            fdd = Dict{String,Any}("H" => maxabs15(Hf, lib[1]), "g" => maxabs15(gf, lib[2]), "c" => abs(cf - lib[3]),
                                   "A" => maxabs15(Af, lib[4]), "b" => maxabs15(bf, lib[5]))
            sfx = solve_qp(Hf, gf, cf, Af, bf, cof; opts = OPTS15)
            sdir = solve_direct(model.program; opts = OPTS15)
            fpos = planned_positions(model, sfx.x)
            tf_asm = sample15(() -> assemble_fine15!(fo, spec))
            sf = solve_qp(Hf, gf, cf, Af, bf, cof; opts = OPTS15_TIMING)
            tf_sol = sample15(() -> solve_qp(Hf, gf, cf, Af, bf, cof; opts = OPTS15_TIMING))
            push!(fine, Dict{String,Any}("step" => kstep, "vars" => length(gf), "rows" => size(Af, 1),
                "t_build_scratch" => tb, "t_flatten_scratch" => tfl,
                "t_assemble_samples" => tf_asm, "t_solve_samples" => tf_sol,
                "t_assemble" => median(tf_asm), "t_solve_timing" => median(tf_sol),
                "iters_timing" => sf.iterations, "status" => string(sfx.status), "obj" => sfx.obj, "obj_direct" => sdir.J,
                "obj_rel_direct" => relerr(sfx.obj, sdir.J), "obj_rel_timing" => relerr(sf.obj, sfx.obj), "data_diff" => fdd,
                "plan_vs_reduced" => maximum(maximum(abs.(fpos[i] - pos[i])) for i in 1:n),
                "plan_direct_vs_reduced" => maximum(maximum(abs.(fp - p)) for (fp, p) in zip(planned_positions(model, sdir.x), pos)),
                "loadavg" => loadavg15()))
        end
        push!(rec, r)
        cost += r["stage_cost"]
        nom = shifted_nominal(pos)
        x = plant_step(spec, x, u0)
    end
    specK = spec15(layout, edges; xhat = x, t0 = steps * DT15, nominal = nom, ob = ob)
    cost += stage_cost(specK, x, nothing)
    out = Dict{String,Any}("clusters" => maximum(label), "cluster_size" => n ÷ maximum(label), "steps" => rec,
        "final_positions" => [xi[1:2] for xi in x], "closed_loop_cost" => cost,
        "final_clearance" => minimum(norm(xi[1:2] - ob.center) - ob.radius for xi in x),
        "offline" => merge(stats15(t_off), Dict{String,Any}("samples" => t_off)),
        "assemble" => stats15(asm_all), "solve" => stats15(sol_all),
        "max_obj_rel_scratch" => maximum(s["obj_rel_scratch"] for s in rec),
        "max_data_diff" => maximum(maximum(Float64(v) for (kk, v) in s["data_diff"] if !startswith(kk, "nnz")) for s in rec),
        "same_pattern" => all(s["data_diff"]["nnz_H"][1] == s["data_diff"]["nnz_H"][2] &&
                              s["data_diff"]["nnz_A"][1] == s["data_diff"]["nnz_A"][2] for s in rec))
    if TEAMMPC15
        sms = [s["teammpc"] for s in rec]
        out["teammpc"] = Dict{String,Any}("setup" => t_sm_setup, "update" => stats15(smu_all), "solve" => stats15(sms_all),
            "candidates" => length(sm_cand) * H, "screened_vehicles" => sm_cand,
            "max_obj_rel" => maximum(s["obj_rel"] for s in sms), "max_violation" => maximum(s["violation"] for s in sms),
            "statuses" => unique(s["status"] for s in sms), "max_iter" => maximum(s["iter"] for s in sms),
            "methods" => unique(s["method"] for s in sms))
    end
    if time_fine
        out["fine"] = fine
        out["fine_offline"] = merge(stats15(t_off_fine), Dict{String,Any}("samples" => t_off_fine))
    end
    return out
end

function main15_incr(; d = DEPTH15)
    tstart = time()
    load0 = loadavg15()
    layout, labels, edges = sierpinski(d)
    n = length(layout)
    apex = argmax(p -> p[2], layout)
    ob = ObstacleT(([apex[1] + 4.0, apex[2] + 0.2], 1.2, :all))
    levels = Dict{String,Any}[]
    for l in 0:d
        t = @elapsed lv = run_level15_incr(layout, edges, labels[l+1], ob; time_fine = (l == 0))
        lv["level"] = l; lv["wall_seconds"] = t
        push!(levels, lv)
        @printf("d=%d n=%d level %d (%4d of %4d): cost %.3f  offline %.2e  asm %.2e [%.2e, %.2e]  solve %.2e [%.2e, %.2e]  obj %.1e data %.1e%s  (%.0f s)\n",
                d, n, l, lv["clusters"], lv["cluster_size"], lv["closed_loop_cost"], lv["offline"]["median"],
                lv["assemble"]["median"], lv["assemble"]["min"], lv["assemble"]["max"],
                lv["solve"]["median"], lv["solve"]["min"], lv["solve"]["max"], lv["max_obj_rel_scratch"], lv["max_data_diff"],
                TEAMMPC15 ? @sprintf("  TeamMPC upd %.2e solve %.2e obj %.1e viol %.1e", lv["teammpc"]["update"]["median"],
                                      lv["teammpc"]["solve"]["median"], lv["teammpc"]["max_obj_rel"], lv["teammpc"]["max_violation"]) : "",
                t)
        if l == 0
            for f in lv["fine"]
                @printf("    fine step %d: asm %.2e  solve %.2e  build+flatten (scratch) %.2e  obj vs direct %.1e  data %.1e  plan %.1e\n",
                        f["step"], f["t_assemble"], f["t_solve_timing"], f["t_build_scratch"] + f["t_flatten_scratch"],
                        f["obj_rel_direct"], maximum(values(f["data_diff"])), f["plan_vs_reduced"])
            end
        end
    end
    fine = levels[1]["fine"]
    fasm = reduce(vcat, [Float64.(f["t_assemble_samples"]) for f in fine])
    fsol = reduce(vcat, [Float64.(f["t_solve_samples"]) for f in fine])
    out = Dict{String,Any}("experiment" => "E15-sierpinski-scale-incremental", "depth" => d, "n" => n, "steps" => STEPS15,
        "H" => H15, "h" => DT15, "speed" => SPEED15, "layout" => layout, "labels" => labels, "edges" => edges,
        "obstacle" => Dict("center" => ob.center, "radius" => ob.radius), "levels" => levels, "fine" => fine,
        "fine_offline" => levels[1]["fine_offline"], "fine_assemble" => stats15(fasm), "fine_solve" => stats15(fsol),
        "estimator" => Dict{String,Any}("timed_steps" => TIMED15, "repeats" => NREP15I, "warmup" => 1,
            "statistic" => "median, min and max over all timed samples (timed steps x repeats)",
            "solve" => "solve_qp with OPTS15_TIMING (Clarabel), the same call for every level and the time-expanded program"),
        "teammpc" => TEAMMPC15 ? Dict{String,Any}("eps" => SM_EPS15, "screen" => SCREEN15,
            "version" => string(pkgversion(TeamMPC)), "dir" => pkgdir(TeamMPC),
            "commit" => get(ENV, "TEAMMPC_COMMIT", ""), "src_sha1" => get(ENV, "TEAMMPC_SRC_SHA", "")) : nothing,
        "meta" => run_metadata(OPTS15), "meta_timing" => run_metadata(OPTS15_TIMING), "runtime_seconds" => time() - tstart,
        "loadavg" => Dict("start" => load0, "end" => loadavg15()),
        "machine" => Dict("hostname" => gethostname(), "threads" => Threads.nthreads(), "blas_threads" => BLAS.get_num_threads(),
                          "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "E15_AFFINITY", "")))
    write_results("e15_sierpinski_scale_d$(d)_incr", out)
    return out
end

if abspath(PROGRAM_FILE) == @__FILE__
    BLAS.set_num_threads(1)
    main15_incr()
end
