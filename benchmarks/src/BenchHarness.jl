"""
    BenchHarness

The benchmark harness that referees TeamMPC against the state of the art:
problem families with deterministic closed-loop QP sequences, a cached
high-accuracy reference per QP, one shared accuracy checker, solver adapters
behind one interface, and the timing protocol (protocol.jl).
"""
module BenchHarness

using LinearAlgebra, SparseArrays, Printf, Statistics, Random, Libdl
import JSON, SHA

include("qp.jl")
include("solvers/interface.jl")
include("meta.jl")
include("solvers/clarabel.jl")
include("reference.jl")
include("families/stage.jl")
include("families/fleet.jl")
include("families/mpc.jl")
include("families/registry.jl")
include("protocol.jl")
include("solvers/teammpc.jl")
include("solvers/osqp.jl")
include("solvers/mumblebee.jl")
(isfile(joinpath(@__DIR__, "solvers", "hpipm.jl")) && get(ENV, "BENCH_SKIP_HPIPM", "") == "") && include("solvers/hpipm.jl")
isfile(joinpath(@__DIR__, "solvers", "piqp.jl")) && include("solvers/piqp.jl")

end
