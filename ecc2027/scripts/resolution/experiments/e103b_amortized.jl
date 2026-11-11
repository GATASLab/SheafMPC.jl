# E103b: certified adaptive teams with an amortized certificate, in the setting of Theorem closedloop.
# Runs from the teammpc-paper tree (it includes e70_adaptive.jl, hence e63_gap.jl and e51_symmetric.jl).
#
# Setting: E103's irregular formation (natural instance, the same instances and seeds, ball limits, H = 10,
# h = 0.2 s), in the nominal loop of Theorem closedloop: regulation to the slots at rest (drones at altitude 1.5),
# the terminal equality x_H = slot state for every vehicle (a two-sided state polyhedron at t = H in TeamMPC, the
# equality rows in the condensed program), and a start in formation per region: region c starts displaced by
# (dp_c, dv_c), dp_c ~ 0.15 N(0, I), dv_c ~ 0.05 N(0, I) in the plane (E81 scale), both scaled by 0.7 until the team program of the regions
# with the terminal equality is feasible at the start. Every team refines the regions, so the teams are
# in formation, the data are coherent, the projection is the identity and Proposition quotient holds.
#
# Certificate (E63's evaluation, no re-condensing of the TeamMPC program): the condensed data at the measured state
# (E30's CProg from the stored base program), the gradient of J without the held edges, and per team the NNLS over
# the active ball normals in the metric Z'H_SZ (terminal rows eliminated), as cert63; eta_c per team and the Newton
# steps for the 2-means split.
#
# Arms (one job per seed runs every arm on one node):
#   exact        centralized MPC solved exactly (Clarabel, 1e-9, terminal equality): the reference cost
#   coord        centralized MPC with TeamMPC at its default accuracy
#   rt           centralized MPC warm started and stopped at the 200 ms period (E71's guard), first inputs projected
#   fix_<lab>    fixed teams classes, qs8, resp (k-means of 24 centralized responses per region at the qs8 count)
#   seq<m>_<eps> adaptive, the certificate on the control core every m samples (step time = solve + certificate)
#   par_<eps>    adaptive, the certificate of the plan of sample n on a second core while the team solve of n+1 runs
#                (the two cores are simulated with the measured times: each core's work is run in turn on one core,
#                and a result is used at the first sample after the core that computes it has finished)
#   Splits (selection: refined quotient program, its certificate operators, priming solve) run on the second core in
#   both modes and take effect ceil(time / period) samples after they are launched. A split applied at sample n'
#   refines the current teams, which refine the teams of the shifted plan, so (a) of Theorem adaptive holds.
# Per step (untimed): the true gap J(u) - J* (Clarabel, terminal equality, 1e-9), eta over gap when certified, the
# decrease W(n+1) <= W(n) - l(n) with W the condensed cost of the team plan.
#
#   E103B_N=256 E103B_SEEDS=1 julia --project=env scripts/resolution/experiments/e103b_amortized.jl
#   E103B_MODE=merge E103B_PARTDIR=<parts> E103B_OUT=<json> julia --project=env .../e103b_amortized.jl

const MODE103B = get(ENV, "E103B_MODE", "run")
if MODE103B == "run"
    ENV["E63_REG"] = "1"
    haskey(ENV, "BENCH_INSTANCE") || (ENV["BENCH_INSTANCE"] = "natural")
    include(get(ENV, "E103B_E70", joinpath(@__DIR__, "e70_adaptive_e103b.jl")))
    let src = read(get(ENV, "E103B_E71", joinpath(@__DIR__, "e71_budget.jl")), String)   # E79's k-means and DP allocation
        a = first(findfirst("function kmeans79_(", src)); b = first(findfirst("function main71c()", src)) - 1
        include_string(Main, src[a:b], "e71_budget.jl")
    end
else
    using JSON, Statistics, Printf
end

