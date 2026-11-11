# dump_overview.jl: a small planted fleet and its coarsest lossless teams, for the overview figure
# (render/fig_overview.py). No MPC solves.
#   julia --project=env scripts/resolution/experiments/dump_overview.jl  -> results/overview_fleet.json
include(joinpath(@__DIR__, "e30_bounds_dc.jl"))
include(joinpath(@__DIR__, "squads_dc.jl"))
using JSON
out = Dict{String,Any}()
for (n, seed) in ((56, 4), (64, 2))
    inst = squads_instance(n, seed)
    lab, _ = sq_teams(inst, "aep", seed)
    out["n$(n)_s$(seed)"] = Dict("x" => [s[1] for s in inst.slots], "y" => [s[2] for s in inst.slots],
        "kind" => [String(k) for k in inst.kinds], "edges" => [[i, j] for (i, j) in inst.edges], "w" => inst.w,
        "teams" => lab)
end
open(joinpath(@__DIR__, "..", "..", "..", "results", "overview_fleet.json"), "w") do f
    JSON.print(f, out)
end
