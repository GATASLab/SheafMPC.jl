# results/*.json -> preamble/numbers.tex and results/numbers_index.md.
#
#   julia --project=env scripts/gen_numbers.jl        (make numbers)
#
# This script is the only writer of preamble/numbers.tex.
# Every macro is one measured quantity: `\cn` followed by letters only
# (no digits), preceded in the .tex file by a comment naming its JSON file and
# key path. A missing file or key is an error (exit 1), never a placeholder.
#
# Hook: if scripts/resolution/numbers_spatial.jl exists it is included after
# the macros below and may call
#
#     defmacro!(name, file, path, fmt, meaning; reduce = identity)
#
# where `name` is the macro name without the backslash (`"cnEsixFoo"`), `file`
# the results file without `.json`, `path` a vector of keys (strings) and
# 1-based indices (integers), `fmt` one of the formatters below (`fint`,
# `fsci`, `fsig`, `ffix`, `fpct`), and `reduce` an optional function applied to
# the value at `path` (e.g. `length`, `maximum`); its name is recorded in the
# comment.

using JSON, Printf

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULTS = joinpath(ROOT, "results")
const OUTFILE = joinpath(ROOT, "preamble", "numbers.tex")
const INDEXFILE = joinpath(RESULTS, "numbers_index.md")

# Rounding direction of the macro being formatted: maxima and worst cases round up and
# minima down, so a printed "at most" or "at least" stays true; a largest admissible
# value (TauMax: the largest delay that still meets the period) rounds down.
const RMODE = Ref{RoundingMode}(RoundNearest)
rmode_for(name) = occursin("TauMax", name) ? RoundDown : occursin(r"Max|Worst", name) ? RoundUp :
                  occursin("Min", name) ? RoundDown : RoundNearest

struct NumMacro
    name::String
    file::String
    path::Vector{Any}
    fmt::Function
    meaning::String
    reduce::Function
    reduce_name::String
end

const MACROS = NumMacro[]
const CACHE = Dict{String,Any}()

function load_results(file::AbstractString)
    get!(CACHE, file) do
        path = joinpath(RESULTS, file * ".json")
        isfile(path) || error("gen_numbers: missing results file $path")
        JSON.parsefile(path)
    end
end

pathstring(path) = join([p isa Integer ? "[$p]" : p isa AbstractDict ? "[" * join(["$k=$v" for (k, v) in sort(collect(p); by = first)], ",") * "]" :
                          string(p) for p in path], "/")

function lookup(file::AbstractString, path::Vector)
    v = load_results(file)
    for p in path
        if p isa AbstractDict
            # a selector: the unique element of an array whose fields match
            v isa AbstractVector || error("gen_numbers: results/$file.json: selector on a non-array at $(pathstring(path))")
            hits = [x for x in v if x isa AbstractDict && all(k -> haskey(x, k) && x[k] == p[k], keys(p))]
            length(hits) == 1 || error("gen_numbers: results/$file.json: selector $(pathstring([p])) matches $(length(hits)) elements")
            v = hits[1]
        elseif p isa Integer
            (v isa AbstractVector && 1 <= p <= length(v)) ||
                error("gen_numbers: results/$file.json has no index $p at $(pathstring(path))")
            v = v[p]
        else
            (v isa AbstractDict && haskey(v, p)) ||
                error("gen_numbers: results/$file.json has no key \"$p\" at $(pathstring(path))")
            v = v[p]
        end
    end
    return v
end

"""Register a macro (see the header for the hook contract)."""
function defmacro!(name::AbstractString, file::AbstractString, path::Vector, fmt::Function, meaning::AbstractString;
                   reduce::Function = identity, reduce_name::AbstractString = reduce === identity ? "" : string(reduce))
    occursin(r"^cn[A-Z][A-Za-z]*$", name) || error("gen_numbers: macro name \\$name must be cn followed by letters only")
    any(m -> m.name == name, MACROS) && error("gen_numbers: duplicate macro \\$name")
    push!(MACROS, NumMacro(String(name), String(file), Vector{Any}(path), fmt, String(meaning), reduce, String(reduce_name)))
    return nothing
end

# ---------------------------------------------------------------------------
# formatters (return LaTeX that works in text and in math)
# ---------------------------------------------------------------------------

tonum(x::Number) = Float64(x)
tonum(x::AbstractString) = x == "Inf" ? Inf : x == "-Inf" ? -Inf : x == "NaN" ? NaN : parse(Float64, x)
tonum(x) = error("gen_numbers: not a number: $(repr(x))")

