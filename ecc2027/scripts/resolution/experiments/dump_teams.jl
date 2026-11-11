# dump_teams.jl: positions, edges and team labels of the planted squads and the natural formation, for the
# grouping figure (render/fig_teams_map.py). No MPC solves.
#   julia --project=env scripts/resolution/experiments/dump_teams.jl  -> results/teams_map.json
include(joinpath(@__DIR__, "e30_bounds_dc.jl"))
include(joinpath(@__DIR__, "squads_dc.jl"))
using JSON
function dumpinst(inst, choices, seed)
    D = Dict{String,Any}("x" => [s[1] for s in inst.slots], "y" => [s[2] for s in inst.slots],
        "kind" => [String(k) for k in inst.kinds], "class" => inst.class,
        "edges" => [[i, j] for (i, j) in inst.edges], "w" => inst.w)
    for c in choices
        lab, t = sq_teams(inst, c, seed)
        D["teams_" * c] = lab
    end
    D
end
out = Dict{String,Any}()
out["squads"] = dumpinst(squads_instance(1024, 1), ["aep", "classes"], 1)
out["natural"] = dumpinst(natural_instance(1024, 1), ["aep", "qs8", "classes"], 1)
open(joinpath(@__DIR__, "..", "..", "..", "results", "teams_map.json"), "w") do f
    JSON.print(f, out)
end
for k in ("squads", "natural")
    println(k, " n=", length(out[k]["x"]), " ", join(["$(c)=$(maximum(out[k][c]))" for c in keys(out[k]) if startswith(c, "teams_")], " "))
end
