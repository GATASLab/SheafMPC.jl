# The per-team certificate (Thm. 2) on the condensed QP.

"The coordinated optimum's plan from an MPCController step, stacked for `cq`."
function coord_plan(fl, x, refs, term, cq)
    co = MPCController(fl, full_condensing(); certify = false, eps_abs = 1e-9, eps_rel = 1e-9)
    step!(co, x, refs; terminal = term)
    _, U = trajectories(co.fp, plan(co))
    return stack_inputs(cq, U)
end

@testset "team certificate" begin
    @testset "condensed QP matches the program's objective" begin
        sc = GridScenario(rows = 2, cols = 3, H = 5, coherence = :agents)
        fl = fleet(sc); x = formation_start(sc); refs, term = references(sc)
        cq = CondensedQP(fl, x, refs; terminal = term)
        co = MPCController(fl, full_condensing(); certify = false, eps_abs = 1e-10, eps_rel = 1e-10)
        info = step!(co, x, refs; terminal = term)
        u = coord_plan(fl, x, refs, term, cq)
        @test relgap(objective(cq, u), info.J) < 1e-6
    end

    @testset "zero for lossless teams, at least the gap otherwise" begin
        for (coh, part, lossless) in ((:rows, :rows, true), (:fleet, :kinds, false))
            sc = GridScenario(rows = 4, cols = 3, H = 6, coherence = coh, umax_scale = 0.3)
            fl = fleet(sc)
            D = slot_offsets(fl, slots(sc))
            teams_ = part == :rows ? row_teams(sc) : [agent_kind(sc, i) == :quadrotor ? 1 : 2 for i in 1:nagents(sc)]
            tm = TeamMPC(fl, teams_; offsets = D, eps_abs = 1e-9, eps_rel = 1e-9)
            x = formation_start(sc)
            for k in 0:2
                refs, term = references(sc, k * sc.h)
                u = step!(tm, x, refs; terminal = term)
                cert, Jt, cq = certificate(tm, x, refs; terminal = term)
                Jc = objective(cq, coord_plan(fl, project(tm, x), refs, term, cq))
                gap = Jt - Jc
                @test gap >= -1e-5 * max(1, abs(Jc))
                @test cert >= gap - 1e-5 * max(1, abs(Jc))
                lossless ? (@test cert < 1e-5 * max(1, abs(Jc))) : (@test gap > 1e-6 && cert > 1e-6)
                x = plant_step(fl, x, deepcopy(u))
            end
            kap = team_kappa(CondensedQP(fl, x, references(sc)[1]; terminal = references(sc)[2]), teams_)
            @test kap >= 1 - 1e-8
        end
    end

    @testset "nonnegative least squares" begin
        rng = Xoshiro(4)
        for _ in 1:50
            Y = randn(rng, 6, 4); y = randn(rng, 6)
            c = SheafMPC._nnls(Y, y)
            @test all(c .>= 0)
            g = Y' * (Y * c + y)                       # KKT: g >= 0, g = 0 on the support
            @test all(g .>= -1e-8)
            @test all(abs.(g[c .> 1e-10]) .< 1e-8)
        end
    end
end
