# summarize.jl: markdown tables and pgfplots-ready .dat files from result
# directories written by run.jl.
#
#   julia --project=benchmarks benchmarks/summarize.jl OUTDIR RESULTDIR [RESULTDIR...]
#
# Writes OUTDIR/summary.md and
#   OUTDIR/dat/size_<family>_<mode>_<tier>_<solver>.dat   size nvars median p90 max failures count
#   OUTDIR/dat/profile_<family|all>_<mode>_<tier>.dat     tau and one column per solver (Dolan-More)
# Times are per-QP medians over the repeats (seconds in .dat, milliseconds in
# the tables). Failures (a QP that misses the accuracy tier, or a solver that
# never meets it on the instance) are charged the time limit in shifted
# geometric means and are infinite ratios in the profiles. Shift: 1e-4 s
# (sub-millisecond MPC times; a 1 s shift would flatten every ratio).

import JSON
using Printf, Statistics

const SHIFT = 1e-4
# the solver of the "equal or faster" gate: Mumblebee fast-symbolic with AMF
const GATE = get(ENV, "BENCH_GATE", "mumblebee_fast")
const MODES = ["cold", "warm"]
const TIERNAMES = ["low", "medium", "high"]

num(x) = x isa Number ? Float64(x) : x == "NaN" ? NaN : x == "Inf" ? Inf : x == "-Inf" ? -Inf : NaN

function load(dirs)
    R = Dict{String,Any}[]
    for d in dirs, f in readdir(d; join = true)
        endswith(f, ".json") || continue
        r = JSON.parsefile(f)
        haskey(r, "instance") || continue
        r["_file"] = f
        push!(R, r)
    end
    # files of the same instance key (e.g. a second solver variant run in another
    # environment) merge their solvers; a later file wins for the same solver
    byk = Dict{String,Any}()
    for r in R
        if haskey(byk, r["key"])
            merge!(byk[r["key"]]["solvers"], r["solvers"])
        else
            byk[r["key"]] = r
        end
    end
    return collect(values(byk))
end

"Per-QP times of one solver, tier and mode: Vector of (qp index, time or Inf for a failure)."
function qptimes(r, solver, tier, mode)
    s = get(r["solvers"], solver, nothing)
    s === nothing && return nothing
    t = get(s["tiers"], tier, nothing)
    t === nothing && return nothing
    L = r["instance"]["L"]
    tl = num(r["time_limit"])
    if t["status"] != "ran"
        n = mode == "cold" ? min(L, r["protocol"]["cold_qps"]) : L - 1
        return [(j, Inf) for j in 1:n]
    end
    rows = t[mode]
    mode == "warm" && (rows = rows[2:end])
    return [(Int(row["qp"]), row["ok"] ? num(row["t_med"]) : Inf) for row in rows]
end

function stats(v)
    ok = filter(isfinite, v)
    isempty(ok) && return (med = NaN, p90 = NaN, max = NaN, fail = length(v), n = length(v))
    return (med = median(ok), p90 = quantile(ok, 0.9), max = maximum(ok), fail = count(!isfinite, v), n = length(v))
end

sgm(v, tl) = exp(mean(log.(min.(v, tl) .+ SHIFT))) - SHIFT

ms(x) = isfinite(x) ? (x < 1e-3 ? @sprintf("%.3f", 1e3x) : x < 1e-1 ? @sprintf("%.2f", 1e3x) : @sprintf("%.0f", 1e3x)) : "--"