const N103B = parse(Int, get(ENV, "E103B_N", "256"))
const SEEDS103B = parse.(Int, split(get(ENV, "E103B_SEEDS", "1"), ","))
const STEPS103B = parse(Int, get(ENV, "E103B_STEPS", "30"))
const ARMS103B = split(get(ENV, "E103B_ARMS", "coord,rt,fix_classes,fix_qs8,fix_resp,seq1_0.005,seq2_0.005,seq3_0.005,seq5_0.005,par_0.005,par_0.002,par_0.02"), ",")
const ROUNDS103B = parse(Int, get(ENV, "E103B_ROUNDS", "12"))
const PARTDIR103B = get(ENV, "E103B_PARTDIR", joinpath(@__DIR__, "..", "..", "..", "results", "e103b_parts"))
const OUT103B = get(ENV, "E103B_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "e103b_amortized.json"))
const P103B = 0.2
const RESERVE103B = 1e-3; const GMIN103B = 2e-3; const GMAX103B = 0.05

if MODE103B == "run"

st103(v) = isempty(v) ? Dict{String,Any}() : Dict{String,Any}("median" => median(v), "max" => maximum(v), "min" => minimum(v), "n" => length(v))

"""An agent with the terminal equality Cf x_H = rf as a two-sided state polyhedron at t = H (deviation or not)."""
function termagent103(ag, rf, H)
    st = Union{Nothing,SM.Polyhedron}[nothing for _ in 1:H]
    st[H] = SM.Polyhedron([ag.Cf; -ag.Cf], [rf; -rf])
    return SM.Agent(ag.A[1], ag.B[1]; C = ag.C, Cr = ag.Cr, Q = ag.Q, R = ag.R, Cf = ag.Cf, Qf = ag.Qf, g = ag.g[1],
                    input = ag.input, state = st, kind = ag.kind)
end

termfleet103(fl, term) = SM.Fleet([termagent103(ag, term[i], fl.H) for (i, ag) in enumerate(fl.agents)], fl.edges;
                                  H = fl.H, targets = fl.targets, weights = fl.weights, select = fl.select)

"""Everything constant of one instance."""
function setup103(n, seed)
    inst = sq_instance(n, seed); n = length(inst.kinds)
    fl0 = sq_fleet(inst, DT63G, H63G, CONE63G)
    refs, term = refs_reg63(inst, fl0, H63G)
    fl = termfleet103(fl0, term)
    sc = scenario70(inst, seed, fl)
    cls = SM.canonical_partition(inst.class); K = maximum(cls)
    rng = Xoshiro(103_200 + seed)
    dp = [0.15 .* randn(rng, 2) for _ in 1:K]; dv = [0.05 .* randn(rng, 2) for _ in 1:K]
    start(a) = [fl.agents[i].nx == 6 ? [inst.slots[i] + [a .* dp[cls[i]]; 1.5]; [a .* dv[cls[i]]; 0.0]] : [inst.slots[i][1:2] + a .* dp[cls[i]]; a .* dv[cls[i]]] for i in 1:n]
    cf = cfleet63(fl0, H63G; terminal = :equality); Kc = Cons63(cf, CONE63G)
    x0 = start(1.0)
    base = CProg(cf, CData(x0, refs, term))
    H0b = H0blk30(cf); Hb = sparse(H0b + base.A' * base.Wd * base.A)
    # the start must make the team program of the regions feasible (Theorem closedloop): shrink the offsets by 0.7
    # until the program with the terminal equality and the region teams held is feasible at x0
    scale = 1.0
    for _ in 1:12
        P = CProg(base, CData(x0, refs, term)); _, hq, c = quad63(P, Hb)
        s = solve63(Hb, hq, c, Kc, teamZ63(cf, cls); E = P.E, e = P.e)
        s.status in ("SOLVED", "ALMOST_SOLVED") && break
        scale *= 0.7; x0 = start(scale)
    end
    return (inst = inst, n = n, fl = fl, sc = sc, cls = cls, x0 = x0, refs = refs, term = term, cf = cf, K = Kc,
            base = base, H0b = H0b, Hb = Hb, scale = scale)
end

"""The certificate operators of a partition (E63's, terminal rows eliminated)."""
function certop103(I, lab)
    S = srows30(I.base, lab)
    return (ops = certops30(I.base, lab, S; restrict = true), rest = RestOp(I.base, S))
end

"""A team controller: the quotient program with the terminal equality in deviation coordinates."""
function team103(I, lab)
    Q = Quot51(I.sc, lab)
    _, _, tq = teamdata51(Q, I.sc, I.x0, I.refs, I.term)
    fq = Q.fleet
    fq2 = SM.Fleet([termagent103(ag, tq[c], fq.H) for (c, ag) in enumerate(fq.agents)], fq.edges;
                   H = fq.H, targets = fq.targets, weights = fq.weights, select = fq.select)
    Q2 = Quot51(fq2, Q.teams, Q.team, Q.Delta, Q.merged)
    return (Q = Q2, C = controller51(fq2), lab = SM.canonical_partition(Q.team))
end

"""Per-team certificate at the stacked plan u from the measured state x (E63: data at x, then cert63 per team)."""
function cert103b(I, co, x, u; tol = 1e-6)
    cf = I.cf; H = cf.spec.H
    P = CProg(I.base, CData(x, I.refs, I.term))
    g0 = grad_rest30(co.rest, P, u)
    etac = zeros(length(co.ops)); d = zeros(length(u))
    for (o, op) in enumerate(co.ops)
        y0 = op.R * g0[op.cols]; val = 0.5 * dot(y0, y0); yb = y0
        normals = Tuple{Vector{Int},Vector{Float64}}[]; off = 0
        for i in op.members
            nu = cf.nus[i]; um = cf.agents[i].umax
            for t in 0:(H-1)
                ui = u[uidx(cf, i, t)]; nz = norm(ui)
                nz >= (1 - tol) * um && push!(normals, (collect(off + t * nu .+ (1:nu)), ui / nz))
            end
            off += nu * H
        end
        if !isempty(normals)
            Y = zeros(size(op.R, 1), length(normals))
            for (k, (cc, w)) in enumerate(normals); mul!(view(Y, :, k), view(op.R, :, cc), w); end
            cc = max.(nnls30(Y' * Y, -(Y' * y0)), 0.0); yc = y0 + Y * cc
            v = 0.5 * dot(yc, yc); v < val && (val = v; yb = yc)
        end
        etac[o] = val; d[op.cols] .= -(op.R' * yb)
    end
    return etac, d, P
end

"""The true values at x (untimed): J(u) and J* (Clarabel, terminal equality)."""
function truth103(I, x, u)
    P = CProg(I.base, CData(x, I.refs, I.term)); _, hq, c = quad63(P, I.Hb)
    full = solve63(I.Hb, hq, c, I.K, nothing; E = P.E, e = P.e)
    return J63(I.Hb, hq, c, u), full.J, full.status, maximum(abs.(P.E * u - P.e); init = 0.0)
end

stage103(I, x, ua, x1) = (l = sq_stage(I.fl, x, ua, I.refs); (l[1] - l[2]) + sq_stage(I.fl, x1, nothing, I.refs)[2])
"""
Make a team plan meet the terminal equality exactly (the solver meets it to its tolerance, about 1e-6, which
matters once J* is small): per team, the minimum-norm correction of its inputs at the instants whose ball is not
active, then the radial projection onto the balls, three passes. Members of a team are in formation and share the
correction, so the plan stays a team plan.
"""
function fixterm103!(I, T, Uq, x)
    H = I.cf.spec.H; res = 0.0
    for (c, m) in enumerate(T.Q.teams)
        i = m[1]; ag = I.fl.agents[i]; Th = I.cf.Theta[i][H+1]; um = I.cf.agents[i].umax; nu = size(Uq[c], 1)
        xf = copy(x[i]); for _ in 1:H; xf = ag.A[1] * xf + ag.g[1]; end
        for _ in 1:3
            v = vec(Uq[c]); r = xf + Th * v - I.term[i]
            norm(r, Inf) <= 1e-13 && break
            free = [t for t in 0:(H-1) if norm(view(Uq[c], :, t + 1)) < (1 - 1e-9) * um]
            cols = reduce(vcat, [collect(t * nu .+ (1:nu)) for t in free]; init = Int[])
            isempty(cols) && break
            M = Th[:, cols]; v[cols] .-= M' * ((M * M') \ r)
            Uq[c] .= reshape(v, nu, H)
            for t in 1:H; nb = norm(view(Uq[c], :, t)); nb > um && (Uq[c][:, t] .*= um / nb); end
        end
        res = max(res, norm(xf + Th * vec(Uq[c]) - I.term[i], Inf))
    end
    return res
