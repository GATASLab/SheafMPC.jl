# conic.jl: the conic paths: second-order cone algebra of the interior-point
# method, the Moreau classification of the polish, the IPM against Clarabel,
# infeasibility, the duality gap test, the automatic method choice and
# crossover, and reduced programs with active input cones.

@testset "conic" begin

    @testset "second-order cone algebra" begin
        rng = Xoshiro(17)
        for d in (2, 3, 5)
            for _ in 1:20
                s = [2 + rand(rng); randn(rng, d - 1)]; s[1] = norm(s[2:end]) + 0.1 + rand(rng)
                z = [2 + rand(rng); randn(rng, d - 1)]; z[1] = norm(z[2:end]) + 0.1 + rand(rng)
                B = 1:d
                W = zeros(d, d); Wi = zeros(d, d); H = zeros(d, d); lam = zeros(d); wv = zeros(d)
                SheafMPC._soc_nt!(W, Wi, H, lam, s, z, B, wv)
                @test W * z ≈ Wi * s                       # Nesterov-Todd: W z = W^{-1} s = lambda
                @test lam ≈ W * z
                @test W * Wi ≈ I(d)
                @test H ≈ W * W
                @test H * z ≈ s
                # inverse Jordan product
                v = randn(rng, d); u = zeros(d); back = zeros(d)
                SheafMPC._jdiv!(u, lam, v, B)
                SheafMPC._jprod!(back, lam, u, B)
                @test back ≈ v
                # step to the boundary: largest a with s + a ds in the cone
                ds = 3 * randn(rng, d)
                a = SheafMPC._soc_step(s, ds, B)
                inK(v) = v[1] >= norm(v[2:end]) - 1e-9
                if isfinite(a)
                    @test inK(s + 0.999a * ds)
                    @test !inK(s + 1.001a * ds)
                else
                    @test inK(s + 1e6 * ds)
                end
            end
        end
    end

    @testset "Moreau classification of SOC blocks" begin
        # one SOC block b - A x in K with A = -I: the slack is b + x
        P = sparse(1.0I, 3, 3)
        p = ConicQP(P, zeros(3), sparse(-1.0I, 3, 3), [1.0, 0.0, 0.0], [(:soc, 3)])
        s = setup(p; scaling = 0)
        B = s.socs[1]
        w = zeros(3); y = zeros(3)
        cls(slack, mult, old = SheafMPC.ACT_NONE, band = 0.0) =
            (w .= s.socb .- slack; SheafMPC._soc_classify!(s, 1, B, w, mult, old, band))
        @test cls([1.0, 0.2, 0.0], zeros(3)) == SheafMPC.ACT_SOC_IN                  # slack inside, no multiplier
        @test cls([1.0, 1.3, 0.0], zeros(3)) == SheafMPC.ACT_SOC_ON                  # slack outside, no multiplier
        @test cls([1.0, 1.0, 0.0], [0.5, -0.5, 0.0]) == SheafMPC.ACT_SOC_ON          # a complementary boundary pair
        @test s.soc_u[2:3] ≈ [1.0, 0.0] && s.soc_tau[1] ≈ 1.0 && s.soc_eta[1] ≈ 0.5
        @test cls(zeros(3), [1.0, 0.1, 0.0]) == SheafMPC.ACT_SOC_APEX                # multiplier interior: apex
        # hysteresis: just inside the boundary, a block on the boundary stays there
        near = [1.0, 1.0 - 1e-6, 0.0]
        @test cls(near, zeros(3)) == SheafMPC.ACT_SOC_IN
        @test cls(near, zeros(3), SheafMPC.ACT_SOC_ON, 1e-4) == SheafMPC.ACT_SOC_ON
    end

    @testset "interior point vs Clarabel" begin
        rng = Xoshiro(23)
        for trial in 1:16
            p = isodd(trial) ? random_socp(rng, rand(rng, 8:30), rand(rng, 1:5), rand(rng, 2:5)) :
                random_qp(rng, rand(rng, 10:40), rand(rng, 10:30); rankdef = trial % 4 == 0)
            ref, _, st = clarabel_ref(p)
            @test st in (Clarabel.SOLVED, Clarabel.ALMOST_SOLVED)   # (the IPM below does solve these)
            for ls in (:qdldl, :cliquetrees, :blockldl, :auto)
                s = setup(p; eps_abs = 1e-9, eps_rel = 1e-9, method = :ipm, linsys = ls)
                info = solve!(s)
                @test info.status == :solved
                @test info.method == :ipm && info.ipm_iter <= 30
                @test relgap(info.obj, ref) <= 1e-7
                @test violation(p, s.xsol) <= 1e-7
            end
            # polished IPM solution: an exact active-set point
            s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, method = :ipm, ipm_polish = true, ipm_polish_final = true)
            info = solve!(s)
            @test info.status == :solved && relgap(info.obj, ref) <= 1e-7
            # the automatic choice
            info = solve!(setup(p; eps_abs = 1e-8, eps_rel = 1e-8))
            @test info.status == :solved && relgap(info.obj, ref) <= 1e-7
        end
    end

    @testset "infeasible and unbounded SOCPs" begin
        for meth in (:ipm, :auto)
            # ||(x1, x2)|| <= 1 and x1 >= 2
            A = sparse([0.0 0; -1 0; 0 -1; -1 0])
            p = ConicQP(sparse(1.0I, 2, 2), [0.0, 0.0], A, [1.0, 0.0, 0.0, -2.0], [(:soc, 3), (:nonneg, 1)])
            @test solve!(setup(p; method = meth)).status == :primal_infeasible
            # two disjoint balls: ||x|| <= 1 and ||x - (3, 0)|| <= 1
            A = sparse([0.0 0; -1 0; 0 -1; 0 0; -1 0; 0 -1])
            p = ConicQP(sparse(1.0I, 2, 2), [0.0, 0.0], A, [1.0, 0.0, 0.0, 1.0, -3.0, 0.0], [(:soc, 3), (:soc, 3)])
            @test solve!(setup(p; method = meth)).status == :primal_infeasible
            # unbounded: min -x2 with (x1, x2) in the cone, x1 free
            p = ConicQP(spzeros(2, 2), [0.0, -1.0], sparse(-1.0I, 2, 2), [0.0, 0.0], [(:soc, 2)])
            @test solve!(setup(p; method = meth)).status == :dual_infeasible
            # unbounded along a ray of a 3-cone with an equality: min -t, (t, u1, u2) in K, u1 = 1
            A = sparse([-1.0 0 0; 0 -1 0; 0 0 -1; 0 1 0])
            p = ConicQP(spzeros(3, 3), [-1.0, 0.0, 0.0], A, [0.0, 0.0, 0.0, 1.0], [(:soc, 3), (:zero, 1)])
            @test solve!(setup(p; method = meth)).status == :dual_infeasible
        end
        # the interval rows, through the IPM
        P = sparse([1.0 0; 0 1]); A = sparse([1.0 0; 1 1; 0 1])
        p = ConicQP(P, [1.0, 1.0], A, [1.0, -Inf, 0.0], [Inf, 0.0, Inf])
        @test solve!(setup(p; method = :ipm)).status == :primal_infeasible
        p = ConicQP(spzeros(2, 2), [-1.0, 0.0], sparse([1.0 0; 0 1]), [0.0, -1.0], [Inf, 1.0])
        @test solve!(setup(p; method = :ipm)).status == :dual_infeasible
    end

    @testset "duality gap test with cancelling terms" begin
        # a tracking cost with large and small weights (P x and q large and
        # cancelling at the optimum) under second-order cone constraints
        rng = Xoshiro(31)
        for trial in 1:6
            n = 30
            wts = [isodd(j) ? 1e3 : 1e-2 for j in 1:n]
            P = sparse(Diagonal(wts)); r = 5 * randn(rng, n)
            q = -P * r; c = 0.5 * dot(r, P * r)
            nb = 6
            rows = Int[]; cols = Int[]; vals = Float64[]; b = Float64[]
            for k in 1:nb
                for a in 1:3
                    push!(rows, 3(k - 1) + a + 1); push!(cols, mod1(5k + 7a, n)); push!(vals, -1.0)
                end
                append!(b, [1.0 + rand(rng), 0.0, 0.0, 0.0])
            end
            A = sparse([4(k - 1) + a for k in 1:nb for a in 2:4], cols, vals, 4nb, n)
            p = ConicQP(P, q, A, b, [(:soc, 4) for _ in 1:nb]; c = c)
            ref, _, st = clarabel_ref(p)
            for meth in (:admm, :ipm)
                s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7, method = meth, polish = false, max_iter = 100_000)
                info = solve!(s)
                @test info.status == :solved
                @test relgap(info.obj, ref) <= 1e-6
                @test info.gap <= 1e-7 + 1e-7 * abs(info.obj)
            end
        end
    end

    @testset "the IPM system is built lazily" begin
        rng = Xoshiro(43)
        for p in (random_socp(rng, 25, 5, 4), random_qp(rng, 30, 25))
            s = setup(p)                                       # :auto
            @test s.ipm === nothing
            @test isfinite(s.cost.t_ipm) && isfinite(s.cost.t_admm_iter)
            @test setup(p; method = :admm).ipm === nothing
            @test setup(p; method = :ipm).ipm !== nothing
            # a crossover builds it, and the solve still meets the tolerance
            # (no polish: it would be tried at the budget and could end the solve)
            ref, _, _ = clarabel_ref(p)
            s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, crossover = 1e-6, polish_interval = 0, polish = false)
            info = solve!(s)
            info.method == :admm_ipm && @test s.ipm !== nothing
            @test info.status == :solved && relgap(info.obj, ref) <= 1e-7
        end
    end

    @testset "crossover and the constant in update!" begin
        rng = Xoshiro(41)
        p = random_socp(rng, 25, 5, 4)
        ref, _, _ = clarabel_ref(p)
        s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, crossover = 1e-6, polish_interval = 0)
        info = solve!(s)
        @test info.method in (:admm_ipm, :admm) && info.status == :solved
        @test relgap(info.obj, ref) <= 1e-7
        # a new constant moves the reported objective by the difference
        o1 = info.obj
        update!(s; c = p.c + 3.0)
        @test solve!(s).obj ≈ o1 + 3.0 atol = 1e-6
        # :admm never crosses over
        info = solve!(setup(p; eps_abs = 1e-8, eps_rel = 1e-8, method = :admm, max_iter = 50_000))
        @test info.method == :admm && relgap(info.obj, ref) <= 1e-6
    end

    @testset "reduced programs with active input cones" begin
        for scale in (0.25, 0.15)
            sc = GridScenario(rows = 4, cols = 3, H = 8, coherence = :rows, umax_scale = scale, seed = 4)
            refs, term = references(sc)
            fp = FleetProgram(fleet(sc); x0 = formation_start(sc), references = refs, terminal = term)
            for res in (Teams(row_teams(sc)), Teams(strip_teams(sc, 2)))
                R = reduce(fp, res)
                qp = sheaf_qp(R.program)
                ref, _, st = clarabel_ref(qp)
                nact = 0
                for meth in (:admm, :ipm, :auto)
                    s = setup(qp; eps_abs = 1e-8, eps_rel = 1e-8, method = meth, max_iter = 100_000)
                    info = solve!(s)
                    @test info.status == :solved
                    @test relgap(info.obj, ref) <= 1e-7
                    nact = count(B -> norm(s.ysol[B]) > 1e-6, qp.socs)
                end
                @test nact > 0                                  # the input cones are active
            end
        end
        # closed loop with rows as teams (shifted warm starts) on tight input balls
        sc = GridScenario(rows = 4, cols = 4, H = 8, coherence = :rows, umax_scale = 0.15, seed = 7)
        fl = fleet(sc)
        ctrl = MPCController(fl, Teams(row_teams(sc)); certify = false, eps_abs = 1e-7, eps_rel = 1e-7)
        x = formation_start(sc)
        for step in 0:7
            refs, term = references(sc, step * sc.h)
            info = step!(ctrl, x, refs; terminal = term)
            @test info.status == :solved
            qp = SheafMPC._current_qp(ctrl.qmap)
            ref, _, _ = clarabel_ref(qp)
            @test relgap(ctrl.solver.info.obj - ctrl.solver.c0 + qp.c, ref) <= 1e-6
            @test relgap(info.J, ref) <= 1e-6
            x = plant_step(fl, x, info.u)
        end
    end
end
