# E66: the disturbed closed loop of team MPC (Algorithm 1 with the projection and the local gain).
#
# The natural formation of E63-gap (squads_dc.jl natural_instance, same generator and seeds, ball limits, the
# setup of results/setup.json), tracking the lanes (or, with E63_REG=1, regulation with the terminal equality).
# Every vehicle starts off formation by a random offset and every step adds a bounded disturbance to every
# vehicle's state, i.i.d. per vehicle and step, uniform in a box:
#   start offset   position U(-1,1) * rho * E66_P0 (m), velocity U(-1,1) * rho * E66_V0 (m/s), per component
#   disturbance    position U(-1,1) * rho * umax_i h^2/2, velocity U(-1,1) * rho * umax_i h, per component
# at the levels rho of E66_LEVELS (input limit times the sample time as the unit). The unit draws come from one
# RNG per seed, so every controller and every level sees the same realizations (common random numbers).
#
# Controllers (all with Clarabel, the solver of E63-gap):
#   coord             coordinated MPC (the full program from the measured states)
#   <choice>          team MPC: x~ = Delta + Pi (x^ - Delta) (team means in deviation coordinates), the team
#                     program (the full program restricted to team plans u = Z v) solved from x~, and every member
#                     applies v_i = u_c - K_c (x^_i - x~_i), K_c the LQR gain of the team's agent (state weight
#                     Cr'Q Cr + 1e-6 I, input weight R, as TeamMPC.TeamController)
#   <choice>_K0       the same without the local gain (K = 0)
#   <choice>_tight    with the gain, the team program's input limits tightened to (1 - E66_TIGHT) umax_i (tube-style
#                     margin for the feedback)
# The team program keeps the nominal input limits (no tightening), so the applied input is saturated radially
# onto the ball ||v_i|| <= umax_i; saturation is counted. A step whose program is not solved applies the shifted
# previous plan (zero after H steps) and is counted.
#
#   E66_N=256 E66_SEEDS=1 julia --project=env scripts/resolution/experiments/e66_disturbed.jl

haskey(ENV, "BENCH_INSTANCE") || (ENV["BENCH_INSTANCE"] = "natural")
include(joinpath(@__DIR__, "e63_gap.jl"))

const N66 = parse(Int, get(ENV, "E66_N", "256"))
const SEEDS66 = parse.(Int, split(get(ENV, "E66_SEEDS", "1"), ","))
const STEPS66 = parse(Int, get(ENV, "E66_STEPS", "40"))
const LEVELS66 = parse.(Float64, split(get(ENV, "E66_LEVELS", "0,0.1,0.3,1"), ","))
const CHOICES66 = split(get(ENV, "E66_CHOICES", "classes,qs8"), ",")
const P066 = parse(Float64, get(ENV, "E66_P0", "0.5"))
const V066 = parse(Float64, get(ENV, "E66_V0", "0.25"))
const PARTDIR66 = get(ENV, "E66_PARTDIR", joinpath(ROOT27, "bench", "irregular", "results", "parts66"))
const TIGHT66 = parse(Float64, get(ENV, "E66_TIGHT", "0.2"))
const OK66 = ("SOLVED", "ALMOST_SOLVED")

"""The discrete LQR gain (value iteration), as TeamMPC.lqr_gain."""
function lqr66(A, B, Q, R; iters = 10_000, tol = 1e-12)
    P = Matrix{Float64}(Q)
    for _ in 1:iters
        K = (R + B' * P * B) \ (B' * P * A)
        Pn = Q + A' * P * (A - B * K); Pn = (Pn + Pn') / 2
        done = norm(Pn - P) <= tol * (1 + norm(P)); P = Pn
        done && break
    end
    return (R + B' * P * B) \ (B' * P * A)
end

"""x~_i = Delta_i + mean over i's team of (x_j - Delta_j)."""
function project66(x, D, mem, lab)
    mu = [sum(x[j] - D[j] for j in m) / length(m) for m in mem]
    return [mu[lab[i]] + D[i] for i in eachindex(x)]
end

"""Largest and root-mean-square ||x_i - x~_i|| for the teams `lab`."""
function formerr66(x, D, mem, lab)
    xt = project66(x, D, mem, lab)
    e = [norm(x[i] - xt[i]) for i in eachindex(x)]
    return maximum(e), sqrt(mean(abs2, e))
end

st66(v) = isempty(v) ? Dict{String,Any}() : Dict{String,Any}("median" => median(v), "max" => maximum(v), "min" => minimum(v), "mean" => mean(v))

