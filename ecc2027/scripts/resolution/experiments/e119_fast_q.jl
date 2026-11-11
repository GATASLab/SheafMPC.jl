# E119: the certificate's linear term q at the measured state, computed fast, on E106's irregular fleets.
#
# E106 (e102_irregular4096.jl -> arm71 :team, team_resp_<classes> = one team per region, E71_CERT_IN_STEP=1, shift rule)
# times the team solve and the certificate eta = kktE71(E, S, q, u_hat), but q, the linear term of the condensed
# program J(u) = u'Hu/2 + q'u + c at the measured state, is computed untimed by qc71 (~350 ms, E118's t_q).
#
# q is, per vehicle i and input instant s = 0..H-1,
#     q_{i,s} = sum_{t > s} (M_{i,t}[:, s])' lambda_{i,t},      M_{i,t}[:, s] = A_{t-1} ... A_{s+1} B_s,
#     lambda_{i,t} = Cr' Q (Cr f_{i,t} - r_{i,t})             (t = 1..H-1)
#                  + [t = H] Cf' Qf (Cf f_{i,H} - r_f)
#                  + sum_{edges k = (i,j), t} w_{k,t} (-(S_k C_i))' b_{k,t}  + sum_{edges k = (j,i), t} w_{k,t} (S_k C_i)' b_{k,t},
#     b_{k,t} = S_k (C_j f_{j,t} - C_i f_{i,t} - target_{k,t}),
# f_{i,t} the free response (u = 0) of vehicle i from its measured state. fastq computes exactly this sum by the
# adjoint recursion p_{i,H} = lambda_{i,H}, p_{i,t} = lambda_{i,t} + A_t' p_{i,t+1}, q_{i,s} = B_s' p_{i,s+1}:
# O(n H nx^2 + |E| H p) flops, no fleet-sized or horizon-sized (nx x nu H) matrices, allocation free (preallocated
# buffers, hand-written small mat-vecs). Same model, same data; only the order of the floating-point sums differs.
#
# Per seed (E106's seeds 1..5, n = 4096 slots -> largest connected part, one team per region), one closed loop of
# E106's fixed-team arm (team solve + kktE71 timed, E106's shift rule), and at every sample (untimed, as in E106):
# fastq and qc71 at the measured state, both timed, and the check max|fastq - qc71| / max|qc71| <= 1e-10.
# Post hoc: on-time fraction if fastq's time is added to each step. Arm "inloop" (E119_INLOOP=1): the same loop with
# fastq timed inside the step (it then feeds the step time and the shift rule): a real closed-loop rerun.
# No tight reference solve (E106's untimed true-gap evaluation is not needed for q or the step time).
#
#   E119_N=64 E119_SEEDS=1 E119_STEPS=3 E119_WARMUP=0 julia --project=env scripts/resolution/experiments/e119_fast_q.jl
#   E119_MODE=merge E119_PARTDIR=<dir> E119_OUT=results/e119_fast_q.json julia --project=env scripts/resolution/experiments/e119_fast_q.jl

const MODE119 = get(ENV, "E119_MODE", "run")
using Printf, JSON, Statistics
for (k, v) in ("BENCH_INSTANCE" => "natural", "BENCH_FLEET" => "dronecar", "BENCH_DISC" => "zoh",
               "E102_FALLBACK" => "shift", "E71_FALLBACK" => "shift", "E71_CERT_IN_STEP" => "1")
    haskey(ENV, k) || (ENV[k] = v)
end
const ROOT119 = joinpath(@__DIR__, "..", "..", "..")
const PARTDIR119 = get(ENV, "E119_PARTDIR", joinpath(ROOT119, "results", "parts119"))
const OUT119 = get(ENV, "E119_OUT", joinpath(ROOT119, "results", "e119_fast_q.json"))
const TOL119 = 1e-10

