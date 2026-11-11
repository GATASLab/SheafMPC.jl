# e15_summary.jl: the headline numbers of E15 (Sierpinski fleets of 3^d ground
# vehicles, run on HPG) and the validation of its reduced-program builder
# against E14 (the library's reduction on the 27-vehicle fleet).
#
#   julia --project=env scripts/resolution/experiments/e15_summary.jl
#
# Timings. When results/e15_sierpinski_scale_d7_incr.json exists (from
# e15_sierpinski_scale_incr.jl: incremental assembly of every program, offline
# construction reported apart, one estimator: median of every timed sample),
# the levels and the speedups come from it, and the rows keep the earlier
# numbers (from-scratch assembly, minimum over the timed steps) as *_before.
# Otherwise everything comes from results/e15_sierpinski_scale_d<d>.json as
# before. The same holds per depth for the E14 match (d = 3) and the plan
# check against the time-expanded program (d = 3 .. 7).
#
# Writes results/e15_summary.json.

using JSON, Printf

const RES15 = normpath(joinpath(@__DIR__, "..", "..", "..", "results"))
rd(n) = JSON.parsefile(joinpath(RES15, n * ".json"))
has(n) = isfile(joinpath(RES15, n * ".json"))
"The run of depth d: the incremental one when present."
run15(d) = has("e15_sierpinski_scale_d$(d)_incr") ? rd("e15_sierpinski_scale_d$(d)_incr") : rd("e15_sierpinski_scale_d$d")
f64(x) = x isa Number ? Float64(x) : x isa AbstractString ? parse(Float64, x) : NaN

clearance(lv) = min(minimum(f64(s["clearance"]) for s in lv["steps"]), f64(lv["final_clearance"]))

"The rows of the original run: from-scratch assembly, minimum over the timed steps."
function level_rows(d)
    fine = minimum(f64(f["t_solve_timing"]) for f in d["fine"])
    fine_total = minimum(f64(f["t_solve_timing"]) + f64(f["t_build"]) for f in d["fine"])
    base = f64(d["levels"][1]["closed_loop_cost"])
    rows = Dict{String,Any}[]
    for lv in d["levels"]
        t = minimum(f64(s["t_solve_timing"]) for s in lv["steps"] if get(s, "timed", false))
        tt = minimum(f64(s["t_solve_timing"]) + f64(s["t_assemble"]) for s in lv["steps"] if get(s, "timed", false))
        push!(rows, Dict{String,Any}("level" => lv["level"], "clusters" => lv["clusters"], "cluster_size" => lv["cluster_size"],
            "vars" => lv["steps"][1]["vars"], "t_solve" => t, "speedup" => fine / t,
            "t_total" => tt, "speedup_total" => fine_total / tt,
            "cost_ratio" => f64(lv["closed_loop_cost"]) / base, "min_clearance" => clearance(lv),
            "min_input_margin" => minimum(f64(s["input_margin"]) for s in lv["steps"])))
    end
    return rows, fine, fine_total
end

