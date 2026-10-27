# kkt_report.jl: tables (markdown) from the results of kkt.jl, kkt_e2e.jl.
#
#   julia --project=bench bench/kkt_report.jl bench/results/kkt_hpg.json [more.json ...]

using JSON, Printf

ms(x) = x isa Number ? @sprintf("%.3f", 1e3 * x) : "-"

function fleet_table(rows)
    println("| case | KKT dim | OSQP QDLDL f / s | QDLDL.jl f / s | CliqueTrees f / s | BlockLDL f / s (order) | Riccati f / s | nnzL QDLDL / CT / BlockLDL |")
    println("|---|---|---|---|---|---|---|---|")
    for r in rows
        r["set"] in ("fleet", "reduced") || continue
        k = r["kernels"]
        g(n, f) = haskey(k, n) ? ms(k[n][f]) : "-"
        case = r["set"] == "fleet" ? "$(r["graph"]) $(r["form"]) n=$(r["n"])" : "team $(r["rows"])x$(r["cols"]) $(r["level"])"
        @printf("| %s | %d | %s / %s | %s / %s | %s / %s | %s / %s (%s) | %s / %s | %d / %d / %d |\n", case, r["kkt_dim"],
                g("osqp_qdldl", "factor"), g("osqp_qdldl", "solve"), g("qdldl_jl", "factor"), g("qdldl_jl", "solve"),
                g("cliquetrees", "factor"), g("cliquetrees", "solve"), g("blockldl", "factor"), g("blockldl", "solve"),
                k["blockldl"]["ordering"], g("riccati", "factor"), g("riccati", "solve"), k["osqp_qdldl"]["nnzL"],
                k["cliquetrees"]["nnzL"], k["blockldl"]["nnzL"])
    end
end

function symbolic_table(rows)
    println("| case | OSQP QDLDL sym | BlockLDL sym (order incl.) | BlockLDL factor | refined residual |")
    println("|---|---|---|---|---|")
    for r in rows
        r["set"] == "fleet" || continue
        k = r["kernels"]
        @printf("| %s %s n=%d | %s | %s | %s | %.1e |\n", r["graph"], r["form"], r["n"], ms(k["osqp_qdldl"]["symbolic"]),
                ms(k["blockldl"]["symbolic"]), ms(k["blockldl"]["factor"]), k["blockldl"]["res_refined"])
    end
end

function lowrank_table(rows)
    println("| case | refactor ms | k=1 | k=4 | k=16 | k=64 | k=256 |")
    println("|---|---|---|---|---|---|---|")
    for r in rows
        r["set"] == "lowrank" || continue
        l = r["lowrank"]
        cells = [haskey(l, string(k)) ? ms(l[string(k)]["update"]) : "-" for k in (1, 4, 16, 64, 256)]
        @printf("| %s n=%d | %s | %s |\n", r["graph"], r["n"], ms(l["refactor"]), join(cells, " | "))
    end
end

function e2e_table(rows)
    println("| mode | graph | b | n | backend | setup ms | solve min ms | iters | notes |")
    println("|---|---|---|---|---|---|---|---|---|")
    for r in rows
        if r["mode"] == "single"
            @printf("| single | %s | %d | %d | %s | %s | %s | %d | %s |\n", r["graph"], r["b"], r["n"], r["backend"],
                    ms(r["t_setup"]), ms(r["t"]), r["iters"], get(r, "ordering", ""))
        else
            @printf("| rh | ring | %d | %d | %s | - | %s (median step) | %.0f | max %s |\n", r["b"], r["n"], r["backend"],
                    ms(r["t_med"]), r["it_med"], ms(r["t_max"]))
        end
    end
end

for f in ARGS
    d = JSON.parsefile(f)
    rows = d["rows"]
    println("\n## ", basename(f), " (", d["host"], ", ", d["cpu"], ")\n")
    if any(r -> haskey(r, "mode"), rows)
        e2e_table(rows)
    else
        any(r -> r["set"] in ("fleet", "reduced"), rows) && (fleet_table(rows); println(); symbolic_table(rows); println())
        any(r -> r["set"] == "lowrank", rows) && lowrank_table(rows)
    end
end
