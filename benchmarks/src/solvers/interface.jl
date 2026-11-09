# interface.jl: what every solver adapter provides.
#
# A solver is a `SolverSpec` of plain functions. The harness, never the
# adapter, owns the clock: it times `solve!` (cold mode) and `update!` +
# `warm!` + `solve!` together (warm sequence mode) with one wall clock around
# the call boundary; `setup` is timed separately. Adapters must not print,
# must not allocate problem data inside `solve!` beyond what the solver itself
# does, and must return the solution in the canonical variables of `QP`.
#
#   applicable(qp)            -> Bool    (e.g. HPIPM needs qp.stage, no SOC)
#   variants                  :: Vector{Dict{String,Any}}  configurations the
#                                calibration chooses among (fastest that meets
#                                the accuracy tier on the calibration QP)
#   setup(qp, eps, variant)   -> handle  (scaling, ordering, symbolic and
#                                numeric factorization, workspace)
#   solve!(handle)            -> SolveResult, from the handle's current start
#                                (zero after setup: a cold start)
#   update!(handle, qp)       -> nothing; new vector data (q, l, u, socb, or the
#                                stage vectors) of a QP with the same structure
#   warm!(handle, x, y)       -> nothing; start the next solve from (x, y) in
#                                canonical variables; `nothing` if the solver
#                                has no primal-dual warm start (interior point)
#   info()                    -> Dict of version, commit, library path, fixed
#                                settings
#   readback(handle)          -> Dict read back from the live solver object
#                                after setup (not what we passed: what the
#                                solver holds), with "tols" => Dict of every
#                                termination tolerance, which the protocol
#                                checks against the requested one; a keyword
#                                API that drops unknown options is caught here

struct SolveResult
    x::Vector{Float64}
    y::Union{Nothing,Vector{Float64}}   # canonical multipliers (see qp.jl), or nothing
    status::Symbol                      # :solved, :max_iter, :time_limit, :infeasible, :failed, ...
    iters::Int
    t_internal::Float64                 # the solver's own timer of the solve, NaN if none
end

Base.@kwdef struct SolverSpec
    name::String
    kind::Symbol                         # :admm, :ipm
    applicable::Function
    variants::Vector{Dict{String,Any}}
    setup::Function
    solve!::Function
    update!::Function
    warm!::Union{Nothing,Function} = nothing
    info::Function = () -> Dict{String,Any}()
    readback::Function = h -> Dict{String,Any}()
    # warm-mode strategies (merged into the variant at setup); the protocol runs
    # each and keeps the one with the fewest failures, then the fastest
    seq_variants::Vector{Dict{String,Any}} = [Dict{String,Any}()]
end

failed_result(n) = SolveResult(fill(NaN, n), nothing, :failed, 0, NaN)
