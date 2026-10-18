# The structured fiber basis (ported from the paper repository's
# scripts/resolution/test/structured_basis.jl). Thm. 1 holds for any basis of
# the fiber, so the structured basis must give the orthonormal basis's fiber
# dimensions, reduced value and lifted plans: checked on the partitions the
# experiments use (time leg, agent leg, teams over the whole horizon, products,
# corners, random contractions), with the sparsity and kinds of the blocks, the
# team stalk dimension, the empty fiber, composition, and receding-horizon reuse.

@testset "structured fiber basis" begin

SRNG = Xoshiro(20261018)
cases = [
    "mixed ring, drift" => test_program(n = 4, H = 5, graph = :ring, seed = 11, drift = 0.5)[1],
    "quad grid, coherent" => test_program(n = 6, H = 6, graph = :grid, kinds = :quad, seed = 2)[1],
    "mixed grid, cones" => test_program(n = 6, H = 6, graph = :grid, seed = 4, umax_scale = 0.3)[1],
    "time varying, switching, incoherent" => test_program(n = 5, H = 6, graph = :rgg, seed = 5, time_varying = true,
                                                          switching = 0.3, coherent = false, start_in_formation = false)[1],
    "zero-stalk absent edges" => test_program(n = 4, H = 5, graph = :complete, kinds = :rover, switching = 0.4,
                                              absent = :zero, seed = 7)[1],
]

@testset "same fibers as the orthonormal basis, exact lift" begin
    for (cname, fp) in cases, (pname, res) in test_resolutions(fp, SRNG)
        P = fp.program
        Ro = reduce(fp, res; basis = :orthonormal)
        Rs = reduce(fp, res)
        @test Ro.feasible == Rs.feasible
        @test [fiberdim(F) for F in Ro.fibers] == [fiberdim(F) for F in Rs.fibers]
        @test all(F -> F.kind in (:identity, :structured, :structured_reduced), Rs.fibers)
        S = Rs.collapsed
        isempty(S) && continue
        DS = coboundary(P, S)
        @test norm(DS * Rs.N, Inf) < 1e-10 * max(1.0, norm(Rs.N, Inf))
        @test norm(DS * Rs.xbar - targets(P, S), Inf) < 1e-10
        @test rank(Matrix(Rs.N)) == size(Rs.N, 2)
        y = randn(SRNG, c0dim(Rs.program))
        x = lift(Rs, y)
        @test norm(restrict(Rs, x) - y, Inf) < 1e-9
        # the structured and orthonormal lifts parametrize the same affine set
        xo = lift(Ro, randn(SRNG, c0dim(Ro.program)))
        @test norm(lift(Rs, restrict(Rs, xo)) - xo, Inf) < 1e-9 * max(1.0, norm(xo, Inf))
    end
end

@testset "objective, node sets and reduced edges by substitution" begin
    for (cname, fp) in cases, (pname, res) in test_resolutions(fp, SRNG)
        P = fp.program
        R = reduce(fp, res)
        Pc = R.program
        y = randn(SRNG, c0dim(Pc))
        x = lift(R, y)
        @test srelerr(objective(Pc, y), objective(P, x)) < 1e-11
        for (k, e) in enumerate(R.cross)
            @test norm(edge_defect(Pc, k, y) - edge_defect(P, e, x), Inf) < 1e-10
        end
        for (b, F) in enumerate(R.fibers)
            sc = Pc.nodes[b].b - Pc.nodes[b].A * y[vrange(Pc, b)]
            sf = reduce(vcat, [P.nodes[v].b - P.nodes[v].A * x[vrange(P, v)] for v in F.members]; init = Float64[])
            @test norm(sc - sf, Inf) < 1e-10
        end
    end
end

@testset "same optimal value and feasible lifted plans as the orthonormal basis" begin
    for (cname, fp) in cases, (pname, res) in test_resolutions(fp, SRNG)
        P = fp.program
        Ro = reduce(fp, res; basis = :orthonormal)
        Rs = reduce(fp, res)
        Rs.feasible || continue
        so, ss = test_solve(Ro), test_solve(Rs)
        @test so.status == ss.status
        isoptimal(ss) || continue
        @test srelerr(so.J, ss.J) < 1e-7
        x = lift(Rs, ss)
        S = Rs.collapsed
        isempty(S) || @test norm(coboundary(P, S) * x - targets(P, S), Inf) < 1e-8
        f = feasibility(P, x)
        @test f.hard < 1e-8 && f.cone < 1e-7
        @test srelerr(objective(P, x), ss.J) < 1e-9
    end
end

