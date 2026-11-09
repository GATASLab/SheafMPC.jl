# Benchmark summary

Sources: /home/itaykadosh/Projects/GATAS/SheafMPC.jl/benchmarks/results/quick_local, /home/itaykadosh/Projects/GATAS/SheafMPC.jl/benchmarks/results/quick_local/mumblebee_fast, /home/itaykadosh/Projects/GATAS/SheafMPC.jl/benchmarks/results/quick_local/mumblebee_fast_ct; 10 instances.

## Setup

- host `itaykadosh-Legion-5-15AKP10`, CPU AMD Ryzen AI 7 350 w/ Radeon 860M
- Julia 1.12.6, 1 thread, BLAS threads 1; governor `powersave`, boost `1`
- 1-minute load before each instance: median 3.7, max 4.0; gate passed 10, timed out 0, skipped 0
- **clarabel**: package: Clarabel.jl; settings: tol_gap_abs = tol_gap_rel = tol_feas = eps, tol_ktratio = min(1e-6, eps), presolve off, equilibration on (default), max_iter 500; version: 0.11.1; warm_start: none (interior point); sequence mode reuses the setup through update_q!/update_b!
- **hpipm**: blasfeo_commit: d6251233923c9b475fe894fb729fb63ab693e301; blasfeo_target: X64_INTEL_HASWELL; build: HPIPM and BLASFEO Makefiles, shared libraries (sources copied from acados 00947dd external/); hpipm_commit: bad1123a96136fce3cdd8bbcbe24b853d012b840; hpipm_target: AVX; infinite_bounds: dropped if both sides infinite, else masked; iter_max: 1000; lib_dir: /home/itaykadosh/tools/hpipm-avx/X64_INTEL_HASWELL; solver: HPIPM; tolerances: tol_stat = tol_eq = tol_ineq = tol_comp = eps; warm_start: 0; x0: eliminated (stage 0 has nx = 0)
- **mumblebee**: cliquetrees: {"commit":"registry release","path":"/home/itaykadosh/.julia/packages/CliqueTrees/8e1Ca","version":"1.19.7"}; commit: e78d9b9a3a0a2f4c226bf2eb0cf20f662e7d676b (pinned as in the paper's bench/mpc); package: Mumblebee; path: /home/itaykadosh/.julia/packages/Mumblebee/NtQeH; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: none (no IPMSymbolic in this version): rebuild redoes the ordering and symbolic factorization; warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **mumblebee_fast**: cliquetrees: {"commit":"registry release","path":"/home/itaykadosh/.julia/packages/CliqueTrees/8e1Ca","version":"1.19.7"}; commit: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"9416b46f1085901406583675a7257507988c2983"}; package: Mumblebee; path: /home/itaykadosh/Projects/GATAS/Mumblebee.jl; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: IPMSymbolic built at setup; rebuild strategy reuses it (init(prob, st; symb)); warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **mumblebee_fast_ct**: cliquetrees: {"commit":"0015e2b (itay/fast-symbolic, exported with git archive)","path":"/home/itaykadosh/Projects/GATAS/CliqueTrees-fast-0015e2b","version":"1.19.6"}; commit: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"9416b46f1085901406583675a7257507988c2983"}; package: Mumblebee; path: /home/itaykadosh/Projects/GATAS/Mumblebee.jl; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: IPMSymbolic built at setup; rebuild strategy reuses it (init(prob, st; symb)); warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **osqp**: library: 0.6.2; package: OSQP.jl; settings: eps_abs = eps_rel = eps, adaptive_rho on with OSQP's default interval 0 (chosen from measured setup time, so iteration counts vary run to run), polish per variant with 3 refinement steps, max_iter 400000, scaling 10 (default); version: 0.8.1; warm_start: setup with warm_start = false (cold); warm mode: update! (factorization kept) + warm_start!(x, y) from the shifted previous solution, which turns warm starting on
- **piqp**: blasfeo: giaf/blasfeo 0a3df8683c6bf9d98168d616e0c5d05938c9d51c (0.1.4.3-91), TARGET=X64_INTEL_HASWELL, static; commit: 5d849590a18bc7f0b449057e5f2041713a85003c; compile_flags: CMAKE_BUILD_TYPE=Release, CMAKE_CXX_FLAGS_RELEASE='-O3 -march=native -DNDEBUG', BUILD_C_INTERFACE=ON, BUILD_SHARED_LIBS=ON, BUILD_WITH_TEMPLATE_INSTANTIATION=OFF, BUILD_WITH_BLASFEO=ON, link '-Wl,--exclude-libs,ALL'; compiler: GCC 13.3.0; eigen: 3.4.0; library: /home/itaykadosh/tools/piqp-install/lib/libpiqpc.so; mapping: l == u rows -> A x = b; single-nonzero rows -> variable bounds (tightest wins); other rows -> h_l <= G x <= h_u; free rows dropped; package: PIQP (C interface, in-process ccall); python_wheels: piqp 0.6.4, osqp 1.1.3 (~/tools/bench-venv); repo: https://github.com/PREDICT-EPFL/piqp (tag v0.6.4); settings: defaults of piqp_set_default_settings_sparse, then eps_abs = eps_duality_gap_abs = eps, eps_rel = eps_duality_gap_rel = 0, max_iter = 500, verbose off, compute_timings off; version: 0.6.4; warm_start: none (interior point); sequence mode uses piqp_update_sparse with vectors only
- **sheafmpc**: git: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"224dbe250c54648559b790661d18e6a2280df3c3"}; package: SheafMPC; path: /home/itaykadosh/Projects/GATAS/SheafMPC.jl; settings: package defaults (SheafMPC.Settings()), eps_abs = eps_rel = eps, max_iter 100000; warm_start: update! (factorization kept, objective constant c passed) + warm_start!(x, y) from the shifted previous solution

