# dump_teams_resp.jl: the clustered (response) teams of the natural formation of the teams figure (seed 1,
# ~1000 vehicles), built as E79's `resp` choice (k-means of the sketched centralized responses inside each
# region, budget = the q = 8 quasi-stable count, allocated over the regions by DP; Corollary cor:choose), and
# their gap and step time on the same runs as the q = 8 annotation of render/fig_teams_map.py:
#   TR_MODE=labels  labels (E79's rng sequence: geo, spec, plan, then resp at q = 8) -> TR_OUT/resp_labels.json,
#                   then E63-gap's closed loop (20 steps, ball limits) for qs8 and resp -> TR_OUT/gap.json
#   TR_MODE=time    E63-time (team, coord paths, 30 steps) with these teams -> TR_OUT/time_resp.json
#
#   BENCH_DISC=zoh BENCH_FLEET=dronecar TR_MODE=labels TR_OUT=... julia --project=env dump_teams_resp.jl
using JSON, Printf
const TRMODE = get(ENV, "TR_MODE", "labels")
const TROUT = get(ENV, "TR_OUT", joinpath(@__DIR__, "..", "..", "..", "results", "teams_resp"))
const TRN = 1024
const TRSEED = 1
mkpath(TROUT)

if TRMODE == "labels"
    ENV["E79_N"] = string(TRN)
    include(joinpath(@__DIR__, "e79_teamselect.jl"))
    BLAS.set_num_threads(1)
    function resp_labels(n, seed)
        inst = sq_instance(n, seed); n = length(inst.kinds)
        fl = sq_fleet(inst, DT63G, H63G, CONE63G); lanes = sq_lanes(inst, seed)
        cf = cfleet63(fl, H63G); K = Cons63(cf, CONE63G)
        d0 = data79(inst, fl, lanes, seed, 0)
        base = CProg(cf, d0)
        Hb = sparse(H0blk30(cf) + base.A' * base.Wd * base.A)
        tf = @elapsed (Fb = cholesky(Symmetric(Hb)))
        cls = inst.class
        Uc = Dict(c => cholesky(Symmetric(cf.H0[findfirst(==(c), cls)])).U for c in unique(cls))
        L = laplacian79(n, inst.edges, inst.w)
        _, hq0, c0 = quad63(CProg(base, d0), Hb)
        s0 = solve63(Hb, hq0, c0, K, nothing)
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
        rng = Xoshiro(79 + seed)
        lab_qs, _ = sq_teams(inst, "qs8.0", seed); Kb = maximum(lab_qs)
        # E79's rng sequence at the first budget (q = 8): geo, spec, plan consume it before resp
        alloc79(cls, m -> reduce(vcat, (inst.slots[i][1:2]' for i in m)), Kb, rng)
        Ev = eigen(Symmetric(Matrix(L)), 1:min(Kb, n)).vectors
        alloc79(cls, m -> Ev[m, :], Kb, rng)
        alloc79(cls, m -> reduce(vcat, ((Uc[cls[i]] * s0.u[ucols(cf, i)])' for i in m)), Kb, rng)
        t = @elapsed (lab = alloc79(cls, m -> reduce(vcat, (Y[i]' for i in m)), Kb, rng))
        return lab, lab_qs, t + tresp + tf
    end
    lab, lab_qs, tsel = resp_labels(TRN, TRSEED)
    @printf("resp teams %d (qs8 %d), n %d, selection %.2f s\n", maximum(lab), maximum(lab_qs), length(lab), tsel); flush(stdout)
    open(io -> JSON.print(io, Dict("n_requested" => TRN, "seed" => TRSEED, "teams_resp" => lab, "teams_qs8" => lab_qs,
                                   "t_select" => tsel, "R" => R79)), joinpath(TROUT, "resp_labels.json"), "w")
    const RESPLAB = lab
    sq_teams(inst, choice::String, seed::Int) = choice == "resp" ? (RESPLAB, 0.0) :
        invoke(sq_teams, Tuple{Any,AbstractString,Int}, inst, choice, seed)
    res = run63g(TRN, TRSEED; choices = ["qs8", "resp"], baselines = String[])
    res["meta"] = Dict("host" => gethostname(), "julia" => string(VERSION), "job" => get(ENV, "SLURM_JOB_ID", ""))
    open(io -> JSON.print(io, res, 1; allownan = true), joinpath(TROUT, "gap.json"), "w")
    println("wrote gap.json")
else
    ENV["E63_TEAMS"] = "resp"; ENV["E63_N"] = string(TRN); ENV["E63_SEEDS"] = string(TRSEED)
    ENV["E63_PARTDIR"] = TROUT
    include(joinpath(@__DIR__, "e63_time.jl"))
    const RESPLAB = Vector{Int}(JSON.parsefile(joinpath(TROUT, "resp_labels.json"))["teams_resp"])
    # the warm-up of main63 runs at n = 32: q = 8 teams there
    sq_teams(inst, choice::String, seed::Int) = choice != "resp" ? invoke(sq_teams, Tuple{Any,AbstractString,Int}, inst, choice, seed) :
        length(inst.class) == length(RESPLAB) ? (RESPLAB, 0.0) : invoke(sq_teams, Tuple{Any,AbstractString,Int}, inst, "qs8", seed)
    main63()
end
