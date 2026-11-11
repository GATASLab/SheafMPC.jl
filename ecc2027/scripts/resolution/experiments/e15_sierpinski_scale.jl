# E15-sierpinski-scale: closed-loop hard MPC on Sierpinski fleets of 3^d ground
# vehicles (d = 3 .. 7: 27 .. 2187), at every level of the Sierpinski hierarchy
# of teams, with a keep-out disc above the apex; speedups of the reduced
# programs over the time-expanded fine program.
#
#   BENCH_DEPTH=5 julia --project=env scripts/resolution/experiments/e15_sierpinski_scale.jl
#
# Levels l = 0 .. d: clusters are the Sierpinski triangles of 3^l vehicles
# (l = 0 agents, l = d the fleet), each fully condensed in time. The reduced
# program at level l is built directly as a fleet of clusters (manuscript
# Proposition prop:clusteragent): the members of a cluster share their
# dynamics and start in formation with a common velocity, so the hard formation
# edges inside the cluster make every member apply the cluster's input and keep
# its slot, x_i = x_c + E Delta_i, at every step of the closed loop. The
# decision variable is one input sequence per cluster; costs are the members'
# costs, the soft formation edges between clusters couple two clusters, every
# cluster has one input cone per instant, and the keep-out half-spaces of its
# members are rewritten in its input. The Hessian is block sparse, so the
# program scales to thousands of vehicles.
#
# Checks: at d = 3 the closed loop of every level reproduces E14 (the library's
# reduction and solve) to round-off; at every depth the agents level (fully
# condensed, k = n) matches the time-expanded fine program solved by the
# library at the timed steps. Timings per step: assembly and solve of the
# reduced program at every level, and the library's time-expanded fine program
# (assembly and solve) at TIMED15 steps. Writes results/e15_sierpinski_scale_d<d>.json.

include(joinpath(@__DIR__, "e6_refine.jl"))

const DEPTH15 = parse(Int, get(ENV, "BENCH_DEPTH", "4"))
const STEPS15 = parse(Int, get(ENV, "BENCH_STEPS", "30"))
const H15 = 10
const DT15 = 0.2
const SPEED15 = 1.0
const MARGIN15 = 0.3
const DIRS15 = [[0.0, 1.0], [-cos(pi / 6), -sin(pi / 6)], [cos(pi / 6), -sin(pi / 6)]]
const OPTS15 = SolverOptions(tol = 1e-12, infeas_tol = 1e-12, ktratio = 1e-12)
const OPTS15_TIMING = SolverOptions(tol = 1e-8, infeas_tol = 1e-8, ktratio = 1e-6, polish = false)
const TIMED15 = [5, 15, 25]                          # timed steps (after warm-up); min of REPS15 repeats
const REPS15 = 3

"Circumradius of the triangles at level l = 1 .. d (level 1: three vehicles); E14's radii at d = 3."
radius15(l) = l == 1 ? 0.45 : l == 2 ? 1.3 : 3.0 * 2.3^(l - 3)

"""Layout, the level labels (labels[l+1][i] = triangle of 3^l containing i) and the formation edges."""
function sierpinski(d::Int)
    n = 3^d
    layout = Vector{Vector{Float64}}(undef, n)
    for i in 1:n
        digits_ = reverse(digits(i - 1; base = 3, pad = d))       # most significant digit = top level
        layout[i] = sum(radius15(d - k + 1) .* DIRS15[digits_[k]+1] for k in 1:d)
    end
    labels = [[div(i - 1, 3^l) + 1 for i in 1:n] for l in 0:d]
    edges = Tuple{Int,Int}[]
    near(A, B) = (p = argmin(p -> norm(layout[p[1]] - layout[p[2]]), [(a, b) for a in A for b in B]); (min(p...), max(p...)))
    for l in 1:d, c in 1:3^(d-l)
        subs = [[i for i in 1:n if labels[l+1][i] == c && labels[l][i] == s] for s in unique(labels[l][i] for i in 1:n if labels[l+1][i] == c)]
        for (a, b) in ((1, 2), (1, 3), (2, 3))
            push!(edges, near(subs[a], subs[b]))
        end
    end
    return layout, labels, edges
end