Protocol: accuracy tiers low 1e-3, medium 1e-6, high 1e-9 (relative objective error and relative primal residual against the reference, one shared checker on the unscaled problem); tolerance and variant calibrated per solver and instance on the first, middle and last QP; per-QP time is the median over the repeats; warm statistics exclude the first (cold) QP of the sequence. `--` means not applicable, or no QP met the tier. `f/n` = QPs missing the tier.

## chain

### chain, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 0.733 | 0.078 | 1.24 | 0.698 | 0.775 | 0.450 | 0.209 | 0.278 | 3.57 (hpipm) | 0.40 |

Cold cells: median ms of the solve; setup is separate.

### chain, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 0.955 | 0.101 | 1.70 | 0.934 | 1.02 | 0.452 | 0.249 | 0.359 | 3.56 (hpipm) | 0.38 |

Cold cells: median ms of the solve; setup is separate.

### chain, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.09 | 0.090 | 1.92 | 1.06 | 1.41 | 0.652 | 0.305 | 0.388 | 4.29 (hpipm) | 0.36 |

Cold cells: median ms of the solve; setup is separate.

### chain, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 0.701 (0.709) | 0.077 (0.079) | 1.16 (1.19) | 0.679 (0.687) | 0.744 (0.746) | 0.416 (0.443) [1/5] | 0.217 (0.231) | 0.124 (0.218) | 1.62 (hpipm) | 0.18 |

Warm cells: median (max) ms.

### chain, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 0.931 (1.06) | 0.097 (0.101) | 1.61 (1.62) | 0.910 (0.920) | 0.974 (3.96) | 0.450 (0.652) | 0.249 (0.307) | 0.167 (0.208) | 1.72 (hpipm) | 0.18 |

Warm cells: median (max) ms.

### chain, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.15 (1.44) | 0.097 (0.119) | 3.51 (3.91) | 1.14 (1.27) | 1.80 (4.73) | 0.649 (0.656) | 0.301 (0.366) | 0.162 (0.208) | 1.67 (hpipm) | 0.14 |

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
| chain_M4 | 0.452 | 0.134 | 1.66 | 0.673 | 0.810 | 0.275 | 0.354 | 3.07 |

## fleet_ring_box

### fleet_ring_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.204 | 0.047 | 0.524 | 0.444 | 0.312 | 0.204 [1/5] | 0.059 | 0.062 | 1.33 (hpipm) | 0.14 |
| fleet_ring_box_n4 | 560 | 1.43 | 0.307 | 2.70 | 5.01 | 1.73 | 0.800 [1/5] | 0.421 [1/5] | 0.667 | 2.17 (hpipm) | 0.13 |
| fleet_ring_box_n16 | 2240 | 9.09 | 5.65 [1/5] | 13.94 | 18.75 | 8.79 | 8.59 | 3.93 | 4.08 | 1.04 (piqp) | 0.22 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.283 | 0.048 | 0.691 | 0.582 | 0.417 | 0.400 | 0.070 | 0.055 | 1.14 (hpipm) | 0.09 |
| fleet_ring_box_n4 | 560 | 1.86 | 0.312 | 3.28 | 5.49 | 2.18 | 3.35 | 0.567 | 0.897 | 2.87 (hpipm) | 0.16 |
| fleet_ring_box_n16 | 2240 | 12.49 | 7.90 | 18.11 | 25.12 | 12.10 | 19.07 | 5.46 | 4.26 | 0.78 (piqp) | 0.17 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.311 | 0.048 | 0.790 | 0.649 | 0.475 | 0.658 | 0.094 | 0.052 | 1.08 (hpipm) | 0.08 |
| fleet_ring_box_n4 | 560 | 2.25 | 0.341 | 3.85 | 5.97 | 2.63 | 6.51 | 0.702 | 0.931 | 2.73 (hpipm) | 0.16 |
| fleet_ring_box_n16 | 2240 | 14.77 | 10.48 [1/5] | 22.40 | 30.49 | 29.81 | 39.68 | 6.22 | 4.21 | 0.68 (piqp) | 0.14 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.204 (0.240) | 0.044 (0.046) | 0.518 (0.644) | 0.455 (0.603) | 0.330 (0.412) | 0.085 (0.086) | 0.062 (0.065) | 0.047 (0.113) | 1.07 (hpipm) | 0.10 |
| fleet_ring_box_n4 | 560 | 1.39 (1.58) | 0.269 (0.308) | 2.64 (2.95) | 4.97 (5.15) | 1.72 (1.93) | 0.735 (1.08) [1/5] | 0.428 (0.450) [1/5] | 0.416 (0.789) | 1.55 (hpipm) | 0.08 |
| fleet_ring_box_n16 | 2240 | 8.77 (12.99) | 5.10 (6.12) [1/5] | 12.11 (16.53) | 18.51 (22.57) | 8.66 (9.72) | 6.98 (10.00) | 4.10 (4.59) | 3.92 (6.54) | 0.95 (piqp) | 0.21 |