if MODE119 == "run"
include(joinpath(@__DIR__, "e102_irregular4096.jl"))         # e71_budget.jl (qc71, Ev71, hs71, kktE71), e63_time.jl, E51
import SHA
@assert ENV["BENCH_INSTANCE"] == "natural" && ENV["BENCH_FLEET"] == "dronecar" && ENV["BENCH_DISC"] == "zoh"
@assert FALLBACK71 == "shift" && CERTSTEP71

const N119 = parse(Int, get(ENV, "E119_N", "4096"))
const SEEDS119 = parse.(Int, split(get(ENV, "E119_SEEDS", "1"), ":"))
const STEPS119 = parse(Int, get(ENV, "E119_STEPS", "30"))
const REPS119 = parse(Int, get(ENV, "E119_REPS", "5"))
const INLOOP119 = get(ENV, "E119_INLOOP", "1") == "1"

# ------------------------------------------------------------------------------------------------------------------
# fastq: the structure (offline: references to every vehicle's matrices, Cr'Q, Cf'Qf, S_k C_i; buffers)
# ------------------------------------------------------------------------------------------------------------------
struct FastQ
    H::Int
    T::Array{Float64,3}                        # the fleet's edge targets, weights, presence, selections (same arrays)
    W::Matrix{Float64}
    Pr::BitMatrix
    Sel::Vector{Matrix{Float64}}
    off::Vector{Int}                           # n + 1 offsets
    nx::Vector{Int}
    nu::Vector{Int}
    A::Vector{Vector{Matrix{Float64}}}         # A[i][t+1] = A_t, t = 0..H-1
    B::Vector{Vector{Matrix{Float64}}}
    g::Vector{Vector{Vector{Float64}}}
    Cr::Vector{Matrix{Float64}}
    CrQ::Vector{Matrix{Float64}}               # Cr' Q   (nx x pr)
    Cf::Vector{Matrix{Float64}}
    CfQf::Vector{Matrix{Float64}}              # Cf' Qf
    ei::Vector{Int}
    ej::Vector{Int}
    Gi::Vector{Matrix{Float64}}                # S_k C_i
    Gj::Vector{Matrix{Float64}}                # S_k C_j
    F::Vector{Matrix{Float64}}                 # free response, nx x (H+1), column 1 = x0
    L::Vector{Matrix{Float64}}                 # lambda, nx x H
    e::Vector{Float64}                         # buffers
    b::Vector{Float64}
    p::Vector{Float64}
    pn::Vector{Float64}
end

