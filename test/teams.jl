# Colour refinement: lossless teams as the coarsest almost equitable partition
# within the data classes (the paper's Sec. IV).

@testset "colour refinement" begin

rowsof(R, C) = [cld(i, C) for i in 1:(R*C)]
colof(R, C) = [rem(i - 1, C) + 1 for i in 1:(R*C)]

@testset "grid rows" begin
    for (R, C) in ((6, 6), (8, 8), (16, 16), (32, 32), (128, 128), (5, 9))
        edges, _ = grid_graph(R, C)
        n = R * C
        rows = rowsof(R, C)
        # every row its own data class (a lane per row): already almost equitable
        @test colour_refinement(n, edges, 1.0, rows) == rows
        @test is_almost_equitable(n, edges, 1.0, rows)
        # two row types sharing their data: the splitting separates the rows by
        # their distance to the edge of the grid, down to the rows; with an odd
        # number of rows, mirror rows have the same type and nothing separates
        # them, so they form one (disconnected, still lossless) team
        mirror = isodd(R) ? [min(r, R + 1 - r) for r in rows] : rows
        @test colour_refinement(n, edges, 1.0, isodd.(rows)) == canonical_partition(mirror)
        # one class: nothing to split (one team is almost equitable)
        @test colour_refinement(n, edges, 1.0, ones(Int, n)) == ones(Int, n)
    end
end

@testset "blocks and columns are not almost equitable" begin
    edges, _ = grid_graph(8, 8)
    r, c = rowsof(8, 8), colof(8, 8)
    @test !is_almost_equitable(64, edges, 1.0, [(cld(r[i], 2), cld(c[i], 2)) for i in 1:64])
    @test !is_almost_equitable(64, edges, 1.0, [(r[i], cld(c[i], 4)) for i in 1:64])     # half rows
    @test is_almost_equitable(64, edges, 1.0, c)                                            # columns, by symmetry
end

@testset "ordinary colour refinement gives the mirror pairs" begin
    for (R, C) in ((8, 8), (32, 32))
        edges, _ = grid_graph(R, C)
        n = R * C
        r, c = rowsof(R, C), colof(R, C)
        eq = colour_refinement(n, edges, 1.0, r; within = true)
        @test eq == canonical_partition([(r[i], min(c[i], C + 1 - c[i])) for i in 1:n])
        @test maximum(eq) == R * cld(C, 2)                                                # 512 at 32 x 32
    end
end

@testset "uneven coupling and lost links split the rows" begin
    R = C = 8
    edges, _ = grid_graph(R, C)
    n = R * C
    r, c = rowsof(R, C), colof(R, C)
    between = [r[i] != r[j] for (i, j) in edges]
    eps = 0.3
    w = [b ? 1 + eps * cos(2pi * c[i] / C) : 1.0 for ((i, j), b) in zip(edges, between)]
    @test !is_almost_equitable(n, edges, w, r)
    @test maximum(colour_refinement(n, edges, w, r)) > R
    # weights below the tolerance do not split
    w2 = [b ? 1 + 1e-12 * cos(2pi * c[i] / C) : 1.0 for ((i, j), b) in zip(edges, between)]
    @test is_almost_equitable(n, edges, w2, r)
    # a lost link between rows (weight zero) splits its two rows
    w3 = ones(length(edges)); w3[findfirst(between)] = 0.0
    @test !is_almost_equitable(n, edges, w3, r)
    @test colour_refinement(n, edges[setdiff(1:end, findfirst(between))], 1.0, r) == colour_refinement(n, edges, w3, r)
end

@testset "drones and cars" begin
    # rows alternate drones and cars, one lane per type: the data classes are the two types, and
    # colour refinement splits them into the rows (an even number of rows)
    for (R, C) in ((4, 5), (8, 8), (32, 32))
        edges, _ = grid_graph(R, C)
        n = R * C
        rows = rowsof(R, C)
        kind = [isodd(r) ? 1 : 2 for r in rows]
        @test colour_refinement(n, edges, 1.0, kind) == canonical_partition(rows)
        @test is_almost_equitable(n, edges, 1.0, rows)
    end
    # columns alternate the types (a mixed fleet): rows split by type are not almost equitable (the ends of a
    # row see one neighbour of the other type in the row, the others two), and colour refinement returns a
    # finer, almost equitable partition
    R, C = 8, 8
    edges, _ = grid_graph(R, C)
    n = R * C
    r, c = rowsof(R, C), colof(R, C)
    kind = [isodd(c[i]) ? 1 : 2 for i in 1:n]
    split = canonical_partition([(r[i], kind[i]) for i in 1:n])
    @test !is_almost_equitable(n, edges, 1.0, split)
    cr = colour_refinement(n, edges, 1.0, kind)
    @test is_almost_equitable(n, edges, 1.0, cr)
    @test all(length(unique(kind[cr .== b])) == 1 for b in 1:maximum(cr))
    # a fleet whose drone-car and car-car edges compare only the horizontal position
    h = 0.2
    I2 = Matrix(1.0I, 2, 2); I3 = Matrix(1.0I, 3, 3)
    drone = Agent([I3 h*I3; zeros(3, 3) I3], [0.5h^2*I3; h*I3]; C = [I3 zeros(3, 3)], Q = I3, R = 0.1I3,
                  input = BallSet(4.0), kind = :drone)
    car = Agent([I2 h*I2; zeros(2, 2) 0.9I2], [0.5h^2*I2; h*I2]; C = [I2 zeros(2, 2); zeros(1, 4)], Cr = [I2 zeros(2, 2)],
                Q = I2, R = 0.2I2, input = BallSet(1.0), kind = :car)
    edges, sl = grid_graph(2, 3)
    ags = [i <= 3 ? drone : car for i in 1:6]
    horiz = [1.0 0 0; 0 1 0]
    sel = [(ags[i].kind == :drone && ags[j].kind == :drone) ? Matrix(1.0I, 3, 3) : horiz for (i, j) in edges]
    fl = Fleet(ags, edges; H = 4, offsets = [[s; 0.0] for s in sl], select = sel)
    F = FleetProgram(fl)
    for (k, (i, j)) in enumerate(fl.edges)
        e = F.program.edges[F.form[k, 1]]
        @test size(e.b) == (size(sel[k], 1),)
        Mi, Mj = edge_maps(fl, k)
        @test size(Mi) == (size(sel[k], 1), ags[i].nx) && size(Mj) == (size(sel[k], 1), ags[j].nx)
    end
    T = randn(3, length(edges), 4)
    set_targets!(F, T)
    @test all(F.program.edges[F.form[k, t]].b ≈ sel[k] * T[:, k, t] for k in eachindex(edges), t in 1:4)
    xi = [randn(ag.nx) for ag in ags]
    @test edge_residual(fl, 1, xi[1], xi[2], 2) ≈ sel[1] * (ags[2].C * xi[2] - ags[1].C * xi[1] - fl.targets[:, 1, 2])
    @test_throws DimensionMismatch Fleet(ags, edges; H = 4, select = sel[1:end-1])
end

@testset "fleets" begin
    sc = GridScenario(rows = 4, cols = 5, H = 4)
    fl = fleet(sc)
    kinds = [agent_kind(sc, i) for i in 1:nagents(sc)]                # two row types
    @test colour_refinement(fl, kinds) == row_teams(sc)
    @test_throws DimensionMismatch colour_refinement(fl, kinds[1:end-1])
end

end
