# E54-lifted: the lifted-QP baseline (Mladenov, Kersting et al.: lifted linear
# and quadratic programs; Grohe et al., dimension reduction via colour
# refinement). At every sample, colour refinement runs on the coefficient graph
# of the coordinated MPC problem's QP with its CURRENT data (the condensed QP:
# variables and constraint rows as vertices, P and A as weighted edges, q, the
# bounds and the cone structure as initial colours), and the QP is restricted
# to vectors constant on the variable classes (one representative per class of
# rows and of cones). For a convex QP an equitable partition of its data is a
# fractional automorphism, so the lifted QP has the same optimum (exact). The
# partition is computed from the data at every sample, since the data change;
# our teams are computed once offline from the graph and the data classes.
#
#   BENCH_SIDE=32 BENCH_SEEDS=1,2 julia --project=env scripts/resolution/experiments/e54_lifted.jl
#   E54_MODE=merge E54_PARTDIR=<parts> julia --project=env scripts/resolution/experiments/e54_lifted.jl
#
# Per seed, E26's coherent drone/car fleet, ball limits, E54_STEPS steps:
#   team     team MPC on the quotient of the rows (E51's `rows`: MPCController, condensed, warm)
#   lifted   per sample: write the data (states, references) into the condensed
#            MPC QP over the inputs (E26's `cond` form, unmerged: construct26!),
#            read its QP (current_qp26), colour refinement of the QP data (refine54), build the
#            lifted QP, solve it (TeamMPC, MPCController's accuracy 1e-6; warm
#            started from the previous lifted solution when the partition did
#            not change), lift the first inputs. Each phase timed; `t_total`
#            is their sum, `t_no_assembly` without the QP assembly.
# Recorded: sizes (variables of the full QP, of the lifted QP; classes),
# whether the partition changed between samples, time per sample, closed-loop
# costs and the largest applied-input difference from team MPC (both exact,
# so they agree to solver accuracy); at step 0 for n <= E54_CHECKN the full
# QP solved too, to check the lifted optimum.

include(joinpath(@__DIR__, "e51_symmetric.jl"))

const MODE54 = get(ENV, "E54_MODE", "run")
const PARTDIR54 = get(ENV, "E54_PARTDIR", joinpath(ROOT26, "bench", "baselines", "results", "parts54"))
const OUT54 = get(ENV, "E54_OUT", joinpath(ROOT26, "results", "e54_lifted.json"))
const STEPS54 = parse(Int, get(ENV, "E54_STEPS", string(STEPS26)))
const CHECKN54 = parse(Int, get(ENV, "E54_CHECKN", "1024"))
const RTOL54 = 1e-9

key54(v::Float64, s::Float64) = v == 0 ? 0 : round(Int, v / (RTOL54 * s))