Warm cells: median (max) ms.

### fleet_ring_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.281 (0.318) | 0.046 (0.069) | 0.689 (0.777) | 0.612 (0.654) | 0.419 (0.473) | 0.477 (0.557) | 0.078 (0.094) | 0.049 (0.110) | 1.07 (hpipm) | 0.08 |
| fleet_ring_box_n4 | 560 | 1.79 (1.97) | 0.271 (0.273) | 3.23 (3.55) | 5.40 (5.69) | 2.16 (2.40) | 3.24 (4.00) | 0.574 (0.586) | 0.508 (0.773) | 1.88 (hpipm) | 0.09 |
| fleet_ring_box_n16 | 2240 | 14.06 (15.20) | 6.97 (7.56) | 19.54 (21.03) | 27.82 (32.06) | 12.86 (14.92) | 18.68 (22.17) | 5.37 (8.92) | 4.13 (6.45) | 0.77 (piqp) | 0.15 |

Warm cells: median (max) ms.

### fleet_ring_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.307 (0.422) | 0.048 (0.075) | 0.778 (0.955) | 0.716 (3.66) | 0.475 (0.583) | 0.928 (1.01) | 0.092 (0.101) | 0.047 (0.112) | 0.96 (hpipm) | 0.07 |
| fleet_ring_box_n4 | 560 | 2.06 (2.25) | 0.307 (0.336) | 3.86 (3.88) | 5.90 (5.91) | 2.61 (2.61) | 4.33 (5.85) | 0.701 (0.765) | 0.536 (0.820) | 1.75 (hpipm) | 0.09 |
| fleet_ring_box_n16 | 2240 | 15.82 (17.55) | 10.81 (13.41) [1/5] | 22.34 (22.54) | 33.12 (33.19) | 29.61 (32.66) | 29.91 (77.46) | 6.20 (9.25) | 4.10 (6.53) | 0.66 (piqp) | 0.12 |

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
| fleet_ring_box_n1 | 0.168 | 0.116 | 0.330 | 0.340 | 0.205 | 0.089 | 0.105 | 0.972 |
| fleet_ring_box_n4 | 0.931 | 0.177 | 1.29 | 1.04 | 0.860 | 0.614 | 0.272 | 5.85 |
| fleet_ring_box_n16 | 2.38 | 1.43 | 4.68 | 6.68 | 3.36 | 1.89 | 1.33 | 25.98 |

## fleet_ring_box_b4

### fleet_ring_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.08 | 2.18 | 4.59 | 4.49 | 0.795 | 0.363 [1/5] | 0.440 | 0.55 (osqp) | 0.10 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.37 | 2.76 | 1.78 | 1.88 | 2.73 | 0.472 | 0.547 | 1.16 (piqp) | 0.31 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.63 | 3.23 | 2.12 | 5.23 | 4.29 | 0.527 | 0.558 | 1.06 (piqp) | 0.26 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.07 (1.08) | 2.10 (2.35) | 1.52 (1.66) | 4.38 (4.58) | 0.601 (0.806) [1/5] | 0.363 (0.364) [1/5] | 0.340 (0.827) | 0.32 (clarabel) | 0.22 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.34 (1.34) | 2.61 (2.92) | 1.74 (1.91) | 4.77 (4.88) | 1.71 (2.49) | 0.472 (0.486) | 0.337 (0.822) | 0.71 (piqp) | 0.19 |

Warm cells: median (max) ms.

### fleet_ring_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.59 (1.61) | 3.10 (3.34) | 2.09 (2.10) | 5.12 (5.15) | 2.84 (4.18) | 0.539 (0.559) | 0.329 (0.824) | 0.61 (piqp) | 0.16 |

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
| fleet_ring_box_b4_n4 | 0.555 | 1.10 | 0.838 | 0.993 | 0.374 | 0.282 | 3.51 |

## fleet_ring_soc

### fleet_ring_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 1.98 | 2.71 | 5.53 | 5.23 | 1.49 | 0.75 (clarabel) | 0.27 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 2.61 | 3.88 | 6.49 | 6.16 | 1.56 | 0.60 (clarabel) | 0.24 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.25 | 4.36 | 7.24 | 9.54 | 1.73 | 0.53 (clarabel) | 0.24 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.57 | 4.76 | 7.38 | 7.17 | 1.73 | 0.48 (clarabel) | 0.23 |

Cold cells: median ms of the solve; setup is separate.

### fleet_ring_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 1.85 (2.41) | 2.65 (3.08) | 5.36 (5.80) | 5.13 (5.49) | 1.23 (2.58) | 0.67 (clarabel) | 0.23 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 2.76 (5.59) | 3.79 (4.18) | 6.49 (6.89) | 6.17 (9.11) | 1.21 (2.80) | 0.44 (clarabel) | 0.19 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.15 (3.17) | 4.56 (7.25) | 9.92 (10.29) | 6.80 (9.73) | 1.35 (2.75) | 0.43 (clarabel) | 0.14 |

