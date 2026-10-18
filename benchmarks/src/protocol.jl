# protocol.jl: calibration to a matched achieved accuracy, the cold single-QP
# mode and the warm-started sequence mode, with one wall clock per call.
#
# Accuracy tiers: low 1e-3, medium 1e-6, high 1e-9. A solve meets tier eps when
# the shared checker (qp.jl `check`) finds relative objective error <= eps and
# relative primal residual <= eps against the reference of that QP.
#
# Calibration (untimed for the result; it also compiles every code path): on
# the first QP of the instance's sequence, every variant of the solver is
# tried with its tolerance at eps, eps/10, eps/100, eps/1000 (the solver's own
# termination tolerance is not the achieved accuracy); the loosest tolerance
# that meets the tier is kept per variant, and the variant with the smallest
# median solve time over 3 cold solves wins. Every later QP of the instance
# runs with that (variant, tolerance); a QP that then misses the tier is a
# failure. A solver that meets the tier with no variant fails the whole
# instance at that tier (recorded with its best achieved accuracy).
#
# Cold mode: every QP of the sequence (up to `cold_qps` of them), `reps`
# times: setup (timed separately) then solve from zero (timed).
# Warm mode: `reps` replays of the whole sequence. Each replay sets up on the
# first QP and solves it cold; every later QP is one timed call of update!
# (new vectors, factorization kept) + warm! (the solver's own previous
# solution, moved one stage by the family's shift map when it has one) +
# solve!. Interior-point solvers have no warm!; they still reuse the setup.
# Per QP the time is the median over the repeats; reported over the sequence:
# median, p90 and max. The timer is `time_ns` around the call; a young
# generation GC runs before each timed call, outside the clock.

using Statistics

const TIERS = [("low", 1e-3), ("medium", 1e-6), ("high", 1e-9)]

struct Instance
    family::String
    name::String
    params::Dict{String,Any}
    seq::Vector{QP}
    refs::Vector{Reference}
    shift::Union{Nothing,Tuple{Vector{Int},Vector{Int}}}
    t_generate::Float64
end

function timed(f)
    GC.gc(false)
    t0 = time_ns()
    r = f()
    return r, (time_ns() - t0) * 1e-9
end

function safe_setup(spec, p, eps, v)
    try
        return spec.setup(p, eps, v), nothing
    catch e
        return nothing, sprint(showerror, e)[1:min(end, 300)]
    end
end

function safe_solve(spec, h, n)
    try
        return spec.solve!(h)
    catch e
        @warn "$(spec.name) solve failed" exception = (e, catch_backtrace())
        return failed_result(n)
    end
end

"""
    calibrate(spec, inst, eps; time_cap) -> Dict

The (variant, tolerance) this solver uses for this instance at tier `eps`.
"""
function calibrate(spec::SolverSpec, inst::Instance, eps; time_cap = 60.0)
    p = inst.seq[1]; ref = inst.refs[1]
    trials = Dict{String,Any}[]
    best = nothing
    for v in spec.variants
        for f in (1.0, 0.1, 0.01, 0.001)
            tol = eps * f
            h, err = safe_setup(spec, p, tol, v)
            if h === nothing
                push!(trials, Dict{String,Any}("variant" => v, "tol" => tol, "error" => err)); break
            end
            r, t = timed(() -> safe_solve(spec, h, nvars(p)))
            c = check(p, r.x, r.y, ref.obj0)
            tr = Dict{String,Any}("variant" => v, "tol" => tol, "status" => string(r.status), "obj_err" => c.obj_err,
                                  "prim_rel" => c.prim_rel, "t" => t, "iters" => r.iters)
            push!(trials, tr)
            if meets(c, eps)
                ts = [t]
                for _ in 1:2
                    t > time_cap / 4 && break
                    h2, _ = safe_setup(spec, p, tol, v)
                    _, t2 = timed(() -> safe_solve(spec, h2, nvars(p)))
                    push!(ts, t2)
                end
                tr["t_med"] = median(ts)
                if best === nothing || tr["t_med"] < best["t_med"]
                    best = tr
                end
                break
            end
            t > time_cap && break
        end
    end
    return Dict{String,Any}("chosen" => best, "trials" => trials)
end