"""
Colour refinement of the data of a conic QP `p`: returns (vcol, rcol), the
canonical colours of its variables and of its constraint rows. Initial
colours: q_j for a variable; (kind, bounds, SOC shift, position in its cone,
cone dimension) for a row. A round recolours a variable by its colour and the
multisets of (P_jk, colour of k) over k (the diagonal included) and of
(A_ij, colour of i); a row by its colour, the multiset of (A_ij, colour of j)
and, for a cone row, the colours of its cone's rows in order. Stops when
neither count grows.
"""
function refine54(p::SM.ConicQP)
    n = length(p.q); m = size(p.A, 1)
    sP = max(maximum(abs, nonzeros(p.P); init = 0.0), 1e-300)
    sA = max(maximum(abs, nonzeros(p.A); init = 0.0), 1e-300)
    sq = max(maximum(abs, p.q; init = 0.0), 1e-300)
    fin = filter(isfinite, [p.l; p.u; p.socb])
    sb = max(maximum(abs, fin; init = 0.0), 1e-300)
    bk(v) = isfinite(v) ? key54(v, sb) : (v > 0 ? typemax(Int) : typemin(Int))
    cone = zeros(Int, m); pos = zeros(Int, m)
    for (c, B) in enumerate(p.socs), (k, i) in enumerate(B)
        cone[i] = c; pos[i] = k
    end
    vcol = canon51([key54(p.q[j], sq) for j in 1:n])
    rcol = canon51([(Int(p.kinds[i]), bk(p.l[i]), bk(p.u[i]), bk(p.socb[i]), pos[i],
                     cone[i] == 0 ? 0 : length(p.socs[cone[i]])) for i in 1:m])
    At = sparse(transpose(p.A))                       # columns of At = rows of A
    Prow, Pval = rowvals(p.P), nonzeros(p.P)
    Arow, Aval = rowvals(p.A), nonzeros(p.A)
    Atr, Atv = rowvals(At), nonzeros(At)
    while true
        nv, nr = maximum(vcol; init = 0), maximum(rcol; init = 0)
        vs = Vector{Tuple{Int,Vector{Tuple{Int,Int}},Vector{Tuple{Int,Int}}}}(undef, n)
        for j in 1:n
            a = Tuple{Int,Int}[]
            for t in nzrange(p.P, j)
                push!(a, (key54(Pval[t], sP), vcol[Prow[t]]))
            end
            b = Tuple{Int,Int}[]
            for t in nzrange(p.A, j)
                push!(b, (key54(Aval[t], sA), rcol[Arow[t]]))
            end
            vs[j] = (vcol[j], sort!(a), sort!(b))
        end
        rs = Vector{Tuple{Int,Vector{Tuple{Int,Int}},Vector{Int}}}(undef, m)
        for i in 1:m
            a = Tuple{Int,Int}[]
            for t in nzrange(At, i)
                push!(a, (key54(Atv[t], sA), vcol[Atr[t]]))
            end
            cc = cone[i] == 0 ? Int[] : [rcol[r] for r in p.socs[cone[i]]]
            rs[i] = (rcol[i], sort!(a), cc)
        end
        v2 = canon51(vs); r2 = canon51(rs)
        (maximum(v2; init = 0) == nv && maximum(r2; init = 0) == nr) && return vcol, rcol
        vcol, rcol = v2, r2
    end
end

"""
The lifted QP of `p` for the colours `(vcol, rcol)`: variables x = E xbar (E
the class indicator), objective (1/2) xbar'E'PE xbar + q'E xbar, one
representative per class of non-cone rows and per class of cones (a cone's
class: the tuple of its rows' colours), rows A E. Returns (lifted QP, E).
"""
function lift54(p::SM.ConicQP, vcol, rcol)
    n = length(p.q); k = maximum(vcol)
    E = sparse(1:n, vcol, ones(n), n, k)
    keep = Int[]; seen = Set{Int}()
    insoc = falses(size(p.A, 1))
    for B in p.socs
        insoc[B] .= true
    end
    for i in 1:size(p.A, 1)
        insoc[i] && continue
        rcol[i] in seen && continue
        push!(seen, rcol[i]); push!(keep, i)
    end
    socs = UnitRange{Int}[]; seenc = Set{Vector{Int}}()
    rows = copy(keep)
    for B in p.socs
        sig = rcol[B]
        sig in seenc && continue
        push!(seenc, sig)
        push!(socs, (length(rows)+1):(length(rows)+length(B)))
        append!(rows, B)
    end
    AE = p.A[rows, :] * E
    kinds = p.kinds[rows]
    q = SM.ConicQP(SparseMatrixCSC(transpose(E) * p.P * E), transpose(E) * p.q, AE, p.l[rows], p.u[rows];
                   c = p.c, socs = socs, socb = p.socb[rows], kinds = kinds)
    return q, E
end

objective54(p::SM.ConicQP, x) = 0.5 * dot(x, p.P * x) + dot(p.q, x) + p.c

