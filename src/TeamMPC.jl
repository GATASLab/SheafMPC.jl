"""
    TeamMPC

Multi-agent model predictive control as a convex program on the time-expanded
graph, its reduced-order models and condensations along graph quotients, and
certificates of their optimality gap; the companion of "Exact and Certified
Team Reduction for Large-Fleet Formation MPC".

* Team MPC (the paper's Algorithm 1): `lossless_teams`, `quasi_stable_teams`,
  `TeamController` (quotient program, projection, broadcast, local feedback), and the
  per-team certificate of Thm. 2 (`certificate`, `team_certificate`).

* Modelling: `Agent`, `Fleet`, `FleetProgram` (formation edges soft, dynamics
  edges hard, the initial state pinned).
* Reductions: `TimeBlocking` (condensing, exact), `Teams` (agreement
  subspaces), products `teams ⊠ blocking`, `Mixed` resolutions;
  `reduce(program, resolution)` is the reduction, `lift` maps reduced plans
  back, and reductions compose (teams of teams); `StepOperator` precomposes a
  chain's map from the changing data to the reduced QP vectors.
* Certificates: `gap_bounds` (from the reduced solve, and the fine one when
  available), `gap_kernel`, `gap` and `select_teams`.
* Receding horizon: `MPCController` and `step!`; `DistributedMPC`, consensus
  ADMM over agents or teams.
* The solver: an operator-splitting (ADMM) conic QP solver for graph programs
  (OSQP's algorithm with second-order cones, a quasi-definite KKT matrix
  factored once, an active-set and semismooth Newton polish, a duality gap
  test), with `update!` and warm starts that keep every factorization, and a
  primal-dual interior-point method (Mehrotra, Nesterov-Todd scaling,
  homogeneous embedding) on the same KKT pattern, chosen automatically or by
  crossover (`method`).
"""
module TeamMPC

using LinearAlgebra
using SparseArrays
using Printf
using Random
import QDLDL
using CliqueTrees
using CliqueTrees.Multifrontal: Multifrontal

include("problem.jl")
include("graph.jl")
include("cones.jl")
include("scaling.jl")
include("kkt/BlockLDL.jl")
include("linsys.jl")
include("kkt/system.jl")
include("settings.jl")
include("anderson.jl")
include("termination.jl")
include("ipm.jl")
include("solver.jl")
include("polish.jl")
include("dual.jl")
include("rho.jl")
include("method.jl")

include("program.jl")
include("fiber.jl")
include("resolutions.jl")
include("reduce.jl")
include("qpmap.jl")
include("stepop.jl")
include("fleet.jl")
include("scenarios.jl")
include("certificates.jl")
include("controller.jl")
include("distributed.jl")
include("teammpc.jl")
include("teams.jl")
include("teamcert.jl")

# the conic QP solver (row kinds, `dedup_rows` and `soc_twins` are internal: `TeamMPC.ROW_SOC`, ...)
export ConicQP
export nvars, nrows, objective, violation, graph_qp
export Settings, Info, Solver, setup, solve!, update!, warm_start!, warm_start_shifted!, solution, reset!
# programs
export ConeKind, ZERO_CONE, NONNEG_CONE, SOC_CONE, ConeBlock, zero_cone, nonneg_cone, soc_cone
export NodeData, EdgeTag, GraphEdge, GraphProgram
export nvertices, nedges, c0dim, c1dim, vrange, erange, edgedim, hard_edges, soft_edges
export edge_operator, targets, quadratic_form, node_constraints, feasibility, harden, edge_defect
# fleets
export Agent, BallSet, BoxSet, Polyhedron, Fleet, FleetProgram, nagents, edge_maps, edge_residual
export set_state!, set_references!, set_targets!, set_drift!, set_state_bound!, set_state_set!, set_state_sets!
export trajectories, first_inputs, plant_step, shift_plan, shift_plan!, free_response!
export quadrotor, ground_vehicle, grid_graph, GridScenario, fleet, slots, references, formation_start
export agent_kind, row_teams, strip_teams, block_teams
# resolutions and reductions
export FleetLayout, Resolution, Fine, TimeBlocking, full_condensing, partial_condensing, Teams, Product, ⊠
export Mixed, VertexPartition, canonical_partition, colour_refinement, is_almost_equitable
export ReducedProgram, Fiber, fiberdim, lift, lift!, restrict, restrict!, update_matrices!, reduction_chain, root_program, composite_partition, fiber_kinds
export QPMap, refresh!, refresh_matrices!, ProgramSolution, solve, isoptimal
export StepOperator, data_index, sync!
# certificates
export gap_bounds, gap_lower_bound, Certifier, certify!, multipliers
export GapKernel, gap_kernel, gap, team_front, select_teams
# receding horizon
export MPCController, StepInfo, step!, plan, reduced_program
# distributed MPC
export DistributedMPC, floats_per_iteration
# team MPC (Algorithm 1)
export TeamController, QuotientFleet, slot_offsets, same_data, lqr_gain, project, teams, stepinfo
export data_classes, lossless_teams, quasi_stable_teams, team_spread
export CondensedQP, stack_inputs, team_certificate, team_kappa, team_plan, certificate

end
