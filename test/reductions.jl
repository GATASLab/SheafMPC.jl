# Reductions: the identities of the paper's Sec. III and IV on small fleets.

@testset "reductions" begin

rng = Xoshiro(7)

@testset "fine vs reduced objective identities (Thm. 1)" begin
    fp, _ = test_program(n = 6, H = 6, graph = :grid, seed = 3, coherent = false)
    P = fp.program
    fine = test_solve(fp)
    @test isoptimal(fine)
    for res in (Teams([1, 1, 2, 2, 3, 3]), full_condensing(), partial_condensing(2), Teams([1, 1, 1, 2, 2, 2]) ⊠ partial_condensing(3),
                Mixed((i, t) -> t >= 2 ? (cld(i, 3), t) : (i + 100, t)))
        R = reduce(fp, res)
        Pc = R.program
        # J'(y) = J(iota(y)) for any y, and the lift satisfies every contracted edge
        for _ in 1:3
            y = randn(rng, c0dim(Pc))
            x = lift(R, y)
            @test srelerr(objective(Pc, y), objective(P, x)) < 1e-11
            S = R.collapsed
            @test norm(coboundary(P, S) * x - targets(P, S), Inf) < 1e-10
        end
        # same value as the fine program with the contracted edges hard, and J* <= J*(reduced)
        sr = test_solve(R)
        sh = test_solve(harden(P, R.collapsed))
        @test srelerr(sr.J, sh.J) < 1e-7
        @test sr.J >= fine.J - 1e-8 * abs(fine.J)
        x = lift(R, sr)
        @test feasibility(P, x).hard < 1e-8 && feasibility(P, x).cone < 1e-8
        @test srelerr(objective(P, x), sr.J) < 1e-9
    end
end

@testset "time blocking is exact (Prop. 4), and the legs commute (eq. (3))" begin
    for (n, kinds, scale) in ((4, :mixed, 1.0), (6, :quad, 0.3))
        fp, _ = test_program(n = n, H = 6, graph = :ring, kinds = kinds, seed = 5, umax_scale = scale, coherent = false,
                             start_in_formation = false)
        fine = test_solve(fp)
        for blk in (full_condensing(), partial_condensing(2), partial_condensing(4), TimeBlocking([1, 1, 2, 2, 2, 3, 4]))
            R = reduce(fp, blk)
            @test isempty(intersect(R.collapsed, [e for (e, E) in enumerate(fp.program.edges) if !E.hard]))
            @test srelerr(test_solve(R).J, fine.J) < 1e-7                         # gap 0
        end
        # teams need a start from which exact formation is reachable in one step (else all three are infeasible)
        fp, _ = test_program(n = n, H = 6, graph = :ring, kinds = kinds, seed = 5, umax_scale = scale, coherent = false)
        alpha = [cld(i, 2) for i in 1:n]
        Jt = test_solve(reduce(fp, Teams(alpha))).J
        @test isfinite(Jt)
        for blk in (full_condensing(), partial_condensing(3))
            Jp = test_solve(reduce(fp, Teams(alpha) ⊠ blk)).J                  # at once
            Jtb = test_solve(reduce(reduce(fp, Teams(alpha)), blk)).J           # teams, then blocking
            Jbt = test_solve(reduce(reduce(fp, blk), Teams(alpha))).J           # blocking, then teams
            @test srelerr(Jp, Jt) < 1e-7 && srelerr(Jtb, Jt) < 1e-7 && srelerr(Jbt, Jt) < 1e-7
        end
    end
end

@testset "teams of teams compose (Thm. 4) and refinement lowers the value" begin
    sc = GridScenario(rows = 4, cols = 3, H = 6, coherence = :agents, seed = 2)
    refs, term = references(sc)
    fp = FleetProgram(fleet(sc); x0 = formation_start(sc), references = refs, terminal = term)
    R1 = reduce(fp, Teams(row_teams(sc)))
    R12 = reduce(R1, Teams([1, 1, 2, 2]))                    # pairs of rows, as teams of the reduced fleet
    R2 = reduce(fp, Teams(strip_teams(sc, 2)))
    s12, s2, s1 = test_solve(R12), test_solve(R2), test_solve(R1)
    @test srelerr(s12.J, s2.J) < 1e-7
    @test s1.J <= s2.J + 1e-8
    x = lift(R12, s12)
    @test length(x) == c0dim(fp.program)
    @test srelerr(objective(fp.program, x), s12.J) < 1e-9
    labels, collapsed, _, _ = composite_partition(R12)
    @test canonical_partition(labels) == R2.partition
    @test sort(collapsed) == sort(R2.collapsed)
    # a mixed resolution (teams from t = 2 on) refines the teams: no larger value
    sm = test_solve(reduce(fp, Teams(strip_teams(sc, 2); from = 2)))
    @test sm.J <= s2.J + 1e-8
end

@testset "zero gap for almost equitable teams with coherent data (Thm. 3)" begin
    for scale in (1.0, 0.25)                                 # inputs inactive, and active
        sc = GridScenario(rows = 4, cols = 3, H = 8, coherence = :rows, umax_scale = scale, seed = 4)
        refs, term = references(sc)
        fp = FleetProgram(fleet(sc); x0 = formation_start(sc), references = refs, terminal = term)
        fine = test_solve(fp)
        R = reduce(fp, Teams(row_teams(sc)))
        sr = test_solve(R)
        @test abs(sr.J - fine.J) <= 1e-7 * abs(fine.J)
        # a team that mixes rows is not coherent: positive gap
        @test test_solve(reduce(fp, Teams(strip_teams(sc, 2)))).J > fine.J + 1e-3
    end
end

@testset "in-place data updates match a rebuild" begin
    fp, d = test_program(n = 6, H = 6, graph = :grid, seed = 9, coherent = false)
    R = reduce(fp, Teams([1, 1, 1, 2, 2, 2]) ⊠ partial_condensing(2))
    M = QPMap(R.program; dedup = false)
    for k in 1:3
        set_state!(fp, [x .+ 0.1k for x in d.x0])                           # a rigid shift: still in formation
        set_references!(fp, [r .+ 0.05k for r in d.refs]; terminal = [r .- 0.02k for r in d.terminal])
        set_targets!(fp, fp.fleet.targets .* (1 + 0.002k))
        update!(R)
        refresh!(M, R.program)
        R2 = reduce(fp, R.resolution)
        q2 = sheaf_qp(R2.program)
        @test M.q ≈ q2.q && M.c ≈ q2.c
        @test M.b ≈ [q2.kinds[i] == SheafMPC.ROW_SOC ? q2.socb[i] : q2.u[i] for i in 1:nrows(q2)]
        J1, J2 = test_solve(R).J, test_solve(R2).J
        @test isfinite(J1) && srelerr(J1, J2) < 1e-8
    end
end

@testset "multipliers of merged duplicate rows" begin
    # a rigid fleet of identical quadrotors over the whole horizon repeats input cones
    fp, _ = test_program(n = 4, H = 4, graph = :ring, kinds = :quad, seed = 1, umax_scale = 0.1)
    R = reduce(fp, Teams(ones(Int, 4)) ⊠ full_condensing())
    full = sheaf_qp(R.program)
    M = QPMap(R.program)
    s = setup(M.qp; eps_abs = 1e-9, eps_rel = 1e-9, max_iter = 50_000)
    solve!(s)
    y = SheafMPC.expand_duals(M, s.ysol)
    @test norm(full.P * s.xsol + full.q + full.A' * y, Inf) < 1e-6
end

end