function main()
    out = ARGS[1]; dirs = ARGS[2:end]
    R = load(dirs)
    isempty(R) && error("no results in $dirs")
    mkpath(joinpath(out, "dat"))
    solvers = sort(unique(vcat([collect(keys(r["solvers"])) for r in R]...)))
    pkg = "sheafmpc"
    others = filter(!=(pkg), solvers)
    fams = sort(unique([r["instance"]["family"] for r in R]))
    io = IOBuffer()
    # setup
    m = R[1]["machine"]
    println(io, "# Benchmark summary\n")
    println(io, "Sources: ", join(dirs, ", "), "; $(length(R)) instances.\n")
    println(io, "## Setup\n")
    hosts = unique([(r["machine"]["host"], r["machine"]["cpu"]) for r in R])
    for (h, c) in hosts
        println(io, "- host `$h`, CPU $c")
    end
    println(io, "- Julia $(m["julia"]), $(m["julia_threads"]) thread, BLAS threads $(m["blas_threads"]); governor `$(m["governor"])`, boost `$(m["boost"])`")
    loads = [num(r["load_before"]["load"][1]) for r in R]
    gates = [r["load_before"]["gate"] for r in R]
    @printf(io, "- 1-minute load before each instance: median %.1f, max %.1f; gate passed %d, timed out %d, skipped %d\n",
            median(loads), maximum(loads), count(==("passed"), gates), count(==("timed_out"), gates), count(==("skipped"), gates))
    for s in solvers
        r = first(filter(r -> haskey(r["solvers"], s), R))
        inf = r["solvers"][s]["info"]
        desc = join(["$k: $(v isa AbstractDict ? JSON.json(v) : v)" for (k, v) in sort(collect(inf); by = first)], "; ")
        println(io, "- **$s**: ", desc)
    end
    println(io, "\nProtocol: accuracy tiers low 1e-3, medium 1e-6, high 1e-9 (relative objective error and relative primal residual against the reference, one shared checker on the unscaled problem); tolerance and variant calibrated per solver and instance on the first, middle and last QP; per-QP time is the median over the repeats; warm statistics exclude the first (cold) QP of the sequence. `--` means not applicable, or no QP met the tier. `f/n` = QPs missing the tier.\n")

    # per family tables
    losses = []; gates = []
    for fam in fams
        RF = sort(filter(r -> r["instance"]["family"] == fam, R); by = r -> (num(r["instance"]["params"]["size"]), r["key"]))
        fs = filter(s -> any(r -> haskey(r["solvers"], s), RF), solvers)
        println(io, "## $fam\n")
        for mode in MODES, tier in TIERNAMES
            println(io, "### $fam, $mode, $tier\n")
            gate = GATE in fs
            println(io, "| instance | vars | ", join(fs, " | "), " | sheafmpc / best other |", gate ? " sheafmpc / $GATE |" : "")
            println(io, "|---|---:|", repeat("---:|", length(fs)), "---:|", gate ? "---:|" : "")
            for r in RF
                cells = String[]; med = Dict{String,Float64}()
                for s in fs
                    v = qptimes(r, s, tier, mode)
                    if v === nothing
                        push!(cells, "n/a"); continue
                    end
                    st = stats(last.(v))
                    med[s] = st.fail == 0 ? st.med : NaN
                    push!(cells, ms(st.med) * (mode == "warm" && isfinite(st.max) ? " ($(ms(st.max)))" : "") * (st.fail > 0 ? " [$(st.fail)/$(st.n)]" : ""))
                end
                bo = [get(med, s, NaN) for s in fs if s != pkg]
                bo = filter(isfinite, bo)
                best = isempty(bo) ? NaN : minimum(bo)
                bests = isempty(bo) ? "" : fs[findfirst(s -> s != pkg && get(med, s, NaN) == best, fs)]
                ratio = get(med, pkg, NaN) / best
                rs = isfinite(ratio) ? @sprintf("%.2f (%s)", ratio, bests) : (haskey(med, pkg) && !isnan(best) ? "pkg fails" : "--")
                push!(losses, (fam = fam, key = r["key"], mode = mode, tier = tier, ratio = ratio, best = bests,
                               pkg = get(med, pkg, NaN), other = best, pkgfail = haskey(med, pkg) && isnan(med[pkg])))
                gr = get(med, pkg, NaN) / get(med, GATE, NaN)
                gs = gate ? (isfinite(gr) ? @sprintf(" %.2f |", gr) : " -- |") : ""
                gate && push!(gates, (key = r["key"], mode = mode, tier = tier, ratio = gr,
                                      pkgmiss = haskey(med, pkg) && isnan(med[pkg]) && isfinite(get(med, GATE, NaN))))
                println(io, "| $(r["key"]) | $(r["instance"]["nvars"]) | ", join(cells, " | "), " | $rs |", gs)
            end
            println(io, mode == "warm" ? "\nWarm cells: median (max) ms.\n" : "\nCold cells: median ms of the solve; setup is separate.\n")
        end
        # setup times
        println(io, "### $fam, setup (ms, median over the cold repeats, medium tier)\n")
        println(io, "| instance | ", join(fs, " | "), " |")
        println(io, "|---|", repeat("---:|", length(fs)))
        for r in RF
            cells = [haskey(r["solvers"], s) && haskey(r["solvers"][s]["tiers"], "medium") && haskey(r["solvers"][s]["tiers"]["medium"], "setup_med") ?
                     ms(num(r["solvers"][s]["tiers"]["medium"]["setup_med"])) : "--" for s in fs]
            println(io, "| $(r["key"]) | ", join(cells, " | "), " |")
        end
        println(io)
        # size curves
        for mode in MODES, tier in TIERNAMES, s in fs
            open(joinpath(out, "dat", "size_$(fam)_$(mode)_$(tier)_$(s).dat"), "w") do f
                println(f, "size nvars median p90 max failures count")
                for r in RF
                    v = qptimes(r, s, tier, mode); v === nothing && continue
                    st = stats(last.(v))
                    @printf(f, "%g %d %.6e %.6e %.6e %d %d\n", num(r["instance"]["params"]["size"]), r["instance"]["nvars"],
                            st.med, st.p90, st.max, st.fail, st.n)
                end
            end
        end
    end

    # shifted geometric means and performance profiles
    println(io, "## Shifted geometric means (ms; shift $(1e3SHIFT) ms; failures charged the time limit) and failure rates\n")
    taus = exp10.(range(0, 3, length = 61))
    for mode in MODES, tier in TIERNAMES
        println(io, "### $mode, $tier\n")
        println(io, "| family | ", join(solvers, " | "), " |")
        println(io, "|---|", repeat("---:|", length(solvers)))
        allratios = Dict(s => Float64[] for s in solvers)
        for fam in [fams; "all"]
            RF = fam == "all" ? R : filter(r -> r["instance"]["family"] == fam, R)
            fs = filter(s -> all(r -> haskey(r["solvers"], s), RF), solvers)   # solvers applicable to the whole family
            T = Dict(s => Float64[] for s in fs); tls = Float64[]
            ratios = Dict(s => Float64[] for s in fs)
            for r in RF
                per = Dict(s => Dict(qptimes(r, s, tier, mode)) for s in fs)
                isempty(fs) && continue
                qs = keys(per[fs[1]])
                for q in qs
                    tq = Dict(s => get(per[s], q, Inf) for s in fs)
                    best = minimum(values(tq))
                    for s in fs
                        push!(T[s], tq[s])
                        isfinite(best) && push!(ratios[s], tq[s] / best)
                    end
                    push!(tls, num(r["time_limit"]))
                end
            end
            cells = [s in fs && !isempty(T[s]) ? @sprintf("%s (%.0f%% fail)", ms(sgm(T[s], minimum(tls))), 100 * count(!isfinite, T[s]) / length(T[s])) : "--"
                     for s in solvers]
            println(io, "| $fam | ", join(cells, " | "), " |")
            isempty(fs) && continue
            open(joinpath(out, "dat", "profile_$(fam)_$(mode)_$(tier).dat"), "w") do f
                println(f, "tau ", join(fs, " "))
                for tau in taus
                    println(f, @sprintf("%.6g", tau), " ", join([@sprintf("%.4f", isempty(ratios[s]) ? 0.0 : count(<=(tau), ratios[s]) / length(ratios[s])) for s in fs], " "))
                end
            end
        end
        println(io)
    end

    # where the package loses
    println(io, "## Where sheafmpc loses (median time over the best other solver, ratio > 1, or misses the tier)\n")
    println(io, "| instance | mode | tier | sheafmpc ms | best other | its ms | ratio |")
    println(io, "|---|---|---|---:|---|---:|---:|")
    L = sort(filter(l -> (isfinite(l.ratio) && l.ratio > 1) || l.pkgfail, losses); by = l -> -(isfinite(l.ratio) ? l.ratio : 1e9))
    for l in L
        println(io, "| $(l.key) | $(l.mode) | $(l.tier) | $(ms(l.pkg)) | $(l.best) | $(ms(l.other)) | ",
                isfinite(l.ratio) ? @sprintf("%.2f", l.ratio) : "fails", " |")
    end
    W = filter(l -> isfinite(l.ratio), losses)
    if !isempty(W)
        @printf(io, "\nsheafmpc is fastest (ratio <= 1) in %d of %d (instance, mode, tier) cells with a finite ratio; median ratio %.2f.\n",
                count(l -> l.ratio <= 1, W), length(W), median([l.ratio for l in W]))
    end
    G = filter(g -> isfinite(g.ratio) || g.pkgmiss, gates)
    if !isempty(G)
        println(io, "\n## Gate: sheafmpc against $GATE (median time ratio; <= 1 passes)\n")
        println(io, "| mode | tier | cells | pass | sheafmpc misses the tier | median ratio | worst ratio (instance) |")
        println(io, "|---|---|---:|---:|---:|---:|---|")
        for mode in MODES, tier in TIERNAMES
            g = filter(x -> x.mode == mode && x.tier == tier, G)
            isempty(g) && continue
            gf = filter(x -> isfinite(x.ratio), g)
            w = isempty(gf) ? nothing : gf[argmax([x.ratio for x in gf])]
            @printf(io, "| %s | %s | %d | %d | %d | %s | %s |\n", mode, tier, length(g), count(x -> isfinite(x.ratio) && x.ratio <= 1, g),
                    count(x -> x.pkgmiss, g), isempty(gf) ? "--" : @sprintf("%.2f", median([x.ratio for x in gf])),
                    w === nothing ? "--" : @sprintf("%.2f (%s)", w.ratio, w.key))
        end
    end
    write(joinpath(out, "summary.md"), String(take!(io)))
    println("wrote ", joinpath(out, "summary.md"))
end

main()
