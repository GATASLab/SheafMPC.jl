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
end
