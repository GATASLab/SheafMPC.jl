# variants_parse.jl: SHEAF_VARIANTS="name:key=val,key=val;name2:..." -> [name => Dict(settings)]

function parse_variants(s)
    out = Pair{String,Dict{Symbol,Any}}[]
    for item in split(s, ";")
        isempty(strip(item)) && continue
        name, kv = occursin(":", item) ? split(item, ":"; limit = 2) : (item, "")
        d = Dict{Symbol,Any}()
        for a in split(kv, ",")
            isempty(strip(a)) && continue
            k, v = split(a, "=")
            vv = v == "true" ? true : v == "false" ? false : startswith(v, ":") ? Symbol(v[2:end]) :
                 occursin(r"^-?\d+$", v) ? parse(Int, v) : parse(Float64, v)
            d[Symbol(strip(k))] = vv
        end
        push!(out, String(strip(name)) => d)
    end
    return out
end
