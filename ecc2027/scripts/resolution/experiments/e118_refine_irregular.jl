# E118: Algorithm 1 (certified refinement) ENFORCED on the irregular fleets of E106 (largest connected part of 4096
# random slots, ~4069 vehicles, one team per region = 339 fixed teams of ~12 neighbouring same-type vehicles,
# h = 0.2 s, H = 10, ball limits; scenario63, E106's references and start).
#
# E106 computes the certificate at every step but never acts on it. Here, at every sample, after the team solve
# and the certificate (least certificate per team, E117's etateams117: NNLS over the active ball normals, D = H_0,
# H_S = own Hessians + edges inside teams, block diagonal by team), while eta_min > eps W + delta the teams of
# largest eta_c are split in two by 2-means of their members' steps d = -H_S,c^{-1}(g_c + N c*) (own-Hessian
# metric, E103b's split103b), the quotient program is rebuilt (Quot51, controller51, cold), re-solved and
# re-certified. Teams only split, never merge. W = V_N(u_hat), the value of the projected team plan at the measured
# state (as E112). delta = E118_DELTA_REL * W_0, W_0 the value of the initial teams' plan at x(0) (as E112).
# Per round the teams are split in order of eta_c until the split teams cover eta - (eps W + delta)/2 (E112's rule;
# the paper's Algorithm 1 splits one team per round, which would need one re-solve per split).
#
# Step 0 is offline (untimed, as E106; the paper's "split at x(0), offline"). Steps 1..: the step time is
# team solve + certificate (gradient and per-team NNLS) + all split rounds (2-means, block factors of the new teams,
# quotient rebuild, cold re-solve, re-certificate). As in E106 (kktE71 timed, q given) the linear data q of the
# condensed program at the measured state is NOT in the step time (recorded as t_q; met_frac_with_q counts it).
# E106's overrun rule (shift): on a step over the 200 ms period the previously
# applied plan, shifted one sample, is applied (the refined teams are kept for the next sample).
# Untimed evaluation per step: the tight central solve (Ref71, 1e-9) for the true gap Jp - J*.
#
# Arms per seed (one core, sequential): coord (converged centralized, the reference cost, E106's coord71),
# fix (eps = Inf: the same loop without splits, a reproduction of E106's team_resp_quarter), ref_<eps>; each team arm
# also as <arm>_nofb, without the overrun rule (the cost of the teams alone, independent of the wall time).
#
#   E118_SEEDS=1 E118_PARTDIR=<dir> julia --project=env scripts/resolution/experiments/e118_refine_irregular.jl
#   E118_N=64 E118_STEPS=2 E118_WARMUP=0 ...      (smoke test)
#   E118_MODE=merge E118_PARTDIR=<dir> E118_OUT=results/e118_refine_irregular.json julia ... e118_refine_irregular.jl

const MODE118 = get(ENV, "E118_MODE", "run")
using Printf, JSON, Statistics       # macros of the run block must exist when it is parsed
for (k, v) in ("BENCH_INSTANCE" => "natural", "BENCH_FLEET" => "dronecar", "BENCH_DISC" => "zoh",
               "E102_FALLBACK" => "shift", "E71_FALLBACK" => "shift", "E71_CERT_IN_STEP" => "1")
    haskey(ENV, k) || (ENV[k] = v)
end
const ROOT118 = joinpath(@__DIR__, "..", "..", "..")
const PARTDIR118 = get(ENV, "E118_PARTDIR", joinpath(ROOT118, "results", "parts118"))
const OUT118 = get(ENV, "E118_OUT", joinpath(ROOT118, "results", "e118_refine_irregular.json"))

if MODE118 == "run"
include(joinpath(@__DIR__, "e102_irregular4096.jl"))         # e71_budget.jl, e63_time.jl, squads_dc.jl, E51/E52
let src = read(joinpath(@__DIR__, "e30_bounds_dc.jl"), String)   # nnls30 only
    a = first(findfirst("function nnls30", src)); b = first(findnext("\nend\n", src, a)) + 4
    include_string(Main, src[a:b], joinpath(@__DIR__, "e30_bounds_dc.jl"))