function run66(n::Int, seed::Int; steps::Int = STEPS66, levels = LEVELS66, choices = CHOICES66, quiet::Bool = false)
    inst = sq_instance(n, seed); n = length(inst.kinds)
    h = DT63G; H = H63G
    fl = sq_fleet(inst, h, H, CONE63G)
    lanes = sq_lanes(inst, seed)
    cf = cfleet63(fl, H)
    K = Cons63(cf, CONE63G)
    Kt = Cons63(K.A, (1 - TIGHT66) .* K.b, K.blocks, K.owner, K.cone)          # tightened limits
    x0n, dp, dv = sq_start(inst, fl, seed)
    REG63G && (x0n = [fl.agents[i].nx == 6 ? [inst.slots[i] + [0.5dp; 1.5]; [0.3dv; 0.0]] : [inst.slots[i][1:2] + 0.5dp; 0.3dv] for i in 1:n])
    refsk(k) = REG63G ? refs_reg63(inst, fl, H) : sq_references(inst, lanes, fl, k * h, h, H)
    r0, t0 = refsk(0)
    base = CProg(cf, CData(x0n, r0, t0))
    Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
    umax = [cf.agents[i].umax for i in 1:n]
    D = [pinv(fl.agents[i].C) * inst.slots[i] for i in 1:n]           # offsets Delta_i (slot, at rest)
    # common random numbers: unit draws for the start offsets and the disturbances
    rng = Xoshiro(66_000_000 + seed)
    xi0 = [2 .* rand(rng, fl.agents[i].nx) .- 1 for i in 1:n]
    xiw = [[2 .* rand(rng, fl.agents[i].nx) .- 1 for i in 1:n] for _ in 1:steps]
    scl(i, a, b) = (d = fl.agents[i].nx ÷ 2; [fill(a, d); fill(b, d)])
    # teams, their gains (LQR per team type), Z
    teams = Dict{String,Any}()
    for ch in choices
        lab, _ = sq_teams(inst, ch, seed)
        mem = [findall(==(c), lab) for c in 1:maximum(lab)]
        Kg = Vector{Matrix{Float64}}(undef, n); rhoS = 0.0
        for m in mem
            ag = fl.agents[m[1]]; A, B = ag.A[1], ag.B[1]
            Kc = lqr66(A, B, ag.Cr' * ag.Q * ag.Cr + 1e-6 * I, ag.R)
            rhoS = max(rhoS, maximum(abs, eigvals(A - B * Kc)))
            for i in m; Kg[i] = Kc; end
        end
        teams[ch] = (lab = lab, mem = mem, Kg = Kg, Z = teamZ63(cf, lab), rhoS = rhoS)
    end
    res = Dict{String,Any}("seed" => seed, "n" => n, "edges" => length(inst.edges), "classes" => maximum(inst.class),
                           "regulation" => REG63G, "steps" => steps, "teams" => Dict(ch => maximum(t.lab) for (ch, t) in teams),
                           "closed_loop_spectral_radius_max" => Dict(ch => t.rhoS for (ch, t) in teams), "levels" => Dict{String,Any}())
    for rho in levels
        x0 = [x0n[i] .+ rho .* scl(i, P066, V066) .* xi0[i] for i in 1:n]
        W = [[rho .* scl(i, umax[i] * h^2 / 2, umax[i] * h) .* xiw[k][i] for i in 1:n] for k in 1:steps]
        # the closed loop of a controller: ctrl(x, k, refs, term, prev, age) -> (inputs before saturation, plan, solved, seconds, extra seconds)
        function loop(ctrl; labs)
            x = [copy(v) for v in x0]; cost = 0.0
            ferr = Dict(l => Float64[] for l in keys(labs)); frms = Dict(l => Float64[] for l in keys(labs))
            tsol = Float64[]; tfb = Float64[]; fails = 0; statuses = String[]
            nsat = 0; satsteps = 0; maxratio = 0.0; maxplan = 0.0; prev = nothing; age = 0
            for k in 0:steps
                for (l, (D_, mem, lab)) in labs
                    a, b = formerr66(x, D_, mem, lab); push!(ferr[l], a); push!(frms[l], b)
                end
                refs, term = refsk(k)
                if k == steps
                    cost += sq_stage(fl, x, nothing, refs)[1]
                    break
                end
                v, uplan, solved, ts, tx, st = ctrl(x, refs, term, prev, age)
                push!(tsol, ts); push!(tfb, tx)
                if solved
                    prev = uplan; age = 0
                else
                    fails += 1; push!(statuses, st); age += 1
                end
                anys = false
                for i in 1:n
                    maxplan = max(maxplan, norm(uplan === nothing ? zeros(0) : uplan[uidx(cf, i, min(age, H - 1))]) / umax[i])
                    nv = norm(v[i]); maxratio = max(maxratio, nv / umax[i])
                    if nv > umax[i] * (1 + 1e-9)
                        v[i] = v[i] .* (umax[i] / nv); nsat += 1; anys = true
                    end
                end
                satsteps += anys
                cost += sq_stage(fl, x, v, refs)[1]
                x = [xn .+ w for (xn, w) in zip(sq_plant(fl, x, v), W[k+1])]
            end
            return Dict{String,Any}("cost" => cost, "form_err_max" => Dict(l => maximum(e) for (l, e) in ferr),
                                    "form_err_final" => Dict(l => e[end] for (l, e) in ferr),
                                    "form_err_rms_final" => Dict(l => e[end] for (l, e) in frms),
                                    "form_err_max_late" => Dict(l => maximum(e[(steps÷2+1):end]) for (l, e) in ferr),
                                    "form_err_traj" => ferr,
                                    "infeasible_steps" => fails, "fail_statuses" => unique(statuses),
                                    "saturated_frac" => nsat / (n * steps), "saturated_steps" => satsteps,
                                    "max_input_ratio_presat" => maxratio, "max_plan_ratio" => maxplan,
                                    "t_solve_ms" => st66(1e3 .* tsol), "t_project_feedback_ms" => st66(1e3 .* tfb))
        end
        # the shifted previous plan when a solve fails
        shifted(prev, age) = prev === nothing || age >= H ? [zeros(cf.nus[i]) for i in 1:n] : [prev[uidx(cf, i, age)] for i in 1:n]
        alllabs = Dict(ch => (D, t.mem, t.lab) for (ch, t) in teams)
        out = Dict{String,Any}()
        out["coord"] = loop(; labs = alllabs) do x, refs, term, prev, age
            P = CProg(base, CData(x, refs, term)); _, hq, c = quad63(P, Hb)
            s = solve63(Hb, hq, c, K, nothing; E = P.E, e = P.e)
            ok = s.status in OK66
            v = ok ? first63(cf, s.u) : shifted(prev, age + 1)
            (v, ok ? s.u : prev, ok, s.seconds, 0.0, s.status)
        end
        Jc = out["coord"]["cost"]
        for ch in choices, (gain, tight) in ((true, false), (false, false), (true, true))
            T = teams[ch]
            name = tight ? ch * "_tight" : gain ? ch : ch * "_K0"
            KK = tight ? Kt : K
            r = loop(; labs = Dict(ch => alllabs[ch])) do x, refs, term, prev, age
                ta = time_ns()
                xt = project66(x, D, T.mem, T.lab)
                tb = time_ns()
                P = CProg(base, CData(xt, refs, term)); _, hq, c = quad63(P, Hb)
                s = solve63(Hb, hq, c, KK, T.Z; E = P.E, e = P.e)
                ok = s.status in OK66
                tc = time_ns()
                uc = ok ? first63(cf, s.u) : shifted(prev, age + 1)
                v = gain ? [uc[i] - T.Kg[i] * (x[i] - xt[i]) for i in 1:n] : [copy(uc[i]) for i in 1:n]
                (v, ok ? s.u : prev, ok, s.seconds, ((tb - ta) + (time_ns() - tc)) / 1e9, s.status)
            end
            r["cost_ratio"] = r["cost"] / Jc
            out[name] = r
        end
        res["levels"][string(rho)] = out
        if !quiet
            @printf("  rho %.2f  coord cost %.4g  ferr(classes) max %.3f final %.3f  t %.0f ms\n", rho, Jc,
                    out["coord"]["form_err_max"][choices[1]], out["coord"]["form_err_final"][choices[1]], out["coord"]["t_solve_ms"]["median"])
            for ch in choices, nm in (ch, ch * "_K0", ch * "_tight")
                o = out[nm]
                @printf("    %-12s ratio %.4f  ferr max %.3f final %.3f  infeas %d  sat %.3f (%d steps, presat max %.2f, plan max %.4f)  t med %.1f max %.1f ms\n",
                        nm, o["cost_ratio"], o["form_err_max"][ch], o["form_err_final"][ch], o["infeasible_steps"],
                        o["saturated_frac"], o["saturated_steps"], o["max_input_ratio_presat"], o["max_plan_ratio"],
                        o["t_solve_ms"]["median"], o["t_solve_ms"]["max"])
            end
            flush(stdout)
        end
    end
    return res
end

function main66()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR66)
    get(ENV, "E66_WARMUP", "1") == "1" && run66(32, 1; steps = 2, levels = [0.1], quiet = true)
    for seed in SEEDS66
        @printf("E66 natural n=%d seed %d cone %s reg %d\n", N66, seed, CONE63G, Int(REG63G)); flush(stdout)
        res = run66(N66, seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "levels" => LEVELS66, "p0" => P066, "v0" => V066, "tight" => TIGHT66)
        path = joinpath(PARTDIR66, @sprintf("e66_n%d_%s_reg%d_seed%d.json", N66, CONE63G, Int(REG63G), seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main66()
end