end

liftU103(T, U) = reduce(vcat, [vec(U[T.Q.team[i]]) for i in eachindex(T.Q.team)])

"""Split teams with the largest eta_c until they cover `excess`, each by 2-means of its members' Newton steps."""
function split103b(I, lab, etac, d, excess, rng)
    Uc = [cholesky(Symmetric(Matrix(I.cf.H0[i]))).U for i in 1:I.n]
    new = copy(lab); nxt = maximum(lab); cov = 0.0; ns = 0
    mem = [findall(==(c), lab) for c in 1:maximum(lab)]
    for c in sortperm(etac; rev = true)
        (cov >= excess || etac[c] <= 0) && break
        m = mem[c]; length(m) < 2 && continue
        a, _ = kmeans79_(Matrix(reduce(vcat, ((Uc[i] * d[ucols(I.cf, i)])' for i in m))), 2, rng)
        nxt += 1; new[m[a .== 2]] .= nxt; cov += etac[c]; ns += 1
    end
    return SM.canonical_partition(new), ns
end

"""A team arm. kind :fixed, :seq (certificate on the control core every m samples) or :par (second core)."""
function teamarm103(I, lab0, Jref; kind::Symbol, m::Int = 1, eps::Float64 = NaN, steps = STEPS103B, seed = 1)
    GC.gc(); rng = Xoshiro(1031 + seed)
    adapt = kind != :fixed
    T = team103(I, lab0); co = certop103(I, T.lab); lab = T.lab
    x = [copy(v) for v in I.x0]; cost = 0.0; rec = Dict{String,Any}[]
    pending = nothing; core2_free = 0.0                     # time (in s from the start of the loop) the second core is free
    cert_due = nothing                                      # a certificate on the second core: (ready sample, etac, d, J, k)
    for k in 0:(steps-1)
        now = k * P103B
        swapped = false
        if pending !== nothing && k >= pending.ready
            T = pending.T; co = pending.co; lab = T.lab; pending = nothing; swapped = true
        end
        t0 = time_ns()
        xq, rq, tq = teamdata51(T.Q, I.sc, x, I.refs, I.term)
        info = SM.step!(T.C, xq, rq; terminal = tq)
        Uq = [copy(v) for v in SM.trajectories(T.C.fp, SM.plan(T.C))[2]]
        fixterm103!(I, T, Uq, x)
        tsolve = (time_ns() - t0) / 1e9
        u = liftU103(T, Uq)
        tcert = 0.0; certified_now = false; etac = nothing; d = nothing; Jp = NaN
        docert = adapt && (k == 0 || (kind == :seq && k % m == 0) || (kind == :par && core2_free <= now + tsolve))
        if docert
            tc0 = time_ns(); etac, d, P = cert103b(I, co, x, u); tc = (time_ns() - tc0) / 1e9
            _, hq, c = quad63(P, I.Hb); Jp = J63(I.Hb, hq, c, u)
            tcert = tc; certified_now = true
        end
        # step 0: the offline initialization, untimed, splits in the sample until certified
        ns = 0; tsel = 0.0; launched = false; rounds = 0
        if adapt && k == 0
            while sum(etac) > eps * abs(Jp) && rounds < ROUNDS103B
                lab2, s = split103b(I, lab, etac, d, sum(etac) - eps * abs(Jp) / 2, rng)
                s == 0 && break
                T = team103(I, lab2); co = certop103(I, T.lab); lab = T.lab; ns += s; rounds += 1
                xq, rq, tq = teamdata51(T.Q, I.sc, x, I.refs, I.term)
                info = SM.step!(T.C, xq, rq; terminal = tq)
                Uq = [copy(v) for v in SM.trajectories(T.C.fp, SM.plan(T.C))[2]]; fixterm103!(I, T, Uq, x)
                u = liftU103(T, Uq)
                etac, d, P = cert103b(I, co, x, u); _, hq, c = quad63(P, I.Hb); Jp = J63(I.Hb, hq, c, u)
            end
            core2_free = now + P103B
        elseif docert && pending === nothing && sum(etac) > eps * abs(Jp)
            tsel = @elapsed begin
                lab2, ns = split103b(I, lab, etac, d, sum(etac) - eps * abs(Jp) / 2, rng)
                if ns > 0
                    T2 = team103(I, lab2); co2 = certop103(I, T2.lab)
                    xq2, rq2, tq2 = teamdata51(T2.Q, I.sc, x, I.refs, I.term)
                    SM.step!(T2.C, xq2, rq2; terminal = tq2)
                end
            end
            if ns > 0
                launched = true
                # second-core work: (par) the certificate, then the selection; (seq) the selection
                start = kind == :par ? max(core2_free, now + tsolve) : now + tsolve + tcert
                fin = start + (kind == :par ? tcert : 0.0) + tsel
                core2_free = fin
                pending = (T = T2, co = co2, ready = max(k + 1, ceil(Int, fin / P103B - 1e-12)))
            end
        end
        if kind == :par && docert && !launched && k > 0
            core2_free = max(core2_free, now + tsolve) + tcert
        end
        tctl = kind == :par ? tsolve : tsolve + tcert
        # evaluation (untimed)
        Jt, Js, sts, tres = truth103(I, x, u)
        gap = Jt - Js
        eta = certified_now ? sum(etac) : NaN
        ua = first63(I.cf, u); x1 = sq_plant(I.fl, x, ua); l = stage103(I, x, ua, x1)
        cost += l
        push!(rec, Dict{String,Any}("step" => k, "teams" => maximum(lab), "t_solve" => tsolve, "t_cert" => tcert, "t_ctl" => tctl,
            "t_select" => tsel, "launched" => launched, "swapped" => swapped, "splits" => ns, "rounds" => rounds,
            "certified" => certified_now, "eta_rel" => certified_now ? eta / abs(Jp) : nothing,
            "eta_over_gap" => (certified_now && gap > 1e-9 * abs(Js)) ? eta / gap : nothing,
            "W" => Jt, "Jstar" => Js, "gap_rel" => gap / abs(Js), "l" => l, "status" => string(info.status), "status_full" => sts, "term_res" => tres,
            "met" => tctl <= P103B))
        x = x1
        GC.gc()
    end
    cost += sq_stage(I.fl, x, nothing, I.refs)[1]
    # decrease check W(n+1) <= W(n) - l(n) (W the condensed cost of the applied team plan)
    dec = [rec[k+1]["W"] - (rec[k]["W"] - rec[k]["l"]) for k in 1:(length(rec)-1)]
    a = rec[2:end]; col(f) = [Float64(r[f]) for r in a if r[f] !== nothing]
    return Dict{String,Any}("kind" => string(kind), "m" => m, "eps" => eps, "closed_loop_cost" => cost, "cost_ratio" => cost / Jref,
        "t_ctl" => st103(col("t_ctl")), "t_solve" => st103(col("t_solve")), "t_cert" => st103([r["t_cert"] for r in a if r["certified"]]),
        "t_select" => st103([r["t_select"] for r in a if r["launched"]]), "met_frac" => count(r -> r["met"], a) / length(a),
        "teams" => [r["teams"] for r in rec], "splits" => sum(r["splits"] for r in a; init = 0), "splits0" => rec[1]["splits"],
        "launches" => count(r -> r["launched"], a), "certified_frac" => count(r -> r["certified"], a) / length(a),
        "eta_over_gap" => st103(col("eta_over_gap")), "gap_rel" => st103([r["gap_rel"] for r in rec]),
        "eta_below_gap" => count(r -> r["eta_over_gap"] !== nothing && r["eta_over_gap"] < 1 - 1e-6, rec),
        "decrease_slack_rel_max" => maximum(dec) / abs(rec[1]["W"]), "steps" => rec)
end

"""Exact centralized MPC (Clarabel to 1e-9 with the terminal equality, every step): the reference closed-loop cost."""
function exact103(I; steps = STEPS103B)
    x = [copy(v) for v in I.x0]; cost = 0.0; rec = Dict{String,Any}[]
    for k in 0:(steps-1)
        P = CProg(I.base, CData(x, I.refs, I.term)); _, hq, c = quad63(P, I.Hb)
        s = solve63(I.Hb, hq, c, I.K, nothing; E = P.E, e = P.e)
        ua = first63(I.cf, s.u); x1 = sq_plant(I.fl, x, ua); l = stage103(I, x, ua, x1); cost += l
        push!(rec, Dict{String,Any}("step" => k, "W" => s.J, "l" => l, "status" => s.status, "t_ctl" => s.seconds)); x = x1
    end
    cost += sq_stage(I.fl, x, nothing, I.refs)[1]
    dec = [rec[k+1]["W"] - (rec[k]["W"] - rec[k]["l"]) for k in 1:(length(rec)-1)]
    return Dict{String,Any}("kind" => "exact", "closed_loop_cost" => cost, "cost_ratio" => 1.0, "t_ctl" => st103([r["t_ctl"] for r in rec[2:end]]),
                            "met_frac" => count(r -> r["t_ctl"] <= P103B, rec[2:end]) / (steps - 1),
                            "decrease_slack_rel_max" => maximum(dec) / abs(rec[1]["W"]), "steps" => rec)
end

"""Centralized arms: converged (:coord) or stopped at the period (:rt), on the full fleet with the terminal set."""
function central103(I, Jref; kind::Symbol, steps = STEPS103B)
    GC.gc()
    C = controller51(I.fl); x = [copy(v) for v in I.x0]; cost = 0.0; rec = Dict{String,Any}[]; over = Float64[]; pre = 0.0; post = 0.0
    for k in 0:(steps-1)
        t0 = time_ns()
        if kind == :rt && k > 0
            guard = isempty(over) ? GMIN103B : clamp(maximum(over[max(1, end - 9):end]), GMIN103B, GMAX103B)
            tl = max(P103B - pre - post - RESERVE103B - guard, 1e-6)
            C.solver.settings.time_limit = tl; C.solver.info.status = :solved
            info = SM.step!(C, x, I.refs; terminal = I.term)
            C.solver.settings.time_limit = Inf; push!(over, max(info.t_solve - tl, 0.0))
        else
            info = SM.step!(C, x, I.refs; terminal = I.term)
            if kind == :rt && k == 0
                s = C.solver.settings; s.polish = false; s.adaptive_rho = false; s.warm_reset_rho = false; s.method = :admm
            end
        end
        pre = info.t_construct + info.t_setup; post = info.t_lift
        tt = (time_ns() - t0) / 1e9
        U = SM.trajectories(C.fp, SM.plan(C))[2]; u = reduce(vcat, [vec(U[i]) for i in 1:I.n])
        uc, viol = clip26(I.sc, [copy(v) for v in info.u])
        r = Dict{String,Any}("step" => k, "t_ctl" => tt, "status" => string(info.status), "viol" => viol, "met" => tt <= P103B)
        if kind == :rt
            Jt, Js, _, _ = truth103(I, x, u); r["gap_rel"] = (Jt - Js) / abs(Js)
        end
        x1 = sq_plant(I.fl, x, uc); cost += stage103(I, x, uc, x1); x = x1
        push!(rec, r); GC.gc()
    end
    cost += sq_stage(I.fl, x, nothing, I.refs)[1]
    a = rec[2:end]
    o = Dict{String,Any}("kind" => string(kind), "closed_loop_cost" => cost, "t_ctl" => st103([r["t_ctl"] for r in a]),
        "met_frac" => count(r -> r["met"], a) / length(a), "viol" => st103([r["viol"] for r in a]),
        "unsolved" => count(r -> r["status"] != "solved", a), "steps" => rec)
    Jref === nothing || (o["cost_ratio"] = cost / Jref)
    kind == :rt && (o["gap_rel"] = st103([r["gap_rel"] for r in rec]))
    return o
end

"""Response teams (E79/E71c): k-means within each region of the centralized responses (terminal equality, no limits)
to 24 random coherent starts, in the own-Hessian metric, at the qs8 team count."""
function resp103(I, seed, Kb)
    P0 = CProg(I.base, CData(I.x0, I.refs, I.term)); E = P0.E
    N = size(I.Hb, 1); KKT = lu([I.Hb E'; E spzeros(size(E, 1), size(E, 1))])
    Uc = [cholesky(Symmetric(Matrix(I.cf.H0[i]))).U for i in 1:I.n]
    Y = [Float64[] for _ in 1:I.n]; K = maximum(I.cls)
    for r in 1:24
        rng = Xoshiro(79_000_000 + 1000 * (10_000 + seed) + r)
        dp = [0.15 .* randn(rng, 2) for _ in 1:K]; dv = [0.05 .* randn(rng, 2) for _ in 1:K]
        x0 = [I.fl.agents[i].nx == 6 ? [I.inst.slots[i] + [dp[I.cls[i]]; 1.5]; [dv[I.cls[i]]; 0.0]] : [I.inst.slots[i][1:2] + dp[I.cls[i]]; dv[I.cls[i]]] for i in 1:I.n]
        P = CProg(I.base, CData(x0, I.refs, I.term)); _, hq, _ = quad63(P, I.Hb)
        u = (KKT \ [-hq; P.e])[1:N]
        for i in 1:I.n; append!(Y[i], Uc[i] * u[ucols(I.cf, i)] ./ sqrt(24)); end
    end
    return alloc79_(I.cls, mm -> reduce(vcat, (Y[i]' for i in mm)), Kb, Xoshiro(79 + seed))
end

function run103b(seed; n = N103B, steps = STEPS103B, arms = ARMS103B, quiet = false)
    I = setup103(n, seed)
    res = Dict{String,Any}("n_requested" => n, "seed" => seed, "n" => I.n, "classes" => maximum(I.cls), "start_scale" => I.scale, "steps" => steps,
                           "period" => P103B, "arms" => Dict{String,Any}())
    A = res["arms"]
    ex = exact103(I; steps = steps); Jc = ex["closed_loop_cost"]; A["exact"] = ex
    pr(key, o) = quiet || !haskey(o, "cost_ratio") || (@printf("  %-12s ratio %.5f ms med %6.1f max %6.1f met %.2f teams %s splits %s eta/gap %s gap med %s\n",
        key, o["cost_ratio"], 1e3 * o["t_ctl"]["median"], 1e3 * o["t_ctl"]["max"], o["met_frac"],
        haskey(o, "teams") ? "$(o["teams"][1])->$(o["teams"][end])" : "-", string(get(o, "splits", "-")),
        haskey(o, "eta_over_gap") && haskey(o["eta_over_gap"], "median") ? @sprintf("%.2f", o["eta_over_gap"]["median"]) : "-",
        haskey(o, "gap_rel") ? @sprintf("%.1e", o["gap_rel"]["median"]) : "-"); flush(stdout))
    pr("exact", ex)
    labs = Dict{String,Vector{Int}}()
    for arm in arms
        A[arm] = try
            if arm == "coord"
                central103(I, Jc; kind = :coord, steps = steps)
            elseif arm == "rt"
                central103(I, Jc; kind = :rt, steps = steps)
            elseif startswith(arm, "fix_")
                ch = arm[5:end]
                lab = ch == "resp" ? resp103(I, seed, maximum(sq_teams(I.inst, "qs8", seed)[1])) : sq_teams(I.inst, ch, seed)[1]
                teamarm103(I, lab, Jc; kind = :fixed, steps = steps, seed = seed)
            else
                mode, e = split(arm, "_"); epsv = parse(Float64, e)
                kind = startswith(mode, "par") ? :par : :seq
                mm = kind == :seq ? parse(Int, mode[4:end]) : 1
                teamarm103(I, I.cls, Jc; kind = kind, m = mm, eps = epsv, steps = steps, seed = seed)
            end
        catch err
            @printf("  %s FAILED: %s\n", arm, sprint(showerror, err)[1:min(end, 400)]); flush(stdout)
            Dict{String,Any}("error" => sprint(showerror, err)[1:min(end, 2000)])
        end
        pr(arm, A[arm])
    end
    return res
end

clean103(x) = x
clean103(x::AbstractFloat) = isfinite(x) ? x : nothing
clean103(x::AbstractDict) = Dict{String,Any}(string(k) => clean103(v) for (k, v) in x)
clean103(x::AbstractVector) = Any[clean103(v) for v in x]

function main103b()
    BLAS.set_num_threads(1); mkpath(PARTDIR103B)
    get(ENV, "E103B_WARMUP", "1") == "1" && run103b(1; n = 48, steps = 3, quiet = true)
    for seed in SEEDS103B
        res = run103b(seed)
        res["meta"] = Dict("host" => gethostname(), "job" => get(ENV, "SLURM_JOB_ID", ""), "cpu" => Sys.cpu_info()[1].model,
                           "affinity" => get(ENV, "E71_AFFINITY", ""))
        path = joinpath(PARTDIR103B, @sprintf("e103b_n%d_seed%d.json", N103B, seed))
        open(io -> JSON.print(io, clean103(res), 1), path, "w"); println("wrote $path"); flush(stdout)
    end
end

end # run

function merge103b()
    parts = [JSON.parsefile(joinpath(PARTDIR103B, f)) for f in readdir(PARTDIR103B) if endswith(f, ".json")]
    md(v) = isempty(v) ? nothing : Dict("median" => median(v), "min" => minimum(v), "max" => maximum(v))
    rows = Dict{String,Any}()
    for p in parts, (arm, o) in p["arms"]
        haskey(o, "cost_ratio") || continue
        r = get!(rows, "n$(p["n_requested"])_$arm", Dict{String,Any}("n_requested" => p["n_requested"], "arm" => arm, "runs" => Any[]))
        S = o["steps"][2:end]
        run = Dict{String,Any}("seed" => p["seed"], "n" => p["n"], "cost_ratio" => o["cost_ratio"], "met_frac" => o["met_frac"],
                               "ms_med" => 1e3 * median([s["t_ctl"] for s in S]), "ms_max" => 1e3 * maximum(s["t_ctl"] for s in S))
        for f in ("splits", "splits0", "launches", "certified_frac", "eta_below_gap", "decrease_slack_rel_max")
            haskey(o, f) && (run[f] = o[f])
        end
        haskey(o, "teams") && (run["teams"] = o["teams"])
        haskey(o, "gap_rel") && haskey(o["gap_rel"], "median") && (run["gap_med"] = o["gap_rel"]["median"]; run["gap_max"] = o["gap_rel"]["max"])
        haskey(o, "eta_over_gap") && haskey(o["eta_over_gap"], "median") && (run["eta_over_gap_med"] = o["eta_over_gap"]["median"])
        for (f, g) in (("t_cert", "cert_ms_med"), ("t_select", "select_ms_med"), ("t_solve", "solve_ms_med"))
            haskey(o, f) && haskey(o[f], "median") && (run[g] = 1e3 * o[f]["median"])
        end
        push!(r["runs"], run)
    end
    for (key, r) in rows
        R = r["runs"]; r["seeds"] = length(R); r["n_median"] = median([x["n"] for x in R])
        for f in ("cost_ratio", "met_frac", "ms_med", "ms_max", "gap_med", "gap_max", "eta_over_gap_med", "certified_frac",
                  "cert_ms_med", "select_ms_med", "solve_ms_med", "decrease_slack_rel_max", "splits")
            v = [Float64(x[f]) for x in R if haskey(x, f) && x[f] !== nothing]
            isempty(v) || (r[f] = md(v))
        end
        if all(haskey(x, "teams") for x in R)
            L = minimum(length(x["teams"]) for x in R)
            r["teams_per_step_median"] = [median([x["teams"][s] for x in R]) for s in 1:L]
            r["splits_total"] = sum(get(x, "splits", 0) for x in R); r["eta_below_gap_total"] = sum(get(x, "eta_below_gap", 0) for x in R)
        end
    end
    pair = Dict{String,Any}()
    for p in parts
        A = p["arms"]; ex(a) = haskey(A, a) && haskey(A[a], "cost_ratio") ? A[a]["cost_ratio"] - 1 : nothing
        for a in keys(A), b in ("fix_resp", "fix_qs8", "fix_classes", "rt")
            (startswith(a, "seq") || startswith(a, "par")) || continue
            ea, eb = ex(a), ex(b); (ea === nothing || eb === nothing || ea <= 0) && continue
            push!(get!(pair, "n$(p["n_requested"])_$(a)_vs_$b", Float64[]), eb / ea)
        end
    end
    out = Dict("experiment" => "E103b certified adaptive teams with an amortized certificate (every m samples on the control core, or on a second core), nominal loop of Theorem closedloop (regulation, terminal equality, regions start displaced in formation), irregular formation",
               "period_ms" => 1e3 * P103B, "rows" => rows,
               "start_scale" => Dict("n$(p["n_requested"])_seed$(p["seed"])" => p["start_scale"] for p in parts),
               "start_scale_note" => "factor applied to the start displacement (1.0, or 0.7 when the team program of the regions with the terminal equality was infeasible at the unscaled start)",
               "excess_ratio_fixed_over_adaptive" => Dict(k => md(v) for (k, v) in pair))
    open(io -> JSON.print(io, out, 1), OUT103B, "w"); println("wrote $OUT103B")
    for key in sort(collect(keys(rows)))
        r = rows[key]; g(f) = haskey(r, f) ? r[f]["median"] : NaN
        tp = get(r, "teams_per_step_median", [NaN])
        @printf("%-22s ratio %.5f ms %6.1f max %6.1f met %.2f teams %4.0f->%4.0f splits %s gap %.1e eta/gap %.2f cert ms %.1f sel ms %.0f dec %.1e\n", key,
                g("cost_ratio"), g("ms_med"), haskey(r, "ms_max") ? r["ms_max"]["max"] : NaN, g("met_frac"), tp[1], tp[end],
                string(get(r, "splits_total", "-")), g("gap_med"), g("eta_over_gap_med"), g("cert_ms_med"), g("select_ms_med"),
                haskey(r, "decrease_slack_rel_max") ? r["decrease_slack_rel_max"]["max"] : NaN)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE103B == "merge" ? merge103b() : main103b()
end
