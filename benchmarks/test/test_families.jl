# test_families.jl: the generators against the paper's code, and every stage
# form against its canonical QP through cmap (what the HPIPM adapter relies on).
#
#   julia --project=benchmarks benchmarks/test/test_families.jl

using Test, LinearAlgebra, SparseArrays
include(joinpath(@__DIR__, "..", "src", "BenchHarness.jl"))
using .BenchHarness
const BH = BenchHarness
BH.REF_DIR[] = mktempdir()

const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))
module PaperQP
ENV["BENCH_ABAR"] = "1.0"
include(joinpath(Main.PAPER, "bench", "central", "qp.jl"))
end

"Solve the stage form's own canonical QP and map its solution into p's variables."
function stage_solution_in(p)
    o = p.stage
    ps = BH.stage_canonical("s", o)
    r = BH.reference(ps)
    uo, xo, _ = BH.stage_offsets(ps.stage)
    xs = [k == 0 ? o.x0 : r.x[xo[k+1] .+ (1:o.nx[k+1])] for k in 0:o.N]
    us = [k < o.N ? r.x[uo[k+1] .+ (1:o.nu[k+1])] : Float64[] for k in 0:o.N]
    return BH.canonical_from_stages(o, xs, us)
end

@testset "fleet matches the paper's blocked_qp at x0 = 0" begin
    for n in (1, 4), b in (1, 4, 24)
        Q = PaperQP.blocked_qp(n, 24, b)
        p = BH.fleet_qp(n = n, N = 24, b = b)
        @test p.P ≈ Q.P
        @test p.q ≈ Q.q
        @test p.c ≈ Q.c
        me = size(Q.Aeq, 1)
        @test p.A[1:me, :] ≈ Q.Aeq
        @test p.l[1:me] ≈ Q.beq
    end
end

@testset "stage forms agree with the canonical QPs" begin
    x0f = [[0.1i, -0.05i, 0.2, -0.1] for i in 1:4]
    cases = [BH.fleet_qp(n = 4, N = 24, b = 1, x0 = x0f, t0 = 0.7),
             BH.fleet_qp(n = 4, N = 24, b = 1, graph = :grid, x0 = x0f),
             BH.stage_canonical("di", BH.di_ocp(N = 15, x0 = [0.3, -0.2, 0.1, 0.5, 0, -0.4])),
             BH.stage_canonical("quad", BH.quad_ocp(N = 12, x0 = zeros(12))),
             BH.stage_canonical("chain", BH.chain_ocp(M = 4, N = 15, x0 = BH.chain_x0(4))),
             BH.osqprand_qp(BH.read_osqprand(joinpath(BH.OSQPRAND_DIR[], "osqprand_n10_s1.json")),
                            BH.read_osqprand(joinpath(BH.OSQPRAND_DIR[], "osqprand_n10_s1.json")).x0)]
    for p in cases
        ref = BH.reference(p)
        x = stage_solution_in(p)
        c = BH.check(p, x, nothing, ref.obj0)
        @test c.obj_err < 1e-8
        @test c.prim_rel < 1e-8
        @test ref.prim_rel < 1e-9
    end
end

@testset "reference polish and shift maps" begin
    p = BH.fleet_qp(n = 4, N = 24, b = 1)
    r = BH.reference(p)
    @test r.source == "clarabel+polish"
    @test r.dual_rel < 1e-9
    xm, ym = BH.fleet_shift_maps(p)
    @test length(xm) == BH.nvars(p) && length(ym) == BH.ncons(p)
    @test all(1 .<= xm .<= BH.nvars(p)) && all(1 .<= ym .<= BH.ncons(p))
    ps = BH.fleet_qp(n = 4, N = 24, b = 1, cone = :soc)
    xm, ym = BH.fleet_shift_maps(ps)
    @test length(ym) == BH.ncons(ps)
    pd = BH.stage_canonical("di", BH.di_ocp(N = 10, x0 = zeros(6)))
    xm, ym = BH.stage_shift_maps(pd)
    @test length(xm) == BH.nvars(pd) && length(ym) == BH.ncons(pd)
end
