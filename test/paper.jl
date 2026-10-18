# Tests against the paper repository (read only): the fleet QP of the
# centralized benchmark and sheaf programs (fine and pushed forward) of the
# Resolution module, both against Clarabel.

haskey(ENV, "BENCH_ABAR") || (ENV["BENCH_ABAR"] = "1.0")
module FleetQP
using SparseArrays, LinearAlgebra
include(joinpath(Main.PAPER, "bench", "central", "qp.jl"))
end
# the paper's research module is also called `Resolution`, like the package's
# abstract type: keep it inside a module of its own
module Paper
include(joinpath(Main.PAPER, "scripts", "resolution", "src", "Resolution.jl"))
end
const Res = Paper.Resolution

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
    for (cfg, label) in ((Res.MPCConfig(n = 6, H = 8, graph = :ring, fleet = :mixed, obstacle = true, seed = 3), "ring, obstacle"),
                         (Res.MPCConfig(n = 6, H = 8, graph = :grid, fleet = :rows, abar_scale = 0.3, seed = 2), "grid, active inputs"),
                         (Res.MPCConfig(n = 5, H = 6, typing = :virtual, wind = 0.5, seed = 4), "virtual dynamics"))
        model = Res.build_model(cfg)
        P = model.program
        sol = Res.solve_direct(P)
        @test Res.isoptimal(sol)
        qp = sheaf_qp(P)
        s = setup(qp; eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 50_000)
        info = solve!(s)
        @test info.status == :solved
        @test relgap(info.obj, sol.J) <= 1e-6
        @test relgap(Res.objective(P, s.xsol), sol.J) <= 1e-6
        # the pushforward along agent clusters (spatial) and a time blocking
        rng = Random.Xoshiro(1)
        n, H = model.spec.n, model.spec.H
        for Pi in (Res.product_partition(model, [cld(i, 2) for i in 1:n], 1:(H+1)),
                   Res.product_partition(model, collect(1:n), Res.random_time_blocking(H, rng)))
            Pc, L = Res.pushforward(P, Pi)
            Pc === nothing && continue
            solc = Res.solve_direct(Pc)
            Res.isoptimal(solc) || continue
            sc = setup(sheaf_qp(Pc); eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 50_000)
            ic = solve!(sc)
            @test ic.status == :solved
            @test relgap(ic.obj, solc.J) <= 1e-6
            # the lifted plan is feasible for the fine program and has the same value
            z = Res.lift(L, sc.xsol)
            @test relgap(Res.objective(P, z), solc.J) <= 1e-6
            @test Res.feasibility(P, z).hard <= 1e-6
        end
    end
end

@testset "fleet QP with second-order cone inputs: Newton polish" begin
    for n in (1, 4), b in (1, 8)
        Q = FleetQP.blocked_qp(n, 24, b)
        ny = length(Q.q); nb = length(Q.ubox)
        I = Int[]; J = Int[]; V = Float64[]; bb = Float64[]; row = 0
        cones = Tuple{Symbol,Int}[(:zero, size(Q.Aeq, 1))]
        for k in 1:2:nb
            row += 1; push!(bb, FleetQP.ABAR)
            for a in 0:1
                row += 1; push!(I, row); push!(J, Q.ubox[k+a]); push!(V, -1.0); push!(bb, 0.0)
            end
            push!(cones, (:soc, 3))
        end
        p = ConicQP(Q.P, Q.q, [Q.Aeq; sparse(I, J, V, row, ny)], [Q.beq; bb], cones; c = Q.c)
        ref, _, _ = clarabel_ref(p)
        s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7)
        info = solve!(s)
        @test info.status == :solved && info.polish == :success
        @test relgap(info.obj, ref) <= 1e-8
        @test violation(p, s.xsol) <= 1e-7
    end
end

"""The package's `Fleet` for the data of a research `MPCSpec` (hard dynamics)."""
function fleet_from_spec(spec)
    H = spec.H
    agents = Agent[]
    for (i, ag) in enumerate(spec.agents)
        Sv = zeros(length(ag.vel), ag.nx)
        for (k, j) in enumerate(ag.vel)
            Sv[k, j] = 1.0
        end
        nyr = size(ag.Cr, 1)
        Qf = zeros(nyr + length(ag.vel), nyr + length(ag.vel))
        Qf[1:nyr, 1:nyr] .= ag.Qf
        Qf[(nyr+1):end, (nyr+1):end] .= ag.qv * I(length(ag.vel))
        states = Union{Nothing,Polyhedron}[]
        for t in 1:H
            hs = [(a, beta) for (tt, a, beta) in spec.halfspaces[i] if tt == t]
            push!(states, isempty(hs) ? nothing :
                  Polyhedron(reduce(vcat, [-(a' * ag.C) for (a, _) in hs]), [-beta for (_, beta) in hs]))
        end
        push!(agents, Agent(ag.A, ag.B; g = ag.c, C = ag.C, Cr = ag.Cr, Q = ag.Q, R = ag.R, Cf = [ag.Cr; Sv], Qf = Qf,
                            input = BallSet(ag.abar), state = states))
    end
    fl = Fleet(agents, spec.gedges; H = H, targets = spec.ftarget, weights = spec.fweight, present = spec.present)
    term = [[spec.ref[i][:, H+1]; spec.vref[i]] for i in 1:spec.n]
    return FleetProgram(fl; x0 = spec.xhat, references = spec.ref, terminal = term, absent = spec.absent)
end

@testset "the package's fleet program and reductions = the research module's" begin
    for cfg in (Res.MPCConfig(n = 6, H = 8, graph = :ring, fleet = :mixed, obstacle = true, seed = 3),
                Res.MPCConfig(n = 6, H = 6, graph = :grid, fleet = :rows, abar_scale = 0.3, seed = 2),
                Res.MPCConfig(n = 5, H = 6, graph = :rgg, fleet = :mixed, time_varying = true, switching = 0.3, wind = 0.4, seed = 5),
                Res.MPCConfig(n = 4, H = 5, graph = :complete, fleet = :rover, switching = 0.4, absent = :zero, seed = 7))
        model = Res.build_model(cfg)
        fp = fleet_from_spec(model.spec)
        q1, q2 = sheaf_qp(model.program), sheaf_qp(fp.program)
        @test q1.P ≈ q2.P && q1.q ≈ q2.q && q1.c ≈ q2.c
        @test q1.A ≈ q2.A && q1.l ≈ q2.l && q1.u ≈ q2.u && q1.socs == q2.socs && q1.socb ≈ q2.socb
        sol = Res.solve_direct(model.program)
        Res.isoptimal(sol) || continue
        @test relgap(test_solve(fp).J, sol.J) <= 1e-7
        n, H = model.spec.n, model.spec.H
        rng = Random.Xoshiro(2)
        for (alpha, beta) in (([cld(i, 2) for i in 1:n], collect(1:(H+1))), (collect(1:n), Res.random_time_blocking(H, rng)),
                              ([cld(i, 3) for i in 1:n], Res.random_time_blocking(H, rng)))
            Pc, L = Res.pushforward(model.program, Res.product_partition(model, alpha, beta); basis = :structured)
            R = reduce(fp, Teams(alpha) ⊠ TimeBlocking(beta))
            @test (Pc === nothing) == !R.feasible
            Pc === nothing && continue
            @test Res.c0dim(Pc) == c0dim(R.program)
            solc = Res.solve_direct(Pc)
            Res.isoptimal(solc) || continue
            @test relgap(test_solve(R).J, solc.J) <= 1e-7
        end
    end
end
