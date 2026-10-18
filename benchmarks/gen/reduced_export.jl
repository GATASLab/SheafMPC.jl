# reduced_export.jl: export the reduced (pushed-forward) fleet programs of the
# paper's Resolution module as canonical QP files, with their closed-loop
# sequences. Runs in the paper repository's scripts environment:
#
#   julia --project=$PAPER/scripts gen/reduced_export.jl OUTDIR ROWS COLS H STEPS K1,K2,...
#
# The fleet is the paper's heterogeneous grid (scripts/resolution/experiments/
# common_spatial.jl, read only): ROWS x COLS agents, rows alternating
# quadrotors and ground vehicles, horizon H, hard dynamics, each row tracking
# its own centre trajectory (coherence :rows), second-order-cone input bounds.
# Levels: the fine program (k = 0) and the pushforwards along the spatial
# resolution of teams of k whole rows (k = 1: one team per row; k = ROWS: the
# whole fleet as one rigid formation), structured fibre basis. Each level runs
# its own receding-horizon loop of STEPS steps closed by the paper's direct
# solver (Clarabel, `solve_direct`), the fibres reused across steps; every QP
# of the loop is written, so all benchmarked solvers see the same sequence.
#
# The program becomes a canonical QP as in SheafMPC's `sheaf_qp`: node costs,
# soft edges as quadratic penalties, hard edges then node constraints as rows
# (b - A x in K: zero rows are equalities, nonnegative rows a'x <= b, cone
# blocks second-order cones).

const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))
include(joinpath(PAPER, "scripts", "resolution", "experiments", "common_spatial.jl"))
using JSON, SparseArrays, LinearAlgebra
module BQ
using SparseArrays, LinearAlgebra, JSON
include(joinpath(@__DIR__, "..", "src", "qp.jl"))
end
using .BQ: write_qp

_kind(k) = (s = string(Symbol(k)); s == "ZERO_CONE" ? :zero : s == "NONNEG_CONE" ? :nonneg : s == "SOC_CONE" ? :soc :
                                    error("cone $s"))

function push_blk!(I, J, V, r0, c0, M, s)
    M = sparse(M)
    rv = rowvals(M); nz = nonzeros(M)
    for col in 1:size(M, 2), k in nzrange(M, col)
        push!(I, r0 + rv[k]); push!(J, c0 + col); push!(V, s * nz[k])
    end
end

function program_qp(name, prog, meta)
    offs = prog.offsets; n = offs[end]
    I = Int[]; J = Int[]; V = Float64[]; q = zeros(n); c = 0.0
    for (v, nd) in enumerate(prog.nodes)
        push_blk!(I, J, V, offs[v], offs[v], nd.Q, 1.0)
        q[(offs[v]+1):offs[v+1]] .+= nd.q; c += nd.c
    end
    DI = Int[]; DJ = Int[]; DV = Float64[]; WI = Int[]; WJ = Int[]; WV = Float64[]; bs = Float64[]; row = 0
    for E in prog.edges
        (E.hard || length(E.b) == 0) && continue
        d = length(E.b)
        push_blk!(DI, DJ, DV, row, offs[E.head], E.Fh, 1.0)
        push_blk!(DI, DJ, DV, row, offs[E.tail], E.Ft, -1.0)
        W = Matrix{Float64}(E.W)
        for jj in 1:d, ii in 1:d
            W[ii, jj] != 0 && (push!(WI, row + ii); push!(WJ, row + jj); push!(WV, W[ii, jj]))
        end
        append!(bs, E.b); row += d
    end
    P = sparse(I, J, V, n, n)
    if row > 0
        Ds = sparse(DI, DJ, DV, row, n); Ws = sparse(WI, WJ, WV, row, row)
        P = P + Ds' * (Ws * Ds); q .-= Ds' * (Ws * bs); c += 0.5 * dot(bs, Ws * bs)
    end
    AI = Int[]; AJ = Int[]; AV = Float64[]; b = Float64[]; kinds = Symbol[]; socs = UnitRange{Int}[]; row = 0
    for E in prog.edges
        (E.hard && length(E.b) > 0) || continue
        push_blk!(AI, AJ, AV, row, offs[E.head], E.Fh, 1.0)
        push_blk!(AI, AJ, AV, row, offs[E.tail], E.Ft, -1.0)
        append!(b, E.b); append!(kinds, fill(:zero, length(E.b))); row += length(E.b)
    end
    for (v, nd) in enumerate(prog.nodes)
        size(nd.A, 1) == 0 && continue
        push_blk!(AI, AJ, AV, row, offs[v], nd.A, 1.0)
        append!(b, nd.b)
        r = row
        for cb in nd.cones
            cb.dim == 0 && continue
            k = _kind(cb.kind)
            k == :soc && push!(socs, (r + 1):(r + cb.dim))
            append!(kinds, fill(k, cb.dim)); r += cb.dim
        end
        row += size(nd.A, 1)
    end
    A = sparse(AI, AJ, AV, row, n)
    l = fill(-Inf, row); u = fill(Inf, row); sb = zeros(row)
    for i in 1:row
        if kinds[i] == :zero
            l[i] = u[i] = b[i]
        elseif kinds[i] == :nonneg
            u[i] = b[i]
        else
            sb[i] = b[i]
        end
    end
    return BQ.QP(name, P, q, A, l, u; c = c, socs = socs, socb = sb, meta = meta)
