# E79: choosing teams. On the random (natural) formation of E63/E65c, compare team choices at equal team count:
#   qs      greedy quasi-stable colouring (Kayali-Suciu variant of squads_dc.jl) with q; its team count is the budget
#   geo     k-means of the slots inside each class (regions), the budget allocated over the classes by DP
#   spec    spectral: rows of the bottom-K eigenvectors of L_G (K the budget), k-means inside each class, DP
#   plan    k-means of the centralized plan u* at the first data (one centralized solve with limits), in the metric
#           of the members' own Hessian H_c, inside each class, DP
#   resp    k-means of the sketched response embedding: the unconstrained centralized plans of E79_R random coherent
#           data sets stacked per vehicle (H_c metric), inside each class, DP (the mean-gap surrogate of the theory)
#   adapt   certificate-driven: from the classes, at the first data, split the teams with the largest terms of the
#           first bound of Thm. thm:qbound (B1x) along the top principal direction of their members' imbalances,
#           re-solving the team program after every round, until the budget is reached
#   classes one team per class (reference, fewer teams)
# Data (E79_DATA sets, all coherent along the classes and in formation): set 0 is E63's (start rigidly perturbed, lanes
# at t = 0); set j > 0 has its own random displacement per class and the lanes at t = 2j s, the start on the lane.
# Per (budget, choice, data): J* and the team optimum with ball limits (Clarabel 1e-9), gap; the first bound B1x and
# B1 of Thm. thm:qbound at the team plan; without limits (Cholesky): gap_free, and the theory's sandwich
#   K <= 2 gap_free <= (1 + 4 beta d) K,   K_S <= 2 gap_free <= (1 + 4 beta dbar) K_S,
# K = sum_c sum_{i in c} ||u*_i - mean_c u*||^2_{H_c} (u* the unconstrained plan), K_S = K + u*' F_S u* (F_S the
# intra-team formation Hessian), d the largest weighted degree, dbar the largest cross-team weight of a vehicle.
# Per choice: the defect delta^2 = max_{x in im chi} ||(I - Pi) L x||^2 / x'L x, the q achieved, the seconds to
# compute the teams.
#
#   E79_N=256 E79_SEEDS=1 julia --project=env scripts/resolution/experiments/e79_teamselect.jl
#   E79_MODE=merge E79_PARTDIR=... E79_OUT=results/e79_teamselect.json julia --project=env ...e79_teamselect.jl

ENV["BENCH_INSTANCE"] = "natural"
ENV["E63_REG"] = "0"
const MODE79 = get(ENV, "E79_MODE", "run")
include(joinpath(@__DIR__, "e63_gap.jl"))

