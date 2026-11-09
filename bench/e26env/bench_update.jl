# usage: BENCH_SIDE=16 julia --project=bench/e26env bench/e26env/bench_update.jl
using LinearAlgebra, Printf, Profile
include(joinpath(ENV["E26_DIR"], "e26_flagship.jl"))
BLAS.set_num_threads(1)
function timeit(f, reps)
    f(); GC.gc()
    best = Inf
    for _ in 1:7
        t = time_ns(); for _ in 1:reps; f(); end
        best = min(best, (time_ns() - t) / 1e6 / reps)
    end
    best
end
function run_bench(side)
    sc = Scenario26(side; seed = 1)
    F = Form26(sc, "red")
    x0 = start26(sc); refs, term = references26(sc, 0.0)
    construct26!(F, sc, x0, refs, term)
    reps = side == 16 ? 100 : 20
    tset = timeit(() -> set_data26!(F.pp, sc, x0, refs, term), reps)
    tupd = [timeit(() -> SM.update!(R), reps) for R in F.chain]
    tref = timeit(() -> refresh26!(F.G, Pq26(F)), reps)
    tcon = timeit(() -> construct26!(F, sc, x0, refs, term), reps)
    if get(ENV,"PROF","0")=="1"
                f() = for _ in 1:reps; construct26!(F, sc, x0, refs, term); end
        f(); @profile f(); Profile.print(format=:flat, sortedby=:count, mincount=15)
    end
    @printf("alloc construct %d B\n", @allocated construct26!(F, sc, x0, refs, term))
    y = zeros(length(F.levels[end])); y .= 0.1
    tlift = timeit(() -> lift26!(F, y), reps * 5)
    @printf("n=%d levels=%d set_data %.3f  update! per level %s  refresh %.3f  construct %.3f ms  lift %.3f ms\n",
            side^2, length(F.chain), tset, string(round.(tupd; digits = 3)), tref, tcon, tlift)
    # correctness dump: q,b,c after several steps
    out = Vector{Vector{Float64}}()
    for k in 0:3
        refs, term = references26(sc, 0.2k)
        xk = [x0[i] .+ 0.01k .* sin.(i .+ (1:length(x0[i]))) for i in eachindex(x0)]
        construct26!(F, sc, xk, refs, term)
        qp = F.G.qp
        push!(out, vcat(Vector(qp.q), Vector(qp.l), Vector(qp.u), [qp.c]))
        P = Pq26(F)
        push!(out, vcat([nd.q for nd in P.nodes]..., [nd.b for nd in P.nodes]..., [E.b for E in P.edges]..., [nd.c for nd in P.nodes]))
    end
    return out
end
function main()
    side = parse(Int, ENV["BENCH_SIDE"])
    out = run_bench(side)
    open(get(ENV, "BENCH_DUMP", tempname()), "w") do io; serialize(io, out); end
end
main()