Warm cells: median (max) ms.

### fleet_ring_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.42 (3.49) [2/5] | 4.97 (5.01) | 8.09 (11.07) | 7.06 (10.04) | 1.54 (2.75) | 0.31 (mumblebee) | 0.19 |

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
| fleet_ring_soc_n4 | 0.956 | 1.23 | 4.09 | 1.10 | 7.65 |

## osqprand

### osqprand, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.38 | 0.140 | 3.58 | 1.72 | 1.90 | 2.78 | 1.27 | 0.641 | 4.57 (hpipm) | 0.37 |

Cold cells: median ms of the solve; setup is separate.

### osqprand, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.77 | 0.192 | 4.17 | 1.99 | 2.03 | 5.46 | 1.64 | 0.635 | 3.31 (hpipm) | 0.32 |

Cold cells: median ms of the solve; setup is separate.

### osqprand, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 3.33 | 0.189 [1/5] | 5.28 | 2.50 | 2.51 | 7.06 | 1.81 | 0.678 | 0.37 (piqp) | 0.27 |

Cold cells: median ms of the solve; setup is separate.

### osqprand, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.35 (2.36) | 0.144 (0.171) | 3.52 (6.54) | 1.70 (1.72) | 1.68 (1.71) | 1.55 (1.56) | 1.27 (1.45) | 0.145 (0.415) | 1.00 (hpipm) | 0.09 |

Warm cells: median (max) ms.

### osqprand, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.98 (2.99) | 0.196 (0.201) | 4.06 (4.26) | 1.96 (1.97) | 1.94 (1.95) | 8.64 (14.36) [1/5] | 1.64 (1.64) | 0.137 (0.408) | 0.70 (hpipm) | 0.07 |

Warm cells: median (max) ms.

### osqprand, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 3.30 (3.45) | 0.196 (0.197) [1/5] | 18.31 (18.44) | 2.45 (2.46) | 2.46 (5.47) | 20.19 (20.75) | 1.83 (2.01) | 0.140 (0.412) | 0.08 (piqp) | 0.06 |

Warm cells: median (max) ms.

### osqprand, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 6 / 7 / -- / 9 | 5 / 7 / -- / 7 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 100 / 250 / -- / 300 | 6 / 8 / -- / 9 | 20 / 20 / -- / 20 |

### osqprand, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 6 / 8 / -- / 9 | 5 / 7 / -- / 7 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 50 / 575 / -- / 800 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |

### osqprand, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 0.857 | 0.071 | 10.46 | 3.37 | 3.34 | 0.758 | 0.583 | 8.12 |

## reduced

### reduced, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 11.96 | 8.44 | 7.31 | 6.66 | 3.02 | 0.45 (mumblebee_fast_ct) | 0.41 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 16.72 | 11.05 | 18.94 | 8.64 | 3.01 | 0.35 (mumblebee_fast_ct) | 0.16 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 18.86 | 16.56 | 24.18 | 10.78 | 3.00 | 0.28 (mumblebee_fast_ct) | 0.12 |

Cold cells: median ms of the solve; setup is separate.

### reduced, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 20.48 | 18.23 | 29.72 | 15.58 | 3.04 | 0.19 (mumblebee_fast_ct) | 0.10 |

Cold cells: median ms of the solve; setup is separate.

### reduced, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 11.56 (11.91) | 8.26 (11.35) | 7.32 (7.33) | 6.52 (6.62) | 0.635 (0.639) | 0.10 (mumblebee_fast_ct) | 0.09 |

Warm cells: median (max) ms.

### reduced, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 13.34 (16.50) | 10.96 (11.03) | 21.75 (24.82) | 8.59 (9.16) | 0.612 (0.626) | 0.07 (mumblebee_fast_ct) | 0.03 |

Warm cells: median (max) ms.

### reduced, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 18.91 (19.03) | 13.72 (16.54) | 23.98 (27.00) | 10.56 (13.67) | 0.620 (0.656) | 0.06 (mumblebee_fast_ct) | 0.03 |

Warm cells: median (max) ms.

### reduced, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 20.12 (20.42) | 19.05 (19.10) | 29.47 (32.44) | 13.11 (15.57) | 0.622 (0.642) | 0.05 (mumblebee_fast_ct) | 0.02 |

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
| reduced_k8 | 6.75 | 10.64 | 17.20 | 8.38 | 61.62 |

## single_di_box

### single_di_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.374 | 0.065 | 0.680 | 0.502 | 0.466 | 0.118 | 0.113 | 0.191 | 2.92 (hpipm) | 0.38 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.540 | 0.085 | 1.11 | 0.829 | 0.745 | 0.232 | 0.155 | 0.191 | 2.24 (hpipm) | 0.23 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.670 | 0.103 | 1.52 | 1.16 | 3.90 | 0.344 | 0.168 | 0.191 | 1.85 (hpipm) | 0.17 |

Cold cells: median ms of the solve; setup is separate.

### single_di_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.359 (0.377) | 0.072 (0.073) | 0.641 (0.661) | 0.505 (0.508) | 0.457 (0.464) | 0.123 (0.130) | 0.112 (0.113) | 0.071 (0.106) | 0.98 (hpipm) | 0.14 |

Warm cells: median (max) ms.

