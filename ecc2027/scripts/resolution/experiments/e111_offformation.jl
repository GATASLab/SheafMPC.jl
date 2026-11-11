# E111: off-formation starts and intra-team diffusion. Team plans keep teams in formation but cannot drive
# members into formation: under a shared input u_i = v_c a member's formation error relative to its team persists.
# This compares four controllers from starts where every vehicle is off its slot by an independent random offset.
#
# Formation: the planted squads of squads_dc.jl (Fig. teams(a); BENCH_INSTANCE=squads), drones and cars of
# Example 1 (two variants per type), lane references per class as in the paper's closed loops (sq_references,
# coherent, one lane per class, terminal cost, no terminal equality), ball limits, h = 0.2 s, H = 10. The teams are
# the planted squads, an almost equitable partition refining the classes (sq_spread recorded, 0 = exact).
#
# Start: the paper's start (sq_start: on the slot, lane velocity, one rigid perturbation per seed) plus, per vehicle,
# a position offset sigma * ell * xi_i, xi_i ~ N(0, I_d)/sqrt(d) (so E||xi_i||^2 = 1), zero velocity offset, with
# ell the median edge length of the formation. Unit draws xi are common to all sigma and all controllers.
# Disturbance case (level "dist"): sigma = 0.3 and, every step, an independent velocity kick N(0, (rw umax_i h)^2)
# per component to every vehicle (rw = E111_RW, default 0.1).
#
# Controllers (Clarabel at 1e-9, the solver of E63/E66/E86, every step to convergence):
#   A  central   the fleet program from the measured state
#   B  team      the team program from the projected state x~ (eq. (7)), u_i = v_{c,0} (shared input only)
#   C  diffuse   B plus one diffusion step on the team's own edges:
#                  u_i = v_{c,0} - kappa_c K_c sum_{j in c, ij in E} w_ij (e_i - e_j),  e_i = x_i - x_{s,i},
#                K_c the per-type LQR gain of Algorithm 1 (state weight Cr'Q Cr + 1e-6 I, input weight R), and
#                kappa_c = 1 / (2 d_c), d_c the largest weighted degree inside team c (edges inside c only).
#                Gain rule: the correction acts on the Laplacian modes of team c, mode lambda gets the gain
#                (lambda kappa_c) K_c, and lambda <= 2 d_c (Gershgorin), so every mode gets s K_c, s in (0, 1]; the
#                script checks max_s rho(A - s B K_c) < 1 on a grid. The correction sums to zero over the team (the
#                team mean is untouched), uses only the errors of i's team neighbours, and needs no team mean.
#   C* diffuse_opt  the same correction with per-axis PD gains G_c = [k_p k_v] tuned to team c's Laplacian
#                spectrum: (k_p, k_v) minimizes max_{lambda in [lambda_2(L_c), lambda_max(L_c)]} rho(A - lambda B G_c) on a
#                log grid (per-axis model of the team's type), u_i = v_{c,0} - G_c sum_j w_ij (e_i - e_j)
#   D  alg1      Algorithm 1: u_i = v_{c,0} - K_c (x_i - x~_i)
# All applied inputs are clipped radially onto ||u_i|| <= umax_i (counted). A failed solve applies the shifted
# previous plan (counted).
#
# Metrics per run: closed-loop cost (sum of the stage costs, terminal stage included) over that of A; the
# within-team spread S(t) = ||x - x_s - Pi(x - x_s)|| (2-norm over the fleet, position and velocity) at every step,
# also its position part; the first step with S(t) <= 0.01 S(0); clip activity and the largest applied ||u_i||/umax
# after clipping; wall time per step of each controller (data, projection, solve, correction).
#
#   E111_N=256 E111_SEEDS=1 julia --project=env scripts/resolution/experiments/e111_offformation.jl
#   E111_MODE=merge E111_PARTDIR=<parts> E111_OUT=results/e111_offformation.json julia ... e111_offformation.jl
# The run mode needs the condensed-program files with per-agent input sizes (e30_bounds_dc.jl, loaded by e63_gap.jl,
# as E103b); the HPG run used the E106 tree, whose files this directory carries. E111_LIBDIR (optional) points at
# another experiments directory (default: this one).

