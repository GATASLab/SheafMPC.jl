# kkt.jl: the BlockLDL kernel (supernodal multifrontal LDLt of quasi-definite
# KKT matrices) against dense LDLt and QDLDL, on random quasi-definite systems
# and on fleet KKT matrices, sequential and threaded, with every ordering, the
# rank-one update path, and as the solver's linear system backend.

using SheafMPC: BlockLDL
include(joinpath(@__DIR__, "..", "bench", "kkt_problems.jl"))

"A random quasi-definite K = [P + s I, A'; A, -D] (upper triangle, every diagonal stored) and n."
function random_quasidefinite(rng, n, m; dens = 0.1)
    M = sprandn(rng, n, n, dens)
    P = M * M' + 1e-3 * I
    A = sprandn(rng, m, n, dens)
    D = spdiagm(0 => 1e-3 .+ rand(rng, m))
    K = sparse(triu([P A'; A -D]))
    return K, n
end

full_sym(K) = Matrix(Symmetric(Matrix(K), :U))
kkt_signs(N, n) = [i <= n ? 1.0 : -1.0 for i in 1:N]

function check_solve(K, n, perm; relax = BlockLDL.EXACT, nthreads = 1, tol = 1e-12)
    N = size(K, 1)
    S = BlockLDL.symbolic(K, perm, kkt_signs(N, n); relax = relax)
    F = BlockLDL.Factor(S; nthreads = nthreads)
    BlockLDL.factor!(F, K)
    b = randn(N)
    x = zeros(N); r = zeros(N); w = zeros(N)
    _, rel, _ = BlockLDL.solve_refined!(F, K, x, b, r, w; iters = 5, rtol = 1e-15)
    return rel, F
end

@testset "BlockLDL" begin
    rng = MersenneTwister(7)
    @testset "random quasi-definite vs dense LDLt" begin
        for (n, m) in ((1, 1), (3, 2), (12, 7), (40, 25), (150, 90), (600, 400))
            K, nn = random_quasidefinite(rng, n, m)
            N = size(K, 1)
            for relax in (BlockLDL.EXACT, BlockLDL.LIGHT, BlockLDL.Relax())
                S = BlockLDL.symbolic(K, BlockLDL.order_amd(K), kkt_signs(N, n); relax = relax)
                F = BlockLDL.Factor(S); BlockLDL.factor!(F, K)
                @test BlockLDL.wrong_signs(F) == 0
                @test F.nreg == 0
                b = randn(rng, N); x = copy(b)
                BlockLDL.ldiv!(F, x, zeros(N))
                Kd = full_sym(K)
                @test norm(Kd * x - b) / norm(b) <= 1e-10
                if N <= 80
                    # the same pivots as a dense LDLt without pivoting in this order
                    p = S.perm
                    Kp = Kd[p, p]
                    dd = zeros(N); Ld = Matrix{Float64}(I, N, N); W = copy(Kp)
                    for k in 1:N
                        dd[k] = W[k, k]
                        Ld[k+1:N, k] = W[k+1:N, k] / dd[k]
                        W[k+1:N, k+1:N] -= Ld[k+1:N, k] * dd[k] * Ld[k+1:N, k]'
                    end
                    @test maximum(abs.(F.d - dd) ./ max.(abs.(dd), 1)) <= 1e-10
                    @test x ≈ Kd \ b rtol = 1e-9
                end
                rel, _ = check_solve(K, n, BlockLDL.order_amd(K); relax = relax)
                @test rel <= 1e-12
            end
        end
    end
    @testset "orderings and threads on fleet KKTs" begin
        for (graph, b, n) in ((:ring, 1, 1), (:ring, 1, 4), (:ring, 1, 16), (:ring, 24, 16), (:grid, 1, 16),
                              (:grid, 4, 16), (:ring, 1, 64), (:grid, 1, 64), (:ring, 1, 256))
            qp, lab = fleet_problem(n, 24; graph = graph, b = b)
            K, nv, _ = kkt_matrix(qp)
            L = kkt_labels(lab)
            st = BlockLDL.KKTStructure(L.agent, L.block)
            for ord in (:amd, :amf, :stage, :chain, :nd2, :nd8)
                n >= 256 && ord in (:stage, :chain) && continue
                perm = BlockLDL.make_ordering(K, ord; structure = st)
                @test isperm(perm)
                rel, F = check_solve(K, nv, perm)
                @test rel <= 1e-12
                @test BlockLDL.wrong_signs(F) == 0
            end
            if Threads.nthreads() > 1
                perm = BlockLDL.make_ordering(K, :nd4; structure = st)
                for nt in (2, 4)
                    rel, F = check_solve(K, nv, perm; nthreads = nt)
                    @test rel <= 1e-12
                end
            end
            p, name, tab = BlockLDL.choose_ordering(K; structure = st)
            @test isperm(p)
            @test !isempty(tab)
        end
    end
    @testset "rank-one diagonal updates" begin
        qp, lab = fleet_problem(8, 24; graph = :ring, b = 1)
        K, nv, di = kkt_matrix(qp)
        N = size(K, 1)
        S = BlockLDL.symbolic(K, BlockLDL.order_amd(K), kkt_signs(N, nv))
        F = BlockLDL.Factor(S); BlockLDL.factor!(F, K)
        rows = nv .+ [3, 17, 40, 41, 100]
        delta = [-0.5, 0.3, -0.9, 5.0, 2.0] .* nonzeros(K)[di[rows]]      # scaled pivots keep their signs
        w = zeros(N)
        BlockLDL.update_diagonal!(F, rows, delta, w)
        @test all(iszero, w)
        K2 = copy(K)
        nonzeros(K2)[di[rows]] .+= delta
        F2 = BlockLDL.Factor(S); BlockLDL.factor!(F2, K2)
        @test F.d ≈ F2.d rtol = 1e-9
        b = randn(N); x = copy(b)
        BlockLDL.ldiv!(F, x, zeros(N))
        @test norm(full_sym(K2) * x - b) / norm(b) <= 1e-10
    end
    @testset "rank-one path of the polish system" begin
        qp, lab = fleet_problem(8, 24; graph = :ring, b = 4)
        K, nv, di = kkt_matrix(qp)
        N = size(K, 1)
        A = SheafMPC.BlockLDLSystem(copy(K), di, nv)
        P = SheafMPC._polish_system(A, copy(K), nv)
        @test P.lowrank
        nz = nonzeros(P.K)
        rows = nv .+ [2, 9, 30]
        nz[di[rows]] .= -1e-6                          # three rows turn active
        SheafMPC.refactor!(P)
        @test P.nlowrank == 1
        b = randn(N); x = zeros(N); r = zeros(N); w = zeros(N)
        _, rel, _ = BlockLDL.solve_refined!(P.F, P.K, x, b, r, w; iters = 3, rtol = 1e-15)
        @test rel <= 1e-10
        nz[di] .*= 1.5                                  # every row: a full refactorization
        SheafMPC.refactor!(P)
        @test P.nlowrank == 1 && P.nupd == 0
    end
    @testset "no subnormals in the factor" begin
        nsub(v) = count(x -> x != 0 && abs(x) < floatmin(Float64), v)
        # entries of K below floatmin: the factor holds zeros, not subnormals
        K = sparse(triu([2.0 1e-310 0.0; 1e-310 3.0 1e-311; 0.0 1e-311 -4.0]))
        S = BlockLDL.symbolic(K, [1, 2, 3], [1.0, 1.0, -1.0])
        F = BlockLDL.Factor(S); BlockLDL.factor!(F, K)
        @test nsub(F.Lx) == 0 && nsub(F.leafL) == 0
        # a rank-one update whose scale underflows leaves the factor untouched and normal
        qp, lab = fleet_problem(8, 24; graph = :ring, b = 1)
        Kf, nv, di = kkt_matrix(qp)
        N = size(Kf, 1)
        S2 = BlockLDL.symbolic(Kf, BlockLDL.order_amd(Kf), kkt_signs(N, nv))
        F2 = BlockLDL.Factor(S2); BlockLDL.factor!(F2, Kf)
        L0 = copy(F2.Lx); w = zeros(N)
        BlockLDL.rank1_diagonal!(F2, 1, 1e-310, w)
        @test nsub(F2.Lx) == 0 && all(iszero, w)
        @test maximum(abs.(F2.Lx .- L0)) <= 1e-300
        # the polish cycle (delta and 1/delta pivots, rank-one flips of the active set):
        # no subnormals in the factor or the solutions, solves as fast as with flushing
        s = setup(qp; linsys = :blockldl)
        P = s.pol
        nzP = nonzeros(P.K); n = s.n; m = s.m; del = s.settings.polish_delta
        rngs = MersenneTwister(5)
        b = randn(rngs, N); x = similar(b)
        for _ in 1:6
            for i in rand(rngs, 1:m, 8)
                v = nzP[P.diag_idx[n+i]]
                nzP[P.diag_idx[n+i]] = v ≈ -del ? -1 / del : -del
            end
            SheafMPC.refactor!(P)
            @test nsub(P.F.Lx) == 0 && nsub(P.F.d) == 0
            copyto!(x, b); solve!(P, x)
            @test nsub(x) == 0
        end
        @test P.nlowrank > 0
        tplain = minimum(@elapsed((copyto!(x, b); solve!(P, x))) for _ in 1:20)
        set_zero_subnormals(true)
        tflush = minimum(@elapsed((copyto!(x, b); solve!(P, x))) for _ in 1:20)
        set_zero_subnormals(false)
        @test tplain <= 2.0 * tflush + 1e-5
    end
    @testset "threaded solves only on large factors" begin
        qp, lab = fleet_problem(4, 24; graph = :ring, b = 1)
        K, nv, _ = kkt_matrix(qp)
        S = BlockLDL.symbolic(K, BlockLDL.order_amd(K), kkt_signs(size(K, 1), nv))
        F = BlockLDL.Factor(S; nthreads = 4)
        @test F.sched !== nothing && !F.par_solve
    end
    @testset "random QPs vs Clarabel with :blockldl" begin
        rng2 = Xoshiro(11)
        for (n, m) in ((10, 8), (40, 30), (80, 60))
            p = random_qp(rng2, n, m)
            ref, _, _ = clarabel_ref(p)
            s = setup(p; linsys = :blockldl, eps_abs = 1e-8, eps_rel = 1e-8)
            info = solve!(s)
            @test info.status == :solved && relgap(info.obj, ref) <= 1e-6
        end
        p = random_socp(rng2, 15, 3, 3)
        ref, _, _ = clarabel_ref(p)
        s = setup(p; linsys = :blockldl, eps_abs = 1e-8, eps_rel = 1e-8)
        @test relgap(solve!(s).obj, ref) <= 1e-6
        for ls in (:blockldl, :model)
            p = random_socp(rng2, 12, 4, 3)
            ref, _, _ = clarabel_ref(p)
            s = setup(p; linsys = ls, eps_abs = 1e-8, eps_rel = 1e-8)
            @test relgap(solve!(s).obj, ref) <= 1e-6
        end
        s = setup(random_qp(rng2, 30, 25); linsys = :blockldl)
        solve!(s)
        SheafMPC.admm_step!(s)
        @test (@allocated SheafMPC.admm_step!(s)) == 0
    end
    @testset "solver backend" begin
        for (graph, n) in ((:ring, 4), (:grid, 16))
            qp, lab = fleet_problem(n, 24; graph = graph, b = 1)
            s0 = setup(qp; linsys = :qdldl, eps_abs = 1e-8, eps_rel = 1e-8)
            solve!(s0)
            sm = setup(qp; linsys = :model, eps_abs = 1e-8, eps_rel = 1e-8)
            @test solve!(sm).status == :solved && relgap(sm.info.obj, s0.info.obj) <= 1e-6
            for kw in ((kkt_ordering = :auto,), (kkt_ordering = :nd4, kkt_structure = (agent = lab.var_agent, block = lab.var_block)),
                       (kkt_ordering = :auto, kkt_threads = 2, kkt_structure = (agent = lab.var_agent, block = lab.var_block)))
                s = setup(qp; linsys = :blockldl, eps_abs = 1e-8, eps_rel = 1e-8, kw...)
                info = solve!(s)
                @test info.status == :solved
                @test relgap(info.obj, s0.info.obj) <= 1e-6
                @test s.info.linsys == :blockldl
            end
        end
    end
end
