# reduced.jl: the same solver on a fine sheaf program and on its pushforwards.
#
#   julia --project=bench bench/reduced.jl
#
# The paper's grid fleet (scripts/resolution/experiments/common_spatial.jl,
# included read only): ROWS x COLS agents, rows alternating quadrotors and
# ground vehicles, horizon H, hard dynamics, each row tracking its own centre
# trajectory (coherence :rows), second-order cone input bounds. Levels: the fine
# program (every agent its own vertex at every instant) and the pushforwards
# along the spatial resolutions alpha box id of teams of k = 1, 2, 4, 8 whole
# rows (k = ROWS is the whole fleet as one rigid formation), with the
# structured fibre basis of pushforward.jl when it is available (otherwise the
# rref basis; the basis used is printed and recorded).
#
# Per level: the program's size, the pushforward time, SheafMPC's setup and
# cold solve time (min and median over REPS), Clarabel's solve time (setup
# excluded, tolerance 1e-8), the objective J (with its constant) and its
# gap to the fine optimum (the price of the reduction), and SheafMPC's accuracy
# against Clarabel on the same program. Then a receding-horizon run of STEPS
# steps at every level (fibres reused across steps, `pushforward(...; reuse)`;
# SheafMPC with `update!` and a warm start from the previous solution, the
# factorizations kept), timed per step for the solve and for the pushforward.

const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))
include(joinpath(PAPER, "scripts", "resolution", "experiments", "common_spatial.jl"))
import SheafMPC
using SheafMPC: ConicQP, setup, solve!, sheaf_qp, reset!, update!, warm_start!, nvars, nrows

const ROWS = parse(Int, get(ENV, "BENCH_ROWS", "8"))
const COLS = parse(Int, get(ENV, "BENCH_COLS", "8"))
const HZ = parse(Int, get(ENV, "BENCH_H", "10"))
const KS = parse.(Int, split(get(ENV, "BENCH_K", "1,2,4,8"), ","))
const REPS = parse(Int, get(ENV, "BENCH_REPS", "7"))
const STEPS = parse(Int, get(ENV, "BENCH_STEPS", "10"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))
const ABAR_SCALE = parse(Float64, get(ENV, "BENCH_ABAR_SCALE", "1.0"))
const SEED = 20261018

relg(a, b) = abs(a - b) / max(1.0, abs(b))

"Clarabel on a ConicQP (Clarabel form rebuilt from the rows), returns (obj, x, status, iterations, time)."
function clarabel_solve(p::ConicQP; tol = 1e-10, reps = 0)
    m = nrows(p); n = nvars(p)
    rows = Int[]; b = Float64[]; sgn = Float64[]; cones = Clarabel.SupportedCone[]
    # equality rows, then one-sided rows, then SOC blocks
    eq = [i for i in 1:m if p.kinds[i] != SheafMPC.ROW_SOC && p.l[i] == p.u[i]]
    isempty(eq) || (append!(rows, eq); append!(b, p.u[eq]); append!(sgn, ones(length(eq))); push!(cones, Clarabel.ZeroConeT(length(eq))))
    ub = [i for i in 1:m if p.kinds[i] != SheafMPC.ROW_SOC && p.l[i] != p.u[i] && p.u[i] < Inf]
    lb = [i for i in 1:m if p.kinds[i] != SheafMPC.ROW_SOC && p.l[i] != p.u[i] && p.l[i] > -Inf]
    if !isempty(ub) || !isempty(lb)
        append!(rows, ub); append!(b, p.u[ub]); append!(sgn, ones(length(ub)))
        append!(rows, lb); append!(b, -p.l[lb]); append!(sgn, -ones(length(lb)))
        push!(cones, Clarabel.NonnegativeConeT(length(ub) + length(lb)))
    end
    for B in p.socs
        append!(rows, B); append!(b, p.socb[B]); append!(sgn, ones(length(B)))
        push!(cones, Clarabel.SecondOrderConeT(length(B)))
    end
    A = Diagonal(sgn) * p.A[rows, :]
    st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol, tol_ktratio = min(1e-6, tol),
                           presolve_enable = false, max_iter = 500)
    s = Clarabel.Solver()
    Clarabel.setup!(s, SparseMatrixCSC(triu(p.P)), p.q, SparseMatrixCSC(A), b, cones, st)
    r = Clarabel.solve!(s)
    ts = Float64[]
    for _ in 1:reps
        push!(ts, @elapsed(r = Clarabel.solve!(s)))
    end
    return (obj = SheafMPC.objective(p, r.x), x = r.x, status = string(r.status), iters = r.iterations,
            t = isempty(ts) ? NaN : minimum(ts), tmed = isempty(ts) ? NaN : median(ts))