end

function level_partition(model, k, rows, cols)
    k == 0 && return collect(1:nvertices(model.program))
    alpha = k == 1 ? sp_rows(rows, cols) : sp_strips(rows, cols, k)
    return spatial_partition(model, alpha)
end

function main()
    out = ARGS[1]
    ROWS, COLS, HZ, STEPS = parse.(Int, ARGS[2:5])
    KS = parse.(Int, split(ARGS[6], ","))
    sc = FleetScenario(; rows = ROWS, cols = COLS, H = HZ, coherence = :rows, abar_scale = 1.0, seed = 20261018)
    layout = sp_grid(sc.rows, sc.cols; spacing = sc.spacing)[2]
    for k in KS
        dir = joinpath(out, "grid$(ROWS)x$(COLS)_H$(HZ)_k$(k)")
        mkpath(dir)
        x = formation_start(sc, layout)
        prev = nothing
        for step in 0:(STEPS-1)
            spec = fleet_spec(sc; xhat = x, t0 = step * sc.h)
            model = build_model(spec)
            Pi = level_partition(model, k, ROWS, COLS)
            if k == 0
                Pk = model.program; L = nothing; tp = 0.0
            else
                tp = @elapsed((Pk, L) = pushforward(model.program, Pi; basis = :structured, reuse = prev))
                prev = (model.program, L)
            end
            meta = Dict{String,Any}("family" => "reduced", "rows" => ROWS, "cols" => COLS, "n" => ROWS * COLS, "H" => HZ,
                                    "k" => k, "step" => step, "t_pushforward" => tp, "basis" => "structured",
                                    "teams" => k == 0 ? ROWS * COLS : cld(ROWS, k))
            qp = program_qp("reduced_grid$(ROWS)x$(COLS)_H$(HZ)_k$(k)", Pk, meta)
            write_qp(joinpath(dir, "step$(lpad(step, 3, '0')).qp"), qp)
            sol = solve_direct(Pk)
            z = k == 0 ? sol.x : lift(L, sol.x)
            u = [agent_state(model, z, i, 0)[2] for i in 1:spec.n]
            x = [spec.agents[i].A[1] * x[i] + spec.agents[i].B[1] * u[i] + spec.agents[i].c[1] for i in 1:spec.n]
            println("k=$k step=$step vars=$(BQ.nvars(qp)) rows=$(BQ.ncons(qp)) J=$(sol.J) push=$(round(1e3tp, digits = 2)) ms")
            flush(stdout)
        end
    end
end

main()