"""
The lifted-QP closed loop. The QP is the standard condensed MPC QP over the
inputs (E26's `cond` form: the measured states and references as data, so its
data are in slot-relative form exactly where the problem's are), unmerged.
"""
function lifted_loop54(sc::Scenario26; steps::Int = STEPS54, check::Bool = false)
    F = Form26(sc, "cond"; merge = false)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; us = Vector{Vector{Vector{Float64}}}()
    st = SM.Settings()
    prev = nothing; S = nothing; xb = Float64[]; yb = Float64[]
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        r = Dict{String,Any}("step" => k)
        t0 = time_ns()
        construct26!(F, sc, x, refs, term)
        t1 = time_ns()
        p = current_qp26(F.G)
        t2 = time_ns()
        vcol, rcol = refine54(p)
        t3 = time_ns()
        pl, E = lift54(p, vcol, rcol)
        same = prev !== nothing && prev == vcol
        S = SM.setup(pl; settings = st)
        same && length(xb) == length(pl.q) && SM.warm_start!(S; x = xb, y = yb)
        t4 = time_ns()
        info = SM.solve!(S)
        t5 = time_ns()
        xb = copy(S.xsol); yb = copy(S.ysol)
        y = E * xb
        u = lift26!(F, y)
        t6 = time_ns()
        r["t_data"] = (t1 - t0) / 1e9; r["t_assemble"] = (t2 - t1) / 1e9; r["t_refine"] = (t3 - t2) / 1e9
        r["t_liftbuild"] = (t4 - t3) / 1e9; r["t_solve"] = (t5 - t4) / 1e9; r["t_lift"] = (t6 - t5) / 1e9
        r["t_total"] = (t6 - t0) / 1e9; r["t_no_assembly"] = r["t_total"] - r["t_assemble"]
        r["n_full"] = length(p.q); r["n_lifted"] = length(pl.q); r["rows_full"] = size(p.A, 1); r["rows_lifted"] = size(pl.A, 1)
        r["same_partition"] = same; r["status"] = string(info.status); r["iter"] = info.iter + info.ipm_iter
        r["J_lifted"] = objective54(p, y)
        if check && k == 0
            Sf = SM.setup(p; settings = SM.Settings(eps_abs = 1e-9, eps_rel = 1e-9, max_iter = 100_000))
            SM.solve!(Sf)
            r["J_full"] = objective54(p, Sf.xsol)
            r["lifted_rel_err"] = (r["J_lifted"] - r["J_full"]) / abs(r["J_full"])
        end
        prev = vcol
        uc, viol = clip26(sc, [copy(v) for v in u])
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, r); push!(us, uc)
        x = plant26(sc, x, uc)
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    after = rec[2:end]
    col(key) = [Float64(r[key]) for r in after]
    out = Dict{String,Any}("closed_loop_cost" => cost, "unsolved" => count(r -> r["status"] != "solved", rec),
                           "partition_changes" => count(r -> !r["same_partition"], after),
                           "n_full" => rec[1]["n_full"], "n_lifted" => sumstats26(Float64[r["n_lifted"] for r in rec]),
                           "rows_full" => rec[1]["rows_full"], "rows_lifted" => sumstats26(Float64[r["rows_lifted"] for r in rec]),
                           "steps" => rec)
    for key in ("t_data", "t_assemble", "t_refine", "t_liftbuild", "t_solve", "t_lift", "t_total", "t_no_assembly")
        out[key] = sumstats26(col(key))
    end
    haskey(rec[1], "lifted_rel_err") && (out["lifted_rel_err_step0"] = rec[1]["lifted_rel_err"])
    return out, us
end

function run54(seed::Int; side::Int = SIDE26, quiet::Bool = false, steps::Int = STEPS54)
    sc = Scenario26(side; seed = seed)
    res = Dict{String,Any}("seed" => seed, "n" => sc.n, "side" => side, "load" => loadavg26(), "steps" => steps)
    aep, _ = partitions51(sc)
    GC.gc()
    tb = @elapsed begin
        Q = Quot51(sc, aep); C = controller51(Q.fleet)
    end
    tcr = @elapsed partitions51(sc)                       # our teams' offline cost (colour refinement of the graph)
    GC.gc()
    ot, ut = loop51(sc, C, Q; steps = steps)
    ot["build_seconds"] = tb; ot["refine_seconds"] = tcr; ot["teams"] = length(Q.teams); ot["qp"] = qpsize51(C)
    res["team"] = ot
    GC.gc()
    ol, ul = lifted_loop54(sc; steps = steps, check = sc.n <= CHECKN54)
    res["lifted"] = ol
    res["input_diff_team_lifted"] = maxdiff26(ut, ul)
    res["cost_ratio_lifted_team"] = ol["closed_loop_cost"] / ot["closed_loop_cost"]
    if !quiet
        @printf("  team    n=%5d teams %5d  ms/step med %9.3f max %9.3f  (offline: refine %.3f s, build %.2f s)\n", sc.n,
                ot["teams"], ms26(ot["t_total"]["median"]), ms26(ot["t_total"]["max"]), tcr, tb)
        @printf("  lifted  n=%5d vars %d -> %.0f  ms/step med %9.3f max %9.3f  (data %.2f assemble %.2f refine %.2f build %.2f solve %.2f)  partition changes %d\n",
                sc.n, ol["n_full"], ol["n_lifted"]["median"], ms26(ol["t_total"]["median"]), ms26(ol["t_total"]["max"]),
                ms26(ol["t_data"]["median"]), ms26(ol["t_assemble"]["median"]), ms26(ol["t_refine"]["median"]),
                ms26(ol["t_liftbuild"]["median"]), ms26(ol["t_solve"]["median"]), ol["partition_changes"])
        @printf("  input diff %.1e  cost ratio %.10f%s\n", res["input_diff_team_lifted"], res["cost_ratio_lifted_team"],
                haskey(ol, "lifted_rel_err_step0") ? @sprintf("  lifted vs full QP at step 0 %.1e", ol["lifted_rel_err_step0"]) : "")
    end
    return res