function result_row(p::QP, ref::Reference, r::SolveResult, eps)
    c = check(p, r.x, r.y, ref.obj0)
    return Dict{String,Any}("status" => string(r.status), "iters" => r.iters, "obj_err" => c.obj_err,
                            "prim_rel" => c.prim_rel, "dual_rel" => c.dual_rel, "ok" => meets(c, eps),
                            "t_internal" => r.t_internal)
end

"Cold mode: per QP, reps x (setup, solve from zero)."
function run_cold(spec::SolverSpec, inst::Instance, eps, v, tol; reps = 3, cold_qps = typemax(Int))
    rows = Dict{String,Any}[]
    for (j, p) in enumerate(inst.seq)
        j > cold_qps && break
        ts = Float64[]; tsu = Float64[]; last = nothing
        for _ in 1:reps
            GC.gc(false)
            t0 = time_ns()
            h, err = safe_setup(spec, p, tol, v)
            push!(tsu, (time_ns() - t0) * 1e-9)
            if h === nothing
                last = failed_result(nvars(p)); push!(ts, NaN); break
            end
            r, t = timed(() -> safe_solve(spec, h, nvars(p)))
            push!(ts, t); last = r
        end
        row = result_row(p, inst.refs[j], last, eps)
        row["qp"] = j; row["t"] = ts; row["t_med"] = median(ts); row["t_min"] = minimum(ts)
        row["t_setup_med"] = median(tsu)
        push!(rows, row)
    end
    return rows
end

function shifted(x, map)
    (x === nothing || map === nothing) && return x
    return [k == 0 ? 0.0 : x[k] for k in map]
end

"Warm mode: reps replays of the sequence (update! + warm! + solve! per QP after the first)."
function run_warm(spec::SolverSpec, inst::Instance, eps, v, tol; reps = 3)
    L = length(inst.seq)
    times = fill(NaN, L, reps); lastres = Vector{Any}(nothing, L); tsetup = Float64[]
    for rep in 0:reps                      # replay 0 (two QPs) compiles update! and warm!, discarded
        GC.gc(false)
        t0 = time_ns()
        h, err = safe_setup(spec, inst.seq[1], tol, v)
        rep >= 1 && push!(tsetup, (time_ns() - t0) * 1e-9)
        h === nothing && break
        r, t = timed(() -> safe_solve(spec, h, nvars(inst.seq[1])))
        rep >= 1 && (times[1, rep] = t); lastres[1] = r
        prev = r
        for j in 2:(rep == 0 ? min(L, 2) : L)
            p = inst.seq[j]
            xw = yw = nothing
            if spec.warm! !== nothing
                okx = all(isfinite, prev.x)
                xw = okx ? shifted(prev.x, inst.shift === nothing ? nothing : inst.shift[1]) : zeros(nvars(p))
                yw = (prev.y === nothing || !all(isfinite, prev.y)) ? nothing :
                     shifted(prev.y, inst.shift === nothing ? nothing : inst.shift[2])
            end
            GC.gc(false)
            t0 = time_ns()
            r = try
                spec.update!(h, p)
                spec.warm! !== nothing && spec.warm!(h, xw, yw)
                spec.solve!(h)
            catch e
                @warn "$(spec.name) warm step failed" exception = (e, catch_backtrace())
                failed_result(nvars(p))
            end
            rep >= 1 && (times[j, rep] = (time_ns() - t0) * 1e-9)
            lastres[j] = r; prev = r
        end
    end
    rows = Dict{String,Any}[]
    for j in 1:L
        r = lastres[j] === nothing ? failed_result(nvars(inst.seq[j])) : lastres[j]
        row = result_row(inst.seq[j], inst.refs[j], r, eps)
        row["qp"] = j; row["t"] = times[j, :]; row["t_med"] = medfin(filter(isfinite, times[j, :]))
        push!(rows, row)
    end
    return rows, tsetup
end

medfin(v) = isempty(v) ? NaN : median(v)

function seqstats(rows; skipfirst = false)
    rr = skipfirst ? rows[2:end] : rows
    t = [r["t_med"] for r in rr if r["ok"]]
    nf = count(r -> !r["ok"], rr)
    isempty(t) && return Dict{String,Any}("median" => NaN, "p90" => NaN, "max" => NaN, "failures" => nf, "count" => length(rr))
    return Dict{String,Any}("median" => median(t), "p90" => quantile(t, 0.9), "max" => maximum(t), "failures" => nf,
                            "count" => length(rr), "iters_med" => median([r["iters"] for r in rr]))
end
