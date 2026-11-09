# reference.jl: the high-accuracy reference solution of a QP, computed once
# and cached on disk by a hash of the problem data.
#
# Clarabel at tolerance 1e-11 (gap and feasibility, max 1000 iterations), and
# for problems without cones an active-set polish: the equality-constrained QP
# on the rows with nonzero multipliers is solved exactly (sparse LU of the KKT
# matrix, two steps of iterative refinement), rows the result violates are
# added, and the polished point is kept only if it is feasible to 1e-12
# (relative) and its objective is no worse than Clarabel's. The reference
# records which of the two it is and its own residuals.

using SHA, Serialization

const REF_TOL = 1e-11
const REF_DIR = Ref(joinpath(@__DIR__, "..", "data", "refcache"))

function qp_hash(p::QP)
    ctx = SHA.SHA1_CTX()
    for v in (p.P.colptr, p.P.rowval, p.P.nzval, p.q, p.A.colptr, p.A.rowval, p.A.nzval, p.l, p.u, p.socb)
        SHA.update!(ctx, reinterpret(UInt8, collect(v)))
    end
    SHA.update!(ctx, Vector{UInt8}(string([(first(B), last(B)) for B in p.socs])))
    return bytes2hex(SHA.digest!(ctx))
end

struct Reference
    x::Vector{Float64}
    y::Vector{Float64}
    obj0::Float64              # objective without the constant
    source::String             # "clarabel" or "clarabel+polish"
    status::String
    prim_rel::Float64
    dual_rel::Float64
    t::Float64
end

function _clarabel_ref(p::QP)
    d = clarabel_data(p)
    s = Clarabel.Solver()
    st = clarabel_settings(REF_TOL; max_iter = 1000)
    Clarabel.setup!(s, d.P, p.q, d.A, d.b, d.cones, st)
    r = Clarabel.solve!(s)
    return r.x, clarabel_y(d, r.z, ncons(p)), string(r.status)
end

function _polish(p::QP, x::Vector{Float64}, y::Vector{Float64})
    n = nvars(p); m = ncons(p)
    Ax = p.A * x
    scale = max(1.0, norm(y, Inf))
    act = Int[]; bnd = Float64[]
    for i in 1:m
        if p.l[i] == p.u[i]
            push!(act, i); push!(bnd, p.u[i])
        elseif y[i] > 1e-9 * scale
            push!(act, i); push!(bnd, p.u[i])
        elseif y[i] < -1e-9 * scale
            push!(act, i); push!(bnd, p.l[i])
        end
    end
    isact = falses(m); isact[act] .= true
    for _ in 1:5
        Aa = p.A[act, :]
        K = [p.P Aa'; Aa spzeros(length(act), length(act))]
        rhs = [-p.q; bnd]
        sol = try
            F = lu(K)
            z = F \ rhs
            for _ in 1:2
                z .+= F \ (rhs .- K * z)
            end
            z
        catch
            return nothing
        end
        xp = sol[1:n]
        any(!isfinite, xp) && return nothing
        Axp = p.A * xp
        viol = [i for i in 1:m if !isact[i] && (Axp[i] > p.u[i] + 1e-12 * max(1, abs(p.u[i])) ||
                                                  Axp[i] < p.l[i] - 1e-12 * max(1, abs(p.l[i])))]
        if isempty(viol)
            yp = zeros(m); yp[act] .= sol[n+1:end]
            return xp, yp
        end
        for i in viol
            push!(act, i); push!(bnd, Axp[i] > p.u[i] ? p.u[i] : p.l[i]); isact[i] = true
        end
    end
    return nothing
end

"""
    reference(p) -> Reference

Cached high-accuracy solution (see the file header).
"""
function reference(p::QP; cache = true)
    h = qp_hash(p)
    file = joinpath(REF_DIR[], h * ".jls")
    if cache && isfile(file)
        r = try
            deserialize(file)::Reference
        catch
            nothing                       # being written by another job: compute it here
        end
        r === nothing || return r
    end
    t = @elapsed begin
        x, y, status = _clarabel_ref(p)
        f0 = objective0(p, x)
        src = "clarabel"
        if !has_soc(p)
            pol = _polish(p, x, y)
            if pol !== nothing
                xp, yp = pol
                cp = check(p, xp, yp, f0)
                fp = objective0(p, xp)
                if cp.prim_rel <= 1e-12 && fp <= f0 + 1e-13 * max(1.0, abs(f0))
                    x, y, f0, src = xp, yp, fp, "clarabel+polish"
                end
            end
        end
    end
    c = check(p, x, y, f0)
    r = Reference(x, y, f0, src, status, c.prim_rel, c.dual_rel, t)
    if cache
        mkpath(REF_DIR[])
        tmp = file * ".tmp$(getpid())"
        serialize(tmp, r)
        mv(tmp, file; force = true)       # atomic on one file system: concurrent jobs never read a partial file
    end
    return r
end
