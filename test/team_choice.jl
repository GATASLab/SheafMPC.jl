# Choosing teams: fast colour refinement, lossless and quasi-stable teams.

function rand_graph(rng, n, m)
    E = Tuple{Int,Int}[]
    for _ in 1:m
        i, j = rand(rng, 1:n), rand(rng, 1:n)
        i == j || push!(E, (i, j))
    end
    return E
end

@testset "choosing teams" begin
    @testset "fast refinement equals the rounds" begin
        rng = Xoshiro(11)
        for trial in 1:500
            n = rand(rng, 1:30); E = rand_graph(rng, n, rand(rng, 0:3n))
            W = rand(rng, Bool) ? ones(length(E)) : rand(rng, [0.5, 1.0, 2.0], length(E))
            cls = rand(rng, 1:rand(rng, 1:3), n)
            for within in (false, true)
                @test colour_refinement(n, E, W, cls; within) == TeamMPC.colour_refinement_rounds(n, E, W, cls; within)
            end
        end
    end

    @testset "fast on large graphs" begin
        n = 10_000
        E = [(i, i + 1) for i in 1:n-1]
        colour_refinement(n, E, 1.0, ones(Int, n))
        t = @elapsed a = colour_refinement(n, E, 1.0, ones(Int, n); within = true)
        @test maximum(a) == n ÷ 2                      # mirror pairs of the path
        @test t < 1.0
        E, _ = grid_graph(64, 64)
        cls = [isodd(div(i - 1, 64) + 1) ? 1 : 2 for i in 1:64^2]
        @test maximum(colour_refinement(64^2, E, 1.0, cls)) == 64          # the rows
    end

    @testset "quasi-stable teams: definition and the rounds" begin
        rng = Xoshiro(13)
        nnew = 0; nold = 0
        for trial in 1:400
            n = rand(rng, 2:60); E = rand_graph(rng, n, rand(rng, 0:4n))
            W = rand(rng, Bool) ? ones(length(E)) : 0.1 .+ rand(rng, length(E))
            rand(rng) < 0.2 && !isempty(E) && (W[rand(rng, 1:length(E))] = 0.0)   # a zero weight is no edge
            cls = rand(rng, 1:rand(rng, 1:4), n)
            q = rand(rng, (0.0, 0.05, 0.3, 1.0, 2.0, 4.0, 8.0))
            lab = quasi_stable_teams(n, E, W, cls; q = q)
            @test lab == canonical_partition(lab)
            @test all(cls[i] == cls[j] for i in 1:n, j in 1:n if lab[i] == lab[j])        # refines the classes
            @test team_spread(n, E, W, lab)[1] <= q + 1e-9                                # q-quasi-stable
            q == 0 && @test lab == colour_refinement(n, E, W, cls)
            old = TeamMPC.quasi_stable_teams_rounds(n, E, W, cls; q = q)
            @test team_spread(n, E, W, old)[1] <= q + 1e-9
            nnew += maximum(lab); nold += maximum(old)
        end
        @test nnew <= 1.05 * nold                         # not finer than the rounds overall
        # geometric graphs with two large classes: as coarse as the rounds, and fast
        for (n, seed) in ((300, 1), (1000, 2))
            r2 = Xoshiro(seed); pts = [sqrt(n) .* rand(r2, 2) for _ in 1:n]
            E = [(i, j) for i in 1:n for j in (i+1):n if norm(pts[i] - pts[j]) < 1.5]
            W = [1 / norm(pts[i] - pts[j]) for (i, j) in E]
            cls = [1 + (floor(Int, pts[i][1] / 3) % 2) for i in 1:n]
            for q in (0.5, 2.0, 8.0)
                lab = quasi_stable_teams(n, E, W, cls; q)
                @test team_spread(n, E, W, lab)[1] <= q + 1e-9
                @test maximum(lab) <= 1.1 * maximum(TeamMPC.quasi_stable_teams_rounds(n, E, W, cls; q))
            end
            t = @elapsed quasi_stable_teams(n, E, W, cls; q = 2.0)
            @test t < 0.2
        end
        @test_throws ArgumentError quasi_stable_teams(3, [(1, 4)], 1.0, ones(Int, 3); q = 1)
        @test_throws DimensionMismatch quasi_stable_teams(3, [(1, 2)], 1.0, ones(Int, 2); q = 1)
        @test quasi_stable_teams(0, Tuple{Int,Int}[], 1.0, Int[]; q = 1) == Int[]
    end

    @testset "lossless and quasi-stable teams" begin
        rng = Xoshiro(12)
        for trial in 1:150
            n = rand(rng, 4:40); E = rand_graph(rng, n, rand(rng, n:3n))
            W = 0.5 .+ rand(rng, length(E))
            cls = rand(rng, 1:rand(rng, 1:3), n)
            refines(lab) = all(cls[i] == cls[j] for i in 1:n, j in 1:n if lab[i] == lab[j])
            for q in (0.0, 0.1, 0.5, 1.0, 2.0, 8.0)
                lab = quasi_stable_teams(n, E, W, cls; q = q)
                @test refines(lab)
                @test team_spread(n, E, W, lab)[1] <= q + 1e-9
                q == 0 && @test is_almost_equitable(n, E, W, lab)
            end
        end
        sc = GridScenario(rows = 4, cols = 6, H = 4, coherence = :rows)
        fl = fleet(sc)
        cls = [agent_kind(sc, i) == :quadrotor ? 2div(i - 1, 6) : 1 + 2div(i - 1, 6) for i in 1:24]   # one class per row
        @test lossless_teams(fl; classes = cls) == canonical_partition(row_teams(sc))
        @test maximum(data_classes(fl)) == 2
        @test team_spread(fl, row_teams(sc))[1] == 0
    end
end