"""The rows of the incremental run: medians (and min, max) of every timed sample."""
function level_rows_incr(d)
    fs, fa = d["fine_solve"], d["fine_assemble"]
    fine, fine_asm = f64(fs["median"]), f64(fa["median"])
    fine_total = fine + fine_asm
    base = f64(d["levels"][1]["closed_loop_cost"])
    rows = Dict{String,Any}[]
    for lv in d["levels"]
        s, a, o = lv["solve"], lv["assemble"], lv["offline"]
        t, ta = f64(s["median"]), f64(a["median"])
        tt = t + ta
        r = Dict{String,Any}("level" => lv["level"], "clusters" => lv["clusters"], "cluster_size" => lv["cluster_size"],
            "vars" => lv["steps"][1]["vars"],
            "t_solve" => t, "t_solve_min" => f64(s["min"]), "t_solve_max" => f64(s["max"]),
            "t_assemble" => ta, "t_assemble_min" => f64(a["min"]), "t_assemble_max" => f64(a["max"]),
            "t_offline" => f64(o["median"]), "t_offline_min" => f64(o["min"]), "t_offline_max" => f64(o["max"]),
            "t_total" => tt, "speedup" => fine / t, "speedup_total" => fine_total / tt,
            "cost_ratio" => f64(lv["closed_loop_cost"]) / base, "min_clearance" => clearance(lv),
            "min_input_margin" => minimum(f64(s["input_margin"]) for s in lv["steps"]),
            "max_obj_rel_scratch" => f64(lv["max_obj_rel_scratch"]), "max_data_diff" => f64(lv["max_data_diff"]))
        if haskey(lv, "teammpc")
            sm = lv["teammpc"]
            smt = ta + f64(sm["update"]["median"]) + f64(sm["solve"]["median"])
            r["teammpc"] = Dict{String,Any}("t_setup" => f64(sm["setup"]),
                "t_update" => f64(sm["update"]["median"]), "t_update_min" => f64(sm["update"]["min"]), "t_update_max" => f64(sm["update"]["max"]),
                "t_solve" => f64(sm["solve"]["median"]), "t_solve_min" => f64(sm["solve"]["min"]), "t_solve_max" => f64(sm["solve"]["max"]),
                "t_total" => smt, "speedup_total" => fine_total / smt, "over_clarabel_total" => tt / smt,
                "max_obj_rel" => f64(sm["max_obj_rel"]), "max_violation" => f64(sm["max_violation"]),
                "statuses" => sm["statuses"], "candidates" => sm["candidates"])
        end
        push!(rows, r)
    end
    return rows, fine, fine_total, fine_asm
end