end
import SHA
@assert ENV["BENCH_INSTANCE"] == "natural" && ENV["BENCH_FLEET"] == "dronecar" && ENV["BENCH_DISC"] == "zoh"
@assert FALLBACK71 == "shift"

const N118 = parse(Int, get(ENV, "E118_N", "4096"))
const SEEDS118 = parse.(Int, split(get(ENV, "E118_SEEDS", "1"), ":"))      # ':' separated (sbatch --export)
const STEPS118 = parse(Int, get(ENV, "E118_STEPS", "30"))
const EPS118 = parse.(Float64, split(get(ENV, "E118_EPS", "0.03:0.01"), ":"))
const ARMS118 = split(get(ENV, "E118_ARMS", "coord:fix:ref"), ":")
const DELTA_REL118 = parse(Float64, get(ENV, "E118_DELTA_REL", "1e-4"))
const ROUNDS118 = parse(Int, get(ENV, "E118_ROUNDS", "40"))
const TOL118 = 1e-6
# overrun rules: "" = E106's shift rule (timed), "_nofb" = no fallback (every plan applied when it finishes: isolates
# the cost effect of the teams from the timing)
const FBMODES118 = [m == "shift" ? "" : "_nofb" for m in split(get(ENV, "E118_FB", "shift:none"), ":")]

"""Team structure kept incrementally: members, columns, dense lower factor of H_S,c, balls (block, local cols)."""
mutable struct Teams118
    mem::Vector{Vector{Int}}
    cols::Vector{Vector{Int}}
    L::Vector{Matrix{Float64}}
    balls::Vector{Vector{Tuple{Int,UnitRange{Int}}}}
    lab::Vector{Int}
end

vrng118(E, i) = E.off[i]+1:E.off[i+1]

"""Vehicle -> blocks (ball indices) and vehicle -> edge terms."""
function index118(E::Ev71, n)
    vb = [Int[] for _ in 1:n]
    for (k, b) in enumerate(E.blocks)
        i = searchsortedlast(E.off, first(b) - 1); push!(vb[i], k)
    end
    adj = [Int[] for _ in 1:n]
    for (e, (i, j, _, _, _)) in enumerate(E.edge_terms)
        push!(adj[i], e); push!(adj[j], e)
    end
    return (vb = vb, adj = adj)
end

"""The block of H_S of a team m (own Hessians, edges inside m), its columns, factor and balls."""
function block118(E::Ev71, ix, m, lab)
    loc = Dict{Int,UnitRange{Int}}(); o = 0
    for i in m
        d = E.off[i+1] - E.off[i]; loc[i] = o+1:o+d; o += d
    end
    B = zeros(o, o)
    for i in m
        B[loc[i], loc[i]] .+= E.H0[i]
    end
    c = lab[m[1]]
    for i in m, e in ix.adj[i]
        a, b, Hii, Hij, Hjj = E.edge_terms[e]
        a == i || continue                                   # each edge once (from its first end)
        lab[b] == c || continue
        B[loc[a], loc[a]] .+= Hii; B[loc[b], loc[b]] .+= Hjj
        B[loc[a], loc[b]] .+= Hij; B[loc[b], loc[a]] .+= Hij'
    end
    B = (B + B') / 2
    cols = reduce(vcat, [collect(vrng118(E, i)) for i in m])
    balls = Tuple{Int,UnitRange{Int}}[]
    for i in m, k in ix.vb[i]
        b = E.blocks[k]; push!(balls, (k, (first(b) - E.off[i]) - 1 + first(loc[i]):(last(b) - E.off[i]) - 1 + first(loc[i])))
    end
    return cols, cholesky(Symmetric(B)).L, balls, B
end

function teams118(E::Ev71, ix, lab)
    K = maximum(lab); mem = [findall(==(c), lab) for c in 1:K]
    T = Teams118(mem, Vector{Vector{Int}}(undef, K), Vector{Matrix{Float64}}(undef, K),
                 Vector{Vector{Tuple{Int,UnitRange{Int}}}}(undef, K), copy(lab))
    for c in 1:K
        T.cols[c], T.L[c], T.balls[c], _ = block118(E, ix, mem[c], lab)
    end
    return T
end

"""Least certificate per team at the feasible u (E117's etateams117) and y_c = L_c^{-1}(g_c + N c) (the step
d_c = -H_S,c^{-1}(g_c + N c) = -L_c' \\ y_c is formed only for the teams that are split, in the split time)."""
function cert118(E::Ev71, T::Teams118, g, u)
    K = length(T.mem); eta = zeros(K); yv = Vector{Vector{Float64}}(undef, K); nact = 0
    for p in 1:K
        cols = T.cols[p]; Lc = T.L[p]; y0 = Lc \ g[cols]
        best = 0.5 * dot(y0, y0); yb = y0
        act = [(k, rg) for (k, rg) in T.balls[p] if norm(view(u, E.blocks[k])) >= (1 - TOL118) * E.um[k]]
        na = length(act); nact += na
        if na > 0
            Nm = zeros(length(cols), na); slack = zeros(na); cr = zeros(na)
            for (a, (k, rg)) in enumerate(act)
                b = E.blocks[k]; nu = norm(view(u, b)); w = u[b] ./ nu
                Nm[rg, a] .= w; slack[a] = max(E.um[k] - nu, 0.0); cr[a] = max(0.0, -dot(view(g, b), w))
            end
            Y = Lc \ Nm
            for cc in (max.(nnls30(Y' * Y, -(Y' * y0) .- slack), 0.0), cr)
                y = y0 .+ Y * cc; v = 0.5 * dot(y, y) + dot(cc, slack)
                v < best && (best = v; yb = y)
            end
        end
        eta[p] = best; yv[p] = yb
    end
    return eta, yv, nact