const MODE111 = get(ENV, "E111_MODE", "run")
if MODE111 == "run"
    ENV["BENCH_INSTANCE"] = get(ENV, "E111_INSTANCE", "squads")
    ENV["E63_REG"] = "0"
    include(joinpath(get(ENV, "E111_LIBDIR", @__DIR__), "e66_disturbed.jl"))
    @assert !REG63G
end
using JSON, Statistics, Printf, LinearAlgebra, Random

const N111 = parse(Int, get(ENV, "E111_N", "256"))
const SEEDS111 = parse.(Int, split(get(ENV, "E111_SEEDS", "1"), ","))
const STEPS111 = parse(Int, get(ENV, "E111_STEPS", "100"))
const SIGMAS111 = parse.(Float64, split(get(ENV, "E111_SIGMAS", "0.1,0.3,1.0"), ","))
const DISTSIG111 = parse(Float64, get(ENV, "E111_DIST_SIGMA", "0.3"))
const RW111 = parse(Float64, get(ENV, "E111_RW", "0.1"))
const ARMS111 = split(get(ENV, "E111_ARMS", "central,team,diffuse,diffuse_opt,alg1"), ",")
const PARTDIR111 = get(ENV, "E111_PARTDIR", joinpath(@__DIR__, "..", "..", "..", "results", "e111_parts"))
const OUT111 = get(ENV, "E111_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "e111_offformation.json"))

st111(v) = (w = [x for x in v if x !== nothing && isfinite(x)]; isempty(w) ? nothing :
            Dict{String,Any}("median" => median(w), "min" => minimum(w), "max" => maximum(w), "mean" => mean(w), "n" => length(w)))
nonan111(x) = x isa AbstractFloat ? (isfinite(x) ? x : nothing) : x isa AbstractDict ? Dict{String,Any}(string(k) => nonan111(v) for (k, v) in x) :
              x isa AbstractVector ? Any[nonan111(v) for v in x] : x

if MODE111 == "run"

"""Per-axis (2x2) model of an agent: position and velocity of axis 1 (as E67)."""
axis111(ag) = (d = ag.nx ÷ 2; (ag.A[1][[1, d + 1], [1, d + 1]], ag.B[1][[1, d + 1], 1:1], d))

"""Spectral radius of a 2x2 matrix."""
rho2(M) = (t = (M[1, 1] + M[2, 2]) / 2; dt = M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]; q = t^2 - dt;
           q >= 0 ? max(abs(t + sqrt(q)), abs(t - sqrt(q))) : sqrt(dt))