function main()
    old7 = rd("e15_sierpinski_scale_d7")
    rows_old, tfine_old, tfine_total_old = level_rows(old7)
    incremental = has("e15_sierpinski_scale_d7_incr")
    d7 = incremental ? rd("e15_sierpinski_scale_d7_incr") : old7
    if incremental
        rows, tfine, tfine_total, tfine_asm = level_rows_incr(d7)
        for (r, ro) in zip(rows, rows_old)
            r["level"] == ro["level"] || error("level mismatch")
            for k in ("t_solve", "t_total", "speedup", "speedup_total")
                r[k*"_before"] = ro[k]
            end
            r["cost_ratio_before"] = ro["cost_ratio"]
        end
    else
        rows, tfine, tfine_total = rows_old, tfine_old, tfine_total_old
    end
    e14 = rd("e14_shapes_sim"); d3 = run15(3)
    posdiff = maximum(maximum(max(abs(p[1] - q[1]), abs(p[2] - q[2])) for (sa, sb) in zip(la["steps"], lb["steps"])
                              for (p, q) in zip(sa["positions"], sb["positions"]))
                      for (la, lb) in zip(e14["levels"], d3["levels"]))
    costdiff = maximum(abs(f64(la["closed_loop_cost"]) - f64(lb["closed_loop_cost"])) / f64(la["closed_loop_cost"])
                       for (la, lb) in zip(e14["levels"], d3["levels"]))
    runs = [run15(dd) for dd in (3, 4, 5, 6, 7)]
    finediff = maximum(f64(f["plan_vs_reduced"]) for r in runs for f in r["fine"])
    by(l) = only(r for r in rows if r["level"] == l)
    nums = Dict{String,Any}(
        "n" => d7["n"], "steps" => d7["steps"], "fine_vars" => d7["fine"][1]["vars"], "fine_seconds" => tfine,
        "agents_speedup" => by(0)["speedup"], "fleet_speedup" => by(7)["speedup"], "fleet_seconds" => by(7)["t_solve"],
        "fine_total_seconds" => tfine_total, "agents_speedup_total" => by(0)["speedup_total"],
        "fleet_speedup_total" => by(7)["speedup_total"],
        "t3_speedup" => by(1)["speedup"], "t3_speedup_total" => by(1)["speedup_total"],
        "t3_over_agents_total" => by(1)["speedup_total"] / by(0)["speedup_total"],
        "cost_t3" => by(1)["cost_ratio"], "cost_t27" => by(3)["cost_ratio"], "cost_t243" => by(5)["cost_ratio"],
        "cost_fleet" => by(7)["cost_ratio"],
        "min_clearance" => minimum(r["min_clearance"] for r in rows), "min_input_margin" => minimum(r["min_input_margin"] for r in rows),
        "e14_position_diff" => posdiff, "e14_cost_diff" => costdiff, "fine_plan_diff" => finediff,
        "machine" => d7["machine"]["cpu"], "incremental" => incremental,
        "depths_incremental" => [dd for dd in (3, 4, 5, 6, 7) if has("e15_sierpinski_scale_d$(dd)_incr")])
    if incremental
        incr_runs = [r for r in runs if haskey(r, "fine_solve")]
        nums["fine_assemble_seconds"] = tfine_asm
        nums["fine_offline_seconds"] = f64(d7["fine_offline"]["median"])
        nums["fine_solve_min"] = f64(d7["fine_solve"]["min"]); nums["fine_solve_max"] = f64(d7["fine_solve"]["max"])
        nums["repeats"] = d7["estimator"]["repeats"]; nums["timed_steps"] = length(d7["estimator"]["timed_steps"])
        nums["incr_obj_diff"] = maximum(f64(lv["max_obj_rel_scratch"]) for r in incr_runs for lv in r["levels"])
        nums["incr_data_diff"] = maximum(f64(lv["max_data_diff"]) for r in incr_runs for lv in r["levels"])
        nums["incr_same_pattern"] = all(lv["same_pattern"] for r in incr_runs for lv in r["levels"])
        nums["fine_obj_diff"] = maximum(f64(f["obj_rel_direct"]) for r in incr_runs for f in r["fine"])
        nums["fine_data_diff"] = maximum(maximum(f64(v) for v in values(f["data_diff"])) for r in incr_runs for f in r["fine"])
        nums["loadavg"] = d7["loadavg"]
        nums["before"] = Dict{String,Any}("fine_seconds" => tfine_old, "fine_total_seconds" => tfine_total_old,
            "agents_speedup" => by(0)["speedup_before"], "fleet_speedup" => by(7)["speedup_before"],
            "agents_speedup_total" => by(0)["speedup_total_before"], "fleet_speedup_total" => by(7)["speedup_total_before"],
            "t3_speedup_total" => by(1)["speedup_total_before"])
        if haskey(by(0), "teammpc")
            nums["teammpc_max_obj_rel"] = maximum(r["teammpc"]["max_obj_rel"] for r in rows)
            nums["teammpc_max_violation"] = maximum(r["teammpc"]["max_violation"] for r in rows)
        end
    end
    out = Dict{String,Any}("experiment" => "E15-summary", "levels" => rows, "numbers" => nums,
                           "source" => incremental ? "e15_sierpinski_scale_d7_incr" : "e15_sierpinski_scale_d7")
    open(io -> JSON.json(io, out; pretty = 2), joinpath(RES15, "e15_summary.json"), "w")
    @printf("n=%d (%s): fine %.2f s, agents x%.1f (x%.1f with assembly), fleet x%.0f (x%.0f); E14 match %.1e (cost %.1e); fine plan %.1e; clearance %.1e\n",
            d7["n"], incremental ? "incremental" : "from scratch", tfine, by(0)["speedup"], by(0)["speedup_total"],
            by(7)["speedup"], by(7)["speedup_total"], posdiff, costdiff, finediff, nums["min_clearance"])
    if incremental
        @printf("  incremental vs from scratch: objective %.1e, data %.1e, same pattern %s; fine vs solve_direct %.1e\n",
                nums["incr_obj_diff"], nums["incr_data_diff"], nums["incr_same_pattern"], nums["fine_obj_diff"])
    end
end
main()
