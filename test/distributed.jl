# Distributed MPC by consensus ADMM over agents or teams.

@testset "distributed MPC" begin
    sc = GridScenario(rows = 2, cols = 3, H = 6, coherence = :agents, seed = 2)
    fl = fleet(sc)
    for teams in (collect(1:6), row_teams(sc))
        D = DistributedMPC(fl, teams; rho = 1.0, eps_abs = 1e-8, eps_rel = 1e-7)
        x = formation_start(sc)
        for k in 0:2
            refs, term = references(sc, k * sc.h)
            info = step!(D, x, refs; terminal = term)
            @test info.status == :solved && D.converged
            # the centralized solve of the same reduction
            fp = FleetProgram(fl; x0 = x, references = refs, terminal = term)
            R = reduce(fp, Teams(teams) ⊠ full_condensing())
            ref = test_solve(R)
            @test abs(info.J - ref.J) <= 1e-4 * abs(ref.J)
            u = first_inputs(fp, lift(R, ref))
            @test maximum(norm(info.u[i] - u[i]) for i in 1:6) < 1e-2
            @test D.floats == D.iterations * floats_per_iteration(D)
            x = plant_step(fl, x, info.u)
        end
    end
    # a fixed budget of iterations per step
    D = DistributedMPC(fl; budget = 5)
    refs, term = references(sc)
    info = step!(D, formation_start(sc), refs; terminal = term)
    @test info.iter == 5 && all(isfinite, reduce(vcat, info.u))

    @testset "shifted warm start" begin
        # the closed-loop cost (true stage cost, formation included) over coordinated MPC, one ADMM iteration per step
        scw = GridScenario(rows = 3, cols = 3, H = 8, coherence = :agents, seed = 1)
        flw = fleet(scw)
        function closed_loop(c; steps = 10)
            x = formation_start(scw); J = 0.0
            for k in 0:(steps-1)
                r, rf = references(scw, k * scw.h)
                u = step!(c, x, r; terminal = rf).u
                J += sum(0.5 * dot(flw.agents[i].Cr * x[i] - r[i][:, 1], flw.agents[i].Q * (flw.agents[i].Cr * x[i] - r[i][:, 1])) +
                         0.5 * dot(u[i], flw.agents[i].R * u[i]) for i in eachindex(x))
                J += sum(0.5 * flw.weights[e, 1] * sum(abs2, flw.agents[j].C * x[j] - flw.agents[i].C * x[i] - flw.targets[:, e, 1])
                         for (e, (i, j)) in enumerate(flw.edges))
                x = plant_step(flw, x, u)
            end
            return J
        end
        Jc = closed_loop(MPCController(flw, Fine(); certify = false))
        Js = closed_loop(DistributedMPC(flw; rho = 0.3, budget = 1))
        Jp = closed_loop(DistributedMPC(flw; rho = 0.3, budget = 1, warm = :previous))
        @test Js / Jc < 1.06
        @test Js < Jp
        # converged, the warm start does not change the plans
        D1 = DistributedMPC(flw; rho = 0.3, eps_abs = 1e-8, eps_rel = 1e-7)
        D2 = DistributedMPC(flw; rho = 0.3, eps_abs = 1e-8, eps_rel = 1e-7, warm = :previous)
        x = formation_start(scw)
        it1 = 0; it2 = 0
        for k in 0:3
            r, rf = references(scw, k * scw.h)
            i1 = step!(D1, x, r; terminal = rf); i2 = step!(D2, x, r; terminal = rf)
            @test D1.converged && D2.converged
            @test srelerr(i1.J, i2.J) < 1e-5
            k > 0 && (it1 += i1.iter; it2 += i2.iter)
            x = plant_step(flw, x, i1.u)
        end
        @test it1 < it2
        # the dual shift moves every interface row to the next instant (the last held)
        I1 = D1.ifs[1]
        @test length(I1.shift) == 2 * scw.H
        @test I1.shift == [collect(3:(2*scw.H)); 2 * scw.H - 1; 2 * scw.H]
        # the shifted plan: one instant earlier, the measured first state, every later dynamics edge satisfied
        fp = D1.fp
        xs = shift_plan(fp, plan(D1), x)
        X0, U0 = trajectories(fp, plan(D1)); X1, U1 = trajectories(fp, xs)
        @test X1[1][:, 1] == x[1] && X1[2][:, 2:scw.H] == X0[2][:, 3:(scw.H+1)] && U1[3][:, 1:(scw.H-1)] == U0[3][:, 2:scw.H]
        @test U1[3][:, scw.H] == U0[3][:, scw.H]
        Pf = fp.program
        @test maximum(maximum(abs, edge_defect(Pf, fp.dyn[i, t], xs)) for i in 1:9, t in 2:scw.H) < 1e-10
        # restrict inverts the lift, with or without the cached factorizations
        R = D1.R
        y = randn(Xoshiro(3), c0dim(R.program))
        @test norm(restrict(R, lift(R, y)) - y) < 1e-8 * norm(y)
        @test restrict!(zeros(length(y)), R, lift(R, y)) == restrict(R, lift(R, y))
    end

    @testset "every step terminates with a status" begin
        sct = GridScenario(rows = 2, cols = 3, H = 6, coherence = :agents, seed = 4)
        flt = fleet(sct)
        x = formation_start(sct)
        refs, term = references(sct)
        # rho far too small or too large: the iteration cap ends the step, reported as such
        for rho in (1e-7, 1e7)
            D = DistributedMPC(flt; rho = rho, maxit = 25)
            info = step!(D, x, refs; terminal = term)
            @test info.iter == 25 && info.status == :max_iter && !D.converged
            @test all(isfinite, reduce(vcat, info.u))
        end
        # the time limit (checked after every iteration)
        D = DistributedMPC(flt; rho = 1e-7, maxit = 10^9, time_limit = 1e-3)
        t = @elapsed info = step!(D, x, refs; terminal = term)
        @test info.status == :time_limit && !D.converged && t < 5
        # a NaN in the data stops the iteration at once, and the next step starts afresh
        D = DistributedMPC(flt; rho = 1.0)
        bad = deepcopy(refs); bad[2][1, 3] = NaN
        t = @elapsed info = step!(D, x, bad; terminal = term)
        @test info.status == :numerical_error && info.iter == 1 && !D.converged
        @test D.local_failures <= 1 && t < 5           # at most one local solve runs into the NaN
        info = step!(D, x, refs; terminal = term)
        @test info.status == :solved && D.converged && all(isfinite, plan(D))
        # bad arguments
        @test_throws ArgumentError DistributedMPC(flt; rho = NaN)
        @test_throws ArgumentError DistributedMPC(flt; rho = -1.0)
        @test_throws ArgumentError DistributedMPC(flt; maxit = 0)
        @test_throws ArgumentError DistributedMPC(flt; warm = :sideways)
    end
end
