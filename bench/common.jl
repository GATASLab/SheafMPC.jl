# common.jl: shared helpers of the benchmarks: the centralized fleet QP of the
# paper repository (bench/central/qp.jl, included read-only), its conversion to
# a ConicQP, reference solves with Clarabel and OSQP, and timing.

using SheafMPC, Clarabel, OSQP, LinearAlgebra, SparseArrays, Printf, Statistics, JSON

const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))
haskey(ENV, "BENCH_ABAR") || (ENV["BENCH_ABAR"] = "1.0")          # the constrained setting of the paper's latest runs
isdefined(Main, :blocked_qp) || include(joinpath(PAPER, "bench", "central", "qp.jl"))

"The fleet QP (qp.jl's `BlockedQP`) as a ConicQP: equality rows, then the input constraints."
function fleet_conic(Q; cone::String = "box")
    ny = length(Q.q); nb = length(Q.ubox)
    me = size(Q.Aeq, 1)
    if cone == "box"
        Ab = sparse(1:nb, Q.ubox, ones(nb), nb, ny)
        A = [Q.Aeq; Ab]
        l = [Q.beq; fill(-ABAR, nb)]; u = [Q.beq; fill(ABAR, nb)]
        kinds = [fill(SheafMPC.ROW_EQ, me); fill(SheafMPC.ROW_INTERVAL, nb)]
        return ConicQP(Q.P, Q.q, A, l, u; c = Q.c, kinds = kinds)
    end
    I = Int[]; J = Int[]; V = Float64[]; b = Float64[]; row = 0
    cones = Tuple{Symbol,Int}[]
    me > 0 && push!(cones, (:zero, me))
    for p in 1:2:nb
        row += 1; push!(b, ABAR)
        for a in 0:1
            row += 1; push!(I, row); push!(J, Q.ubox[p+a]); push!(V, -1.0); push!(b, 0.0)
        end
        push!(cones, (:soc, 3))
    end
    return ConicQP(Q.P, Q.q, [Q.Aeq; sparse(I, J, V, row, ny)], [Q.beq; b], cones; c = Q.c)
end

"A set-up Clarabel solver for a ConicQP (Clarabel form rebuilt from the rows)."
function clarabel_setup(p::ConicQP; tol = 1e-10)
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
    return s
end

"Clarabel on a ConicQP, returns (obj, x, status, iterations, time)."
function clarabel_solve(p::ConicQP; tol = 1e-10, reps = 0)
    s = clarabel_setup(p; tol = tol)
    r = Clarabel.solve!(s)
    ts = Float64[]
    for _ in 1:reps
        push!(ts, @elapsed(r = Clarabel.solve!(s)))
    end
    return (obj = SheafMPC.objective(p, r.x), x = r.x, status = string(r.status), iters = r.iterations,
            t = isempty(ts) ? NaN : minimum(ts), tmed = isempty(ts) ? NaN : median(ts))
end

relgap(a, b) = abs(a - b) / max(1.0, abs(b))