### single_di_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.541 (0.561) | 0.096 (0.102) | 1.07 (1.09) | 0.837 (0.840) | 0.735 (3.74) | 0.233 (0.235) | 0.143 (0.162) | 0.059 (0.102) | 0.61 (hpipm) | 0.07 |

Warm cells: median (max) ms.

### single_di_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.673 (0.709) | 0.112 (0.115) | 2.00 (2.09) | 1.17 (1.17) | 0.999 (1.01) | 0.235 (0.345) | 0.172 (0.186) | 0.063 (0.103) | 0.57 (hpipm) | 0.05 |

Warm cells: median (max) ms.

### single_di_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 5 / 8 / -- / 10 | 5 / 7 / -- / 9 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 40 / 40 / -- / 40 |

### single_di_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 5 / 8 / -- / 10 | 5 / 7 / -- / 9 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 25 / 50 / -- / 50 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |

### single_di_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 0.302 | 0.072 | 0.574 | 0.398 | 0.503 | 0.150 | 0.146 | 1.43 |

## single_quad

### single_quad, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 0.816 | 0.089 | 1.25 | 0.845 | 0.973 | 0.262 | 0.243 | 0.323 | 3.65 (hpipm) | 0.38 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.09 | 0.127 | 1.74 | 1.19 | 4.31 | 0.508 | 0.313 | 0.466 | 3.66 (hpipm) | 0.39 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.32 | 0.134 | 2.04 | 1.37 | 1.62 | 0.777 | 0.363 | 0.476 | 3.54 (hpipm) | 0.35 |

Cold cells: median ms of the solve; setup is separate.

### single_quad, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 0.800 (0.805) | 0.083 (0.087) | 1.19 (1.30) | 0.797 (0.806) | 0.888 (0.889) | 0.263 (0.265) | 0.234 (0.244) | 0.063 (0.280) | 0.75 (hpipm) | 0.08 |

Warm cells: median (max) ms.

### single_quad, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.06 (1.08) | 0.121 (0.135) | 1.69 (1.71) | 1.16 (1.16) | 4.17 (4.20) | 0.509 (0.519) | 0.316 (0.329) | 0.081 (0.284) | 0.67 (hpipm) | 0.07 |

Warm cells: median (max) ms.

### single_quad, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.21 (1.31) | 0.120 (0.137) | 1.95 (2.20) | 1.34 (1.52) | 4.41 (4.61) | 0.623 (0.794) [1/5] | 0.347 (0.377) | 0.060 (0.283) | 0.50 (hpipm) | 0.05 |

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
| quad_N20 | 0.568 | 0.082 | 1.45 | 0.888 | 4.04 | 0.377 | 0.368 | 4.73 |

## Shifted geometric means (ms; shift 0.1 ms; failures charged the time limit) and failure rates

### cold, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.738 (0% fail) | 0.077 (0% fail) | 1.23 (0% fail) | 0.698 (0% fail) | 0.770 (0% fail) | 0.460 (0% fail) | 0.213 (0% fail) | 0.272 (0% fail) |
| fleet_ring_box | 1.58 (0% fail) | 1.23 (7% fail) | 2.85 (0% fail) | 3.75 (0% fail) | 1.82 (0% fail) | 6.31 (13% fail) | 1.44 (7% fail) | 0.714 (0% fail) |
| fleet_ring_box_b4 | 1.04 (0% fail) | -- | 2.23 (0% fail) | 3.72 (0% fail) | 2.97 (0% fail) | 0.703 (0% fail) | 4.74 (20% fail) | 0.458 (0% fail) |
| fleet_ring_soc | 2.05 (0% fail) | -- | 2.78 (0% fail) | 5.58 (0% fail) | 4.45 (0% fail) | -- | -- | 1.61 (0% fail) |
| osqprand | 2.39 (0% fail) | 0.152 (0% fail) | 3.48 (0% fail) | 1.67 (0% fail) | 2.25 (0% fail) | 2.78 (0% fail) | 1.31 (0% fail) | 0.734 (0% fail) |
| reduced | 12.88 (0% fail) | -- | 9.53 (0% fail) | 7.32 (0% fail) | 6.67 (0% fail) | -- | -- | 3.03 (0% fail) |
| single_di_box | 0.378 (0% fail) | 0.065 (0% fail) | 0.686 (0% fail) | 0.501 (0% fail) | 0.469 (0% fail) | 0.120 (0% fail) | 0.117 (0% fail) | 0.190 (0% fail) |
| single_quad | 0.829 (0% fail) | 0.089 (0% fail) | 1.25 (0% fail) | 0.844 (0% fail) | 1.34 (0% fail) | 0.263 (0% fail) | 0.247 (0% fail) | 0.382 (0% fail) |
| all | 1.54 (0% fail) | -- | 2.37 (0% fail) | 2.34 (0% fail) | 1.92 (0% fail) | -- | -- | 0.667 (0% fail) |