"""An integer, plain."""
fint(x) = (v = tonum(x); isinteger(round(v)) || error("not an integer"); string(round(Int, v)))

"""Scientific notation with `d` significant digits: `\\ensuremath{2\\times10^{-9}}`."""
function fsci(x; d::Int = 1)
    v = tonum(x)
    isfinite(v) || error("gen_numbers: non-finite value $v")
    v == 0 && return "0"
    e = floor(Int, log10(abs(v)))
    m = round(v / 10.0^e, RMODE[]; digits = d - 1)
    if abs(m) >= 10
        m /= 10; e += 1
    end
    ms = d == 1 ? string(round(Int, m)) : @sprintf("%.*f", d - 1, m)
    return "\\ensuremath{$(ms)\\times10^{$(e)}}"
end

"""`n` significant digits, fixed notation between 1e-3 and 1e5, scientific outside."""
function fsig(x; n::Int = 2)
    v = tonum(x)
    isfinite(v) || error("gen_numbers: non-finite value $v")
    v == 0 && return "0"
    (abs(v) < 1e-3 || abs(v) >= 1e5) && return fsci(v; d = n)
    e = floor(Int, log10(abs(v)))
    dec = max(0, n - 1 - e)
    s = @sprintf("%.*f", dec, round(v, RMODE[]; sigdigits = n))
    return v < 0 ? "\\ensuremath{$s}" : s
end

"""Fixed notation with `d` decimals."""
function ffix(x; d::Int = 2)
    v = tonum(x)
    s = @sprintf("%.*f", d, round(v, RMODE[]; digits = d))
    return v < 0 ? "\\ensuremath{$s}" : s
end

"""A fraction as a percentage with `d` decimals (no percent sign)."""
fpct(x; d::Int = 0) = @sprintf("%.*f", d, 100 * tonum(x))

"""A ratio to a bound: five significant digits when it is close to 1 (so 0.99997 is not printed as 1.00)."""
fratio(x) = (v = tonum(x); v > 0.9 ? @sprintf("%.5g", round(v, RMODE[]; sigdigits = 5)) : fsig(v))

sig3(x) = fsig(x; n = 3)
sci2(x) = fsci(x; d = 2)
fix3(x) = ffix(x; d = 3)
fix1(x) = ffix(x; d = 1)
fix2(x) = ffix(x; d = 2)

function main_numbers()
    empty!(MACROS)
    # hooks: every scripts/resolution/numbers_<name>.jl registers its macros
    for f in ("numbers_simulation.jl", "numbers_scalesim.jl", "numbers_flagship_text.jl")
        include(joinpath(@__DIR__, "resolution", f))
    end
    lines = String["% GENERATED by scripts/gen_numbers.jl from results/*.json; do not edit by hand.",
                   "% Every macro is one measured quantity; the comment above it names the JSON file and key path.",
                   "% Regenerate with `make numbers` (julia --project=env scripts/gen_numbers.jl).", ""]
    index = String["# Numbers index", "", "Generated by `scripts/gen_numbers.jl` with `preamble/numbers.tex`; one row per macro.", "",
                   "| macro | value | meaning | source |", "|---|---|---|---|"]
    for m in MACROS
        raw = lookup(m.file, m.path)
        v = Base.invokelatest(m.reduce, raw)
        RMODE[] = rmode_for(m.name)
        s = Base.invokelatest(m.fmt, v)
        RMODE[] = RoundNearest
        src = "results/$(m.file).json: $(pathstring(m.path))" * (isempty(m.reduce_name) ? "" : " ($(m.reduce_name))")
        push!(lines, "% $src :: $(m.meaning)")
        push!(lines, "\\newcommand{\\$(m.name)}{$s}")
        esc(x) = replace(x, "|" => "\\|")
        push!(index, "| `\\$(m.name)` | `$(esc(s))` | $(esc(m.meaning)) | `$(esc(src))` |")
    end
    open(OUTFILE, "w") do io
        println(io, join(lines, "\n"))
    end
    open(INDEXFILE, "w") do io
        println(io, join(index, "\n"))
    end
    println("wrote $(length(MACROS)) macros to $OUTFILE and $INDEXFILE")
end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        main_numbers()
    catch err
        println(stderr, sprint(showerror, err))
        exit(1)
    end
end
