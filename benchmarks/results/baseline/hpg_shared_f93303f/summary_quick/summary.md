# Benchmark summary

Sources: results/hpg_fa5390d/quick_20261018_fa5390d7c2_shared, results/hpg_fa5390d/quick_20261018_fa5390d7c2_shared/mumblebee_fast, results/hpg_fa5390d/quick_20261018_fa5390d7c2_shared/mumblebee_fast_ct; 10 instances.

## Setup

- host `c0706a-s12.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- Julia 1.12.6, 1 thread, BLAS threads 1; governor ``, boost ``
- 1-minute load before each instance: median 87.8, max 88.4; gate passed 10, timed out 0, skipped 0
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
| chain_M4 | 220 | 1.19 | 0.138 | 2.07 | 1.26 | 1.21 | 0.736 | 0.415 | 0.518 | 3.76 (hpipm) | 0.41 |

Cold cells: median ms of the solve; setup is separate.

### chain, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.57 | 0.179 | 2.77 | 1.70 | 1.68 | 0.718 | 0.452 | 0.531 | 2.97 (hpipm) | 0.31 |

Cold cells: median ms of the solve; setup is separate.

### chain, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.74 | 0.193 | 3.23 | 1.96 | 1.92 | 1.03 | 0.546 | 0.534 | 2.77 (hpipm) | 0.27 |

Cold cells: median ms of the solve; setup is separate.

### chain, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.16 (1.19) | 0.127 (0.133) | 2.00 (2.03) | 1.23 (1.25) | 1.18 (1.20) | 0.671 (0.706) [1/5] | 0.394 (0.401) | 0.201 (0.338) | 1.59 (hpipm) | 0.16 |

Warm cells: median (max) ms.

### chain, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.55 (1.75) | 0.166 (0.174) | 2.76 (2.82) | 1.68 (1.68) | 1.62 (1.73) | 0.717 (1.03) | 0.471 (0.572) | 0.265 (0.324) | 1.60 (hpipm) | 0.16 |

Warm cells: median (max) ms.

### chain, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.91 (2.28) | 0.174 (0.212) | 7.90 (8.29) | 2.03 (2.33) | 2.05 (2.27) | 1.03 (1.03) | 0.579 (0.692) | 0.256 (0.326) | 1.47 (hpipm) | 0.13 |

Warm cells: median (max) ms.

### chain, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 50 / 50 / -- / 75 | 6 / 7 / -- / 9 | 30 / 30 / -- / 30 |

### chain, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 50 / 50 / -- / 75 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |

### chain, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 0.643 | 0.145 | 4.66 | 1.13 | 1.14 | 0.435 | 0.522 | 4.98 |

## fleet_ring_box

### fleet_ring_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.315 | 0.073 | 0.952 | 0.746 | 0.577 | 0.307 [1/5] | 0.094 | 0.086 | 1.18 (hpipm) | 0.12 |
| fleet_ring_box_n4 | 560 | 2.14 | 0.633 | 4.53 | 3.43 | 3.09 | 1.24 [1/5] | 0.770 [1/5] | 1.22 | 1.92 (hpipm) | 0.35 |
| fleet_ring_box_n16 | 2240 | 14.86 | 9.24 [1/5] | 22.33 | 16.76 | 15.00 | 14.15 | 6.57 | 7.70 | 1.17 (piqp) | 0.46 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.445 | 0.081 | 1.28 | 0.982 | 0.726 | 0.631 | 0.110 | 0.085 | 1.05 (hpipm) | 0.09 |
| fleet_ring_box_n4 | 560 | 2.83 | 0.644 | 5.79 | 4.35 | 3.88 | 5.08 | 1.06 | 1.34 | 2.08 (hpipm) | 0.31 |
| fleet_ring_box_n16 | 2240 | 20.49 | 12.34 | 30.23 | 22.53 | 20.38 | 30.97 | 9.09 | 7.66 | 0.84 (piqp) | 0.34 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.485 | 0.089 | 1.53 | 1.12 | 0.869 | 0.884 | 0.142 | 0.079 | 0.89 (hpipm) | 0.07 |
| fleet_ring_box_n4 | 560 | 3.40 | 0.731 | 7.08 | 5.19 | 4.66 | 10.22 | 1.29 | 1.30 | 1.78 (hpipm) | 0.25 |
| fleet_ring_box_n16 | 2240 | 24.15 | 14.22 [1/5] | 35.38 | 26.23 | 24.27 | 60.30 | 10.92 | 7.73 | 0.71 (piqp) | 0.29 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.326 (0.387) | 0.075 (0.080) | 0.961 (1.13) | 0.761 (0.920) | 0.551 (0.648) | 0.120 (0.123) | 0.104 (0.107) | 0.087 (0.202) | 1.15 (hpipm) | 0.11 |
| fleet_ring_box_n4 | 560 | 2.15 (2.46) | 0.540 (0.623) | 4.65 (5.29) | 3.45 (3.91) | 3.11 (3.46) | 1.17 (1.74) [1/5] | 0.784 (0.789) [1/5] | 0.675 (1.41) | 1.25 (hpipm) | 0.20 |
| fleet_ring_box_n16 | 2240 | 15.04 (17.10) | 8.89 (11.10) [1/5] | 22.52 (24.90) | 16.61 (18.51) | 15.08 (16.96) | 11.29 (11.32) | 7.87 (8.84) | 7.20 (11.68) | 0.91 (piqp) | 0.43 |

Warm cells: median (max) ms.

### fleet_ring_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.428 (0.494) | 0.073 (0.126) | 1.25 (1.45) | 0.999 (1.15) | 0.733 (0.830) | 0.663 (0.755) | 0.119 (0.152) | 0.094 (0.201) | 1.29 (hpipm) | 0.09 |
| fleet_ring_box_n4 | 560 | 2.75 (3.09) | 0.572 (0.596) | 5.88 (6.47) | 4.21 (4.63) | 3.84 (4.25) | 4.95 (6.02) | 1.07 (1.07) | 0.847 (1.45) | 1.48 (hpipm) | 0.20 |
| fleet_ring_box_n16 | 2240 | 20.45 (20.79) | 10.86 (11.68) | 30.26 (32.91) | 22.55 (24.46) | 20.54 (22.47) | 25.39 (31.17) | 9.17 (10.08) | 7.57 (11.49) | 0.83 (piqp) | 0.34 |

Warm cells: median (max) ms.

### fleet_ring_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.465 (0.651) | 0.080 (0.138) | 1.48 (1.77) | 1.15 (1.42) | 0.850 (1.04) | 1.23 (1.32) | 0.148 (0.164) | 0.089 (0.193) | 1.11 (hpipm) | 0.08 |
| fleet_ring_box_n4 | 560 | 3.30 (3.61) | 0.650 (0.712) | 7.12 (7.22) | 5.22 (5.27) | 4.65 (4.69) | 6.62 (9.16) | 1.30 (1.30) | 0.847 (1.41) | 1.30 (hpipm) | 0.16 |
| fleet_ring_box_n16 | 2240 | 24.29 (24.51) | 12.56 (13.45) [1/5] | 35.56 (36.12) | 26.28 (26.43) | 24.05 (24.20) | 44.33 (116) | 10.99 (11.09) | 7.57 (11.65) | 0.69 (piqp) | 0.29 |

Warm cells: median (max) ms.

### fleet_ring_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 4 / 6 / -- / 7 | 5 / 6 / -- / 7 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 75 / 125 / -- / 175 | 4 / 5 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_ring_box_n4 | 6 / 8 / -- / 10 | 7 / 9 / -- / 10 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 50 / 200 / -- / 450 | 6 / 8 / -- / 10 | 50 / 50 / -- / 50 |
| fleet_ring_box_n16 | 7 / 10 / -- / 12 | 7 / 10 / -- / 12 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 125 / 250 / -- / 500 | 7 / 10 / -- / 12 | 60 / 60 / -- / 60 |

### fleet_ring_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 4 / 6 / -- / 7 | 5 / 6 / -- / 7 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 25 / 150 / -- / 275 | 4 / 5 / -- / 7 | 20 / 20 / -- / 20 |
| fleet_ring_box_n4 | 6 / 8 / -- / 10 | 7 / 9 / -- / 10 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 50 / 200 / -- / 275 | 6 / 8 / -- / 10 | 30 / 30 / -- / 30 |
| fleet_ring_box_n16 | 7 / 10 / -- / 12 | 7 / 10 / -- / 12 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 100 / 200 / -- / 350 | 8 / 10 / -- / 12 | 50 / 50 / -- / 50 |

### fleet_ring_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 0.277 | 0.114 | 0.605 | 0.358 | 0.392 | 0.145 | 0.120 | 1.63 |
| fleet_ring_box_n4 | 1.06 | 0.214 | 2.39 | 1.40 | 1.46 | 0.736 | 0.431 | 8.92 |
| fleet_ring_box_n16 | 4.00 | 2.82 | 9.67 | 5.53 | 5.58 | 3.13 | 1.60 | 41.67 |

## fleet_ring_box_b4

### fleet_ring_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.76 | 3.84 | 2.64 | 2.48 | 1.32 | 0.635 [1/5] | 0.779 | 0.59 (osqp) | 0.30 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.23 | 4.78 | 3.30 | 3.04 | 3.90 | 0.807 | 0.840 | 1.04 (piqp) | 0.25 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.60 | 5.86 | 3.95 | 3.58 | 6.99 | 1.01 | 0.846 | 0.83 (piqp) | 0.21 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.72 (1.77) | 3.79 (4.31) | 2.63 (2.94) | 2.43 (2.71) | 0.999 (1.35) [1/5] | 0.644 (0.653) [1/5] | 0.592 (1.47) | 0.34 (clarabel) | 0.22 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.17 (2.25) | 4.83 (5.34) | 3.28 (3.62) | 3.00 (3.30) | 2.69 (3.61) [1/5] | 0.813 (0.816) | 0.597 (1.44) | 0.73 (piqp) | 0.18 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.57 (2.61) | 5.76 (6.06) | 3.94 (3.98) | 3.73 (3.74) | 4.56 (6.78) | 0.912 (1.01) | 0.606 (1.49) | 0.66 (piqp) | 0.15 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 100 / 300 / -- / 525 | 6 / 8 / -- / 9 | 50 / 50 / -- / 50 |

### fleet_ring_box_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 75 / 175 / -- / 350 | 6 / 8 / -- / 9 | 50 / 50 / -- / 50 |

### fleet_ring_box_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 0.721 | 2.00 | 1.28 | 1.30 | 0.516 | 0.297 | 5.64 |

## fleet_ring_soc

### fleet_ring_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.25 | 4.92 | 4.50 | 3.68 | 2.09 | 0.64 (clarabel) | 0.46 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 4.40 | 7.16 | 6.32 | 5.33 | 2.36 | 0.54 (clarabel) | 0.37 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 5.47 | 7.86 | 7.32 | 6.08 | 2.76 | 0.51 (clarabel) | 0.38 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 6.05 | 8.67 | 7.95 | 6.56 | 2.84 | 0.47 (clarabel) | 0.36 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.14 (3.69) | 4.79 (5.55) | 4.39 (5.13) | 3.66 (4.21) | 2.10 (4.35) | 0.67 (clarabel) | 0.48 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 4.27 (4.90) | 7.06 (7.91) | 6.44 (7.12) | 5.37 (5.95) | 2.05 (4.88) | 0.48 (clarabel) | 0.32 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 5.47 (5.56) | 8.37 (8.53) | 7.65 (7.70) | 6.48 (6.58) | 2.31 (4.73) | 0.42 (clarabel) | 0.30 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 6.01 (6.02) | 9.33 (9.39) | 8.52 (8.59) | 7.05 (7.07) | 2.72 (4.85) | 0.45 (clarabel) | 0.32 |

Warm cells: median (max) ms.

### fleet_ring_soc, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 5 / 7 / 9 / 10 | 7 / 10 / 11 / 12 | 7 / 10 / 11 / 12 | 7 / 10 / 11 / 12 | 40 / 40 / 40 / 40 |

### fleet_ring_soc, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 5 / 7 / 9 / 10 | 7 / 10 / 12 / 13 | 7 / 10 / 12 / 13 | 7 / 10 / 12 / 13 | 20 / 20 / 20 / 20 |

### fleet_ring_soc, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 1.28 | 2.21 | 1.45 | 1.57 | 11.64 |

## osqprand

### osqprand, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 4.20 | 0.340 | 6.04 | 3.10 | 3.08 | 4.45 | 2.39 | 0.979 | 2.88 (hpipm) | 0.32 |

Cold cells: median ms of the solve; setup is separate.

### osqprand, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 4.95 | 0.442 | 6.96 | 3.56 | 3.52 | 8.64 | 2.97 | 1.07 | 2.42 (hpipm) | 0.30 |

Cold cells: median ms of the solve; setup is separate.

### osqprand, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 5.80 | 0.439 [1/5] | 8.86 | 4.50 | 4.40 | 11.07 | 3.35 | 0.976 | 0.29 (piqp) | 0.22 |

Cold cells: median ms of the solve; setup is separate.

### osqprand, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 4.19 (4.21) | 0.344 (0.385) | 5.99 (6.14) | 3.10 (3.13) | 3.04 (3.11) | 2.59 (2.60) | 2.37 (2.72) | 0.236 (0.689) | 0.69 (hpipm) | 0.08 |

Warm cells: median (max) ms.

### osqprand, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 5.43 (5.56) | 0.447 (0.452) | 6.97 (6.99) | 3.64 (3.72) | 3.52 (3.58) | 8.51 (18.10) [2/5] | 2.94 (2.98) | 0.214 (0.659) | 0.48 (hpipm) | 0.06 |

Warm cells: median (max) ms.

### osqprand, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 5.79 (5.81) | 0.457 (0.480) [1/5] | 42.57 (43.29) | 4.47 (4.51) | 4.39 (4.42) | 27.04 (27.98) | 3.83 (4.29) | 0.226 (0.649) | 0.06 (piqp) | 0.05 |

Warm cells: median (max) ms.

### osqprand, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 6 / 7 / -- / 9 | 5 / 7 / -- / 7 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 100 / 250 / -- / 300 | 6 / 8 / -- / 9 | 20 / 20 / -- / 20 |

### osqprand, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 6 / 8 / -- / 9 | 5 / 7 / -- / 7 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 50 / 550 / -- / 800 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |

### osqprand, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 1.55 | 0.137 | 34.89 | 4.93 | 5.03 | 1.27 | 0.906 | 13.77 |

## reduced

### reduced, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 18.99 | 15.53 | 13.87 | 12.14 | 5.93 | 0.49 (mumblebee_fast_ct) | 0.43 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 23.03 | 20.23 | 18.60 | 15.76 | 6.17 | 0.39 (mumblebee_fast_ct) | 0.33 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 26.47 | 24.85 | 22.50 | 19.38 | 5.92 | 0.31 (mumblebee_fast_ct) | 0.26 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 29.07 | 29.65 | 27.47 | 22.98 | 5.87 | 0.26 (mumblebee_fast_ct) | 0.21 |

Cold cells: median ms of the solve; setup is separate.

### reduced, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 18.48 (19.13) | 15.51 (15.59) | 13.71 (13.76) | 11.91 (11.99) | 1.08 (1.13) | 0.09 (mumblebee_fast_ct) | 0.08 |

Warm cells: median (max) ms.

### reduced, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 21.98 (22.44) | 20.13 (20.37) | 18.36 (18.49) | 15.59 (15.64) | 1.06 (1.15) | 0.07 (mumblebee_fast_ct) | 0.06 |

Warm cells: median (max) ms.

### reduced, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 26.05 (26.54) | 24.88 (25.11) | 22.89 (23.01) | 19.17 (19.22) | 1.11 (1.18) | 0.06 (mumblebee_fast_ct) | 0.05 |

Warm cells: median (max) ms.

### reduced, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 29.02 (29.31) | 29.60 (29.79) | 27.30 (27.42) | 22.85 (22.91) | 1.10 (1.15) | 0.05 (mumblebee_fast_ct) | 0.04 |

Warm cells: median (max) ms.

### reduced, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| reduced_k8 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 20 / 20 / 20 / 20 |

### reduced, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| reduced_k8 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 | 0 / 0 / 0 / 0 |

### reduced, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc |
|---|---:|---:|---:|---:|---:|
| reduced_k8 | 12.29 | 21.56 | 13.65 | 14.05 | 105 |

## single_di_box

### single_di_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.558 | 0.110 | 1.18 | 0.937 | 0.723 | 0.177 | 0.181 | 0.320 | 2.91 (hpipm) | 0.34 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.877 | 0.161 | 1.97 | 1.59 | 1.24 | 0.321 | 0.232 | 0.306 | 1.91 (hpipm) | 0.19 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 1.06 | 0.192 | 2.77 | 2.19 | 1.65 | 0.488 | 0.298 | 0.308 | 1.60 (hpipm) | 0.14 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.557 (0.562) | 0.096 (0.117) | 1.19 (1.19) | 0.937 (0.951) | 0.754 (0.763) | 0.174 (0.178) | 0.190 (0.196) | 0.090 (0.160) | 0.93 (hpipm) | 0.10 |

Warm cells: median (max) ms.

### single_di_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.845 (0.856) | 0.148 (0.154) | 1.97 (2.00) | 1.56 (1.59) | 1.24 (1.28) | 0.322 (0.337) | 0.245 (0.277) | 0.097 (0.177) | 0.66 (hpipm) | 0.06 |

Warm cells: median (max) ms.

### single_di_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 1.04 (1.06) | 0.178 (0.189) | 3.69 (3.71) | 2.18 (2.20) | 1.69 (1.74) | 0.332 (0.503) | 0.296 (0.317) | 0.098 (0.153) | 0.55 (hpipm) | 0.05 |

Warm cells: median (max) ms.

### single_di_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 5 / 8 / -- / 10 | 4 / 7 / -- / 9 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 40 / 40 / -- / 40 |

### single_di_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 5 / 8 / -- / 10 | 4 / 7 / -- / 9 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 25 / 50 / -- / 50 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |

### single_di_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 0.434 | 0.131 | 1.06 | 0.676 | 0.638 | 0.209 | 0.174 | 2.29 |

## single_quad

### single_quad, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.41 | 0.189 | 2.09 | 1.53 | 1.46 | 0.432 | 0.467 | 0.605 | 3.20 (hpipm) | 0.40 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.85 | 0.227 | 3.06 | 2.21 | 2.09 | 0.816 | 0.592 | 0.592 | 2.61 (hpipm) | 0.27 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 2.05 | 0.269 | 3.50 | 2.53 | 2.37 | 1.27 | 0.668 | 0.566 | 2.10 (hpipm) | 0.22 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.36 (1.36) | 0.188 (0.209) | 2.10 (2.13) | 1.48 (1.50) | 1.42 (1.45) | 0.421 (0.424) | 0.457 (0.497) | 0.096 (0.445) | 0.51 (hpipm) | 0.07 |

Warm cells: median (max) ms.

### single_quad, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.83 (1.85) | 0.188 (0.209) | 2.99 (3.00) | 2.16 (2.16) | 2.01 (2.03) | 0.832 (0.845) | 0.621 (0.626) | 0.097 (0.451) | 0.51 (hpipm) | 0.04 |

Warm cells: median (max) ms.

### single_quad, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 2.01 (2.23) | 0.213 (0.253) | 3.48 (3.96) | 2.50 (2.91) | 2.30 (2.60) | 1.00 (1.27) [1/5] | 0.673 (0.730) | 0.096 (0.445) | 0.45 (hpipm) | 0.04 |

Warm cells: median (max) ms.

### single_quad, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 20 / 20 / -- / 20 |

### single_quad, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 5 / 7 / -- / 8 | 4 / 5 / -- / 6 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 50 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |

### single_quad, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 0.739 | 0.147 | 3.03 | 1.40 | 1.42 | 0.537 | 0.520 | 7.35 |

## Shifted geometric means (ms; shift 0.1 ms; failures charged the time limit) and failure rates

### cold, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.18 (0% fail) | 0.141 (0% fail) | 2.08 (0% fail) | 1.26 (0% fail) | 1.21 (0% fail) | 0.729 (0% fail) | 0.399 (0% fail) | 0.522 (0% fail) |
| fleet_ring_box | 2.36 (0% fail) | 2.13 (7% fail) | 4.79 (0% fail) | 3.67 (0% fail) | 3.15 (0% fail) | 11.99 (13% fail) | 2.50 (7% fail) | 1.12 (0% fail) |
| fleet_ring_box_b4 | 1.69 (0% fail) | -- | 3.92 (0% fail) | 2.70 (0% fail) | 2.49 (0% fail) | 1.16 (0% fail) | 10.85 (20% fail) | 0.776 (0% fail) |
| fleet_ring_soc | 3.41 (0% fail) | -- | 5.04 (0% fail) | 4.61 (0% fail) | 3.80 (0% fail) | -- | -- | 2.33 (0% fail) |
| osqprand | 4.22 (0% fail) | 0.347 (0% fail) | 5.81 (0% fail) | 3.03 (0% fail) | 2.99 (0% fail) | 4.45 (0% fail) | 2.44 (0% fail) | 1.16 (0% fail) |
| reduced | 18.93 (0% fail) | -- | 15.53 (0% fail) | 13.91 (0% fail) | 12.17 (0% fail) | -- | -- | 6.00 (0% fail) |
| single_di_box | 0.561 (0% fail) | 0.115 (0% fail) | 1.18 (0% fail) | 0.938 (0% fail) | 0.723 (0% fail) | 0.173 (0% fail) | 0.184 (0% fail) | 0.330 (0% fail) |
| single_quad | 1.41 (0% fail) | 0.189 (0% fail) | 2.09 (0% fail) | 1.54 (0% fail) | 1.47 (0% fail) | 0.433 (0% fail) | 0.466 (0% fail) | 0.572 (0% fail) |
| all | 2.41 (0% fail) | -- | 4.01 (0% fail) | 2.96 (0% fail) | 2.62 (0% fail) | -- | -- | 1.08 (0% fail) |

### cold, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.59 (0% fail) | 0.179 (0% fail) | 2.78 (0% fail) | 1.70 (0% fail) | 1.66 (0% fail) | 0.828 (0% fail) | 0.470 (0% fail) | 0.530 (0% fail) |
| fleet_ring_box | 3.09 (0% fail) | 1.09 (0% fail) | 6.04 (0% fail) | 4.57 (0% fail) | 3.92 (0% fail) | 4.38 (0% fail) | 1.22 (0% fail) | 1.16 (0% fail) |
| fleet_ring_box_b4 | 2.23 (0% fail) | -- | 4.89 (0% fail) | 3.37 (0% fail) | 3.10 (0% fail) | 4.54 (0% fail) | 0.808 (0% fail) | 0.834 (0% fail) |
| fleet_ring_soc | 4.59 (0% fail) | -- | 6.96 (0% fail) | 6.28 (0% fail) | 5.26 (0% fail) | -- | -- | 2.64 (0% fail) |
| osqprand | 5.06 (0% fail) | 0.444 (0% fail) | 6.95 (0% fail) | 3.55 (0% fail) | 3.52 (0% fail) | 8.93 (0% fail) | 2.97 (0% fail) | 1.24 (0% fail) |
| reduced | 22.86 (0% fail) | -- | 20.24 (0% fail) | 18.68 (0% fail) | 15.80 (0% fail) | -- | -- | 6.14 (0% fail) |
| single_di_box | 0.876 (0% fail) | 0.162 (0% fail) | 1.98 (0% fail) | 1.60 (0% fail) | 1.24 (0% fail) | 0.326 (0% fail) | 0.239 (0% fail) | 0.321 (0% fail) |
| single_quad | 1.81 (0% fail) | 0.223 (0% fail) | 3.06 (0% fail) | 2.21 (0% fail) | 2.08 (0% fail) | 0.823 (0% fail) | 0.589 (0% fail) | 0.591 (0% fail) |
| all | 3.15 (0% fail) | -- | 5.32 (0% fail) | 3.92 (0% fail) | 3.47 (0% fail) | -- | -- | 1.13 (0% fail) |

### cold, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 5.47 (0% fail) | -- | 8.10 (0% fail) | 7.46 (0% fail) | 6.29 (0% fail) | -- | -- | 2.98 (0% fail) |
| reduced | 26.31 (0% fail) | -- | 24.73 (0% fail) | 22.75 (0% fail) | 19.35 (0% fail) | -- | -- | 5.90 (0% fail) |
| all | 12.03 (0% fail) | -- | 14.17 (0% fail) | 13.05 (0% fail) | 11.05 (0% fail) | -- | -- | 4.20 (0% fail) |

### cold, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.86 (0% fail) | 0.198 (0% fail) | 3.38 (0% fail) | 2.06 (0% fail) | 1.97 (0% fail) | 1.04 (0% fail) | 0.564 (0% fail) | 0.533 (0% fail) |
| fleet_ring_box | 3.56 (0% fail) | 2.56 (7% fail) | 7.30 (0% fail) | 5.47 (0% fail) | 4.70 (0% fail) | 8.13 (0% fail) | 1.42 (0% fail) | 1.15 (0% fail) |
| fleet_ring_box_b4 | 2.52 (0% fail) | -- | 5.94 (0% fail) | 3.93 (0% fail) | 3.59 (0% fail) | 8.20 (0% fail) | 0.986 (0% fail) | 0.826 (0% fail) |
| fleet_ring_soc | 6.15 (0% fail) | -- | 8.90 (0% fail) | 8.22 (0% fail) | 6.73 (0% fail) | -- | -- | 3.02 (0% fail) |
| osqprand | 5.80 (0% fail) | 8.64 (20% fail) | 8.84 (0% fail) | 4.51 (0% fail) | 4.39 (0% fail) | 11.87 (0% fail) | 3.42 (0% fail) | 1.16 (0% fail) |
| reduced | 29.33 (0% fail) | -- | 29.49 (0% fail) | 27.50 (0% fail) | 23.07 (0% fail) | -- | -- | 5.97 (0% fail) |
| single_di_box | 1.05 (0% fail) | 0.194 (0% fail) | 2.72 (0% fail) | 2.16 (0% fail) | 1.62 (0% fail) | 0.489 (0% fail) | 0.291 (0% fail) | 0.321 (0% fail) |
| single_quad | 2.10 (0% fail) | 0.264 (0% fail) | 3.60 (0% fail) | 2.58 (0% fail) | 2.41 (0% fail) | 1.27 (0% fail) | 0.678 (0% fail) | 0.567 (0% fail) |
| all | 3.74 (0% fail) | -- | 6.70 (0% fail) | 4.89 (0% fail) | 4.28 (0% fail) | -- | -- | 1.13 (0% fail) |

### warm, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.16 (0% fail) | 0.127 (0% fail) | 2.01 (0% fail) | 1.23 (0% fail) | 1.18 (0% fail) | 10.37 (20% fail) | 0.384 (0% fail) | 0.209 (0% fail) |
| fleet_ring_box | 2.39 (0% fail) | 2.02 (7% fail) | 4.89 (0% fail) | 3.73 (0% fail) | 3.14 (0% fail) | 3.50 (7% fail) | 2.65 (7% fail) | 0.958 (0% fail) |
| fleet_ring_box_b4 | 1.66 (0% fail) | -- | 3.98 (0% fail) | 2.75 (0% fail) | 2.53 (0% fail) | 15.11 (20% fail) | 11.22 (20% fail) | 0.780 (0% fail) |
| fleet_ring_soc | 3.34 (0% fail) | -- | 4.90 (0% fail) | 4.54 (0% fail) | 3.76 (0% fail) | -- | -- | 2.13 (0% fail) |
| osqprand | 4.19 (0% fail) | 0.347 (0% fail) | 5.80 (0% fail) | 3.02 (0% fail) | 2.95 (0% fail) | 2.58 (0% fail) | 2.44 (0% fail) | 0.295 (0% fail) |
| reduced | 18.62 (0% fail) | -- | 15.49 (0% fail) | 13.72 (0% fail) | 11.89 (0% fail) | -- | -- | 1.08 (0% fail) |
| single_di_box | 0.555 (0% fail) | 0.104 (0% fail) | 1.19 (0% fail) | 0.936 (0% fail) | 0.755 (0% fail) | 0.173 (0% fail) | 0.190 (0% fail) | 0.091 (0% fail) |
| single_quad | 1.31 (0% fail) | 0.185 (0% fail) | 2.10 (0% fail) | 1.48 (0% fail) | 1.42 (0% fail) | 0.421 (0% fail) | 0.447 (0% fail) | 0.194 (0% fail) |
| all | 2.38 (0% fail) | -- | 4.01 (0% fail) | 2.95 (0% fail) | 2.61 (0% fail) | -- | -- | 0.572 (0% fail) |

### warm, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.61 (0% fail) | 0.164 (0% fail) | 2.77 (0% fail) | 1.67 (0% fail) | 1.63 (0% fail) | 0.824 (0% fail) | 0.494 (0% fail) | 0.229 (0% fail) |
| fleet_ring_box | 3.09 (0% fail) | 1.01 (0% fail) | 6.22 (0% fail) | 4.67 (0% fail) | 4.01 (0% fail) | 4.17 (0% fail) | 1.25 (0% fail) | 1.04 (0% fail) |
| fleet_ring_box_b4 | 2.15 (0% fail) | -- | 5.01 (0% fail) | 3.41 (0% fail) | 3.11 (0% fail) | 32.22 (20% fail) | 0.813 (0% fail) | 0.777 (0% fail) |
| fleet_ring_soc | 4.50 (0% fail) | -- | 7.05 (0% fail) | 6.41 (0% fail) | 5.37 (0% fail) | -- | -- | 2.44 (0% fail) |
| osqprand | 5.25 (0% fail) | 0.438 (0% fail) | 6.95 (0% fail) | 3.64 (0% fail) | 3.52 (0% fail) | 821 (40% fail) | 2.94 (0% fail) | 0.280 (0% fail) |
| reduced | 22.11 (0% fail) | -- | 20.14 (0% fail) | 18.37 (0% fail) | 15.58 (0% fail) | -- | -- | 1.07 (0% fail) |
| single_di_box | 0.839 (0% fail) | 0.149 (0% fail) | 1.97 (0% fail) | 1.57 (0% fail) | 1.25 (0% fail) | 0.327 (0% fail) | 0.252 (0% fail) | 0.106 (0% fail) |
| single_quad | 1.74 (0% fail) | 0.186 (0% fail) | 2.89 (0% fail) | 2.08 (0% fail) | 1.94 (0% fail) | 0.831 (0% fail) | 0.604 (0% fail) | 0.195 (0% fail) |
| all | 3.11 (0% fail) | -- | 5.36 (0% fail) | 3.92 (0% fail) | 3.46 (0% fail) | -- | -- | 0.603 (0% fail) |

### warm, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 5.47 (0% fail) | -- | 8.17 (0% fail) | 7.39 (0% fail) | 6.29 (0% fail) | -- | -- | 2.51 (0% fail) |
| reduced | 26.07 (0% fail) | -- | 24.93 (0% fail) | 22.80 (0% fail) | 19.15 (0% fail) | -- | -- | 1.12 (0% fail) |
| all | 11.97 (0% fail) | -- | 14.28 (0% fail) | 13.00 (0% fail) | 10.99 (0% fail) | -- | -- | 1.69 (0% fail) |

### warm, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.87 (0% fail) | 0.184 (0% fail) | 7.86 (0% fail) | 2.02 (0% fail) | 2.01 (0% fail) | 1.03 (0% fail) | 0.601 (0% fail) | 0.227 (0% fail) |
| fleet_ring_box | 3.56 (0% fail) | 2.41 (7% fail) | 7.39 (0% fail) | 5.57 (0% fail) | 4.74 (0% fail) | 7.29 (0% fail) | 1.45 (0% fail) | 1.03 (0% fail) |
| fleet_ring_box_b4 | 2.51 (0% fail) | -- | 5.83 (0% fail) | 3.94 (0% fail) | 3.73 (0% fail) | 4.92 (0% fail) | 0.946 (0% fail) | 0.792 (0% fail) |
| fleet_ring_soc | 5.97 (0% fail) | -- | 9.06 (0% fail) | 8.26 (0% fail) | 6.82 (0% fail) | -- | -- | 2.64 (0% fail) |
| osqprand | 5.79 (0% fail) | 8.88 (20% fail) | 42.63 (0% fail) | 4.47 (0% fail) | 4.38 (0% fail) | 19.35 (0% fail) | 3.94 (0% fail) | 0.284 (0% fail) |
| reduced | 29.09 (0% fail) | -- | 29.60 (0% fail) | 27.28 (0% fail) | 22.85 (0% fail) | -- | -- | 1.10 (0% fail) |
| single_di_box | 1.02 (0% fail) | 0.177 (0% fail) | 3.59 (0% fail) | 2.10 (0% fail) | 1.66 (0% fail) | 0.389 (0% fail) | 0.293 (0% fail) | 0.099 (0% fail) |
| single_quad | 2.02 (0% fail) | 0.214 (0% fail) | 3.57 (0% fail) | 2.57 (0% fail) | 2.36 (0% fail) | 15.32 (20% fail) | 0.669 (0% fail) | 0.192 (0% fail) |
| all | 3.70 (0% fail) | -- | 8.80 (0% fail) | 4.89 (0% fail) | 4.32 (0% fail) | -- | -- | 0.606 (0% fail) |

## Where sheafmpc loses (median time over the best other solver, ratio > 1, or misses the tier)

| instance | mode | tier | sheafmpc ms | best other | its ms | ratio |
|---|---|---|---:|---|---:|---:|
| chain_M4 | cold | low | 0.518 | hpipm | 0.138 | 3.76 |
| quad_N20 | cold | low | 0.605 | hpipm | 0.189 | 3.20 |
| chain_M4 | cold | medium | 0.531 | hpipm | 0.179 | 2.97 |
| di_box_N20 | cold | low | 0.320 | hpipm | 0.110 | 2.91 |
| osqprand_nx20_s1 | cold | low | 0.979 | hpipm | 0.340 | 2.88 |
| chain_M4 | cold | high | 0.534 | hpipm | 0.193 | 2.77 |
| quad_N20 | cold | medium | 0.592 | hpipm | 0.227 | 2.61 |
| osqprand_nx20_s1 | cold | medium | 1.07 | hpipm | 0.442 | 2.42 |
| quad_N20 | cold | high | 0.566 | hpipm | 0.269 | 2.10 |
| fleet_ring_box_n4 | cold | medium | 1.34 | hpipm | 0.644 | 2.08 |
| fleet_ring_box_n4 | cold | low | 1.22 | hpipm | 0.633 | 1.92 |
| di_box_N20 | cold | medium | 0.306 | hpipm | 0.161 | 1.91 |
| fleet_ring_box_n4 | cold | high | 1.30 | hpipm | 0.731 | 1.78 |
| di_box_N20 | cold | high | 0.308 | hpipm | 0.192 | 1.60 |
| chain_M4 | warm | medium | 0.265 | hpipm | 0.166 | 1.60 |
| chain_M4 | warm | low | 0.201 | hpipm | 0.127 | 1.59 |
| fleet_ring_box_n4 | warm | medium | 0.847 | hpipm | 0.572 | 1.48 |
| chain_M4 | warm | high | 0.256 | hpipm | 0.174 | 1.47 |
| fleet_ring_box_n4 | warm | high | 0.847 | hpipm | 0.650 | 1.30 |
| fleet_ring_box_n1 | warm | medium | 0.094 | hpipm | 0.073 | 1.29 |
| fleet_ring_box_n4 | warm | low | 0.675 | hpipm | 0.540 | 1.25 |
| fleet_ring_box_n1 | cold | low | 0.086 | hpipm | 0.073 | 1.18 |
| fleet_ring_box_n16 | cold | low | 7.70 | piqp | 6.57 | 1.17 |
| fleet_ring_box_n1 | warm | low | 0.087 | hpipm | 0.075 | 1.15 |
| fleet_ring_box_n1 | warm | high | 0.089 | hpipm | 0.080 | 1.11 |
| fleet_ring_box_n1 | cold | medium | 0.085 | hpipm | 0.081 | 1.05 |
| fleet_ring_box_b4_n4 | cold | medium | 0.840 | piqp | 0.807 | 1.04 |

sheafmpc is fastest (ratio <= 1) in 37 of 64 (instance, mode, tier) cells with a finite ratio; median ratio 0.83.

## Gate: sheafmpc against mumblebee_fast (median time ratio; <= 1 passes)

| mode | tier | cells | pass | sheafmpc misses the tier | median ratio | worst ratio (instance) |
|---|---|---:|---:|---:|---:|---|
| cold | low | 10 | 10 | 0 | 0.38 | 0.46 (fleet_ring_soc_n4) |
| cold | medium | 10 | 10 | 0 | 0.30 | 0.37 (fleet_ring_soc_n4) |
| cold | e8 | 2 | 2 | 0 | 0.32 | 0.38 (fleet_ring_soc_n4) |
| cold | high | 10 | 10 | 0 | 0.22 | 0.36 (fleet_ring_soc_n4) |
| warm | low | 10 | 10 | 0 | 0.14 | 0.48 (fleet_ring_soc_n4) |
| warm | medium | 10 | 10 | 0 | 0.13 | 0.34 (fleet_ring_box_n16) |
| warm | e8 | 2 | 2 | 0 | 0.18 | 0.30 (fleet_ring_soc_n4) |
| warm | high | 10 | 10 | 0 | 0.10 | 0.32 (fleet_ring_soc_n4) |
