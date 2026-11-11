# numbers_scalesim.jl: the \cn macros of E15 (closed-loop hard MPC on a Sierpinski
# fleet of 2187 ground vehicles, results/e15_summary.json from e15_summary.jl).
# Hook of scripts/gen_numbers.jl, which includes every numbers_<name>.jl.
#
# The summary comes from the incremental run (e15_sierpinski_scale_d7_incr.json:
# every program assembled per step by value updates of operators built once,
# offline construction excluded, medians of every timed sample) when it exists,
# and from the original run otherwise; the macro names are the same, their
# meanings below follow the source, and the incremental run adds three macros.

"True when results/e15_summary.json was made from the incremental run."
function scalesim_incremental()
    p = normpath(joinpath(@__DIR__, "..", "..", "results", "e15_summary.json"))
    return isfile(p) && occursin(r"\"incremental\"\s*:\s*true", read(p, String))
end

function scalesim_macro_specs()
    specs = Any[]
    add!(name, path, fmt, meaning) = push!(specs, (name, "e15_summary", Any[path...], fmt, meaning))
    N(k) = ["numbers", k]
    inc = scalesim_incremental()
    tsolve = inc ? "median of 5 repeats at each of 3 timed steps, Clarabel on the assembled QP" : "min of 3 at each of 3 steps"
    tasm = inc ? "the per-step assembly of the reduced program and of the time-expanded one (value updates of operators built once, offline construction excluded; medians)" :
                 "assembly of the reduced program and build of the fine one"
    add!("cnEfifteenN", N("n"), :fint, "vehicles of the large Sierpinski fleet")
    add!("cnEfifteenSteps", N("steps"), :fint, "closed-loop steps of E15")
    add!("cnEfifteenFineVars", N("fine_vars"), :fint, "variables of the time-expanded program at 2187 vehicles")
    add!("cnEfifteenFineSeconds", N("fine_seconds"), :fix1, "solve time of the time-expanded program, s ($tsolve)")
    add!("cnEfifteenAgentsSpeedup", N("agents_speedup"), :fix1, "speedup of the fully condensed agents level over the time-expanded program, solve alone ($tsolve)")
    add!("cnEfifteenFleetSpeedup", N("fleet_speedup"), :fint, "speedup of the fleet level over the time-expanded program, solve alone")
    add!("cnEfifteenAgentsSpeedupTotal", N("agents_speedup_total"), :fix1, "agents-level speedup counting $tasm")
    add!("cnEfifteenFleetSpeedupTotal", N("fleet_speedup_total"), :fint, "fleet speedup counting $tasm")
    add!("cnEfifteenTthreeSpeedupTotal", N("t3_speedup_total"), :fint, "teams of 3: speedup over the time-expanded program counting $tasm")
    add!("cnEfifteenTthreeOverAgents", N("t3_over_agents_total"), :fix1, "teams of 3: speedup over the fully condensed agents, assembly counted")
    add!("cnEfifteenCostThree", N("cost_t3"), :fix2, "closed-loop cost, teams of 3 over agents")
    add!("cnEfifteenCostTwentySeven", N("cost_t27"), :fix2, "closed-loop cost, teams of 27 over agents")
    add!("cnEfifteenCostTwoFortyThree", N("cost_t243"), :fix2, "closed-loop cost, teams of 243 over agents")
    add!("cnEfifteenCostFleet", N("cost_fleet"), :fix1, "closed-loop cost, whole fleet over agents")
    add!("cnEfifteenMatch", N("e14_position_diff"), :fsci, "largest position difference, sparse cluster builder against the library reduction (E14), 27 vehicles, every level and step")
    add!("cnEfifteenFinePlan", N("fine_plan_diff"), :fsci, "largest difference, agents-level plan against the time-expanded plan, every depth")
    if inc
        add!("cnEfifteenFineAssembleSeconds", N("fine_assemble_seconds"), :fsig, "per-step assembly of the time-expanded program by value updates, s (median)")
        add!("cnEfifteenFineOfflineSeconds", N("fine_offline_seconds"), :fsig, "one-off offline construction of the time-expanded program's operators, s (median)")
        add!("cnEfifteenIncrMatch", N("incr_obj_diff"), :fsci, "largest relative optimal-value difference, incremental against from-scratch reduced programs, every level, step and depth run")
    end
    return specs
end

if isdefined(Main, :defmacro!) && isdefined(Main, :MACROS)
    for (name, file, path, fmt, meaning) in scalesim_macro_specs()
        Main.defmacro!(name, file, path, getfield(Main, fmt), meaning)
    end
end