"""PD gains [k_p, k_v] minimizing the worst per-axis rate max_lambda rho(A1 - lambda B1 k) over [l2, lx] (log grid, refined)."""
function pdopt111(A1, B1, l2, lx; nl = 40)
    ls = range(l2, lx; length = nl)
    worst(k) = maximum(rho2(A1 - l * B1 * k') for l in ls)
    best = (Inf, [0.0, 0.0])
    for kp in exp10.(range(-3, 2; length = 81)), kv in exp10.(range(-3, 2; length = 81))
        w = worst([kp, kv]); w < best[1] && (best = (w, [kp, kv]))
    end
    for _ in 1:3                                   # local refinement around the grid optimum
        kp0, kv0 = best[2]
        for kp in kp0 .* exp10.(range(-0.1, 0.1; length = 21)), kv in kv0 .* exp10.(range(-0.1, 0.1; length = 21))
            w = worst([kp, kv]); w < best[1] && (best = (w, [kp, kv]))
        end
    end
    return best[2]
end

"""Within-team spread ||x - x_s - Pi(x - x_s)|| (full state) and its position part."""
function spread111(x, D, mem, lab, fl)
    xt = project66(x, D, mem, lab)
    s = 0.0; sp = 0.0
    for i in eachindex(x)
        e = x[i] - xt[i]; d = fl.agents[i].nx ÷ 2
        s += sum(abs2, e); sp += sum(abs2, @view e[1:d])
    end
    return sqrt(s), sqrt(sp)
end

"""Closed loop from x0: ctrl(x, k) -> (v, solved, status); records cost, spread, timing, clipping."""
function loop111(ctrl, x0, W, fl, refsk, umax, D, mem, lab, steps)
    n = length(x0); x = [copy(v) for v in x0]; cost = 0.0
    S = Float64[]; Sp = Float64[]; tstep = Float64[]; fails = 0; statuses = String[]
    nclip = 0; maxpre = 0.0; maxpost = 0.0
    for k in 0:steps
        s, sp = spread111(x, D, mem, lab, fl); push!(S, s); push!(Sp, sp)
        refs, term = refsk(k)
        if k == steps
            cost += sq_stage(fl, x, nothing, refs)[1]; break
        end
        t0 = time_ns()
        v, solved, st = ctrl(x, k, refs, term)
        push!(tstep, (time_ns() - t0) / 1e9)
        solved || (fails += 1; push!(statuses, st))
        for i in 1:n
            nv = norm(v[i]); maxpre = max(maxpre, nv / umax[i])
            if nv > umax[i]
                v[i] = v[i] .* (umax[i] / nv); nclip += 1
            end
            maxpost = max(maxpost, norm(v[i]) / umax[i])
        end
        cost += sq_stage(fl, x, v, refs)[1]
        x = [xn .+ w for (xn, w) in zip(sq_plant(fl, x, v), W[k+1])]
    end
    hit = findfirst(<=(0.01 * S[1]), S)
    late = S[(steps÷2+1):end]
    return Dict{String,Any}("cost" => cost, "spread" => S, "spread_pos" => Sp,
                            "spread_final_rel" => S[end] / S[1], "spread_late_median_rel" => median(late) / S[1],
                            "t1pct_step" => hit === nothing ? nothing : hit - 1,
                            "infeasible_steps" => fails, "fail_statuses" => unique(statuses),
                            "clipped" => nclip, "clipped_frac" => nclip / (n * steps),
                            "max_input_ratio_preclip" => maxpre, "max_input_ratio_applied" => maxpost,
                            "violations_applied" => count(>(1 + 1e-12), [maxpost]),
                            "t_step_ms" => st111(1e3 .* tstep[2:end]))     # step 0 excluded (compilation)
end

function run111(n::Int, seed::Int; steps::Int = STEPS111, quiet::Bool = false)
    inst = sq_instance(n, seed); n = length(inst.kinds)
    h = DT63G; H = H63G
    fl = sq_fleet(inst, h, H, CONE63G)
    CONE63G == :soc || error("E111 needs ball limits")
    lanes = sq_lanes(inst, seed)
    cf = cfleet63(fl, H)
    K = Cons63(cf, CONE63G)
    x0n, _, _ = sq_start(inst, fl, seed)
    refsk(k) = sq_references(inst, lanes, fl, k * h, h, H)
    r0, t0 = refsk(0)
    base = CProg(cf, CData(x0n, r0, t0))
    Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
    umax = [cf.agents[i].umax for i in 1:n]
    D = [pinv(fl.agents[i].C) * inst.slots[i] for i in 1:n]         # x_{s,i}: slot at rest (the lane is in r_c)
    lab, _ = sq_teams(inst, "squads", seed)
    mem = [findall(==(c), lab) for c in 1:maximum(lab)]
    for m in mem
        all(i -> inst.kinds[i] == inst.kinds[m[1]] && inst.params[i] == inst.params[m[1]], m) || error("a team mixes vehicle types")
    end
    Z = teamZ63(cf, lab)
    aep = sq_spread(n, inst.edges, inst.w, lab)[1]
    ell_all = median([norm(inst.slots[j] - inst.slots[i]) for (i, j) in inst.edges])
    ell = median([norm(inst.slots[j] - inst.slots[i]) for (i, j) in inst.edges if lab[i] == lab[j]])   # inside teams
    # gains: per-type LQR (Algorithm 1) and the intra-team graph
    Kg = Vector{Matrix{Float64}}(undef, n)
    tcache = Dict{Any,Matrix{Float64}}()
    for i in 1:n
        ag = fl.agents[i]
        Kg[i] = get!(() -> lqr66(ag.A[1], ag.B[1], ag.Cr' * ag.Q * ag.Cr + 1e-6 * I, ag.R), tcache, (inst.kinds[i], inst.params[i]))
    end
    nbr = [Tuple{Int,Float64}[] for _ in 1:n]
    for (k, (i, j)) in enumerate(inst.edges)
        lab[i] == lab[j] || continue
        push!(nbr[i], (j, inst.w[k])); push!(nbr[j], (i, inst.w[k]))
    end
    deg = [sum(last, nbr[i]; init = 0.0) for i in 1:n]
    dmax = [maximum(deg[m]) for m in mem]
    lam2 = zeros(length(mem)); lamx = zeros(length(mem))
    for (c, m) in enumerate(mem)
        pos = Dict(i => a for (a, i) in enumerate(m)); Lc = zeros(length(m), length(m))
        for i in m, (j, w) in nbr[i]
            Lc[pos[i], pos[i]] += w; Lc[pos[i], pos[j]] -= w
        end
        ev = sort(eigvals(Symmetric(Lc)))
        lam2[c] = length(m) > 1 ? ev[2] : 0.0; lamx[c] = ev[end]
        length(m) > 1 && lam2[c] < 1e-9 && error("team $c is disconnected inside")
    end
    # diffusion gains per team (d x 2d matrices on sum_j w_ij (e_i - e_j))
    Gd = Dict{String,Vector{Matrix{Float64}}}()
    Gd["diffuse"] = [Kg[m[1]] ./ (2 * dmax[c]) for (c, m) in enumerate(mem)]
    ocache = Dict{Any,Vector{Float64}}()
    Gd["diffuse_opt"] = map(enumerate(mem)) do (c, m)
        ag = fl.agents[m[1]]; A1, B1, d = axis111(ag)
        length(m) == 1 && return zeros(d, 2d)
        k1 = get!(() -> pdopt111(A1, B1, lam2[c], lamx[c]), ocache, (round(lam2[c]; digits = 6), round(lamx[c]; digits = 6), A1, B1))
        Gf = zeros(d, 2d)
        for a in 1:d
            Gf[a, a] = k1[1]; Gf[a, d+a] = k1[2]
        end
        Gf
    end
    # stability of A - s B K over s in (0, 1] per type, and the slowest-mode rate per team
    stab = Dict{String,Any}()
    for (key, Kc) in tcache
        i = findfirst(j -> (inst.kinds[j], inst.params[j]) == key, 1:n); ag = fl.agents[i]
        rr = [maximum(abs, eigvals(ag.A[1] - s * ag.B[1] * Kc)) for s in exp.(range(log(1e-4), 0; length = 400))]
        stab[@sprintf("%s_umax%g_drag%g", key[1], key[2].umax, key[2].drag)] = Dict("rho_max_over_s" => maximum(rr), "rho_s1" => rr[end])
    end
    # slowest rate over team c's nonzero Laplacian modes (lambda on a grid of [lambda_2, lambda_max])
    slow = Dict(nm => [(m = mem[c]; ag = fl.agents[m[1]]; length(m) > 1 ?
                        maximum(maximum(abs, eigvals(ag.A[1] - l * ag.B[1] * Gd[nm][c])) for l in range(lam2[c], lamx[c]; length = 50)) : 0.0)
                       for c in eachindex(mem)] for nm in keys(Gd))
    alg1rate = [maximum(abs, eigvals(fl.agents[m[1]].A[1] - fl.agents[m[1]].B[1] * Kg[m[1]])) for m in mem]
    res = Dict{String,Any}("seed" => seed, "n" => n, "edges" => length(inst.edges), "classes" => maximum(inst.class),
                           "teams" => length(mem), "team_sizes" => st111(Float64.(length.(mem))), "aep_spread" => aep,
                           "edge_length_median" => ell, "edge_length_median_all" => ell_all, "steps" => steps,
                           "pd_gains_opt" => [vec(Gd["diffuse_opt"][c][1, [1, size(Gd["diffuse_opt"][c], 2) ÷ 2 + 1]]) for c in eachindex(mem)],
                           "intra_team" => Dict("dmax" => st111(dmax), "lambda2" => st111(lam2), "lambda_max" => st111(lamx),
                                                "lambda_max_over_2dmax" => st111(lamx ./ (2 .* dmax)),
                                                "slowest_mode_rho" => Dict(k => st111(v) for (k, v) in slow),
                                                "alg1_rho" => st111(alg1rate)),
                           "stability" => stab, "levels" => Dict{String,Any}())
    quiet || @printf("  n %d edges %d teams %d sizes %.0f-%.0f aep %.1e ell %.3f  lambda2 med %.3f  rho slow diffuse med %.4f max %.4f, opt %.4f  alg1 %.4f\n",
                     n, length(inst.edges), length(mem), minimum(length.(mem)), maximum(length.(mem)), aep, ell, median(lam2),
                     median(slow["diffuse"]), maximum(slow["diffuse"]), median(slow["diffuse_opt"]), maximum(alg1rate))
    rng = Xoshiro(111_000_000 + seed)
    xi = [(d = fl.agents[i].nx ÷ 2; randn(rng, d) ./ sqrt(d)) for i in 1:n]
    kick = [[(d = fl.agents[i].nx ÷ 2; randn(rng, d)) for i in 1:n] for _ in 1:steps]
    levels = [(@sprintf("s%g", s), s, 0.0) for s in SIGMAS111]
    DISTSIG111 > 0 && push!(levels, ("dist", DISTSIG111, RW111))
    zw = [[zeros(fl.agents[i].nx) for i in 1:n] for _ in 1:steps]
    shifted(prev, age) = prev === nothing || age >= H ? [zeros(cf.nus[i]) for i in 1:n] : [prev[uidx(cf, i, age)] for i in 1:n]
    for (lname, sig, rw) in levels
        x0 = [(d = fl.agents[i].nx ÷ 2; x0n[i] .+ [sig * ell .* xi[i]; zeros(d)]) for i in 1:n]
        W = rw == 0 ? zw : [[(d = fl.agents[i].nx ÷ 2; [zeros(d); rw * umax[i] * h .* kick[k][i]]) for i in 1:n] for k in 1:steps]
        out = Dict{String,Any}()
        for arm in ARMS111
            prev = Ref{Any}(nothing); age = Ref(0)
            out[arm] = loop111(x0, W, fl, refsk, umax, D, mem, lab, steps) do x, k, refs, term
                if arm == "central"
                    P = CProg(base, CData(x, refs, term)); _, hq, c = quad63(P, Hb)
                    s = solve63(Hb, hq, c, K, nothing; E = P.E, e = P.e)
                    ok = s.status in OK66
                    ok ? (prev[] = s.u; age[] = 0) : (age[] += 1)
                    return (ok ? first63(cf, s.u) : shifted(prev[], age[]), ok, s.status)
                end
                xt = project66(x, D, mem, lab)
                P = CProg(base, CData(xt, refs, term)); _, hq, c = quad63(P, Hb)
                s = solve63(Hb, hq, c, K, Z; E = P.E, e = P.e)
                ok = s.status in OK66
                ok ? (prev[] = s.u; age[] = 0) : (age[] += 1)
                uc = ok ? first63(cf, s.u) : shifted(prev[], age[])
                if arm == "team"
                    v = uc
                elseif arm == "alg1"
                    v = [uc[i] - Kg[i] * (x[i] - xt[i]) for i in 1:n]
                else
                    G = Gd[arm]
                    e = [x[i] - D[i] for i in 1:n]
                    v = map(1:n) do i
                        g = zero(e[i])
                        for (j, w) in nbr[i]
                            g .+= w .* (e[i] .- e[j])
                        end
                        uc[i] - G[lab[i]] * g
                    end
                end
                return (v, ok, s.status)
            end
        end
        Jc = haskey(out, "central") ? out["central"]["cost"] : NaN
        for (_, q) in out
            q["cost_ratio"] = q["cost"] / Jc
        end
        res["levels"][lname] = merge(Dict{String,Any}("sigma" => sig, "rw" => rw), out)
        if !quiet
            @printf("  level %-5s sigma %.2f rw %.2f  S0 %.3f\n", lname, sig, rw, out[ARMS111[1]]["spread"][1])
            for arm in ARMS111
                q = out[arm]
                @printf("    %-12s cost ratio %.4f  S final/S0 %.2e late %.2e  t1%% %s  fails %d  clip %.3f (pre %.2f post %.4f)  t med %.1f ms\n",
                        arm, q["cost_ratio"], q["spread_final_rel"], q["spread_late_median_rel"], string(q["t1pct_step"]),
                        q["infeasible_steps"], q["clipped_frac"], q["max_input_ratio_preclip"], q["max_input_ratio_applied"],
                        q["t_step_ms"]["median"])
            end
            flush(stdout)
        end
    end
    return res
end

function main111()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR111)
    get(ENV, "E111_WARMUP", "1") == "1" && run111(32, 1; steps = 2, quiet = true)
    for seed in SEEDS111
        @printf("E111 squads n=%d seed %d\n", N111, seed); flush(stdout)
        res = run111(N111, seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "E111_AFFINITY", ""),
                           "git" => get(ENV, "E111_GIT", ""), "rw" => RW111, "sigmas" => SIGMAS111, "dist_sigma" => DISTSIG111)
        path = joinpath(PARTDIR111, @sprintf("e111_n%d_seed%d.json", N111, seed))
        open(io -> JSON.print(io, nonan111(res), 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

end  # run mode

# ---------------------------------------------------------------------------
# Merge: per (n, level, arm) statistics over seeds, and the median and band of the spread trajectories
# ---------------------------------------------------------------------------

function merge111()
    parts = [JSON.parsefile(joinpath(PARTDIR111, f)) for f in sort(readdir(PARTDIR111)) if startswith(f, "e111_") && endswith(f, ".json")]
    sizes = Dict{String,Any}()
    for n in sort(unique(p["n"] for p in parts))
        ps = [p for p in parts if p["n"] == n]
        S = Dict{String,Any}("seeds" => [p["seed"] for p in ps], "teams" => st111([p["teams"] for p in ps]),
                             "team_size_max" => maximum(p["team_sizes"]["max"] for p in ps),
                             "team_size_min" => minimum(p["team_sizes"]["min"] for p in ps),
                             "aep_spread_max" => maximum(p["aep_spread"] for p in ps),
                             "teams_disconnected_inside" => 0,       # run111 errors on a team disconnected inside G
                             "edge_length_median" => st111([p["edge_length_median"] for p in ps]),
                             "lambda2_median" => median(p["intra_team"]["lambda2"]["median"] for p in ps),
                             "slowest_mode_rho_diffuse_max" => maximum(p["intra_team"]["slowest_mode_rho"]["diffuse"]["max"] for p in ps),
                             "slowest_mode_rho_diffuse_median" => median(p["intra_team"]["slowest_mode_rho"]["diffuse"]["median"] for p in ps),
                             "slowest_mode_rho_opt_median" => median(p["intra_team"]["slowest_mode_rho"]["diffuse_opt"]["median"] for p in ps),
                             "slowest_mode_rho_opt_max" => maximum(p["intra_team"]["slowest_mode_rho"]["diffuse_opt"]["max"] for p in ps),
                             "alg1_rho_max" => maximum(p["intra_team"]["alg1_rho"]["max"] for p in ps),
                             "stability_rho_max" => maximum(v["rho_max_over_s"] for p in ps for (_, v) in p["stability"]),
                             "jobs" => unique([p["meta"]["job"] for p in ps]), "hosts" => unique([p["meta"]["host"] for p in ps]),
                             "cpus" => unique([p["meta"]["cpu"] for p in ps]), "levels" => Dict{String,Any}())
        for lname in keys(ps[1]["levels"])
            ls = [p["levels"][lname] for p in ps]
            L = Dict{String,Any}("sigma" => ls[1]["sigma"], "rw" => ls[1]["rw"])
            for arm in keys(ls[1])
                arm in ("sigma", "rw") && continue
                qs = [l[arm] for l in ls]
                T = reduce(hcat, [Float64.(q["spread"]) ./ q["spread"][1] for q in qs])
                C = Dict{String,Any}("cost_ratio" => st111([q["cost_ratio"] for q in qs]),
                                     "cost_ratio_alg1" => haskey(ls[1], "alg1") ? st111([q["cost"] / l["alg1"]["cost"] for (q, l) in zip(qs, ls)]) : nothing,
                                     "spread_final_rel" => st111([q["spread_final_rel"] for q in qs]),
                                     "spread_late_median_rel" => st111([q["spread_late_median_rel"] for q in qs]),
                                     "t1pct_step" => st111([q["t1pct_step"] for q in qs]),
                                     "t1pct_reached" => count(q -> q["t1pct_step"] !== nothing, qs),
                                     "t5pct_step" => st111([something(findfirst(<=(0.05 * q["spread"][1]), q["spread"]), 0) - 1 for q in qs
                                                            if findfirst(<=(0.05 * q["spread"][1]), q["spread"]) !== nothing]),
                                     "t5pct_reached" => count(q -> findfirst(<=(0.05 * q["spread"][1]), q["spread"]) !== nothing, qs),
                                     "spread_late_median_abs" => st111([median(q["spread"][(length(q["spread"])÷2+1):end]) for q in qs]),
                                     "infeasible_steps_total" => sum(q["infeasible_steps"] for q in qs),
                                     "clipped_frac" => st111([q["clipped_frac"] for q in qs]),
                                     "max_input_ratio_applied" => maximum(q["max_input_ratio_applied"] for q in qs),
                                     "max_input_ratio_preclip" => maximum(q["max_input_ratio_preclip"] for q in qs),
                                     "violations_applied_total" => sum(q["violations_applied"] for q in qs),
                                     "t_step_ms_median" => median([q["t_step_ms"]["median"] for q in qs]),
                                     "t_step_ms_max" => maximum([q["t_step_ms"]["max"] for q in qs]),
                                     "spread_rel_traj" => Dict("median" => [median(T[k, :]) for k in 1:size(T, 1)],
                                                               "min" => [minimum(T[k, :]) for k in 1:size(T, 1)],
                                                               "max" => [maximum(T[k, :]) for k in 1:size(T, 1)]),
                                     "spread0" => st111([q["spread"][1] for q in qs]))
                L[arm] = C
            end
            S["levels"][lname] = L
        end
        sizes[string(n)] = S
    end
    # optional timing probe (a few closed-loop steps of centralized and team MPC, one seed per size)
    probe = Dict{String,Any}()
    pdir = get(ENV, "E111_PROBEDIR", "")
    if !isempty(pdir) && isdir(pdir)
        for f in sort(readdir(pdir))
            endswith(f, ".json") || continue
            P = JSON.parsefile(joinpath(pdir, f)); L = first(values(P["levels"]))
            probe[string(P["n"])] = Dict{String,Any}("steps" => P["steps"], "job" => P["meta"]["job"], "host" => P["meta"]["host"],
                                                     "cpu" => P["meta"]["cpu"],
                                                     "t_step_ms_median" => Dict(a => L[a]["t_step_ms"]["median"] for a in keys(L) if L[a] isa AbstractDict && haskey(L[a], "t_step_ms")))
        end
    end
    out = Dict{String,Any}("experiment" => "E111 off-formation starts: centralized MPC, team MPC alone, team MPC plus one intra-team diffusion step, Algorithm 1 (team-mean LQR correction)",
                           "setup" => "planted squads (squads_dc.jl, teams = squads, almost equitable), lane references, terminal cost, ball limits, h = 0.2 s, H = 10; start = sq_start plus per-vehicle position offset sigma*ell*N(0,I)/sqrt(d), ell = median edge length inside teams, zero velocity offset; dist = sigma 0.3 plus velocity kicks N(0,(rw umax h)^2) per component and step; Clarabel 1e-9 every step; inputs clipped onto the balls; diffuse gain kappa_c = 1/(2 d_c) times the per-type LQR gain of Algorithm 1; diffuse_opt per-axis PD gains minimizing the worst rate over [lambda_2(L_c), lambda_max(L_c)]",
                           "git" => unique([p["meta"]["git"] for p in parts]), "sizes" => sizes, "timing_probe" => probe,
                           "notes" => "converged centralized MPC (Clarabel 1e-9) took about 14 s per step at 256 vehicles, so the 1024-vehicle runs omit it (cost reported over Algorithm 1 there); its step time at 1024 is from timing_probe")
    open(io -> JSON.print(io, nonan111(out), 1), OUT111, "w")
    println("wrote $OUT111")
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE111 == "merge" ? merge111() : main111()
end
