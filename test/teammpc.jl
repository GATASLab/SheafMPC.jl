# Team MPC (Algorithm 1): the quotient program, projection, broadcast and feedback.

"A scalar single integrator agent (formation output its position)."
integrator(; r = 0.1) = Agent(fill(1.0, 1, 1), fill(1.0, 1, 1); C = fill(1.0, 1, 1), Q = fill(1.0, 1, 1),
                              R = fill(r, 1, 1), Qf = fill(1.0, 1, 1))

"The path 1-2-3-4 of the paper's Example 2 with unit weights and zero targets."
path4(H) = Fleet([integrator() for _ in 1:4], [(1, 2), (2, 3), (3, 4)]; H = H)

"Run `steps` steps of a controller (`TeamMPC` or `MPCController`) on the nominal plant; returns the applied inputs."
function run_loop(ctrl, fl, x, refs_of; steps)
    us = Vector{Vector{Vector{Float64}}}()
    for k in 0:(steps-1)
        refs, term = refs_of(k)
        out = step!(ctrl, x, refs; terminal = term)
        u = deepcopy(out isa StepInfo ? out.u : out)
        push!(us, u)
        x = plant_step(fl, x, u)
    end
    return us
end

maxdiff(a, b) = maximum(maximum(norm(p - q, Inf) for (p, q) in zip(x, y)) for (x, y) in zip(a, b))

@testset "team MPC" begin
    @testset "grid rows: the inputs of coordinated MPC" begin
        sc = GridScenario(rows = 4, cols = 4, H = 8, coherence = :rows)
        fl = fleet(sc)
        D = slot_offsets(fl, slots(sc))
        tm = TeamMPC(fl, row_teams(sc); offsets = D)
        @test length(teams(tm)) == 4
        @test tm.quotient.residual < 1e-12
        co = MPCController(fl, full_condensing(); certify = false)
        refs_of(k) = references(sc, k * sc.h)
        x0 = formation_start(sc)
        ut = run_loop(tm, fl, x0, refs_of; steps = 5)
        uc = run_loop(co, fl, x0, refs_of; steps = 5)
        @test maxdiff(ut, uc) < 1e-5
        @test stepinfo(tm).status == :solved
        @test tm.t_team >= 0
    end

    @testset "path example: {1,4},{2,3} lossless, {1,2},{3,4} not" begin
        H = 6
        fl = path4(H)
        co = MPCController(fl, full_condensing(); certify = false)
        rng = Xoshiro(3)
        good = [1, 2, 2, 1]; bad = [1, 1, 2, 2]
        @test is_almost_equitable(4, fl.edges, ones(3), good)
        @test !is_almost_equitable(4, fl.edges, ones(3), bad)
        for (part, lossless) in ((good, true), (bad, false))
            tm = TeamMPC(fl, part; gains = nothing)
            worst = 0.0
            for trial in 1:5
                ra, rb = randn(rng), randn(rng)                 # one reference per team: coherent data
                ref = [fill(part[i] == 1 ? ra : rb, 1, H + 1) for i in 1:4]
                xa, xb = randn(rng), randn(rng)
                x = [[part[i] == 1 ? xa : xb] for i in 1:4]      # teams start in formation
                u1 = deepcopy(step!(tm, x, ref))
                u2 = deepcopy(step!(co, x, ref).u)
                worst = max(worst, maximum(abs(a[1] - b[1]) for (a, b) in zip(u1, u2)))
            end
            lossless ? (@test worst < 1e-6) : (@test worst > 1e-3)
        end
    end

    @testset "projection and feedback" begin
        sc = GridScenario(rows = 2, cols = 3, H = 6, coherence = :rows)
        fl = fleet(sc)
        D = slot_offsets(fl, slots(sc))
        x = formation_start(sc)
        x[2] = x[2] .+ [0.3, -0.2, 0.1, 0.0, 0.0, 0.0]          # one quadrotor off its slot
        for gains in (:lqr, nothing)
            tm = TeamMPC(fl, row_teams(sc); offsets = D, gains = gains)
            xt = project(tm, x)
            for m in teams(tm), i in m
                @test norm((xt[i] - D[i]) - (xt[m[1]] - D[m[1]])) < 1e-12
            end
            # the projection keeps the team mean
            for m in teams(tm)
                @test norm(sum(xt[i] - D[i] for i in m) - sum(x[i] - D[i] for i in m)) < 1e-12
            end
        end
        dev(tm, x) = maximum(norm(x[i] - project(tm, x)[i]) for i in eachindex(x))
        function closed(gains)
            tm = TeamMPC(fl, row_teams(sc); offsets = D, gains = gains)
            y = deepcopy(x)
            for k in 0:14
                refs, term = references(sc, k * sc.h)
                y = plant_step(fl, y, deepcopy(step!(tm, y, refs; terminal = term)))
            end
            return dev(tm, y)
        end
        d0 = dev(TeamMPC(fl, row_teams(sc); offsets = D), x)
        @test closed(:lqr) < 0.2 * d0
        @test closed(nothing) > 0.5 * d0                         # equal inputs cannot remove a mismatch
    end

    @testset "checks" begin
        fl = Fleet([integrator(), integrator(r = 0.2), integrator()], [(1, 2), (2, 3)]; H = 4)
        @test_throws ArgumentError TeamMPC(fl, [1, 1, 2])
        @test_throws ArgumentError TeamMPC(fleet(GridScenario(rows = 2, cols = 2, H = 4)), [1, 1, 2, 2];
                                           offsets = [[1.0, 0, 0, 1.0, 0, 0], zeros(6), zeros(4), zeros(4)])
        K = lqr_gain([1.0 1.0; 0 1.0], reshape([0.5, 1.0], 2, 1), Matrix(1.0I, 2, 2), fill(0.1, 1, 1))
        @test maximum(abs, eigvals([1.0 1.0; 0 1.0] - reshape([0.5, 1.0], 2, 1) * K)) < 1
    end
end
