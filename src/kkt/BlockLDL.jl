"""
    BlockLDL

A block-supernodal multifrontal LDLt for quasi-definite KKT matrices

    K = [ P + sigma I    A'   ]
        [ A           -R^{-1} ]

with structure-aware elimination orders. Quasi-definite matrices are strongly
factorizable: every symmetric permutation has an LDLt factorization with
pivots of known sign (Vanderbei 1995), so the factorization needs no pivoting
and the symbolic analysis (ordering, elimination tree, supernodes, assembly
and extend-add maps, memory layout) is done once; a new rho or sigma only
refactors numerically. Pieces:

* `symbolic.jl`  elimination tree, postorder, column counts, relaxed
  supernodes, extend-add maps, storage layout;
* `orderings.jl` fill-reducing orders: generic (AMD, CliqueTrees' AMF/MMD,
  METIS when loaded) and structure-given ones for time-expanded multi-agent
  programs (time-major Riccati-like, agent-major nested dissection of the
  agent graph), chosen by a cost model on the symbolic counts;
* `dense.jl`     dense LDLt of a frontal panel and the Schur update, loops for
  small blocks and BLAS-3 (through libblastrampoline, on pointers) for large;
* `numeric.jl`   the multifrontal factorization;
* `solve.jl`     allocation-free triangular solves with the diagonal fused;
* `parallel.jl`  factorization and solves over independent subtrees;
* `lowrank.jl`   rank-k updates of the factor when a few rho change.
"""
module BlockLDL

using LinearAlgebra
using LinearAlgebra: BLAS
using SparseArrays
import CliqueTrees
import QDLDL

include("symbolic.jl")
include("dense.jl")
include("numeric.jl")
include("solve.jl")
include("parallel.jl")
include("orderings.jl")
include("lowrank.jl")

end