function FastQ(fl, off)
    n = SM.nagents(fl); H = fl.H; ags = fl.agents
    at(v, t) = length(v) == 1 ? v[1] : v[t+1]                       # SM._at
    A = [[at(ag.A, t) for t in 0:(H-1)] for ag in ags]
    B = [[at(ag.B, t) for t in 0:(H-1)] for ag in ags]
    g = [[at(ag.g, t) for t in 0:(H-1)] for ag in ags]
    nx = [ag.nx for ag in ags]; nu = [ag.nu for ag in ags]
    ei = [e[1] for e in fl.edges]; ej = [e[2] for e in fl.edges]
    Gi = [fl.select[k] * ags[ei[k]].C for k in eachindex(fl.edges)]
    Gj = [fl.select[k] * ags[ej[k]].C for k in eachindex(fl.edges)]
    mx = maximum(nx); mr = maximum(max(size(ag.Cr, 1), size(ag.Cf, 1)) for ag in ags)
    mp = isempty(fl.select) ? 1 : maximum(size(S, 1) for S in fl.select)
    return FastQ(H, fl.targets, fl.weights, fl.present, fl.select, copy(off), nx, nu, A, B, g, [ag.Cr for ag in ags], [Matrix(ag.Cr' * ag.Q) for ag in ags],
                 [ag.Cf for ag in ags], [Matrix(ag.Cf' * ag.Qf) for ag in ags], ei, ej, Gi, Gj,
                 [zeros(nx[i], H + 1) for i in 1:n], [zeros(nx[i], H) for i in 1:n],
                 zeros(max(mr, size(fl.targets, 1))), zeros(mp), zeros(mx), zeros(mx))
end

"""The condensed linear term q (the vector of qc71 / SM.CondensedQP) at the measured states x0, into q."""
function fastq!(q::Vector{Float64}, Fq::FastQ, x0, refs, term)
    H = Fq.H; e = Fq.e; b = Fq.b; p = Fq.p; pn = Fq.pn
    T = Fq.T; Wt = Fq.W; Pr = Fq.Pr
    @inbounds for i in eachindex(Fq.F)
        F = Fq.F[i]; L = Fq.L[i]; nx = Fq.nx[i]; xi = x0[i]; R = refs[i]
        for a in 1:nx
            F[a, 1] = xi[a]
        end
        for t in 1:H                                               # f_t = A_{t-1} f_{t-1} + g_{t-1}
            At = Fq.A[i][t]; gt = Fq.g[i][t]
            for a in 1:nx
                F[a, t+1] = gt[a]
            end
            for c in 1:nx
                v = F[c, t]
                for a in 1:nx
                    F[a, t+1] += At[a, c] * v
                end
            end
        end
        Cr = Fq.Cr[i]; CrQ = Fq.CrQ[i]; pr = size(Cr, 1)
        for t in 1:(H-1)                                           # lambda_t = Cr'Q (Cr f_t - r_t)
            for a in 1:pr
                e[a] = -R[a, t+1]
            end
            for c in 1:nx
                v = F[c, t+1]
                for a in 1:pr
                    e[a] += Cr[a, c] * v
                end
            end
            for a in 1:nx
                s = 0.0
                for c in 1:pr
                    s += CrQ[a, c] * e[c]
                end
                L[a, t] = s
            end
        end
        Cf = Fq.Cf[i]; CfQf = Fq.CfQf[i]; pf = size(Cf, 1)         # lambda_H = Cf'Qf (Cf f_H - r_f)
        rf = term === nothing ? view(R, :, H + 1) : term[i]
        for a in 1:pf
            e[a] = -rf[a]
        end
        for c in 1:nx
            v = F[c, H+1]
            for a in 1:pf
                e[a] += Cf[a, c] * v
            end
        end
        for a in 1:nx
            s = 0.0
            for c in 1:pf
                s += CfQf[a, c] * e[c]
            end
            L[a, H] = s
        end
    end
    @inbounds for k in eachindex(Fq.ei)                            # formation edges
        i = Fq.ei[k]; j = Fq.ej[k]; Gi = Fq.Gi[k]; Gj = Fq.Gj[k]; S = Fq.Sel[k]
        Fi = Fq.F[i]; Fj = Fq.F[j]; Li = Fq.L[i]; Lj = Fq.L[j]
        pk = size(S, 1); p0 = size(S, 2); nxi = Fq.nx[i]; nxj = Fq.nx[j]
        for t in 1:H
            (Pr[k, t] && Wt[k, t] > 0) || continue
            w = Wt[k, t]
            for a in 1:pk                                          # b = S_k (C_j f_j - C_i f_i - target)
                s = 0.0
                for c in 1:p0
                    s -= S[a, c] * T[c, k, t]
                end
                for c in 1:nxj
                    s += Gj[a, c] * Fj[c, t+1]
                end
                for c in 1:nxi
                    s -= Gi[a, c] * Fi[c, t+1]
                end
                b[a] = w * s
            end
            for c in 1:nxi
                s = 0.0
                for a in 1:pk
                    s += Gi[a, c] * b[a]
                end
                Li[c, t] -= s
            end
            for c in 1:nxj
                s = 0.0
                for a in 1:pk
                    s += Gj[a, c] * b[a]
                end
                Lj[c, t] += s
            end
        end
    end
    @inbounds for i in eachindex(Fq.F)                             # adjoint: q_s = B_s' p_{s+1}
        L = Fq.L[i]; nx = Fq.nx[i]; nu = Fq.nu[i]; o = Fq.off[i]
        for a in 1:nx
            p[a] = L[a, H]
        end
        for s in (H-1):-1:0
            Bs = Fq.B[i][s+1]
            for c in 1:nu
                v = 0.0
                for a in 1:nx
                    v += Bs[a, c] * p[a]
                end
                q[o+s*nu+c] = v
            end
            s == 0 && break
            As = Fq.A[i][s+1]                                      # p_s = lambda_s + A_s' p_{s+1}
            for c in 1:nx
                v = L[c, s]
                for a in 1:nx
                    v += As[a, c] * p[a]
                end
                pn[c] = v
            end
            for a in 1:nx
                p[a] = pn[a]
            end
        end
    end
    return q
end

relerr119(a, b) = maximum(abs, a .- b) / max(maximum(abs, b), 1e-300)

# ------------------------------------------------------------------------------------------------------------------
# E106's fixed-team loop (arm71 :team with E71_CERT_IN_STEP=1 and the shift rule), q by both codes at every sample
# ------------------------------------------------------------------------------------------------------------------
"""One closed loop. inloop = false: E106's step (team solve + kktE71), fastq and qc71 untimed-in-step (timed
separately); inloop = true: fastq timed inside the step, before the certificate (step = team + fastq + kktE71)."""
function loop119(sc, E, S, lab, Fq; steps, inloop::Bool = false, reps = REPS119)
    GC.gc()
    fl = sc.fleet
    Q = Quot51(sc, lab); C = controller51(Q.fleet)
    x = start26(sc); cost = 0.0; rec = Dict{String,Any}[]; Uapp = nothing
    qf = zeros(E.off[end]); tr = zeros(reps)
    for k in 0:(steps-1)
        refs, term = references26(sc, k * sc.h)
        t0 = time_ns()
        xq, rq, tq = teamdata51(Q, sc, x, refs, term)
        info = SM.step!(C, xq, rq; terminal = tq)
        Uq = SM.trajectories(C.fp, SM.plan(C))[2]
        U = [copy(Uq[Q.team[i]]) for i in 1:sc.n]; u = [copy(info.u[Q.team[i]]) for i in 1:sc.n]; status = string(info.status)
        tteam = (time_ns() - t0) / 1e9
        tf0 = time_ns(); fastq!(qf, Fq, x, refs, term); tfq = (time_ns() - tf0) / 1e9
        # untimed below (except t_eta, as E106): reps of fastq, qc71, the check
        for r in 1:reps
            tr[r] = @elapsed fastq!(qf, Fq, x, refs, term)
        end
        tqc = @elapsed ((q, c) = qc71(fl, E.off, x, refs, term))
        err = relerr119(qf, q)
        err <= TOL119 || error(@sprintf("fastq disagrees with qc71 at step %d: max rel err %.3e", k, err))
        up = projE71!(stackE71(E, U), E)
        te = @elapsed (eta = kktE71(E, S, q, up))
        tt = tteam + te + (inloop ? tfq : 0.0)                      # E106: team + eta (q untimed)
        fallback = k > 0 && tt > PERIOD71 && Uapp !== nothing
        if fallback
            Uapp = [hcat(Ui[:, 2:end], Ui[:, end]) for Ui in Uapp]; u = [copy(Ui[:, 1]) for Ui in Uapp]
        else
            Uapp = [copy(Ui) for Ui in U]
        end
        uc, viol = clip26(sc, u)
        cost += stage_cost26(sc, x, uc, refs)
        push!(rec, Dict{String,Any}("step" => k, "t_team" => tteam, "t_eta" => te, "t_total" => tt, "t_fastq" => tfq,
            "t_fastq_reps" => copy(tr), "t_qc71" => tqc, "relerr" => err, "qnorm_inf" => maximum(abs, q), "eta" => eta,
            "met" => tt <= PERIOD71, "met_with_fastq" => (inloop ? tt : tt + tfq) <= PERIOD71, "fallback" => fallback,
            "status" => status, "viol" => viol))
        @printf("  %s step %2d team %6.1f eta %5.1f fastq %6.2f (reps min %6.2f) qc71 %7.1f ms tot %6.1f fb %d relerr %.2e\n",
                inloop ? "inloop" : "e106  ", k, 1e3 * tteam, 1e3 * te, 1e3 * tfq, 1e3 * minimum(tr), 1e3 * tqc, 1e3 * tt, fallback, err)
        flush(stdout)
        x = plant26(sc, x, uc)
        GC.gc()
    end
    refs, _ = references26(sc, steps * sc.h)
    cost += stage_cost26(sc, x, nothing, refs)
    a = rec[2:end]; col(f) = [Float64(r[f]) for r in a]
    tsum = col("t_total") .+ (inloop ? 0.0 : col("t_fastq"))
    added = inloop ? 0 : count(r -> r["t_total"] <= PERIOD71 < r["t_total"] + r["t_fastq"], a)
    return Dict{String,Any}("inloop" => inloop, "closed_loop_cost" => cost, "teams" => maximum(lab),
        "t_total" => st71(col("t_total")), "t_team" => st71(col("t_team")), "t_eta" => st71(col("t_eta")),
        "t_fastq" => st71(col("t_fastq")), "t_fastq_repmin" => st71([minimum(r["t_fastq_reps"]) for r in a]),
        "t_qc71" => st71(col("t_qc71")), "t_total_with_fastq" => st71(tsum),
        "relerr_max" => maximum(r["relerr"] for r in rec), "met_frac" => count(r -> r["met"], a) / length(a),
        "met_frac_with_fastq" => count(r -> r["met_with_fastq"], a) / length(a),
        "added_overruns" => added, "fallback_frac" => count(r -> r["fallback"], a) / length(a), "steps" => rec)
end

function meta119()
    f = @__FILE__
    return Dict{String,Any}("host" => gethostname(), "job" => get(ENV, "SLURM_JOB_ID", ""), "partition" => get(ENV, "SLURM_JOB_PARTITION", ""),
        "julia" => string(VERSION), "cpu" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(),
        "affinity" => get(ENV, "E119_AFFINITY", ""), "exclusive" => get(ENV, "E119_EXCLUSIVE", "0") == "1",
        "commit" => get(ENV, "E119_COMMIT", ""), "commit_note" => get(ENV, "E119_COMMIT_NOTE", ""),
        "script_sha256" => bytes2hex(SHA.sha256(read(f))), "teammpc" => teammpc52(),
        "env" => Dict(k => get(ENV, k, "") for k in ("BENCH_INSTANCE", "BENCH_FLEET", "BENCH_DISC", "E71_FALLBACK", "E71_CERT_IN_STEP")),
        "date" => string(Libc.strftime("%Y-%m-%dT%H:%M:%S", time())))
end

function run119(seed; n = N119, steps = STEPS119, path = nothing)
    t00 = time()
    inst = sq_instance(n, seed); nv = length(inst.kinds)
    lab, _ = sq_teams(inst, "classes", seed)
    @assert lab == SM.canonical_partition(inst.class)               # E106's team_resp at the class floor
    sc = scenario63(inst, seed, lab)
    E = Ev71(sc)                                                     # asserts qc71 == SM.CondensedQP at x(0)
    S = hs71(E, lab)
    Fq = FastQ(sc.fleet, E.off)
    # x(0) check against the package's CondensedQP directly
    x = start26(sc); refs, term = references26(sc, 0.0)
    cq = SM.CondensedQP(sc.fleet, x, refs; terminal = term); qf = zeros(E.off[end]); fastq!(qf, Fq, x, refs, term)
    err0 = relerr119(qf, cq.q); err0 <= TOL119 || error("fastq disagrees with CondensedQP at x(0): $err0")
    cq = nothing; GC.gc()
    res = Dict{String,Any}("seed" => seed, "n_requested" => n, "n" => nv, "edges" => length(inst.edges), "teams" => maximum(lab),
                           "inputs" => E.off[end], "steps" => steps, "period" => PERIOD71, "relerr_condensedqp_x0" => err0,
                           "arms" => Dict{String,Any}(), "load" => Dict{String,Any}("start" => loadavg26()))
    f106 = joinpath(get(ENV, "E119_E106_PARTS", ""), @sprintf("e102_n%d_seed%d.json", n, seed))
    if isfile(f106)
        d = JSON.parsefile(f106); key = "team_resp_$(maximum(lab))"
        if haskey(d["controllers"], key)
            o = d["controllers"][key]
            res["e106"] = Dict{String,Any}("closed_loop_cost" => o["closed_loop_cost"], "n" => d["n"],
                "t_total" => [r["t_total"] for r in o["steps"]], "fallback" => [r["fallback"] for r in o["steps"]])
        end
    end
    save() = path === nothing || (res["meta"] = meta119(); res["seconds"] = time() - t00;
                                  open(io -> JSON.print(io, clean71(res), 1), path, "w"); println("wrote $path"); flush(stdout))
    for (key, il) in (INLOOP119 ? [("e106", false), ("inloop", true)] : [("e106", false)])
        res["load"]["before_" * key] = loadavg26()
        o = loop119(sc, E, S, lab, Fq; steps = steps, inloop = il); res["arms"][key] = o
        @printf("seed %d n %d %-6s fastq ms med %.2f max %.2f | qc71 ms med %.1f | step ms med %.1f max %.1f met %.3f -> with fastq %.3f (added overruns %d) fb %.3f relerr %.1e cost %.6e\n",
                seed, nv, key, 1e3 * o["t_fastq"]["median"], 1e3 * o["t_fastq"]["max"], 1e3 * o["t_qc71"]["median"],
                1e3 * o["t_total"]["median"], 1e3 * o["t_total"]["max"], o["met_frac"], o["met_frac_with_fastq"], o["added_overruns"],
                o["fallback_frac"], o["relerr_max"], o["closed_loop_cost"])
        flush(stdout); save(); GC.gc()
    end
    res["load"]["end"] = loadavg26()
    save()
    return res
end

function main119()
    BLAS.set_num_threads(1); mkpath(PARTDIR119)
    get(ENV, "E119_WARMUP", "1") == "1" && run119(1; n = 64, steps = 3)      # compile every path
    for seed in SEEDS119
        run119(seed; path = joinpath(PARTDIR119, @sprintf("e119_n%d_seed%d.json", N119, seed)))
    end
end

end # run

function merge119()
    parts = sort([JSON.parsefile(joinpath(PARTDIR119, f)) for f in readdir(PARTDIR119) if endswith(f, ".json") && startswith(f, "e119_n4096")];
                 by = p -> p["seed"])
    ms(v) = 1e3 .* v
    rows = Dict{String,Any}()
    for key in ("e106", "inloop")
        ps = [p for p in parts if haskey(p["arms"], key)]
        isempty(ps) && continue
        os = [p["arms"][key] for p in ps]
        steps = vcat([o["steps"][2:end] for o in os]...)              # samples 1..29 of every seed (step 0 offline)
        tf = [r["t_fastq"] for r in steps]; tq = [r["t_qc71"] for r in steps]; tt = [r["t_total"] for r in steps]
        rows[key] = Dict{String,Any}("seeds" => [p["seed"] for p in ps], "samples" => length(steps),
            "fastq_ms_med" => median(ms(tf)), "fastq_ms_max" => maximum(ms(tf)), "fastq_ms_med_per_seed" => [1e3 * o["t_fastq"]["median"] for o in os],
            "fastq_ms_max_per_seed" => [1e3 * o["t_fastq"]["max"] for o in os],
            "fastq_repmin_ms_med" => median([1e3 * minimum(r["t_fastq_reps"]) for r in steps]),
            "qc71_ms_med" => median(ms(tq)), "qc71_ms_max" => maximum(ms(tq)), "speedup_med" => median(tq ./ tf),
            "relerr_max" => maximum(o["relerr_max"] for o in os), "relerr_x0_condensedqp_max" => maximum(p["relerr_condensedqp_x0"] for p in ps),
            "step_ms_med" => median(ms(tt)), "step_ms_max" => maximum(ms(tt)),
            "met_frac" => count(r -> r["met"], steps) / length(steps),
            "met_frac_with_fastq" => count(r -> r["met_with_fastq"], steps) / length(steps),
            "added_overruns" => sum(o["added_overruns"] for o in os), "fallback_frac" => count(r -> r["fallback"], steps) / length(steps),
            "closed_loop_cost_per_seed" => [o["closed_loop_cost"] for o in os])
    end
    # post hoc on E106's own per-step times (its parts), with this job's per-step fastq times
    e106 = [p for p in parts if haskey(p, "e106")]
    if !isempty(e106)
        tot = 0; ok = 0; ok0 = 0; added = 0; cr = Float64[]
        for p in e106
            t6 = p["e106"]["t_total"][2:end]; tf = [r["t_fastq"] for r in p["arms"]["e106"]["steps"][2:end]]
            tot += length(t6); ok += count(t6 .+ tf .<= 0.2); ok0 += count(t6 .<= 0.2); added += count((t6 .<= 0.2) .& (t6 .+ tf .> 0.2))
            push!(cr, p["arms"]["e106"]["closed_loop_cost"] / p["e106"]["closed_loop_cost"])
        end
        rows["e106_parts_posthoc"] = Dict{String,Any}("seeds" => [p["seed"] for p in e106], "samples" => tot,
            "met_frac_e106" => ok0 / tot, "met_frac_with_fastq" => ok / tot, "added_overruns" => added,
            "replay_cost_over_e106_cost" => cr,
            "note" => "E106's recorded per-step t_total (its HPG run) + this job's fastq time at the same sample index; post hoc sum")
    end
    out = Dict{String,Any}("experiment" => "E119: the certificate's linear term q (condensed program at the measured state) by fastq (free responses + adjoint recursion, sparse edge sums, no fleet-sized matrices) vs qc71, on E106's irregular fleets (largest connected part of 4096 random slots, one team per region, h = 0.2 s, H = 10). Per seed one closed loop of E106's fixed-team arm (team solve + kktE71 timed, shift rule); at every sample fastq and qc71 at the measured state, checked max|fastq - qc71|/max|qc71| <= 1e-10. 'with fastq' on the e106 row is a POST-HOC sum (step time + fastq time per sample), not a rerun; the inloop row is a closed-loop rerun with fastq inside the timed step.",
        "period_ms" => 200.0, "tolerance" => TOL119, "rows" => rows,
        "seeds_info" => [Dict{String,Any}("seed" => p["seed"], "n" => p["n"], "edges" => p["edges"], "teams" => p["teams"], "inputs" => p["inputs"],
                                          "meta" => p["meta"], "load" => p["load"], "seconds" => p["seconds"]) for p in parts],
        "jobs" => sort(unique([p["meta"]["job"] for p in parts])), "hosts" => sort(unique([p["meta"]["host"] for p in parts])),
        "cpus" => sort(unique([p["meta"]["cpu"] for p in parts])), "commits" => sort(unique([p["meta"]["commit"] for p in parts])),
        "script_sha256" => sort(unique([p["meta"]["script_sha256"] for p in parts])))
    open(io -> JSON.print(io, out, 1), OUT119, "w"); println("wrote $OUT119")
    for (k, r) in sort(collect(rows); by = first)
        println(k, ": ", JSON.json(Dict(kk => v for (kk, v) in r if !(v isa AbstractVector))))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE119 == "merge" ? merge119() : main119()
end