### cold, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.982 (0% fail) | 0.102 (0% fail) | 1.68 (0% fail) | 0.934 (0% fail) | 1.35 (0% fail) | 0.524 (0% fail) | 0.255 (0% fail) | 0.355 (0% fail) |
| fleet_ring_box | 2.02 (0% fail) | 0.697 (0% fail) | 3.50 (0% fail) | 4.48 (0% fail) | 2.32 (0% fail) | 3.03 (0% fail) | 0.760 (0% fail) | 0.763 (0% fail) |
| fleet_ring_box_b4 | 1.37 (0% fail) | -- | 2.76 (0% fail) | 1.82 (0% fail) | 2.26 (0% fail) | 3.15 (0% fail) | 0.475 (0% fail) | 0.538 (0% fail) |
| fleet_ring_soc | 2.69 (0% fail) | -- | 3.83 (0% fail) | 6.44 (0% fail) | 6.08 (0% fail) | -- | -- | 1.74 (0% fail) |
| osqprand | 2.86 (0% fail) | 0.193 (0% fail) | 4.18 (0% fail) | 2.01 (0% fail) | 2.03 (0% fail) | 5.65 (0% fail) | 1.64 (0% fail) | 0.723 (0% fail) |
| reduced | 15.44 (0% fail) | -- | 12.11 (0% fail) | 15.00 (0% fail) | 8.68 (0% fail) | -- | -- | 3.00 (0% fail) |
| single_di_box | 0.541 (0% fail) | 0.086 (0% fail) | 1.11 (0% fail) | 0.829 (0% fail) | 1.04 (0% fail) | 0.232 (0% fail) | 0.151 (0% fail) | 0.187 (0% fail) |
| single_quad | 1.09 (0% fail) | 0.120 (0% fail) | 1.75 (0% fail) | 1.19 (0% fail) | 2.72 (0% fail) | 0.516 (0% fail) | 0.313 (0% fail) | 0.464 (0% fail) |
| all | 1.97 (0% fail) | -- | 3.09 (0% fail) | 2.84 (0% fail) | 2.56 (0% fail) | -- | -- | 0.722 (0% fail) |

### cold, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 3.22 (0% fail) | -- | 4.50 (0% fail) | 7.74 (0% fail) | 8.35 (0% fail) | -- | -- | 1.86 (0% fail) |
| reduced | 18.09 (0% fail) | -- | 15.48 (0% fail) | 25.36 (0% fail) | 11.80 (0% fail) | -- | -- | 3.01 (0% fail) |
| all | 7.67 (0% fail) | -- | 8.37 (0% fail) | 14.03 (0% fail) | 9.93 (0% fail) | -- | -- | 2.37 (0% fail) |

### cold, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.14 (0% fail) | 0.092 (0% fail) | 2.00 (0% fail) | 1.13 (0% fail) | 2.08 (0% fail) | 0.653 (0% fail) | 0.312 (0% fail) | 0.387 (0% fail) |
| fleet_ring_box | 2.36 (0% fail) | 1.51 (7% fail) | 4.16 (0% fail) | 5.16 (0% fail) | 3.58 (0% fail) | 5.52 (0% fail) | 0.886 (0% fail) | 0.766 (0% fail) |
| fleet_ring_box_b4 | 1.58 (0% fail) | -- | 3.23 (0% fail) | 2.12 (0% fail) | 4.42 (0% fail) | 5.11 (0% fail) | 0.536 (0% fail) | 0.543 (0% fail) |
| fleet_ring_soc | 3.58 (0% fail) | -- | 4.87 (0% fail) | 7.99 (0% fail) | 8.09 (0% fail) | -- | -- | 1.87 (0% fail) |
| osqprand | 3.34 (0% fail) | 3.25 (20% fail) | 5.27 (0% fail) | 2.50 (0% fail) | 2.50 (0% fail) | 7.51 (0% fail) | 1.85 (0% fail) | 0.733 (0% fail) |
| reduced | 19.43 (0% fail) | -- | 18.04 (0% fail) | 30.27 (0% fail) | 14.37 (0% fail) | -- | -- | 3.04 (0% fail) |
| single_di_box | 0.672 (0% fail) | 0.104 (0% fail) | 1.51 (0% fail) | 1.14 (0% fail) | 2.31 (0% fail) | 0.344 (0% fail) | 0.171 (0% fail) | 0.189 (0% fail) |
| single_quad | 1.47 (0% fail) | 0.138 (0% fail) | 2.09 (0% fail) | 1.41 (0% fail) | 2.34 (0% fail) | 0.771 (0% fail) | 0.358 (0% fail) | 0.474 (0% fail) |
| all | 2.39 (0% fail) | -- | 3.85 (0% fail) | 3.60 (0% fail) | 3.83 (0% fail) | -- | -- | 0.740 (0% fail) |

