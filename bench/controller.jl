# controller.jl: where the time of a receding-horizon step goes, before and
# after the in-place reduction.
#
#   julia --project=bench bench/controller.jl
#
# The paper's grid fleet (8 x 8, rows alternating quadrotors and ground
# vehicles, H = 10, coherence :rows, formation start), STEPS closed-loop steps
# at every level (fine, teams of k rows, the whole fleet, full condensing).
# Three pipelines, all with the same solver, updated with `update!` and warm
# started from the previous solution (factorizations kept):
#
#   research   the paper repository's per-step pipeline: rebuild the data and
#              the time-expanded program, pushforward with fiber reuse, then
#              `sheaf_qp` of the pushforward (read only from SHEAFMPC_PAPER);
#   rebuild    the package without the in-place path: a new FleetProgram,
#              `reduce(...; reuse)` and `sheaf_qp` every step;
#   controller `MPCController` and `step!`: data written in place, pushed
#              through the reduction by `update!` (sparse products), the
#              reduced QP's vectors refreshed in place.
#
# Per step: construction (data, program, pushforward, QP vectors), setup (the
# data update into the solver), solve, lift (to the fine plan and the first
# inputs); medians over the steps after the first, in milliseconds.

const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))
module Paper
include(joinpath(Main.PAPER, "scripts", "resolution", "experiments", "common_spatial.jl"))
end
using SheafMPC, LinearAlgebra, SparseArrays, Statistics, Printf, JSON

