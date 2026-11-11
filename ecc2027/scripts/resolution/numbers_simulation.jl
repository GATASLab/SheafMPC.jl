# numbers_simulation.jl: the \cnSim macros of Section VI (drone/car fleet, ZOH).
#   E51 results/e51_symmetric.json   team MPC (rows) vs symmetric MPC (mirror orbits) vs coordinated MPC
#   E52 results/e52_admm.json        consensus ADMM on the fleet vs on the quotient
#   E54 results/e54_lifted.json      lifted QP (per-sample colour refinement) vs team MPC
#   E63 results/e63_irregular*.json  planted squads (lossless) and the natural formation (lossy), gap and timing runs
# Hook of scripts/gen_numbers.jl; a file that is missing leaves its macros out.

const SIM_RES = joinpath(@__DIR__, "..", "..", "results")
sim_has(f) = isfile(joinpath(SIM_RES, f * ".json"))

if isdefined(Main, :defmacro!) && isdefined(Main, :MACROS)
    let D = Main.defmacro!, fint = Main.fint, fsig = Main.fsig, fsci = Main.fsci, fpct = Main.fpct
        sec(x) = Main.fsig(x / 1000)
        f3(x) = Main.fsig(x; n = 3)
        pc(x) = Main.fsig(100 * x)
        sizes(S) = sort([parse(Int, k) for k in keys(S)])

        # -------------------------------------------------------------- setup
        if sim_has("setup")
            D("cnSetHorizon", "setup", ["horizon"], fint, "MPC horizon T of Section VI")
            D("cnSetUmaxDrone", "setup", ["umax_drone"], fsig, "input ball radius of a drone, m/s^2")
            D("cnSetUmaxCar", "setup", ["umax_car"], fsig, "input ball radius of a car, m/s^2")
            D("cnSetDragCar", "setup", ["drag_car"], fsig, "linear drag of a car, 1/s")
            D("cnSetRDrone", "setup", ["r_drone"], fsig, "effort weight of a drone (R = r I)")
            D("cnSetRCar", "setup", ["r_car"], fsig, "effort weight of a car (R = r I)")
            D("cnSetQPos", "setup", ["q_position"], fsig, "position tracking weight (Q = q C'C)")
            D("cnSetQfPos", "setup", ["qf_position"], fsig, "terminal weight on position")
            D("cnSetQfVel", "setup", ["qf_velocity"], fsig, "terminal weight on velocity")
            D("cnSetSolverEps", "setup", ["solver_eps"], fsci, "absolute and relative tolerance of our solver")
        end

        # --------------------------------------------------------- E74 mission formations
        if sim_has("e74_mission")
            for (nm, v) in ("Esc" => "E1t", "Ring" => "Ccyl", "Lat" => "L26", "LatBal" => "L26bal", "Conv" => "C1", "Ware" => "W1")
                D("cnMis$(nm)Classes", "e74_mission", ["partitions", "$(v)_N16384", "classes"], fint, "E74 $v: classes at 16384")
                D("cnMis$(nm)TeamsBig", "e74_mission", ["partitions", "$(v)_N16384", "teams"], fint, "E74 $v: teams phi* at 16384")
                D("cnMis$(nm)Red", "e74_mission", ["partitions", "$(v)_N16384", "reduction"], x -> (abs(x - round(x)) < 0.01 ? fint(x) : fsig(x)), "E74 $v: vehicles per team at 16384")
                D("cnMis$(nm)TeamsK", "e74_mission", ["solves", "$(v)_N1024", "teams"], fint, "E74 $v: teams at 1024")
                D("cnMis$(nm)ClassesK", "e74_mission", ["partitions", "$(v)_N1024", "classes"], fint, "E74 $v: classes at 1024")
                D("cnMis$(nm)EqTeamsK", "e74_mission", ["partitions", "$(v)_N1024", "equitable_teams"], fint, "E74 $v: teams of the coarsest equitable partition at 1024")
                D("cnMis$(nm)TeamMs", "e74_mission", ["solves", "$(v)_N1024", "summary", "t_team_med"], x -> fsig(1000x), "E74 $v at 1024: team solve, median ms (Clarabel)")
                D("cnMis$(nm)FullS", "e74_mission", ["solves", "$(v)_N1024", "summary", "t_full_med"], fsig, "E74 $v at 1024: centralized solve, median s (Clarabel)")
                D("cnMis$(nm)MpcTeamMs", "e74_mission", ["solves", "$(v)_N1024", "summary", "mpc_t_team_med"], x -> fsig(1000x), "E74 $v at 1024: package MPC step on teams, median ms")
                D("cnMis$(nm)MpcFullS", "e74_mission", ["solves", "$(v)_N1024", "summary", "mpc_t_full_med"], fsig, "E74 $v at 1024: package MPC step on the fleet, median s")
                nm == "Lat" || D("cnMis$(nm)Speed", "e74_mission", ["solves", "$(v)_N1024", "summary"], fsig, "E74 $v at 1024: centralized over team median solve time (Clarabel)";
                  reduce = S -> S["t_full_med"] / S["t_team_med"], reduce_name = "t_full_med / t_team_med")
                D("cnMis$(nm)Active", "e74_mission", ["solves", "$(v)_N1024", "summary", "active_full_max"], fint, "E74 $v at 1024: active input limits at the centralized minimizer, largest")
            end
            for (nm, v) in ("ConvW" => "C3", "EscW" => "E3", "WareW" => "W3", "Fig" => "Lfig")
                D("cnMis$(nm)Red", "e74_mission", ["partitions", "$(v)_N16384", "reduction"], x -> (abs(x - round(x)) < 0.01 ? fint(x) : fsig(x)), "E74 $v: vehicles per team at 16384")
            end
            for (nm, v) in ("ConvW" => "C3", "EscW" => "E3", "WareW" => "W3")
                D("cnMis$(nm)TeamS", "e74_mission", ["solves", "$(v)_N1024", "summary", "t_team_med"], fsig, "E74 $v at 1024: team solve, median s (Clarabel)")
            end
            D("cnMisLatTeamS", "e74_mission", ["solves", "L26_N1024", "summary", "t_team_med"], fsig, "E74 L26 at 1024: team solve, median s (Clarabel)")
            D("cnMisLatSpeed", "e74_mission", ["solves", "L26_N1024", "summary"], fint, "E74 L26 at 1024: fleet over team median step time, both with our solver (the faster one on this fleet)";
              reduce = S -> round(S["mpc_t_full_med"] / S["mpc_t_team_med"]), reduce_name = "round(mpc_t_full_med / mpc_t_team_med)")
            D("cnMisLatMpcFullMs", "e74_mission", ["solves", "L26_N1024", "summary", "mpc_t_full_med"], x -> fsig(1000x), "E74 L26 at 1024: package MPC step on the fleet, median ms")
            D("cnMisLatSteps", "e74_mission", ["solves", "L26_N1024", "steps"], fint, "E74 L26 at 1024: timed steps"; reduce = length, reduce_name = "length")
            D("cnMisVariants", "e74_mission", ["solves"], fint, "E74: formation variants (geometry, radius, weighting) in the solve runs";
              reduce = S -> length(unique(first(split(k, "_N")) for k in keys(S))), reduce_name = "distinct variants")
            D("cnMisSolves", "e74_mission", ["solves"], fint, "E74: team-vs-centralized solve runs, all variants and sizes";
              reduce = S -> length(S), reduce_name = "number of runs")
            D("cnMisAllSolved", "e74_mission", ["solves"], fint, "E74: runs with every step solved";
              reduce = S -> count(r -> r["summary"]["all_solved"], values(S)), reduce_name = "count all_solved")
            D("cnMisGapMax", "e74_mission", ["solves"], fsci, "E74: largest |gap|/J* over all runs and steps";
              reduce = S -> maximum(abs(st["gap_rel"]) for r in values(S) for st in r["steps"]), reduce_name = "max |gap_rel|")
            D("cnMisActiveMax", "e74_mission", ["solves"], fint, "E74: largest number of active limits at a centralized minimizer";
              reduce = S -> maximum(r["summary"]["active_full_max"] for r in values(S)), reduce_name = "max active_full_max")
            D("cnMisCrMs", "e74_mission", ["partitions"], fsig, "E74: slowest color refinement at about 16k vehicles, ms";
              reduce = P -> 1000 * maximum(v["cr_seconds"] for (k, v) in P if endswith(k, "N16384")), reduce_name = "max cr_seconds at 16384, ms")
            D("cnMisBalMin", "e74_mission", ["partitions", "L26bal_N16384", "balance_factor", "min"], fsig, "E74 L26bal: smallest stiffness factor")
            D("cnMisBalMax", "e74_mission", ["partitions", "L26bal_N16384", "balance_factor", "max"], fsig, "E74 L26bal: largest stiffness factor")
        end

        if sim_has("e97_baselines")
            F97 = Main.JSON.parsefile(joinpath(SIM_RES, "e97_baselines.json"))["formations"]
            for (nm, v) in ("Conv" => "C1", "Esc" => "E1t", "Ware" => "W1", "Ring" => "Ccyl", "Lat" => "L26")
                haskey(F97, v) || continue
                D("cnBase$(nm)TeamMs", "e97_baselines", ["formations", v, "soc", "same_solver_team_ms_med"], x -> fsig(x; n = 3), "E97 $v at 1024, ball: team program, same solver as the best centralized, median ms")
                D("cnBase$(nm)BestMs", "e97_baselines", ["formations", v, "soc", "best_central_ms_med"], x -> (x >= 100 ? fint(round(x)) : fsig(x; n = 3)), "E97 $v at 1024, ball: fastest centralized solver, median ms")
                D("cnBase$(nm)Speed", "e97_baselines", ["formations", v, "soc", "speedup_same_solver"], fint, "E97 $v at 1024, ball: best centralized over team, same solver"; reduce = round, reduce_name = "round")
            end
            D("cnBaseBoxSpeedMin", "e97_baselines", ["formations"], fint, "E97 box limits: best centralized over team, same solver, smallest over formations";
              reduce = F -> round(minimum(F[v]["box"]["speedup_same_solver"] for v in keys(F) if haskey(F[v], "box") && haskey(F[v]["box"], "speedup_same_solver"))), reduce_name = "min, round")
            D("cnBaseBoxSpeedMax", "e97_baselines", ["formations"], fint, "E97 box limits: best centralized over team, same solver, largest over formations";
              reduce = F -> round(maximum(F[v]["box"]["speedup_same_solver"] for v in keys(F) if haskey(F[v], "box") && haskey(F[v]["box"], "speedup_same_solver"))), reduce_name = "max, round")
            D("cnBaseSpeedMin", "e97_baselines", ["formations"], fint, "E97 ball limits: same-solver speedup, smallest over the Table II rows";
              reduce = F -> round(minimum(F[v]["soc"]["speedup_same_solver"] for v in keys(F) if haskey(F[v], "soc") && haskey(F[v]["soc"], "speedup_same_solver"))), reduce_name = "min, round")
            D("cnBaseSpeedMax", "e97_baselines", ["formations"], fint, "E97 ball limits: same-solver speedup, largest over the Table II rows";
              reduce = F -> round(maximum(F[v]["soc"]["speedup_same_solver"] for v in keys(F) if haskey(F[v], "soc") && haskey(F[v]["soc"], "speedup_same_solver"))), reduce_name = "max, round")
            boxf(F, a) = [F[v]["box"]["arms"][a]["ms_med"] for v in keys(F) if haskey(F[v], "box") && haskey(F[v]["box"]["arms"], a) && haskey(F[v]["box"]["arms"][a], "ms_med")]
            D("cnBaseOsqpBoxMin", "e97_baselines", ["formations"], fint, "E97 box: OSQP warm started on the fleet, median ms, fastest formation"; reduce = F -> round(minimum(boxf(F, "osqp_fine_full"))), reduce_name = "min, round")
            D("cnBaseOsqpBoxMax", "e97_baselines", ["formations"], fint, "E97 box: OSQP warm started on the fleet, median ms, slowest formation"; reduce = F -> round(maximum(boxf(F, "osqp_fine_full"))), reduce_name = "max, round")
            D("cnBaseOursBoxMin", "e97_baselines", ["formations"], fint, "E97 box: our solver on the fleet, best form, median ms, fastest formation";
              reduce = F -> round(minimum(F[v]["box"]["best_central_ms_med"] for v in keys(F) if haskey(F[v], "box"))), reduce_name = "min, round")
            D("cnBaseOursBoxMax", "e97_baselines", ["formations"], fint, "E97 box: our solver on the fleet, best form, median ms, slowest formation";
              reduce = F -> round(maximum(F[v]["box"]["best_central_ms_med"] for v in keys(F) if haskey(F[v], "box"))), reduce_name = "max, round")
            f2d(x) = Main.@sprintf("%.2f", x)
            D("cnBaseOursBoxTeamMin", "e97_baselines", ["formations"], f2d, "E97 box: our solver on the team program (form of the best centralized), median ms, fastest formation";
              reduce = F -> minimum(F[v]["box"]["same_solver_team_ms_med"] for v in keys(F) if haskey(F[v], "box")), reduce_name = "min")
            D("cnBaseOursBoxTeamMax", "e97_baselines", ["formations"], f2d, "E97 box: our solver on the team program (form of the best centralized), median ms, slowest formation";
              reduce = F -> maximum(F[v]["box"]["same_solver_team_ms_med"] for v in keys(F) if haskey(F[v], "box")), reduce_name = "max")
            clt(F) = [minimum(F[v][l]["arms"][a]["ms_med"] for a in ("clarabel_cond_team", "clarabel_fine_team")
                              if haskey(F[v][l]["arms"], a) && haskey(F[v][l]["arms"][a], "ms_med") && !(a in get(F[v][l], "rejected", String[])))
                      for v in keys(F) for l in ("box", "soc") if haskey(F[v], l) && any(haskey(F[v][l]["arms"], a) for a in ("clarabel_cond_team", "clarabel_fine_team"))]
            D("cnBaseClarabelTeamMin", "e97_baselines", ["formations"], fsig, "E97 warm: Clarabel on the team program, best form, median ms, fastest formation and limit";
              reduce = F -> minimum(clt(F)), reduce_name = "min over formations and limits of the best form")
            D("cnBaseClarabelTeamMax", "e97_baselines", ["formations"], fsig, "E97 warm: Clarabel on the team program, best form, median ms, slowest formation and limit";
              reduce = F -> maximum(clt(F)), reduce_name = "max over formations and limits of the best form")
            hp(X) = [X[v]["box"]["arms"]["hpipm_b2_full"]["ms_med"] for v in keys(X) if haskey(X[v], "box") && haskey(X[v]["box"]["arms"], "hpipm_b2_full") && haskey(X[v]["box"]["arms"]["hpipm_b2_full"], "ms_med")]
            D("cnBaseHpipmMinMin", "e97_baselines", ["crosscheck", "parts_dev", "formations"], fint, "E97 (three-step dedicated run): HPIPM on the fleet, one step, box limits, fastest formation, minutes"; reduce = X -> floor(minimum(hp(X)) / 60000), reduce_name = "min, floor minutes")
            D("cnBaseHpipmMaxMin", "e97_baselines", ["crosscheck", "parts_dev", "formations"], fint, "E97 (three-step dedicated run): HPIPM on the fleet, one step, box limits, slowest formation, minutes"; reduce = X -> ceil(maximum(hp(X)) / 60000), reduce_name = "max, ceil minutes")
            hpt(X) = [X[v]["box"]["arms"]["hpipm_b1_team"]["ms_med"] for v in keys(X) if haskey(X[v], "box") && haskey(X[v]["box"]["arms"], "hpipm_b1_team") && haskey(X[v]["box"]["arms"]["hpipm_b1_team"], "ms_med")]
            D("cnBaseHpipmTeamMsMin", "e97_baselines", ["crosscheck", "parts_dev", "formations"], fsig, "E97 (three-step dedicated run): HPIPM on the team program, box limits, median ms, fastest formation"; reduce = X -> minimum(hpt(X)), reduce_name = "min")
            D("cnBaseHpipmTeamMsMax", "e97_baselines", ["crosscheck", "parts_dev", "formations"], fsig, "E97 (three-step dedicated run): HPIPM on the team program, box limits, median ms, slowest formation"; reduce = X -> maximum(hpt(X)), reduce_name = "max")
            D("cnBaseSteps", "e97_baselines", ["formations", "C1", "soc", "arms", "sm_cond_full", "nsteps"], fint, "E97: timed warm steps per run (the first, cold, step is not timed)"; reduce = x -> x - 1, reduce_name = "nsteps - 1")
            # HPIPM (box limits, 3 steps) is kept under crosscheck of e97_baselines.json; no macro reads it
            D("cnBaseOsqpConvMs", "e97_baselines", ["formations", "C1", "box", "arms", "osqp_fine_full", "ms_med"], fint, "E97 C1 box: OSQP warm started on the full fleet, median ms"; reduce = round, reduce_name = "round")
            D("cnBaseBestConvBoxMs", "e97_baselines", ["formations", "C1", "box", "best_central_ms_med"], fint, "E97 C1 box: fastest centralized, median ms"; reduce = round, reduce_name = "round")
        end

        # ---------------------------------------------------------------- E52
        if sim_has("e52_admm")
            L = ["sizes", "4096", "loops"]
            D("cnSimAdmmQuotMs", "e52_admm", [L; "quot_b5"; "seq_ms_med"], fsig, "ADMM on the quotient, 5 iterations, 4096 vehicles, sequential ms per sample (median)")
            D("cnSimAdmmFullSec", "e52_admm", [L; "full_b5"; "seq_ms_med"], sec, "ADMM on the fleet, 5 iterations, 4096 vehicles, sequential s per sample (median)")
            D("cnSimAdmmQuotAgents", "e52_admm", [L; "quot_b5"; "agents"], fint, "ADMM agents on the quotient at 4096 vehicles")
            D("cnSimAdmmFullSubMed", "e52_admm", [L; "full_b5"; "sub_med"], fsci, "ADMM on the fleet, 5 iterations, median relative suboptimality per step")
            D("cnSimAdmmQuotSubMed", "e52_admm", [L; "quot_b5"; "sub_med"], fsci, "ADMM on the quotient, 5 iterations, median relative suboptimality per step")
        end

        # ---------------------------------------------------------------- setup of the tube runs
        if sim_has("setup")
            D("cnSetTubeQv", "setup", ["tube_qv"], fsig, "velocity weight of the tube runs, Q_c = C'C + qv V'V")
            D("cnSetTubeHorizon", "setup", ["tube_horizon"], fint, "horizon of the tube runs")
        end

        # ---------------------------------------------------------------- E106, 4 of 5 seeds at 4096 (results/e106_overrun_partial.json)
        if (sim_has("e106_overrun_partial") || sim_has("e106_overrun_full")) && !sim_has("e106_overrun")
            F = sim_has("e106_overrun_full") ? "e106_overrun_full" : "e106_overrun_partial"; C = ["sizes", "4096", "controllers"]
            if F == "e106_overrun_full"
                D("cnOvHybSkipPct", F, [C; "hyb_f25"; "refine_skipped_frac"], x -> fint(round(100x)), "E106 4096: team plan refined by V-FISTA, percent of steps where no refinement fit in the period")
                D("cnOvVfItersMax", F, [C; "vf_HS_shift"; "iters_max"], fint, "E106 4096: V-FISTA, most iterations completed in a step")
                for (a, k) in (("Hyb", "hyb_f25"), ("Vf", "vf_HS_shift"))
                    D("cnOv$(a)CostBig", F, [C; k; "cost_ratio_med"], x -> fsig(x; n = 3), "E106 4096 $k: closed-loop cost over converged centralized, median over seeds")
                    D("cnOv$(a)CostMaxBig", F, [C; k; "cost_ratio_max"], x -> fsig(x; n = 3), "E106 4096 $k: worst seed cost ratio")
                    D("cnOv$(a)MetBig", F, [C; k; "met_frac"], x -> fint(round(100x)), "E106 4096 $k: percent of steps within the period")
                    D("cnOv$(a)MsBig", F, [C; k; "ms_med"], fint, "E106 4096 $k: median ms per step"; reduce = round, reduce_name = "round")
                end
            end
            D("cnOvGenN", F, ["sizes"], fint, "E106: vehicles requested from the irregular-formation generator"; reduce = S -> parse(Int, only(keys(S))), reduce_name = "the requested size (the key of sizes)")
            D("cnOvN", F, ["sizes", "4096", "n"], fint, "E106 partial: vehicles, median over seeds"; reduce = x -> sort(x)[(length(x) + 1) ÷ 2], reduce_name = "median")
            D("cnOvStepsTimed", F, ["sizes", "4096", "steps"], fint, "E106: timed steps per run (the first, compiling, step is not timed)"; reduce = x -> x - 1, reduce_name = "steps - 1")
            D("cnOvClsEtaGap", F, [C; "team_resp_quarter"; "certified"; "eta_over_gap_med"], fsig, "E106: one team per region, certificate over the true gap at the measured state, median of per-seed medians")
            D("cnOvRtMsMaxBig", F, [C; "rt_admm"; "ms_max"], fint, "E106: centralized MPC stopped at the period, worst step ms"; reduce = round, reduce_name = "round")
            D("cnOvClsLossPct", F, [C; "team_resp_quarter"; "cost_ratio_med"], x -> fint(round(100 * (x - 1))), "E106 partial: one team per region, closed-loop cost above converged centralized, median, percent")
            D("cnOvClsTeams", F, [C; "team_resp_quarter"; "teams"], fint, "E106 partial: one team per region (type and shared reference), teams, median over seeds"; reduce = round, reduce_name = "round")
            D("cnOvSeeds", F, ["sizes", "4096", "seeds"], fint, "E106 partial: seeds"; reduce = length, reduce_name = "length")
            D("cnOvClsMetBig", F, [C; "team_resp_quarter"; "met_frac"], x -> fint(round(100x)), "E106 partial: one team per type, percent of steps within the period, certificate counted")
            D("cnOvClsCostBig", F, [C; "team_resp_quarter"; "cost_ratio_med"], x -> fsig(x; n = 3), "E106 partial: one team per type, closed-loop cost over converged centralized, median over seeds")
            D("cnOvClsEtaMsBig", F, [C; "team_resp_quarter"; "eta_ms_med"], fsig, "E106 partial: one team per type, certificate time, median ms")
            D("cnOvClsEtaViolBig", F, [C; "team_resp_quarter"; "certified"; "eta_below_gap"], fint, "E106 partial: steps with the certificate below the true gap")
            D("cnOvRtMetBig", F, [C; "rt_admm"; "met_frac"], x -> fint(round(100x)), "E106 partial: centralized MPC stopped at the period, percent of steps within the period")
            D("cnOvRtCostBig", F, [C; "rt_admm"; "cost_ratio_med"], x -> fsig(x; n = 3), "E106 partial: centralized MPC stopped at the period, cost ratio, median over seeds")
            D("cnOvClsCostMaxBig", F, [C; "team_resp_quarter"; "cost_ratio_max"], x -> fsig(x; n = 3), "E106: one team per region, closed-loop cost over converged centralized, worst seed")
            D("cnOvRtCostMaxBig", F, [C; "rt_admm"; "cost_ratio_max"], x -> fsig(x; n = 3), "E106: centralized MPC stopped at the period, cost ratio, worst seed")
            D("cnOvClsSolveMsBig", F, [C; "team_resp_quarter"; "solve_ms_med"], fint, "E106: one team per region, team solve alone, median ms per step"; reduce = round, reduce_name = "round")
            D("cnOvClsStepMsBig", F, [C; "team_resp_quarter"; "ms_med"], fint, "E106: one team per region, step with its certificate, median ms"; reduce = round, reduce_name = "round")
            D("cnOvClsMsMaxBig", F, [C; "team_resp_quarter"; "ms_max"], fint, "E106: one team per region, worst step ms"; reduce = ceil, reduce_name = "ceil")
            D("cnOvCoordMsBig", F, [C; "coord"; "ms_med"], fint, "E106: converged centralized MPC, median ms per step"; reduce = round, reduce_name = "round")
            D("cnOvRtMsBig", F, [C; "rt_admm"; "ms_med"], fint, "E106: centralized MPC stopped at the period, median ms per step"; reduce = round, reduce_name = "round")
            exrp(Cc) = [(r - 1) / (c - 1) for (r, c) in zip(Cc["rt_admm"]["cost_ratio_per_seed"], Cc["team_resp_quarter"]["cost_ratio_per_seed"])]
            D("cnOvClsWins", F, C, fint, "E106: seeds where one team per region had the lower closed-loop cost than centralized MPC stopped at the period";
              reduce = Cc -> count(>(1), exrp(Cc)), reduce_name = "count of seeds with (rt - 1) / (teams - 1) > 1")
            D("cnOvClsExcessRatioWinMin", F, C, fsig, "E106: over the seeds the teams won, the smallest ratio of excess costs (stopped centralized over teams)";
              reduce = Cc -> minimum(filter(>(1), exrp(Cc))), reduce_name = "min over winning seeds")
            D("cnOvLoseRtCost", F, C, x -> fsig(x; n = 3), "E106: the seed the teams lost, cost ratio of centralized MPC stopped at the period";
              reduce = Cc -> Cc["rt_admm"]["cost_ratio_per_seed"][argmin(exrp(Cc))], reduce_name = "rt cost at the seed with the smallest ratio")
            D("cnOvLoseClsCost", F, C, x -> fsig(x; n = 3), "E106: the seed the teams lost, cost ratio of one team per region";
              reduce = Cc -> Cc["team_resp_quarter"]["cost_ratio_per_seed"][argmin(exrp(Cc))], reduce_name = "team cost at the seed with the smallest ratio")
            D("cnOvClsExcessRatioMin", F, C, fsig, "E106 partial: excess cost of the stopped centralized solver over that of one team per type, smallest over seeds";
              reduce = Cc -> minimum((r - 1) / (c - 1) for (r, c) in zip(Cc["rt_admm"]["cost_ratio_per_seed"], Cc["team_resp_quarter"]["cost_ratio_per_seed"])),
              reduce_name = "min over seeds of (rt - 1) / (types - 1)")
        end

        # ---------------------------------------------------------------- E52 at 1024 vehicles, 10 ADMM iterations
        if sim_has("e52_admm")
            L1 = ["sizes", "1024", "loops"]
            D("cnAdmmFullParMs", "e52_admm", [L1; "full_b10"; "par_ms_med"], fsig, "ADMM on the fleet, 10 iterations, 1024 vehicles, parallel ms per sample (median)")
            D("cnAdmmFullParMsMax", "e52_admm", [L1; "full_b10"; "par_ms_max"], fsig, "the same, largest")
            D("cnAdmmFullRounds", "e52_admm", [L1; "full_b10"; "rounds"], fint, "ADMM on the fleet, 10 iterations: message rounds per sample")
            D("cnAdmmFullKfloats", "e52_admm", [L1; "full_b10"; "floats_med"], fint, "ADMM on the fleet, 10 iterations, 1024 vehicles: thousand floats per sample"; reduce = x -> x / 1000, reduce_name = "/1000")
            D("cnAdmmFullCost", "e52_admm", [L1; "full_b10"; "cost_ratio_max"], f3, "ADMM on the fleet, 10 iterations: closed-loop cost over coordinated MPC, largest")
            D("cnAdmmOneRoundCost", "e52_admm", [L1; "full_b1"; "cost_ratio_med"], x -> fsig(x; n = 4), "ADMM on the fleet, 1 iteration: closed-loop cost over coordinated MPC, median")
            D("cnAdmmQuotRounds", "e52_admm", [L1; "quot_b10"; "rounds"], fint, "ADMM on the team program, 10 iterations: message rounds per sample")
            D("cnAdmmQuotKfloats", "e52_admm", [L1; "quot_b10"; "floats_med"], fint, "ADMM on the team program, 10 iterations, 1024 vehicles: thousand floats per sample"; reduce = x -> x / 1000, reduce_name = "/1000")
            D("cnAdmmFullKfloatsFourK", "e52_admm", ["sizes", "4096", "loops", "full_b10", "floats_med"], fint, "ADMM on the fleet, 10 iterations, 4096 vehicles: thousand floats per sample"; reduce = x -> x / 1000, reduce_name = "/1000")
            D("cnAdmmFullParMsFourK", "e52_admm", ["sizes", "4096", "loops", "full_b10", "par_ms_med"], fsig, "ADMM on the fleet, 10 iterations, 4096 vehicles: parallel ms per sample (median)")
            D("cnAdmmFullCostQuarter", "e52_admm", ["sizes", "256", "loops", "full_b10", "cost_ratio_max"], f3, "ADMM on the fleet, 10 iterations, 256 vehicles: closed-loop cost over coordinated, largest")
            D("cnAdmmCentralKfloats", "e52_admm", ["sizes", "1024"], fint, "central team MPC at 1024 vehicles: thousand floats per sample (6n up, 3n down)"; reduce = _ -> 9 * 1024 / 1000, reduce_name = "9 n / 1000")
        end
    end
end
