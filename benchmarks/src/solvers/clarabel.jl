# clarabel.jl: Clarabel.jl (interior point, conic) adapter, and the conversion
# of a canonical QP to Clarabel's form  b - A x in K  that the reference uses.
#
# Rows: equality rows (zero cone), then upper rows u - a'x >= 0 and lower rows
# a'x - l >= 0 (one nonnegative cone), then every SOC block. Multipliers map
# back to the canonical convention P x + q + A'y = 0: y_i = z for equality and
# upper rows, y_i = -z for lower rows, y_B = z_B on cone blocks.

import Clarabel

struct ClarabelData
    P::SpMat               # upper triangle
    A::SpMat
    b::Vector{Float64}
    cones::Vector{Clarabel.SupportedCone}
    rows::Vector{Int}      # canonical row of every Clarabel row
    sgn::Vector{Float64}   # its sign
    eq::Vector{Int}; ub::Vector{Int}; lb::Vector{Int}
end

function clarabel_data(p::QP)
    m = ncons(p)
    soc = issocrow(p)
    eq = [i for i in 1:m if !soc[i] && p.l[i] == p.u[i]]
    ub = [i for i in 1:m if !soc[i] && p.l[i] != p.u[i] && isfinite(p.u[i])]
    lb = [i for i in 1:m if !soc[i] && p.l[i] != p.u[i] && isfinite(p.l[i])]
    rows = Int[]; sgn = Float64[]; b = Float64[]; cones = Clarabel.SupportedCone[]
    if !isempty(eq)
        append!(rows, eq); append!(sgn, ones(length(eq))); append!(b, p.u[eq]); push!(cones, Clarabel.ZeroConeT(length(eq)))
    end
    if !isempty(ub) || !isempty(lb)
        append!(rows, ub); append!(sgn, ones(length(ub))); append!(b, p.u[ub])
        append!(rows, lb); append!(sgn, -ones(length(lb))); append!(b, -p.l[lb])
        push!(cones, Clarabel.NonnegativeConeT(length(ub) + length(lb)))
    end
    for B in p.socs
        append!(rows, B); append!(sgn, ones(length(B))); append!(b, p.socb[B]); push!(cones, Clarabel.SecondOrderConeT(length(B)))
    end
    A = SpMat(Diagonal(sgn) * p.A[rows, :])
    return ClarabelData(SpMat(triu(p.P)), A, b, cones, rows, sgn, eq, ub, lb)
end

"New right-hand side b of the Clarabel form for a QP with the same structure."
function clarabel_rhs!(b::Vector{Float64}, d::ClarabelData, p::QP)
    r = 0
    for i in d.eq; r += 1; b[r] = p.u[i]; end
    for i in d.ub; r += 1; b[r] = p.u[i]; end
    for i in d.lb; r += 1; b[r] = -p.l[i]; end
    for B in p.socs, i in B; r += 1; b[r] = p.socb[i]; end
    return b
end

function clarabel_y(d::ClarabelData, z::AbstractVector, m::Int)
    y = zeros(m)
    for (k, i) in enumerate(d.rows)
        y[i] += d.sgn[k] * z[k]
    end
    return y
end

function clarabel_settings(eps; direct = :qdldl, max_iter = 500, time_limit = Inf, static_reg = true)
    return Clarabel.Settings(verbose = false, tol_gap_abs = eps, tol_gap_rel = eps, tol_feas = eps,
                             tol_ktratio = min(1e-6, eps), max_iter = max_iter, time_limit = time_limit,
                             presolve_enable = false, direct_solve_method = direct,
                             static_regularization_enable = static_reg)
end

const CLARABEL_STATUS = Dict("SOLVED" => :solved, "ALMOST_SOLVED" => :almost_solved, "MAX_ITERATIONS" => :max_iter,
                             "MAX_TIME" => :time_limit, "PRIMAL_INFEASIBLE" => :infeasible,
                             "DUAL_INFEASIBLE" => :infeasible)

mutable struct ClarabelHandle
    s::Clarabel.Solver{Float64}
    d::ClarabelData
    m::Int
    b::Vector{Float64}
    pending_q::Union{Nothing,Vector{Float64}}
end

function clarabel_spec(; time_limit = Inf)
    setup = function (p::QP, eps, v)
        d = clarabel_data(p)
        s = Clarabel.Solver()
        Clarabel.setup!(s, d.P, p.q, d.A, d.b, d.cones,
                        clarabel_settings(eps; direct = Symbol(v["direct"]), time_limit = time_limit))
        return ClarabelHandle(s, d, ncons(p), copy(d.b), nothing)
    end
    solve! = function (h::ClarabelHandle)
        r = Clarabel.solve!(h.s)
        st = get(CLARABEL_STATUS, string(r.status), :failed)
        return SolveResult(r.x, clarabel_y(h.d, r.z, h.m), st, r.iterations, r.solve_time)
    end
    update! = function (h::ClarabelHandle, p::QP)
        # Clarabel's data updates keep the symbolic factorization (presolve is off)
        Clarabel.update_q!(h.s, p.q)
        Clarabel.update_b!(h.s, clarabel_rhs!(h.b, h.d, p))
        return nothing
    end
    info = () -> Dict{String,Any}("package" => "Clarabel.jl", "version" => string(pkgversion(Clarabel)),
                                  "settings" => "tol_gap_abs = tol_gap_rel = tol_feas = eps, tol_ktratio = min(1e-6, eps), presolve off, equilibration on (default), max_iter 500",
                                  "warm_start" => "none (interior point); sequence mode reuses the setup through update_q!/update_b!")
    return SolverSpec(name = "clarabel", kind = :ipm, applicable = p -> true,
                      variants = [Dict{String,Any}("direct" => "qdldl"), Dict{String,Any}("direct" => "cholmod")],
                      setup = setup, solve! = solve!, update! = update!, warm! = nothing, info = info)
end
