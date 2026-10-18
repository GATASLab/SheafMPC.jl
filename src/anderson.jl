# anderson.jl: safeguarded type-II Anderson acceleration of the ADMM fixed-point
# map (Walker and Ni 2011; for operator splitting: Zhang, O'Donoghue and Boyd
# 2020 (SCS 3), Garstka, Cannon and Goulart 2021 (COSMO)).
#
# One ADMM iteration is a map T of w = (x, v), v = z + R^{-1} y: the pair
# (z, y) is the Moreau decomposition of v, z = Proj_C(v), y = R (v - z), so v
# carries both. With the residual g(w) = T(w) - w and the last `mem`
# differences dG = [g_{i+1} - g_i], dF = [T(w_{i+1}) - T(w_i)], the
# accelerated point is
#
#     w+ = T(w) - dF gamma,   gamma = argmin || g(w) - dG gamma ||_2,
#
# (a least-squares problem of `mem` unknowns, solved from the Gram matrix
# dG'dG kept up to date column by column, with a small Tikhonov term). The
# safeguard: an accelerated point whose residual exceeds `safeguard` times the
# residual it was computed from is rejected, the iterate falls back to T(w),
# and the memory is cleared. The memory is also cleared when rho changes (the
# map changes) and after a polish restart.

mutable struct Anderson
    mem::Int
    dim::Int
    ncol::Int                 # stored columns (<= mem)
    head::Int                 # column of the newest difference
    dG::Matrix{Float64}
    dF::Matrix{Float64}
    gram::Matrix{Float64}     # dG' dG
    Gg::Vector{Float64}       # dG' g (current g)
    w::Vector{Float64}        # point at which T was evaluated
    f::Vector{Float64}        # T(w)
    g::Vector{Float64}
    fprev::Vector{Float64}
    gprev::Vector{Float64}
    has_prev::Bool
    gnorm_ref::Float64        # residual norm the pending accelerated point was computed from
    pending::Bool             # the current iterate is an accelerated point
    M::Matrix{Float64}        # workspace for the small solve
    gamma::Vector{Float64}
    accepted::Int
    rejected::Int
end

function Anderson(mem::Int, dim::Int)
    mem = max(mem, 1)
    return Anderson(mem, dim, 0, 0, zeros(dim, mem), zeros(dim, mem), zeros(mem, mem), zeros(mem),
                    zeros(dim), zeros(dim), zeros(dim), zeros(dim), zeros(dim), false, Inf, false,
                    zeros(mem, mem), zeros(mem), 0, 0)
end

function reset!(aa::Anderson)
    aa.ncol = 0
    aa.head = 0
    aa.has_prev = false
    aa.pending = false
    aa.gnorm_ref = Inf
    return aa
end

"Store `w = (x, z + R^{-1} y)` (the point at which the next iteration evaluates T)."
function _aa_load_point!(buf::Vector{Float64}, s)
    n = s.n
    @inbounds for j in 1:n
        buf[j] = s.x[j]
    end
    @inbounds for i in 1:s.m
        buf[n+i] = s.z[i] + s.rhoinv[i] * s.y[i]
    end
    return buf
end

"Set the iterate `(x, z, y)` from `w = (x, v)`: `z = Proj_C(v)`, `y = R (v - z)`."
function _aa_set_iterate!(s, wv::Vector{Float64})
    n = s.n
    @inbounds for j in 1:n
        s.x[j] = wv[j]
    end
    @inbounds for i in 1:s.m
        s.w[i] = wv[n+i]
        s.z[i] = wv[n+i]
    end
    _project!(s, s.z)
    @inbounds for i in 1:s.m
        s.y[i] = s.rhovec[i] * (s.w[i] - s.z[i])
    end
    return nothing
end

"Solve `(gram + lambda I) gamma = Gg` (Cholesky of the `ncol` stored columns)."
function _aa_gamma!(aa::Anderson)
    k = aa.ncol
    M = aa.M; gam = aa.gamma
    tr = 0.0
    @inbounds for a in 1:k
        tr += aa.gram[a, a]
    end
    lam = 1e-10 * tr + 1e-300
    @inbounds for b in 1:k, a in 1:k
        M[a, b] = aa.gram[a, b] + (a == b ? lam : 0.0)
    end
    # Cholesky in place (lower), then two triangular solves
    @inbounds for j in 1:k
        d = M[j, j]
        for p in 1:(j-1)
            d -= M[j, p]^2
        end
        d <= 0 && return false
        d = sqrt(d)
        M[j, j] = d
        for i in (j+1):k
            v = M[i, j]
            for p in 1:(j-1)
                v -= M[i, p] * M[j, p]
            end
            M[i, j] = v / d
        end
    end
    @inbounds for i in 1:k
        v = aa.Gg[i]
        for p in 1:(i-1)
            v -= M[i, p] * gam[p]
        end
        gam[i] = v / M[i, i]
    end
    @inbounds for i in k:-1:1
        v = gam[i]
        for p in (i+1):k
            v -= M[p, i] * gam[p]
        end
        gam[i] = v / M[i, i]
    end
    return true
end

"""
After an ADMM iteration from `aa.w` (loaded before it): record the pair, and
unless `extrapolate` is false, replace the iterate by the accelerated point.
Returns true if the iterate was changed.
"""
function _aa_update!(aa::Anderson, s; extrapolate::Bool = true, safeguard::Float64 = 1.0)
    dim = aa.dim
    f = aa.f; g = aa.g; w = aa.w
    _aa_load_point!(f, s)
    gn2 = 0.0
    @inbounds for i in 1:dim
        gi = f[i] - w[i]
        g[i] = gi
        gn2 += gi * gi
    end
    gn = sqrt(gn2)
    if aa.pending
        aa.pending = false
        if gn > safeguard * aa.gnorm_ref
            # reject: back to T of the point the acceleration was computed from
            aa.rejected += 1
            _aa_set_iterate!(s, aa.fprev)
            reset!(aa)
            return true
        end
        aa.accepted += 1
    end
    if aa.has_prev
        # new difference column at the head of the circular buffer
        h = aa.head % aa.mem + 1
        aa.head = h
        aa.ncol = min(aa.ncol + 1, aa.mem)
        dG = aa.dG; dF = aa.dF
        @inbounds for i in 1:dim
            dG[i, h] = g[i] - aa.gprev[i]
            dF[i, h] = f[i] - aa.fprev[i]
        end
        @inbounds for c in 1:aa.ncol
            v = 0.0
            for i in 1:dim
                v += dG[i, c] * dG[i, h]
            end
            aa.gram[c, h] = v
            aa.gram[h, c] = v
        end
    end
    copyto!(aa.gprev, g); copyto!(aa.fprev, f)
    aa.has_prev = true
    (extrapolate && aa.ncol > 0) || return false
    dG = aa.dG
    @inbounds for c in 1:aa.ncol
        v = 0.0
        for i in 1:dim
            v += dG[i, c] * g[i]
        end
        aa.Gg[c] = v
    end
    _aa_gamma!(aa) || (reset!(aa); return false)
    # w+ = f - dF gamma, written into w (reloaded before the next iteration anyway)
    copyto!(w, f)
    dF = aa.dF; gam = aa.gamma
    @inbounds for c in 1:aa.ncol
        gc = gam[c]
        for i in 1:dim
            w[i] -= gc * dF[i, c]
        end
    end
    _aa_set_iterate!(s, w)
    aa.pending = true
    aa.gnorm_ref = gn
    return true
end