const N79 = parse(Int, get(ENV, "E79_N", "256"))
const SEEDS79 = parse.(Int, split(get(ENV, "E79_SEEDS", "1"), ","))
const NDATA79 = parse(Int, get(ENV, "E79_DATA", "6"))
const Q79 = parse.(Float64, split(get(ENV, "E79_Q", "8,2"), ","))
const METHODS79 = split(get(ENV, "E79_METHODS", "qs,geo,spec,plan,resp,adapt"), ",")
const R79 = parse(Int, get(ENV, "E79_R", "24"))
const PARTDIR79 = get(ENV, "E79_PARTDIR", joinpath(@__DIR__, "..", "..", "..", "bench", "irregular", "results", "parts79"))
const OUT79 = get(ENV, "E79_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "e79_teamselect.json"))

# ---------------------------------------------------------------------------
# Data, k-means, budget allocation
# ---------------------------------------------------------------------------

"""Data set j: j = 0 E63's start and lanes at t = 0; j > 0 a random displacement per class, lanes at t = 2j."""
function data79(inst, fl, lanes, seed::Int, j::Int)
    t0 = 2.0 * j
    refs, term = sq_references(inst, lanes, fl, t0, DT63G, H63G)
    j == 0 && return CData(sq_start(inst, fl, seed)[1], refs, term)
    rng = Xoshiro(79_000_000 + 1000 * seed + j)
    K = maximum(inst.class)
    dp = [0.3 .* randn(rng, 2) for _ in 1:K]; dv = [0.15 .* randn(rng, 2) for _ in 1:K]
    x0 = map(eachindex(inst.kinds)) do i
        ag = fl.agents[i]; c = inst.class[i]
        p, v = sq_reference(inst, lanes, ag, i, t0)
        d = length(p)
        [p .+ [dp[c]; zeros(d - 2)]; v .+ [dv[c]; zeros(d - 2)]]
    end
    return CData(x0, refs, term)
end

"""Lloyd's k-means with k-means++ seeding, best of `restarts`; rows of X are the points. Returns (labels, cost)."""
function kmeans79(X::Matrix{Float64}, k::Int, rng; restarts::Int = 4, iters::Int = 60)
    m = size(X, 1)
    k >= m && return (collect(1:m), 0.0)
    k == 1 && (mu = vec(mean(X; dims = 1)); return (ones(Int, m), sum(abs2, X .- mu')))
    best = (Int[], Inf)
    for _ in 1:restarts
        C = zeros(k, size(X, 2)); C[1, :] .= X[rand(rng, 1:m), :]
        d2 = vec(sum(abs2, X .- C[1, :]'; dims = 2))
        for c in 2:k
            s = sum(d2)
            idx = s <= 0 ? rand(rng, 1:m) : findfirst(>=(rand(rng) * s), cumsum(d2))
            idx === nothing && (idx = m)
            C[c, :] .= X[idx, :]
            d2 .= min.(d2, vec(sum(abs2, X .- C[c, :]'; dims = 2)))
        end
        a = zeros(Int, m)
        for _ in 1:iters
            D = max.(vec(sum(abs2, X; dims = 2)) .+ vec(sum(abs2, C; dims = 2))' .- 2 .* (X * C'), 0.0)
            anew = [argmin(D[p, :]) for p in 1:m]
            for c in 1:k                                   # an empty cluster takes the farthest point
                if !any(==(c), anew)
                    far = argmax([D[p, anew[p]] for p in 1:m]); anew[far] = c
                end
            end
            anew == a && break
            a = anew
            for c in 1:k
                C[c, :] .= vec(mean(X[a .== c, :]; dims = 1))
            end
        end
        cost = sum(sum(abs2, X[p, :] .- C[a[p], :]) for p in 1:m)
        cost < best[2] && (best = (copy(a), cost))
    end
    return best
end

"""Teams of total count Kb refining the classes: k-means per class for every count, counts chosen by DP."""
function alloc79(cls::Vector{Int}, emb::Function, Kb::Int, rng)
    cs = sort(unique(cls)); mem = [findall(==(c), cls) for c in cs]
    sols = Vector{Vector{Tuple{Vector{Int},Float64}}}(undef, length(cs))
    for (a, m) in enumerate(mem)
        X = Matrix{Float64}(emb(m))
        sols[a] = [kmeans79(X, j, rng) for j in 1:length(m)]
    end
    # DP over classes: best[a][K] the least cost of classes 1..a with K teams
    nc = length(cs); INF = Inf
    best = fill(INF, nc + 1, Kb + 1); arg = zeros(Int, nc + 1, Kb + 1); best[1, 1] = 0.0
    for a in 1:nc, K in 0:Kb
        best[a, K+1] == INF && continue
        for j in 1:length(mem[a])
            K + j <= Kb || break
            v = best[a, K+1] + sols[a][j][2]
            v < best[a+1, K+j+1] && (best[a+1, K+j+1] = v; arg[a+1, K+j+1] = j)
        end
    end
    @assert best[nc+1, Kb+1] < INF "budget $Kb infeasible for $(nc) classes"
    lab = zeros(Int, length(cls)); K = Kb; nxt = 0
    for a in nc:-1:1
        j = arg[a+1, K+1]
        lab[mem[a]] .= nxt .+ sols[a][j][1]; nxt += j; K -= j
    end
    return SM.canonical_partition(lab)
end

# ---------------------------------------------------------------------------
# Graph quantities
# ---------------------------------------------------------------------------

function laplacian79(n, edges, w)
    I_ = Int[]; J_ = Int[]; V_ = Float64[]
    for ((i, j), x) in zip(edges, w)
        append!(I_, (i, j, i, j)); append!(J_, (i, j, j, i)); append!(V_, (x, x, -x, -x))
    end
    return sparse(I_, J_, V_, n, n)
end

"""delta^2 = max over x in im chi of ||(I - Pi) L x||^2 / (x'L x)."""
function defect79(L, lab)
    n = length(lab); k = maximum(lab)
    chi = sparse(1:n, lab, ones(n), n, k)
    sz = vec(sum(chi; dims = 1))
    LX = Matrix(L * chi)
    D = LX .- chi * ((chi' * LX) ./ sz)
    A = Symmetric(D' * D); B = Symmetric(Matrix(chi' * LX))
    e = eigen(B); keep = e.values .> 1e-10 * maximum(e.values)
    Z = e.vectors[:, keep] ./ sqrt.(e.values[keep])'
    return eigmax(Symmetric(Z' * A * Z))
end

# ---------------------------------------------------------------------------
# Certificate-driven splitting (adapt)
# ---------------------------------------------------------------------------

"""Per team: the B1x term and the members' whitened imbalances v_i = U_c^{-T} G' (f_i - fbar_c) (rows)."""
function terms79(P::CProg, qs, u)
    cf = P.cf; H = cf.spec.H; lab = qs.lab; n = length(lab)
    R = P.A * u .- P.b
    dpos(i) = size(cf.agents[i].Ct, 1)
    f = [zeros(dpos(i) * H) for i in 1:n]
    for e in qs.cross
        (i, j) = cf.edges[e]; we = qs.w[e]
        Li = cf.Me[e][1] * cf.agents[i].Ct'; Lj = cf.Me[e][2] * cf.agents[j].Ct'
        for t in 1:H
            rt = R[P.rowof[(e, t)]]
            f[i][((t-1)*dpos(i)+1):(t*dpos(i))] .-= we .* (Li' * rt)
            f[j][((t-1)*dpos(j)+1):(t*dpos(j))] .+= we .* (Lj' * rt)
        end
    end
    term = zeros(length(qs.mem)); V = Vector{Matrix{Float64}}(undef, length(qs.mem))
    for (c, m) in enumerate(qs.mem)
        fbar = sum(f[i] for i in m) / length(m)
        Vc = reduce(hcat, (qs.Fc[c].L \ (qs.G[i]' * (f[i] - fbar)) for i in m))'
        V[c] = Matrix(Vc); term[c] = 0.5 * sum(abs2, Vc)
    end
    return term, V
end

function adapt79(cf, base, Hb, K, d0, inst, Kb)
    lab = SM.canonical_partition(inst.class)
    P = CProg(base, d0); _, hq, c = quad63(P, Hb)
    rounds = 0
    while maximum(lab) < Kb
        k = maximum(lab)
        tm = solve63(Hb, hq, c, K, teamZ63(cf, lab))
        qs = qbound_setup63(cf, lab, 0.0)
        term, V = terms79(P, qs, tm.u)
        order = sortperm(term; rev = true)
        quota = min(Kb - k, max(1, ceil(Int, 0.25k)))
        nxt = k; done = 0
        for cidx in order
            done >= quota && break
            m = qs.mem[cidx]
            (length(m) < 2 || term[cidx] <= 0) && continue
            Vc = V[cidx]
            p = Vc * svd(Vc).V[:, 1]
            o = sortperm(p); g = argmax(diff(p[o]))
            nxt += 1; lab[m[o[(g+1):end]]] .= nxt; done += 1
        end
        done == 0 && break
        lab = SM.canonical_partition(lab); rounds += 1
    end
    return lab, rounds
end

# ---------------------------------------------------------------------------
# One seed
# ---------------------------------------------------------------------------

function run79(n::Int, seed::Int; quiet::Bool = false, ndata::Int = NDATA79, qlist = Q79, methods = METHODS79)
    inst = sq_instance(n, seed); n = length(inst.kinds)
    fl = sq_fleet(inst, DT63G, H63G, CONE63G)
    lanes = sq_lanes(inst, seed)
    cf = cfleet63(fl, H63G)
    K = Cons63(cf, CONE63G)
    D = [data79(inst, fl, lanes, seed, j) for j in 0:(ndata-1)]
    base = CProg(cf, D[1])
    Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
    tf = @elapsed (Fb = cholesky(Symmetric(Hb)))
    Hown = H0blk30(cf)
    L = laplacian79(n, inst.edges, inst.w)
    deg = vec(sum(abs.(L); dims = 2)) ./ 2
    cls = inst.class
    Uc = Dict(c => cholesky(Symmetric(cf.H0[findfirst(==(c), cls)])).U for c in unique(cls))
    # the full programs at every data set
    full = Vector{Any}(undef, ndata)
    for j in 1:ndata
        P = CProg(base, D[j]); _, hq, c = quad63(P, Hb)
        s = solve63(Hb, hq, c, K, nothing)
        uf = -(Fb \ hq)
        full[j] = (P = P, hq = hq, c = c, s = s, uf = uf, Jf = J63(Hb, hq, c, uf))
    end
    res = Dict{String,Any}("n_requested" => N79, "seed" => seed, "n" => n, "edges" => length(inst.edges), "classes" => maximum(cls),
                           "hb_factor_seconds" => tf, "t_full" => [f.s.seconds for f in full], "Jstar" => [f.s.J for f in full],
                           "status_full" => [f.s.status for f in full], "budgets" => Dict{String,Any}())
    qb0 = qbound_setup63(cf, SM.canonical_partition(cls), 0.0)
    beta = qb0.beta; dmax = maximum(deg)
    res["beta"] = beta; res["d_max"] = dmax; res["alpha_ok"] = qb0.alpha_ok
    rng = Xoshiro(79 + seed)
    # shared embeddings (their times are charged to the methods that use them)
    tplan = full[1].s.seconds
    emb_plan(m) = reduce(vcat, ((Uc[cls[i]] * full[1].s.u[ucols(cf, i)])' for i in m))
    tresp = @elapsed begin
        Y = [zeros(0) for _ in 1:n]
        for r in 1:R79
            d = data79(inst, fl, lanes, 10_000 + seed, r)
            P = CProg(base, d); _, hq, _ = quad63(P, Hb)
            u = -(Fb \ hq)
            for i in 1:n
                append!(Y[i], Uc[cls[i]] * u[ucols(cf, i)] ./ sqrt(R79))
            end
        end
    end
    tresp += tf
    emb_resp(m) = reduce(vcat, (Y[i]' for i in m))
    for q in qlist
        lab_qs, tqs = sq_teams(inst, "qs$(q)", seed)
        Kb = maximum(lab_qs)
        bud = Dict{String,Any}("q" => q, "budget" => Kb, "choices" => Dict{String,Any}())
        choices = Dict{String,Tuple{Vector{Int},Float64}}()
        "qs" in methods && (choices["qs"] = (lab_qs, tqs))
        if "geo" in methods
            t = @elapsed (lab = alloc79(cls, m -> reduce(vcat, (inst.slots[i][1:2]' for i in m)), Kb, rng))
            choices["geo"] = (lab, t)
        end
        if "spec" in methods
            t = @elapsed begin
                Ev = eigen(Symmetric(Matrix(L)), 1:min(Kb, n)).vectors
                lab = alloc79(cls, m -> Ev[m, :], Kb, rng)
            end
            choices["spec"] = (lab, t)
        end
        if "plan" in methods
            t = @elapsed (lab = alloc79(cls, emb_plan, Kb, rng))
            choices["plan"] = (lab, t + tplan)
        end
        if "resp" in methods
            t = @elapsed (lab = alloc79(cls, emb_resp, Kb, rng))
            choices["resp"] = (lab, t + tresp)
        end
        if "adapt" in methods
            t = @elapsed ((lab, rounds) = adapt79(cf, base, Hb, K, D[1], inst, Kb))
            choices["adapt"] = (lab, t); bud["adapt_rounds"] = rounds
        end
        choices["classes"] = (SM.canonical_partition(cls), 0.0)
        for (name, (lab, tsel)) in choices
            k = maximum(lab)
            qach = sq_spread(n, inst.edges, inst.w, lab)[1]
            del2 = defect79(L, lab)
            qs = qbound_setup63(cf, lab, qach)
            Z = teamZ63(cf, lab)
            S = srows30(base, lab)
            dcross = zeros(n)
            for ((i, j), x) in zip(inst.edges, inst.w)
                lab[i] == lab[j] && continue
                dcross[i] += x; dcross[j] += x
            end
            up = 1 + 4beta * dmax; upS = 1 + 4beta * maximum(dcross)
            Fz = cholesky(Symmetric(sparse(Z' * Hb * Z)))
            recs = Dict{String,Any}[]
            for j in 1:ndata
                f = full[j]
                tm = solve63(Hb, f.hq, f.c, K, Z)
                qbr = qbound63(f.P, Hown, qs, tm.u, inst.slots)
                ut = Z * (Fz \ (-(Z' * f.hq)))
                gfree = J63(Hb, f.hq, f.c, ut) - f.Jf
                u = f.uf; Kc = 0.0
                for m in qs.mem
                    ub = sum(u[ucols(cf, i)] for i in m) / length(m)
                    Kc += sum(sum(abs2, Uc[cls[i]] * (u[ucols(cf, i)] - ub)) for i in m)
                end
                rS = base.A[S, :] * u
                KS = Kc + dot(rS, base.Wd[S, S] * rS)
                push!(recs, Dict{String,Any}("data" => j - 1, "Jstar" => f.s.J, "Jteam" => tm.J, "gap" => tm.J - f.s.J,
                    "gap_rel" => (tm.J - f.s.J) / abs(f.s.J), "B1x" => qbr["B1x"], "B1" => qbr["B1"],
                    "coh_own_rel" => qbr["coh_own_rel"], "form_dev" => qbr["form_dev"],
                    "gap_free" => gfree, "gap_free_rel" => gfree / abs(f.Jf), "K" => Kc, "KS" => KS, "t_team" => tm.seconds,
                    "status_team" => tm.status))
            end
            bud["choices"][name] = Dict{String,Any}("teams" => k, "t_select" => tsel, "q_achieved" => qach, "delta2" => del2,
                "up" => up, "upS" => upS, "steps" => recs)
            if !quiet
                gr = [r["gap_rel"] for r in recs]
                @printf("  q=%g K=%d %-8s teams %4d  t_sel %8.3f s  delta2 %.3f  q %.2f  gap/J* med %.4f max %.4f  B1x/gap med %.2f  2gf/K med %.2f (<= %.1f)  2gf/KS med %.2f (<= %.1f)\n",
                        q, Kb, name, k, tsel, del2, qach, median(gr), maximum(gr),
                        median([r["B1x"] / max(r["gap"], 1e-300) for r in recs]),
                        median([2r["gap_free"] / max(r["K"], 1e-300) for r in recs]), up,
                        median([2r["gap_free"] / max(r["KS"], 1e-300) for r in recs]), upS)
                flush(stdout)
            end
        end
        res["budgets"]["q$(q)"] = bud
    end
    return res
end

function main79()
    BLAS.set_num_threads(1)
    mkpath(PARTDIR79)
    get(ENV, "E79_WARMUP", "1") == "1" && run79(48, 1; quiet = true, ndata = 2, qlist = [8.0])
    for seed in SEEDS79
        @printf("E79 n=%d seed %d\n", N79, seed); flush(stdout)
        res = run79(N79, seed)
        res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""),
                           "cpu" => Sys.cpu_info()[1].model, "R" => R79, "ndata" => NDATA79)
        path = joinpath(PARTDIR79, @sprintf("e79_n%d_seed%d.json", N79, seed))
        open(io -> JSON.print(io, res, 1), path, "w")
        println("wrote $path"); flush(stdout)
    end
end

# ---------------------------------------------------------------------------
# Merge
# ---------------------------------------------------------------------------

st79(v) = isempty(v) ? Dict{String,Any}() : Dict{String,Any}("median" => median(v), "mean" => mean(v), "min" => minimum(v), "max" => maximum(v), "n" => length(v))

function merge79()
    parts = [JSON.parsefile(joinpath(PARTDIR79, f)) for f in readdir(PARTDIR79) if endswith(f, ".json")]
    rows = Dict{String,Any}()
    tol = 1e-7
    for p in parts, (bk, b) in p["budgets"]
        base = b["choices"]["qs"]["steps"]
        for (name, o) in b["choices"]
            key = "n$(p["n_requested"])_$(bk)_$(name)"
            r = get!(rows, key, Dict{String,Any}("n_requested" => p["n_requested"], "budget_q" => b["q"], "choice" => name,
                                                   "acc" => Dict{String,Vector{Float64}}(), "viol" => Dict{String,Int}()))
            acc = r["acc"]
            push!(get!(acc, "teams", Float64[]), o["teams"]); push!(get!(acc, "t_select", Float64[]), o["t_select"])
            push!(get!(acc, "delta2", Float64[]), o["delta2"]); push!(get!(acc, "q_achieved", Float64[]), o["q_achieved"])
            push!(get!(acc, "n", Float64[]), p["n"])
            for (s, s0) in zip(o["steps"], base)
                push!(get!(acc, "gap_rel", Float64[]), s["gap_rel"])
                push!(get!(acc, "gap_free_rel", Float64[]), s["gap_free_rel"])
                push!(get!(acc, "gap_over_qs", Float64[]), s["gap"] / max(s0["gap"], 1e-300))
                push!(get!(acc, "win_vs_qs", Float64[]), s["gap"] < s0["gap"] ? 1.0 : 0.0)
                s["gap"] > 1e-7 * abs(s["Jstar"]) && push!(get!(acc, "B1x_over_gap", Float64[]), s["B1x"] / s["gap"])
                push!(get!(acc, "B1x_rel", Float64[]), s["B1x"] / abs(s["Jstar"]))
                if s["gap_free"] > 1e-9 * abs(s["Jstar"])
                    push!(get!(acc, "twogf_over_K", Float64[]), 2s["gap_free"] / s["K"])
                    push!(get!(acc, "twogf_over_KS", Float64[]), 2s["gap_free"] / s["KS"])
                    push!(get!(acc, "twogf_over_upK", Float64[]), 2s["gap_free"] / (o["up"] * s["K"]))
                    push!(get!(acc, "twogf_over_upSKS", Float64[]), 2s["gap_free"] / (o["upS"] * s["KS"]))
                end
                v = r["viol"]; sc = tol * max(abs(s["Jstar"]), 1.0)
                v["B1x"] = get(v, "B1x", 0) + (s["B1x"] < s["gap"] - sc)
                v["K_lo"] = get(v, "K_lo", 0) + (s["K"] > 2s["gap_free"] + sc)
                v["K_hi"] = get(v, "K_hi", 0) + (2s["gap_free"] > o["up"] * s["K"] + sc)
                v["KS_lo"] = get(v, "KS_lo", 0) + (s["KS"] > 2s["gap_free"] + sc)
                v["KS_hi"] = get(v, "KS_hi", 0) + (2s["gap_free"] > o["upS"] * s["KS"] + sc)
                v["status"] = get(v, "status", 0) + (s["status_team"] != "SOLVED")
                push!(get!(acc, "coh_own_rel", Float64[]), s["coh_own_rel"]); push!(get!(acc, "form_dev", Float64[]), s["form_dev"])
            end
            push!(get!(r, "seeds", Int[]), p["seed"])
        end
    end
    for (_, r) in rows
        r["stats"] = Dict(k => st79(v) for (k, v) in r["acc"]); delete!(r, "acc")
        r["samples"] = r["stats"]["gap_rel"]["n"]
    end
    out = Dict{String,Any}("experiment" => "E79 team selection at equal team count on the random formation (natural instance, ball limits)", "rows" => rows)
    th = get(ENV, "E79_THEORY", "")
    isfile(th) && (out["theory_checks"] = JSON.parsefile(th))          # e79_theory.jl's output
    ms = [get(p, "meta", Dict()) for p in parts]
    out["meta"] = Dict("hosts" => sort!(unique([get(m, "host", "") for m in ms])), "jobs" => sort!(unique([get(m, "job", "") for m in ms])),
                       "cpus" => sort!(unique([get(m, "cpu", "") for m in ms])), "julia" => sort!(unique([get(m, "julia", "") for m in ms])),
                       "partdir" => get(ENV, "E79_PARTDIR_LABEL", PARTDIR79), "commit" => get(ENV, "E79_COMMIT", ""),
                       "provenance" => [Dict("n" => p["n_requested"], "seed" => p["seed"], "host" => get(m, "host", ""), "job" => get(m, "job", ""))
                                        for (p, m) in zip(parts, ms)])
    open(io -> JSON.print(io, out, 1), OUT79, "w")
    println("wrote $OUT79")
    for key in sort(collect(keys(rows)))
        r = rows[key]; S = r["stats"]
        g(k, f = "median") = haskey(S, k) && haskey(S[k], f) ? S[k][f] : NaN
        @printf("%-26s teams %6.1f  t_sel %8.3f s  gap/J* med %.4f mean %.4f  gap/qs med %.3f win %.2f  B1x/gap med %.2f  delta2 med %.3f  q med %.2f  2gf/K med %.2f max %.2f  viol %s\n",
                key, g("teams"), g("t_select"), g("gap_rel"), g("gap_rel", "mean"), g("gap_over_qs"), g("win_vs_qs", "mean"),
                g("B1x_over_gap"), g("delta2"), g("q_achieved"), g("twogf_over_K"), g("twogf_over_K", "max"), string(r["viol"]))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE79 == "merge" ? merge79() : main79()
end
