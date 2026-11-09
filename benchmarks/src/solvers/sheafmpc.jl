# sheafmpc.jl: the adapter for the package under test. This is the ONLY file
# of the harness that touches SheafMPC's API; if the API changes, adapt here.
#
# API used: ConicQP(P, q, A, l, u; c, socs, socb, kinds), setup(qp; kwargs...),
# solve!(s) -> Info, update!(s; q, l, u, b[, c]), warm_start!(s; x, y), s.xsol,
# s.ysol, Info fields status, iter, solve_time, polish.

import SheafMPC

const SHEAFMPC_DIR = normpath(joinpath(pkgdir(SheafMPC)))
# newer versions take the objective constant in update! (receding horizon: c changes with x0)
const SHEAFMPC_UPDATE_C = any(m -> :c in Base.kwarg_decl(m), methods(SheafMPC.update!))

mutable struct SheafMPCHandle
    s::Any
    hassoc::Bool
    eqrows::BitVector
    b::Vector{Float64}
end

function sheafmpc_conic(p::QP)
    m = ncons(p); soc = issocrow(p)
    kinds = fill(SheafMPC.ROW_INTERVAL, m)
    for i in 1:m
        soc[i] && continue
        p.l[i] == p.u[i] && (kinds[i] = SheafMPC.ROW_EQ)
    end
    return SheafMPC.ConicQP(p.P, p.q, p.A, p.l, p.u; c = p.c, socs = copy(p.socs), socb = copy(p.socb), kinds = kinds)
end

function sheafmpc_spec(; time_limit = Inf, max_iter = 100_000)
    setup = function (p::QP, eps, v)
        cq = sheafmpc_conic(p)
        kw = Dict{Symbol,Any}(Symbol(k) => val for (k, val) in v if k != "label")
        s = SheafMPC.setup(cq; eps_abs = eps, eps_rel = eps, max_iter = max_iter, time_limit = time_limit, kw...)
        soc = issocrow(p)
        eqr = BitVector([!soc[i] && p.l[i] == p.u[i] for i in 1:ncons(p)])
        return SheafMPCHandle(s, has_soc(p), eqr, zeros(ncons(p)))
    end
    solve! = function (h::SheafMPCHandle)
        info = SheafMPC.solve!(h.s)
        st = info.status == :solved ? :solved : info.status
        return SolveResult(copy(h.s.xsol), copy(h.s.ysol), st, info.iter, info.solve_time)
    end
    update! = function (h::SheafMPCHandle, p::QP)
        if !h.hassoc
            SHEAFMPC_UPDATE_C ? SheafMPC.update!(h.s; q = p.q, l = p.l, u = p.u, c = p.c) :
                                SheafMPC.update!(h.s; q = p.q, l = p.l, u = p.u)
        else
            # the right-hand side form: b = u on equality rows, socb on cone rows (the
            # package rejects b on interval rows, so mixed problems are not updatable)
            all(h.eqrows .| issocrow(p)) || error("sheafmpc: no in-place update for cones mixed with interval rows")
            for i in eachindex(h.b)
                h.b[i] = h.eqrows[i] ? p.u[i] : p.socb[i]
            end
            SHEAFMPC_UPDATE_C ? SheafMPC.update!(h.s; q = p.q, b = h.b, c = p.c) : SheafMPC.update!(h.s; q = p.q, b = h.b)
        end
        return nothing
    end
    warm! = function (h::SheafMPCHandle, x, y)
        SheafMPC.warm_start!(h.s; x = x, y = y)
        return nothing
    end
    info = () -> Dict{String,Any}("package" => "SheafMPC", "path" => SHEAFMPC_DIR, "git" => git_state(SHEAFMPC_DIR),
                                  "settings" => "package defaults (SheafMPC.Settings()), eps_abs = eps_rel = eps, max_iter $max_iter",
                                  "warm_start" => "update! (factorization kept" * (SHEAFMPC_UPDATE_C ? ", objective constant c passed" : "") * ") + warm_start!(x, y) from the shifted previous solution")
    readback = function (h::SheafMPCHandle)
        st = h.s.settings
        d = Dict{String,Any}(string(f) => getfield(st, f) for f in fieldnames(typeof(st)))
        d["tols"] = Dict("eps_abs" => st.eps_abs, "eps_rel" => st.eps_rel)
        d["has_iterate"] = h.s.has_iterate
        d["expect"] = Dict("has_iterate" => false)
        return d
    end
    return SolverSpec(name = "sheafmpc", readback = readback, kind = :admm, applicable = p -> true,
                      variants = [Dict{String,Any}("label" => "default")],
                      setup = setup, solve! = solve!, update! = update!, warm! = warm!, info = info)
end