const ROWS = parse(Int, get(ENV, "BENCH_ROWS", "8"))
const COLS = parse(Int, get(ENV, "BENCH_COLS", "8"))
const HZ = parse(Int, get(ENV, "BENCH_H", "10"))
const STEPS = parse(Int, get(ENV, "BENCH_STEPS", "30"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const SEED = 20261018

ms(t) = 1e3 * t
med(v) = isempty(v) ? NaN : median(v)
qp_b(qp) = [qp.kinds[i] == SheafMPC.ROW_SOC ? qp.socb[i] : qp.u[i] for i in 1:nrows(qp)]

function levels(sc)
    return [("fine", Fine(), nothing), ("teams k=8 (rows)", Teams(row_teams(sc)), row_teams(sc)),
            ("teams k=4", Teams(strip_teams(sc, 2)), strip_teams(sc, 2)), ("teams k=2", Teams(strip_teams(sc, 4)), strip_teams(sc, 4)),
            ("fleet (k=1)", Teams(ones(Int, nagents(sc))), ones(Int, nagents(sc))), ("full condensing", full_condensing(), :time)]
end

"The research pipeline: rebuild data and program, pushforward with reuse, sheaf_qp, update, solve, lift."
function run_research(sc0, sc, alpha)
    layout = Paper.sp_grid(sc0.rows, sc0.cols)[2]
    x = Paper.formation_start(sc0, layout)
    prev = nothing; s = nothing
    T = (c = Float64[], s = Float64[], v = Float64[], l = Float64[])
    for step in 0:(STEPS-1)
        t0 = time_ns()
        spec = Paper.fleet_spec(sc0; xhat = x, t0 = step * sc0.h)
        model = Paper.build_model(spec)
        if alpha === nothing
            Pk = model.program; L = nothing
        else
            Pi = alpha === :time ? Paper.time_leg(model) : Paper.spatial_partition(model, alpha)
            Pk, L = Paper.pushforward(model.program, Pi; basis = :structured, reuse = prev)
            prev = (model.program, L)
        end
        qp = sheaf_qp(Pk)
        t1 = time_ns()
        if s === nothing
            s = setup(qp; eps_abs = EPS, eps_rel = EPS, max_iter = 20_000)
        else
            update!(s; q = qp.q, b = qp_b(qp))
        end
        t2 = time_ns()
        solve!(s)
        t3 = time_ns()
        z = L === nothing ? s.xsol : Paper.lift(L, s.xsol)
        u = [Paper.agent_state(model, z, i, 0)[2] for i in 1:spec.n]
        t4 = time_ns()
        x = [spec.agents[i].A[1] * x[i] + spec.agents[i].B[1] * u[i] + spec.agents[i].c[1] for i in 1:spec.n]
        if step > 0
            push!(T.c, (t1 - t0) / 1e9); push!(T.s, (t2 - t1) / 1e9); push!(T.v, (t3 - t2) / 1e9); push!(T.l, (t4 - t3) / 1e9)
        end
    end
    return T
end

"The package, rebuilt every step: FleetProgram, reduce with reuse, sheaf_qp."
function run_rebuild(sc, res)
    fl = fleet(sc)
    x = formation_start(sc)
    prev = nothing; s = nothing
    T = (c = Float64[], s = Float64[], v = Float64[], l = Float64[])
    for step in 0:(STEPS-1)
        refs, term = references(sc, step * sc.h)
        t0 = time_ns()
        fp = FleetProgram(fl; x0 = x, references = refs, terminal = term)
        R = res isa Fine ? nothing : reduce(fp, res; reuse = prev)
        prev = R
        qp = sheaf_qp(R === nothing ? fp.program : R.program)
        t1 = time_ns()
        if s === nothing
            s = setup(qp; eps_abs = EPS, eps_rel = EPS, max_iter = 20_000)
        else
            update!(s; q = qp.q, b = qp_b(qp))
        end
        t2 = time_ns()
        solve!(s)
        t3 = time_ns()
        z = R === nothing ? s.xsol : lift(R, s.xsol)
        u = first_inputs(fp, z)
        t4 = time_ns()
        x = plant_step(fl, x, u)
        if step > 0
            push!(T.c, (t1 - t0) / 1e9); push!(T.s, (t2 - t1) / 1e9); push!(T.v, (t3 - t2) / 1e9); push!(T.l, (t4 - t3) / 1e9)
        end
    end
    return T
end

"The controller: data in place, update! through the reduction, QP vectors in place."
function run_controller(sc, res; certify = false)
    fl = fleet(sc)
    ctrl = MPCController(fl, res; certify = certify, eps_abs = EPS, eps_rel = EPS)
    x = formation_start(sc)
    T = (c = Float64[], s = Float64[], v = Float64[], l = Float64[], k = Float64[])
    J = Float64[]; allocs = Int[]
    for step in 0:(STEPS-1)
        refs, term = references(sc, step * sc.h)
        a = @allocated (info = step!(ctrl, x, refs; terminal = term))
        x = plant_step(fl, x, info.u)
        push!(J, info.J)
        if step > 0
            push!(T.c, info.t_construct); push!(T.s, info.t_setup); push!(T.v, info.t_solve); push!(T.l, info.t_lift)
            push!(T.k, info.t_certify); push!(allocs, a)
        end
    end
    return T, J, allocs, ctrl
end

function main()
    sc0 = Paper.FleetScenario(; rows = ROWS, cols = COLS, H = HZ, coherence = :rows, seed = SEED)
    sc = GridScenario(; rows = ROWS, cols = COLS, H = HZ, coherence = :rows, seed = SEED)
    println("grid $(ROWS)x$(COLS), H = $HZ, $STEPS steps, eps = $EPS; medians over steps 2..$STEPS, ms")
    @printf("%-18s %-10s %9s %9s %9s %9s %9s %9s\n", "level", "pipeline", "construct", "setup", "solve", "lift", "certify", "total")
    out = Dict{String,Any}[]
    for (name, res, alpha) in levels(sc)
        rows = [("research", run_research(sc0, sc, alpha)), ("rebuild", run_rebuild(sc, res))]
        Tc, J, allocs, ctrl = run_controller(sc, res)
        Tk, _, _, _ = run_controller(sc, res; certify = !(res isa Fine) && !(res isa TimeBlocking))
        for (pipe, T) in [rows; ("controller", Tc); ("certified", Tk)]
            k = haskey(T, :k) ? med(T.k) : 0.0
            tot = med(T.c) + med(T.s) + med(T.v) + med(T.l) + k
            @printf("%-18s %-10s %9.3f %9.3f %9.3f %9.3f %9.3f %9.3f\n", name, pipe, ms(med(T.c)), ms(med(T.s)), ms(med(T.v)),
                    ms(med(T.l)), ms(k), ms(tot))
            push!(out, Dict{String,Any}("level" => name, "pipeline" => pipe, "construct_ms" => ms(med(T.c)), "setup_ms" => ms(med(T.s)),
                                        "solve_ms" => ms(med(T.v)), "lift_ms" => ms(med(T.l)), "certify_ms" => ms(k),
                                        "total_ms" => ms(tot)))
        end
        @printf("%-18s controller allocates %d..%d bytes per step\n", "", minimum(allocs), maximum(allocs))
        flush(stdout)
    end
    mkpath(joinpath(@__DIR__, "results"))
    path = joinpath(@__DIR__, "results", "controller.json")
    open(io -> JSON.print(io, Dict("rows" => ROWS, "cols" => COLS, "H" => HZ, "steps" => STEPS, "eps" => EPS,
                                   "host" => gethostname(), "timings" => out), 1), path, "w")
    println("wrote ", path)
end

BLAS.set_num_threads(1)
main()
