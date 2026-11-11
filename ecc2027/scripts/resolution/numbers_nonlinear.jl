# numbers_nonlinear.jl: the \cn macros of E10 (nonlinear MPC through
# linearization, results/e10_nonlinear.json).
#
# Hook of scripts/gen_numbers.jl (the only writer of preamble/numbers.tex): when
# that script includes this file, every macro below is registered with its
# `defmacro!(name, file, path, fmt, meaning)`, so the value, its formatting and
# the provenance comment all come from gen_numbers.jl. Paths point into the
# `numbers` block that e10_nonlinear.jl derives from its per-instance records,
# or into its `claims` block. Formatters are gen_numbers.jl's own (fint, fsci,
# fsig, ffix, fpct, fratio, sig3, sci2, fix3, fix1): a function defined here
# would be too new for the already running generator (world age).
#
# `nonlinear_numbers()` returns the same macros as `(macro_name, value_string,
# json_path)` triples (names with the backslash), without gen_numbers.jl:
#
#   julia --project=env -e 'include("scripts/resolution/numbers_nonlinear.jl"); foreach(println, nonlinear_numbers())'

"""The macro table: (name without backslash, results file, key path, formatter name, meaning)."""
function nonlinear_macro_specs()
    specs = Any[]
    add!(name, file, path, fmt, meaning) = push!(specs, (name, file, Any[path...], fmt, meaning))
    E = "e10_nonlinear"
    N(k...) = Any["numbers", k...]
    W(c, k) = Any["claims", c, "worst", k]

    # the fleet and the problem
    add!("cnEtenAgents", E, N("n_agents"), :fint, "agents in the E10 fleet (2 x 4 grid)")
    add!("cnEtenQuads", E, N("n_quads"), :fint, "quadrotors (3D double integrators), one row")
    add!("cnEtenGround", E, N("n_ground"), :fint, "ground vehicles with nonlinear unicycle dynamics, one row")
    add!("cnEtenHorizon", E, N("H"), :fint, "horizon T of E10")
    add!("cnEtenStep", E, N("h"), :fix1, "sample time h of E10, s")
    add!("cnEtenInstances", E, N("n_instances"), :fint, "reference instances (S-curves and a steady turn)")
    add!("cnEtenAccelBound", E, N("amax"), :fix1, "ground vehicle acceleration bound |a|, m/s^2")
    add!("cnEtenTurnBound", E, N("wmax"), :ffix, "ground vehicle turn-rate bound |w|, rad/s")
    add!("cnEtenHeadingSwingMin", E, N("heading_swing_deg_min"), :fint, "smallest heading swing of the center reference over an instance, degrees")
    add!("cnEtenHeadingSwingMax", E, N("heading_swing_deg_max"), :fint, "largest heading swing of the center reference over an instance, degrees")
    add!("cnEtenHeadingSwingLoop", E, N("heading_swing_deg_closed_loop"), :fint, "heading swing of the closed-loop instance, degrees")

    # N1 condensing per SQP iteration
    add!("cnEtenCondIterates", E, N("n1_iterates"), :fint, "SQP iterates compared, sparse against fully condensed")
    add!("cnEtenCondItersMin", E, N("n1_iterations_min"), :fint, "fewest SQP iterations to convergence (fine program)")
    add!("cnEtenCondItersMax", E, N("n1_iterations_max"), :fint, "most SQP iterations to convergence (fine program)")
    add!("cnEtenCondPlanErr", E, N("n1_plan_rel_max"), :fsci, "largest relative plan difference of an SQP iterate, condensed against sparse")
    add!("cnEtenCondValueErr", E, N("n1_value_rel_max"), :fsci, "largest relative nonlinear value difference of an SQP iterate, condensed against sparse")
    add!("cnEtenFineVariables", E, N("n1_variables_fine"), :fint, "variables of the fine SQP subproblem")
    add!("cnEtenCondensedVariables", E, N("n1_variables_condensed"), :fint, "variables of the fully condensed SQP subproblem")

    # N2 the spatial leg commutes with linearization
    add!("cnEtenCommPoints", E, N("n2_points"), :fint, "coarse points at which reduction and linearization were compared")
    add!("cnEtenCommErr", E, N("n2_worst"), :fsci, "largest relative difference of the two coarse programs' data")
    add!("cnEtenCommDefect", E, W("nl:spatial_commutes", "max_nonlinear_defect_at_points"), :fsig, "largest nonlinear dynamics defect at a compared point")

    # N3 the reduced nonlinear program
    add!("cnEtenRedRuns", E, N("n3_runs"), :fint, "SQP runs on spatially reduced programs (instances x clusterings)")
    add!("cnEtenRedItersMax", E, N("n3_iterations_max"), :fint, "most SQP iterations of a reduced run")
    add!("cnEtenRedDefect", E, N("n3_defect_max"), :fsci, "largest nonlinear dynamics defect of a lifted reduced plan")
    add!("cnEtenRedIntra", E, N("n3_intra_max"), :fsci, "largest intra-cluster formation defect of a lifted reduced plan")
    add!("cnEtenRedPriceMin", E, N("n3_price_rel_min"), :fsig, "smallest price of a reduction over the fine nonlinear value")
    add!("cnEtenRedPriceMax", E, N("n3_price_rel_max"), :fsig, "largest price of a reduction over the fine nonlinear value")
    add!("cnEtenSandwichHolds", E, N("n3_sandwich_holds"), :fint, "reduced runs on which lower <= price <= upper holds at the converged points")
    add!("cnEtenLowerOverPriceMin", E, N("n3_lower_over_price_min"), :fsig, "smallest lower bound over price")
    add!("cnEtenPriceOverUpperMax", E, N("n3_price_over_upper_max"), :fsig, "largest price over the multiplier bound")
    add!("cnEtenPriceOverUpperMin", E, W("nl:price_sandwich_reported", "min_price_over_upper"), :fsig, "smallest price over the multiplier bound (mixed quadrotor and ground vehicle pairs)")

    # N4 the closed loop
    add!("cnEtenLoopSteps", E, N("n4_steps"), :fint, "closed-loop steps")
    add!("cnEtenLoopStateDiff", E, N("n4_state_diff"), :fsci, "largest relative state difference, condensed against fine closed loop")
    add!("cnEtenLoopFirstDefect", E, N("n4_first_defect_max"), :fsci, "largest defect between the planned and the applied first transition")
    add!("cnEtenLoopViolation", E, N("n4_input_violation_max"), :fsci, "largest input-bound violation of an applied input")
    add!("cnEtenLoopBoundStepsFine", E, N("n4_bound_steps_fine"), :fint, "closed-loop steps with an applied input on its bound, fine")
    add!("cnEtenLoopBoundStepsRows", E, N("n4_bound_steps_rows"), :fint, "closed-loop steps with an applied input on its bound, rows")
    add!("cnEtenLoopRowFormation", E, N("n4_row_formation_max"), :fsci, "largest within-row formation error of the row-reduced closed loop")
    add!("cnEtenLoopCostRatio", E, N("n4_cost_ratio"), :fratio, "realized closed-loop cost, rows over fine")
    add!("cnEtenLoopCostExcess", E, N("n4_cost_excess_percent"), :fint, "realized closed-loop cost excess of the rows over fine, percent")
    add!("cnEtenLoopPlanDefect", E, N("n4_plan_defect_median"), :fsci, "median nonlinear defect of a plan after one SQP iteration (fine)")
    add!("cnEtenLoopFormationFine", E, N("n4_formation_rms_fine"), :fix3, "mean RMS formation error of the fine closed loop, m")
    add!("cnEtenLoopFormationRows", E, N("n4_formation_rms_rows"), :fix3, "mean RMS formation error of the row-reduced closed loop, m")
    return specs