"""The explicit data at world time t0 (the E14 construction for any layout)."""
function spec15(layout, edges; xhat, t0, nominal, ob)
    n, H = length(layout), H15
    hv = fill(DT15, H)
    agents = [rover_agent(hv) for _ in 1:n]
    tau = t0 .+ DT15 .* (0:H)
    ne = length(edges)
    offsets = zeros(2, n, H + 1)
    for i in 1:n, t in 0:H
        offsets[:, i, t+1] = layout[i]
    end
    ftarget = zeros(2, ne, H)
    for (k, (i, j)) in enumerate(edges), t in 1:H
        ftarget[:, k, t] = layout[j] - layout[i]
    end
    ref = [reduce(hcat, [layout[i] .+ [SPEED15 * tt, 0.0] for tt in tau]) for i in 1:n]
    vref = [[SPEED15, 0.0] for _ in 1:n]
    hs = [Tuple{Int,Vector{Float64},Float64}[] for _ in 1:n]
    if nominal !== nothing
        for i in 1:n, t in 1:H
            dd = nominal[i][:, t+1] - ob.center
            norm(dd) <= ob.radius + MARGIN15 || continue
            a = norm(dd) > 1e-9 ? dd / norm(dd) : [0.0, 1.0]
            push!(hs[i], (t, a, dot(a, ob.center) + ob.radius))
        end
    end
    return MPCSpec(n, H, hv, agents, edges, trues(ne, H), ftarget, ones(ne, H), [copy(x) for x in xhat], ref, vref,
                   hs, :hard, 10.0, :omit, offsets, [ob], Dict{String,Any}("experiment" => "E15", "t0" => t0))
end

# ---------------------------------------------------------------------------
# The reduced program of a clustering (cluster = agent), block sparse
# ---------------------------------------------------------------------------

struct Reduced15
    H::SparseMatrixCSC{Float64,Int}; g::Vector{Float64}; c::Float64
    A::SparseMatrixCSC{Float64,Int}; b::Vector{Float64}; cones::Vector{ConeBlock}
    k::Int; rep::Vector{Int}; delta::Vector{Vector{Float64}}; label::Vector{Int}; xc::Vector{Vector{Float64}}
end

