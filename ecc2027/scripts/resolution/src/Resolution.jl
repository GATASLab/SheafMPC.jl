"""
    Resolution

Graph programs, their reduction along any vertex partition with an
orthonormal fibre basis, multi-agent MPC as a graph program on the
time-expanded graph `G box P_H`, and a direct conic solver (Clarabel) that
returns primal solutions and the multipliers of every hard row.

Layout: `program.jl` (Def 2.1, 2.2), `reduction.jl` (Def 1.3, 2.3, 3.1),
`mpc_model.jl` (Def 4.1 and the resolutions of `G box P_H`), `direct.jl`
(solves), `analysis.jl` (the quantities the checks compare), and, when present,
`algorithms.jl` (iterative solvers, added later).
"""
module Resolution

using LinearAlgebra
using SparseArrays
using Random
using Printf
using Statistics: median
import Clarabel

include("program.jl")
include("reduction.jl")
include("mpc_model.jl")
include("direct.jl")
include("analysis.jl")

# program
export ConeKind, ZERO_CONE, NONNEG_CONE, SOC_CONE, ConeBlock, zero_cone, nonneg_cone, soc_cone
export NodeData, EdgeTag, GraphEdge, GraphProgram
export nvertices, nedges, c0dim, c1dim, vrange, erange, hard_edges, soft_edges, edgedim, edgedims
export edge_value, edge_defect, edge_operator, targets, weight_matrix, quadratic_form, objective
export node_constraints, node_equalities, feasibility, harden, reweight, reverse_edge, merge_parallel_edges
# reduction
export canonical_partition, nblocks, block_members, is_refinement, partition_meet, partition_join
export induced_partition, pullback_partition, collapsed_edges, blocks_connected
export random_contraction, random_coarsening, random_maximal_chain
export FibreBlock, ResolutionLift, AffineLift, lift, restrict, compose, coarsen, coarsen_two_step
export fibre_dims, rref_nullspace
# MPC
export AgentModel, quad_agent, rover_agent, agent_graph, MPCSpec, MPCConfig, mpc_spec, MPCModel
export build_model, build_mpc, with_absent_encoding, with_typing, config_dict
export nverts, vertex_coordinates, product_partition, time_leg, agent_leg, corner_partition, bottom_partition
export random_time_blocking, random_agent_clustering, virtual_base_partition, implementable
export condensing_matrices, condensed_qp, virtual_structure_qp
# direct
export SolverOptions, DEFAULT_SOLVER, QPResult, solve_qp, DirectSolution, isoptimal, isinfeasible
export solve_direct, solve_hardened, price_upper_bound, price_lower_bound
# analysis
export nullbasis, rangebasis, numerical_rank, cost_factor, kappa_factor, reduced_hessian, spectrum, strong_convexity, gd_iterations
export reduced_problem, active_set, sensitivity_basis, price_sensitivity, sensitivity_report, local_multipliers

# algorithms (phase 2)
export IterativeResult, graph_diffusion, graph_admm, direct_timing, power_iteration
export floats_per_iteration, rods_between_vertices

isfile(joinpath(@__DIR__, "algorithms.jl")) && include("algorithms.jl")

end # module