end

module NonlinearNumbersFallback
# Copies of gen_numbers.jl's formatters, used only by nonlinear_numbers() when
# this file is not included by gen_numbers.jl.
using Printf
tonum(x::Number) = Float64(x)
tonum(x::AbstractString) = x == "Inf" ? Inf : x == "-Inf" ? -Inf : x == "NaN" ? NaN : parse(Float64, x)
fint(x) = string(round(Int, tonum(x)))
function fsci(x; d::Int = 1)
    v = tonum(x); v == 0 && return "0"
    e = floor(Int, log10(abs(v))); m = round(v / 10.0^e; digits = d - 1)
    abs(m) >= 10 && (m /= 10; e += 1)
    ms = d == 1 ? string(round(Int, m)) : @sprintf("%.*f", d - 1, m)
    return "\\ensuremath{$(ms)\\times10^{$(e)}}"
end
function fsig(x; n::Int = 2)
    v = tonum(x); v == 0 && return "0"
    (abs(v) < 1e-3 || abs(v) >= 1e5) && return fsci(v; d = n)
    e = floor(Int, log10(abs(v))); dec = max(0, n - 1 - e)
    s = @sprintf("%.*f", dec, round(v; sigdigits = n))
    return v < 0 ? "\\ensuremath{$s}" : s
end
ffix(x; d::Int = 2) = (v = tonum(x); s = @sprintf("%.*f", d, v); v < 0 ? "\\ensuremath{$s}" : s)
fpct(x; d::Int = 0) = @sprintf("%.*f", d, 100 * tonum(x))
fratio(x) = (v = tonum(x); v > 0.9 ? @sprintf("%.5g", v) : fsig(v))
sig3(x) = fsig(x; n = 3)
sci2(x) = fsci(x; d = 2)
fix3(x) = ffix(x; d = 3)
fix1(x) = ffix(x; d = 1)
end

"""Follow a key path (strings and 1-based indices)."""
nonlinear_lookup(d, path) = foldl((v, p) -> v[p], path; init = d)