end



function pick_basis(P, Pi)
    for basis in (:structured, :rref)
        try
            Pc, L = pushforward(P, Pi; basis = basis)
            return basis
        catch err
            @warn "basis $basis unavailable" exception = (err, catch_backtrace())
        end
    end
    error("no fibre basis works")
end

function level_partition(model, k)
    k == 0 && return collect(1:nvertices(model.program))                  # fine
    alpha = k == 1 ? sp_rows(ROWS, COLS) : sp_strips(ROWS, COLS, k)
    return spatial_partition(model, alpha)
end

level_name(k) = k == 0 ? "fine" : k == ROWS ? "fleet (k=$k)" : "teams k=$k"

function solve_level(P; reps = REPS)
    qp = sheaf_qp(P)
    s = setup(qp; eps_abs = EPS, eps_rel = EPS, max_iter = 20_000)
    reset!(s); solve!(s)
    ts = Float64[]; info = s.info
    for _ in 1:reps
        reset!(s)
        info = solve!(s)
        push!(ts, info.solve_time)
    end
    return s, qp, (t = minimum(ts), tmed = median(ts), obj = info.obj, iters = info.iter, status = info.status,
                   polish = info.polish, setup = s.info.setup_time, linsys = s.info.linsys)
end

# Clarabel: the paper's solve_direct (setup, solve and its active-set polish,
# for the objective J) and, timed, Clarabel's solve alone at 1e-8 on the same QP
function clarabel_level(P, qp; reps = REPS)
    sol = solve_direct(P)
    c = clarabel_solve(qp; tol = 1e-8, reps = reps)
    return sol, c.t, c.tmed
end

