using SheafMPC: noderows

@testset "step operator" begin

"The agent of every vertex: the partition of full condensing."
function agent_labels(fp)
    labels = zeros(Int, nvertices(fp.program))
    for i in axes(fp.vid, 1), v in fp.vid[i, :]
        labels[v] = i
    end
    return labels
end

relerr(a, b) = isempty(b) ? 0.0 : maximum(abs, a - b) / max(1.0, maximum(abs, b))

"Rigidly shifted states, moved references and targets: new data in place, as a receding-horizon step writes them."
function move_data!(fp, d, k)
    set_state!(fp, [x .+ 0.1k for x in d.x0])
    set_references!(fp, [r .+ 0.05k for r in d.refs]; terminal = [r .- 0.02k for r in d.terminal])
    set_targets!(fp, fp.fleet.targets .* (1 + 0.002k))
end

@testset "equals the level by level update on a chain ($name)" for (name, chains) in (("chains", :auto), ("no chains", nothing))
    fp, d = test_program(n = 6, H = 5, graph = :grid, kinds = :quad, seed = 9, coherent = false)
    R1 = reduce(fp, VertexPartition(agent_labels(fp)))                       # full condensing
    R2 = reduce(R1, VertexPartition([1, 1, 2, 2, 3, 3]))                      # pairs
    R3 = reduce(R2, VertexPartition([1, 1, 2]))                               # pairs of pairs
    P0 = fp.program
    M = QPMap(R3.program; dedup = false)
    active = 1:(c0dim(P0) + noderows(P0) + c1dim(P0))                      # every entry of the data
    rows = collect(1:c0dim(P0))                                             # the whole plan
    op = StepOperator(R3, M, active; lift_rows = rows, chains = chains, chunk = 97)
    @test op.feasible
    c0 = M.c
    for k in 1:3
        move_data!(fp, d, k)
        update!(op)
        q, b, bk = copy(M.q), copy(M.bfull), copy(M.b)
        @test M.c == c0                                                     # the constant is left alone
        y = randn(Xoshiro(k), c0dim(R3.program))
        u = lift!(zeros(length(rows)), op, y)
        sync!(op)                                                           # the level by level path
        @test relerr(q, M.q) < 1e-12
        @test relerr(b, M.bfull) < 1e-12 && relerr(bk, M.b) < 1e-12
        @test relerr(u, lift(R3, y)) < 1e-12
        @test M.c != c0 && M.c ≈ sheaf_qp(R3.program).c                    # sync! recomputes it
        c0 = M.c
    end
end

@testset "active entries, chained rows, lifted inputs" begin
    fp, d = test_program(n = 4, H = 4, graph = :ring, kinds = :quad, seed = 1, umax_scale = 0.3)
    R1 = reduce(fp, Teams([1, 1, 2, 2]) ⊠ full_condensing())
    R3 = reduce(R1, Teams([1, 1]))
    P0 = fp.program
    M = QPMap(R3.program; dedup = false)
    # the data that set_state! and set_references! change: the pinned initial states and the costs
    active = vcat([data_index(P0, :bn, fp.vid[i, 1]) for i in 1:4]..., [data_index(P0, :q, v) for v in 1:nvertices(P0)]...)
    inputs = vcat([collect(vrange(P0, v))[end-2:end] for v in 1:nvertices(P0) if length(vrange(P0, v)) > 6]...)
    nb = length(M.bfull)
    # chains are exact for any rows (only the sparsity depends on them being copies): one through every node row
    chains = [i > M.nh + 1 ? i - 1 : 0 for i in 1:nb]
    lift_chains = [i > 1 ? i - 1 : 0 for i in eachindex(inputs)]
    ops = [StepOperator(R3, M, active; lift_rows = inputs),
           StepOperator(R3, M, active; lift_rows = inputs, chains = chains, lift_chains = lift_chains)]
    @test count(>(0), ops[2].qb.prev) == nb - M.nh - 1 && !isempty(ops[2].qb.crows)
    for k in 1:3
        set_state!(fp, [x .+ 0.1k .+ 0.01 * randn(Xoshiro(k), length(x)) for x in d.x0])
        set_references!(fp, [r .+ 0.05k for r in d.refs]; terminal = [r .- 0.02k for r in d.terminal])
        y = randn(Xoshiro(10 + k), c0dim(R3.program))
        outs = map(ops) do op
            update!(op)
            (copy(M.q), copy(M.bfull), lift!(zeros(length(inputs)), op, y))
        end
        sync!(ops[1])
        for (q, b, u) in outs
            @test relerr(q, M.q) < 1e-12 && relerr(b, M.bfull) < 1e-12
            @test relerr(u, lift(R3, y)[inputs]) < 1e-12
        end
    end
    # links applied to departures from classes of entries: with every entry its own class the links drop out,
    # and their bound (along the classes) covers the copies' error
    W = sparse(1:length(active), 1:length(active), 1.0)
    opw = StepOperator(R3, M, active; chains = chains, invariant = W)
    @test opw.deviation && maximum(opw.linkboundW) > 0
    set_state!(fp, [x .+ 0.3 for x in d.x0])
    update!(opw)
    b = copy(M.bfull); da = maximum(abs, opw.a - opw.qb.x0)
    sync!(opw)
    @test all(abs.(b - M.bfull) .<= opw.linkboundW[opw.nq+1:end] .* da .+ 1e-12)       # no departures: dev = 0
    @test_throws ArgumentError StepOperator(R3, M, active; invariant = 2 .* W)
    @test_throws ArgumentError StepOperator(R3, M, [0])
    @test_throws ArgumentError StepOperator(R3, M, active; chains = [i == 1 ? 2 : (i == 2 ? 1 : 0) for i in 1:nb])
end

end