@testset "the paper's fibers are solved structurally, without the fallback" begin
    fp = cases[3][2]                                          # mixed quadrotors and ground vehicles on a 2 x 3 grid
    for alpha in ([1, 2, 3, 4, 5, 6], [1, 1, 1, 2, 2, 2], [1, 1, 2, 2, 3, 3], [1, 1, 1, 1, 1, 1])
        R = reduce(fp, Teams(alpha) ⊠ full_condensing())
        @test all(F -> F.kind == :structured, R.fibers)
    end
    R = reduce(fp, Teams(ones(Int, 6)))
    @test all(F -> F.kind in (:identity, :structured), R.fibers)
    # a time chain is classical condensing: the free coordinates are x_0 and the inputs
    R = reduce(fp, full_condensing())
    ag = fp.fleet.agents[1]
    @test fiberdim(R.fibers[1]) == ag.nx + fp.fleet.H * ag.nu
end

@testset "team stalk: one member's coordinates plus ker(C Gam) per other member" begin
    fp = cases[2][2]                                          # identical quadrotors, rows of 3 on a 2 x 3 grid
    H = fp.fleet.H
    ag = fp.fleet.agents[1]
    R = reduce(fp, Teams([1, 1, 1, 2, 2, 2]) ⊠ full_condensing())
    member = ag.nx + H * ag.nu                                # (x_0, U) of one quadrotor
    kerM = member - 2 * H                                     # planar position at t = 1..H pinned relative to a neighbour
    @test c0dim(R.program) == 2 * (member + 2 * kerM)
    @test all(F -> F.kind == :structured, R.fibers)
end

@testset "empty affine fiber and composition" begin
    nodes = [NodeData(sparse([1.0;;]), [0.0]) for _ in 1:3]
    one_ = sparse([1.0;;])
    edges = [SheafEdge(1, 2, one_, one_, false, [1.0;;], [1.0]),
             SheafEdge(2, 3, one_, one_, false, [1.0;;], [1.0]),
             SheafEdge(1, 3, one_, one_, false, [1.0;;], [1.0])]
    P = SheafProgram(nodes, edges)
    R = reduce(P, VertexPartition([1, 1, 1]))
    @test !R.feasible
    @test solve(R).status == :primal_infeasible
    P.edges[3].b[1] = 2.0                                     # now realizable around the cycle
    update!(R)
    @test R.feasible
    @test abs(test_solve(R).J - 1.0) < 1e-8                  # x = (a, a + 1, a + 2), best a = -1
    fp = cases[2][2]
    H = fp.fleet.H
    R1 = reduce(fp, full_condensing())
    R12 = reduce(R1, Teams([1, 1, 1, 2, 2, 2]))
    R2 = reduce(fp, Teams([1, 1, 1, 2, 2, 2]) ⊠ full_condensing())
    @test c0dim(R12.program) == c0dim(R2.program)
    s12, s2 = test_solve(R12), test_solve(R2)
    @test srelerr(s12.J, s2.J) < 1e-8
    x = lift(R12, s12)                                        # level by level to the fine program
    @test length(x) == c0dim(fp.program)
    @test srelerr(objective(fp.program, x), s12.J) < 1e-9
    @test feasibility(fp.program, x).hard < 1e-8
end

@testset "receding horizon: fibers are reused, also when the targets change" begin
    fp, d = test_program(n = 6, H = 6, graph = :grid, seed = 4, umax_scale = 0.3)
    res = Teams([1, 1, 1, 2, 2, 2])
    R = reduce(fp, res)
    # the next step: new measured states and references (node data only), and new formation targets
    fp2, _ = test_program(n = 6, H = 6, graph = :grid, seed = 4, umax_scale = 0.3)
    set_state!(fp2, [x .+ 0.05 for x in d.x0])
    set_targets!(fp2, fp2.fleet.targets .* 1.1)
    Ra = reduce(fp2, res)
    Rb = reduce(fp2, res; reuse = R)
    @test all(b -> Rb.fibers[b] === R.fibers[b], eachindex(R.fibers))
    @test quadratic_form(Ra.program)[2] ≈ quadratic_form(Rb.program)[2]
    @test node_constraints(Ra.program)[2] ≈ node_constraints(Rb.program)[2]
    @test Ra.xbar ≈ Rb.xbar && Ra.N == Rb.N
    # and in place: update! on the first reduction gives the same program
    set_state!(fp, [x .+ 0.05 for x in d.x0])
    set_targets!(fp, fp.fleet.targets .* 1.1)
    update!(R)
    @test quadratic_form(R.program)[2] ≈ quadratic_form(Ra.program)[2]
    @test targets(R.program) ≈ targets(Ra.program)
    @test node_constraints(R.program)[2] ≈ node_constraints(Ra.program)[2]
    # a changed restriction map is not reused
    P2 = copy(fp2.program)
    e = fp2.form[1, 2]
    E = P2.edges[e]
    P2.edges[e] = SheafEdge(E.tail, E.head, 2 * E.Ft, 2 * E.Fh, E.hard, E.W, E.b, E.tag)
    lab = SheafMPC.vertex_labels(res, nvertices(P2), fp2.layout)[1]
    Rc = reduce(P2, VertexPartition(lab); reuse = R)
    @test Rc.fibers[R.partition[E.tail]] !== R.fibers[R.partition[E.tail]]
end

end