function main()
    sc = FleetScenario(; rows = ROWS, cols = COLS, H = HZ, coherence = :rows, abar_scale = ABAR_SCALE, seed = SEED)
    layout = sp_grid(sc.rows, sc.cols; spacing = sc.spacing)[2]
    spec = fleet_spec(sc; xhat = formation_start(sc, layout), t0 = 0.0)
    model = build_model(spec)
    P = model.program
    basis = pick_basis(P, level_partition(model, 2))
    println("grid $(ROWS)x$(COLS), H = $HZ, fibre basis: $basis")
    rows = Dict{String,Any}[]
    Jfine = NaN
    @printf("%-14s %7s %7s %9s %9s %9s %9s %9s %10s %9s %9s %s\n", "level", "vars", "rows", "push ms", "setup ms",
            "ours ms", "ours med", "clar ms", "J", "price", "vs clar", "iters/polish")
    for k in [0; KS]
        Pi = level_partition(model, k)
        tp = k == 0 ? 0.0 : @elapsed((Pc, L) = pushforward(P, Pi; basis = basis))
        Pk = k == 0 ? P : Pc
        s, qp, r = solve_level(Pk)
        sol, tc, tcm = clarabel_level(Pk, qp)
        k == 0 && (Jfine = sol.J)
        nsoc_act = count(B -> SheafMPC.soc_distance(s.ysol, B) < 1e-12 && norm(s.ysol[B]) > 1e-9, qp.socs)
        @printf("%-14s %7d %7d %9.2f %9.2f %9.3f %9.3f %9.3f %10.5f %9.2e %9.1e %d/%s (%s, %d active SOC)\n", level_name(k),
                nvars(qp), nrows(qp), 1e3 * tp, 1e3 * r.setup, 1e3 * r.t, 1e3 * r.tmed, 1e3 * tc, r.obj,
                (sol.J - Jfine) / abs(Jfine), relg(r.obj, sol.J), r.iters, r.polish, r.linsys, nsoc_act)
        push!(rows, Dict{String,Any}("level" => level_name(k), "k" => k, "vars" => nvars(qp), "rows" => nrows(qp),
                                     "nnz_P" => nnz(qp.P), "nnz_A" => nnz(qp.A), "t_pushforward" => tp,
                                     "t_setup" => r.setup, "t_solve" => r.t, "t_solve_med" => r.tmed, "iters" => r.iters,
                                     "polish" => string(r.polish), "status" => string(r.status), "obj" => r.obj,
                                     "J_clarabel" => sol.J, "t_clarabel" => tc, "t_clarabel_med" => tcm,
                                     "price_rel" => (sol.J - Jfine) / abs(Jfine), "gap_vs_clarabel" => relg(r.obj, sol.J),
                                     "linsys" => string(r.linsys), "active_soc" => nsoc_act))
        flush(stdout)
    end
    # receding horizon at every level
    println("\nreceding horizon, $STEPS steps (fibres reused; SheafMPC warm from the previous solution, factorizations kept)")
    @printf("%-14s %10s %10s %10s %10s %10s %8s %9s\n", "level", "push med", "ours med", "ours max", "cold med",
            "clar med", "iters", "max gap")
    rh = Dict{String,Any}[]
    for k in [0; KS]
        x = formation_start(sc, layout)
        prev = nothing; s = nothing; s0c = 0.0; s0P = spzeros(0, 0); s0A = spzeros(0, 0)
        tps = Float64[]; tws = Float64[]; tcs = Float64[]; tcl = Float64[]; its = Int[]; gaps = Float64[]
        for step in 0:(STEPS-1)
            spec = fleet_spec(sc; xhat = x, t0 = step * sc.h)
            model = build_model(spec)
            Pi = level_partition(model, k)
            local Pk, L
            if k == 0
                Pk = model.program; L = nothing
            else
                tp = @elapsed((Pk, L) = pushforward(model.program, Pi; basis = basis, reuse = prev))
                prev = (model.program, L)
                push!(tps, tp)
            end
            qp = sheaf_qp(Pk)
            sol = solve_direct(Pk)
            push!(tcl, clarabel_solve(qp; tol = 1e-8, reps = 1).t)
            if s === nothing || qp.P != s0P || qp.A != s0A
                s = setup(qp; eps_abs = EPS, eps_rel = EPS, max_iter = 20_000)
                s0P = qp.P; s0A = qp.A; s0c = qp.c
                solve!(s); reset!(s)
                info = solve!(s)
                step > 0 && @warn "level $(level_name(k)): structure changed at step $step, new setup"
            else
                bvec = [qp.kinds[i] == SheafMPC.ROW_SOC ? qp.socb[i] : qp.u[i] for i in 1:nrows(qp)]
                t = @elapsed begin
                    update!(s; q = qp.q, b = bvec, c = qp.c)
                    info = solve!(s)
                end
                push!(tws, t); push!(its, info.iter)
                # cold solve of the same program, for comparison
                reset!(s); ic = solve!(s); push!(tcs, ic.solve_time)
                warm_start!(s; x = copy(s.xsol), y = copy(s.ysol))
                info = solve!(s)
            end
            push!(gaps, relg(info.obj, sol.J))
            z = k == 0 ? s.xsol : lift(L, s.xsol)
            u = [agent_state(model, z, i, 0)[2] for i in 1:spec.n]
            x = [spec.agents[i].A[1] * x[i] + spec.agents[i].B[1] * u[i] + spec.agents[i].c[1] for i in 1:spec.n]
        end
        @printf("%-14s %10.3f %10.3f %10.3f %10.3f %10.3f %8.1f %9.1e\n", level_name(k), isempty(tps) ? 0.0 : 1e3 * median(tps),
                1e3 * median(tws), 1e3 * maximum(tws), 1e3 * median(tcs), 1e3 * median(tcl), median(its), maximum(gaps))
        push!(rh, Dict{String,Any}("level" => level_name(k), "k" => k, "t_push_med" => isempty(tps) ? 0.0 : median(tps),
                                   "t_warm_med" => median(tws), "t_warm_max" => maximum(tws), "t_cold_med" => median(tcs),
                                   "t_clarabel_med" => median(tcl), "iters_med" => median(its), "max_gap" => maximum(gaps)))
        flush(stdout)
    end
    out = joinpath(@__DIR__, "results", "reduced.json")
    open(io -> JSON.print(io, Dict("static" => rows, "rh" => rh, "basis" => string(basis), "rows" => ROWS, "cols" => COLS,
                                   "H" => HZ, "eps" => EPS, "abar_scale" => ABAR_SCALE, "host" => gethostname()), 1), out, "w")
    println("wrote ", out)
end

BLAS.set_num_threads(1)
main()