end

function main54()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR54)
    run54(1; side = 4, quiet = true, steps = 3)                  # warm-up: every path
    for seed in SEEDS26
        @printf("E54 side %d seed %d\n", SIDE26, seed); flush(stdout)
        res = run54(seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "threads" => Threads.nthreads(),
                           "job" => get(ENV, "SLURM_JOB_ID", ""), "cpu" => Sys.cpu_info()[1].model, "cone" => string(CONE26),
                           "fleet" => string(FLEET_DC), "layout" => string(LAYOUT_DC), "disc" => get(ENV, "BENCH_DISC", "zoh"))
        path = joinpath(PARTDIR54, @sprintf("e54_n%d_seed%d.json", SIDE26^2, seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

function merge54()
    byn = Dict{Int,Vector{Any}}()
    for f in readdir(PARTDIR54; join = true)
        endswith(f, ".json") || continue
        p = JSON.parsefile(f)
        push!(get!(byn, p["n"], Any[]), p)
    end
    out = Dict{String,Any}("experiment" => "E54 lifted QP (per-sample colour refinement of the QP data) vs team MPC (teams offline)",
                           "period_ms" => 1e3 * DT26, "sizes" => Dict{String,Any}())
    for (n, parts) in sort!(collect(byn); by = first)
        L = [p["lifted"] for p in parts]; T = [p["team"] for p in parts]
        d = Dict{String,Any}("seeds" => [p["seed"] for p in parts], "steps" => parts[1]["steps"],
                             "team_ms_med" => 1e3 * median([t["t_total"]["median"] for t in T]),
                             "team_ms_max" => 1e3 * maximum([t["t_total"]["max"] for t in T]),
                             "team_refine_s" => median([t["refine_seconds"] for t in T]), "teams" => T[1]["teams"],
                             "lifted_ms_med" => 1e3 * median([l["t_total"]["median"] for l in L]),
                             "lifted_ms_max" => 1e3 * maximum([l["t_total"]["max"] for l in L]),
                             "lifted_no_assembly_ms_med" => 1e3 * median([l["t_no_assembly"]["median"] for l in L]),
                             "lifted_refine_ms_med" => 1e3 * median([l["t_refine"]["median"] for l in L]),
                             "lifted_solve_ms_med" => 1e3 * median([l["t_solve"]["median"] for l in L]),
                             "n_full" => L[1]["n_full"], "n_lifted_med" => median([l["n_lifted"]["median"] for l in L]),
                             "partition_changes" => sum(l["partition_changes"] for l in L),
                             "unsolved" => sum(l["unsolved"] for l in L),
                             "input_diff_max" => maximum(p["input_diff_team_lifted"] for p in parts),
                             "cost_ratio_maxdev" => maximum(abs(p["cost_ratio_lifted_team"] - 1) for p in parts))
        e = [l["lifted_rel_err_step0"] for l in L if haskey(l, "lifted_rel_err_step0")]
        isempty(e) || (d["lifted_vs_full_step0_maxabs"] = maximum(abs, e))
        d["speedup_team_vs_lifted"] = d["lifted_ms_med"] / d["team_ms_med"]
        out["sizes"][string(n)] = d
    end
    open(io -> JSON.print(io, out, 1), OUT54, "w")
    println("wrote $OUT54")
    JSON.print(stdout, out, 1)
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE54 == "merge" ? merge54() : main54()
end
