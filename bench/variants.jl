# variants.jl: SheafMPC settings variants side by side on the fleet QPs, cold
# solves: iterations, polish attempts and factorizations, rho updates (the
# deterministic cost drivers) and the min / median time over REPS solves.
#
#   SHEAF_VARIANTS='base:;aa10:anderson=10' BENCH_N=4,16,64 BENCH_B=1,8 julia --project=bench bench/variants.jl

include(joinpath(@__DIR__, "common.jl"))

ints(k, d) = parse.(Int, split(get(ENV, k, d), ","))
const NS = ints("BENCH_N", "1,4,16,64")
const BS = ints("BENCH_B", "1,8")
const CONES = split(get(ENV, "BENCH_CONE", "box,soc"), ",")
const REPS = parse(Int, get(ENV, "BENCH_REPS", "5"))
const EPS = parse(Float64, get(ENV, "BENCH_EPS", "1e-7"))

include(joinpath(@__DIR__, "variants_parse.jl"))

function main()
    vs = parse_variants(get(ENV, "SHEAF_VARIANTS", "base:"))
    println("load: ", strip(read(`uptime`, String)))
    @printf("%-4s %3s %2s %-14s %6s %5s %5s %5s %9s %9s %8s %8s\n", "cone", "n", "b", "variant", "iters", "pol", "fact", "rho+",
            "min ms", "med ms", "gap", "viol")
    tot = Dict(name => [0, 0, 0.0] for (name, _) in vs)
    for cone in CONES, n in NS, b in BS
        p = fleet_conic(blocked_qp(n, 24, b); cone = String(cone))
        ref = clarabel_solve(p; tol = 1e-10)
        ss = [setup(p; eps_abs = EPS, eps_rel = EPS, kw...) for (_, kw) in vs]
        ts = [Float64[] for _ in vs]
        for s in ss
            reset!(s); solve!(s)
        end
        for _ in 1:REPS, (j, s) in enumerate(ss)
            reset!(s)
            GC.gc(false)
            push!(ts[j], solve!(s).solve_time)
        end
        for (j, (name, _)) in enumerate(vs)
            s = ss[j]; info = s.info
            gap = relgap(info.obj, ref.obj); viol = violation(p, s.xsol)
            @printf("%-4s %3d %2d %-14s %6d %5d %5d %5d %9.3f %9.3f %8.1e %8.1e %s\n", cone, n, b, name, info.iter,
                    info.polish_attempts, info.polish_factorizations, info.rho_updates, 1e3 * minimum(ts[j]),
                    1e3 * median(ts[j]), gap, viol, (gap <= 1e-6 && viol <= 1e-6 && info.status == :solved) ? "" : "FAIL")
            tot[name][1] += info.iter; tot[name][2] += info.polish_factorizations + info.rho_updates
            tot[name][3] += log(minimum(ts[j]))
        end
        flush(stdout)
    end
    for (name, _) in vs
        @printf("total %-14s iters %6d  factorizations %4d  geomean min ms %.3f\n", name, tot[name][1], tot[name][2],
                1e3 * exp(tot[name][3] / (length(CONES) * length(NS) * length(BS))))
    end
end

BLAS.set_num_threads(1)
main()
