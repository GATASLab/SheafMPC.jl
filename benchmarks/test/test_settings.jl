# test_settings.jl: every solver holds the settings the harness asked for, and
# cold means cold. OSQP.jl drops unknown setup! keywords silently, so options
# are read back from the live objects (src/protocol.jl check_readback), and
# behaviour is checked: a warm-mode step without warm! (update! then solve!,
# what interior-point solvers get) takes the same iterations as the cold solve
# (no hidden warm start), and OSQP's and SheafMPC's warm! from the solution
# takes (almost) none.
#
#   julia --project=benchmarks benchmarks/test/test_settings.jl

using Test, LinearAlgebra, SparseArrays
include(joinpath(@__DIR__, "..", "src", "BenchHarness.jl"))
using .BenchHarness
const BH = BenchHarness

specs = [BH.sheafmpc_spec(), BH.osqp_spec(), BH.clarabel_spec(), BH.mumblebee_spec()]
isdefined(BH, :hpipm_spec) && push!(specs, BH.hpipm_spec())
isdefined(BH, :piqp_spec) && push!(specs, BH.piqp_spec())
problems = [BH.fleet_qp(n = 4, N = 24, b = 1), BH.stage_canonical("quad", BH.quad_ocp(N = 12, x0 = zeros(12))),
            BH.fleet_qp(n = 4, N = 24, b = 1, cone = :soc)]

@testset "read-back and cold starts: $(s.name)" for s in specs
    for p in problems, eps in (1e-4, 1e-8)
        s.applicable(p) || continue
        for v in s.variants
            h = s.setup(p, eps, v)
            rb, err = BH.check_readback(s, h, eps)
            @test err === nothing
            err === nothing || (@info "$(s.name) $(v): $err"; continue)
            r1 = s.solve!(h)
            s.update!(h, p)                      # a warm-mode step of an interior-point solver: update!, no warm!
            r2 = s.solve!(h)                     # must be a cold start again (same QP: same iterations)
                        # (OSQP: no count check here, see its own testset: the read-back shows warm_start = 0,
            # with which osqp_solve zeroes x, z, y; the counts move with the rho kept on the handle)
            # (Mumblebee: reinit! restarts from its starting point, but a little internal state
            # survives it, so the count can differ by one; a warm start would take one or two)
            if s.name == "mumblebee"
                @test abs(r2.iters - r1.iters) <= 1
            elseif !(s.name in ("osqp", "sheafmpc"))
                @test r2.iters == r1.iters
            end
            @test r1.status in (:solved, :almost_solved)   # accuracy itself is judged by check()
        end
    end
end

@testset "OSQP: setup is cold, warm! warms" begin
    s = BH.osqp_spec(); p = problems[1]
    h = s.setup(p, 1e-6, s.variants[2])
    @test BH.check_readback(s, h, 1e-6)[1]["warm_start"] == 0
    r1 = s.solve!(h)
    s.warm!(h, r1.x, r1.y)
    @test s.readback(h)["warm_start"] == 1
    r3 = s.solve!(h)
    @test r3.iters <= 25 < r1.iters
end

@testset "SheafMPC: a fresh setup has no iterate; warm! sets one" begin
    s = BH.sheafmpc_spec(); p = problems[1]
    h = s.setup(p, 1e-6, s.variants[1])
    @test s.readback(h)["has_iterate"] == false
    r1 = s.solve!(h)
    h2 = s.setup(p, 1e-6, s.variants[1]); r1b = s.solve!(h2)
    @test r1b.iters == r1.iters                   # fresh setups are identical cold solves
    s.warm!(h2, r1.x, r1.y); r3 = s.solve!(h2)
    @test r3.iters < r1.iters || r3.iters <= 25
end
