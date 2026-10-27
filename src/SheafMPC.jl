"""
    SheafMPC

Multi-agent model predictive control as a homological program on a cellular
sheaf over the time-expanded graph, its reduced-order models and condensations
by sheaf pushforward, and certificates of their optimality gap; the companion
of "Reduced-Order Models and Condensation of Multi-Agent MPC by Sheaf
Pushforward".

* Modelling: `Agent`, `Fleet`, `FleetProgram` (formation edges soft, dynamics
  edges hard, the initial state pinned).
* Reductions: `TimeBlocking` (condensing, exact), `Teams` (agreement
  subspaces), products `teams ⊠ blocking`, `Mixed` resolutions;
  `reduce(program, resolution)` is the pushforward, `lift` maps reduced plans
  back, and reductions compose (teams of teams); `StepOperator` precomposes a
  chain's map from the changing data to the reduced QP vectors.
* Certificates: `gap_bounds` (from the reduced solve, and the fine one when
  available), `gap_kernel`, `gap` and `select_teams`.
* Receding horizon: `MPCController` and `step!`; `DistributedMPC`, consensus
  ADMM over agents or teams.
* The solver: an operator-splitting (ADMM) conic QP solver for sheaf programs
  (OSQP's algorithm with second-order cones, a quasi-definite KKT matrix
  factored once, an active-set and semismooth Newton polish, a duality gap
  test), with `update!` and warm starts that keep every factorization, and a
  primal-dual interior-point method (Mehrotra, Nesterov-Todd scaling,
  homogeneous embedding) on the same KKT pattern, chosen automatically or by
  crossover (`method`).
"""
module SheafMPC

using LinearAlgebra
using SparseArrays
using Printf
using Random
import QDLDL
using CliqueTrees
using CliqueTrees.Multifrontal: Multifrontal

include("problem.jl")
include("sheaf.jl")
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

# the conic QP solver
export ConicQP, RowKind, ROW_INTERVAL, ROW_EQ, ROW_LEQ, ROW_SOC
export nvars, nrows, objective, violation, sheaf_qp, dedup_rows
export Settings, Info, Solver, setup, solve!, update!, warm_start!, warm_start_shifted!, solution, reset!
# programs
export ConeKind, ZERO_CONE, NONNEG_CONE, SOC_CONE, ConeBlock, zero_cone, nonneg_cone, soc_cone
export NodeData, EdgeTag, SheafEdge, SheafProgram
export nvertices, nedges, c0dim, c1dim, vrange, erange, edgedim, hard_edges, soft_edges
export coboundary, targets, quadratic_form, node_constraints, feasibility, harden, edge_defect
# fleets
export Agent, BallSet, BoxSet, Polyhedron, Fleet, FleetProgram, nagents
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

end
