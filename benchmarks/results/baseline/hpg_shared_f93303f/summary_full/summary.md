# Benchmark summary

Sources: results/hpg_fa5390d/full_20261018_fa5390d7c2_shared, results/hpg_fa5390d/full_20261018_fa5390d7c2_shared/mumblebee_fast, results/hpg_fa5390d/full_20261018_fa5390d7c2_shared/mumblebee_fast_ct; 62 instances.

## Setup

- host `c0706a-s19.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0705a-s5.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0706a-s22.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0701a-s1.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0700a-s16.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0701a-s6.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0700a-s5.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- Julia 1.12.6, 1 thread, BLAS threads 1; governor ``, boost ``
- 1-minute load before each instance: median 146.6, max 422.9; gate passed 62, timed out 0, skipped 0
- **clarabel**: package: Clarabel.jl; settings: tol_gap_abs = tol_gap_rel = tol_feas = eps, tol_ktratio = min(1e-6, eps), presolve off, equilibration on (default), max_iter 500; version: 0.11.1; warm_start: none (interior point); sequence mode reuses the setup through update_q!/update_b!
- **hpipm**: blasfeo_target: X64_AUTOMATIC (X64_INTEL_HASWELL); build: acados 00947dd (cmake); hpipm_commit: bad1123; hpipm_target: GENERIC; infinite_bounds: dropped if both sides infinite, else masked; iter_max: 1000; lib_dir: /blue/fairbanksj/itaykadosh/central_bench/acados/lib; solver: HPIPM; tolerances: tol_stat = tol_eq = tol_ineq = tol_comp = eps; warm_start: 0; x0: eliminated (stage 0 has nx = 0)
- **mumblebee**: cliquetrees: {"commit":"registry release","path":"/blue/fairbanksj/itaykadosh/julia_depot/packages/CliqueTrees/8e1Ca","version":"1.19.7"}; commit: e78d9b9a3a0a2f4c226bf2eb0cf20f662e7d676b (pinned as in the paper's bench/mpc); package: Mumblebee; path: /blue/fairbanksj/itaykadosh/julia_depot/packages/Mumblebee/NtQeH; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: none (no IPMSymbolic in this version): rebuild redoes the ordering and symbolic factorization; warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **mumblebee_fast**: cliquetrees: {"commit":"registry release","path":"/blue/fairbanksj/itaykadosh/julia_depot/packages/CliqueTrees/8e1Ca","version":"1.19.7"}; commit: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"9416b46f1085901406583675a7257507988c2983"}; package: Mumblebee; path: /blue/fairbanksj/itaykadosh/sheafmpc_bench/refs/fa5390d7c2/Mumblebee.jl; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: IPMSymbolic built at setup; rebuild strategy reuses it (init(prob, st; symb)); warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **mumblebee_fast_ct**: cliquetrees: {"commit":"0015e2b (itay/fast-symbolic, exported with git archive)","path":"/blue/fairbanksj/itaykadosh/sheafmpc_bench/CliqueTrees-fast-0015e2b","version":"1.19.6"}; commit: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"9416b46f1085901406583675a7257507988c2983"}; package: Mumblebee; path: /blue/fairbanksj/itaykadosh/sheafmpc_bench/refs/fa5390d7c2/Mumblebee.jl; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: IPMSymbolic built at setup; rebuild strategy reuses it (init(prob, st; symb)); warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **osqp**: library: 0.6.2; package: OSQP.jl; settings: eps_abs = eps_rel = eps, adaptive_rho on with OSQP's default interval 0 (chosen from measured setup time, so iteration counts vary run to run), polish per variant with 3 refinement steps, max_iter 400000, scaling 10 (default); version: 0.8.1; warm_start: setup with warm_start = false (cold); warm mode: update! (factorization kept) + warm_start!(x, y) from the shifted previous solution, which turns warm starting on
- **piqp**: blasfeo: giaf/blasfeo 0a3df8683c6bf9d98168d616e0c5d05938c9d51c (0.1.4.3-91), TARGET=X64_INTEL_HASWELL, static; build_info: PIQP 5d849590a18bc7f0b449057e5f2041713a85003c built on c0702a-s16.ufhpc (AMD EPYC 7702 64-Core Processor), gcc 12.2.0, -O3 -march=native, BLASFEO X64_INTEL_HASWELL static, Eigen 3.4.0, job 46521806
; commit: 5d849590a18bc7f0b449057e5f2041713a85003c; compile_flags: CMAKE_BUILD_TYPE=Release, CMAKE_CXX_FLAGS_RELEASE='-O3 -march=native -DNDEBUG', BUILD_C_INTERFACE=ON, BUILD_SHARED_LIBS=ON, BUILD_WITH_TEMPLATE_INSTANTIATION=OFF, BUILD_WITH_BLASFEO=ON, link '-Wl,--exclude-libs,ALL'; compiler: GCC 13.3.0; eigen: 3.4.0; library: /blue/fairbanksj/itaykadosh/sheafmpc_bench/tools/piqp-install/lib/libpiqpc.so; mapping: l == u rows -> A x = b; single-nonzero rows -> variable bounds (tightest wins); other rows -> h_l <= G x <= h_u; free rows dropped; note: PIQP_LIB overrides the default; build fields describe the default library; package: PIQP (C interface, in-process ccall); python_wheels: piqp 0.6.4, osqp 1.1.3 (~/tools/bench-venv); repo: https://github.com/PREDICT-EPFL/piqp (tag v0.6.4); settings: defaults of piqp_set_default_settings_sparse, then eps_abs = eps_duality_gap_abs = eps, eps_rel = eps_duality_gap_rel = 0, max_iter = 500, verbose off, compute_timings off; version: 0.6.4; warm_start: none (interior point); sequence mode uses piqp_update_sparse with vectors only
- **sheafmpc**: git: {"diff_sha1":"","dirty":false,"dirty_files":[],"ref":"master@1e48122e1511e79825a0d6174970fe91f7d2900d","sha":"fa5390d7c2266c74ce063d47218494db90a041f5","source":"git archive snapshot (PACKAGE_REF)"}; package: SheafMPC; path: /blue/fairbanksj/itaykadosh/sheafmpc_bench/refs/fa5390d7c2/SheafMPC.jl; settings: package defaults (SheafMPC.Settings()), eps_abs = eps_rel = eps, max_iter 100000; warm_start: update! (factorization kept, objective constant c passed) + warm_start!(x, y) from the shifted previous solution

Protocol: accuracy tiers low 1e-3, medium 1e-6, high 1e-9 (relative objective error and relative primal residual against the reference, one shared checker on the unscaled problem); tolerance and variant calibrated per solver and instance on the first, middle and last QP; per-QP time is the median over the repeats; warm statistics exclude the first (cold) QP of the sequence. `--` means not applicable, or no QP met the tier. `f/n` = QPs missing the tier.

## chain

### chain, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.735 | 0.140 | 1.44 | 0.833 | 0.900 | 0.452 | 0.339 | 0.263 | 1.89 (hpipm) | 0.32 |
| chain_M4 | 220 | 1.22 | 0.166 | 2.22 | 1.24 | 1.37 | 0.715 | 0.463 | 0.549 | 3.31 (hpipm) | 0.44 |
| chain_M6 | 340 | 2.20 | 0.268 | 3.89 | 2.12 | 2.10 | 1.35 | 0.694 | 1.62 | 6.03 (hpipm) | 0.76 |
| chain_M8 | 460 | 3.57 | 0.407 | 5.77 | 3.43 | 3.24 | 2.11 | 1.01 | 2.06 | 5.06 (hpipm) | 0.60 |
| chain_M10 | 580 | 5.68 | 0.674 | 8.14 | 4.48 | 4.28 | 3.17 | 1.55 | 3.26 | 4.83 (hpipm) | 0.73 |

Cold cells: median ms of the solve; setup is separate.

### chain, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.05 | 0.159 | 1.85 | 1.24 | 1.26 | 0.442 | 0.405 | 0.259 | 1.62 (hpipm) | 0.21 |
| chain_M4 | 220 | 1.57 | 0.207 | 2.90 | 1.71 | 1.60 | 0.739 | 0.496 | 0.712 | 3.44 (hpipm) | 0.42 |
| chain_M6 | 340 | 2.95 | 0.332 | 5.70 | 3.36 | 3.02 | 1.30 | 0.833 | 1.62 | 4.88 (hpipm) | 0.48 |
| chain_M8 | 460 | 5.29 | 0.560 | 8.65 | 4.93 | 4.67 | 2.11 | 1.31 | 2.08 | 3.72 (hpipm) | 0.42 |
| chain_M10 | 580 | 7.56 | 0.893 | 10.95 | 6.01 | 5.67 | 3.23 | 1.96 | 3.31 | 3.70 (hpipm) | 0.55 |

Cold cells: median ms of the solve; setup is separate.

### chain, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.23 | 0.179 | 2.39 [1/5] | 1.51 [1/5] | 1.43 [1/5] | 0.654 | 0.499 | 0.258 | 1.44 (hpipm) | -- |
| chain_M4 | 220 | 1.86 | 0.231 | 3.35 | 1.88 | 1.80 | 1.01 | 0.606 | 0.675 | 2.93 (hpipm) | 0.36 |
| chain_M6 | 340 | 3.54 | 0.447 | 6.35 [1/5] | 3.65 [1/5] | 3.40 [1/5] | 1.87 | 0.905 | 1.55 | 3.47 (hpipm) | -- |
| chain_M8 | 460 | 6.40 | 0.628 [1/5] | 9.73 | 5.52 | 5.35 | 3.00 | 1.42 | 2.08 | 1.47 (piqp) | 0.38 |
| chain_M10 | 580 | 9.06 | 0.912 | 13.57 [3/5] | 6.93 [3/5] | 6.71 [3/5] | 4.55 | 2.13 | 3.33 | 3.65 (hpipm) | -- |

Cold cells: median ms of the solve; setup is separate.

### chain, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.657 (0.681) | 0.106 (0.117) | 1.30 (1.40) | 0.842 (0.884) | 0.814 (0.899) | 0.211 (0.219) | 0.324 (0.356) | 0.198 (0.279) | 1.86 (hpipm) | 0.23 |
| chain_M4 | 220 | 1.11 (1.14) | 0.145 (0.155) | 1.93 (2.05) | 1.13 (1.17) | 1.16 (1.24) | 0.343 (0.711) [1/11] | 0.386 (0.456) | 0.257 (0.357) | 1.76 (hpipm) | 0.23 |
| chain_M6 | 340 | 2.16 (2.19) | 0.262 (0.272) [1/11] | 3.55 (3.63) [1/11] | 1.99 (2.09) [1/11] | 1.89 (1.93) [1/11] | 0.612 (0.641) | 0.540 (0.674) | 0.755 (1.11) | 1.40 (piqp) | -- |
| chain_M8 | 460 | 3.51 (3.56) | 0.410 (0.433) [3/11] | 5.39 (5.46) [3/11] | 3.06 (3.14) [3/11] | 2.82 (2.83) [3/11] | 0.967 (1.01) | 0.804 (0.984) | 1.02 (1.46) | 1.27 (piqp) | -- |
| chain_M10 | 580 | 5.56 (5.64) | 0.634 (0.670) | 7.96 (8.02) [2/11] | 4.23 (4.33) [2/11] | 3.84 (3.96) [2/11] | 1.39 (1.49) | 1.22 (1.44) | 1.48 (2.07) | 2.34 (hpipm) | -- |

Warm cells: median (max) ms.

### chain, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.897 (1.01) | 0.139 (0.155) | 1.79 (1.99) [1/11] | 1.13 (1.26) [1/11] | 1.05 (1.21) [1/11] | 0.407 (0.413) | 0.376 (0.443) | 0.199 (0.281) | 1.44 (hpipm) | -- |
| chain_M4 | 220 | 1.44 (1.60) | 0.167 (0.190) | 6.97 (7.34) | 1.53 (1.92) | 1.50 (1.89) | 0.672 (1.06) | 0.464 (0.600) | 0.314 (0.373) | 1.88 (hpipm) | 0.20 |
| chain_M6 | 340 | 2.82 (3.20) | 0.315 (0.343) [1/11] | 4.86 (5.60) [1/11] | 2.76 (3.09) [1/11] | 2.57 (2.88) [1/11] | 1.21 (1.89) | 0.691 (0.790) | 0.733 (1.00) | 1.06 (piqp) | -- |
| chain_M8 | 460 | 4.80 (5.43) | 0.522 (0.612) | 34.59 (35.68) [1/11] | 4.09 (4.64) [1/11] | 3.87 (4.38) [1/11] | 1.89 (2.90) | 1.07 (1.32) | 1.02 (1.58) | 1.96 (hpipm) | -- |
| chain_M10 | 580 | 7.47 (8.45) | 0.768 (0.824) [3/11] | 10.79 (10.88) [3/11] | 5.72 (5.81) [3/11] | 5.23 (5.30) [3/11] | 2.74 (4.32) | 1.68 (1.78) | 1.48 (2.02) | 0.88 (piqp) | -- |

Warm cells: median (max) ms.

### chain, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.09 (1.18) | 0.153 (0.182) [1/11] | 4.21 (4.46) [5/11] | 1.38 (1.56) [5/11] | 1.24 (1.39) [5/11] | 0.576 (0.596) | 0.418 (0.513) | 0.188 (0.267) | 0.45 (piqp) | -- |
| chain_M4 | 220 | 1.64 (2.17) | 0.198 (0.247) | 7.33 (7.72) | 1.73 (2.17) | 1.69 (2.07) | 0.971 (1.05) | 0.567 (0.731) | 0.318 (0.377) | 1.61 (hpipm) | 0.18 |
| chain_M6 | 340 | 3.38 (3.77) | 0.339 (0.418) | 17.64 (18.20) [2/11] | 3.16 (3.46) [2/11] | 2.90 (3.25) [2/11] | 1.81 (1.90) | 0.787 (0.959) | 0.706 (0.963) | 2.09 (hpipm) | -- |
| chain_M8 | 460 | 5.79 (6.99) | 0.547 (0.627) [3/11] | 36.59 (38.54) | 5.19 (6.26) | 4.89 (5.86) | 1.88 (2.90) | 1.24 (1.55) | 1.02 (1.51) | 0.82 (piqp) | 0.20 |
| chain_M10 | 580 | 9.02 (10.06) | 0.868 (1.08) | 65.93 (67.35) [6/11] | 5.61 (7.10) [6/11] | 5.29 (6.64) [6/11] | 2.81 (4.42) | 1.82 (1.92) | 1.52 (2.06) | 1.75 (hpipm) | -- |

Warm cells: median (max) ms.

### chain, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 5 / 8 / -- / 10 | 5 / 7 / -- / 9 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 50 / 50 / -- / 75 | 6 / 8 / -- / 10 | 30 / 30 / -- / 30 |
| chain_M4 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 50 / 50 / -- / 75 | 6 / 7 / -- / 9 | 30 / 30 / -- / 30 |
| chain_M6 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 50 / 50 / -- / 75 | 6 / 8 / -- / 9 | 40 / 40 / -- / 40 |
| chain_M8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 9 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 50 / 50 / -- / 75 | 6 / 8 / -- / 9 | 30 / 30 / -- / 30 |
| chain_M10 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 50 / 50 / -- / 75 | 6 / 8 / -- / 9 | 40 / 40 / -- / 40 |

### chain, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 25 / 50 / -- / 75 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| chain_M4 | 5 / 7 / -- / 8 | 5 / 6 / -- / 7 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 25 / 50 / -- / 75 | 5 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| chain_M6 | 5 / 7 / -- / 9 | 5 / 6 / -- / 7 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |
| chain_M8 | 5 / 7 / -- / 9 | 4 / 7 / -- / 7 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 50 | 5 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| chain_M10 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 5 / 8 / -- / 9 | 5 / 8 / -- / 9 | 5 / 8 / -- / 9 | 25 / 50 / -- / 50 | 5 / 8 / -- / 9 | 0 / 0 / -- / 0 |

### chain, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 0.418 | 0.159 | 2.27 | 0.636 | 0.763 | 0.254 | 0.366 | 3.02 |
| chain_M4 | 0.652 | 0.179 | 4.47 | 1.07 | 1.02 | 0.437 | 0.549 | 4.78 |
| chain_M6 | 1.02 | 0.148 | 12.84 | 2.27 | 2.14 | 0.745 | 0.951 | 8.28 |
| chain_M8 | 1.56 | 0.189 | 27.86 | 3.84 | 3.74 | 1.22 | 1.55 | 13.16 |
| chain_M10 | 2.56 | 0.322 | 52.90 | 6.35 | 6.08 | 1.93 | 2.57 | 20.27 |

## fleet_grid_box

### fleet_grid_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.302 | 0.068 | 0.989 | 0.112 [2/6] | 0.093 | 0.076 | 1.10 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.11 | 0.579 [4/6] | 4.22 | 2.17 | 0.702 | 1.38 | 1.97 (piqp) |
| fleet_grid_box_n16 | 2240 | 15.31 | 8.54 | 19.66 | 11.91 | 12.13 | 8.19 | 0.96 (hpipm) |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.423 | 0.080 | 1.34 | 0.483 [2/6] | 0.110 | 0.075 | 0.94 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.83 | 0.831 | 5.63 | 4.35 | 0.999 | 1.36 | 1.64 (hpipm) |
| fleet_grid_box_n16 | 2240 | 22.01 | 10.96 | 28.57 | 25.47 [1/6] | 15.99 | 8.23 | 0.75 (hpipm) |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.501 | 0.090 [1/6] | 1.65 | 1.03 [1/6] | 0.141 | 0.074 | 0.53 (piqp) |
| fleet_grid_box_n4 | 560 | 3.31 | 0.725 | 6.77 | 6.94 | 1.18 | 1.49 | 2.06 (hpipm) |
| fleet_grid_box_n16 | 2240 | 25.93 | 12.52 | 32.64 | 56.72 | 19.76 | 8.29 | 0.66 (hpipm) |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.298 (0.410) | 0.072 (0.081) | 1.24 (1.48) | 0.215 (0.221) [8/11] | 0.098 (0.131) [1/11] | 0.107 (0.168) | 1.49 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.03 (2.26) | 0.585 (0.685) [5/11] | 5.10 (6.27) | 1.13 (1.67) | 0.770 (0.940) | 0.999 (1.75) | 1.30 (piqp) |
| fleet_grid_box_n16 | 2240 | 19.44 (21.74) | 8.85 (10.76) | 24.89 (27.33) | 9.09 (17.48) | 14.24 (15.87) | 8.57 (10.51) | 0.97 (hpipm) |

Warm cells: median (max) ms.

### fleet_grid_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.407 (0.475) | 0.083 (0.088) | 1.47 (1.73) | 0.417 (0.729) | 0.134 (0.171) | 0.103 (0.166) | 1.24 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.86 (2.92) | 0.726 (0.800) | 6.19 (7.35) | 3.67 (5.62) | 1.03 (1.14) | 0.983 (1.80) | 1.35 (hpipm) |
| fleet_grid_box_n16 | 2240 | 23.86 (28.16) | 12.01 (13.20) | 30.18 (38.04) | 21.68 (23.30) [5/11] | 16.75 (21.24) | 8.57 (12.89) | 0.71 (hpipm) |

Warm cells: median (max) ms.

### fleet_grid_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.500 (0.553) | 0.084 (0.093) [1/11] | 1.75 (1.89) | 0.765 (1.02) [1/11] | 0.164 (0.198) | 0.106 (0.170) | 0.65 (piqp) |
| fleet_grid_box_n4 | 560 | 3.34 (3.43) | 0.731 (0.807) [1/11] | 7.38 (8.39) | 6.13 (8.09) | 1.16 (1.29) | 0.998 (1.81) | 0.86 (piqp) |
| fleet_grid_box_n16 | 2240 | 28.14 (32.79) | 12.17 (13.04) | 35.28 (40.58) | 40.12 (67.37) [3/11] | 19.74 (22.63) | 8.49 (12.81) | 0.70 (hpipm) |

Warm cells: median (max) ms.

### fleet_grid_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 4 / 6 / -- / 7.5 | 5 / 6.5 / -- / 7.5 | 6 / 8.5 / -- / 10 | 25 / 137.5 / -- / 250 | 4 / 5 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_grid_box_n4 | 6 / 8.5 / -- / 10 | 5 / 9 / -- / 10 | 7.5 / 10 / -- / 12 | 100 / 212.5 / -- / 312.5 | 5.5 / 9 / -- / 10 | 55 / 60 / -- / 60 |
| fleet_grid_box_n16 | 6 / 9 / -- / 11 | 7 / 9.5 / -- / 11 | 8 / 11.5 / -- / 13 | 100 / 200 / -- / 487.5 | 7 / 9.5 / -- / 12 | 50 / 50 / -- / 50 |

### fleet_grid_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 4 / 6 / -- / 8 | 6 / 8 / -- / 8 | 8 / 9 / -- / 11 | 25 / 100 / -- / 150 | 4 / 6 / -- / 8 | 20 / 20 / -- / 20 |
| fleet_grid_box_n4 | 6 / 9 / -- / 11 | 7 / 10 / -- / 11 | 9 / 11 / -- / 13 | 50 / 175 / -- / 275 | 6 / 9 / -- / 11 | 40 / 40 / -- / 40 |
| fleet_grid_box_n16 | 8 / 10 / -- / 12 | 8 / 11 / -- / 13 | 10 / 12 / -- / 14 | 75 / 175 / -- / 350 | 8 / 10 / -- / 12 | 50 / 50 / -- / 50 |

### fleet_grid_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 0.249 | 0.092 | 0.609 | 0.134 | 0.095 | 1.47 |
| fleet_grid_box_n4 | 0.983 | 0.182 | 2.34 | 0.665 | 0.417 | 8.03 |
| fleet_grid_box_n16 | 4.08 | 1.10 | 9.05 | 3.63 | 1.92 | 45.00 |

## fleet_grid_box_b4

### fleet_grid_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.247 | 0.663 | 0.412 | 0.392 | 0.110 [1/6] | 0.065 | 0.050 | 0.77 (piqp) | 0.12 |
| fleet_grid_box_b4_n4 | 272 | 1.49 | 3.42 | 2.22 | 2.17 | 1.09 | 0.564 | 0.744 | 1.32 (piqp) | 0.33 |
| fleet_grid_box_b4_n16 | 1088 | 14.41 | 18.00 | 12.70 | 11.79 | 8.67 [1/6] | 9.43 | 5.02 | 0.53 (piqp) | 0.39 |
| fleet_grid_box_b4_n64 | 4352 | 270 | 108 | 88.33 | 83.89 | 221 | 347 | 36.75 | 0.44 (mumblebee_fast_ct) | 0.42 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.300 | 0.805 | 0.597 | 0.506 | 0.317 | 0.074 | 0.049 | 0.66 (piqp) | 0.08 |
| fleet_grid_box_b4_n4 | 272 | 2.12 | 4.49 | 2.98 | 2.88 | 3.17 | 0.826 | 0.875 | 1.06 (piqp) | 0.29 |
| fleet_grid_box_b4_n16 | 1088 | 18.45 | 25.62 | 18.21 | 16.86 | 29.53 [2/6] | 12.34 | 4.87 | 0.40 (piqp) | 0.27 |
| fleet_grid_box_b4_n64 | 4352 | 336 | 145 | 118 | 112 | 527 [1/6] | 395 | 37.90 | 0.34 (mumblebee_fast_ct) | 0.32 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.359 | 0.933 | 0.732 | 0.591 | 0.486 | 0.098 | 0.048 | 0.49 (piqp) | 0.07 |
| fleet_grid_box_b4_n4 | 272 | 2.49 | 5.19 | 3.54 | 3.35 | 4.65 | 0.943 | 0.956 | 1.01 (piqp) | 0.27 |
| fleet_grid_box_b4_n16 | 1088 | 22.29 | 29.11 | 20.81 | 19.06 | 44.93 [1/6] | 15.48 | 4.85 | 0.31 (piqp) | 0.23 |
| fleet_grid_box_b4_n64 | 4352 | 400 | 178 | 141 | 134 | 765 [1/6] | 398 | 38.14 | 0.28 (mumblebee_fast_ct) | 0.27 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.263 (0.302) | 0.742 (0.840) | 0.542 (0.614) | 0.474 (0.576) | 0.105 (0.113) [1/11] | 0.068 (0.088) | 0.054 (0.141) | 0.79 (piqp) | 0.10 |
| fleet_grid_box_b4_n4 | 272 | 1.66 (2.02) | 3.87 (5.01) | 2.60 (3.19) | 2.41 (2.96) | 0.928 (1.23) | 0.606 (0.780) | 0.547 (1.18) | 0.90 (piqp) | 0.21 |
| fleet_grid_box_b4_n16 | 1088 | 17.23 (19.27) | 22.00 (24.28) | 15.40 (17.10) | 14.36 (15.80) | 4.35 (6.48) [5/11] | 10.55 (11.75) | 3.82 (7.14) | 0.36 (piqp) | 0.25 |
| fleet_grid_box_b4_n64 | 4352 | 289 (352) | 137 (152) | 114 (127) | 106 (118) | 108 (320) | 341 (418) | 39.05 (94.07) | 0.37 (mumblebee_fast_ct) | 0.34 |

Warm cells: median (max) ms.

### fleet_grid_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.308 (0.379) | 0.857 (1.04) | 0.641 (0.828) | 0.568 (0.678) | 0.248 (0.399) | 0.088 (0.108) | 0.061 (0.141) | 0.70 (piqp) | 0.10 |
| fleet_grid_box_b4_n4 | 272 | 2.24 (2.44) | 4.77 (5.71) | 3.27 (3.78) | 3.03 (3.56) | 2.04 (4.24) [1/11] | 0.845 (0.940) | 0.524 (1.15) | 0.62 (piqp) | 0.16 |
| fleet_grid_box_b4_n16 | 1088 | 20.86 (26.31) | 26.94 (33.43) | 18.95 (23.77) | 17.45 (21.81) | 28.16 (33.78) [2/11] | 12.91 (15.41) | 3.97 (7.79) | 0.31 (piqp) | 0.21 |
| fleet_grid_box_b4_n64 | 4352 | 380 (472) | 182 (197) | 149 (162) | 140 (152) | 432 (507) | 465 (543) | 39.44 (95.77) | 0.28 (mumblebee_fast_ct) | 0.27 |

Warm cells: median (max) ms.

### fleet_grid_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.359 (0.422) | 1.30 (1.38) | 0.762 (0.867) | 0.649 (0.746) | 0.398 (0.612) [1/11] | 0.105 (0.123) | 0.059 (0.140) | 0.56 (piqp) | 0.08 |
| fleet_grid_box_b4_n4 | 272 | 2.64 (2.97) | 5.80 (6.77) | 3.76 (4.29) | 3.55 (4.09) | 3.51 (4.94) | 0.987 (1.05) | 0.513 (1.19) | 0.52 (piqp) | 0.14 |
| fleet_grid_box_b4_n16 | 1088 | 24.94 (30.14) | 31.34 (35.75) | 22.03 (25.53) | 20.53 (23.38) | 59.74 (90.28) [1/11] | 15.67 (18.23) | 3.94 (7.73) | 0.25 (piqp) | 0.18 |
| fleet_grid_box_b4_n64 | 4352 | 434 (527) | 205 (238) | 160 (184) | 151 (175) | 854 (1576) [1/11] | 516 (632) | 39.70 (96.92) | 0.26 (mumblebee_fast_ct) | 0.25 |

Warm cells: median (max) ms.

### fleet_grid_box_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 5 / 6.5 / -- / 8 | 6 / 8.5 / -- / 10 | 6 / 8.5 / -- / 10 | 6 / 8.5 / -- / 10 | 50 / 125 / -- / 225 | 4 / 5 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_grid_box_b4_n4 | 6 / 9 / -- / 11 | 7.5 / 10 / -- / 12 | 7.5 / 10 / -- / 12 | 7.5 / 10 / -- / 12 | 87.5 / 262.5 / -- / 400 | 5.5 / 9 / -- / 10.5 | 50 / 50 / -- / 50 |
| fleet_grid_box_b4_n16 | 7 / 9.5 / -- / 11.5 | 8 / 11.5 / -- / 13 | 8 / 11.5 / -- / 13 | 8 / 11.5 / -- / 13 | 100 / 312.5 / -- / 537.5 | 7 / 9.5 / -- / 11.5 | 50 / 50 / -- / 50 |
| fleet_grid_box_b4_n64 | 7 / 9 / -- / 11 | 8 / 10.5 / -- / 12.5 | 8 / 10.5 / -- / 12.5 | 8 / 10.5 / -- / 12.5 | 250 / 500 / -- / 850 | 8 / 10 / -- / 11.5 | 75 / 75 / -- / 75 |

### fleet_grid_box_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 6 / 7 / -- / 9 | 8 / 9 / -- / 11 | 8 / 9 / -- / 11 | 8 / 9 / -- / 11 | 50 / 100 / -- / 200 | 4 / 6 / -- / 8 | 20 / 20 / -- / 20 |
| fleet_grid_box_b4_n4 | 7 / 10 / -- / 12 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 75 / 175 / -- / 300 | 6 / 9 / -- / 11 | 20 / 20 / -- / 20 |
| fleet_grid_box_b4_n16 | 9 / 11 / -- / 13 | 10 / 12 / -- / 14 | 10 / 12 / -- / 14 | 10 / 12 / -- / 14 | 50 / 275 / -- / 550 | 8 / 10 / -- / 12 | 40 / 40 / -- / 40 |
| fleet_grid_box_b4_n64 | 8 / 11 / -- / 13 | 10 / 13 / -- / 14 | 10 / 13 / -- / 14 | 10 / 13 / -- / 14 | 150 / 475 / -- / 1050 | 9 / 11 / -- / 12 | 80 / 80 / -- / 80 |

### fleet_grid_box_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 0.172 | 0.467 | 0.256 | 0.272 | 0.096 | 0.056 | 0.876 |
| fleet_grid_box_b4_n4 | 0.676 | 1.95 | 1.13 | 1.17 | 0.448 | 0.332 | 5.17 |
| fleet_grid_box_b4_n16 | 2.80 | 7.51 | 5.20 | 5.23 | 2.77 | 0.941 | 31.39 |
| fleet_grid_box_b4_n64 | 13.79 | 31.98 | 23.35 | 23.17 | 36.64 | 4.95 | 332 |

## fleet_grid_soc

### fleet_grid_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.420 | 0.685 | 0.648 | 0.137 | 0.33 (clarabel) | 0.21 |
| fleet_grid_soc_n4 | 560 | 2.71 | 4.30 | 3.87 | 2.05 | 0.76 (clarabel) | 0.53 |
| fleet_grid_soc_n16 | 2240 | 57.38 | 33.26 | 30.69 | 19.65 | 0.64 (mumblebee_fast) | 0.64 |
| fleet_grid_soc_n64 | 8960 | 695 | 244 | 234 | 328 | 1.40 (mumblebee_fast) | 1.40 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.633 | 1.06 | 0.929 | 0.167 | 0.26 (clarabel) | 0.18 |
| fleet_grid_soc_n4 | 560 | 4.17 | 6.28 | 5.57 | 2.41 | 0.58 (clarabel) | 0.43 |
| fleet_grid_soc_n16 | 2240 | 86.85 | 47.16 | 43.37 | 23.10 | 0.53 (mumblebee_fast) | 0.53 |
| fleet_grid_soc_n64 | 8960 | 1052 | 351 | 336 | 360 | 1.07 (mumblebee_fast) | 1.07 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.712 | 1.19 | 1.06 | 0.186 | 0.26 (clarabel) | 0.18 |
| fleet_grid_soc_n4 | 560 | 5.12 | 7.56 | 6.81 | 2.64 | 0.52 (clarabel) | 0.39 |
| fleet_grid_soc_n16 | 2240 | 107 | 56.00 | 51.52 | 24.35 | 0.47 (mumblebee_fast) | 0.47 |
| fleet_grid_soc_n64 | 8960 | 1392 | 459 | 442 | 379 | 0.86 (mumblebee_fast) | 0.86 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.712 | 1.29 | 1.12 | 0.186 | 0.26 (clarabel) | 0.17 |
| fleet_grid_soc_n4 | 560 | 5.47 | 8.38 | 7.32 | 2.70 | 0.49 (clarabel) | 0.37 |
| fleet_grid_soc_n16 | 2240 | 118 | 61.19 | 55.90 | 24.70 | 0.44 (mumblebee_fast) | 0.44 |
| fleet_grid_soc_n64 | 8960 | 1473 | 506 | 493 | 374 | 0.76 (mumblebee_fast) | 0.76 |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.421 (0.502) | 0.911 (0.947) | 0.810 (0.852) | 0.165 (0.244) | 0.39 (clarabel) | 0.20 |
| fleet_grid_soc_n4 | 560 | 2.69 (3.12) | 5.49 (6.16) | 4.90 (5.54) | 1.83 (3.01) | 0.68 (clarabel) | 0.37 |
| fleet_grid_soc_n16 | 2240 | 36.31 (42.91) | 32.93 (41.88) | 30.66 (39.14) | 16.26 (28.54) | 0.53 (mumblebee_fast) | 0.53 |
| fleet_grid_soc_n64 | 8960 | 575 (665) | 296 (298) | 287 (289) | 325 (499) | 1.13 (mumblebee_fast) | 1.13 |

Warm cells: median (max) ms.

### fleet_grid_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.626 (0.688) | 1.10 (1.22) | 0.937 (1.08) | 0.230 (0.272) | 0.37 (clarabel) | 0.25 |
| fleet_grid_soc_n4 | 560 | 4.11 (4.58) | 7.49 (8.82) | 6.59 (7.90) | 1.94 (3.36) | 0.47 (clarabel) | 0.29 |
| fleet_grid_soc_n16 | 2240 | 55.38 (61.76) | 46.66 (51.49) | 43.43 (47.62) | 20.25 (28.42) | 0.47 (mumblebee_fast) | 0.47 |
| fleet_grid_soc_n64 | 8960 | 832 (910) | 406 (444) | 389 (426) | 371 (588) | 0.95 (mumblebee_fast) | 0.95 |

Warm cells: median (max) ms.

### fleet_grid_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.713 (0.809) | 1.22 (1.36) | 1.08 (1.17) | 0.229 (0.273) | 0.32 (clarabel) | 0.21 |
| fleet_grid_soc_n4 | 560 | 4.96 (5.50) | 8.15 (10.86) | 7.31 (9.62) | 2.25 (3.28) | 0.45 (clarabel) | 0.31 |
| fleet_grid_soc_n16 | 2240 | 67.95 (73.98) | 55.51 (59.93) | 51.59 (56.01) | 21.87 (28.74) | 0.42 (mumblebee_fast) | 0.42 |
| fleet_grid_soc_n64 | 8960 | 1017 (1095) | 471 (543) | 462 (532) | 369 (589) | 0.80 (mumblebee_fast) | 0.80 |

Warm cells: median (max) ms.

### fleet_grid_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.758 (0.819) | 1.31 (1.46) | 1.15 (1.29) | 0.238 (0.281) | 0.31 (clarabel) | 0.21 |
| fleet_grid_soc_n4 | 560 | 5.06 (5.56) | 8.98 (11.58) | 7.92 (10.18) | 2.31 (3.29) | 0.46 (clarabel) | 0.29 |
| fleet_grid_soc_n16 | 2240 | 74.69 (81.90) [2/11] | 60.45 (65.04) | 55.49 (59.86) | 21.76 (29.76) | 0.39 (mumblebee_fast) | 0.39 |
| fleet_grid_soc_n64 | 8960 | 1077 (1165) | 505 (578) | 495 (565) | 582 (1191) | 1.18 (mumblebee_fast) | 1.18 |

Warm cells: median (max) ms.

### fleet_grid_soc, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 4 / 6 / 7 / 7 | 6 / 9 / 10 / 10.5 | 6 / 9 / 10 / 10.5 | 20 / 20 / 20 / 20 |
| fleet_grid_soc_n4 | 5 / 8 / 10 / 11 | 7 / 10 / 12 / 13 | 7 / 10 / 12 / 13 | 40 / 40 / 40 / 40 |
| fleet_grid_soc_n16 | 5 / 8 / 10 / 11 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 70 / 70 / 70 / 70 |
| fleet_grid_soc_n64 | 5 / 8 / 11 / 12 | 7.5 / 10.5 / 13.5 / 15 | 7.5 / 10.5 / 13.5 / 15 | 150 / 150 / 150 / 150 |

### fleet_grid_soc, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 4 / 6 / 7 / 8 | 8 / 9 / 10 / 11 | 8 / 9 / 10 / 11 | 20 / 20 / 20 / 20 |
| fleet_grid_soc_n4 | 5 / 8 / 10 / 10 | 9 / 12 / 13 / 14 | 9 / 12 / 13 / 14 | 30 / 30 / 30 / 30 |
| fleet_grid_soc_n16 | 5 / 8 / 10 / 11 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 30 / 30 / 30 / 30 |
| fleet_grid_soc_n64 | 6 / 9 / 11 / 12 | 9 / 12 / 14 / 15 | 9 / 12 / 14 / 15 | 80 / 120 / 120 / 120 |

### fleet_grid_soc, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 0.293 | 0.508 | 0.288 | 2.06 |
| fleet_grid_soc_n4 | 1.13 | 1.90 | 1.24 | 10.18 |
| fleet_grid_soc_n16 | 5.28 | 8.11 | 5.86 | 88.82 |
| fleet_grid_soc_n64 | 24.04 | 32.45 | 23.77 | 948 |

## fleet_grid_soc_b4

### fleet_grid_soc_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.334 | 0.537 | 0.430 | 0.100 | 0.30 (clarabel) | 0.23 |
| fleet_grid_soc_b4_n4 | 272 | 2.49 | 3.33 | 2.90 | 1.71 | 0.69 (clarabel) | 0.59 |
| fleet_grid_soc_b4_n16 | 1088 | 46.14 | 24.29 | 21.13 | 11.15 | 0.53 (mumblebee_fast) | 0.53 |
| fleet_grid_soc_b4_n64 | 4352 | 772 | 238 | n/a | 208 | 0.88 (mumblebee) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.504 | 0.744 | 0.687 | 0.132 | 0.26 (clarabel) | 0.19 |
| fleet_grid_soc_b4_n4 | 272 | 3.88 | 4.74 | 4.03 | 1.87 | 0.48 (clarabel) | 0.46 |
| fleet_grid_soc_b4_n16 | 1088 | 66.80 | 34.08 | 29.17 | 14.63 | 0.50 (mumblebee_fast) | 0.50 |
| fleet_grid_soc_b4_n64 | 4352 | 1171 | 337 | n/a | 241 | 0.72 (mumblebee) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc_b4, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.618 | 0.841 | 0.688 | 0.131 | 0.21 (clarabel) | 0.19 |
| fleet_grid_soc_b4_n4 | 272 | 4.53 | 5.65 | 4.88 | 2.03 | 0.45 (clarabel) | 0.42 |
| fleet_grid_soc_b4_n16 | 1088 | 79.68 | 40.50 | 34.52 | 15.08 | 0.44 (mumblebee_fast) | 0.44 |
| fleet_grid_soc_b4_n64 | 4352 | 1485 | 428 | n/a | 242 | 0.57 (mumblebee) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.599 | 0.896 | 0.780 | 0.131 | 0.22 (clarabel) | 0.17 |
| fleet_grid_soc_b4_n4 | 272 | 4.86 | 6.13 | 5.26 | 1.98 | 0.41 (clarabel) | 0.38 |
| fleet_grid_soc_b4_n16 | 1088 | 90.71 | 43.45 | 37.55 | 15.69 | 0.42 (mumblebee_fast) | 0.42 |
| fleet_grid_soc_b4_n64 | 4352 | 1569 | 475 | n/a | 242 | 0.51 (mumblebee) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_grid_soc_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.374 (0.451) | 0.639 (0.669) | 0.536 (0.584) | 0.115 (0.232) | 0.31 (clarabel) | 0.21 |
| fleet_grid_soc_b4_n4 | 272 | 2.74 (3.14) | 4.06 (4.49) | 3.55 (3.89) | 1.20 (2.26) | 0.44 (clarabel) | 0.34 |
| fleet_grid_soc_b4_n16 | 1088 | 52.10 (59.39) | 24.12 (30.78) | 20.96 (26.44) | 9.61 (26.02) | 0.46 (mumblebee_fast) | 0.46 |
| fleet_grid_soc_b4_n64 | 4352 | 925 (1070) | 283 (289) | n/a | 186 (399) | 0.66 (mumblebee) | -- |

Warm cells: median (max) ms.

### fleet_grid_soc_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.511 (0.582) | 0.744 (0.817) | 0.660 (0.762) | 0.157 (0.270) | 0.31 (clarabel) | 0.24 |
| fleet_grid_soc_b4_n4 | 272 | 4.03 (4.42) | 5.50 (6.49) | 4.78 (5.53) | 1.38 (2.97) | 0.34 (clarabel) | 0.29 |
| fleet_grid_soc_b4_n16 | 1088 | 72.38 (78.92) | 33.88 (37.19) | 29.82 (32.80) | 12.25 (60.48) | 0.41 (mumblebee_fast) | 0.41 |
| fleet_grid_soc_b4_n64 | 4352 | 1278 (1513) | 402 (444) | n/a | 243 (477) | 0.60 (mumblebee) | -- |

Warm cells: median (max) ms.

### fleet_grid_soc_b4, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.579 (0.693) | 0.843 (0.950) | 0.708 (0.799) | 0.162 (0.402) | 0.28 (clarabel) | 0.23 |
| fleet_grid_soc_b4_n4 | 272 | 4.47 (6.00) | 6.09 (7.91) | 5.18 (6.73) | 1.34 (2.83) | 0.30 (clarabel) | 0.26 |
| fleet_grid_soc_b4_n16 | 1088 | 80.28 (86.17) | 40.16 (43.54) | 34.56 (37.30) | 13.27 (69.93) | 0.38 (mumblebee_fast) | 0.38 |
| fleet_grid_soc_b4_n64 | 4352 | 1553 (1684) | 442 (508) | n/a | 253 (507) | 0.57 (mumblebee) | -- |

Warm cells: median (max) ms.

### fleet_grid_soc_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.634 (0.712) | 0.923 (1.02) | 0.815 (0.876) | 0.160 (0.799) | 0.25 (clarabel) | 0.20 |
| fleet_grid_soc_b4_n4 | 272 | 4.84 (6.42) | 6.48 (8.31) | 5.57 (7.11) | 1.54 (2.82) | 0.32 (clarabel) | 0.28 |
| fleet_grid_soc_b4_n16 | 1088 | 99.93 (107) [1/11] | 43.46 (46.65) | 37.33 (40.15) | 14.41 (89.94) | 0.39 (mumblebee_fast) | 0.39 |
| fleet_grid_soc_b4_n64 | 4352 | 1664 (1790) | 482 (547) | n/a | 251 (528) | 0.52 (mumblebee) | -- |

Warm cells: median (max) ms.

### fleet_grid_soc_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 4 / 6.5 / 8 / 8 | 6 / 9 / 10 / 10.5 | 6 / 9 / 10 / 10.5 | 20 / 20 / 20 / 20 |
| fleet_grid_soc_b4_n4 | 5 / 8.5 / 10 / 11 | 7 / 10 / 12 / 13 | 7 / 10 / 12 / 13 | 40 / 40 / 40 / 40 |
| fleet_grid_soc_b4_n16 | 6 / 9 / 11 / 12.5 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 65 / 70 / 70 / 70 |
| fleet_grid_soc_b4_n64 | 6 / 9 / 12 / 13 | 7.5 / 10.5 / 13.5 / 15 | n/a | 125 / 130 / 130 / 130 |

### fleet_grid_soc_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 5 / 7 / 8 / 9 | 8 / 9 / 10 / 11 | 8 / 9 / 10 / 11 | 20 / 25 / 30 / 30 |
| fleet_grid_soc_b4_n4 | 6 / 9 / 10 / 11 | 9 / 12 / 13 / 14 | 9 / 12 / 13 / 14 | 30 / 30 / 30 / 30 |
| fleet_grid_soc_b4_n16 | 7 / 10 / 11 / 14 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 50 / 60 / 60 / 60 |
| fleet_grid_soc_b4_n64 | 7 / 10 / 13 / 14 | 9 / 12 / 14 / 15 | n/a | 90 / 100 / 100 / 100 |

### fleet_grid_soc_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 0.231 | 0.482 | 0.263 | 1.34 |
| fleet_grid_soc_b4_n4 | 0.952 | 1.79 | 1.10 | 7.25 |
| fleet_grid_soc_b4_n16 | 4.55 | 7.26 | 5.41 | 68.13 |
| fleet_grid_soc_b4_n64 | 21.44 | 30.82 | -- | 962 |

## fleet_ring_box

### fleet_ring_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.338 | 0.071 | 0.904 | 0.730 | 0.229 [1/6] | 0.090 | 0.077 | 1.07 (hpipm) | 0.11 |
| fleet_ring_box_n4 | 560 | 1.91 | 0.507 | 4.01 | 3.09 | 1.14 [1/6] | 0.661 [1/6] | 1.05 | 2.07 (hpipm) | 0.34 |
| fleet_ring_box_n16 | 2240 | 12.54 | 7.92 [1/6] | 19.10 | 14.66 | 7.30 [2/6] | 5.89 | 6.45 | 1.09 (piqp) | 0.44 |
| fleet_ring_box_n64 | 8960 | 55.54 | 446 | 82.33 | n/a | 55.99 | 36.56 | 40.14 | 1.10 (piqp) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.419 | 0.078 | 1.13 | 0.934 | 0.454 | 0.110 | 0.077 | 0.98 (hpipm) | 0.08 |
| fleet_ring_box_n4 | 560 | 2.46 | 0.573 | 5.08 | 3.88 | 4.29 | 0.933 | 1.24 | 2.16 (hpipm) | 0.32 |
| fleet_ring_box_n16 | 2240 | 17.38 | 10.87 | 25.55 | 20.22 | 19.25 [1/6] | 7.95 | 6.55 | 0.82 (piqp) | 0.32 |
| fleet_ring_box_n64 | 8960 | 81.14 | 569 [1/6] | 110 | n/a | 101 [1/6] | 46.31 | 41.77 | 0.90 (piqp) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.483 | 0.080 | 1.39 | 1.13 | 0.804 | 0.138 | 0.075 | 0.93 (hpipm) | 0.07 |
| fleet_ring_box_n4 | 560 | 2.93 | 0.604 | 6.15 | 4.68 | 8.84 | 1.10 | 1.20 | 1.99 (hpipm) | 0.26 |
| fleet_ring_box_n16 | 2240 | 20.63 | 12.35 [1/6] | 30.11 | 23.54 | 47.83 [1/6] | 9.44 | 6.47 | 0.68 (piqp) | 0.27 |
| fleet_ring_box_n64 | 8960 | 91.09 | 594 | 127 | n/a | 189 [1/6] | 56.33 | 42.47 | 0.75 (piqp) | -- |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.351 (0.420) | 0.068 (0.079) | 1.02 (1.31) | 0.837 (1.06) | 0.114 (0.114) | 0.095 (0.111) | 0.085 (0.190) | 1.25 (hpipm) | 0.10 |
| fleet_ring_box_n4 | 560 | 1.86 (2.11) | 0.468 (0.520) | 4.45 (4.54) | 3.46 (3.50) | 1.01 (1.53) [4/11] | 0.715 (0.771) [1/11] | 0.914 (1.30) | 1.95 (hpipm) | 0.26 |
| fleet_ring_box_n16 | 2240 | 14.02 (15.60) | 8.79 (10.29) [1/11] | 20.97 (23.43) | 16.44 (18.15) | 7.23 (7.26) [3/11] | 6.26 (7.53) | 6.02 (9.88) | 0.96 (piqp) | 0.37 |
| fleet_ring_box_n64 | 8960 | 61.55 (75.24) | 422 (505) | 88.66 (107) | n/a | 40.77 (61.39) | 39.59 (46.93) | 32.87 (49.28) | 0.83 (piqp) | -- |

Warm cells: median (max) ms.

### fleet_ring_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.405 (0.516) | 0.076 (0.117) | 1.36 (1.66) | 1.06 (1.31) | 0.335 (0.751) | 0.119 (0.152) | 0.085 (0.189) | 1.11 (hpipm) | 0.08 |
| fleet_ring_box_n4 | 560 | 2.61 (2.92) | 0.492 (0.566) | 5.61 (6.08) | 4.28 (4.70) | 4.28 (5.17) | 0.956 (1.06) | 0.852 (1.27) | 1.73 (hpipm) | 0.20 |
| fleet_ring_box_n16 | 2240 | 17.30 (18.80) | 9.71 (10.59) | 27.68 (29.96) | 22.02 (23.73) | 19.26 (28.10) [6/11] | 8.65 (9.43) | 6.17 (9.81) | 0.71 (piqp) | 0.28 |
| fleet_ring_box_n64 | 8960 | 82.43 (96.33) | 566 (611) [1/11] | 124 (141) | n/a | 95.57 (154) [5/11] | 50.52 (58.23) | 37.72 (57.82) | 0.75 (piqp) | -- |

Warm cells: median (max) ms.

### fleet_ring_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.492 (0.634) | 0.084 (0.125) | 1.55 (1.73) | 1.25 (1.46) | 1.11 (1.30) | 0.143 (0.170) | 0.085 (0.189) | 1.02 (hpipm) | 0.07 |
| fleet_ring_box_n4 | 560 | 3.10 (3.38) | 0.589 (0.750) | 6.57 (7.22) | 5.01 (5.46) | 5.75 (10.17) | 1.15 (1.36) | 0.868 (1.29) | 1.47 (hpipm) | 0.17 |
| fleet_ring_box_n16 | 2240 | 20.59 (22.10) | 11.26 (12.16) [1/11] | 32.13 (34.43) | 24.56 (26.53) | 34.77 (96.28) [4/11] | 9.62 (10.85) | 6.05 (9.87) | 0.63 (piqp) | 0.25 |
| fleet_ring_box_n64 | 8960 | 96.76 (111) | 582 (666) | 141 (160) | n/a | 188 (263) [4/11] | 57.09 (63.58) | 37.75 (57.80) | 0.66 (piqp) | -- |

Warm cells: median (max) ms.

### fleet_ring_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 4 / 6 / -- / 7 | 5 / 6.5 / -- / 7 | 6.5 / 8 / -- / 9.5 | 6.5 / 8 / -- / 9.5 | 62.5 / 100 / -- / 162.5 | 4 / 5.5 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_ring_box_n4 | 6 / 8 / -- / 10 | 7.5 / 9 / -- / 10 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 50 / 200 / -- / 450 | 6 / 8 / -- / 10 | 50 / 50 / -- / 50 |
| fleet_ring_box_n16 | 7 / 10 / -- / 12 | 7 / 10 / -- / 12 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 75 / 225 / -- / 500 | 7.5 / 10 / -- / 12 | 60 / 60 / -- / 60 |
| fleet_ring_box_n64 | 7 / 10.5 / -- / 12 | 9.5 / 11.5 / -- / 13 | 9.5 / 12.5 / -- / 14.5 | n/a | 137.5 / 237.5 / -- / 462.5 | 9 / 11 / -- / 13.5 | 95 / 100 / -- / 100 |

### fleet_ring_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 5 / 6 / -- / 8 | 6 / 7 / -- / 8 | 7 / 9 / -- / 11 | 7 / 9 / -- / 11 | 25 / 75 / -- / 250 | 4 / 6 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_ring_box_n4 | 6 / 9 / -- / 11 | 8 / 9 / -- / 11 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 50 / 200 / -- / 275 | 6 / 8 / -- / 10 | 30 / 30 / -- / 30 |
| fleet_ring_box_n16 | 8 / 10 / -- / 12 | 8 / 11 / -- / 13 | 10 / 13 / -- / 15 | 10 / 13 / -- / 15 | 75 / 200 / -- / 350 | 8 / 11 / -- / 12 | 60 / 60 / -- / 60 |
| fleet_ring_box_n64 | 8 / 11 / -- / 13 | 10 / 13 / -- / 14 | 10 / 14 / -- / 16 | n/a | 100 / 225 / -- / 450 | 10 / 12 / -- / 14 | 75 / 80 / -- / 80 |

### fleet_ring_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 0.253 | 0.087 | 0.508 | 0.323 | 0.140 | 0.083 | 1.52 |
| fleet_ring_box_n4 | 0.879 | 0.158 | 2.03 | 1.25 | 0.610 | 0.403 | 7.42 |
| fleet_ring_box_n16 | 3.32 | 1.61 | 7.80 | 4.67 | 2.56 | 1.21 | 33.68 |
| fleet_ring_box_n64 | 13.70 | 46.71 | 31.56 | -- | 10.46 | 4.92 | 133 |

## fleet_ring_box_b4

### fleet_ring_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.251 | 0.566 | 0.434 | 0.374 | 0.111 [1/6] | 0.061 | 0.050 | 0.82 (piqp) | 0.12 |
| fleet_ring_box_b4_n4 | 272 | 1.61 | 3.31 | 2.46 | 2.29 | 1.19 | 0.561 [1/6] | 0.664 | 0.56 (osqp) | 0.27 |
| fleet_ring_box_b4_n16 | 1088 | 11.32 | 16.85 | 12.56 | 11.95 | 10.58 | 6.72 | 4.16 | 0.62 (piqp) | 0.33 |
| fleet_ring_box_b4_n64 | 4352 | 62.81 | 71.58 | 52.18 | 49.67 | 78.32 | 45.49 | 19.37 | 0.43 (piqp) | 0.37 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.316 | 0.691 | 0.529 | 0.456 | 0.228 | 0.070 | 0.050 | 0.71 (piqp) | 0.09 |
| fleet_ring_box_b4_n4 | 272 | 2.01 | 4.15 | 2.96 | 2.84 | 4.54 | 0.707 | 0.674 | 0.95 (piqp) | 0.23 |
| fleet_ring_box_b4_n16 | 1088 | 15.72 | 22.76 | 16.71 | 16.23 | 33.10 [2/6] | 8.66 | 4.23 | 0.49 (piqp) | 0.25 |
| fleet_ring_box_b4_n64 | 4352 | 87.44 | 95.56 | 69.77 | 65.99 | 190 | 55.53 | 21.24 | 0.38 (piqp) | 0.30 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.359 | 0.847 | 0.642 | 0.566 | 0.374 | 0.087 | 0.049 | 0.57 (piqp) | 0.08 |
| fleet_ring_box_b4_n4 | 272 | 2.36 | 4.89 | 3.43 | 3.35 | 6.98 | 0.803 | 0.778 | 0.97 (piqp) | 0.23 |
| fleet_ring_box_b4_n16 | 1088 | 18.57 | 26.68 | 19.57 | 18.78 | 46.43 | 10.15 | 4.30 | 0.42 (piqp) | 0.22 |
| fleet_ring_box_b4_n64 | 4352 | 97.85 | 113 | 80.94 | 76.82 | 238 | 65.94 | 21.77 | 0.33 (piqp) | 0.27 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.273 (0.319) | 0.644 (0.824) | 0.507 (0.611) | 0.417 (0.548) | 0.110 (0.163) | 0.064 (0.075) | 0.052 (0.133) | 0.81 (piqp) | 0.10 |
| fleet_ring_box_b4_n4 | 272 | 1.58 (1.94) | 3.64 (3.70) | 2.58 (2.64) | 2.46 (2.48) | 0.628 (1.25) [3/11] | 0.611 (0.650) [1/11] | 0.555 (1.52) | 0.35 (clarabel) | 0.22 |
| fleet_ring_box_b4_n16 | 1088 | 12.74 (14.08) | 18.69 (20.68) | 13.66 (15.11) | 13.13 (14.46) | 9.80 (17.69) | 7.19 (8.70) | 3.42 (6.71) | 0.48 (piqp) | 0.25 |
| fleet_ring_box_b4_n64 | 4352 | 76.56 (83.60) | 76.25 (92.17) | 56.25 (67.80) | 53.10 (63.95) | 53.62 (69.38) | 49.55 (58.76) | 18.76 (29.38) | 0.38 (piqp) | 0.33 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.345 (0.425) | 0.808 (0.983) | 0.643 (0.738) | 0.508 (0.663) | 0.220 (0.275) | 0.074 (0.095) | 0.050 (0.127) | 0.67 (piqp) | 0.08 |
| fleet_ring_box_b4_n4 | 272 | 1.95 (2.32) | 4.53 (4.93) | 3.18 (3.44) | 3.05 (3.31) | 2.58 (3.23) [3/11] | 0.720 (0.865) | 0.580 (1.40) | 0.81 (piqp) | 0.18 |
| fleet_ring_box_b4_n16 | 1088 | 16.61 (18.03) | 24.65 (26.61) | 17.90 (19.36) | 17.03 (18.33) | 22.28 (34.59) | 9.38 (10.21) | 3.46 (6.81) | 0.37 (piqp) | 0.19 |
| fleet_ring_box_b4_n64 | 4352 | 97.73 (112) | 108 (124) | 79.18 (90.80) | 74.94 (85.86) | 69.31 (133) [4/11] | 58.70 (68.03) | 21.59 (33.69) | 0.37 (piqp) | 0.27 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.375 (0.447) | 0.963 (1.11) | 0.723 (0.845) | 0.603 (0.697) | 0.350 (0.435) [1/11] | 0.089 (0.107) | 0.050 (0.129) | 0.56 (piqp) | 0.07 |
| fleet_ring_box_b4_n4 | 272 | 2.38 (2.65) | 5.25 (5.70) | 3.63 (3.99) | 3.51 (3.81) | 4.65 (5.96) | 0.849 (0.934) | 0.566 (1.44) | 0.67 (piqp) | 0.16 |
| fleet_ring_box_b4_n16 | 1088 | 18.00 (20.53) | 28.54 (30.50) | 20.48 (21.90) | 19.75 (21.14) | 31.96 (93.55) | 10.18 (11.71) | 3.41 (6.72) | 0.34 (piqp) | 0.17 |
| fleet_ring_box_b4_n64 | 4352 | 112 (126) | 125 (141) | 90.74 (103) | 85.93 (96.41) | 160 (276) | 67.43 (76.37) | 21.54 (33.83) | 0.32 (piqp) | 0.24 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 5 / 6.5 / -- / 8 | 6.5 / 8 / -- / 9.5 | 6.5 / 8 / -- / 9.5 | 6.5 / 8 / -- / 9.5 | 50 / 100 / -- / 175 | 4 / 5.5 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 100 / 400 / -- / 625 | 6 / 8 / -- / 9.5 | 50 / 50 / -- / 50 |
| fleet_ring_box_b4_n16 | 7.5 / 10.5 / -- / 12.5 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 162.5 / 487.5 / -- / 662.5 | 7.5 / 10 / -- / 12 | 55 / 55 / -- / 55 |
| fleet_ring_box_b4_n64 | 8 / 11.5 / -- / 13 | 9.5 / 12.5 / -- / 14.5 | 9.5 / 12.5 / -- / 14.5 | 9.5 / 12.5 / -- / 14.5 | 250 / 575 / -- / 737.5 | 9 / 11 / -- / 13.5 | 75 / 85 / -- / 85 |

### fleet_ring_box_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 6 / 8 / -- / 9 | 7 / 9 / -- / 11 | 7 / 9 / -- / 11 | 7 / 9 / -- / 11 | 50 / 100 / -- / 175 | 4 / 6 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 50 / 200 / -- / 425 | 6 / 8 / -- / 10 | 40 / 40 / -- / 40 |
| fleet_ring_box_b4_n16 | 9 / 12 / -- / 13 | 10 / 13 / -- / 15 | 10 / 13 / -- / 15 | 10 / 13 / -- / 15 | 150 / 325 / -- / 450 | 8 / 11 / -- / 12 | 40 / 40 / -- / 40 |
| fleet_ring_box_b4_n64 | 10 / 13 / -- / 15 | 10 / 14 / -- / 16 | 10 / 14 / -- / 16 | 10 / 14 / -- / 16 | 175 / 250 / -- / 500 | 10 / 12 / -- / 14 | 75 / 80 / -- / 80 |

### fleet_ring_box_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 0.177 | 0.398 | 0.261 | 0.246 | 0.095 | 0.044 | 0.920 |
| fleet_ring_box_b4_n4 | 0.605 | 1.73 | 1.13 | 1.12 | 0.433 | 0.300 | 4.61 |
| fleet_ring_box_b4_n16 | 2.35 | 6.47 | 4.28 | 4.30 | 2.00 | 1.02 | 21.83 |
| fleet_ring_box_b4_n64 | 9.68 | 25.58 | 16.72 | 16.89 | 8.83 | 3.93 | 95.46 |

## fleet_ring_soc

### fleet_ring_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.395 | 0.712 | 0.635 | 0.503 | 0.150 | 0.38 (clarabel) | 0.24 |
| fleet_ring_soc_n4 | 560 | 2.89 | 4.33 | 3.86 | 3.15 | 1.73 | 0.60 (clarabel) | 0.45 |
| fleet_ring_soc_n16 | 2240 | 19.70 | 21.31 | 19.25 | 16.14 | 11.30 | 0.70 (mumblebee_fast_ct) | 0.59 |
| fleet_ring_soc_n64 | 8960 | 97.24 | 83.91 | 82.07 | 81.82 | 54.52 | 0.67 (mumblebee_fast_ct) | 0.66 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.571 | 0.894 | 0.791 | 0.628 | 0.191 | 0.33 (clarabel) | 0.24 |
| fleet_ring_soc_n4 | 560 | 3.91 | 6.38 | 5.60 | 4.62 | 2.12 | 0.54 (clarabel) | 0.38 |
| fleet_ring_soc_n16 | 2240 | 29.58 | 29.98 | 27.00 | 22.71 | 13.00 | 0.57 (mumblebee_fast_ct) | 0.48 |
| fleet_ring_soc_n64 | 8960 | 153 | 119 | 113 | 109 | 62.50 | 0.57 (mumblebee_fast_ct) | 0.55 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.665 | 1.07 | 0.952 | 0.728 | 0.219 | 0.33 (clarabel) | 0.23 |
| fleet_ring_soc_n4 | 560 | 4.95 | 7.32 | 6.49 | 5.36 | 2.35 | 0.47 (clarabel) | 0.36 |
| fleet_ring_soc_n16 | 2240 | 36.62 | 35.98 | 33.28 | 27.19 | 14.45 | 0.53 (mumblebee_fast_ct) | 0.43 |
| fleet_ring_soc_n64 | 8960 | 170 | 156 | 134 | 125 | 63.88 | 0.51 (mumblebee_fast_ct) | 0.48 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.742 | 1.12 | 1.02 | 0.801 | 0.219 | 0.30 (clarabel) | 0.22 |
| fleet_ring_soc_n4 | 560 | 5.45 | 7.94 | 7.15 | 5.83 | 2.37 | 0.43 (clarabel) | 0.33 |
| fleet_ring_soc_n16 | 2240 | 38.48 | 37.18 | 33.94 | 28.37 | 14.51 | 0.51 (mumblebee_fast_ct) | 0.43 |
| fleet_ring_soc_n64 | 8960 | 185 | 162 | 144 | 138 | 65.48 | 0.47 (mumblebee_fast_ct) | 0.45 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.384 (0.459) | 0.781 (1.02) | 0.688 (0.890) | 0.563 (0.692) | 0.119 (0.326) | 0.31 (clarabel) | 0.17 |
| fleet_ring_soc_n4 | 560 | 2.83 (4.27) | 4.91 (5.60) | 4.42 (5.02) | 3.58 (4.08) | 1.52 (3.94) | 0.54 (clarabel) | 0.34 |
| fleet_ring_soc_n16 | 2240 | 22.11 (25.47) | 23.54 (26.56) | 21.77 (24.78) | 18.03 (20.34) | 12.32 (18.85) | 0.68 (mumblebee_fast_ct) | 0.57 |
| fleet_ring_soc_n64 | 8960 | 105 (120) | 95.52 (107) | 92.43 (104) | 82.45 (96.15) | 54.43 (119) | 0.66 (mumblebee_fast_ct) | 0.59 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.555 (0.634) | 1.00 (1.25) | 0.896 (1.10) | 0.707 (0.870) | 0.152 (0.333) | 0.27 (clarabel) | 0.17 |
| fleet_ring_soc_n4 | 560 | 4.34 (5.36) | 6.34 (7.61) | 5.63 (6.79) | 4.57 (5.54) | 1.88 (4.30) | 0.43 (clarabel) | 0.33 |
| fleet_ring_soc_n16 | 2240 | 29.79 (36.75) | 29.87 (38.81) | 27.11 (34.70) | 22.49 (28.94) | 13.28 (21.92) | 0.59 (mumblebee_fast_ct) | 0.49 |
| fleet_ring_soc_n64 | 8960 | 153 (168) | 133 (161) | 125 (148) | 117 (137) | 64.97 (275) | 0.56 (mumblebee_fast_ct) | 0.52 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.646 (0.803) | 1.23 (1.39) | 1.10 (1.21) | 0.847 (0.938) | 0.187 (0.369) | 0.29 (clarabel) | 0.17 |
| fleet_ring_soc_n4 | 560 | 4.90 (5.89) | 7.52 (8.89) | 6.80 (7.96) | 5.56 (6.51) | 2.10 (4.31) | 0.43 (clarabel) | 0.31 |
| fleet_ring_soc_n16 | 2240 | 36.95 (44.04) | 37.64 (46.39) | 35.14 (43.24) | 29.01 (35.62) | 14.60 (23.00) | 0.50 (mumblebee_fast_ct) | 0.42 |
| fleet_ring_soc_n64 | 8960 | 186 (219) | 171 (186) | 155 (166) | 147 (158) | 64.93 (287) | 0.44 (mumblebee_fast_ct) | 0.42 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.718 (0.873) | 1.27 (1.50) | 1.11 (1.31) | 0.871 (1.02) | 0.190 (0.368) | 0.26 (clarabel) | 0.17 |
| fleet_ring_soc_n4 | 560 | 5.42 (6.33) [1/11] | 8.29 (9.65) | 7.33 (8.44) | 6.03 (7.01) | 2.20 (4.27) | 0.37 (mumblebee_fast_ct) | 0.30 |
| fleet_ring_soc_n16 | 2240 | 39.24 (48.60) | 38.68 (49.87) | 34.90 (45.04) | 32.34 (41.90) | 14.33 (23.93) | 0.44 (mumblebee_fast_ct) | 0.41 |
| fleet_ring_soc_n64 | 8960 | 203 (235) | 183 (198) | 166 (178) | 158 (170) | 61.82 (302) | 0.39 (mumblebee_fast_ct) | 0.37 |

Warm cells: median (max) ms.

### fleet_ring_soc, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 4 / 6 / 7 / 8 | 6.5 / 8 / 9.5 / 10 | 6.5 / 8 / 9.5 / 10 | 6.5 / 8 / 9.5 / 10 | 30 / 30 / 30 / 30 |
| fleet_ring_soc_n4 | 5 / 7 / 9 / 10 | 7 / 10 / 11.5 / 12.5 | 7 / 10 / 11.5 / 12.5 | 7 / 10 / 11.5 / 12.5 | 35 / 35 / 35 / 35 |
| fleet_ring_soc_n16 | 5 / 8 / 10 / 10.5 | 8 / 11 / 13 / 13.5 | 8 / 11 / 13 / 13.5 | 8 / 11 / 13 / 13.5 | 55 / 55 / 55 / 55 |
| fleet_ring_soc_n64 | 5.5 / 9 / 10 / 11 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 70 / 70 / 70 / 70 |

### fleet_ring_soc, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 4 / 6 / 7 / 8 | 7 / 9 / 11 / 11 | 7 / 9 / 11 / 11 | 7 / 9 / 11 / 11 | 20 / 20 / 20 / 20 |
| fleet_ring_soc_n4 | 5 / 8 / 9 / 10 | 8 / 10 / 12 / 13 | 8 / 10 / 12 / 13 | 8 / 10 / 12 / 13 | 20 / 20 / 20 / 20 |
| fleet_ring_soc_n16 | 6 / 8 / 10 / 11 | 9 / 11 / 14 / 14 | 9 / 11 / 14 / 14 | 9 / 11 / 14 / 14 | 40 / 40 / 40 / 40 |
| fleet_ring_soc_n64 | 6 / 9 / 11 / 12 | 9 / 12 / 15 / 16 | 9 / 12 / 15 / 16 | 9 / 12 / 15 / 16 | 70 / 80 / 80 / 80 |

### fleet_ring_soc, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 0.287 | 0.476 | 0.300 | 0.301 | 2.02 |
| fleet_ring_soc_n4 | 1.16 | 1.99 | 1.23 | 1.22 | 10.61 |
| fleet_ring_soc_n16 | 4.46 | 7.28 | 4.63 | 4.52 | 53.83 |
| fleet_ring_soc_n64 | 17.38 | 27.12 | 17.54 | 19.61 | 229 |

## fleet_ring_soc_b4

### fleet_ring_soc_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.311 | 0.511 | 0.439 | 0.446 | 0.105 | 0.34 (clarabel) | 0.24 |
| fleet_ring_soc_b4_n4 | 272 | 2.75 | 3.35 | 2.80 | 2.64 | 1.23 | 0.47 (mumblebee_fast_ct) | 0.44 |
| fleet_ring_soc_b4_n16 | 1088 | 32.50 | 18.28 | 16.41 | 15.37 | 8.58 | 0.56 (mumblebee_fast_ct) | 0.52 |
| fleet_ring_soc_b4_n64 | 4352 | 125 | 77.64 | 76.35 | 72.26 | 37.51 | 0.52 (mumblebee_fast_ct) | 0.49 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.448 | 0.607 | 0.543 | 0.510 | 0.133 | 0.30 (clarabel) | 0.25 |
| fleet_ring_soc_b4_n4 | 272 | 3.56 | 4.82 | 3.95 | 3.70 | 1.59 | 0.45 (clarabel) | 0.40 |
| fleet_ring_soc_b4_n16 | 1088 | 35.50 | 25.31 | 23.09 | 21.41 | 9.67 | 0.45 (mumblebee_fast_ct) | 0.42 |
| fleet_ring_soc_b4_n64 | 4352 | 182 | 109 | 106 | 113 | 45.18 | 0.43 (mumblebee_fast) | 0.43 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc_b4, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.573 | 0.728 | 0.645 | 0.616 | 0.157 | 0.27 (clarabel) | 0.24 |
| fleet_ring_soc_b4_n4 | 272 | 4.42 | 5.25 | 4.63 | 4.24 | 1.51 | 0.36 (mumblebee_fast_ct) | 0.33 |
| fleet_ring_soc_b4_n16 | 1088 | 43.49 | 30.30 | 27.02 | 25.69 | 10.37 | 0.40 (mumblebee_fast_ct) | 0.38 |
| fleet_ring_soc_b4_n64 | 4352 | 216 | 135 | 124 | 133 | 49.93 | 0.40 (mumblebee_fast) | 0.40 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.581 | 0.776 | 0.698 | 0.657 | 0.156 | 0.27 (clarabel) | 0.22 |
| fleet_ring_soc_b4_n4 | 272 | 4.78 | 5.62 | 5.07 | 4.64 | 1.67 | 0.36 (mumblebee_fast_ct) | 0.33 |
| fleet_ring_soc_b4_n16 | 1088 | 46.27 | 31.49 | 28.09 | 26.79 | 11.14 | 0.42 (mumblebee_fast_ct) | 0.40 |
| fleet_ring_soc_b4_n64 | 4352 | 226 | 146 | 134 | 141 | 52.41 | 0.39 (mumblebee_fast) | 0.39 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.361 (0.430) | 0.530 (0.679) | 0.464 (0.598) | 0.448 (0.571) | 0.103 (0.232) | 0.29 (clarabel) | 0.22 |
| fleet_ring_soc_b4_n4 | 272 | 2.70 (3.22) | 3.68 (4.22) | 3.16 (3.58) | 2.89 (3.35) | 1.07 (2.71) | 0.39 (clarabel) | 0.34 |
| fleet_ring_soc_b4_n16 | 1088 | 28.46 (32.17) | 20.22 (22.74) | 18.44 (20.34) | 17.13 (19.17) | 7.11 (14.30) | 0.42 (mumblebee_fast_ct) | 0.39 |
| fleet_ring_soc_b4_n64 | 4352 | 142 (160) | 88.47 (99.21) | 85.39 (96.71) | 91.54 (104) | 42.24 (69.06) | 0.49 (mumblebee_fast) | 0.49 |

Warm cells: median (max) ms.

### fleet_ring_soc_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.491 (0.554) | 0.684 (0.835) | 0.613 (0.749) | 0.564 (0.696) | 0.127 (0.234) | 0.26 (clarabel) | 0.21 |
| fleet_ring_soc_b4_n4 | 272 | 3.59 (4.36) | 4.80 (5.71) | 4.03 (4.82) | 3.86 (4.40) | 1.33 (2.61) | 0.37 (clarabel) | 0.33 |
| fleet_ring_soc_b4_n16 | 1088 | 35.46 (42.61) | 25.40 (32.20) | 22.78 (29.13) | 21.12 (27.04) | 8.47 (17.19) | 0.40 (mumblebee_fast_ct) | 0.37 |
| fleet_ring_soc_b4_n64 | 4352 | 197 (219) | 121 (141) | 116 (135) | 123 (146) | 52.94 (74.10) | 0.46 (mumblebee_fast) | 0.46 |

Warm cells: median (max) ms.

### fleet_ring_soc_b4, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.554 (0.616) | 0.840 (0.923) | 0.725 (0.813) | 0.689 (0.758) | 0.150 (0.268) | 0.27 (clarabel) | 0.21 |
| fleet_ring_soc_b4_n4 | 272 | 4.41 (5.11) | 5.39 (6.25) | 4.79 (5.58) | 4.38 (5.12) | 1.48 (2.95) | 0.34 (mumblebee_fast_ct) | 0.31 |
| fleet_ring_soc_b4_n16 | 1088 | 46.96 (54.43) | 32.07 (39.48) | 28.58 (34.91) | 27.67 (34.01) | 9.60 (17.98) | 0.35 (mumblebee_fast_ct) | 0.34 |
| fleet_ring_soc_b4_n64 | 4352 | 235 (275) | 162 (179) | 144 (155) | 152 (163) | 56.17 (78.44) | 0.39 (mumblebee_fast) | 0.39 |

Warm cells: median (max) ms.

### fleet_ring_soc_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.631 (0.691) | 0.853 (1.01) | 0.745 (0.883) | 0.699 (0.820) | 0.149 (0.255) | 0.24 (clarabel) | 0.20 |
| fleet_ring_soc_b4_n4 | 272 | 4.89 (5.69) [1/11] | 5.83 (6.76) | 5.20 (6.06) | 4.76 (5.51) | 1.56 (2.81) | 0.33 (mumblebee_fast_ct) | 0.30 |
| fleet_ring_soc_b4_n16 | 1088 | 49.72 (59.68) [1/11] | 33.39 (42.39) | 29.10 (37.47) | 28.05 (35.72) | 9.46 (17.61) | 0.34 (mumblebee_fast_ct) | 0.33 |
| fleet_ring_soc_b4_n64 | 4352 | 253 (291) | 169 (184) | 153 (163) | 164 (178) | 55.99 (77.98) | 0.37 (mumblebee_fast) | 0.37 |

Warm cells: median (max) ms.

### fleet_ring_soc_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 4 / 6 / 8 / 8 | 6.5 / 8 / 9.5 / 10 | 6.5 / 8 / 9.5 / 10 | 6.5 / 8 / 9.5 / 10 | 30 / 30 / 30 / 30 |
| fleet_ring_soc_b4_n4 | 6 / 8 / 10 / 11 | 7 / 10 / 11.5 / 12.5 | 7 / 10 / 11.5 / 12.5 | 7 / 10 / 11.5 / 12.5 | 35 / 35 / 35 / 35 |
| fleet_ring_soc_b4_n16 | 6 / 9 / 11 / 11.5 | 8 / 11 / 13 / 13.5 | 8 / 11 / 13 / 13.5 | 8 / 11 / 13 / 13.5 | 55 / 55 / 55 / 55 |
| fleet_ring_soc_b4_n64 | 6 / 9 / 11 / 11.5 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 60 / 60 / 60 / 60 |

### fleet_ring_soc_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 5 / 7 / 8 / 9 | 7 / 9 / 11 / 11 | 7 / 9 / 11 / 11 | 7 / 9 / 11 / 11 | 20 / 20 / 20 / 20 |
| fleet_ring_soc_b4_n4 | 6 / 8 / 10 / 11 | 8 / 10 / 12 / 13 | 8 / 10 / 12 / 13 | 8 / 10 / 12 / 13 | 30 / 30 / 30 / 30 |
| fleet_ring_soc_b4_n16 | 7 / 9 / 12 / 13 | 9 / 11 / 14 / 14 | 9 / 11 / 14 / 14 | 9 / 11 / 14 / 14 | 40 / 50 / 50 / 50 |
| fleet_ring_soc_b4_n64 | 7 / 10 / 12 / 13 | 9 / 12 / 15 / 16 | 9 / 12 / 15 / 16 | 9 / 12 / 15 / 16 | 70 / 70 / 70 / 70 |

### fleet_ring_soc_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 0.225 | 0.416 | 0.255 | 0.243 | 1.30 |
| fleet_ring_soc_b4_n4 | 0.875 | 2.12 | 1.08 | 1.05 | 7.88 |
| fleet_ring_soc_b4_n16 | 3.81 | 6.64 | 4.33 | 4.23 | 44.23 |
| fleet_ring_soc_b4_n64 | 13.81 | 25.20 | 17.22 | 18.25 | 219 |

## osqprand

### osqprand, cold, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.38 | 0.160 [1/5] | 1.84 | 0.634 | 0.415 | 0.397 | 0.96 (piqp) |
| osqprand_nx10_s2 | 160 | 0.882 | 0.099 | 1.53 | 0.306 | 0.440 | 0.405 | 4.11 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.26 | 0.144 [2/5] | 2.16 | 0.831 | 0.534 | 0.932 | 1.74 (piqp) |
| osqprand_nx20_s1 | 320 | 3.78 | 0.324 | 6.14 | 3.76 | 2.04 | 1.06 | 3.28 (hpipm) |
| osqprand_nx20_s2 | 320 | 3.80 | 0.322 | 5.93 [2/5] | 1.60 | 2.31 | 1.05 | 3.26 (hpipm) |
| osqprand_nx20_s3 | 320 | 3.77 | 0.413 | 6.12 | 0.852 | 2.10 | 1.23 | 2.98 (hpipm) |
| osqprand_nx40_s1 | 640 | 17.90 | 1.21 | 16.40 [1/5] | 9.70 | 11.99 | 3.67 | 3.04 (hpipm) |
| osqprand_nx40_s2 | 640 | 16.41 | 1.68 | 18.95 | 6.82 [2/5] | 12.86 | 13.64 | 8.12 (hpipm) |
| osqprand_nx40_s3 | 640 | 13.99 | 1.81 | 13.22 [1/5] | 2.89 | 10.60 | 3.26 | 1.80 (hpipm) |
| osqprand_nx80_s1 | 1280 | 97.65 | 6.73 | 101 | 82.31 | 104 | 16.29 | 2.42 (hpipm) |

Cold cells: median ms of the solve; setup is separate.

### osqprand, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.49 | 0.181 [1/5] | 2.72 [2/5] | 1.51 | 0.619 | 0.431 | 0.70 (piqp) |
| osqprand_nx10_s2 | 160 | 1.18 | 0.119 | 1.83 | 0.602 | 0.512 | 0.363 | 3.04 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.75 | 0.214 | 2.85 [2/5] | 0.877 [1/5] | 0.697 | 0.908 | 4.26 (hpipm) |
| osqprand_nx20_s1 | 320 | 4.87 | 0.424 | 7.72 | 7.01 [2/5] | 2.57 | 1.06 | 2.49 (hpipm) |
| osqprand_nx20_s2 | 320 | 4.81 | 0.552 | 8.64 | 3.21 | 2.75 | 1.21 | 2.19 (hpipm) |
| osqprand_nx20_s3 | 320 | 4.92 | 0.514 | 7.93 | 2.38 | 2.71 | 1.13 | 2.21 (hpipm) |
| osqprand_nx40_s1 | 640 | 22.52 | 1.69 | 25.32 | 24.52 | 16.86 | 3.58 | 2.12 (hpipm) |
| osqprand_nx40_s2 | 640 | 20.82 | 1.94 [2/5] | 24.83 [4/5] | 45.12 | 14.63 | 13.78 | 0.94 (piqp) |
| osqprand_nx40_s3 | 640 | 18.15 | 1.31 | 22.50 | 7.78 | 13.72 | 3.62 | 2.76 (hpipm) |
| osqprand_nx80_s1 | 1280 | 126 | 7.70 | 112 | 163 | 128 | 16.05 | 2.08 (hpipm) |

Cold cells: median ms of the solve; setup is separate.

### osqprand, cold, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.84 | 0.203 [1/5] | 3.06 [2/5] | 1.69 | 0.693 | 0.518 | 0.75 (piqp) |
| osqprand_nx10_s2 | 160 | 1.37 | 0.118 | 2.54 | 0.611 | 0.633 | 0.363 | 3.07 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.84 | 0.226 [1/5] | 3.73 | 1.32 | 0.898 | 2.98 | 3.32 (piqp) |
| osqprand_nx20_s1 | 320 | 5.10 | 0.466 [1/5] | 8.37 [2/5] | 9.95 | 2.96 | 1.10 | 0.37 (piqp) |
| osqprand_nx20_s2 | 320 | 5.67 | 0.490 | 8.75 | 6.09 | 3.15 | 0.960 | 1.96 (hpipm) |
| osqprand_nx20_s3 | 320 | 6.01 | 0.615 [1/5] | 9.62 | 3.87 | 3.19 | 1.17 | 0.37 (piqp) |
| osqprand_nx40_s1 | 640 | 25.57 | 1.82 | 31.26 | 51.42 | 17.95 | 3.52 | 1.93 (hpipm) |
| osqprand_nx40_s2 | 640 | 25.18 | 1.71 [3/5] | 27.60 [3/5] | 68.56 | 18.71 | 13.91 | 0.74 (piqp) |
| osqprand_nx40_s3 | 640 | 20.31 | 1.48 | 25.30 | 11.03 | 15.10 | 3.30 | 2.23 (hpipm) |
| osqprand_nx80_s1 | 1280 | 138 | 8.22 [1/5] | 136 | 255 | 141 | 15.47 | 0.11 (mumblebee) |

Cold cells: median ms of the solve; setup is separate.

### osqprand, warm, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.07 (1.33) | 0.110 (0.160) [1/11] | 1.88 (2.22) | 0.320 (0.720) | 0.425 (0.485) | 0.084 (0.344) | 0.26 (osqp) |
| osqprand_nx10_s2 | 160 | 0.864 (0.890) | 0.097 (0.102) | 1.47 (1.50) | 0.310 (0.321) | 0.456 (0.471) | 0.082 (0.094) | 0.85 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.23 (1.28) | 0.154 (0.158) [2/11] | 2.06 (2.14) | 0.544 (0.568) | 0.547 (0.622) | 0.082 (0.642) | 0.15 (osqp) |
| osqprand_nx20_s1 | 320 | 4.22 (4.31) | 0.340 (0.403) | 5.51 (5.69) | 2.17 (2.21) | 2.16 (2.49) | 0.219 (0.677) | 0.65 (hpipm) |
| osqprand_nx20_s2 | 320 | 3.71 (4.25) | 0.389 (0.486) | 4.73 (5.67) [2/11] | 0.731 (1.67) | 2.15 (2.47) | 0.773 (1.97) | 1.98 (hpipm) |
| osqprand_nx20_s3 | 320 | 3.69 (3.77) | 0.389 (0.459) | 4.75 (6.53) | 0.840 (1.83) | 2.18 (2.21) | 0.220 (1.86) | 0.56 (hpipm) |
| osqprand_nx40_s1 | 640 | 15.72 (18.54) | 1.16 (1.22) | 12.48 (15.65) [2/11] | 2.84 (6.84) | 11.61 (13.30) | 0.722 (40.90) | 0.62 (hpipm) |
| osqprand_nx40_s2 | 640 | 16.19 (16.41) | 1.09 (1.52) | 17.68 (20.60) | 2.81 (11.98) | 11.51 (13.09) | 2.53 (10.61) | 2.32 (hpipm) |
| osqprand_nx40_s3 | 640 | 13.74 (13.86) | 1.10 (1.42) | 12.36 (12.74) [1/11] | 2.78 (2.85) | 10.09 (10.14) | 0.685 (5.92) | 0.62 (hpipm) |
| osqprand_nx80_s1 | 1280 | 90.23 (119) | 6.02 (7.21) | 85.64 (98.61) | 33.19 (79.48) | 88.25 (103) | 17.54 (104) | 2.91 (hpipm) |

Warm cells: median (max) ms.

### osqprand, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.19 (1.51) | 0.128 (0.203) [1/11] | 2.07 (2.76) [2/11] | 0.560 (1.18) | 0.532 (0.685) | 0.073 (0.291) | 0.14 (piqp) |
| osqprand_nx10_s2 | 160 | 1.12 (1.15) | 0.118 (0.132) | 1.77 (2.03) | 0.594 (0.630) | 0.524 (0.544) | 0.075 (0.079) | 0.63 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.63 (1.93) | 0.211 (0.239) | 2.66 (2.99) [2/11] | 0.849 (0.895) [4/11] | 0.661 (0.754) | 0.068 (0.544) | 0.33 (hpipm) |
| osqprand_nx20_s1 | 320 | 4.68 (5.22) | 0.442 (0.503) | 7.16 (7.41) | 6.01 (6.04) [8/11] | 2.69 (2.75) | 0.210 (0.622) | 0.48 (hpipm) |
| osqprand_nx20_s2 | 320 | 4.69 (4.83) | 0.715 (0.798) | 7.25 (8.23) | 1.70 (3.88) | 2.71 (3.05) | 0.772 (1.99) | 1.08 (hpipm) |
| osqprand_nx20_s3 | 320 | 4.75 (5.45) | 0.467 (0.600) | 6.38 (8.88) | 1.57 (2.47) | 2.50 (3.10) | 0.220 (1.91) | 0.47 (hpipm) |
| osqprand_nx40_s1 | 640 | 20.90 (23.49) | 1.42 (1.47) | 23.35 (27.38) | 13.69 (40.40) | 13.47 (15.09) | 0.754 (45.16) | 0.53 (hpipm) |
| osqprand_nx40_s2 | 640 | 20.53 (23.02) | 1.38 (1.59) [2/11] | 20.45 (26.12) [4/11] | 9.47 (31.97) | 12.85 (14.45) | 0.665 (6.29) | 0.07 (osqp) |
| osqprand_nx40_s3 | 640 | 18.15 (20.78) | 1.28 (1.34) [1/11] | 18.34 (21.66) [2/11] | 5.22 (6.54) | 13.24 (13.28) | 0.684 (5.95) | 0.13 (osqp) |
| osqprand_nx80_s1 | 1280 | 115 (138) | 7.83 (9.09) | 1679 (1703) | 153 (195) | 102 (120) | 17.74 (105) | 2.27 (hpipm) |

Warm cells: median (max) ms.

### osqprand, warm, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.37 (1.77) | 0.156 (0.241) [1/11] | 6.99 (7.47) [2/11] | 0.531 (1.65) | 0.655 (0.785) | 0.077 (0.300) | 0.15 (osqp) |
| osqprand_nx10_s2 | 160 | 1.27 (1.35) | 0.123 (0.125) | 2.37 (2.45) | 0.595 (0.617) | 0.661 (0.681) | 0.075 (0.082) | 0.61 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.76 (1.99) | 0.235 (0.270) [1/11] | 7.86 (8.62) | 1.06 (1.32) [3/11] | 0.804 (0.904) | 1.15 (2.92) | 1.43 (piqp) |
| osqprand_nx20_s1 | 320 | 5.53 (5.64) | 0.486 (0.559) [2/11] | 37.10 (37.38) [3/11] | 24.78 (25.32) | 3.14 (3.41) | 0.211 (0.634) | 0.07 (piqp) |
| osqprand_nx20_s2 | 320 | 5.10 (5.63) | 0.486 (0.547) [1/11] | 7.60 (8.46) [1/11] | 3.09 (6.61) | 3.24 (3.32) | 0.824 (2.07) | 0.27 (osqp) |
| osqprand_nx20_s3 | 320 | 5.14 (6.35) | 0.491 (0.632) [1/11] | 37.19 (39.35) | 1.62 (3.98) | 3.01 (3.58) | 0.212 (1.92) | 0.13 (osqp) |
| osqprand_nx40_s1 | 640 | 23.00 (27.26) | 1.65 (1.90) | 235 (239) | 28.29 (55.92) | 16.52 (18.32) | 0.719 (47.17) | 0.44 (hpipm) |
| osqprand_nx40_s2 | 640 | 22.82 (32.23) | 1.43 (1.78) [3/11] | 23.08 (29.67) [3/11] | 9.65 (56.33) | 16.45 (19.75) | 0.673 (6.38) | 0.07 (osqp) |
| osqprand_nx40_s3 | 640 | 20.09 (22.62) | 1.08 (1.31) [1/11] | 24.02 (24.47) [1/11] | 5.58 (10.92) | 15.17 (16.92) | 0.713 (6.05) | 0.13 (osqp) |
| osqprand_nx80_s1 | 1280 | 134 (150) | 8.31 (9.22) [1/11] | 1701 (1713) | 212 (274) [1/11] | 120 (134) | 18.46 (105) | 0.15 (piqp) |

Warm cells: median (max) ms.

### osqprand, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 6 / 8 / -- / 10 | 4 / 6 / -- / 8 | 6 / 8 / -- / 10 | 50 / 125 / -- / 150 | 5 / 7 / -- / 9 | 20 / 20 / -- / 20 |
| osqprand_nx10_s2 | 4 / 6 / -- / 7 | 3 / 4 / -- / 4 | 5 / 6 / -- / 8 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 20 / 20 / -- / 20 |
| osqprand_nx10_s3 | 6 / 9 / -- / 10 | 5 / 8 / -- / 9 | 7 / 9 / -- / 12 | 50 / 75 / -- / 125 | 6 / 9 / -- / 10 | 60 / 60 / -- / 131 |
| osqprand_nx20_s1 | 6 / 7 / -- / 9 | 5 / 7 / -- / 7 | 7 / 9 / -- / 10 | 100 / 225 / -- / 300 | 6 / 8 / -- / 9 | 20 / 20 / -- / 20 |
| osqprand_nx20_s2 | 6 / 8 / -- / 10 | 5 / 8 / -- / 8 | 6 / 10 / -- / 10 | 50 / 100 / -- / 175 | 7 / 8 / -- / 10 | 20 / 20 / -- / 20 |
| osqprand_nx20_s3 | 6 / 8 / -- / 10 | 5 / 8 / -- / 9 | 7 / 9 / -- / 11 | 25 / 75 / -- / 125 | 6 / 8 / -- / 10 | 30 / 30 / -- / 30 |
| osqprand_nx40_s1 | 6 / 8 / -- / 10 | 5 / 8 / -- / 9 | 6 / 9 / -- / 11 | 75 / 200 / -- / 375 | 6 / 8 / -- / 10 | 20 / 20 / -- / 20 |
| osqprand_nx40_s2 | 6 / 8 / -- / 10 | 5 / 7 / -- / 9 | 7 / 8 / -- / 10 | 50 / 400 / -- / 650 | 7 / 8 / -- / 10 | 100 / 100 / -- / 100 |
| osqprand_nx40_s3 | 5 / 7 / -- / 8 | 5 / 6 / -- / 6 | 5 / 8 / -- / 9 | 25 / 75 / -- / 100 | 5 / 7 / -- / 8 | 20 / 20 / -- / 20 |
| osqprand_nx80_s1 | 7 / 9 / -- / 10 | 6 / 7 / -- / 8 | 9 / 11 / -- / 12 | 125 / 325 / -- / 500 | 8 / 9 / -- / 11 | 30 / 30 / -- / 30 |

### osqprand, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 5 / 6 / -- / 8 | 3 / 4 / -- / 5 | 6 / 7 / -- / 8 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| osqprand_nx10_s2 | 4 / 6 / -- / 7 | 3 / 3 / -- / 4 | 5 / 6 / -- / 8 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| osqprand_nx10_s3 | 6 / 8 / -- / 10 | 5 / 7 / -- / 8 | 7 / 9 / -- / 11 | 25 / 50 / -- / 125 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| osqprand_nx20_s1 | 7 / 8 / -- / 10 | 5 / 7 / -- / 7 | 7 / 9 / -- / 10 | 50 / 475 / -- / 825 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx20_s2 | 6 / 8 / -- / 9 | 5 / 7 / -- / 8 | 6 / 9 / -- / 10 | 25 / 50 / -- / 100 | 6 / 8 / -- / 10 | 20 / 20 / -- / 20 |
| osqprand_nx20_s3 | 6 / 8 / -- / 9 | 5 / 7 / -- / 7 | 6 / 8 / -- / 10 | 25 / 50 / -- / 50 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx40_s1 | 6 / 8 / -- / 9 | 5 / 8 / -- / 8 | 5 / 9 / -- / 10 | 25 / 125 / -- / 175 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx40_s2 | 6 / 8 / -- / 9 | 4 / 7 / -- / 8 | 7 / 8 / -- / 10 | 25 / 75 / -- / 75 | 6 / 7 / -- / 9 | 20 / 0 / -- / 0 |
| osqprand_nx40_s3 | 5 / 7 / -- / 8 | 4 / 6 / -- / 6 | 5 / 7 / -- / 9 | 25 / 50 / -- / 50 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |
| osqprand_nx80_s1 | 6 / 8 / -- / 10 | 5 / 7 / -- / 8 | 8 / 10 / -- / 11 | 25 / 250 / -- / 450 | 7 / 8 / -- / 10 | 20 / 20 / -- / 20 |

### osqprand, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 0.516 | 0.075 | 4.80 | 0.366 | 0.280 | 4.31 |
| osqprand_nx10_s2 | 0.525 | 0.077 | 4.79 | 0.370 | 0.278 | 4.41 |
| osqprand_nx10_s3 | 0.549 | 0.078 | 4.87 | 0.363 | 0.273 | 4.45 |
| osqprand_nx20_s1 | 1.40 | 0.099 | 29.23 | 1.25 | 0.806 | 12.88 |
| osqprand_nx20_s2 | 1.37 | 0.099 | 29.18 | 1.05 | 0.845 | 12.98 |
| osqprand_nx20_s3 | 1.25 | 0.098 | 29.32 | 1.13 | 0.836 | 13.14 |
| osqprand_nx40_s1 | 4.32 | 0.185 | 210 | 4.73 | 2.97 | 62.65 |
| osqprand_nx40_s2 | 4.25 | 0.230 | 207 | 4.65 | 3.07 | 62.04 |
| osqprand_nx40_s3 | 4.38 | 0.253 | 210 | 4.35 | 3.32 | 61.87 |
| osqprand_nx80_s1 | 16.25 | 0.830 | 1523 | 25.61 | 15.13 | 432 |

## reduced

### reduced, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 16.29 | 12.93 | 12.47 | 10.73 | 5.13 | 0.48 (mumblebee_fast_ct) | 0.41 |
| reduced_k4 | 3880 | 16.35 | 13.12 | 12.15 | 10.92 | 5.26 | 0.48 (mumblebee_fast_ct) | 0.43 |
| reduced_k2 | 3920 | 16.65 | 13.87 | 12.44 | 11.29 | 5.32 | 0.47 (mumblebee_fast_ct) | 0.43 |
| reduced_k0 | 5120 | 40.58 | 27.77 | 26.06 | 24.91 | 8.23 | 0.33 (mumblebee_fast_ct) | 0.32 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 19.12 | 16.88 | 16.12 | 13.84 | 5.03 | 0.36 (mumblebee_fast_ct) | 0.31 |
| reduced_k4 | 3880 | 19.38 | 17.20 | 15.83 | 14.07 | 5.32 | 0.38 (mumblebee_fast_ct) | 0.34 |
| reduced_k2 | 3920 | 19.83 | 18.15 | 16.39 | 14.40 | 5.36 | 0.37 (mumblebee_fast_ct) | 0.33 |
| reduced_k0 | 5120 | 61.58 | 36.50 | 34.17 | 32.99 | 8.43 | 0.26 (mumblebee_fast_ct) | 0.25 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 22.29 | 20.90 | 20.05 | 16.95 | 5.06 | 0.30 (mumblebee_fast_ct) | 0.25 |
| reduced_k4 | 3880 | 21.65 | 21.07 | 19.45 | 17.27 | 5.31 | 0.31 (mumblebee_fast_ct) | 0.27 |
| reduced_k2 | 3920 | 23.12 | 22.69 | 19.71 | 17.53 | 5.40 | 0.31 (mumblebee_fast_ct) | 0.27 |
| reduced_k0 | 5120 | 71.41 | 44.87 | 42.41 | 40.48 | 8.43 | 0.21 (mumblebee_fast_ct) | 0.20 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 25.05 | 25.02 | 23.62 | 20.32 | 4.93 | 0.24 (mumblebee_fast_ct) | 0.21 |
| reduced_k4 | 3880 | 24.04 | 25.08 | 23.84 | 20.21 | 5.29 | 0.26 (mumblebee_fast_ct) | 0.22 |
| reduced_k2 | 3920 | 25.25 | 26.92 | 23.28 | 20.94 | 5.46 | 0.26 (mumblebee_fast_ct) | 0.23 |
| reduced_k0 | 5120 | 71.11 | 53.71 | 51.85 | 48.23 | 8.37 | 0.17 (mumblebee_fast_ct) | 0.16 |

Cold cells: median ms of the solve; setup is separate.

### reduced, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 15.56 (15.87) | 12.62 (12.65) | 12.07 (12.17) | 10.49 (10.64) | 0.924 (0.992) | 0.09 (mumblebee_fast_ct) | 0.08 |
| reduced_k4 | 3880 | 16.11 (16.39) | 12.82 (12.89) | 11.81 (11.93) | 10.63 (10.69) | 0.953 (1.00) | 0.09 (mumblebee_fast_ct) | 0.08 |
| reduced_k2 | 3920 | 16.35 (16.74) | 13.75 (13.90) | 12.13 (12.26) | 10.90 (11.00) | 0.980 (1.19) | 0.09 (mumblebee_fast_ct) | 0.08 |
| reduced_k0 | 5120 | 41.30 (41.87) | 27.38 (27.58) | 25.93 (26.21) | 24.69 (24.81) | 1.64 (1.89) | 0.07 (mumblebee_fast_ct) | 0.06 |

Warm cells: median (max) ms.

### reduced, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 18.53 (18.90) | 16.63 (16.76) | 15.82 (15.93) | 13.55 (13.76) | 0.932 (1.03) | 0.07 (mumblebee_fast_ct) | 0.06 |
| reduced_k4 | 3880 | 18.99 (19.26) | 16.83 (20.89) | 15.43 (19.09) | 14.25 (17.63) | 0.964 (1.03) | 0.07 (mumblebee_fast_ct) | 0.06 |
| reduced_k2 | 3920 | 19.50 (19.66) | 17.95 (22.30) | 15.94 (19.79) | 14.43 (17.79) | 0.958 (1.08) | 0.07 (mumblebee_fast_ct) | 0.06 |
| reduced_k0 | 5120 | 61.99 (62.80) | 35.88 (36.10) | 34.50 (34.70) | 32.39 (32.57) | 1.64 (1.70) | 0.05 (mumblebee_fast_ct) | 0.05 |

Warm cells: median (max) ms.

### reduced, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 21.78 (22.14) | 20.69 (20.81) | 19.23 (19.50) | 16.76 (16.94) | 0.904 (0.981) | 0.05 (mumblebee_fast_ct) | 0.05 |
| reduced_k4 | 3880 | 21.46 (21.89) | 20.85 (24.92) | 19.20 (22.86) | 17.32 (20.68) | 0.935 (1.06) | 0.05 (mumblebee_fast_ct) | 0.05 |
| reduced_k2 | 3920 | 22.57 (22.80) | 21.99 (26.44) | 19.33 (23.13) | 17.71 (21.31) | 0.974 (1.09) | 0.06 (mumblebee_fast_ct) | 0.05 |
| reduced_k0 | 5120 | 71.48 (71.80) | 44.48 (44.59) | 42.18 (42.26) | 40.16 (40.55) | 1.64 (1.74) | 0.04 (mumblebee_fast_ct) | 0.04 |

Warm cells: median (max) ms.

### reduced, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 24.34 (24.76) | 24.66 (24.84) | 23.12 (23.55) | 19.86 (20.02) | 0.893 (0.945) | 0.04 (mumblebee_fast_ct) | 0.04 |
| reduced_k4 | 3880 | 24.00 (24.36) | 24.92 (25.03) | 23.64 (23.84) | 20.16 (20.57) | 0.942 (1.00) | 0.05 (mumblebee_fast_ct) | 0.04 |
| reduced_k2 | 3920 | 25.06 (25.56) | 26.46 (26.61) | 23.05 (23.20) | 21.06 (21.34) | 0.943 (1.04) | 0.04 (mumblebee_fast_ct) | 0.04 |
| reduced_k0 | 5120 | 71.82 (72.10) | 53.96 (54.24) | 50.32 (50.74) | 48.01 (48.31) | 1.63 (1.72) | 0.03 (mumblebee_fast_ct) | 0.03 |

Warm cells: median (max) ms.

### reduced, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| reduced_k8 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 20 / 20 / 20 / 20 |
| reduced_k4 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 20 / 20 / 20 / 20 |
| reduced_k2 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 20 / 20 / 20 / 20 |
| reduced_k0 | 3 / 5 / 6 / 6 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 20 / 20 / 20 / 20 |

### reduced, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| reduced_k8 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 0 / 0 / 0 / 0 |
| reduced_k4 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 0 / 0 / 0 / 0 |
| reduced_k2 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 0 / 0 / 0 / 0 |
| reduced_k0 | 3 / 5 / 6 / 6 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 0 / 0 / 0 / 0 |

### reduced, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| reduced_k8 | 9.78 | 17.36 | 11.26 | 11.20 | 83.57 |
| reduced_k4 | 9.39 | 17.24 | 10.83 | 11.15 | 81.01 |
| reduced_k2 | 9.08 | 17.90 | 10.79 | 10.99 | 77.97 |
| reduced_k0 | 11.20 | 21.40 | 14.60 | 15.07 | 178 |

## single_di_box

### single_di_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.299 | 0.069 | 0.674 | 0.465 | 0.385 | 0.078 | 0.087 | 0.171 | 2.50 (hpipm) | 0.37 |
| di_box_N25 | 225 | 0.778 | 0.153 | 1.55 | 1.17 | 0.822 | 0.203 | 0.229 | 0.577 | 3.78 (hpipm) | 0.49 |
| di_box_N50 | 450 | 1.22 | 0.283 | 2.82 | 2.06 | 1.64 | 0.395 | 0.422 | 0.961 | 3.40 (hpipm) | 0.47 |
| di_box_N100 | 900 | 2.04 | 0.554 | 5.21 | 4.29 | 3.08 | 0.806 | 0.985 | 1.37 | 2.48 (hpipm) | 0.32 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.384 | 0.090 | 0.871 | 0.641 | 0.559 | 0.160 | 0.106 | 0.170 | 1.88 (hpipm) | 0.27 |
| di_box_N25 | 225 | 0.969 | 0.214 | 2.36 | 1.76 | 1.40 | 0.396 | 0.294 | 0.612 | 2.86 (hpipm) | 0.35 |
| di_box_N50 | 450 | 1.74 | 0.358 | 4.48 | 3.44 | 2.60 | 0.783 | 0.573 | 0.948 | 2.65 (hpipm) | 0.28 |
| di_box_N100 | 900 | 3.28 | 0.772 | 8.79 | 6.82 | 5.06 | 1.59 | 1.10 | 1.51 | 1.95 (hpipm) | 0.22 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.449 | 0.096 | 1.16 | 0.831 | 0.655 | 0.221 | 0.126 | 0.176 | 1.82 (hpipm) | 0.21 |
| di_box_N25 | 225 | 1.13 | 0.266 | 3.02 | 2.19 | 1.73 | 0.587 | 0.345 | 0.639 | 2.40 (hpipm) | 0.29 |
| di_box_N50 | 450 | 2.25 | 0.437 | 5.62 | 4.31 | 3.26 | 1.20 | 0.700 | 1.00 | 2.29 (hpipm) | 0.23 |
| di_box_N100 | 900 | 4.15 | 0.901 | 11.10 | 8.55 | 6.36 | 2.28 | 1.30 | 1.51 | 1.68 (hpipm) | 0.18 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.281 (0.292) | 0.056 (0.058) | 0.594 (0.699) | 0.435 (0.556) | 0.363 (0.420) | 0.080 (0.082) | 0.098 (0.103) | 0.047 (0.086) | 0.84 (hpipm) | 0.11 |
| di_box_N25 | 225 | 0.660 (0.673) | 0.143 (0.153) | 1.41 (1.77) | 1.10 (1.32) | 0.842 (1.05) | 0.203 (0.209) | 0.224 (0.263) | 0.138 (0.189) | 0.97 (hpipm) | 0.13 |
| di_box_N50 | 450 | 1.08 (1.34) | 0.294 (0.365) | 2.71 (3.37) | 2.06 (2.41) | 1.60 (1.91) | 0.393 (0.403) | 0.430 (0.511) | 0.262 (0.364) | 0.89 (hpipm) | 0.13 |
| di_box_N100 | 900 | 1.99 (2.37) | 0.493 (0.586) | 5.01 (6.02) | 4.27 (4.98) | 3.11 (3.77) | 0.815 (0.843) | 0.851 (0.974) | 0.519 (0.741) | 1.05 (hpipm) | 0.12 |

Warm cells: median (max) ms.

### single_di_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.410 (0.430) | 0.085 (0.088) | 0.949 (1.02) | 0.722 (0.776) | 0.549 (0.577) | 0.151 (0.155) | 0.129 (0.136) | 0.046 (0.082) | 0.54 (hpipm) | 0.06 |
| di_box_N25 | 225 | 0.937 (1.07) | 0.187 (0.193) | 2.34 (2.40) | 1.72 (1.79) | 1.36 (1.39) | 0.384 (0.396) | 0.291 (0.300) | 0.141 (0.193) | 0.75 (hpipm) | 0.08 |
| di_box_N50 | 450 | 1.69 (1.93) | 0.359 (0.381) | 4.50 (4.56) | 3.42 (3.61) | 2.59 (2.65) | 0.795 (0.821) | 0.593 (0.619) | 0.264 (0.355) | 0.73 (hpipm) | 0.08 |
| di_box_N100 | 900 | 3.34 (3.77) | 0.711 (0.726) | 8.67 (8.74) | 6.75 (6.82) | 5.07 (5.11) | 1.56 (1.61) | 1.07 (1.11) | 0.522 (0.734) | 0.73 (hpipm) | 0.08 |

Warm cells: median (max) ms.

### single_di_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.497 (0.557) | 0.094 (0.113) | 1.71 (1.87) | 0.906 (1.04) | 0.715 (0.801) | 0.151 (0.227) | 0.141 (0.163) | 0.047 (0.083) | 0.51 (hpipm) | 0.05 |
| di_box_N25 | 225 | 1.19 (1.23) | 0.222 (0.241) | 4.21 (4.32) | 2.22 (2.30) | 1.73 (1.78) | 0.397 (0.594) | 0.345 (0.385) | 0.138 (0.185) | 0.62 (hpipm) | 0.06 |
| di_box_N50 | 450 | 2.12 (2.32) | 0.423 (0.443) | 7.74 (7.85) | 4.34 (4.44) | 3.22 (3.28) | 0.819 (1.27) | 0.706 (0.778) | 0.266 (0.363) | 0.63 (hpipm) | 0.06 |
| di_box_N100 | 900 | 4.19 (4.55) | 0.830 (0.935) | 14.93 (16.23) | 8.49 (9.26) | 6.34 (7.03) | 1.58 (2.33) | 1.32 (1.39) | 0.512 (0.725) | 0.62 (hpipm) | 0.06 |

Warm cells: median (max) ms.

### single_di_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 9 | 5 / 7 / -- / 9 | 5 / 7 / -- / 9 | 25 / 50 / -- / 75 | 5 / 6 / -- / 8 | 70 / 70 / -- / 70 |
| di_box_N25 | 5 / 7 / -- / 9 | 4 / 7 / -- / 9 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 70 / 70 / -- / 70 |
| di_box_N50 | 4 / 7 / -- / 9 | 4 / 7 / -- / 8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 40 / 40 / -- / 40 |
| di_box_N100 | 4 / 7 / -- / 9 | 4 / 7 / -- / 8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 75 | 7 / 8 / -- / 10 | 25 / 40 / -- / 40 |

### single_di_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 5 / 8 / -- / 10 | 4 / 7 / -- / 8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 50 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |
| di_box_N25 | 5 / 7 / -- / 10 | 5 / 7 / -- / 9 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 50 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| di_box_N50 | 4 / 7 / -- / 9 | 4 / 7 / -- / 9 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 50 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| di_box_N100 | 4 / 7 / -- / 9 | 4 / 7 / -- / 8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 50 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |

### single_di_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 0.233 | 0.120 | 0.546 | 0.344 | 0.327 | 0.106 | 0.110 | 1.09 |
| di_box_N25 | 0.529 | 0.180 | 1.42 | 0.748 | 0.691 | 0.272 | 0.258 | 2.90 |
| di_box_N50 | 0.946 | 0.250 | 2.66 | 1.49 | 1.28 | 0.465 | 0.390 | 5.23 |
| di_box_N100 | 1.68 | 0.395 | 4.88 | 2.83 | 2.43 | 0.877 | 0.641 | 9.47 |

## single_di_soc

### single_di_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.294 | 0.382 | 0.315 | 0.330 | 0.096 | 0.33 (clarabel) | 0.30 |
| di_soc_N25 | 225 | 0.772 | 1.09 | 0.877 | 0.832 | 0.446 | 0.58 (clarabel) | 0.51 |
| di_soc_N50 | 450 | 1.43 | 2.22 | 2.01 | 1.67 | 1.28 | 0.89 (clarabel) | 0.64 |
| di_soc_N100 | 900 | 2.62 | 4.14 | 3.53 | 3.33 | 2.05 | 0.78 (clarabel) | 0.58 |

Cold cells: median ms of the solve; setup is separate.

### single_di_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.449 | 0.576 | 0.488 | 0.427 | 0.090 | 0.21 (mumblebee_fast_ct) | 0.18 |
| di_soc_N25 | 225 | 1.22 | 1.47 | 1.23 | 1.17 | 0.524 | 0.45 (mumblebee_fast_ct) | 0.43 |
| di_soc_N50 | 450 | 2.29 | 2.98 | 2.57 | 2.40 | 1.61 | 0.70 (clarabel) | 0.63 |
| di_soc_N100 | 900 | 4.16 | 5.47 | 4.74 | 4.39 | 2.28 | 0.55 (clarabel) | 0.48 |

Cold cells: median ms of the solve; setup is separate.

### single_di_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.501 | 0.668 | 0.527 | 0.570 | 0.115 | 0.23 (clarabel) | 0.22 |
| di_soc_N25 | 225 | 1.45 | 1.68 | 1.46 | 1.42 | 0.552 | 0.39 (mumblebee_fast_ct) | 0.38 |
| di_soc_N50 | 450 | 2.53 | 3.61 | 3.14 | 2.78 | 1.61 | 0.64 (clarabel) | 0.51 |
| di_soc_N100 | 900 | 4.84 | 6.82 | 5.75 | 5.31 | 2.27 | 0.47 (clarabel) | 0.39 |

Cold cells: median ms of the solve; setup is separate.

### single_di_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.525 | 0.661 | 0.654 | 0.509 | 0.114 | 0.22 (mumblebee_fast_ct) | 0.17 |
| di_soc_N25 | 225 | 1.50 | 1.85 | 1.56 | 1.44 | 0.670 | 0.46 (mumblebee_fast_ct) | 0.43 |
| di_soc_N50 | 450 | 2.71 | 4.06 | 3.32 | 3.01 | 1.57 | 0.58 (clarabel) | 0.47 |
| di_soc_N100 | 900 | 5.43 | 6.94 | 6.04 | 5.48 | 2.47 | 0.45 (clarabel) | 0.41 |

Cold cells: median ms of the solve; setup is separate.

### single_di_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.285 (0.306) | 0.363 (0.382) | 0.300 (0.312) | 0.288 (0.307) | 0.069 (0.118) | 0.24 (clarabel) | 0.23 |
| di_soc_N25 | 225 | 0.713 (0.764) | 0.887 (1.13) | 0.734 (0.921) | 0.686 (0.890) | 0.245 (0.451) | 0.36 (mumblebee_fast_ct) | 0.33 |
| di_soc_N50 | 450 | 1.31 (1.34) | 1.72 (2.07) | 1.40 (1.73) | 1.32 (1.59) | 0.477 (0.931) | 0.37 (clarabel) | 0.34 |
| di_soc_N100 | 900 | 2.53 (2.62) | 3.29 (3.98) | 2.74 (3.35) | 2.48 (3.03) | 0.903 (1.77) | 0.36 (mumblebee_fast_ct) | 0.33 |

Warm cells: median (max) ms.

### single_di_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.412 (0.470) | 0.537 (0.634) | 0.447 (0.521) | 0.419 (0.479) | 0.095 (0.184) | 0.23 (clarabel) | 0.21 |
| di_soc_N25 | 225 | 1.16 (1.19) | 1.41 (1.48) | 1.23 (1.30) | 1.14 (1.17) | 0.324 (0.692) | 0.28 (mumblebee_fast_ct) | 0.26 |
| di_soc_N50 | 450 | 2.19 (2.26) | 2.84 (3.21) | 2.47 (2.75) | 2.11 (2.37) | 0.636 (1.37) | 0.30 (mumblebee_fast_ct) | 0.26 |
| di_soc_N100 | 900 | 3.60 (4.15) | 4.65 (5.35) | 4.10 (4.67) | 3.66 (4.30) | 1.22 (2.54) | 0.34 (clarabel) | 0.30 |

Warm cells: median (max) ms.

### single_di_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.513 (0.579) | 0.672 (0.719) | 0.527 (0.616) | 0.524 (0.585) | 0.121 (0.178) | 0.24 (clarabel) | 0.23 |
| di_soc_N25 | 225 | 1.30 (1.44) | 2.46 (2.68) | 1.37 (1.58) | 1.25 (1.44) | 0.376 (0.694) | 0.30 (mumblebee_fast_ct) | 0.27 |
| di_soc_N50 | 450 | 2.42 (2.73) | 3.21 (3.92) | 2.73 (3.30) | 2.40 (2.93) | 0.785 (1.78) | 0.33 (mumblebee_fast_ct) | 0.29 |
| di_soc_N100 | 900 | 4.76 (5.44) | 6.11 (6.91) | 5.28 (5.98) | 4.64 (5.30) | 1.30 (2.56) | 0.28 (mumblebee_fast_ct) | 0.25 |

Warm cells: median (max) ms.

### single_di_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.514 (0.646) | 1.02 (1.13) | 0.610 (0.688) | 0.545 (0.632) | 0.115 (0.177) | 0.22 (clarabel) | 0.19 |
| di_soc_N25 | 225 | 1.27 (1.58) | 2.64 (2.90) | 1.51 (1.67) | 1.39 (1.59) | 0.392 (0.711) | 0.31 (clarabel) | 0.26 |
| di_soc_N50 | 450 | 2.52 (3.09) | 5.09 (5.82) | 2.97 (3.66) | 2.71 (3.31) | 0.761 (4.61) | 0.30 (clarabel) | 0.26 |
| di_soc_N100 | 900 | 4.85 (5.95) | 9.38 (10.83) | 5.88 (7.00) | 5.08 (6.20) | 1.45 (2.58) | 0.30 (clarabel) | 0.25 |

Warm cells: median (max) ms.

### single_di_soc, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| di_soc_N10 | 4 / 6 / 7 / 7 | 5 / 7 / 8 / 8 | 5 / 7 / 8 / 8 | 5 / 7 / 8 / 8 | 20 / 20 / 20 / 20 |
| di_soc_N25 | 4 / 7 / 8 / 9 | 6 / 8 / 9 / 10 | 6 / 8 / 9 / 10 | 6 / 8 / 9 / 10 | 40 / 40 / 40 / 40 |
| di_soc_N50 | 4 / 7 / 8 / 9 | 6 / 8 / 10 / 11 | 6 / 8 / 10 / 11 | 6 / 8 / 10 / 11 | 40 / 40 / 40 / 40 |
| di_soc_N100 | 4 / 7 / 8 / 9 | 6 / 8 / 10 / 10 | 6 / 8 / 10 / 10 | 6 / 8 / 10 / 10 | 40 / 40 / 40 / 40 |

### single_di_soc, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| di_soc_N10 | 4 / 6 / 8 / 8 | 5 / 7 / 8 / 9 | 5 / 7 / 8 / 9 | 5 / 7 / 8 / 9 | 0 / 0 / 0 / 0 |
| di_soc_N25 | 4 / 7 / 8 / 8 | 5 / 8 / 9 / 10 | 5 / 8 / 9 / 10 | 5 / 8 / 9 / 10 | 0 / 0 / 0 / 0 |
| di_soc_N50 | 4 / 7 / 8 / 8 | 5 / 8 / 9 / 10 | 5 / 8 / 9 / 10 | 5 / 8 / 9 / 10 | 0 / 0 / 20 / 20 |
| di_soc_N100 | 4 / 6 / 8 / 8 | 5 / 7 / 9 / 10 | 5 / 7 / 9 / 10 | 5 / 7 / 9 / 10 | 0 / 0 / 20 / 20 |

### single_di_soc, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| di_soc_N10 | 0.228 | 0.472 | 0.325 | 0.299 | 1.60 |
| di_soc_N25 | 0.532 | 1.04 | 0.662 | 0.606 | 3.93 |
| di_soc_N50 | 0.953 | 1.98 | 1.24 | 1.18 | 7.18 |
| di_soc_N100 | 1.64 | 3.56 | 2.22 | 2.25 | 13.52 |

## single_quad

### single_quad, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.790 | 0.119 | 1.10 | 0.875 | 0.828 | 0.247 | 0.269 | 0.246 | 2.07 (hpipm) | 0.28 |
| quad_N25 | 400 | 1.66 | 0.290 | 2.20 | 1.93 | 1.85 | 0.581 | 0.626 | 0.783 | 2.70 (hpipm) | 0.41 |
| quad_N50 | 800 | 3.21 | 0.556 | 4.82 | 3.14 | 3.55 | 1.07 | 1.13 | 1.41 | 2.53 (hpipm) | 0.45 |
| quad_N100 | 1600 | 6.12 | 0.796 | 9.27 | 6.68 | 6.53 | 1.98 | 2.62 | 2.53 | 3.18 (hpipm) | 0.38 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.930 | 0.137 | 1.49 | 1.21 | 1.21 | 0.451 | 0.347 | 0.217 | 1.58 (hpipm) | 0.18 |
| quad_N25 | 400 | 2.13 | 0.385 | 3.55 | 2.49 | 2.42 | 1.06 | 0.788 | 0.759 | 1.97 (hpipm) | 0.31 |
| quad_N50 | 800 | 4.07 | 0.546 | 6.89 | 4.93 | 4.77 | 1.94 | 1.48 | 1.44 | 2.64 (hpipm) | 0.29 |
| quad_N100 | 1600 | 8.09 | 1.29 | 13.51 | 9.48 | 9.35 | 3.78 | 2.82 | 2.70 | 2.08 (hpipm) | 0.28 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.996 | 0.146 | 1.69 | 1.29 | 1.21 | 0.638 | 0.387 | 0.213 | 1.46 (hpipm) | 0.17 |
| quad_N25 | 400 | 2.34 | 0.337 | 4.04 | 2.85 | 2.79 | 1.53 | 0.870 | 0.807 | 2.40 (hpipm) | 0.28 |
| quad_N50 | 800 | 5.04 | 0.614 | 7.93 | 5.58 | 5.41 | 2.95 | 1.60 | 1.43 | 2.33 (hpipm) | 0.26 |
| quad_N100 | 1600 | 9.39 | 1.29 | 15.29 | 10.94 | 10.32 | 5.84 | 3.56 | 2.59 | 2.00 (hpipm) | 0.24 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.598 (0.749) | 0.078 (0.113) | 0.724 (0.954) | 0.653 (0.883) | 0.656 (0.943) | 0.238 (0.251) | 0.235 (0.293) | 0.056 (0.231) | 0.71 (hpipm) | 0.09 |
| quad_N25 | 400 | 1.33 (1.60) | 0.222 (0.296) | 1.98 (2.49) | 1.42 (1.80) | 1.30 (1.69) | 0.578 (0.593) | 0.521 (0.627) | 0.125 (0.554) | 0.56 (hpipm) | 0.09 |
| quad_N50 | 800 | 2.57 (3.10) | 0.417 (0.562) | 3.63 (4.85) | 2.33 (3.01) | 2.44 (3.18) | 1.02 (1.05) | 0.935 (1.14) | 0.232 (1.11) | 0.56 (hpipm) | 0.10 |
| quad_N100 | 1600 | 4.89 (5.91) | 0.814 (1.19) | 7.00 (9.06) | 5.01 (6.39) | 4.86 (6.12) | 1.92 (2.00) | 2.13 (2.51) | 0.442 (2.07) | 0.54 (hpipm) | 0.09 |

Warm cells: median (max) ms.

### single_quad, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.646 (0.884) | 0.086 (0.124) | 1.25 (1.55) | 0.939 (1.20) | 0.916 (1.15) | 0.429 (0.447) | 0.283 (0.356) | 0.051 (0.222) | 0.60 (hpipm) | 0.05 |
| quad_N25 | 400 | 1.80 (2.09) | 0.279 (0.431) | 2.99 (3.47) | 2.05 (2.43) | 2.10 (2.47) | 1.02 (1.06) | 0.705 (0.816) | 0.121 (0.542) | 0.43 (hpipm) | 0.06 |
| quad_N50 | 800 | 3.19 (3.77) | 0.369 (0.537) | 5.71 (6.69) | 4.03 (4.83) | 3.85 (4.54) | 1.88 (1.98) | 1.24 (1.45) | 0.227 (1.10) | 0.62 (hpipm) | 0.06 |
| quad_N100 | 1600 | 6.30 (7.42) | 0.770 (1.10) | 11.11 (13.20) | 7.75 (9.25) | 7.46 (8.80) | 3.64 (3.78) | 2.39 (2.80) | 0.443 (2.08) | 0.58 (hpipm) | 0.06 |

Warm cells: median (max) ms.

### single_quad, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.821 (1.05) | 0.095 (0.150) | 2.76 (3.06) | 1.08 (1.44) | 1.05 (1.34) | 0.398 (0.617) | 0.352 (0.401) | 0.052 (0.201) | 0.55 (hpipm) | 0.05 |
| quad_N25 | 400 | 1.88 (2.40) | 0.220 (0.396) | 3.45 (4.39) | 2.48 (3.16) | 2.37 (3.00) | 0.970 (1.52) | 0.760 (0.934) | 0.126 (0.563) | 0.57 (hpipm) | 0.05 |
| quad_N50 | 800 | 3.84 (4.94) | 0.401 (0.697) | 6.72 (8.76) | 4.71 (6.08) | 4.52 (5.85) | 1.92 (3.02) | 1.39 (1.69) | 0.234 (1.10) | 0.58 (hpipm) | 0.05 |
| quad_N100 | 1600 | 7.51 (9.57) | 0.949 (1.45) | 13.24 (17.44) | 9.23 (11.97) | 9.10 (11.89) | 3.70 (5.75) | 3.04 (3.39) | 0.475 (2.25) | 0.50 (hpipm) | 0.05 |

Warm cells: median (max) ms.

### single_quad, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 20 / 20 / -- / 20 |
| quad_N25 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 20 / 20 / -- / 20 |
| quad_N50 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 20 / 20 / -- / 20 |
| quad_N100 | 5 / 7 / -- / 8 | 4 / 6 / -- / 6 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 6 / 7 / -- / 9 | 20 / 20 / -- / 20 |

### single_quad, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 4 / 5 / -- / 7 | 3 / 4 / -- / 4 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 25 / 50 / -- / 50 | 4 / 5 / -- / 7 | 0 / 0 / -- / 0 |
| quad_N25 | 4 / 6 / -- / 7 | 3 / 4 / -- / 4 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 25 / 50 / -- / 50 | 4 / 6 / -- / 7 | 0 / 0 / -- / 0 |
| quad_N50 | 4 / 6 / -- / 7 | 3 / 4 / -- / 4 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 25 / 50 / -- / 50 | 4 / 6 / -- / 7 | 0 / 0 / -- / 0 |
| quad_N100 | 4 / 6 / -- / 7 | 3 / 4 / -- / 4 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 4 / 6 / -- / 7 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |

### single_quad, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 0.399 | 0.107 | 1.49 | 0.829 | 0.836 | 0.269 | 0.261 | 3.51 |
| quad_N25 | 0.840 | 0.119 | 3.36 | 1.52 | 1.60 | 0.590 | 0.530 | 8.37 |
| quad_N50 | 1.53 | 0.239 | 6.55 | 2.99 | 3.01 | 1.05 | 1.04 | 16.36 |
| quad_N100 | 2.96 | 0.455 | 12.63 | 5.66 | 6.17 | 2.01 | 2.06 | 30.65 |

## Shifted geometric means (ms; shift 0.1 ms; failures charged the time limit) and failure rates

### cold, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.13 (0% fail) | 0.289 (0% fail) | 3.61 (0% fail) | 2.05 (0% fail) | 2.06 (0% fail) | 1.26 (0% fail) | 0.707 (0% fail) | 1.16 (0% fail) |
| fleet_grid_box | 2.32 (0% fail) | 20.82 (22% fail) | 4.65 (0% fail) | -- | -- | 9.45 (11% fail) | 1.12 (0% fail) | 1.22 (0% fail) |
| fleet_grid_box_b4 | 6.88 (0% fail) | -- | 8.60 (0% fail) | 6.26 (0% fail) | 5.86 (0% fail) | 13.58 (8% fail) | 4.27 (0% fail) | 2.18 (0% fail) |
| fleet_grid_soc | 15.62 (0% fail) | -- | 13.21 (0% fail) | 12.25 (0% fail) | -- | -- | -- | 7.46 (0% fail) |
| fleet_grid_soc_b4 | 14.30 (0% fail) | -- | 10.64 (0% fail) | -- | -- | -- | -- | 5.26 (0% fail) |
| fleet_ring_box | 4.98 (0% fail) | 7.01 (4% fail) | 8.96 (0% fail) | -- | -- | 30.16 (17% fail) | 4.08 (4% fail) | 2.59 (0% fail) |
| fleet_ring_box_b4 | 4.46 (0% fail) | -- | 7.21 (0% fail) | 5.37 (0% fail) | 5.05 (0% fail) | 6.67 (4% fail) | 4.17 (4% fail) | 1.63 (0% fail) |
| fleet_ring_soc | 7.39 (0% fail) | -- | 9.01 (0% fail) | 8.27 (0% fail) | 7.08 (0% fail) | -- | -- | 4.21 (0% fail) |
| fleet_ring_soc_b4 | 8.17 (0% fail) | -- | 7.48 (0% fail) | 6.73 (0% fail) | 6.51 (0% fail) | -- | -- | 3.08 (0% fail) |
| osqprand | 5.83 (0% fail) | 1.65 (6% fail) | 18.55 (8% fail) | -- | -- | 4.13 (4% fail) | 3.49 (0% fail) | 2.18 (0% fail) |
| reduced | 20.57 (0% fail) | -- | 15.99 (0% fail) | 14.90 (0% fail) | 13.48 (0% fail) | -- | -- | 5.87 (0% fail) |
| single_di_box | 0.896 (0% fail) | 0.224 (0% fail) | 2.05 (0% fail) | 1.53 (0% fail) | 1.16 (0% fail) | 0.296 (0% fail) | 0.337 (0% fail) | 0.642 (0% fail) |
| single_di_soc | 0.992 (0% fail) | -- | 1.41 (0% fail) | 1.21 (0% fail) | 1.14 (0% fail) | -- | -- | 0.657 (0% fail) |
| single_quad | 2.29 (0% fail) | 0.379 (0% fail) | 3.29 (0% fail) | 2.51 (0% fail) | 2.53 (0% fail) | 0.772 (0% fail) | 0.864 (0% fail) | 0.960 (0% fail) |
| all | 5.00 (0% fail) | -- | 7.33 (1% fail) | -- | -- | -- | -- | 2.21 (0% fail) |

### cold, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.90 (0% fail) | 0.366 (0% fail) | 5.00 (0% fail) | 2.94 (0% fail) | 2.81 (0% fail) | 1.34 (0% fail) | 0.881 (0% fail) | 1.20 (0% fail) |
| fleet_grid_box | 3.13 (0% fail) | 1.14 (0% fail) | 6.11 (0% fail) | -- | -- | 32.56 (17% fail) | 1.43 (0% fail) | 1.23 (0% fail) |
| fleet_grid_box_b4 | 8.70 (0% fail) | -- | 11.15 (0% fail) | 8.22 (0% fail) | 7.56 (0% fail) | 35.73 (12% fail) | 5.18 (0% fail) | 2.27 (0% fail) |
| fleet_grid_soc | 22.65 (0% fail) | -- | 18.48 (0% fail) | 16.84 (0% fail) | -- | -- | -- | 8.56 (0% fail) |
| fleet_grid_soc_b4 | 20.67 (0% fail) | -- | 14.53 (0% fail) | -- | -- | -- | -- | 6.13 (0% fail) |
| fleet_ring_box | 6.47 (0% fail) | 6.89 (4% fail) | 11.50 (0% fail) | -- | -- | 18.58 (8% fail) | 2.91 (0% fail) | 2.72 (0% fail) |
| fleet_ring_box_b4 | 5.79 (0% fail) | -- | 9.13 (0% fail) | 6.77 (0% fail) | 6.36 (0% fail) | 21.72 (8% fail) | 2.78 (0% fail) | 1.76 (0% fail) |
| fleet_ring_soc | 10.41 (0% fail) | -- | 12.28 (0% fail) | 11.12 (0% fail) | 9.51 (0% fail) | -- | -- | 4.99 (0% fail) |
| fleet_ring_soc_b4 | 10.72 (0% fail) | -- | 9.87 (0% fail) | 8.87 (0% fail) | 8.62 (0% fail) | -- | -- | 3.71 (0% fail) |
| osqprand | 7.34 (0% fail) | 1.78 (6% fail) | 61.95 (16% fail) | -- | -- | 12.35 (6% fail) | 4.40 (0% fail) | 2.17 (0% fail) |
| reduced | 26.03 (0% fail) | -- | 20.96 (0% fail) | 19.45 (0% fail) | 17.44 (0% fail) | -- | -- | 5.89 (0% fail) |
| single_di_box | 1.25 (0% fail) | 0.293 (0% fail) | 3.08 (0% fail) | 2.34 (0% fail) | 1.82 (0% fail) | 0.561 (0% fail) | 0.408 (0% fail) | 0.680 (0% fail) |
| single_di_soc | 1.56 (0% fail) | -- | 1.98 (0% fail) | 1.70 (0% fail) | 1.57 (0% fail) | -- | -- | 0.762 (0% fail) |
| single_quad | 2.88 (0% fail) | 0.464 (0% fail) | 4.75 (0% fail) | 3.48 (0% fail) | 3.43 (0% fail) | 1.41 (0% fail) | 1.06 (0% fail) | 0.956 (0% fail) |
| all | 6.69 (0% fail) | -- | 11.32 (2% fail) | -- | -- | -- | -- | 2.37 (0% fail) |

### cold, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc | 27.64 (0% fail) | -- | 22.25 (0% fail) | 20.46 (0% fail) | -- | -- | -- | 9.33 (0% fail) |
| fleet_grid_soc_b4 | 24.58 (0% fail) | -- | 17.30 (0% fail) | -- | -- | -- | -- | 6.45 (0% fail) |
| fleet_ring_soc | 12.47 (0% fail) | -- | 14.70 (0% fail) | 13.17 (0% fail) | 11.06 (0% fail) | -- | -- | 5.37 (0% fail) |
| fleet_ring_soc_b4 | 12.80 (0% fail) | -- | 11.53 (0% fail) | 10.34 (0% fail) | 10.03 (0% fail) | -- | -- | 3.94 (0% fail) |
| reduced | 29.95 (0% fail) | -- | 25.91 (0% fail) | 23.91 (0% fail) | 21.37 (0% fail) | -- | -- | 5.92 (0% fail) |
| single_di_soc | 1.81 (0% fail) | -- | 2.33 (0% fail) | 1.99 (0% fail) | 1.88 (0% fail) | -- | -- | 0.804 (0% fail) |
| all | 13.99 (0% fail) | -- | 12.98 (0% fail) | -- | -- | -- | -- | 4.49 (0% fail) |

### cold, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 3.47 (0% fail) | 0.799 (4% fail) | 56.48 (20% fail) | 36.62 (20% fail) | 35.46 (20% fail) | 1.84 (0% fail) | 0.998 (0% fail) | 1.19 (0% fail) |
| fleet_grid_box | 3.65 (0% fail) | 2.78 (6% fail) | 7.26 (0% fail) | -- | -- | 15.44 (6% fail) | 1.71 (0% fail) | 1.26 (0% fail) |
| fleet_grid_box_b4 | 10.10 (0% fail) | -- | 13.19 (0% fail) | 9.70 (0% fail) | 8.69 (0% fail) | 34.84 (8% fail) | 5.81 (0% fail) | 2.30 (0% fail) |
| fleet_grid_soc | 29.92 (0% fail) | -- | 24.13 (0% fail) | 21.95 (0% fail) | -- | -- | -- | 9.38 (0% fail) |
| fleet_grid_soc_b4 | 26.45 (0% fail) | -- | 18.65 (0% fail) | -- | -- | -- | -- | 6.55 (0% fail) |
| fleet_ring_box | 7.56 (0% fail) | 8.70 (4% fail) | 13.60 (0% fail) | -- | -- | 33.30 (8% fail) | 3.39 (0% fail) | 2.71 (0% fail) |
| fleet_ring_box_b4 | 6.65 (0% fail) | -- | 10.79 (0% fail) | 7.89 (0% fail) | 7.47 (0% fail) | 14.69 (0% fail) | 3.15 (0% fail) | 1.82 (0% fail) |
| fleet_ring_soc | 13.54 (0% fail) | -- | 15.67 (0% fail) | 14.09 (0% fail) | 11.97 (0% fail) | -- | -- | 5.41 (0% fail) |
| fleet_ring_soc_b4 | 13.79 (0% fail) | -- | 12.34 (0% fail) | 11.09 (0% fail) | 10.78 (0% fail) | -- | -- | 4.14 (0% fail) |
| osqprand | 8.55 (0% fail) | 7.13 (16% fail) | 56.32 (14% fail) | -- | -- | 8.72 (0% fail) | 5.11 (0% fail) | 2.47 (0% fail) |
| reduced | 32.25 (0% fail) | -- | 30.89 (0% fail) | 28.65 (0% fail) | 25.41 (0% fail) | -- | -- | 5.88 (0% fail) |
| single_di_box | 1.54 (0% fail) | 0.353 (0% fail) | 3.84 (0% fail) | 2.88 (0% fail) | 2.22 (0% fail) | 0.816 (0% fail) | 0.484 (0% fail) | 0.676 (0% fail) |
| single_di_soc | 1.89 (0% fail) | -- | 2.47 (0% fail) | 2.15 (0% fail) | 1.92 (0% fail) | -- | -- | 0.823 (0% fail) |
| single_quad | 3.32 (0% fail) | 0.491 (0% fail) | 5.56 (0% fail) | 4.08 (0% fail) | 3.83 (0% fail) | 2.05 (0% fail) | 1.21 (0% fail) | 0.950 (0% fail) |
| all | 8.11 (0% fail) | -- | 15.83 (4% fail) | -- | -- | -- | -- | 2.50 (0% fail) |

### warm, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.98 (0% fail) | 0.904 (7% fail) | 11.51 (11% fail) | 7.23 (11% fail) | 6.96 (11% fail) | 0.821 (2% fail) | 0.598 (0% fail) | 0.500 (0% fail) |
| fleet_grid_box | 2.47 (0% fail) | 8.05 (15% fail) | 5.27 (0% fail) | -- | -- | 54.83 (24% fail) | 2.03 (3% fail) | 1.17 (0% fail) |
| fleet_grid_box_b4 | 7.36 (0% fail) | -- | 9.47 (0% fail) | 7.05 (0% fail) | 6.51 (0% fail) | 17.19 (14% fail) | 4.53 (0% fail) | 2.06 (0% fail) |
| fleet_grid_soc | 13.39 (0% fail) | -- | 14.45 (0% fail) | 13.30 (0% fail) | -- | -- | -- | 6.81 (0% fail) |
| fleet_grid_soc_b4 | 15.60 (0% fail) | -- | 11.39 (0% fail) | -- | -- | -- | -- | 5.13 (0% fail) |
| fleet_ring_box | 5.17 (0% fail) | 5.50 (2% fail) | 9.80 (0% fail) | -- | -- | 21.04 (16% fail) | 3.37 (2% fail) | 2.44 (0% fail) |
| fleet_ring_box_b4 | 4.77 (0% fail) | -- | 7.86 (0% fail) | 5.84 (0% fail) | 5.46 (0% fail) | 7.38 (7% fail) | 3.42 (2% fail) | 1.65 (0% fail) |
| fleet_ring_soc | 7.52 (0% fail) | -- | 9.85 (0% fail) | 9.05 (0% fail) | 7.58 (0% fail) | -- | -- | 4.12 (0% fail) |
| fleet_ring_soc_b4 | 8.37 (0% fail) | -- | 8.01 (0% fail) | 7.26 (0% fail) | 7.03 (0% fail) | -- | -- | 3.14 (0% fail) |
| osqprand | 5.46 (0% fail) | 0.866 (3% fail) | 11.30 (5% fail) | -- | -- | 1.69 (0% fail) | 3.38 (0% fail) | 0.766 (0% fail) |
| reduced | 20.31 (0% fail) | -- | 15.72 (0% fail) | 14.57 (0% fail) | 13.18 (0% fail) | -- | -- | 1.10 (0% fail) |
| single_di_box | 0.831 (0% fail) | 0.210 (0% fail) | 1.92 (0% fail) | 1.50 (0% fail) | 1.17 (0% fail) | 0.296 (0% fail) | 0.330 (0% fail) | 0.159 (0% fail) |
| single_di_soc | 0.935 (0% fail) | -- | 1.20 (0% fail) | 0.991 (0% fail) | 0.927 (0% fail) | -- | -- | 0.327 (0% fail) |
| single_quad | 1.91 (0% fail) | 0.301 (0% fail) | 2.75 (0% fail) | 2.03 (0% fail) | 2.00 (0% fail) | 0.749 (0% fail) | 0.756 (0% fail) | 0.245 (0% fail) |
| all | 4.72 (0% fail) | -- | 7.44 (2% fail) | -- | -- | -- | -- | 1.24 (0% fail) |

### warm, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.67 (0% fail) | 1.02 (7% fail) | 25.30 (11% fail) | 9.80 (11% fail) | 9.30 (11% fail) | 1.20 (0% fail) | 0.737 (0% fail) | 0.503 (0% fail) |
| fleet_grid_box | 3.21 (0% fail) | 1.10 (0% fail) | 6.74 (0% fail) | -- | -- | 16.37 (15% fail) | 1.55 (0% fail) | 1.19 (0% fail) |
| fleet_grid_box_b4 | 9.28 (0% fail) | -- | 12.24 (0% fail) | 9.08 (0% fail) | 8.35 (0% fail) | 19.61 (7% fail) | 5.61 (0% fail) | 2.09 (0% fail) |
| fleet_grid_soc | 19.40 (0% fail) | -- | 19.82 (0% fail) | 18.10 (0% fail) | -- | -- | -- | 8.17 (0% fail) |
| fleet_grid_soc_b4 | 21.67 (0% fail) | -- | 15.64 (0% fail) | -- | -- | -- | -- | 6.35 (0% fail) |
| fleet_ring_box | 6.74 (0% fail) | 5.65 (2% fail) | 12.66 (0% fail) | -- | -- | 86.52 (25% fail) | 3.11 (0% fail) | 2.55 (0% fail) |
| fleet_ring_box_b4 | 6.01 (0% fail) | -- | 10.07 (0% fail) | 7.46 (0% fail) | 6.90 (0% fail) | 31.78 (16% fail) | 2.92 (0% fail) | 1.71 (0% fail) |
| fleet_ring_soc | 10.81 (0% fail) | -- | 13.37 (0% fail) | 12.04 (0% fail) | 10.20 (0% fail) | -- | -- | 4.87 (0% fail) |
| fleet_ring_soc_b4 | 11.23 (0% fail) | -- | 10.60 (0% fail) | 9.55 (0% fail) | 9.18 (0% fail) | -- | -- | 3.63 (0% fail) |
| osqprand | 6.91 (0% fail) | 1.18 (4% fail) | 33.28 (9% fail) | -- | -- | 15.06 (11% fail) | 4.12 (0% fail) | 0.716 (0% fail) |
| reduced | 25.57 (0% fail) | -- | 21.00 (0% fail) | 19.52 (0% fail) | 17.66 (0% fail) | -- | -- | 1.10 (0% fail) |
| single_di_box | 1.26 (0% fail) | 0.273 (0% fail) | 3.08 (0% fail) | 2.35 (0% fail) | 1.80 (0% fail) | 0.552 (0% fail) | 0.418 (0% fail) | 0.163 (0% fail) |
| single_di_soc | 1.41 (0% fail) | -- | 1.82 (0% fail) | 1.57 (0% fail) | 1.41 (0% fail) | -- | -- | 0.471 (0% fail) |
| single_quad | 2.38 (0% fail) | 0.318 (0% fail) | 4.16 (0% fail) | 2.98 (0% fail) | 2.90 (0% fail) | 1.35 (0% fail) | 0.939 (0% fail) | 0.240 (0% fail) |
| all | 6.29 (0% fail) | -- | 12.01 (2% fail) | -- | -- | -- | -- | 1.33 (0% fail) |

### warm, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc | 23.00 (0% fail) | -- | 23.20 (0% fail) | 21.43 (0% fail) | -- | -- | -- | 8.61 (0% fail) |
| fleet_grid_soc_b4 | 25.16 (0% fail) | -- | 18.01 (0% fail) | -- | -- | -- | -- | 6.67 (0% fail) |
| fleet_ring_soc | 12.95 (0% fail) | -- | 15.70 (0% fail) | 14.21 (0% fail) | 11.98 (0% fail) | -- | -- | 5.17 (0% fail) |
| fleet_ring_soc_b4 | 13.44 (0% fail) | -- | 12.53 (0% fail) | 11.12 (0% fail) | 10.79 (0% fail) | -- | -- | 3.93 (0% fail) |
| reduced | 29.50 (0% fail) | -- | 25.91 (0% fail) | 23.80 (0% fail) | 21.65 (0% fail) | -- | -- | 1.09 (0% fail) |
| single_di_soc | 1.68 (0% fail) | -- | 2.41 (0% fail) | 1.84 (0% fail) | 1.69 (0% fail) | -- | -- | 0.524 (0% fail) |
| all | 13.15 (0% fail) | -- | 13.18 (0% fail) | -- | -- | -- | -- | 3.02 (0% fail) |

### warm, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 3.14 (0% fail) | 1.15 (7% fail) | 196 (24% fail) | 54.74 (24% fail) | 52.15 (24% fail) | 1.38 (0% fail) | 0.844 (0% fail) | 0.498 (0% fail) |
| fleet_grid_box | 3.75 (0% fail) | 2.80 (6% fail) | 7.82 (0% fail) | -- | -- | 21.70 (12% fail) | 1.78 (0% fail) | 1.20 (0% fail) |
| fleet_grid_box_b4 | 10.70 (0% fail) | -- | 15.11 (0% fail) | 10.34 (0% fail) | 9.53 (0% fail) | 32.98 (7% fail) | 6.51 (0% fail) | 2.09 (0% fail) |
| fleet_grid_soc | 37.16 (5% fail) | -- | 24.92 (0% fail) | 22.72 (0% fail) | -- | -- | -- | 9.99 (0% fail) |
| fleet_grid_soc_b4 | 33.77 (2% fail) | -- | 19.37 (0% fail) | -- | -- | -- | -- | 6.90 (0% fail) |
| fleet_ring_box | 7.87 (0% fail) | 6.82 (2% fail) | 14.62 (0% fail) | -- | -- | 73.68 (18% fail) | 3.56 (0% fail) | 2.56 (0% fail) |
| fleet_ring_box_b4 | 6.91 (0% fail) | -- | 11.66 (0% fail) | 8.51 (0% fail) | 7.89 (0% fail) | 13.89 (2% fail) | 3.30 (0% fail) | 1.70 (0% fail) |
| fleet_ring_soc | 18.13 (2% fail) | -- | 16.86 (0% fail) | 15.11 (0% fail) | 13.17 (0% fail) | -- | -- | 5.23 (0% fail) |
| fleet_ring_soc_b4 | 23.60 (5% fail) | -- | 13.37 (0% fail) | 11.89 (0% fail) | 11.56 (0% fail) | -- | -- | 4.00 (0% fail) |
| osqprand | 7.80 (0% fail) | 2.93 (10% fail) | 72.75 (9% fail) | -- | -- | 8.52 (4% fail) | 4.88 (0% fail) | 0.894 (0% fail) |
| reduced | 32.07 (0% fail) | -- | 30.61 (0% fail) | 28.25 (0% fail) | 25.26 (0% fail) | -- | -- | 1.08 (0% fail) |
| single_di_box | 1.54 (0% fail) | 0.317 (0% fail) | 5.39 (0% fail) | 2.95 (0% fail) | 2.25 (0% fail) | 0.617 (0% fail) | 0.489 (0% fail) | 0.165 (0% fail) |
| single_di_soc | 1.78 (0% fail) | -- | 3.40 (0% fail) | 2.01 (0% fail) | 1.82 (0% fail) | -- | -- | 0.564 (0% fail) |
| single_quad | 2.78 (0% fail) | 0.359 (0% fail) | 5.70 (0% fail) | 3.53 (0% fail) | 3.41 (0% fail) | 1.47 (0% fail) | 1.08 (0% fail) | 0.246 (0% fail) |
| all | 8.26 (1% fail) | -- | 19.99 (3% fail) | -- | -- | -- | -- | 1.43 (0% fail) |

## Where sheafmpc loses (median time over the best other solver, ratio > 1, or misses the tier)

| instance | mode | tier | sheafmpc ms | best other | its ms | ratio |
|---|---|---|---:|---|---:|---:|
| osqprand_nx40_s2 | cold | low | 13.64 | hpipm | 1.68 | 8.12 |
| chain_M6 | cold | low | 1.62 | hpipm | 0.268 | 6.03 |
| chain_M8 | cold | low | 2.06 | hpipm | 0.407 | 5.06 |
| chain_M6 | cold | medium | 1.62 | hpipm | 0.332 | 4.88 |
| chain_M10 | cold | low | 3.26 | hpipm | 0.674 | 4.83 |
| osqprand_nx10_s3 | cold | medium | 0.908 | hpipm | 0.214 | 4.26 |
| osqprand_nx10_s2 | cold | low | 0.405 | hpipm | 0.099 | 4.11 |
| di_box_N25 | cold | low | 0.577 | hpipm | 0.153 | 3.78 |
| chain_M8 | cold | medium | 2.08 | hpipm | 0.560 | 3.72 |
| chain_M10 | cold | medium | 3.31 | hpipm | 0.893 | 3.70 |
| chain_M10 | cold | high | 3.33 | hpipm | 0.912 | 3.65 |
| chain_M6 | cold | high | 1.55 | hpipm | 0.447 | 3.47 |
| chain_M4 | cold | medium | 0.712 | hpipm | 0.207 | 3.44 |
| di_box_N50 | cold | low | 0.961 | hpipm | 0.283 | 3.40 |
| osqprand_nx10_s3 | cold | high | 2.98 | piqp | 0.898 | 3.32 |
| chain_M4 | cold | low | 0.549 | hpipm | 0.166 | 3.31 |
| osqprand_nx20_s1 | cold | low | 1.06 | hpipm | 0.324 | 3.28 |
| osqprand_nx20_s2 | cold | low | 1.05 | hpipm | 0.322 | 3.26 |
| quad_N100 | cold | low | 2.53 | hpipm | 0.796 | 3.18 |
| osqprand_nx10_s2 | cold | high | 0.363 | hpipm | 0.118 | 3.07 |
| osqprand_nx10_s2 | cold | medium | 0.363 | hpipm | 0.119 | 3.04 |
| osqprand_nx40_s1 | cold | low | 3.67 | hpipm | 1.21 | 3.04 |
| osqprand_nx20_s3 | cold | low | 1.23 | hpipm | 0.413 | 2.98 |
| chain_M4 | cold | high | 0.675 | hpipm | 0.231 | 2.93 |
| osqprand_nx80_s1 | warm | low | 17.54 | hpipm | 6.02 | 2.91 |
| di_box_N25 | cold | medium | 0.612 | hpipm | 0.214 | 2.86 |
| osqprand_nx40_s3 | cold | medium | 3.62 | hpipm | 1.31 | 2.76 |
| quad_N25 | cold | low | 0.783 | hpipm | 0.290 | 2.70 |
| di_box_N50 | cold | medium | 0.948 | hpipm | 0.358 | 2.65 |
| quad_N50 | cold | medium | 1.44 | hpipm | 0.546 | 2.64 |
| quad_N50 | cold | low | 1.41 | hpipm | 0.556 | 2.53 |
| di_box_N10 | cold | low | 0.171 | hpipm | 0.069 | 2.50 |
| osqprand_nx20_s1 | cold | medium | 1.06 | hpipm | 0.424 | 2.49 |
| di_box_N100 | cold | low | 1.37 | hpipm | 0.554 | 2.48 |
| osqprand_nx80_s1 | cold | low | 16.29 | hpipm | 6.73 | 2.42 |
| di_box_N25 | cold | high | 0.639 | hpipm | 0.266 | 2.40 |
| quad_N25 | cold | high | 0.807 | hpipm | 0.337 | 2.40 |
| chain_M10 | warm | low | 1.48 | hpipm | 0.634 | 2.34 |
| quad_N50 | cold | high | 1.43 | hpipm | 0.614 | 2.33 |
| osqprand_nx40_s2 | warm | low | 2.53 | hpipm | 1.09 | 2.32 |
| di_box_N50 | cold | high | 1.00 | hpipm | 0.437 | 2.29 |
| osqprand_nx80_s1 | warm | medium | 17.74 | hpipm | 7.83 | 2.27 |
| osqprand_nx40_s3 | cold | high | 3.30 | hpipm | 1.48 | 2.23 |
| osqprand_nx20_s3 | cold | medium | 1.13 | hpipm | 0.514 | 2.21 |
| osqprand_nx20_s2 | cold | medium | 1.21 | hpipm | 0.552 | 2.19 |
| fleet_ring_box_n4 | cold | medium | 1.24 | hpipm | 0.573 | 2.16 |
| osqprand_nx40_s1 | cold | medium | 3.58 | hpipm | 1.69 | 2.12 |
| chain_M6 | warm | high | 0.706 | hpipm | 0.339 | 2.09 |
| osqprand_nx80_s1 | cold | medium | 16.05 | hpipm | 7.70 | 2.08 |
| quad_N100 | cold | medium | 2.70 | hpipm | 1.29 | 2.08 |
| quad_N10 | cold | low | 0.246 | hpipm | 0.119 | 2.07 |
| fleet_ring_box_n4 | cold | low | 1.05 | hpipm | 0.507 | 2.07 |
| fleet_grid_box_n4 | cold | high | 1.49 | hpipm | 0.725 | 2.06 |
| quad_N100 | cold | high | 2.59 | hpipm | 1.29 | 2.00 |
| fleet_ring_box_n4 | cold | high | 1.20 | hpipm | 0.604 | 1.99 |
| osqprand_nx20_s2 | warm | low | 0.773 | hpipm | 0.389 | 1.98 |
| fleet_grid_box_n4 | cold | low | 1.38 | piqp | 0.702 | 1.97 |
| quad_N25 | cold | medium | 0.759 | hpipm | 0.385 | 1.97 |
| osqprand_nx20_s2 | cold | high | 0.960 | hpipm | 0.490 | 1.96 |
| chain_M8 | warm | medium | 1.02 | hpipm | 0.522 | 1.96 |
| fleet_ring_box_n4 | warm | low | 0.914 | hpipm | 0.468 | 1.95 |
| di_box_N100 | cold | medium | 1.51 | hpipm | 0.772 | 1.95 |
| osqprand_nx40_s1 | cold | high | 3.52 | hpipm | 1.82 | 1.93 |
| chain_M3 | cold | low | 0.263 | hpipm | 0.140 | 1.89 |
| chain_M4 | warm | medium | 0.314 | hpipm | 0.167 | 1.88 |
| di_box_N10 | cold | medium | 0.170 | hpipm | 0.090 | 1.88 |
| chain_M3 | warm | low | 0.198 | hpipm | 0.106 | 1.86 |
| di_box_N10 | cold | high | 0.176 | hpipm | 0.096 | 1.82 |
| osqprand_nx40_s3 | cold | low | 3.26 | hpipm | 1.81 | 1.80 |
| chain_M4 | warm | low | 0.257 | hpipm | 0.145 | 1.76 |
| chain_M10 | warm | high | 1.52 | hpipm | 0.868 | 1.75 |
| osqprand_nx10_s3 | cold | low | 0.932 | piqp | 0.534 | 1.74 |
| fleet_ring_box_n4 | warm | medium | 0.852 | hpipm | 0.492 | 1.73 |
| di_box_N100 | cold | high | 1.51 | hpipm | 0.901 | 1.68 |
| fleet_grid_box_n4 | cold | medium | 1.36 | hpipm | 0.831 | 1.64 |
| chain_M3 | cold | medium | 0.259 | hpipm | 0.159 | 1.62 |
| chain_M4 | warm | high | 0.318 | hpipm | 0.198 | 1.61 |
| quad_N10 | cold | medium | 0.217 | hpipm | 0.137 | 1.58 |
| fleet_grid_box_n1 | warm | low | 0.107 | hpipm | 0.072 | 1.49 |
| fleet_ring_box_n4 | warm | high | 0.868 | hpipm | 0.589 | 1.47 |
| chain_M8 | cold | high | 2.08 | piqp | 1.42 | 1.47 |
| quad_N10 | cold | high | 0.213 | hpipm | 0.146 | 1.46 |
| chain_M3 | cold | high | 0.258 | hpipm | 0.179 | 1.44 |
| chain_M3 | warm | medium | 0.199 | hpipm | 0.139 | 1.44 |
| osqprand_nx10_s3 | warm | high | 1.15 | piqp | 0.804 | 1.43 |
| fleet_grid_soc_n64 | cold | low | 328 | mumblebee_fast | 234 | 1.40 |
| chain_M6 | warm | low | 0.755 | piqp | 0.540 | 1.40 |
| fleet_grid_box_n4 | warm | medium | 0.983 | hpipm | 0.726 | 1.35 |
| fleet_grid_box_b4_n4 | cold | low | 0.744 | piqp | 0.564 | 1.32 |
| fleet_grid_box_n4 | warm | low | 0.999 | piqp | 0.770 | 1.30 |
| chain_M8 | warm | low | 1.02 | piqp | 0.804 | 1.27 |
| fleet_ring_box_n1 | warm | low | 0.085 | hpipm | 0.068 | 1.25 |
| fleet_grid_box_n1 | warm | medium | 0.103 | hpipm | 0.083 | 1.24 |
| fleet_grid_soc_n64 | warm | high | 582 | mumblebee_fast | 495 | 1.18 |
| fleet_grid_soc_n64 | warm | low | 325 | mumblebee_fast | 287 | 1.13 |
| fleet_ring_box_n1 | warm | medium | 0.085 | hpipm | 0.076 | 1.11 |
| fleet_grid_box_n1 | cold | low | 0.076 | hpipm | 0.068 | 1.10 |
| fleet_ring_box_n64 | cold | low | 40.14 | piqp | 36.56 | 1.10 |
| fleet_ring_box_n16 | cold | low | 6.45 | piqp | 5.89 | 1.09 |
| osqprand_nx20_s2 | warm | medium | 0.772 | hpipm | 0.715 | 1.08 |
| fleet_ring_box_n1 | cold | low | 0.077 | hpipm | 0.071 | 1.07 |
| fleet_grid_soc_n64 | cold | medium | 360 | mumblebee_fast | 336 | 1.07 |
| chain_M6 | warm | medium | 0.733 | piqp | 0.691 | 1.06 |
| fleet_grid_box_b4_n4 | cold | medium | 0.875 | piqp | 0.826 | 1.06 |
| di_box_N100 | warm | low | 0.519 | hpipm | 0.493 | 1.05 |
| fleet_ring_box_n1 | warm | high | 0.085 | hpipm | 0.084 | 1.02 |
| fleet_grid_box_b4_n4 | cold | high | 0.956 | piqp | 0.943 | 1.01 |

sheafmpc is fastest (ratio <= 1) in 313 of 420 (instance, mode, tier) cells with a finite ratio; median ratio 0.55.

## Gate: sheafmpc against mumblebee_fast (median time ratio; <= 1 passes)

| mode | tier | cells | pass | sheafmpc misses the tier | median ratio | worst ratio (instance) |
|---|---|---:|---:|---:|---:|---|
| cold | low | 47 | 46 | 0 | 0.43 | 1.40 (fleet_grid_soc_n64) |
| cold | medium | 47 | 46 | 0 | 0.32 | 1.07 (fleet_grid_soc_n64) |
| cold | e8 | 23 | 23 | 0 | 0.38 | 0.86 (fleet_grid_soc_n64) |
| cold | high | 44 | 44 | 0 | 0.26 | 0.76 (fleet_grid_soc_n64) |
| warm | low | 44 | 43 | 0 | 0.23 | 1.13 (fleet_grid_soc_n64) |
| warm | medium | 43 | 43 | 0 | 0.21 | 0.95 (fleet_grid_soc_n64) |
| warm | e8 | 23 | 23 | 0 | 0.27 | 0.80 (fleet_grid_soc_n64) |
| warm | high | 44 | 43 | 0 | 0.19 | 1.18 (fleet_grid_soc_n64) |
