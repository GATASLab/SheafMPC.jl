# Certificates: the two-sided gap bound (Thm. 2), the gap kernel (Prop. 7),
# and the team selector.

@testset "certificates" begin

@testset "gap bounds bracket the true gap" begin
    instances = [
        test_program(n = 6, H = 6, graph = :grid, seed = 3, coherent = false)[1],
        test_program(n = 6, H = 6, graph = :grid, seed = 4, coherent = false, umax_scale = 0.3)[1],     # active cones
        test_program(n = 5, H = 5, graph = :ring, seed = 8, coherent = false, start_in_formation = false)[1],
    ]
    for fp in instances
        fine = test_solve(fp)
        n = nagents(fp.fleet)
        for res in (Teams([cld(i, 2) for i in 1:n]), Teams(ones(Int, n)), Teams([cld(i, 3) for i in 1:n]) ⊠ partial_condensing(2),
                    Teams([cld(i, 2) for i in 1:n]; from = 2))
            R = reduce(fp, res)
            sr = test_solve(R)
            isoptimal(sr) || continue
            b = gap_bounds(fp, R, sr; fine_solution = fine)
            tol = 1e-7 * max(1.0, abs(fine.J))
            @test b.lower <= b.gap + tol
            @test b.gap <= b.upper + tol
            @test b.residual < 1e-6
            @test b.upper ≈ sum(b.per_block)
        end
    end
end

@testset "bounds vanish for coherent rows, and compose for teams of teams" begin
    sc = GridScenario(rows = 4, cols = 3, H = 6, coherence = :rows, seed = 1)
    refs, term = references(sc)
    fp = FleetProgram(fleet(sc); x0 = formation_start(sc), references = refs, terminal = term)
    fine = test_solve(fp)
    R = reduce(fp, Teams(row_teams(sc)))
    b = gap_bounds(fp, R, test_solve(R); fine_solution = fine)
    @test abs(b.gap) < 1e-7 && b.upper < 1e-7 && b.lower < 1e-7
    R12 = reduce(R, Teams([1, 1, 2, 2]))
    s12 = test_solve(R12)
    b12 = gap_bounds(fp, R12, s12; fine_solution = fine)
    @test b12.lower <= b12.gap + 1e-7 && b12.gap <= b12.upper + 1e-7
    # the same as the one-step reduction to strips of two rows
    R2 = reduce(fp, Teams(strip_teams(sc, 2)))
    b2 = gap_bounds(fp, R2, test_solve(R2); fine_solution = fine)
    @test srelerr(b12.gap, b2.gap) < 1e-6 && srelerr(b12.lower, b2.lower) < 1e-9
    @test srelerr(b12.upper, b2.upper) < 1e-5
end

@testset "the kernel matches pushforward and solve on equality-constrained QPs" begin
    for (graph, n, seed) in ((:grid, 6, 1), (:ring, 5, 2), (:grid, 8, 3))
        fp, _ = test_program(n = n, H = 5, graph = graph, seed = seed, coherent = false, input = :none)
        fine = test_solve(fp)
        K = gap_kernel(fp, fine.x)
        @test K.nb == n && K.active_soc == 0
        rng = Xoshiro(seed)
        for alpha in (ones(Int, n), [cld(i, 2) for i in 1:n], random_teams(fp.fleet, rng, 2), random_teams(fp.fleet, rng, 3))
            g = gap(K, alpha)
            Jr = test_solve(reduce(fp, Teams(alpha))).J
            @test abs(g - (Jr - fine.J)) <= 1e-6 * max(1.0, abs(fine.J))
        end
        @test gap(K, collect(1:n)) == 0.0
    end
    # with inequalities inactive at the fine optimum, a lower bound
    fp, _ = test_program(n = 6, H = 6, graph = :grid, seed = 4, coherent = false, umax_scale = 0.4)
    fine = test_solve(fp)
    K = gap_kernel(fp, fine.x)
    if K.active_soc == 0 && K.active_nonneg == 0
        for alpha in ([1, 1, 2, 2, 3, 3], [1, 1, 1, 2, 2, 2], ones(Int, 6))
            @test gap(K, alpha) <= test_solve(reduce(fp, Teams(alpha))).J - fine.J + 1e-7
        end
    end
end

@testset "the selector" begin
    sc = GridScenario(rows = 3, cols = 4, H = 6, coherence = :rows, seed = 3)
    refs, term = references(sc)
    fp = FleetProgram(fleet(sc); x0 = formation_start(sc), references = refs, terminal = term)
    fine = test_solve(fp)
    K = gap_kernel(fp, fine.x)
    sel = select_teams(K; k = 3)
    @test canonical_partition(sel.teams) == canonical_partition(row_teams(sc))
    @test sel.gap < 1e-9 * abs(K.Jstar)
    # a budget: the coarsest structure under it
    b = select_teams(K; budget = 1e-9 * abs(K.Jstar))
    @test b.k == 3 && b.gap <= 1e-9 * abs(K.Jstar)
    # incoherent data: beam search and pair re-splitting do no worse than greedy
    sc2 = GridScenario(rows = 3, cols = 4, H = 6, coherence = :agents, seed = 3)
    refs, term = references(sc2)
    fp2 = FleetProgram(fleet(sc2); x0 = formation_start(sc2), references = refs, terminal = term)
    K2 = gap_kernel(fp2, test_solve(fp2).x)
    g1 = select_teams(K2; k = 4, refine = :none)
    g2 = select_teams(K2; k = 4, beam = 4, refine = :pairs)
    @test g2.gap <= g1.gap + 1e-12
    @test maximum(g2.teams) == 4
    @test abs(gap(K2, g2.teams) - g2.gap) < 1e-9
    # the selected teams' true gap (pushforward and solve) agrees with the kernel
    fine2 = test_solve(fp2)
    if K2.active_soc == 0
        @test abs(test_solve(reduce(fp2, Teams(g2.teams))).J - fine2.J - g2.gap) < 1e-6 * abs(fine2.J)
    end
    # restricting merges to a graph
    g3 = select_teams(K2, [(i, i + 1) for i in 1:11]; k = 4)
    @test maximum(g3.teams) == 4
end

end