### warm, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.702 (0% fail) | 0.076 (0% fail) | 1.16 (0% fail) | 0.681 (0% fail) | 0.742 (0% fail) | 4.77 (20% fail) | 0.214 (0% fail) | 0.131 (0% fail) |
| fleet_ring_box | 1.55 (0% fail) | 1.12 (7% fail) | 2.77 (0% fail) | 3.35 (0% fail) | 1.86 (0% fail) | 2.23 (7% fail) | 1.44 (7% fail) | 0.607 (0% fail) |
| fleet_ring_box_b4 | 1.03 (0% fail) | -- | 2.18 (0% fail) | 1.57 (0% fail) | 4.44 (0% fail) | 6.61 (20% fail) | 4.77 (20% fail) | 0.441 (0% fail) |
| fleet_ring_soc | 1.99 (0% fail) | -- | 2.74 (0% fail) | 5.44 (0% fail) | 4.36 (0% fail) | -- | -- | 1.25 (0% fail) |
| osqprand | 2.35 (0% fail) | 0.150 (0% fail) | 3.84 (0% fail) | 1.65 (0% fail) | 1.63 (0% fail) | 1.55 (0% fail) | 1.31 (0% fail) | 0.183 (0% fail) |
| reduced | 11.62 (0% fail) | -- | 8.91 (0% fail) | 7.30 (0% fail) | 6.54 (0% fail) | -- | -- | 0.632 (0% fail) |
| single_di_box | 0.362 (0% fail) | 0.070 (0% fail) | 0.644 (0% fail) | 0.505 (0% fail) | 0.453 (0% fail) | 0.123 (0% fail) | 0.113 (0% fail) | 0.066 (0% fail) |
| single_quad | 0.772 (0% fail) | 0.081 (0% fail) | 1.21 (0% fail) | 0.798 (0% fail) | 0.885 (0% fail) | 0.263 (0% fail) | 0.232 (0% fail) | 0.125 (0% fail) |
| all | 1.48 (0% fail) | -- | 2.32 (0% fail) | 2.05 (0% fail) | 1.85 (0% fail) | -- | -- | 0.364 (0% fail) |

### warm, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.974 (0% fail) | 0.096 (0% fail) | 1.61 (0% fail) | 0.912 (0% fail) | 1.29 (0% fail) | 0.522 (0% fail) | 0.265 (0% fail) | 0.145 (0% fail) |
| fleet_ring_box | 2.08 (0% fail) | 0.637 (0% fail) | 3.57 (0% fail) | 4.13 (0% fail) | 2.40 (0% fail) | 2.98 (0% fail) | 0.798 (0% fail) | 0.642 (0% fail) |
| fleet_ring_box_b4 | 1.31 (0% fail) | -- | 2.70 (0% fail) | 1.80 (0% fail) | 4.05 (0% fail) | 1.80 (0% fail) | 0.473 (0% fail) | 0.442 (0% fail) |
| fleet_ring_soc | 3.04 (0% fail) | -- | 3.77 (0% fail) | 6.48 (0% fail) | 6.64 (0% fail) | -- | -- | 1.40 (0% fail) |
| osqprand | 2.87 (0% fail) | 0.196 (0% fail) | 4.10 (0% fail) | 1.95 (0% fail) | 1.94 (0% fail) | 48.45 (20% fail) | 1.64 (0% fail) | 0.179 (0% fail) |
| reduced | 14.48 (0% fail) | -- | 10.90 (0% fail) | 21.78 (0% fail) | 8.68 (0% fail) | -- | -- | 0.613 (0% fail) |
| single_di_box | 0.545 (0% fail) | 0.096 (0% fail) | 1.07 (0% fail) | 0.837 (0% fail) | 1.02 (0% fail) | 0.234 (0% fail) | 0.147 (0% fail) | 0.064 (0% fail) |
| single_quad | 1.01 (0% fail) | 0.122 (0% fail) | 1.64 (0% fail) | 1.12 (0% fail) | 2.52 (0% fail) | 0.509 (0% fail) | 0.310 (0% fail) | 0.132 (0% fail) |
| all | 1.98 (0% fail) | -- | 3.02 (0% fail) | 2.84 (0% fail) | 2.72 (0% fail) | -- | -- | 0.378 (0% fail) |

### warm, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 3.13 (0% fail) | -- | 4.92 (0% fail) | 9.41 (0% fail) | 7.67 (0% fail) | -- | -- | 1.47 (0% fail) |
| reduced | 18.22 (0% fail) | -- | 14.70 (0% fail) | 24.64 (0% fail) | 11.68 (0% fail) | -- | -- | 0.626 (0% fail) |
| all | 7.59 (0% fail) | -- | 8.52 (0% fail) | 15.24 (0% fail) | 9.47 (0% fail) | -- | -- | 0.966 (0% fail) |

### warm, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.15 (0% fail) | 0.099 (0% fail) | 3.54 (0% fail) | 1.12 (0% fail) | 2.12 (0% fail) | 0.650 (0% fail) | 0.318 (0% fail) | 0.145 (0% fail) |
| fleet_ring_box | 2.36 (0% fail) | 1.48 (7% fail) | 4.22 (0% fail) | 5.80 (0% fail) | 3.57 (0% fail) | 5.11 (0% fail) | 0.915 (0% fail) | 0.654 (0% fail) |
| fleet_ring_box_b4 | 1.54 (0% fail) | -- | 3.14 (0% fail) | 2.09 (0% fail) | 4.31 (0% fail) | 3.04 (0% fail) | 0.535 (0% fail) | 0.436 (0% fail) |
| fleet_ring_soc | 173 (40% fail) | -- | 4.83 (0% fail) | 8.96 (0% fail) | 7.99 (0% fail) | -- | -- | 1.51 (0% fail) |
| osqprand | 3.33 (0% fail) | 3.31 (20% fail) | 17.09 (0% fail) | 2.45 (0% fail) | 2.88 (0% fail) | 13.52 (0% fail) | 1.86 (0% fail) | 0.182 (0% fail) |
| reduced | 19.06 (0% fail) | -- | 17.81 (0% fail) | 30.52 (0% fail) | 13.88 (0% fail) | -- | -- | 0.624 (0% fail) |
| single_di_box | 0.664 (0% fail) | 0.110 (0% fail) | 1.96 (0% fail) | 1.12 (0% fail) | 0.961 (0% fail) | 0.274 (0% fail) | 0.172 (0% fail) | 0.065 (0% fail) |
| single_quad | 1.19 (0% fail) | 0.119 (0% fail) | 1.99 (0% fail) | 1.37 (0% fail) | 2.85 (0% fail) | 6.86 (20% fail) | 0.345 (0% fail) | 0.122 (0% fail) |
| all | 3.48 (4% fail) | -- | 4.68 (0% fail) | 3.74 (0% fail) | 3.62 (0% fail) | -- | -- | 0.382 (0% fail) |

