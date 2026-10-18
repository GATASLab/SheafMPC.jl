# The receding-horizon controller.

@testset "controller" begin

sc = GridScenario(rows = 4, cols = 4, H = 8, coherence = :agents, seed = 5)
fl = fleet(sc)

@testset "a step solves the reduced program of the current data" begin
    for res in (Fine(), Teams(row_teams(sc)), Teams(strip_teams(sc, 2)) ⊠ partial_condensing(4), full_condensing())
        ctrl = MPCController(fl, res; eps_abs = 1e-8, eps_rel = 1e-8)
        x = formation_start(sc)
        local info
        for k in 0:2
            refs, term = references(sc, k * sc.h)
            info = step!(ctrl, x, refs; terminal = term)
            @test info.status == :solved
            # offline: the same reduction of the same data
            fp = FleetProgram(fl; x0 = x, references = refs, terminal = term)
            off = res isa Fine ? test_solve(fp) : test_solve(reduce(fp, res))
            @test srelerr(info.J, off.J) < 1e-6
            u_off = first_inputs(fp, res isa Fine ? off.x : lift(reduce(fp, res), off))
            @test maximum(norm(info.u[i] - u_off[i]) for i in eachindex(u_off)) < 1e-4
            @test all(norm(info.u[i]) <= fl.agents[i].input.radius + 1e-6 for i in eachindex(info.u))
            x = plant_step(fl, x, info.u)
        end
        if res isa Teams
            @test isfinite(info.gap_upper) && info.gap_upper >= 0
        end
    end
end

@testset "teams of teams" begin
    ctrl = MPCController(fl, [Teams(row_teams(sc)), Teams([1, 1, 2, 2])])
    refs, term = references(sc)
    info = step!(ctrl, formation_start(sc), refs; terminal = term)
    fp = FleetProgram(fl; x0 = formation_start(sc), references = refs, terminal = term)
    @test info.status == :solved
    @test srelerr(info.J, test_solve(reduce(fp, Teams(strip_teams(sc, 2)))).J) < 1e-5
    @test feasibility(fp.program, plan(ctrl)).hard < 1e-8
end

@testset "30 steps without allocation growth" begin
    ctrl = MPCController(fl, Teams(row_teams(sc)))
    x = formation_start(sc)
    allocs = Int[]
    for k in 0:29
        refs, term = references(sc, k * sc.h)
        a = @allocated (info = step!(ctrl, x, refs; terminal = term))
        push!(allocs, a)
        @test info.status == :solved
        x = plant_step(fl, x, info.u)
    end
    @test maximum(allocs[3:end]) <= 1024              # a few bytes of keyword handling, constant
    @test maximum(allocs[21:30]) <= maximum(allocs[3:12])
    @test ctrl.steps == 30
    @test ctrl.info.t_total > 0 && ctrl.info.t_construct > 0
end

end
