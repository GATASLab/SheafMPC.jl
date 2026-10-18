"""
    SheafMPC

An operator-splitting (ADMM) solver for convex conic QPs, aimed at sheaf
programs and multi-agent model predictive control: OSQP's algorithm
(Stellato et al. 2020) with second-order cones (as in COSMO), a quasi-definite
KKT matrix factored once by a sparse LDLt (QDLDL or CliqueTrees'
supernodal multifrontal LDLt), adaptive rho, Ruiz scaling, infeasibility
detection, and an active-set polish that reuses the symbolic factorization.
For receding horizon, `update!` and `warm_start!` keep every factorization.
"""
module SheafMPC

using LinearAlgebra
using SparseArrays
using Printf
import QDLDL
using CliqueTrees
using CliqueTrees.Multifrontal: Multifrontal

include("problem.jl")
include("sheaf.jl")
include("cones.jl")
include("scaling.jl")
include("linsys.jl")
include("settings.jl")
include("solver.jl")
include("polish.jl")

export ConicQP, RowKind, ROW_INTERVAL, ROW_EQ, ROW_LEQ, ROW_SOC
export nvars, nrows, objective, violation, sheaf_qp
export Settings, Info, Solver, setup, solve!, update!, warm_start!, warm_start_shifted!, solution, reset!

end
