# osqp.jl: OSQP.jl (the C library OSQP 0.6.x through OSQP_jll) adapter.
# Not applicable to problems with second-order cones.

import OSQP

mutable struct OSQPHandle
    m::OSQP.Model
    res::OSQP.Results
end

function osqp_spec(; time_limit = 0.0, max_iter = 400_000)
    setup = function (p::QP, eps, v)
        m = OSQP.Model()
        OSQP.setup!(m; P = SpMat(triu(p.P)), q = p.q, A = p.A, l = p.l, u = p.u, verbose = false,
                    eps_abs = eps, eps_rel = eps, eps_prim_inf = 1e-6, eps_dual_inf = 1e-6,
                    polish = v["polish"], polish_refine_iter = 3, max_iter = max_iter, adaptive_rho = true,
                    warm_start = true, time_limit = time_limit)
        return OSQPHandle(m, OSQP.Results())
    end
    solve! = function (h::OSQPHandle)
        OSQP.solve!(h.m, h.res)
        r = h.res
        st = r.info.status == :Solved ? :solved : r.info.status == :Max_iter_reached ? :max_iter :
             r.info.status == :Solved_inaccurate ? :inaccurate : r.info.status == :Time_limit_reached ? :time_limit :
             Symbol(lowercase(string(r.info.status)))
        return SolveResult(copy(r.x), copy(r.y), st, r.info.iter, r.info.solve_time + r.info.polish_time)
    end
    update! = function (h::OSQPHandle, p::QP)
        OSQP.update!(h.m; q = p.q, l = p.l, u = p.u)
        return nothing
    end
    warm! = function (h::OSQPHandle, x, y)
        OSQP.warm_start!(h.m; x = x, y = y)
        return nothing
    end
    info = () -> Dict{String,Any}("package" => "OSQP.jl", "version" => string(pkgversion(OSQP)),
                                  "library" => unsafe_string(ccall((:osqp_version, OSQP.osqp), Cstring, ())),
                                  "settings" => "eps_abs = eps_rel = eps, adaptive_rho on (OSQP default interval), polish per variant with 3 refinement steps, max_iter $max_iter, scaling 10 (default)",
                                  "warm_start" => "update! (factorization kept) + warm_start!(x, y) from the shifted previous solution")
    return SolverSpec(name = "osqp", kind = :admm, applicable = p -> !has_soc(p),
                      variants = [Dict{String,Any}("polish" => true), Dict{String,Any}("polish" => false)],
                      setup = setup, solve! = solve!, update! = update!, warm! = warm!, info = info)
end