## Where sheafmpc loses (median time over the best other solver, ratio > 1, or misses the tier)

| instance | mode | tier | sheafmpc ms | best other | its ms | ratio |
|---|---|---|---:|---|---:|---:|
| osqprand_nx20_s1 | cold | low | 0.641 | hpipm | 0.140 | 4.57 |
| chain_M4 | cold | high | 0.388 | hpipm | 0.090 | 4.29 |
| quad_N20 | cold | medium | 0.466 | hpipm | 0.127 | 3.66 |
| quad_N20 | cold | low | 0.323 | hpipm | 0.089 | 3.65 |
| chain_M4 | cold | low | 0.278 | hpipm | 0.078 | 3.57 |
| chain_M4 | cold | medium | 0.359 | hpipm | 0.101 | 3.56 |
| quad_N20 | cold | high | 0.476 | hpipm | 0.134 | 3.54 |
| osqprand_nx20_s1 | cold | medium | 0.635 | hpipm | 0.192 | 3.31 |
| di_box_N20 | cold | low | 0.191 | hpipm | 0.065 | 2.92 |
| fleet_ring_box_n4 | cold | medium | 0.897 | hpipm | 0.312 | 2.87 |
| fleet_ring_box_n4 | cold | high | 0.931 | hpipm | 0.341 | 2.73 |
| di_box_N20 | cold | medium | 0.191 | hpipm | 0.085 | 2.24 |
| fleet_ring_box_n4 | cold | low | 0.667 | hpipm | 0.307 | 2.17 |
| fleet_ring_box_n4 | warm | medium | 0.508 | hpipm | 0.271 | 1.88 |
| di_box_N20 | cold | high | 0.191 | hpipm | 0.103 | 1.85 |
| fleet_ring_box_n4 | warm | high | 0.536 | hpipm | 0.307 | 1.75 |
| chain_M4 | warm | medium | 0.167 | hpipm | 0.097 | 1.72 |
| chain_M4 | warm | high | 0.162 | hpipm | 0.097 | 1.67 |
| chain_M4 | warm | low | 0.124 | hpipm | 0.077 | 1.62 |
| fleet_ring_box_n4 | warm | low | 0.416 | hpipm | 0.269 | 1.55 |
| fleet_ring_box_n1 | cold | low | 0.062 | hpipm | 0.047 | 1.33 |
| fleet_ring_box_b4_n4 | cold | medium | 0.547 | piqp | 0.472 | 1.16 |
| fleet_ring_box_n1 | cold | medium | 0.055 | hpipm | 0.048 | 1.14 |
| fleet_ring_box_n1 | cold | high | 0.052 | hpipm | 0.048 | 1.08 |
| fleet_ring_box_n1 | warm | low | 0.047 | hpipm | 0.044 | 1.07 |
| fleet_ring_box_n1 | warm | medium | 0.049 | hpipm | 0.046 | 1.07 |
| fleet_ring_box_b4_n4 | cold | high | 0.558 | piqp | 0.527 | 1.06 |
| fleet_ring_box_n16 | cold | low | 4.08 | piqp | 3.93 | 1.04 |
| osqprand_nx20_s1 | warm | low | 0.145 | hpipm | 0.144 | 1.00 |

sheafmpc is fastest (ratio <= 1) in 35 of 64 (instance, mode, tier) cells with a finite ratio; median ratio 0.87.

## Gate: sheafmpc against mumblebee_fast (median time ratio; <= 1 passes)

| mode | tier | cells | pass | sheafmpc misses the tier | median ratio | worst ratio (instance) |
|---|---|---:|---:|---:|---:|---|
| cold | low | 10 | 10 | 0 | 0.32 | 0.41 (reduced_k8) |
| cold | medium | 10 | 10 | 0 | 0.24 | 0.39 (quad_N20) |
| cold | e8 | 2 | 2 | 0 | 0.18 | 0.24 (fleet_ring_soc_n4) |
| cold | high | 10 | 10 | 0 | 0.20 | 0.36 (chain_M4) |
| warm | low | 10 | 10 | 0 | 0.12 | 0.23 (fleet_ring_soc_n4) |
| warm | medium | 10 | 10 | 0 | 0.09 | 0.19 (fleet_ring_box_b4_n4) |
| warm | e8 | 2 | 2 | 0 | 0.08 | 0.14 (fleet_ring_soc_n4) |
| warm | high | 10 | 10 | 0 | 0.08 | 0.19 (fleet_ring_soc_n4) |