function reduced15(spec::MPCSpec, label::Vector{Int}, cond)
    n, H = spec.n, spec.H
    ag = spec.agents[1]; nu = ag.nu; m = nu * H
    Phi, Gam, gg = cond
    k = maximum(label)
    rep = [findfirst(==(c), label) for c in 1:k]
    delta = [spec.offsets[:, i, 1] - spec.offsets[:, rep[label[i]], 1] for i in 1:n]
    xc = [spec.xhat[rep[c]] for c in 1:k]
    for i in 1:n                                   # members in formation with the cluster's velocity
        norm(spec.xhat[i] - (xc[label[i]] + ag.E * delta[i]), Inf) <= 1e-8 ||
            error("member $i is not in formation with its cluster")
    end
    blocks = Dict{Tuple{Int,Int},Matrix{Float64}}()
    addb!(a, b, M) = (B = get!(() -> zeros(m, m), blocks, (a, b)); B .+= M)
    g = zeros(k * m); cz = 0.0
    cols(c) = ((c-1)*m+1):(c*m)
    Sv = zeros(length(ag.vel), ag.nx)
    for (q, idx) in enumerate(ag.vel)
        Sv[q, idx] = 1.0
    end
    CrG = [ag.Cr * Gam[t+1] for t in 0:H]; CG = [ag.C * Gam[t+1] for t in 0:H]
    for i in 1:n
        c = label[i]
        for t in 0:H
            W = t < H ? ag.Q : ag.Qf
            M = CrG[t+1]; m0 = ag.Cr * (Phi[t+1] * xc[c] + gg[t+1] + ag.E * delta[i]) - spec.ref[i][:, t+1]
            addb!(c, c, M' * W * M); g[cols(c)] .+= M' * (W * m0); cz += 0.5 * dot(m0, W * m0)
        end
        M = Sv * Gam[H+1]; m0 = Sv * (Phi[H+1] * xc[c] + gg[H+1]) - spec.vref[i]
        addb!(c, c, ag.qv * (M' * M)); g[cols(c)] .+= ag.qv * (M' * m0); cz += 0.5 * ag.qv * dot(m0, m0)
        addb!(c, c, kron(Matrix{Float64}(I, H, H), ag.R))
    end
    for (e, (i, j)) in enumerate(spec.gedges), t in 1:H
        ci, cj = label[i], label[j]
        w = spec.fweight[e, t]
        m0 = ag.C * (Phi[t+1] * (xc[cj] - xc[ci]) + ag.E * (delta[j] - delta[i])) - spec.ftarget[:, e, t]
        if ci == cj
            cz += 0.5 * w * dot(m0, m0)            # zero for exact targets
            continue
        end
        M = CG[t+1]; MM = w * (M' * M)
        addb!(ci, ci, MM); addb!(cj, cj, MM); addb!(ci, cj, -MM); addb!(cj, ci, -MM)
        g[cols(cj)] .+= w * (M' * m0); g[cols(ci)] .-= w * (M' * m0); cz += 0.5 * w * dot(m0, m0)
    end
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for ((a, b), B) in blocks, jj in 1:m, ii in 1:m
        B[ii, jj] != 0 && (push!(I_, (a-1)*m + ii); push!(J_, (b-1)*m + jj); push!(V_, B[ii, jj]))
    end
    Hs = sparse(I_, J_, V_, k * m, k * m); Hs = (Hs + Hs') / 2
    # constraints: one input cone per cluster and instant; the members' half-spaces
    AI = Int[]; AJ = Int[]; AV = Float64[]; b = Float64[]; cones = ConeBlock[]
    row = 0
    for c in 1:k, t in 0:(H-1)
        push!(b, ag.abar); append!(b, zeros(nu))
        for q in 1:nu
            push!(AI, row + 1 + q); push!(AJ, (c-1)*m + t*nu + q); push!(AV, -1.0)
        end
        row += 1 + nu; push!(cones, soc_cone(1 + nu))
    end
    for i in 1:n, (t, a, beta) in spec.halfspaces[i]
        c = label[i]; r = a' * ag.C
        coeff = -(r * Gam[t+1])
        for q in 1:m
            coeff[q] != 0 && (push!(AI, row + 1); push!(AJ, (c-1)*m + q); push!(AV, coeff[q]))
        end
        push!(b, dot(r, Phi[t+1] * xc[c] + gg[t+1] + ag.E * delta[i]) - beta)
        row += 1; push!(cones, nonneg_cone(1))
    end
    A = sparse(AI, AJ, AV, row, k * m)
    return Reduced15(Hs, g, cz, A, b, cones, k, rep, delta, label, xc)
end

"Planned positions (2 x (H+1)) of every vehicle and the first input of every vehicle."
function unpack15(R::Reduced15, U, cond, spec)
    ag = spec.agents[1]; m = ag.nu * spec.H
    Phi, Gam, gg = cond
    uc = [U[((c-1)*m+1):(c*m)] for c in 1:R.k]
    pos = [reduce(hcat, [ag.C * (Phi[t+1] * R.xc[R.label[i]] + Gam[t+1] * uc[R.label[i]] + gg[t+1]) + R.delta[i]
                         for t in 0:spec.H]) for i in 1:spec.n]
    u0 = [uc[R.label[i]][1:ag.nu] for i in 1:spec.n]
    return pos, u0, uc
end

function run_level15(layout, edges, label, ob; steps = STEPS15, time_fine = false)
    n = length(layout)
    ag0 = rover_agent(fill(DT15, H15)); cond = condensing_matrices(ag0, H15)
    x = [[layout[i]; SPEED15; 0.0] for i in 1:n]
    # the first nominal: the obstacle-free optimum of the agents level (= the fine program)
    spec0 = spec15(layout, edges; xhat = x, t0 = 0.0, nominal = nothing, ob = ob)
    R0 = reduced15(spec0, collect(1:n), cond)
    s0 = solve_qp(R0.H, R0.g, R0.c, R0.A, R0.b, R0.cones; opts = OPTS15)
    nom = unpack15(R0, s0.x, cond, spec0)[1]
    rec = Dict{String,Any}[]; cost = 0.0
    for kstep in 0:(steps-1)
        t0 = kstep * DT15
        spec = spec15(layout, edges; xhat = x, t0 = t0, nominal = nom, ob = ob)
        ta = @elapsed R = reduced15(spec, label, cond)
        ts = @elapsed sol = solve_qp(R.H, R.g, R.c, R.A, R.b, R.cones; opts = OPTS15)
        sol.status in (:optimal, :almost_optimal) || error("level $(maximum(label)) clusters, step $kstep: $(sol.status)")
        tt = @elapsed soltime = solve_qp(R.H, R.g, R.c, R.A, R.b, R.cones; opts = OPTS15_TIMING)
        if kstep in TIMED15
            tt = minimum(@elapsed(solve_qp(R.H, R.g, R.c, R.A, R.b, R.cones; opts = OPTS15_TIMING)) for _ in 1:REPS15)
        end
        pos, u0, _ = unpack15(R, sol.x, cond, spec)
        r = Dict{String,Any}("step" => kstep, "positions" => [xi[1:2] for xi in x], "stage_cost" => stage_cost(spec, x, u0),
            "vars" => size(R.H, 1), "rows" => size(R.A, 1), "nnz_H" => nnz(R.H), "t_assemble" => ta, "t_solve" => ts,
            "t_solve_timing" => tt, "timed" => kstep in TIMED15, "iters_timing" => soltime.iterations,
            "clearance" => minimum(norm(xi[1:2] - ob.center) - ob.radius for xi in x),
            "input_margin" => minimum(ag0.abar - norm(u) for u in u0), "halfspaces" => sum(length(h) for h in spec.halfspaces))
        if time_fine && kstep in TIMED15
            tb = @elapsed model = build_model(spec)
            sf = solve_direct(model.program; opts = OPTS15_TIMING)
            tf = minimum(@elapsed(solve_direct(model.program; opts = OPTS15_TIMING)) for _ in 1:REPS15)
            sfx = solve_direct(model.program; opts = OPTS15)
            fpos = planned_positions(model, sfx.x)
            r["fine"] = Dict{String,Any}("vars" => c0dim(model.program), "t_build" => tb, "t_solve_timing" => tf,
                "iters_timing" => sf.iterations, "status" => string(sfx.status),
                "plan_vs_reduced" => maximum(maximum(abs.(fpos[i] - pos[i])) for i in 1:n))
        end
        push!(rec, r)
        cost += r["stage_cost"]
        nom = shifted_nominal(pos)
        x = plant_step(spec, x, u0)
    end
    specK = spec15(layout, edges; xhat = x, t0 = steps * DT15, nominal = nom, ob = ob)
    cost += stage_cost(specK, x, nothing)
    return Dict{String,Any}("clusters" => maximum(label), "cluster_size" => n ÷ maximum(label), "steps" => rec,
        "final_positions" => [xi[1:2] for xi in x], "closed_loop_cost" => cost,
        "final_clearance" => minimum(norm(xi[1:2] - ob.center) - ob.radius for xi in x))
end

function main15(; d = DEPTH15)
    tstart = time()
    layout, labels, edges = sierpinski(d)
    n = length(layout)
    apex = argmax(p -> p[2], layout)
    ob = ObstacleT(([apex[1] + 4.0, apex[2] + 0.2], 1.2, :all))
    levels = Dict{String,Any}[]
    for l in 0:d
        t = @elapsed lv = run_level15(layout, edges, labels[l+1], ob; time_fine = (l == 0))
        lv["level"] = l; lv["wall_seconds"] = t
        push!(levels, lv)
        s = lv["steps"]
        @printf("d=%d n=%d level %d (%4d clusters of %4d): cost %.3f  vars %6d  solve %.3f s/step  clearance %.1e  (%.0f s)\n",
                d, n, l, lv["clusters"], lv["cluster_size"], lv["closed_loop_cost"], s[1]["vars"],
                sum(r["t_solve_timing"] for r in s) / length(s), min(minimum(r["clearance"] for r in s), lv["final_clearance"]), t)
    end
    fine = [r["fine"] for r in levels[1]["steps"] if haskey(r, "fine")]
    out = Dict{String,Any}("experiment" => "E15-sierpinski-scale", "depth" => d, "n" => n, "steps" => STEPS15, "H" => H15,
        "h" => DT15, "speed" => SPEED15, "layout" => layout, "labels" => labels, "edges" => edges,
        "obstacle" => Dict("center" => ob.center, "radius" => ob.radius), "levels" => levels, "fine" => fine,
        "meta" => run_metadata(OPTS15), "runtime_seconds" => time() - tstart,
        "machine" => Dict("hostname" => gethostname(), "threads" => Threads.nthreads(), "blas_threads" => BLAS.get_num_threads(),
                          "cpu" => Sys.cpu_info()[1].model))
    write_results("e15_sierpinski_scale_d$d", out)
    return out
end

if abspath(PROGRAM_FILE) == @__FILE__
    BLAS.set_num_threads(1)
    main15()
end
