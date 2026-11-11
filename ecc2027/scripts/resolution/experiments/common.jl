# Shared helpers of the experiments: loading the library, relative errors,
# instance populations, and writing results/*.json.

if !isdefined(Main, :Resolution)
    include(joinpath(@__DIR__, "..", "src", "Resolution.jl"))
end
using .Resolution
using LinearAlgebra, SparseArrays, Random, Printf, Statistics
import JSON
import Clarabel

const RESULTS_DIR = normpath(joinpath(@__DIR__, "..", "..", "..", "results"))

"""`|a - b| / max(|a|, |b|)` (0 when both are zero or both are +Inf)."""
function relerr(a::Real, b::Real)
    (isinf(a) && isinf(b) && sign(a) == sign(b)) && return 0.0
    d = max(abs(a), abs(b))
    return d == 0 ? 0.0 : abs(a - b) / d
end

"""`||a - b|| / max(||a||, ||b||)`."""
function relnorm(a::AbstractVector, b::AbstractVector)
    d = max(norm(a), norm(b))
    return d == 0 ? 0.0 : norm(a - b) / d
end

"""Make a value JSON-safe: non-finite floats become the strings "Inf", "-Inf", "NaN"."""
jsonable(x::AbstractFloat) = isfinite(x) ? Float64(x) : (isnan(x) ? "NaN" : (x > 0 ? "Inf" : "-Inf"))
jsonable(x::Integer) = x
jsonable(x::Bool) = x
jsonable(x::Symbol) = string(x)
jsonable(x::AbstractString) = String(x)
jsonable(::Nothing) = nothing
jsonable(x::AbstractDict) = Dict{String,Any}(string(k) => jsonable(v) for (k, v) in x)
jsonable(x::NamedTuple) = Dict{String,Any}(string(k) => jsonable(v) for (k, v) in pairs(x))
jsonable(x::Tuple) = [jsonable(v) for v in x]
jsonable(x::AbstractMatrix) = [jsonable(x[i, :]) for i in 1:size(x, 1)]     # a list of rows
jsonable(x::AbstractArray) = [jsonable(v) for v in x]
jsonable(x) = string(x)

"""Solver and environment metadata recorded with every result."""
function run_metadata(opts::SolverOptions)
    return Dict{String,Any}(
        "julia" => string(VERSION),
        "clarabel" => string(pkgversion(Clarabel)),
        "solver" => Dict("tol_gap_abs" => opts.tol, "tol_gap_rel" => opts.tol, "tol_feas" => opts.tol,
                         "tol_infeas" => opts.infeas_tol, "tol_ktratio" => opts.ktratio,
                         "max_iter" => opts.max_iter, "presolve" => opts.presolve,
                         "active_set_polish" => opts.polish),
        "threads" => Threads.nthreads(),
    )
end

function write_results(name::AbstractString, d::AbstractDict)
    mkpath(RESULTS_DIR)
    path = joinpath(RESULTS_DIR, name * ".json")
    open(path, "w") do io
        JSON.json(io, jsonable(d); pretty = 2)
    end
    println("wrote ", path)
    return path
end

"""A claim record: label, pass flag, criterion text, population size and worst values."""
claim(label, passed, criterion, population; kwargs...) =
    Dict{String,Any}("label" => label, "passed" => passed, "criterion" => criterion,
                     "population" => population, "worst" => Dict{String,Any}(string(k) => v for (k, v) in kwargs))

"""Solution summary for the JSON records."""
solstat(s::DirectSolution) = Dict{String,Any}(
    "status" => s.status, "J" => s.J, "iterations" => s.iterations, "solve_time" => s.solve_time,
    "gap_rel" => s.gap_rel, "polished" => s.polished, "kkt_ipm" => s.kkt_ipm, "kkt" => s.kkt,
    "hard_residual" => s.feas.hard, "cone_violation" => s.feas.cone)

"""True when every collapsed edge of `Pi` is hard in `P` (an exact resolution)."""
is_exact(P::GraphProgram, Pi) = all(e -> P.edges[e].hard, collapsed_edges(P, Pi))

"""Maximum over a possibly empty collection (0 when empty)."""
maxor0(xs) = isempty(xs) ? 0.0 : maximum(xs)

nfinite(xs) = count(isfinite, xs)