end

"""Split teams of largest eta_c (2-means of the members' steps in the own-Hessian metric) until they cover `excess`."""
function split118!(T::Teams118, E::Ev71, ix, Uc, eta, yv, excess, rng)
    cov = 0.0; ns = 0; K0 = length(T.mem)
    for c in sortperm(eta; rev = true)
        (cov >= excess || eta[c] <= 0) && break
        m = T.mem[c]; length(m) < 2 && continue
        dc = -(T.L[c]' \ yv[c]); o = 0; rows = Vector{Vector{Float64}}(undef, length(m))
        for (a, i) in enumerate(m)
            w = E.off[i+1] - E.off[i]; rows[a] = Uc[i] * dc[o+1:o+w]; o += w
        end
        X = Matrix(reduce(vcat, (r' for r in rows)))
        a, _ = kmeans79_(X, 2, rng)
        (all(==(1), a) || all(==(2), a)) && continue
        m1 = m[a .== 1]; m2 = m[a .== 2]
        nc = length(T.mem) + 1
        T.lab[m2] .= nc
        T.mem[c] = m1; push!(T.mem, m2)
        T.cols[c], T.L[c], T.balls[c], _ = block118(E, ix, m1, T.lab)
        cl, Ll, bl, _ = block118(E, ix, m2, T.lab)
        push!(T.cols, cl); push!(T.L, Ll); push!(T.balls, bl)
        cov += eta[c]; ns += 1
    end
    return ns
end

function teamsolve118(Q, C, sc, x, refs, term)
    xq, rq, tq = teamdata51(Q, sc, x, refs, term)
    info = SM.step!(C, xq, rq; terminal = tq)
    Uq = SM.trajectories(C.fp, SM.plan(C))[2]
    U = [copy(Uq[Q.team[i]]) for i in 1:sc.n]; u = [copy(info.u[Q.team[i]]) for i in 1:sc.n]
    return U, u, string(info.status)
end

"""One closed loop of team MPC from the regions: eps = Inf (fixed teams) or Algorithm 1 with (eps, delta_rel)."""
function arm118(sc, E, ix, Uc, Rf, lab0, Jref; eps::Float64, steps, seed, fb::Bool = true)
    GC.gc(); rng = Xoshiro(1181 + seed)
    refine = isfinite(eps)
    T = teams118(E, ix, lab0)
    Q = Quot51(sc, T.lab); C = controller51(Q.fleet)
    fl = sc.fleet
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; Uapp = nothing; delta = NaN; W0 = NaN
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        teams_in = length(T.mem)
        t0 = time_ns()
        U, u, status = teamsolve118(Q, C, sc, x, refs, term)
        t1 = time_ns()
        tq0 = time_ns(); q, c = qc71(fl, E.off, x, refs, term); tq = (time_ns() - tq0) / 1e9
        up = projE71!(stackE71(E, U), E); g = E.H * up .+ q
        eta, yv, nact = cert118(E, T, g, up); W = JE71(E, q, c, up)
        t2 = time_ns()
        if k == 0
            W0 = W; delta = DELTA_REL118 * abs(W0)
        end
        eta0_first = sum(eta); W_first = W
        tsplit = 0.0; ns = 0; rounds = 0; stalled = false
        if refine
            while sum(eta) > eps * abs(W) + delta
                rounds >= ROUNDS118 && (stalled = true; break)
                ts0 = time_ns()
                s = split118!(T, E, ix, Uc, eta, yv, sum(eta) - (eps * abs(W) + delta) / 2, rng)
                if s == 0
                    tsplit += (time_ns() - ts0) / 1e9; stalled = true; break
                end
                Q = Quot51(sc, T.lab); C = controller51(Q.fleet)
                U, u, status = teamsolve118(Q, C, sc, x, refs, term)
                up = projE71!(stackE71(E, U), E); g = E.H * up .+ q
                eta, yv, nact = cert118(E, T, g, up); W = JE71(E, q, c, up)
                tsplit += (time_ns() - ts0) / 1e9
                ns += s; rounds += 1
            end
        end
        tsolve = (t1 - t0) / 1e9; tcert = (t2 - t1) / 1e9 - tq       # q at the measured state untimed, as E106
        tt = tsolve + tcert + tsplit
        # evaluation (untimed): the tight central solve at x
        Ur, _ = refU71!(Rf, sc, x, refs, term)
        ur = projE71!(stackE71(E, Ur), E); Js = JE71(E, q, c, ur)
        etas = sum(eta); gap = W - Js
        fallback = fb && k > 0 && tt > PERIOD71 && Uapp !== nothing
        if fallback
            Uapp = [hcat(Ui[:, 2:end], Ui[:, end]) for Ui in Uapp]; u = [copy(Ui[:, 1]) for Ui in Uapp]
        else
            Uapp = [copy(Ui) for Ui in U]
        end
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "teams_in" => teams_in, "teams" => length(T.mem), "splits" => ns, "rounds" => rounds,
            "stalled" => stalled, "t_solve" => tsolve, "t_cert" => tcert, "t_split" => tsplit, "t_q" => tq, "t_total" => tt, "met_with_q" => tt + tq <= PERIOD71, "met" => tt <= PERIOD71,
            "fallback" => fallback, "eta" => etas, "W" => W, "Jstar" => Js, "gap" => gap, "eta_first" => eta0_first, "W_first" => W_first,
            "active_balls" => nact, "status" => status, "viol" => viol,
            "certified" => refine ? etas <= eps * abs(W) + delta : nothing))
        @printf("  eps %-6g step %2d teams %4d -> %4d splits %3d rounds %2d ms solve %6.1f cert %6.1f split %7.1f tot %7.1f fb %d eta/W %.2e gap/J* %.2e eta/gap %.2f\n",
                eps, k, teams_in, length(T.mem), ns, rounds, 1e3 * tsolve, 1e3 * tcert, 1e3 * tsplit, 1e3 * tt, fallback,
                etas / abs(W), gap / abs(Js), etas / gap)
        flush(stdout)
        x = plant26(sc, x, uc)
        GC.gc()
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(f) = [Float64(r[f]) for r in a]
    tolg(r) = 1e-8 * abs(r["Jstar"]) + 1e-12
    return Dict{String,Any}("eps" => eps, "fallback_rule" => fb ? "shift" : "none", "delta" => delta, "delta_rel" => DELTA_REL118, "W0" => W0,
        "closed_loop_cost" => cost, "cost_ratio" => cost / Jref,
        "teams_start" => maximum(lab0), "teams_after0" => rec[1]["teams"], "teams_final" => rec[end]["teams"],
        "splits_total" => sum(r["splits"] for r in rec), "splits_step0" => rec[1]["splits"],
        "splits_after0" => sum(r["splits"] for r in a; init = 0),
        "split_samples" => [r["step"] for r in rec if r["splits"] > 0],
        "stalled" => count(r -> r["stalled"], rec), "uncertified" => refine ? count(r -> !r["certified"], rec) : nothing,
        "cert_viol" => count(r -> r["gap"] > r["eta"] + tolg(r), rec),
        "t_total" => st71(col("t_total")), "t_solve" => st71(col("t_solve")), "t_cert" => st71(col("t_cert")), "t_q" => st71(col("t_q")), "met_frac_with_q" => count(r -> r["met_with_q"], a) / length(a),
        "t_split_when" => st71([r["t_split"] for r in a if r["splits"] > 0]), "t_total0" => rec[1]["t_total"], "t_split0" => rec[1]["t_split"],
        "met_frac" => count(r -> r["met"], a) / length(a), "fallback_frac" => count(r -> r["fallback"], a) / length(a),
        "eta_rel0" => rec[1]["eta"] / abs(rec[1]["Jstar"]), "gap_rel0" => rec[1]["gap"] / abs(rec[1]["Jstar"]),
        "eta_over_gap0" => rec[1]["eta"] / rec[1]["gap"],
        "eta_first_rel0" => rec[1]["eta_first"] / abs(rec[1]["Jstar"]),
        "gap_rel" => st71([r["gap"] / abs(r["Jstar"]) for r in rec]), "eta_rel" => st71([r["eta"] / abs(r["Jstar"]) for r in rec]),
        "eta_over_gap" => st71([r["eta"] / r["gap"] for r in rec if r["gap"] > 1e-9 * abs(r["Jstar"])]),
        "viol" => st71(col("viol")), "steps" => rec)
end

function meta118()
    f = @__FILE__
    return Dict{String,Any}("host" => gethostname(), "job" => get(ENV, "SLURM_JOB_ID", ""), "partition" => get(ENV, "SLURM_JOB_PARTITION", ""),
        "julia" => string(VERSION), "cpu" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(),
        "affinity" => get(ENV, "E118_AFFINITY", ""), "exclusive" => get(ENV, "E118_EXCLUSIVE", "0") == "1",
        "commit" => get(ENV, "E118_COMMIT", ""), "commit_note" => get(ENV, "E118_COMMIT_NOTE", ""),
        "script_sha256" => bytes2hex(SHA.sha256(read(f))), "teammpc" => teammpc52(),
        "env" => Dict(k => get(ENV, k, "") for k in ("BENCH_INSTANCE", "BENCH_FLEET", "BENCH_DISC", "BENCH_NAT_RADIUS", "BENCH_NAT_REGION",
                                                      "E71_FALLBACK", "E71_CERT_IN_STEP", "E118_EPS", "E118_ROUNDS", "E118_DELTA_REL")),
        "date" => string(Libc.strftime("%Y-%m-%dT%H:%M:%S", time())))
end

function run118(seed; n = N118, steps = STEPS118, arms = ARMS118, epss = EPS118, path = nothing)
    t00 = time()
    inst = sq_instance(n, seed); nv = length(inst.kinds)
    lab, _ = sq_teams(inst, "classes", seed)
    sc = scenario63(inst, seed, lab)
    E = Ev71(sc); ix = index118(E, sc.n)
    Uc = [cholesky(Symmetric(E.H0[i])).U for i in 1:sc.n]
    # check the incremental blocks against hs71 (the H_S of E106/E117)
    S = hs71(E, lab); @assert S.lab == lab
    T0 = teams118(E, ix, lab)
    hsdiff = maximum(begin
        _, _, _, B = block118(E, ix, T0.mem[c], lab)
        T0.cols[c] == S.parts[c] || error("team $c columns differ from hs71")
        norm(B - Matrix(S.HS[S.parts[c], S.parts[c]])) / max(norm(B), 1e-300)
    end for c in 1:maximum(lab))
    @assert hsdiff < 1e-12 "H_S blocks differ from hs71: $hsdiff"
    S = nothing; T0 = nothing; GC.gc()
    Rf = Ref71(sc)
    res = Dict{String,Any}("seed" => seed, "n_requested" => n, "n" => nv, "edges" => length(inst.edges), "teams_regions" => maximum(lab),
                           "steps" => steps, "period" => PERIOD71, "hs_check_reldiff" => hsdiff, "arms" => Dict{String,Any}(),
                           "arm_seconds" => Dict{String,Any}(), "load" => Dict{String,Any}("start" => loadavg26()))
    A = res["arms"]
    f106 = joinpath(get(ENV, "E118_E106_PARTS", ""), @sprintf("e102_n%d_seed%d.json", n, seed))
    if isfile(f106)
        d106 = JSON.parsefile(f106)
        res["coord_cost_e106"] = d106["controllers"]["coord"]["closed_loop_cost"]; res["n_e106"] = d106["n"]
        k106 = "team_resp_$(maximum(lab))"
        haskey(d106["controllers"], k106) && (res["fix_cost_ratio_e106"] = d106["controllers"][k106]["cost_ratio"])
    end
    save() = path === nothing || (res["meta"] = meta118(); res["seconds"] = time() - t00;
                                  open(io -> JSON.print(io, clean71(res), 1), path, "w"); println("wrote $path"); flush(stdout))
    Jc = NaN
    if "coord" in arms
        ta = @elapsed (co = coord71(sc; steps = steps)); res["arm_seconds"]["coord"] = ta
        Jc = co["closed_loop_cost"]
        A["coord"] = Dict{String,Any}("closed_loop_cost" => Jc, "t_total" => co["t_total"], "met_frac" => co["met_frac"])
        @printf("seed %d n %d coord cost %.6e ms med %.1f (%.0f s)\n", seed, nv, Jc, 1e3 * co["t_total"]["median"], ta); flush(stdout)
        save()
    end
    keys_ = String[]
    for sfx in FBMODES118
        "fix" in arms && push!(keys_, "fix" * sfx)
        "ref" in arms && append!(keys_, [@sprintf("ref_%g", e) * sfx for e in epss])
    end
    for key in keys_
        parts_ = split(key, "_")
        eps = parts_[1] == "fix" ? Inf : parse(Float64, parts_[2]); fb = !endswith(key, "_nofb")
        res["load"]["before_" * key] = loadavg26()
        ta = @elapsed (o = try
            arm118(sc, E, ix, Uc, Rf, lab, Jc; eps = eps, steps = steps, seed = seed, fb = fb)
        catch err
            @printf("  %s FAILED: %s\n", key, sprint(showerror, err, catch_backtrace())[1:min(end, 1500)]); flush(stdout)
            Dict{String,Any}("error" => sprint(showerror, err)[1:min(end, 2000)])
        end)
        res["arm_seconds"][key] = ta; A[key] = o
        haskey(o, "cost_ratio") && @printf("  %-9s ratio %.5f teams %d->%d->%d splits %d (after 0: %d) ms med %.1f max %.1f met %.3f fb %.3f eta/gap0 %.2f cert_viol %d (%.0f s)\n",
            key, o["cost_ratio"], o["teams_start"], o["teams_after0"], o["teams_final"], o["splits_total"], o["splits_after0"],
            1e3 * o["t_total"]["median"], 1e3 * o["t_total"]["max"], o["met_frac"], o["fallback_frac"], o["eta_over_gap0"], o["cert_viol"], ta)
        flush(stdout); save(); GC.gc()
    end
    res["load"]["end"] = loadavg26()
    save()
    return res
end

function main118()
    BLAS.set_num_threads(1); mkpath(PARTDIR118)
    if get(ENV, "E118_WARMUP", "1") == "1"                       # compile every path
        run118(1; n = 64, steps = 3, epss = [1e-3])
    end
    for seed in SEEDS118
        run118(seed; path = joinpath(PARTDIR118, @sprintf("e118_n%d_seed%d.json", N118, seed)))
    end
end

end # run

const FIELDS118 = Dict(
    "rows.<arm>" => "arm: fix (eps = Inf, same loop without splits), ref_<eps> (Algorithm 1 enforced), suffix _nofb = without the overrun rule (no fallback, timing does not affect the loop), e106_fixed (E106's team_resp_quarter, read from results/e106_overrun_full.json)",
    "cost_ratio_med / cost_ratio_max / cost_ratio_per_seed" => "closed-loop cost (30 steps + terminal stage) over that of converged centralized MPC (coord71) of the same seed in the same job; median / worst over seeds",
    "teams_final_med / teams_per_seed" => "team count at the end of the loop (teams only split; start 337 or 339 = one per region)",
    "teams_after0_per_seed" => "team count after the offline splits at x(0)",
    "splits_per_seed, splits_after0_per_seed, split_samples_per_seed" => "number of team splits in total / at samples 1..29 (online, timed), and the samples at which splits happened",
    "ms_med / ms_max" => "median over seeds of the per-seed median step time / worst step over seeds, ms, one pinned core, samples 1..29 (step 0 offline): team solve + least certificate (q untimed, as E106) + all split rounds (2-means, block factors, quotient rebuild, cold re-solve, re-certificate)",
    "met_frac" => "mean over seeds of the fraction of samples 1..29 with step time <= 200 ms",
    "met_frac_with_q / t_q_ms_med" => "the same counting the condensed linear data q at the measured state (qc71, untimed in E106 and here) / its median time",
    "fallback_frac" => "mean over seeds of the fraction of samples 1..29 on which E106's shift rule applied the previous plan shifted (step over the period)",
    "eta_rel0 / gap_rel0 / eta_over_gap0" => "at t = 0, after the offline splits: least certificate eta_min / |J*|, true gap (V_N(u_hat) - J*) / |J*|, eta/gap; eta_first_rel0 = eta/|J*| of the initial regions before splitting",
    "uncertified_total, stalled_total" => "samples whose final plan still failed eta <= eps W + delta (round cap E118_ROUNDS or no splittable team), summed over seeds",
    "cert_viol_total" => "samples with true gap > eta (Lemma cert violated), summed over seeds; must be 0",
    "seeds_info" => "per seed: n vehicles, edges, coord closed-loop cost here and in E106's part (when available), host, job, provenance")

function merge118()
    parts = sort([JSON.parsefile(joinpath(PARTDIR118, f)) for f in readdir(PARTDIR118) if endswith(f, ".json") && startswith(f, "e118_n4096")];
                 by = p -> p["seed"])
    md(v) = isempty(v) ? nothing : median(v)
    rows = Dict{String,Any}()
    akeys = sort(unique(vcat([[k for (k, o) in p["arms"] if k != "coord" && !haskey(o, "error")] for p in parts]...)))
    for key in akeys
        ps = [p["arms"][key] for p in parts if haskey(p["arms"], key) && !haskey(p["arms"][key], "error")]
        sd = [p["seed"] for p in parts if haskey(p["arms"], key) && !haskey(p["arms"][key], "error")]
        cr = [o["cost_ratio"] for o in ps]
        rows[key] = Dict{String,Any}("eps" => ps[1]["eps"], "fallback_rule" => get(ps[1], "fallback_rule", "shift"), "seeds" => sd, "cost_ratio_med" => md(cr), "cost_ratio_max" => maximum(cr),
            "cost_ratio_per_seed" => cr, "teams_final_med" => md(Float64.([o["teams_final"] for o in ps])),
            "teams_per_seed" => [o["teams_final"] for o in ps], "teams_after0_per_seed" => [o["teams_after0"] for o in ps],
            "teams_start_per_seed" => [o["teams_start"] for o in ps],
            "splits_per_seed" => [o["splits_total"] for o in ps], "splits_after0_per_seed" => [o["splits_after0"] for o in ps],
            "split_samples_per_seed" => [o["split_samples"] for o in ps],
            "ms_med" => 1e3 * md([o["t_total"]["median"] for o in ps]), "ms_max" => 1e3 * maximum(o["t_total"]["max"] for o in ps),
            "ms_med_per_seed" => [1e3 * o["t_total"]["median"] for o in ps],
            "met_frac" => mean([o["met_frac"] for o in ps]), "met_frac_with_q" => mean([o["met_frac_with_q"] for o in ps]),
            "t_q_ms_med" => 1e3 * md([o["t_q"]["median"] for o in ps]), "fallback_frac" => mean([o["fallback_frac"] for o in ps]),
            "eta_rel0_med" => md([o["eta_rel0"] for o in ps]), "gap_rel0_med" => md([o["gap_rel0"] for o in ps]),
            "eta_over_gap0_med" => md([o["eta_over_gap0"] for o in ps]), "eta_first_rel0_med" => md([o["eta_first_rel0"] for o in ps]),
            "gap_rel_med_med" => md([o["gap_rel"]["median"] for o in ps]), "eta_over_gap_med_med" => md([o["eta_over_gap"]["median"] for o in ps]),
            "uncertified_total" => sum(something(o["uncertified"], 0) for o in ps), "stalled_total" => sum(o["stalled"] for o in ps),
            "cert_viol_total" => sum(o["cert_viol"] for o in ps), "delta_rel" => ps[1]["delta_rel"],
            "t_split_when_ms_med" => md([1e3 * o["t_split_when"]["median"] for o in ps if haskey(o["t_split_when"], "median")]))
    end
    f106 = joinpath(ROOT118, "results", "e106_overrun_full.json")
    if isfile(f106)
        c = JSON.parsefile(f106)["sizes"]["4096"]["controllers"]["team_resp_quarter"]
        rows["e106_fixed"] = Dict{String,Any}("eps" => "Inf (E106, kktE71 ray certificate timed)", "cost_ratio_med" => c["cost_ratio_med"],
            "cost_ratio_max" => c["cost_ratio_max"], "cost_ratio_per_seed" => c["cost_ratio_per_seed"], "teams_per_seed" => c["teams_per_seed"],
            "teams_final_med" => c["teams"], "ms_med" => c["ms_med"], "ms_max" => c["ms_max"], "met_frac" => c["met_frac"],
            "fallback_frac" => c["fallback_frac"], "source" => "results/e106_overrun_full.json sizes.4096.controllers.team_resp_quarter")
    end
    seeds = [Dict{String,Any}("seed" => p["seed"], "n" => p["n"], "edges" => p["edges"], "teams_regions" => p["teams_regions"],
                              "coord_cost" => get(get(p["arms"], "coord", Dict()), "closed_loop_cost", nothing),
                              "coord_cost_e106" => get(p, "coord_cost_e106", nothing),
                              "hs_check_reldiff" => p["hs_check_reldiff"], "arm_seconds" => p["arm_seconds"], "load" => p["load"],
                              "meta" => p["meta"]) for p in parts]
    out = Dict{String,Any}("experiment" => "E118: Algorithm 1 (certified refinement) enforced on E106's irregular fleets (largest connected part of 4096 random slots, one team per region to start, h = 0.2 s, H = 10, ball limits). Each sample: team solve, least certificate (NNLS per team, D = H_0), and while eta_min > eps W + delta split the teams of largest eta_c by 2-means of their members' steps -H_S,c^{-1}(g_c + N c) (own-Hessian metric), teams covering eta - (eps W + delta)/2 per round, rebuild the quotient program and re-solve cold; teams only split. W = V_N(u_hat) at the measured state, delta = delta_rel W_0. Step 0 offline (untimed); E106's shift overrun rule on a step over 200 ms.",
                           "fields" => FIELDS118, "period_ms" => 200.0, "rows" => rows, "seeds_info" => seeds,
                           "jobs" => sort(unique([p["meta"]["job"] for p in parts])), "hosts" => sort(unique([p["meta"]["host"] for p in parts])),
                           "commits" => sort(unique([p["meta"]["commit"] for p in parts])),
                           "script_sha256" => sort(unique([p["meta"]["script_sha256"] for p in parts])))
    open(io -> JSON.print(io, out, 1), OUT118, "w"); println("wrote $OUT118")
    @printf("%-11s %-26s %-12s %-10s %-16s %-6s %s\n", "arm", "cost ratio med [worst]", "teams med", "ms med", "ms max", "met", "splits (after 0) per seed")
    for key in sort(collect(keys(rows)); by = k -> k == "e106_fixed" ? "0" : k == "fix" ? "1" : "2" * k)
        r = rows[key]
        @printf("%-11s %.4f [%.4f]            %-12s %-10.1f %-16.1f %-6.3f %s\n", key, r["cost_ratio_med"], r["cost_ratio_max"],
                string(r["teams_final_med"]), r["ms_med"], r["ms_max"], r["met_frac"],
                haskey(r, "splits_per_seed") ? string(r["splits_per_seed"], " (", r["splits_after0_per_seed"], ")") : "-")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE118 == "merge" ? merge118() : main118()
end
