# kkt_calibrate.jl: data for the cost model of the KKT backend choice.
#
#   julia --project=bench bench/kkt_calibrate.jl
#
# For fleet KKT matrices over graphs, blockings b, agent counts and dynamics,
# and every cheap ordering (AMD, MMD, AMF, the structured ones), records the
# symbolic statistics the cost model sees (N, nnz(K), nnz(L), flops, sum of
# squared column counts, number of exact supernodes and leaves) and the measured
# times of QDLDL (simplicial, the package's QDLDLSystem) and BlockLDL
# (multifrontal): ordering time, symbolic time, numeric factorization, solve.
# Output: bench/results/kkt_calibrate[_TAG].json.

using SheafMPC, SparseArrays, LinearAlgebra, Printf, Statistics, JSON
import QDLDL, CliqueTrees
const BL = SheafMPC.BlockLDL
include(joinpath(@__DIR__, "kkt_problems.jl"))

const TAG = get(ENV, "BENCH_TAG", "")
const NS = parse.(Int, split(get(ENV, "BENCH_N", "1,2,4,8,16,32,64,128,256"), ","))
const BSET = parse.(Int, split(get(ENV, "BENCH_B", "1,2,4,8,24"), ","))
# supernode relaxation of BlockLDL: exact, light (the package default) or cholmod
const RELAX = Dict("exact" => BL.EXACT, "light" => BL.LIGHT, "cholmod" => BL.Relax())[get(ENV, "BENCH_RELAX", "light")]

function timeit(f; budget = 0.2, minreps = 3, maxreps = 500)
    f()
    ts = Float64[]; t0 = time()
    while length(ts) < maxreps && (length(ts) < minreps || time() - t0 < budget)
        push!(ts, @elapsed f())
    end
    return minimum(ts)
end

function features(K, perm)
    s = BL.order_stats(K, perm)
    N = size(K, 1)
    iperm = invperm(perm)
    colptr, rowval, _ = BL._permuted_upper(K, iperm)
    parent = BL._etree(N, colptr, rowval)
    cc = BL._colcounts(N, parent, colptr, rowval)
    return (nnzL = s.nnzL, flops = s.flops, critical = s.critical, sumcc2 = sum(abs2, cc), maxcc = maximum(cc; init = 0))
end

function main()
    BLAS.set_num_threads(1)
    rows = Dict{String,Any}[]
    for dyn in (:di, :quad), graph in (:ring, :grid), b in BSET, n in NS
        graph == :grid && isqrt(n)^2 != n && continue
        dyn == :quad && n > 64 && continue
        qp, lab = fleet_problem(n, 24; graph = graph, b = b, dyn = dyn)
        K, nv, di = kkt_matrix(qp)
        N = size(K, 1)
        L = kkt_labels(lab)
        st = BL.KKTStructure(L.agent, L.block)
        signs = [i <= nv ? 1.0 : -1.0 for i in 1:N]
        bb = randn(N); x = similar(bb); w = zeros(N)
        for ord in (:amd, :mmd, :amf, :nd4)
            tord = @elapsed perm = BL.make_ordering(K, ord; structure = st)
            perm === nothing && continue
            fe = features(K, perm)
            Q = SheafMPC.QDLDLSystem(copy(K), di; perm = perm)
            tqf = timeit(() -> SheafMPC.refactor!(Q))
            tqs = timeit(() -> (copyto!(x, bb); SheafMPC.solve!(Q, x)))
            tsym = @elapsed S = BL.symbolic(K, perm, signs; relax = RELAX)
            F = BL.Factor(S); BL.factor!(F, K)
            tbf = timeit(() -> BL.factor!(F, K))
            tbs = timeit(() -> (copyto!(x, bb); BL.ldiv!(F, x, w)))
            push!(rows, Dict{String,Any}("dyn" => string(dyn), "graph" => string(graph), "b" => b, "n" => n,
                                         "ordering" => string(ord), "N" => N, "nnzK" => nnz(K), "nnzL" => fe.nnzL,
                                         "flops" => fe.flops, "critical" => fe.critical, "sumcc2" => fe.sumcc2,
                                         "maxcc" => fe.maxcc, "nsup" => S.nsup, "nleaf" => S.nleaf, "t_order" => tord,
                                         "t_symbolic" => tsym, "q_factor" => tqf, "q_solve" => tqs, "b_factor" => tbf,
                                         "b_solve" => tbs))
            @printf("%-4s %-4s b=%2d n=%4d %-4s N=%7d nnzL=%9d fl=%9.3g | Q f=%9.4f s=%8.4f | B f=%9.4f s=%8.4f ms\n",
                    dyn, graph, b, n, ord, N, fe.nnzL, fe.flops, 1e3tqf, 1e3tqs, 1e3tbf, 1e3tbs)
            flush(stdout)
        end
        GC.gc()
    end
    out = joinpath(@__DIR__, "results", "kkt_calibrate" * (isempty(TAG) ? "" : "_" * TAG) * ".json")
    mkpath(dirname(out))
    open(io -> JSON.print(io, Dict("rows" => rows, "host" => gethostname(), "cpu" => Sys.cpu_info()[1].model), 1), out, "w")
    println("wrote ", out)
end

main()
