# numbers_flagship_text.jl: the \cnFlag macros the manuscript quotes about E26 (the
# flagship, results/e26_flagship.json from e26_flagship.jl, BENCH_MODE=merge).
# Hook of scripts/gen_numbers.jl. Each macro reduces the file's "numbers" table (or
# its per-seed records) to the one quantity the text states; the lookup names the
# regime (Coh/Inc), input set (Soc/Box) and fleet size (TwoFiftySix, OneK, FourK,
# SixteenK) as in numbers_flagship.jl. Times: ms per closed-loop step, median over
# seeds of each seed's median over steps after the first.

const FLAGT_FILE = joinpath(@__DIR__, "..", "..", "results", "e26_flagship.json")

if isdefined(Main, :defmacro!) && isdefined(Main, :MACROS) && isfile(FLAGT_FILE)
    let
        JS = Main.JSON; fsci_ = Main.fsci; fsig_ = Main.fsig; fint_ = Main.fint
        SIZE = Dict(256 => "TwoFiftySix", 1024 => "OneK", 4096 => "FourK", 16384 => "SixteenK")
        sizes(N, reg, cone) = sort([n for n in keys(SIZE) if haskey(N, "$(reg)_$(cone)_$(SIZE[n])_n")])
        nmax(N) = maximum(sizes(N, "Coh", "Soc"))
        T(N, reg, cone, n, q) = N["$(reg)_$(cone)_$(SIZE[n])_$(q)"]
        med(v) = (s = sort(Float64.(v)); k = length(s); isodd(k) ? s[(k + 1) ÷ 2] : (s[k ÷ 2] + s[k ÷ 2 + 1]) / 2)
        # per-seed records of one configuration
        seeds(d, key) = d["configs"][key]["per_seed"]
        pertime(r, L) = Float64(r["$(L)_t_total_med"])
        speed(d, key) = med([pertime(r, "fine") / pertime(r, "red") for r in seeds(d, key)])
        share(d, key) = med([Float64(r["red_t_construct_med"]) / Float64(r["red_t_total_med"]) for r in seeds(d, key)])
        cfg(reg, cone, n) = "$(reg)_$(cone)_n$(n)"
        defm(name, path, fmt, meaning, red) = Main.defmacro!(name, "e26_flagship", path, fmt, meaning; reduce = red, reduce_name = "flagship text reduction")
        defm("cnFlagNmin", ["numbers"], fint_, "smallest fleet of E26 (vehicles)", N -> minimum(sizes(N, "Coh", "Soc")))
        defm("cnFlagNmax", ["numbers"], fint_, "largest fleet of E26 (vehicles)", N -> nmax(N))
        defm("cnFlagSteps", ["numbers", "steps"], fint_, "closed-loop steps", identity)
        defm("cnFlagHorizon", ["numbers", "H"], fint_, "MPC horizon", identity)
        defm("cnFlagSeeds", ["numbers"], fint_, "seeds at fleets of at most 1024 vehicles (coherent, input balls)",
             N -> T(N, "Coh", "Soc", 1024, "seeds"))
        defm("cnFlagRatioDev", ["numbers"], N -> fsci_(N; d = 1), "largest |closed-loop cost ratio - 1|, every coherent run with input balls",
             N -> maximum(T(N, "Coh", "Soc", n, "ratio_dev_max") for n in sizes(N, "Coh", "Soc")))
        defm("cnFlagBoxRatioDev", ["numbers"], N -> fsci_(N; d = 1), "the same with input boxes",
             N -> maximum(T(N, "Coh", "Box", n, "ratio_dev_max") for n in sizes(N, "Coh", "Box")))
        # macros that need per-seed records read the whole file through the empty path
        defwhole(name, fmt, meaning, red) = Main.defmacro!(name, "e26_flagship", Any[], fmt, meaning; reduce = red, reduce_name = "flagship text reduction")
        defwhole("cnFlagSpeedupMax", fsig_, "coordinated over reduced loop time per step, median over seeds of the per-seed ratio, largest fleet (input balls)",
                 d -> speed(d, cfg("coherent", "soc", nmax(d["numbers"]))))
        defm("cnFlagFineSecMax", ["numbers"], fsig_, "coordinated loop, s per step, largest fleet", N -> T(N, "Coh", "Soc", nmax(N), "fine_ms_med") / 1e3)
        defm("cnFlagRedMsMax", ["numbers"], fsig_, "reduced loop, ms per step, largest fleet", N -> T(N, "Coh", "Soc", nmax(N), "red_ms_med"))
        defm("cnFlagFineVarsMax", ["numbers"], N -> fsig_(N), "variables of the coordinated program, largest fleet", N -> T(N, "Coh", "Soc", nmax(N), "fine_vars"))
        defm("cnFlagRedVarsMax", ["numbers"], fint_, "variables of the reduced program, largest fleet", N -> T(N, "Coh", "Soc", nmax(N), "red_vars"))
        defwhole("cnFlagSpeedupThousand", fsig_, "the same speedup at 1024 vehicles (input balls)", d -> speed(d, cfg("coherent", "soc", 1024)))
        defm("cnFlagClarabelFineS", ["numbers"], fsig_, "Clarabel on the coordinated program at 1024 vehicles, s per step (replay)", N -> T(N, "Coh", "Soc", 1024, "fine_clarabel_ms_med") / 1e3)
        defm("cnFlagClarabelRedMs", ["numbers"], fsig_, "Clarabel on the reduced program at 1024 vehicles, ms per step", N -> T(N, "Coh", "Soc", 1024, "red_clarabel_ms_med"))
        defm("cnFlagMumblebeeFineS", ["numbers"], fsig_, "Mumblebee on the coordinated program at 1024 vehicles, s per step", N -> T(N, "Coh", "Soc", 1024, "fine_mumblebee_ms_med") / 1e3)
        defm("cnFlagMumblebeeRedMs", ["numbers"], fsig_, "Mumblebee on the reduced program at 1024 vehicles, ms per step", N -> T(N, "Coh", "Soc", 1024, "red_mumblebee_ms_med"))
        defwhole("cnFlagBoxSpeedup", fsig_, "coordinated over reduced loop time per step at 1024 vehicles (input boxes)", d -> speed(d, cfg("coherent", "box", 1024)))
        defm("cnFlagBoxOsqpS", ["numbers"], fsig_, "OSQP warm on the coordinated program at 1024 vehicles (input boxes), s per step", N -> T(N, "Coh", "Box", 1024, "fine_osqp_warm_ms_med") / 1e3)
        # real time: the largest fleet whose worst step (largest over seeds of the largest step time) fits in one sampling period h
        defwhole("cnFlagSampleMs", fint_, "sampling period h of E26, ms", d -> round(Int, 1e3 * Float64(d["h"])))
        rt(d, q) = maximum([n for n in sizes(d["numbers"], "Coh", "Soc") if T(d["numbers"], "Coh", "Soc", n, q) < 1e3 * Float64(d["h"])]; init = 0)
        defwhole("cnFlagRealtimeRedN", fint_, "largest fleet whose reduced controller meets the sampling period at every step (largest ms per step < h)", d -> rt(d, "red_ms_max"))
        defwhole("cnFlagRealtimeFineN", fint_, "largest fleet whose coordinated MPC meets the sampling period at every step (0: none)", d -> rt(d, "fine_ms_max"))
        defm("cnFlagFineMsMaxMin", ["numbers"], fsig_, "coordinated MPC, largest ms per step at the smallest fleet", N -> T(N, "Coh", "Soc", minimum(sizes(N, "Coh", "Soc")), "fine_ms_max"))
        defm("cnFlagRedMsMaxRt", ["numbers"], fsig_, "reduced controller, largest ms per step at the largest real-time fleet",
             N -> T(N, "Coh", "Soc", maximum([n for n in sizes(N, "Coh", "Soc") if T(N, "Coh", "Soc", n, "red_ms_max") < 200]), "red_ms_max"))
        defm("cnFlagRedBuildMax", ["numbers"], fsig_, "offline build of the reduced controller (chain and step operator), s, largest fleet (median over seeds)", N -> T(N, "Coh", "Soc", nmax(N), "red_build_s_med"))
        defm("cnFlagRedBuildThousand", ["numbers"], fsig_, "the same at 1024 vehicles, s", N -> T(N, "Coh", "Soc", 1024, "red_build_s_med"))
        # fair baseline: coordinated MPC in its faster form (sparse loop or condensed replay, medians)
        best(N, cone, n) = minimum(Float64(N[k]) for k in ("Coh_$(cone)_$(SIZE[n])_fine_ms_med", "Coh_$(cone)_$(SIZE[n])_cond_teammpc_warm_ms_med", "Coh_$(cone)_$(SIZE[n])_cond_teammpc_cold_ms_med") if haskey(N, k))
        # fair worst step: coordinated MPC in whichever form has the smaller worst step (sparse loop or condensed replays), largest over seeds
        rep(d, cone, n, f) = d["configs"][cfg("coherent", cone, n)]["summary"]["replays"][f]["ms_max"]
        worst(d, cone, n) = minimum([Float64(T(d["numbers"], "Coh", cone == "soc" ? "Soc" : "Box", n, "fine_ms_max")); [Float64(rep(d, cone, n, f)) for f in ("cond/teammpc_warm", "cond/teammpc_cold")]])
        defwhole("cnFlagCoordWorstMsQuarter", fsig_, "coordinated MPC at 256 vehicles, input balls, largest ms per step in its form with the smaller worst step", d -> worst(d, "soc", 256))
        defwhole("cnFlagBoxCoordWorstMsThousand", fsig_, "the same at 1024 vehicles with input boxes", d -> worst(d, "box", 1024))
        defm("cnFlagBoxRedMsThousand", ["numbers"], fsig_, "team MPC at 1024 vehicles, input boxes, median ms per step", N -> T(N, "Coh", "Box", 1024, "red_ms_med"))
        defm("cnFlagBoxRedMsMaxThousand", ["numbers"], fsig_, "team MPC at 1024 vehicles, input boxes, largest ms per step", N -> T(N, "Coh", "Box", 1024, "red_ms_max"))
        defm("cnFlagFineVarsThousand", ["numbers"], fint_, "variables of the coordinated program at 1024 vehicles", N -> T(N, "Coh", "Soc", 1024, "fine_vars"))
        defm("cnFlagRedVarsThousand", ["numbers"], fint_, "variables of the team program at 1024 vehicles", N -> T(N, "Coh", "Soc", 1024, "red_vars"))
        defm("cnFlagCoordBestMsThousand", ["numbers"], x -> fsig_(x; n = 3), "coordinated MPC at 1024 vehicles, input balls, faster of sparse and condensed form, median ms per step", N -> best(N, "Soc", 1024))
        defm("cnFlagCoordBestMsQuarter", ["numbers"], fsig_, "the same at 256 vehicles", N -> best(N, "Soc", 256))
        defm("cnFlagBoxCoordBestMsThousand", ["numbers"], fsig_, "the same at 1024 vehicles with input boxes", N -> best(N, "Box", 1024))
        defm("cnFlagRedMsMaxThousand", ["numbers"], fsig_, "team MPC, largest ms per step at 1024 vehicles, input balls", N -> T(N, "Coh", "Soc", 1024, "red_ms_max"))
        defm("cnFlagCoordOverPeriodThousand", ["numbers"], fsig_, "coordinated MPC's faster-form median at 1024 vehicles over the sampling period", N -> best(N, "Soc", 1024) / 200)
        defwhole("cnFlagRedConstructShare", x -> Main.fpct(x) * "\\%", "construction time over total time of the reduced controller, median over seeds, largest fleet",
                 d -> share(d, cfg("coherent", "soc", nmax(d["numbers"]))))
    end
end
