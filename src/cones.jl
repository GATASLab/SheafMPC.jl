# cones.jl: Euclidean projections onto the constraint sets.

"""
    project_soc!(v, r)

Project `v[r]` onto the second-order cone `{(t, s) : ||s|| <= t}` in place:
`v` itself inside the cone, `0` inside the polar cone, and otherwise
`((t + ||s||)/2) (1, s/||s||)`.
"""
@inline function project_soc!(v::AbstractVector{Float64}, r::UnitRange{Int})
    i0 = first(r)
    t = v[i0]
    ns2 = 0.0
    @inbounds for i in (i0+1):last(r)
        ns2 += v[i] * v[i]
    end
    ns = sqrt(ns2)
    if ns <= t
        return nothing
    elseif ns <= -t
        @inbounds for i in r
            v[i] = 0.0
        end
    else
        a = 0.5 * (t + ns)
        f = a / ns
        @inbounds v[i0] = a
        @inbounds for i in (i0+1):last(r)
            v[i] *= f
        end
    end
    return nothing
end

"""
    project_translated_soc!(z, r, b)

Project `z[r]` onto `{z : b[r] - z in SOC}` in place: `z <- b - proj(b - z)`.
"""
@inline function project_translated_soc!(z::AbstractVector{Float64}, r::UnitRange{Int}, b::AbstractVector{Float64})
    @inbounds for i in r
        z[i] = b[i] - z[i]
    end
    project_soc!(z, r)
    @inbounds for i in r
        z[i] = b[i] - z[i]
    end
    return nothing
end

"Distance of `v[r]` to the second-order cone (`v` unchanged)."
@inline function soc_distance(v::AbstractVector{Float64}, r::UnitRange{Int}; sign::Float64 = 1.0)
    i0 = first(r)
    t = sign * v[i0]
    ns2 = 0.0
    @inbounds for i in (i0+1):last(r)
        ns2 += v[i] * v[i]
    end
    ns = sqrt(ns2)
    ns <= t && return 0.0
    ns <= -t && return sqrt(t * t + ns2)
    a = 0.5 * (t + ns)
    # distance between (t, s) and (a, a s/||s||)
    return sqrt((t - a)^2 + (ns - a)^2)
end
