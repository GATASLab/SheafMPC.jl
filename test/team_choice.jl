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
                @test colour_refinement(n, E, W, cls; within) == SheafMPC.colour_refinement_rounds(n, E, W, cls; within)
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
