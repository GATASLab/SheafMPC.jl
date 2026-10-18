# Tests against the paper repository (read only): the fleet QP of the
# centralized benchmark and sheaf programs (fine and pushed forward) of the
# Resolution module, both against Clarabel.

haskey(ENV, "BENCH_ABAR") || (ENV["BENCH_ABAR"] = "1.0")
module FleetQP
using SparseArrays, LinearAlgebra
include(joinpath(Main.PAPER, "bench", "central", "qp.jl"))
end
if !isdefined(Main, :Resolution)
    include(joinpath(PAPER, "scripts", "resolution", "src", "Resolution.jl"))
end
import .Resolution

function fleet_conic(Q, abar)
    ny = length(Q.q); nb = length(Q.ubox)
    Ab = sparse(1:nb, Q.ubox, ones(nb), nb, ny)
    return ConicQP(Q.P, Q.q, [Q.Aeq; Ab], [Q.beq; fill(-abar, nb)], [Q.beq; fill(abar, nb)]; c = Q.c)
end

@testset "fleet QP (bench/central) vs Clarabel" begin
    for n in (1, 4, 16), b in (1, 8)
        Q = FleetQP.blocked_qp(n, 24, b)
        p = fleet_conic(Q, FleetQP.ABAR)
        ref, _, st = clarabel_ref(p)
        s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7)
        info = solve!(s)
        @test info.status == :solved
        @test info.polish == :success
        @test relgap(info.obj, ref) <= 1e-8
        @test violation(p, s.xsol) <= 1e-9
        @test info.obj ≈ FleetQP.objective(Q, s.xsol)
        # a second solve from the solution is polished before any iteration
        info = solve!(s)
        @test info.iter == 0 && relgap(info.obj, ref) <= 1e-8
    end
end

@testset "sheaf programs (Resolution) vs Clarabel" begin
    for (cfg, label) in ((Resolution.MPCConfig(n = 6, H = 8, graph = :ring, fleet = :mixed, obstacle = true, seed = 3), "ring, obstacle"),
                         (Resolution.MPCConfig(n = 6, H = 8, graph = :grid, fleet = :rows, abar_scale = 0.3, seed = 2), "grid, active inputs"),
                         (Resolution.MPCConfig(n = 5, H = 6, typing = :virtual, wind = 0.5, seed = 4), "virtual dynamics"))
        model = Resolution.build_model(cfg)
        P = model.program
        sol = Resolution.solve_direct(P)
        @test Resolution.isoptimal(sol)
        qp = sheaf_qp(P)
        s = setup(qp; eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 50_000)
        info = solve!(s)
        @test info.status == :solved
        @test relgap(info.obj, sol.J) <= 1e-6
        @test relgap(Resolution.objective(P, s.xsol), sol.J) <= 1e-6
        # the pushforward along agent clusters (spatial) and a time blocking
        rng = Random.Xoshiro(1)
        n, H = model.spec.n, model.spec.H
        for Pi in (Resolution.product_partition(model, [cld(i, 2) for i in 1:n], 1:(H+1)),
                   Resolution.product_partition(model, collect(1:n), Resolution.random_time_blocking(H, rng)))
            Pc, L = Resolution.pushforward(P, Pi)
            Pc === nothing && continue
            solc = Resolution.solve_direct(Pc)
            Resolution.isoptimal(solc) || continue
            sc = setup(sheaf_qp(Pc); eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 50_000)
            ic = solve!(sc)
            @test ic.status == :solved
            @test relgap(ic.obj, solc.J) <= 1e-6
            # the lifted plan is feasible for the fine program and has the same value
            z = Resolution.lift(L, sc.xsol)
            @test relgap(Resolution.objective(P, z), solc.J) <= 1e-6
            @test Resolution.feasibility(P, z).hard <= 1e-6
        end
    end
end