"""`(\\macro, value, "results/<file>.json: <path>")` for every E10 macro (standalone use)."""
function nonlinear_numbers()
    json = Base.require(Base.PkgId(Base.UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6"), "JSON"))
    root = normpath(joinpath(@__DIR__, "..", ".."))
    cache = Dict{String,Any}()
    out = Tuple{String,String,String}[]
    for (name, file, path, fmt, _) in nonlinear_macro_specs()
        d = get!(() -> Base.invokelatest(json.parsefile, joinpath(root, "results", file * ".json")), cache, file)
        v = Base.invokelatest(nonlinear_lookup, d, path)
        f = getfield(NonlinearNumbersFallback, fmt)
        push!(out, ("\\" * name, Base.invokelatest(f, v), "results/$(file).json: " * join(string.(path), "/")))
    end
    return out
end

# Registration with scripts/gen_numbers.jl (it includes this file after its own macros).
if isdefined(Main, :defmacro!) && isdefined(Main, :MACROS)
    for (name, file, path, fmt, meaning) in nonlinear_macro_specs()
        Main.defmacro!(name, file, path, getfield(Main, fmt), meaning)
    end
end

# ---------------------------------------------------------------------------
# Standalone generator of preamble/numbers_nonlinear.tex: the macros of the
# nonlinear-vehicles theorem (Theorem thm:nonlinear) from E114, acados SQP_RTI on
# the fleet and on the team program (results/e114_acados_rti.json, copied from
# the team-mpc-main tree, HPG runs). These macros are NOT registered with
# gen_numbers.jl, so they never enter preamble/numbers.tex; main.tex inputs the
# generated file with \InputIfFileExists.
#
#   julia --project=env scripts/resolution/numbers_nonlinear.jl
# ---------------------------------------------------------------------------

"""(name, run key, key path, formatter, meaning) for every E114 macro."""
function rti_macro_specs()
    F = NonlinearNumbersFallback
    sci2 = x -> F.fsci(x; d = 2)
    runs = (("Uni", "unicycle_n64_PARTIAL_CONDENSING_HPIPM", "unicycles"),
            ("Quad", "quadrotor_n16_PARTIAL_CONDENSING_HPIPM", "quaternion quadrotors, thrust in [0, Tmax]"))
    specs = Any[]
    for (tag, key, what) in runs
        push!(specs, ("cnNl$(tag)N", key, ["n"], F.fint, "E114 $what: vehicles"))
        push!(specs, ("cnNl$(tag)Teams", key, ["teams"], F.fint, "E114 $what: almost equitable teams"))
        push!(specs, ("cnNl$(tag)Steps", key, ["steps"], F.fint, "E114 $what: closed-loop steps of fleet and team RTI"))
        push!(specs, ("cnNl$(tag)Act", key, ["aep", "steps_with_active_limit_fleet"], F.fint, "E114 $what: steps with an active input limit (fleet; equal for the team)"))
        push!(specs, ("cnNl$(tag)Du", key, ["aep", "max_du"], sci2, "E114 $what: largest |u_fleet - lifted u_team| over all steps and vehicles"))
        push!(specs, ("cnNl$(tag)DuFirst", key, ["aep", "max_du_first_step"], F.fsci, "E114 $what: largest |u_fleet - lifted u_team| at the first step"))
        push!(specs, ("cnNl$(tag)Trans", key, ["hypotheses", "translation_residual"], F.fsci, "E114 $what: translation residual of the RK4 map"))
    end
    return specs
end

function write_rti_numbers(out = normpath(joinpath(@__DIR__, "..", "..", "preamble", "numbers_nonlinear.tex")))
    json = Base.require(Base.PkgId(Base.UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6"), "JSON"))
    root = normpath(joinpath(@__DIR__, "..", ".."))
    d = Base.invokelatest(json.parsefile, joinpath(root, "results", "e114_acados_rti.json"))
    Base.invokelatest(_write_rti_numbers, d, out)
end

function _write_rti_numbers(d, out)
    a = d["runs"]["unicycle_n64_PARTIAL_CONDENSING_HPIPM"]["aep"]
    q = d["runs"]["quadrotor_n16_PARTIAL_CONDENSING_HPIPM"]["aep"]
    @assert a["steps_with_active_limit_fleet"] == a["steps_with_active_limit_team"]
    @assert q["steps_with_active_limit_fleet"] == q["steps_with_active_limit_team"]
    lines = String["% GENERATED by scripts/resolution/numbers_nonlinear.jl from results/e114_acados_rti.json; do not edit by hand.",
                   "% Regenerate with `julia --project=env scripts/resolution/numbers_nonlinear.jl`.", ""]
    for (name, key, path, fmt, meaning) in rti_macro_specs()
        v = nonlinear_lookup(d["runs"][key], path)
        push!(lines, "% results/e114_acados_rti.json: runs/$key/$(join(path, "/")) :: $meaning")
        push!(lines, "\\newcommand{\\$name}{$(fmt(v))}")
    end
    write(out, join(lines, "\n") * "\n")
    println("wrote ", out)
end

if abspath(PROGRAM_FILE) == @__FILE__
    write_rti_numbers()
end
