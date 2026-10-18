# Benchmark summary

Sources: results/hpg_a284b72/quick_20261018_a284b72a48_shared, results/hpg_a284b72/quick_20261018_a284b72a48_shared/mumblebee_fast, results/hpg_a284b72/quick_20261018_a284b72a48_shared/mumblebee_fast_ct; 10 instances.

## Setup

- host `c0705a-s16.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- Julia 1.12.6, 1 thread, BLAS threads 1; governor ``, boost ``
- 1-minute load before each instance: median 97.0, max 98.9; gate passed 10, timed out 0, skipped 0
- involuntary context switches while timing an instance: median 31, max 372 (fleet_ring_box_n1)
- **clarabel**: package: Clarabel.jl; settings: tol_gap_abs = tol_gap_rel = tol_feas = eps, tol_ktratio = min(1e-6, eps), presolve off, equilibration on (default), max_iter 500; version: 0.11.1; warm_start: none (interior point); sequence mode reuses the setup through update_q!/update_b!
- **hpipm**: blasfeo_target: X64_AUTOMATIC (X64_INTEL_HASWELL); build: acados 00947dd (cmake); hpipm_commit: bad1123; hpipm_target: GENERIC; infinite_bounds: dropped if both sides infinite, else masked; iter_max: 1000; lib_dir: /blue/fairbanksj/itaykadosh/central_bench/acados/lib; solver: HPIPM; tolerances: tol_stat = tol_eq = tol_ineq = tol_comp = eps; warm_start: 0; x0: eliminated (stage 0 has nx = 0)
- **mumblebee**: cliquetrees: {"commit":"registry release","path":"/blue/fairbanksj/itaykadosh/julia_depot/packages/CliqueTrees/8e1Ca","version":"1.19.7"}; commit: e78d9b9a3a0a2f4c226bf2eb0cf20f662e7d676b (pinned as in the paper's bench/mpc); package: Mumblebee; path: /blue/fairbanksj/itaykadosh/julia_depot/packages/Mumblebee/NtQeH; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: none (no IPMSymbolic in this version): rebuild redoes the ordering and symbolic factorization; warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **mumblebee_fast**: cliquetrees: {"commit":"registry release","path":"/blue/fairbanksj/itaykadosh/julia_depot/packages/CliqueTrees/8e1Ca","version":"1.19.7"}; commit: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"9416b46f1085901406583675a7257507988c2983"}; package: Mumblebee; path: /blue/fairbanksj/itaykadosh/sheafmpc_bench/refs/a284b72a48/Mumblebee.jl; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: IPMSymbolic built at setup; rebuild strategy reuses it (init(prob, st; symb)); warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **mumblebee_fast_ct**: cliquetrees: {"commit":"0015e2b (itay/fast-symbolic, exported with git archive)","path":"/blue/fairbanksj/itaykadosh/sheafmpc_bench/CliqueTrees-fast-0015e2b","version":"1.19.6"}; commit: {"diff_sha1":"","dirty":false,"dirty_files":[],"sha":"9416b46f1085901406583675a7257507988c2983"}; package: Mumblebee; path: /blue/fairbanksj/itaykadosh/sheafmpc_bench/refs/a284b72a48/Mumblebee.jl; settings: feas_tol = gap_tol = eps, max_iter 200, other IPMSettings defaults; elimination ordering AMF; symbolic_reuse: IPMSymbolic built at setup; rebuild strategy reuses it (init(prob, st; symb)); warm_start: none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!), or, strategy rebuild, a fresh IPMProblem + init per QP inside the clock; the harness keeps the strategy with fewer failures, then the faster. Pinned commit defect: reinit! after a high-accuracy solve can end in NUMERICAL_FAILURE at iteration 1
- **osqp**: library: 0.6.2; package: OSQP.jl; settings: eps_abs = eps_rel = eps, adaptive_rho on with OSQP's default interval 0 (chosen from measured setup time, so iteration counts vary run to run), polish per variant with 3 refinement steps, max_iter 400000, scaling 10 (default); version: 0.8.1; warm_start: setup with warm_start = false (cold); warm mode: update! (factorization kept) + warm_start!(x, y) from the shifted previous solution, which turns warm starting on
- **piqp**: blasfeo: giaf/blasfeo 0a3df8683c6bf9d98168d616e0c5d05938c9d51c (0.1.4.3-91), TARGET=X64_INTEL_HASWELL, static; build_info: PIQP 5d849590a18bc7f0b449057e5f2041713a85003c built on c0702a-s16.ufhpc (AMD EPYC 7702 64-Core Processor), gcc 12.2.0, -O3 -march=native, BLASFEO X64_INTEL_HASWELL static, Eigen 3.4.0, job 46521806
; commit: 5d849590a18bc7f0b449057e5f2041713a85003c; compile_flags: CMAKE_BUILD_TYPE=Release, CMAKE_CXX_FLAGS_RELEASE='-O3 -march=native -DNDEBUG', BUILD_C_INTERFACE=ON, BUILD_SHARED_LIBS=ON, BUILD_WITH_TEMPLATE_INSTANTIATION=OFF, BUILD_WITH_BLASFEO=ON, link '-Wl,--exclude-libs,ALL'; compiler: GCC 13.3.0; eigen: 3.4.0; library: /blue/fairbanksj/itaykadosh/sheafmpc_bench/tools/piqp-install/lib/libpiqpc.so; mapping: l == u rows -> A x = b; single-nonzero rows -> variable bounds (tightest wins); other rows -> h_l <= G x <= h_u; free rows dropped; note: PIQP_LIB overrides the default; build fields describe the default library; package: PIQP (C interface, in-process ccall); python_wheels: piqp 0.6.4, osqp 1.1.3 (~/tools/bench-venv); repo: https://github.com/PREDICT-EPFL/piqp (tag v0.6.4); settings: defaults of piqp_set_default_settings_sparse, then eps_abs = eps_duality_gap_abs = eps, eps_rel = eps_duality_gap_rel = 0, max_iter = 500, verbose off, compute_timings off; version: 0.6.4; warm_start: none (interior point); sequence mode uses piqp_update_sparse with vectors only
- **sheafmpc**: git: {"diff_sha1":"","dirty":false,"dirty_files":[],"ref":"master@638707f5d100129cd82d9480942e8c372018e9ab","sha":"a284b72a4853654c784913141242a75890036400","source":"git archive snapshot (PACKAGE_REF)"}; package: SheafMPC; path: /blue/fairbanksj/itaykadosh/sheafmpc_bench/refs/a284b72a48/SheafMPC.jl; settings: package defaults (SheafMPC.Settings()), eps_abs = eps_rel = eps, max_iter 100000; warm_start: update! (factorization kept, objective constant c passed) + warm_start!(x, y) from the shifted previous solution

Protocol: accuracy tiers low 1e-3, medium 1e-6, high 1e-9 (relative objective error and relative primal residual against the reference, one shared checker on the unscaled problem); tolerance and variant calibrated per solver and instance on the first, middle and last QP; per-QP time is the median over the repeats; warm statistics exclude the first (cold) QP of the sequence. `--` means not applicable, or no QP met the tier. `f/n` = QPs missing the tier.

## chain

### chain, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.32 | 0.192 | 2.50 | 1.62 | 1.74 | 0.706 | 0.555 | 0.262 | 1.37 (hpipm) | 0.16 |

Cold cells: median ms of the solve alone; setup is its own mode.

### chain, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.71 | 0.260 | 3.20 | 2.09 | 2.08 | 0.771 | 0.596 | 0.276 | 1.06 (hpipm) | 0.13 |

Cold cells: median ms of the solve alone; setup is its own mode.

### chain, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.88 | 0.281 | 3.55 | 2.16 | 2.35 | 1.07 | 0.702 | 0.217 | 0.78 (hpipm) | 0.10 |

Cold cells: median ms of the solve alone; setup is its own mode.

### chain, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 0.916 | 0.279 | 5.46 | 1.51 | 1.93 | 0.615 | 0.961 | 2.90 | 10.40 (hpipm) | 1.92 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### chain, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 0.964 | 0.398 | 5.38 | 1.47 | 1.87 | 0.680 | 0.873 | 3.00 | 7.53 (hpipm) | 2.04 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### chain, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.19 | 0.358 | 5.64 | 1.70 | 1.94 | 0.687 | 0.882 | 2.69 | 7.50 (hpipm) | 1.58 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### chain, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 2.24 | 0.471 | 7.96 | 3.10 | 3.67 | 1.34 | 1.48 | 3.17 | 6.74 (hpipm) | 1.02 |

Setup + solve cells: median ms of a cold setup plus its solve.

### chain, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 2.69 | 0.657 | 8.56 | 3.56 | 3.95 | 1.44 | 1.42 | 3.24 | 4.93 (hpipm) | 0.91 |

Setup + solve cells: median ms of a cold setup plus its solve.

### chain, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 3.13 | 0.630 | 9.22 | 3.86 | 4.37 | 1.77 | 1.53 | 2.90 | 4.60 (hpipm) | 0.75 |

Setup + solve cells: median ms of a cold setup plus its solve.

### chain, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.24 (1.41) | 0.177 (0.266) | 2.04 (2.10) | 1.28 (1.28) | 1.33 (1.52) | 0.662 (0.724) [1/5] | 0.430 (0.532) | 0.090 (0.130) | 0.51 (hpipm) | 0.07 |

Warm cells: median (max) ms of update + warm start + solve.

### chain, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.73 (1.91) | 0.240 (0.321) | 2.87 (2.94) | 1.89 (1.93) | 1.75 (1.78) | 0.817 (1.06) | 0.570 (0.638) | 0.151 (0.177) | 0.63 (hpipm) | 0.08 |

Warm cells: median (max) ms of update + warm start + solve.

### chain, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 220 | 1.98 (2.36) | 0.278 (0.383) | 8.72 (9.05) | 2.17 (2.35) | 2.12 (2.54) | 1.05 (1.19) | 0.730 (0.847) | 0.106 (0.121) | 0.38 (hpipm) | 0.05 |

Warm cells: median (max) ms of update + warm start + solve.

### chain, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 50 / 50 / -- / 75 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |

### chain, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 50 / 50 / -- / 75 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |

### chain, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M4 | 0.964 | 0.398 | 5.38 | 1.47 | 1.87 | 0.680 | 0.873 | 3.00 |

## fleet_ring_box

### fleet_ring_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.385 | 0.149 | 1.12 | 0.932 | 0.679 | 0.299 [1/5] | 0.172 | 0.094 | 0.63 (hpipm) | 0.10 |
| fleet_ring_box_n4 | 560 | 2.31 | 0.745 | 4.92 | 3.89 | 3.57 | 1.40 [1/5] | 0.851 [1/5] | 1.14 | 1.53 (hpipm) | 0.29 |
| fleet_ring_box_n16 | 2240 | 15.14 | 10.24 [1/5] | 22.33 | 16.78 | 16.51 | 13.58 | 6.81 | 7.71 | 1.13 (piqp) | 0.46 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.472 | 0.147 | 1.35 | 0.972 | 0.841 | 0.536 | 0.197 | 0.059 | 0.40 (hpipm) | 0.06 |
| fleet_ring_box_n4 | 560 | 2.95 | 0.944 | 6.11 | 4.73 | 4.33 | 4.93 | 1.19 | 1.35 | 1.43 (hpipm) | 0.28 |
| fleet_ring_box_n16 | 2240 | 20.57 | 13.52 | 29.61 | 22.45 | 21.35 | 30.55 | 9.21 | 7.48 | 0.81 (piqp) | 0.33 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.611 | 0.208 | 1.67 | 1.26 | 0.989 | 0.872 | 0.207 | 0.067 | 0.32 (piqp) | 0.05 |
| fleet_ring_box_n4 | 560 | 3.54 | 0.975 | 7.38 | 5.46 | 5.12 | 9.97 | 1.38 | 1.33 | 1.36 (hpipm) | 0.24 |
| fleet_ring_box_n16 | 2240 | 24.44 | 15.71 [1/5] | 37.55 | 26.38 | 24.23 | 57.89 | 10.92 | 7.49 | 0.69 (piqp) | 0.28 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.463 | 0.246 | 1.07 | 0.794 | 0.769 | 0.192 [1/5] | 0.382 | 0.741 | 3.01 (hpipm) | 0.93 |
| fleet_ring_box_n4 | 560 | 1.48 | 0.380 | 2.72 | 2.38 | 2.25 | 0.870 [1/5] | 0.763 [1/5] | 2.64 | 6.95 (hpipm) | 1.11 |
| fleet_ring_box_n16 | 2240 | 5.14 | 3.07 [1/5] | 10.82 | 6.67 | 7.36 | 3.70 | 2.15 | 11.49 | 5.34 (piqp) | 1.72 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.414 | 0.359 | 1.00 | 0.383 | 0.836 | 0.183 | 0.383 | 0.672 | 3.68 (osqp) | 1.76 |
| fleet_ring_box_n4 | 560 | 1.37 | 0.495 | 2.82 | 2.31 | 2.49 | 0.912 | 0.746 | 2.81 | 5.68 (hpipm) | 1.22 |
| fleet_ring_box_n16 | 2240 | 5.15 | 2.86 | 10.93 | 6.86 | 6.45 | 3.73 | 2.33 | 10.90 | 4.68 (piqp) | 1.59 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.513 | 0.437 | 0.996 | 0.603 | 0.849 | 0.195 | 0.337 | 0.653 | 3.34 (osqp) | 1.08 |
| fleet_ring_box_n4 | 560 | 1.61 | 0.747 | 3.13 | 2.35 | 2.15 | 0.938 | 0.870 | 3.00 | 4.02 (hpipm) | 1.28 |
| fleet_ring_box_n16 | 2240 | 4.81 | 4.63 [1/5] | 11.64 | 6.81 | 6.70 | 3.62 | 2.30 | 11.73 | 5.10 (piqp) | 1.72 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.848 | 0.395 | 2.13 | 1.73 | 1.45 | 0.504 [1/5] | 0.571 | 0.850 | 2.15 (hpipm) | 0.49 |
| fleet_ring_box_n4 | 560 | 3.79 | 1.09 | 7.63 | 6.25 | 5.83 | 2.30 [1/5] | 1.62 [1/5] | 3.71 | 3.40 (hpipm) | 0.59 |
| fleet_ring_box_n16 | 2240 | 19.87 | 14.09 [1/5] | 33.08 | 23.59 | 23.75 | 17.35 | 8.94 | 18.81 | 2.10 (piqp) | 0.80 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.887 | 0.503 | 2.40 | 1.35 | 1.71 | 0.705 | 0.579 | 0.725 | 1.44 (hpipm) | 0.54 |
| fleet_ring_box_n4 | 560 | 4.28 | 1.45 | 8.98 | 7.12 | 6.85 | 5.78 | 1.94 | 4.18 | 2.87 (hpipm) | 0.59 |
| fleet_ring_box_n16 | 2240 | 25.90 | 16.21 | 40.50 | 29.03 | 27.66 | 34.05 | 11.48 | 18.51 | 1.61 (piqp) | 0.64 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 1.08 | 0.721 | 2.77 | 1.86 | 1.84 | 1.07 | 0.544 | 0.758 | 1.39 (piqp) | 0.41 |
| fleet_ring_box_n4 | 560 | 5.15 | 1.62 | 10.50 | 7.81 | 7.30 | 10.91 | 2.20 | 4.33 | 2.68 (hpipm) | 0.55 |
| fleet_ring_box_n16 | 2240 | 29.58 | 20.33 [1/5] | 49.17 | 33.28 | 31.03 | 61.36 | 13.05 | 18.77 | 1.44 (piqp) | 0.56 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.336 (0.410) | 0.094 (0.137) | 1.14 (1.34) | 0.919 (1.11) | 0.726 (0.850) | 0.133 (0.163) | 0.166 (0.214) | 0.032 (0.082) | 0.34 (hpipm) | 0.03 |
| fleet_ring_box_n4 | 560 | 2.21 (2.45) | 0.598 (0.698) | 4.91 (5.51) | 3.83 (4.08) | 3.38 (3.72) | 1.24 (1.76) [1/5] | 0.843 (0.879) [1/5] | 0.650 (1.34) | 1.09 (hpipm) | 0.17 |
| fleet_ring_box_n16 | 2240 | 15.59 (17.40) | 9.91 (11.40) [1/5] | 22.54 (24.81) | 16.89 (18.97) | 15.81 (17.72) | 11.17 (11.19) | 7.21 (7.84) | 7.35 (11.66) | 1.02 (piqp) | 0.44 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.481 (0.517) | 0.200 (0.242) | 1.33 (1.48) | 0.989 (1.13) | 0.793 (0.955) | 0.261 (0.668) [2/5] | 0.159 (0.178) | 0.036 (0.051) | 0.23 (piqp) | 0.04 |
| fleet_ring_box_n4 | 560 | 2.89 (3.20) | 1.01 (1.09) | 6.14 (6.67) | 4.70 (4.97) | 4.34 (4.65) | 4.76 (6.05) | 1.19 (1.20) | 0.940 (1.52) | 0.93 (hpipm) | 0.20 |
| fleet_ring_box_n16 | 2240 | 20.28 (20.72) | 14.07 (15.40) | 30.73 (33.67) | 23.36 (25.58) | 20.66 (22.30) | 25.20 (30.43) | 9.17 (10.05) | 8.19 (11.99) | 0.89 (piqp) | 0.35 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.534 (0.690) | 0.246 (0.258) | 1.66 (1.81) | 1.39 (1.69) | 0.984 (1.09) | 1.25 (1.41) | 0.207 (0.236) | 0.040 (0.059) | 0.20 (piqp) | 0.03 |
| fleet_ring_box_n4 | 560 | 3.57 (4.01) | 0.720 (0.783) | 7.26 (7.50) | 5.62 (5.68) | 4.94 (4.99) | 6.58 (9.11) | 1.28 (1.33) | 1.01 (1.67) | 1.41 (hpipm) | 0.18 |
| fleet_ring_box_n16 | 2240 | 24.30 (24.52) | 14.23 (14.77) [1/5] | 37.31 (37.66) | 26.48 (27.19) | 24.69 (24.88) | 43.88 (112) | 10.77 (11.13) | 8.00 (11.83) | 0.74 (piqp) | 0.30 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 4 / 6 / -- / 7 | 5 / 6 / -- / 7 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 75 / 125 / -- / 175 | 4 / 5 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_ring_box_n4 | 6 / 8 / -- / 10 | 7 / 9 / -- / 10 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 50 / 200 / -- / 450 | 6 / 8 / -- / 10 | 50 / 50 / -- / 50 |
| fleet_ring_box_n16 | 7 / 10 / -- / 12 | 7 / 10 / -- / 12 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 125 / 250 / -- / 500 | 7 / 10 / -- / 12 | 60 / 60 / -- / 60 |

### fleet_ring_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 4 / 6 / -- / 7 | 5 / 6 / -- / 7 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 25 / 100 / -- / 275 | 4 / 5 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_ring_box_n4 | 6 / 8 / -- / 10 | 7 / 9 / -- / 10 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 50 / 200 / -- / 275 | 6 / 8 / -- / 10 | 30 / 30 / -- / 30 |
| fleet_ring_box_n16 | 7 / 10 / -- / 12 | 7 / 10 / -- / 12 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 9 / 12 / -- / 14 | 100 / 200 / -- / 350 | 8 / 10 / -- / 12 | 50 / 50 / -- / 50 |

### fleet_ring_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 0.414 | 0.359 | 1.00 | 0.383 | 0.836 | 0.183 | 0.383 | 0.672 |
| fleet_ring_box_n4 | 1.37 | 0.495 | 2.82 | 2.31 | 2.49 | 0.912 | 0.746 | 2.81 |
| fleet_ring_box_n16 | 5.15 | 2.86 | 10.93 | 6.86 | 6.45 | 3.73 | 2.33 | 10.90 |

## fleet_ring_box_b4

### fleet_ring_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.95 | 4.62 | 3.08 | 3.10 | 1.35 | 0.822 [1/5] | 0.767 | 0.57 (osqp) | 0.25 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.41 | 6.16 | 3.70 | 3.80 | 3.87 | 1.01 | 0.850 | 0.84 (piqp) | 0.23 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.73 | 7.29 | 4.29 | 3.75 | 6.78 | 1.10 | 0.865 | 0.78 (piqp) | 0.20 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box_b4, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.25 | 3.15 | 2.28 | 2.49 | 0.743 | 0.793 [1/5] | 3.36 | 4.53 (osqp) | 1.47 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box_b4, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.31 | 3.48 | 2.11 | 2.39 | 0.795 | 0.871 | 3.43 | 4.31 (osqp) | 1.62 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box_b4, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.27 | 3.35 | 2.27 | 1.33 | 0.861 | 0.546 | 3.42 | 6.27 (piqp) | 1.51 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box_b4, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 3.12 | 7.77 | 5.37 | 5.90 | 2.12 | 1.61 [1/5] | 4.09 | 1.93 (osqp) | 0.76 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box_b4, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 3.76 | 9.91 | 5.89 | 6.29 | 4.59 | 1.89 | 4.28 | 2.27 (piqp) | 0.73 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box_b4, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 3.90 | 10.66 | 6.63 | 5.08 | 7.65 | 1.59 | 4.28 | 2.69 (piqp) | 0.65 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 1.88 (1.97) | 4.46 (4.95) | 2.93 (3.37) | 2.98 (3.08) | 1.04 (1.39) [1/5] | 0.901 (0.946) [1/5] | 0.763 (1.60) | 0.41 (clarabel) | 0.26 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.27 (2.45) | 6.10 (6.54) | 3.41 (3.71) | 3.14 (3.42) | 2.65 (3.57) [1/5] | 0.918 (0.988) | 0.766 (1.66) | 0.83 (piqp) | 0.22 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 272 | 2.72 (2.84) | 6.92 (7.10) | 4.04 (4.27) | 3.77 (3.77) | 4.61 (6.66) | 1.03 (1.13) | 0.701 (1.61) | 0.68 (piqp) | 0.17 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 100 / 300 / -- / 525 | 6 / 8 / -- / 9 | 20 / 20 / -- / 20 |

### fleet_ring_box_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 75 / 175 / -- / 350 | 6 / 8 / -- / 9 | 50 / 50 / -- / 50 |

### fleet_ring_box_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n4 | 1.31 | 3.48 | 2.11 | 2.39 | 0.795 | 0.871 | 3.43 |

## fleet_ring_soc

### fleet_ring_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.50 | 5.12 | 4.68 | 4.13 | 2.21 | 0.63 (clarabel) | 0.47 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 4.71 | 7.27 | 6.74 | 5.75 | 2.56 | 0.54 (clarabel) | 0.38 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 5.57 | 7.99 | 7.37 | 6.49 | 2.95 | 0.53 (clarabel) | 0.40 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 6.17 | 8.87 | 8.07 | 6.92 | 2.88 | 0.47 (clarabel) | 0.36 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 1.76 | 3.04 | 2.33 | 2.45 | 4.76 | 2.71 (clarabel) | 2.04 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 1.68 | 3.14 | 2.49 | 2.46 | 4.75 | 2.84 (clarabel) | 1.91 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 1.81 | 3.32 | 2.62 | 2.48 | 4.68 | 2.59 (clarabel) | 1.79 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 1.92 | 3.17 | 2.34 | 2.45 | 5.10 | 2.66 (clarabel) | 2.18 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 5.33 | 8.27 | 7.08 | 6.55 | 6.76 | 1.27 (clarabel) | 0.96 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 6.62 | 10.40 | 9.05 | 8.33 | 7.26 | 1.10 (clarabel) | 0.80 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 7.34 | 11.48 | 10.19 | 8.88 | 7.74 | 1.05 (clarabel) | 0.76 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 8.09 | 12.06 | 10.58 | 9.38 | 7.93 | 0.98 (clarabel) | 0.75 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 3.29 (3.71) | 4.90 (5.71) | 4.45 (5.14) | 3.76 (4.50) | 2.13 (4.37) | 0.65 (clarabel) | 0.48 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 4.52 (5.18) | 7.11 (8.10) | 6.50 (6.95) | 5.43 (5.88) | 2.11 (4.94) | 0.47 (clarabel) | 0.32 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 5.51 (5.63) | 8.42 (8.70) | 7.67 (7.86) | 6.51 (6.74) | 2.50 (4.82) | 0.45 (clarabel) | 0.33 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n4 | 560 | 6.05 (6.26) | 9.01 (9.47) | 8.35 (8.56) | 7.16 (7.34) | 2.75 (4.73) | 0.45 (clarabel) | 0.33 |

Warm cells: median (max) ms of update + warm start + solve.

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
| fleet_ring_soc_n4 | 1.68 | 3.14 | 2.49 | 2.46 | 4.75 |

## osqprand

### osqprand, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 4.33 | 0.406 | 6.52 | 3.79 | 3.54 | 4.59 | 2.47 | 0.798 | 1.97 (hpipm) | 0.21 |

Cold cells: median ms of the solve alone; setup is its own mode.

### osqprand, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 4.95 | 0.736 | 7.29 | 4.19 | 4.09 | 8.65 | 3.31 | 0.939 | 1.28 (hpipm) | 0.22 |

Cold cells: median ms of the solve alone; setup is its own mode.

### osqprand, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 5.99 | 0.684 [1/5] | 9.16 | 5.04 | 5.14 | 12.70 | 3.53 | 0.604 | 0.17 (piqp) | 0.12 |

Cold cells: median ms of the solve alone; setup is its own mode.

### osqprand, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.26 | 0.387 | 38.98 | 6.18 | 6.02 | 1.33 | 1.39 | 8.19 | 21.16 (hpipm) | 1.33 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### osqprand, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.21 | 0.488 | 36.62 | 6.27 | 6.15 | 1.35 | 1.32 | 8.14 | 16.67 (hpipm) | 1.30 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### osqprand, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 2.26 | 0.483 [1/5] | 36.20 | 6.28 | 6.16 | 1.61 | 1.36 | 6.21 | 4.58 (piqp) | 0.99 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### osqprand, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 6.64 | 0.802 | 45.51 | 9.97 | 9.98 | 5.93 | 3.90 | 8.93 | 11.14 (hpipm) | 0.90 |

Setup + solve cells: median ms of a cold setup plus its solve.

### osqprand, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 7.16 | 1.18 | 43.89 | 10.46 | 10.25 | 10.00 | 4.63 | 9.06 | 7.67 (hpipm) | 0.87 |

Setup + solve cells: median ms of a cold setup plus its solve.

### osqprand, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 8.22 | 1.14 [1/5] | 45.42 | 11.25 | 11.35 | 14.36 | 4.95 | 6.91 | 1.40 (piqp) | 0.61 |

Setup + solve cells: median ms of a cold setup plus its solve.

### osqprand, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 4.18 (4.31) | 0.394 (0.430) | 6.11 (6.23) | 3.50 (3.56) | 3.36 (3.45) | 2.65 (2.68) | 2.35 (2.78) | 0.334 (0.446) | 0.85 (hpipm) | 0.10 |

Warm cells: median (max) ms of update + warm start + solve.

### osqprand, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 5.19 (5.38) | 0.551 (0.600) | 7.04 (7.11) | 3.97 (4.00) | 3.98 (4.14) | 8.84 (19.68) | 3.13 (3.22) | 0.220 (0.257) | 0.40 (hpipm) | 0.06 |

Warm cells: median (max) ms of update + warm start + solve.

### osqprand, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 320 | 5.98 (6.16) | 0.571 (0.587) [1/5] | 44.99 (45.37) | 4.74 (4.90) | 4.89 (5.09) | 26.50 (27.54) | 3.44 (3.64) | 0.193 (0.199) | 0.06 (piqp) | 0.04 |

Warm cells: median (max) ms of update + warm start + solve.

### osqprand, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 6 / 7 / -- / 9 | 5 / 7 / -- / 7 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 100 / 225 / -- / 300 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |

### osqprand, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 6 / 8 / -- / 9 | 5 / 7 / -- / 7 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 7 / 8 / -- / 10 | 50 / 200 / -- / 800 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |

### osqprand, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx20_s1 | 2.21 | 0.488 | 36.62 | 6.27 | 6.15 | 1.35 | 1.32 | 8.14 |

## reduced

### reduced, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 20.04 | 15.30 | 14.84 | 13.09 | 6.38 | 0.49 (mumblebee_fast_ct) | 0.43 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 24.37 | 20.51 | 18.75 | 16.87 | 6.45 | 0.38 (mumblebee_fast_ct) | 0.34 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 29.84 | 25.30 | 22.89 | 21.00 | 6.77 | 0.32 (mumblebee_fast_ct) | 0.30 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 31.63 | 30.35 | 27.58 | 19.88 | 6.75 | 0.34 (mumblebee_fast_ct) | 0.24 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 13.07 | 22.36 | 15.25 | 16.08 | 32.53 | 2.49 (clarabel) | 2.13 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 13.24 | 23.25 | 14.69 | 15.48 | 33.38 | 2.52 (clarabel) | 2.27 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 14.63 | 22.84 | 15.25 | 14.50 | 34.51 | 2.38 (mumblebee_fast_ct) | 2.26 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 12.50 | 23.07 | 15.16 | 11.15 | 31.97 | 2.87 (mumblebee_fast_ct) | 2.11 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 33.11 | 37.66 | 30.06 | 28.92 | 39.09 | 1.35 (mumblebee_fast_ct) | 1.30 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 37.60 | 43.48 | 33.09 | 32.54 | 40.02 | 1.23 (mumblebee_fast_ct) | 1.21 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 43.88 | 48.88 | 38.12 | 35.31 | 41.15 | 1.17 (mumblebee_fast_ct) | 1.08 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 44.42 | 53.66 | 42.79 | 30.95 | 38.72 | 1.25 (mumblebee_fast_ct) | 0.90 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 19.27 (20.69) | 15.56 (15.90) | 14.24 (14.62) | 12.64 (12.76) | 1.23 (1.86) | 0.10 (mumblebee_fast_ct) | 0.09 |

Warm cells: median (max) ms of update + warm start + solve.

### reduced, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 23.37 (24.46) | 20.30 (20.58) | 18.35 (19.17) | 16.40 (16.45) | 1.25 (1.39) | 0.08 (mumblebee_fast_ct) | 0.07 |

Warm cells: median (max) ms of update + warm start + solve.

### reduced, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 30.91 (31.51) | 24.94 (25.12) | 22.93 (23.11) | 20.42 (20.55) | 1.41 (1.46) | 0.07 (mumblebee_fast_ct) | 0.06 |

Warm cells: median (max) ms of update + warm start + solve.

### reduced, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 33.79 (35.58) | 29.29 (29.63) | 27.74 (28.47) | 20.02 (22.12) | 1.41 (1.55) | 0.07 (mumblebee_fast_ct) | 0.05 |

Warm cells: median (max) ms of update + warm start + solve.

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
| reduced_k8 | 13.24 | 23.25 | 14.69 | 15.48 | 33.38 |

## single_di_box

### single_di_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.667 | 0.293 | 1.43 | 1.000 | 0.829 | 0.198 | 0.206 | 0.118 | 0.60 (osqp) | 0.12 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.838 | 0.336 | 2.24 | 1.76 | 1.42 | 0.387 | 0.300 | 0.099 | 0.33 (piqp) | 0.06 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 1.15 | 0.229 | 3.13 | 2.41 | 1.88 | 0.488 | 0.312 | 0.114 | 0.50 (hpipm) | 0.05 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_box, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.748 | 0.400 | 1.30 | 1.12 | 1.09 | 0.381 | 0.351 | 1.27 | 3.64 (piqp) | 1.14 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_box, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.434 | 0.524 | 1.50 | 1.06 | 1.16 | 0.445 | 0.346 | 1.22 | 3.53 (piqp) | 1.15 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_box, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.883 | 0.242 | 1.77 | 1.15 | 1.08 | 0.214 | 0.363 | 1.37 | 6.41 (osqp) | 1.20 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_box, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 1.41 | 0.678 | 2.72 | 2.13 | 1.92 | 0.577 | 0.585 | 1.40 | 2.43 (osqp) | 0.66 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_box, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 1.27 | 0.872 | 3.70 | 2.82 | 2.58 | 0.840 | 0.646 | 1.31 | 2.02 (piqp) | 0.46 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_box, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 2.12 | 0.433 | 4.90 | 3.54 | 2.96 | 0.701 | 0.663 | 1.49 | 3.44 (hpipm) | 0.42 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.771 (0.877) | 0.163 (0.300) | 1.34 (1.38) | 1.11 (1.26) | 0.888 (0.947) | 0.211 (0.221) | 0.211 (0.276) | 0.054 (0.076) | 0.33 (hpipm) | 0.05 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 0.804 (0.831) | 0.177 (0.184) | 2.23 (2.32) | 1.70 (1.79) | 1.39 (1.44) | 0.331 (0.335) | 0.249 (0.280) | 0.058 (0.059) | 0.33 (hpipm) | 0.03 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 180 | 1.08 (1.12) | 0.238 (0.308) | 4.40 (4.57) | 2.21 (2.38) | 1.75 (1.91) | 0.349 (0.523) | 0.360 (0.428) | 0.061 (0.132) | 0.26 (hpipm) | 0.03 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 5 / 8 / -- / 10 | 4 / 7 / -- / 9 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |

### single_di_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 5 / 8 / -- / 10 | 4 / 7 / -- / 9 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 5 / 8 / -- / 11 | 25 / 50 / -- / 50 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |

### single_di_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N20 | 0.434 | 0.524 | 1.50 | 1.06 | 1.16 | 0.445 | 0.346 | 1.22 |

## single_quad

### single_quad, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.59 | 0.221 | 2.52 | 1.81 | 1.79 | 0.487 | 0.595 | 0.182 | 0.82 (hpipm) | 0.10 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_quad, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.99 | 0.347 | 3.44 | 2.53 | 2.41 | 0.951 | 0.695 | 0.251 | 0.72 (hpipm) | 0.10 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_quad, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 2.33 | 0.398 | 3.97 | 3.03 | 2.78 | 1.27 | 0.784 | 0.318 | 0.80 (hpipm) | 0.10 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_quad, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.14 | 0.363 | 3.75 | 2.07 | 2.16 | 0.652 | 0.884 | 3.35 | 9.22 (hpipm) | 1.62 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_quad, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.25 | 0.427 | 3.75 | 2.08 | 2.05 | 0.698 | 0.925 | 3.37 | 7.89 (hpipm) | 1.62 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_quad, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.30 | 0.507 | 3.83 | 2.42 | 2.28 | 0.787 | 0.955 | 3.80 | 7.49 (hpipm) | 1.57 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_quad, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 2.75 | 0.567 | 6.24 | 3.88 | 3.96 | 1.10 | 1.48 | 3.59 | 6.34 (hpipm) | 0.93 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_quad, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 3.19 | 0.759 | 7.13 | 4.50 | 4.47 | 1.65 | 1.61 | 3.68 | 4.85 (hpipm) | 0.82 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_quad, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 3.69 | 0.917 | 7.71 | 5.51 | 5.01 | 2.06 | 1.78 | 4.11 | 4.48 (hpipm) | 0.75 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_quad, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.49 (1.50) | 0.224 (0.367) | 2.19 (2.37) | 1.60 (1.66) | 1.53 (1.75) | 0.459 (0.474) | 0.529 (0.612) | 0.109 (0.223) | 0.48 (hpipm) | 0.07 |

Warm cells: median (max) ms of update + warm start + solve.

### single_quad, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 1.85 (2.02) | 0.245 (0.341) | 3.07 (3.20) | 2.35 (2.64) | 2.19 (2.37) | 0.882 (0.906) | 0.656 (0.816) | 0.156 (0.194) | 0.64 (hpipm) | 0.07 |

Warm cells: median (max) ms of update + warm start + solve.

### single_quad, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 320 | 2.07 (2.27) | 0.318 (0.366) | 3.60 (4.24) | 2.87 (3.32) | 2.59 (2.78) | 1.04 (1.36) [1/5] | 0.763 (0.892) | 0.097 (0.112) | 0.30 (hpipm) | 0.03 |

Warm cells: median (max) ms of update + warm start + solve.

### single_quad, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |

### single_quad, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 5 / 7 / -- / 8 | 4 / 5 / -- / 6 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 50 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |

### single_quad, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N20 | 1.25 | 0.427 | 3.75 | 2.08 | 2.05 | 0.698 | 0.925 | 3.37 |

## Shifted geometric means (ms; shift 0.1 ms; failures charged the time limit) and failure rates

### cold, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.31 (0% fail) | 0.194 (0% fail) | 2.49 (0% fail) | 1.62 (0% fail) | 1.69 (0% fail) | 0.714 (0% fail) | 0.551 (0% fail) | 0.251 (0% fail) |
| fleet_ring_box | 2.53 (0% fail) | 2.57 (7% fail) | 5.13 (0% fail) | 4.02 (0% fail) | 3.54 (0% fail) | 12.14 (13% fail) | 2.88 (7% fail) | 1.10 (0% fail) |
| fleet_ring_box_b4 | 1.93 (0% fail) | -- | 4.54 (0% fail) | 3.05 (0% fail) | 3.15 (0% fail) | 1.21 (0% fail) | 13.38 (20% fail) | 0.770 (0% fail) |
| fleet_ring_soc | 3.62 (0% fail) | -- | 5.22 (0% fail) | 4.76 (0% fail) | 4.19 (0% fail) | -- | -- | 2.44 (0% fail) |
| osqprand | 4.32 (0% fail) | 0.400 (0% fail) | 6.59 (0% fail) | 3.67 (0% fail) | 3.61 (0% fail) | 4.57 (0% fail) | 2.53 (0% fail) | 0.816 (0% fail) |
| reduced | 20.09 (0% fail) | -- | 15.23 (0% fail) | 14.84 (0% fail) | 12.95 (0% fail) | -- | -- | 6.51 (0% fail) |
| single_di_box | 0.658 (0% fail) | 0.278 (0% fail) | 1.39 (0% fail) | 0.986 (0% fail) | 0.834 (0% fail) | 0.192 (0% fail) | 0.214 (0% fail) | 0.115 (0% fail) |
| single_quad | 1.58 (0% fail) | 0.234 (0% fail) | 2.48 (0% fail) | 1.79 (0% fail) | 1.81 (0% fail) | 0.483 (0% fail) | 0.595 (0% fail) | 0.186 (0% fail) |
| all | 2.62 (0% fail) | -- | 4.42 (0% fail) | 3.31 (0% fail) | 3.07 (0% fail) | -- | -- | 0.832 (0% fail) |

### cold, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.72 (0% fail) | 0.276 (0% fail) | 3.20 (0% fail) | 2.09 (0% fail) | 2.06 (0% fail) | 0.856 (0% fail) | 0.576 (0% fail) | 0.281 (0% fail) |
| fleet_ring_box | 3.18 (0% fail) | 1.48 (0% fail) | 6.32 (0% fail) | 4.70 (0% fail) | 4.42 (0% fail) | 4.26 (0% fail) | 1.41 (0% fail) | 1.15 (0% fail) |
| fleet_ring_box_b4 | 2.41 (0% fail) | -- | 6.25 (0% fail) | 3.75 (0% fail) | 3.85 (0% fail) | 4.46 (0% fail) | 1.03 (0% fail) | 0.816 (0% fail) |
| fleet_ring_soc | 4.69 (0% fail) | -- | 7.19 (0% fail) | 6.65 (0% fail) | 5.63 (0% fail) | -- | -- | 2.85 (0% fail) |
| osqprand | 5.07 (0% fail) | 0.723 (0% fail) | 7.27 (0% fail) | 4.19 (0% fail) | 4.10 (0% fail) | 8.56 (0% fail) | 3.32 (0% fail) | 0.974 (0% fail) |
| reduced | 24.39 (0% fail) | -- | 20.41 (0% fail) | 18.65 (0% fail) | 16.92 (0% fail) | -- | -- | 6.54 (0% fail) |
| single_di_box | 0.867 (0% fail) | 0.298 (0% fail) | 2.28 (0% fail) | 1.73 (0% fail) | 1.44 (0% fail) | 0.386 (0% fail) | 0.297 (0% fail) | 0.095 (0% fail) |
| single_quad | 1.94 (0% fail) | 0.332 (0% fail) | 3.40 (0% fail) | 2.48 (0% fail) | 2.43 (0% fail) | 0.951 (0% fail) | 0.686 (0% fail) | 0.253 (0% fail) |
| all | 3.28 (0% fail) | -- | 5.80 (0% fail) | 4.24 (0% fail) | 3.97 (0% fail) | -- | -- | 0.899 (0% fail) |

### cold, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 5.57 (0% fail) | -- | 8.22 (0% fail) | 7.61 (0% fail) | 6.49 (0% fail) | -- | -- | 3.08 (0% fail) |
| reduced | 29.36 (0% fail) | -- | 25.75 (0% fail) | 23.00 (0% fail) | 21.24 (0% fail) | -- | -- | 6.75 (0% fail) |
| all | 12.83 (0% fail) | -- | 14.57 (0% fail) | 13.24 (0% fail) | 11.76 (0% fail) | -- | -- | 4.57 (0% fail) |

### cold, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.04 (0% fail) | 0.290 (0% fail) | 3.69 (0% fail) | 2.26 (0% fail) | 2.43 (0% fail) | 1.09 (0% fail) | 0.684 (0% fail) | 0.227 (0% fail) |
| fleet_ring_box | 3.86 (0% fail) | 3.44 (7% fail) | 7.71 (0% fail) | 5.73 (0% fail) | 5.04 (0% fail) | 8.04 (0% fail) | 1.61 (0% fail) | 1.15 (0% fail) |
| fleet_ring_box_b4 | 2.69 (0% fail) | -- | 7.26 (0% fail) | 4.24 (0% fail) | 3.74 (0% fail) | 8.07 (0% fail) | 1.10 (0% fail) | 0.885 (0% fail) |
| fleet_ring_soc | 6.26 (0% fail) | -- | 8.99 (0% fail) | 8.27 (0% fail) | 7.03 (0% fail) | -- | -- | 3.10 (0% fail) |
| osqprand | 5.98 (0% fail) | 11.35 (20% fail) | 9.15 (0% fail) | 5.11 (0% fail) | 5.12 (0% fail) | 13.56 (0% fail) | 3.57 (0% fail) | 0.639 (0% fail) |
| reduced | 31.93 (0% fail) | -- | 30.59 (0% fail) | 27.58 (0% fail) | 19.92 (0% fail) | -- | -- | 6.77 (0% fail) |
| single_di_box | 1.16 (0% fail) | 0.239 (0% fail) | 3.10 (0% fail) | 2.36 (0% fail) | 1.85 (0% fail) | 0.497 (0% fail) | 0.324 (0% fail) | 0.111 (0% fail) |
| single_quad | 2.33 (0% fail) | 0.393 (0% fail) | 3.99 (0% fail) | 3.05 (0% fail) | 2.79 (0% fail) | 1.30 (0% fail) | 0.799 (0% fail) | 0.336 (0% fail) |
| all | 4.02 (0% fail) | -- | 7.23 (0% fail) | 5.24 (0% fail) | 4.62 (0% fail) | -- | -- | 0.893 (0% fail) |

### setup, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.902 (0% fail) | 0.279 (0% fail) | 5.56 (0% fail) | 1.49 (0% fail) | 1.92 (0% fail) | 0.599 (0% fail) | 0.894 (0% fail) | 2.78 (0% fail) |
| fleet_ring_box | 1.53 (0% fail) | 1.80 (7% fail) | 3.34 (0% fail) | 2.33 (0% fail) | 2.45 (0% fail) | 6.72 (13% fail) | 2.30 (7% fail) | 2.99 (0% fail) |
| fleet_ring_box_b4 | 1.20 (0% fail) | -- | 3.11 (0% fail) | 2.27 (0% fail) | 2.53 (0% fail) | 0.757 (0% fail) | 12.85 (20% fail) | 3.36 (0% fail) |
| fleet_ring_soc | 1.77 (0% fail) | -- | 3.06 (0% fail) | 2.40 (0% fail) | 2.43 (0% fail) | -- | -- | 4.79 (0% fail) |
| osqprand | 2.24 (0% fail) | 0.405 (0% fail) | 39.02 (0% fail) | 6.27 (0% fail) | 6.18 (0% fail) | 1.33 (0% fail) | 1.36 (0% fail) | 8.45 (0% fail) |
| reduced | 13.10 (0% fail) | -- | 22.49 (0% fail) | 15.44 (0% fail) | 16.05 (0% fail) | -- | -- | 32.39 (0% fail) |
| single_di_box | 0.713 (0% fail) | 0.382 (0% fail) | 1.43 (0% fail) | 1.13 (0% fail) | 1.12 (0% fail) | 0.371 (0% fail) | 0.293 (0% fail) | 1.28 (0% fail) |
| single_quad | 1.17 (0% fail) | 0.375 (0% fail) | 3.71 (0% fail) | 2.07 (0% fail) | 2.11 (0% fail) | 0.651 (0% fail) | 0.936 (0% fail) | 3.19 (0% fail) |
| all | 1.69 (0% fail) | -- | 5.00 (0% fail) | 2.75 (0% fail) | 2.91 (0% fail) | -- | -- | 4.13 (0% fail) |

### setup, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.988 (0% fail) | 0.419 (0% fail) | 5.33 (0% fail) | 1.46 (0% fail) | 1.81 (0% fail) | 0.684 (0% fail) | 0.860 (0% fail) | 2.93 (0% fail) |
| fleet_ring_box | 1.50 (0% fail) | 0.841 (0% fail) | 3.17 (0% fail) | 1.93 (0% fail) | 2.37 (0% fail) | 0.954 (0% fail) | 0.905 (0% fail) | 2.85 (0% fail) |
| fleet_ring_box_b4 | 1.29 (0% fail) | -- | 3.63 (0% fail) | 2.09 (0% fail) | 2.40 (0% fail) | 0.793 (0% fail) | 0.881 (0% fail) | 3.43 (0% fail) |
| fleet_ring_soc | 1.81 (0% fail) | -- | 3.24 (0% fail) | 2.44 (0% fail) | 2.54 (0% fail) | -- | -- | 4.74 (0% fail) |
| osqprand | 2.22 (0% fail) | 0.460 (0% fail) | 36.75 (0% fail) | 6.29 (0% fail) | 6.21 (0% fail) | 1.39 (0% fail) | 1.40 (0% fail) | 8.30 (0% fail) |
| reduced | 13.10 (0% fail) | -- | 23.43 (0% fail) | 14.61 (0% fail) | 15.66 (0% fail) | -- | -- | 33.37 (0% fail) |
| single_di_box | 0.534 (0% fail) | 0.405 (0% fail) | 1.43 (0% fail) | 1.06 (0% fail) | 1.16 (0% fail) | 0.438 (0% fail) | 0.342 (0% fail) | 1.25 (0% fail) |
| single_quad | 1.30 (0% fail) | 0.398 (0% fail) | 3.76 (0% fail) | 2.05 (0% fail) | 2.08 (0% fail) | 0.695 (0% fail) | 0.877 (0% fail) | 3.33 (0% fail) |
| all | 1.68 (0% fail) | -- | 5.01 (0% fail) | 2.55 (0% fail) | 2.86 (0% fail) | -- | -- | 4.10 (0% fail) |

### setup, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 1.81 (0% fail) | -- | 3.35 (0% fail) | 2.62 (0% fail) | 2.37 (0% fail) | -- | -- | 4.76 (0% fail) |
| reduced | 14.40 (0% fail) | -- | 22.89 (0% fail) | 15.11 (0% fail) | 15.10 (0% fail) | -- | -- | 34.12 (0% fail) |
| all | 5.16 (0% fail) | -- | 8.80 (0% fail) | 6.33 (0% fail) | 6.03 (0% fail) | -- | -- | 12.79 (0% fail) |

### setup, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.15 (0% fail) | 0.334 (0% fail) | 5.63 (0% fail) | 1.66 (0% fail) | 2.02 (0% fail) | 0.662 (0% fail) | 0.853 (0% fail) | 2.64 (0% fail) |
| fleet_ring_box | 1.63 (0% fail) | 2.78 (7% fail) | 3.33 (0% fail) | 2.14 (0% fail) | 2.39 (0% fail) | 0.975 (0% fail) | 0.905 (0% fail) | 2.94 (0% fail) |
| fleet_ring_box_b4 | 1.23 (0% fail) | -- | 3.47 (0% fail) | 2.23 (0% fail) | 1.32 (0% fail) | 0.859 (0% fail) | 0.545 (0% fail) | 3.46 (0% fail) |
| fleet_ring_soc | 1.88 (0% fail) | -- | 3.31 (0% fail) | 2.39 (0% fail) | 2.42 (0% fail) | -- | -- | 5.06 (0% fail) |
| osqprand | 2.26 (0% fail) | 9.19 (20% fail) | 36.24 (0% fail) | 6.32 (0% fail) | 6.16 (0% fail) | 1.63 (0% fail) | 1.34 (0% fail) | 6.24 (0% fail) |
| reduced | 13.34 (0% fail) | -- | 23.18 (0% fail) | 15.26 (0% fail) | 11.15 (0% fail) | -- | -- | 32.07 (0% fail) |
| single_di_box | 0.778 (0% fail) | 0.258 (0% fail) | 1.76 (0% fail) | 1.11 (0% fail) | 1.13 (0% fail) | 0.216 (0% fail) | 0.333 (0% fail) | 1.38 (0% fail) |
| single_quad | 1.29 (0% fail) | 0.424 (0% fail) | 3.80 (0% fail) | 2.38 (0% fail) | 2.24 (0% fail) | 0.744 (0% fail) | 0.959 (0% fail) | 3.95 (0% fail) |
| all | 1.81 (0% fail) | -- | 5.19 (0% fail) | 2.74 (0% fail) | 2.64 (0% fail) | -- | -- | 4.11 (0% fail) |

### cold_total, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.21 (0% fail) | 0.474 (0% fail) | 8.06 (0% fail) | 3.11 (0% fail) | 3.61 (0% fail) | 1.32 (0% fail) | 1.45 (0% fail) | 3.03 (0% fail) |
| fleet_ring_box | 4.09 (0% fail) | 4.11 (7% fail) | 8.48 (0% fail) | 6.39 (0% fail) | 6.02 (0% fail) | 16.91 (13% fail) | 5.02 (7% fail) | 4.13 (0% fail) |
| fleet_ring_box_b4 | 3.13 (0% fail) | -- | 7.65 (0% fail) | 5.32 (0% fail) | 5.69 (0% fail) | 1.97 (0% fail) | 21.90 (20% fail) | 4.13 (0% fail) |
| fleet_ring_soc | 5.39 (0% fail) | -- | 8.29 (0% fail) | 7.17 (0% fail) | 6.61 (0% fail) | -- | -- | 7.26 (0% fail) |
| osqprand | 6.57 (0% fail) | 0.806 (0% fail) | 45.63 (0% fail) | 9.95 (0% fail) | 9.80 (0% fail) | 5.90 (0% fail) | 3.89 (0% fail) | 9.28 (0% fail) |
| reduced | 33.20 (0% fail) | -- | 37.72 (0% fail) | 30.28 (0% fail) | 29.00 (0% fail) | -- | -- | 38.91 (0% fail) |
| single_di_box | 1.37 (0% fail) | 0.663 (0% fail) | 2.82 (0% fail) | 2.11 (0% fail) | 1.95 (0% fail) | 0.563 (0% fail) | 0.509 (0% fail) | 1.39 (0% fail) |
| single_quad | 2.76 (0% fail) | 0.610 (0% fail) | 6.19 (0% fail) | 3.86 (0% fail) | 3.91 (0% fail) | 1.13 (0% fail) | 1.53 (0% fail) | 3.38 (0% fail) |
| all | 4.31 (0% fail) | -- | 9.96 (0% fail) | 6.16 (0% fail) | 6.06 (0% fail) | -- | -- | 5.08 (0% fail) |

### cold_total, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.71 (0% fail) | 0.695 (0% fail) | 8.53 (0% fail) | 3.54 (0% fail) | 3.88 (0% fail) | 1.54 (0% fail) | 1.44 (0% fail) | 3.22 (0% fail) |
| fleet_ring_box | 4.71 (0% fail) | 2.50 (0% fail) | 9.52 (0% fail) | 6.58 (0% fail) | 6.93 (0% fail) | 5.22 (0% fail) | 2.41 (0% fail) | 3.99 (0% fail) |
| fleet_ring_box_b4 | 3.70 (0% fail) | -- | 9.88 (0% fail) | 5.84 (0% fail) | 6.26 (0% fail) | 5.30 (0% fail) | 1.91 (0% fail) | 4.26 (0% fail) |
| fleet_ring_soc | 6.52 (0% fail) | -- | 10.44 (0% fail) | 9.09 (0% fail) | 8.20 (0% fail) | -- | -- | 7.64 (0% fail) |
| osqprand | 7.29 (0% fail) | 1.18 (0% fail) | 44.02 (0% fail) | 10.49 (0% fail) | 10.31 (0% fail) | 9.96 (0% fail) | 4.72 (0% fail) | 9.27 (0% fail) |
| reduced | 37.50 (0% fail) | -- | 43.84 (0% fail) | 33.26 (0% fail) | 32.59 (0% fail) | -- | -- | 39.91 (0% fail) |
| single_di_box | 1.41 (0% fail) | 0.701 (0% fail) | 3.71 (0% fail) | 2.79 (0% fail) | 2.60 (0% fail) | 0.824 (0% fail) | 0.642 (0% fail) | 1.35 (0% fail) |
| single_quad | 3.24 (0% fail) | 0.732 (0% fail) | 7.16 (0% fail) | 4.54 (0% fail) | 4.51 (0% fail) | 1.65 (0% fail) | 1.57 (0% fail) | 3.60 (0% fail) |
| all | 4.96 (0% fail) | -- | 11.48 (0% fail) | 6.89 (0% fail) | 6.96 (0% fail) | -- | -- | 5.13 (0% fail) |

### cold_total, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 7.39 (0% fail) | -- | 11.57 (0% fail) | 10.23 (0% fail) | 8.90 (0% fail) | -- | -- | 7.88 (0% fail) |
| reduced | 43.78 (0% fail) | -- | 48.66 (0% fail) | 38.11 (0% fail) | 36.34 (0% fail) | -- | -- | 40.87 (0% fail) |
| all | 18.02 (0% fail) | -- | 23.75 (0% fail) | 19.77 (0% fail) | 18.01 (0% fail) | -- | -- | 17.99 (0% fail) |

### cold_total, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 3.19 (0% fail) | 0.630 (0% fail) | 9.32 (0% fail) | 3.93 (0% fail) | 4.46 (0% fail) | 1.75 (0% fail) | 1.54 (0% fail) | 2.87 (0% fail) |
| fleet_ring_box | 5.60 (0% fail) | 6.02 (7% fail) | 11.05 (0% fail) | 7.85 (0% fail) | 7.54 (0% fail) | 9.10 (0% fail) | 2.62 (0% fail) | 4.07 (0% fail) |
| fleet_ring_box_b4 | 3.93 (0% fail) | -- | 10.73 (0% fail) | 6.47 (0% fail) | 5.07 (0% fail) | 9.01 (0% fail) | 1.65 (0% fail) | 4.35 (0% fail) |
| fleet_ring_soc | 8.14 (0% fail) | -- | 12.30 (0% fail) | 10.66 (0% fail) | 9.45 (0% fail) | -- | -- | 8.17 (0% fail) |
| osqprand | 8.23 (0% fail) | 16.90 (20% fail) | 45.39 (0% fail) | 11.42 (0% fail) | 11.29 (0% fail) | 15.20 (0% fail) | 4.91 (0% fail) | 6.89 (0% fail) |
| reduced | 45.29 (0% fail) | -- | 53.79 (0% fail) | 42.84 (0% fail) | 31.07 (0% fail) | -- | -- | 38.84 (0% fail) |
| single_di_box | 1.95 (0% fail) | 0.498 (0% fail) | 4.85 (0% fail) | 3.47 (0% fail) | 2.99 (0% fail) | 0.713 (0% fail) | 0.660 (0% fail) | 1.50 (0% fail) |
| single_quad | 3.62 (0% fail) | 0.822 (0% fail) | 7.79 (0% fail) | 5.43 (0% fail) | 5.03 (0% fail) | 2.04 (0% fail) | 1.76 (0% fail) | 4.29 (0% fail) |
| all | 5.88 (0% fail) | -- | 13.16 (0% fail) | 8.11 (0% fail) | 7.40 (0% fail) | -- | -- | 5.12 (0% fail) |

### warm, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.27 (0% fail) | 0.202 (0% fail) | 2.04 (0% fail) | 1.27 (0% fail) | 1.35 (0% fail) | 10.44 (20% fail) | 0.422 (0% fail) | 0.095 (0% fail) |
| fleet_ring_box | 2.45 (0% fail) | 2.28 (7% fail) | 5.16 (0% fail) | 3.97 (0% fail) | 3.51 (0% fail) | 3.61 (7% fail) | 2.90 (7% fail) | 0.839 (0% fail) |
| fleet_ring_box_b4 | 1.83 (0% fail) | -- | 4.58 (0% fail) | 2.93 (0% fail) | 2.92 (0% fail) | 15.69 (20% fail) | 14.28 (20% fail) | 0.923 (0% fail) |
| fleet_ring_soc | 3.41 (0% fail) | -- | 5.01 (0% fail) | 4.57 (0% fail) | 3.87 (0% fail) | -- | -- | 2.18 (0% fail) |
| osqprand | 4.22 (0% fail) | 0.397 (0% fail) | 5.98 (0% fail) | 3.39 (0% fail) | 3.30 (0% fail) | 2.65 (0% fail) | 2.43 (0% fail) | 0.326 (0% fail) |
| reduced | 19.37 (0% fail) | -- | 15.55 (0% fail) | 14.29 (0% fail) | 12.63 (0% fail) | -- | -- | 1.39 (0% fail) |
| single_di_box | 0.751 (0% fail) | 0.196 (0% fail) | 1.34 (0% fail) | 1.12 (0% fail) | 0.874 (0% fail) | 0.207 (0% fail) | 0.219 (0% fail) | 0.056 (0% fail) |
| single_quad | 1.41 (0% fail) | 0.234 (0% fail) | 2.22 (0% fail) | 1.60 (0% fail) | 1.58 (0% fail) | 0.460 (0% fail) | 0.539 (0% fail) | 0.114 (0% fail) |
| all | 2.54 (0% fail) | -- | 4.24 (0% fail) | 3.16 (0% fail) | 2.89 (0% fail) | -- | -- | 0.517 (0% fail) |

### warm, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.70 (0% fail) | 0.253 (0% fail) | 2.89 (0% fail) | 1.90 (0% fail) | 1.74 (0% fail) | 0.865 (0% fail) | 0.557 (0% fail) | 0.147 (0% fail) |
| fleet_ring_box | 3.18 (0% fail) | 1.59 (0% fail) | 6.40 (0% fail) | 4.82 (0% fail) | 4.24 (0% fail) | 25.21 (13% fail) | 1.37 (0% fail) | 0.941 (0% fail) |
| fleet_ring_box_b4 | 2.29 (0% fail) | -- | 6.15 (0% fail) | 3.47 (0% fail) | 3.22 (0% fail) | 31.95 (20% fail) | 0.929 (0% fail) | 0.971 (0% fail) |
| fleet_ring_soc | 4.63 (0% fail) | -- | 7.13 (0% fail) | 6.44 (0% fail) | 5.43 (0% fail) | -- | -- | 2.48 (0% fail) |
| osqprand | 5.04 (0% fail) | 0.557 (0% fail) | 7.03 (0% fail) | 3.95 (0% fail) | 3.99 (0% fail) | 9.55 (0% fail) | 3.13 (0% fail) | 0.227 (0% fail) |
| reduced | 23.57 (0% fail) | -- | 20.27 (0% fail) | 18.49 (0% fail) | 16.40 (0% fail) | -- | -- | 1.25 (0% fail) |
| single_di_box | 0.807 (0% fail) | 0.177 (0% fail) | 2.22 (0% fail) | 1.70 (0% fail) | 1.37 (0% fail) | 0.331 (0% fail) | 0.256 (0% fail) | 0.056 (0% fail) |
| single_quad | 1.84 (0% fail) | 0.269 (0% fail) | 3.02 (0% fail) | 2.29 (0% fail) | 2.13 (0% fail) | 0.886 (0% fail) | 0.673 (0% fail) | 0.147 (0% fail) |
| all | 3.20 (0% fail) | -- | 5.64 (0% fail) | 4.12 (0% fail) | 3.69 (0% fail) | -- | -- | 0.548 (0% fail) |

### warm, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc | 5.51 (0% fail) | -- | 8.21 (0% fail) | 7.49 (0% fail) | 6.45 (0% fail) | -- | -- | 2.63 (0% fail) |
| reduced | 30.72 (0% fail) | -- | 24.82 (0% fail) | 22.86 (0% fail) | 20.44 (0% fail) | -- | -- | 1.38 (0% fail) |
| all | 13.05 (0% fail) | -- | 14.29 (0% fail) | 13.10 (0% fail) | 11.50 (0% fail) | -- | -- | 1.91 (0% fail) |

### warm, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.01 (0% fail) | 0.289 (0% fail) | 8.70 (0% fail) | 2.13 (0% fail) | 2.18 (0% fail) | 1.08 (0% fail) | 0.717 (0% fail) | 0.106 (0% fail) |
| fleet_ring_box | 3.82 (0% fail) | 3.04 (7% fail) | 7.71 (0% fail) | 6.10 (0% fail) | 5.01 (0% fail) | 7.33 (0% fail) | 1.54 (0% fail) | 0.995 (0% fail) |
| fleet_ring_box_b4 | 2.70 (0% fail) | -- | 6.94 (0% fail) | 4.07 (0% fail) | 3.76 (0% fail) | 4.86 (0% fail) | 1.06 (0% fail) | 0.917 (0% fail) |
| fleet_ring_soc | 6.09 (0% fail) | -- | 8.88 (0% fail) | 8.19 (0% fail) | 7.00 (0% fail) | -- | -- | 2.68 (0% fail) |
| osqprand | 6.04 (0% fail) | 10.20 (20% fail) | 45.08 (0% fail) | 4.76 (0% fail) | 4.87 (0% fail) | 19.34 (0% fail) | 3.41 (0% fail) | 0.194 (0% fail) |
| reduced | 33.84 (0% fail) | -- | 29.29 (0% fail) | 27.86 (0% fail) | 20.36 (0% fail) | -- | -- | 1.36 (0% fail) |
| single_di_box | 1.06 (0% fail) | 0.250 (0% fail) | 4.30 (0% fail) | 2.17 (0% fail) | 1.69 (0% fail) | 0.405 (0% fail) | 0.341 (0% fail) | 0.071 (0% fail) |
| single_quad | 2.06 (0% fail) | 0.304 (0% fail) | 3.67 (0% fail) | 2.90 (0% fail) | 2.58 (0% fail) | 15.86 (20% fail) | 0.778 (0% fail) | 0.099 (0% fail) |
| all | 3.94 (0% fail) | -- | 9.38 (0% fail) | 5.18 (0% fail) | 4.48 (0% fail) | -- | -- | 0.538 (0% fail) |

## Where sheafmpc loses (median time over the best other solver, ratio > 1, or misses the tier)

| instance | mode | tier | sheafmpc ms | best other | its ms | ratio |
|---|---|---|---:|---|---:|---:|
| osqprand_nx20_s1 | setup | low | 8.19 | hpipm | 0.387 | 21.16 |
| osqprand_nx20_s1 | setup | medium | 8.14 | hpipm | 0.488 | 16.67 |
| osqprand_nx20_s1 | cold_total | low | 8.93 | hpipm | 0.802 | 11.14 |
| chain_M4 | setup | low | 2.90 | hpipm | 0.279 | 10.40 |
| quad_N20 | setup | low | 3.35 | hpipm | 0.363 | 9.22 |
| quad_N20 | setup | medium | 3.37 | hpipm | 0.427 | 7.89 |
| osqprand_nx20_s1 | cold_total | medium | 9.06 | hpipm | 1.18 | 7.67 |
| chain_M4 | setup | medium | 3.00 | hpipm | 0.398 | 7.53 |
| chain_M4 | setup | high | 2.69 | hpipm | 0.358 | 7.50 |
| quad_N20 | setup | high | 3.80 | hpipm | 0.507 | 7.49 |
| fleet_ring_box_n4 | setup | low | 2.64 | hpipm | 0.380 | 6.95 |
| chain_M4 | cold_total | low | 3.17 | hpipm | 0.471 | 6.74 |
| di_box_N20 | setup | high | 1.37 | osqp | 0.214 | 6.41 |
| quad_N20 | cold_total | low | 3.59 | hpipm | 0.567 | 6.34 |
| fleet_ring_box_b4_n4 | setup | high | 3.42 | piqp | 0.546 | 6.27 |
| fleet_ring_box_n4 | setup | medium | 2.81 | hpipm | 0.495 | 5.68 |
| fleet_ring_box_n16 | setup | low | 11.49 | piqp | 2.15 | 5.34 |
| fleet_ring_box_n16 | setup | high | 11.73 | piqp | 2.30 | 5.10 |
| chain_M4 | cold_total | medium | 3.24 | hpipm | 0.657 | 4.93 |
| quad_N20 | cold_total | medium | 3.68 | hpipm | 0.759 | 4.85 |
| fleet_ring_box_n16 | setup | medium | 10.90 | piqp | 2.33 | 4.68 |
| chain_M4 | cold_total | high | 2.90 | hpipm | 0.630 | 4.60 |
| osqprand_nx20_s1 | setup | high | 6.21 | piqp | 1.36 | 4.58 |
| fleet_ring_box_b4_n4 | setup | low | 3.36 | osqp | 0.743 | 4.53 |
| quad_N20 | cold_total | high | 4.11 | hpipm | 0.917 | 4.48 |
| fleet_ring_box_b4_n4 | setup | medium | 3.43 | osqp | 0.795 | 4.31 |
| fleet_ring_box_n4 | setup | high | 3.00 | hpipm | 0.747 | 4.02 |
| fleet_ring_box_n1 | setup | medium | 0.672 | osqp | 0.183 | 3.68 |
| di_box_N20 | setup | low | 1.27 | piqp | 0.351 | 3.64 |
| di_box_N20 | setup | medium | 1.22 | piqp | 0.346 | 3.53 |
| di_box_N20 | cold_total | high | 1.49 | hpipm | 0.433 | 3.44 |
| fleet_ring_box_n4 | cold_total | low | 3.71 | hpipm | 1.09 | 3.40 |
| fleet_ring_box_n1 | setup | high | 0.653 | osqp | 0.195 | 3.34 |
| fleet_ring_box_n1 | setup | low | 0.741 | hpipm | 0.246 | 3.01 |
| fleet_ring_box_n4 | cold_total | medium | 4.18 | hpipm | 1.45 | 2.87 |
| reduced_k8 | setup | high | 31.97 | mumblebee_fast_ct | 11.15 | 2.87 |
| fleet_ring_soc_n4 | setup | medium | 4.75 | clarabel | 1.68 | 2.84 |
| fleet_ring_soc_n4 | setup | low | 4.76 | clarabel | 1.76 | 2.71 |
| fleet_ring_box_b4_n4 | cold_total | high | 4.28 | piqp | 1.59 | 2.69 |
| fleet_ring_box_n4 | cold_total | high | 4.33 | hpipm | 1.62 | 2.68 |
| fleet_ring_soc_n4 | setup | high | 5.10 | clarabel | 1.92 | 2.66 |
| fleet_ring_soc_n4 | setup | e8 | 4.68 | clarabel | 1.81 | 2.59 |
| reduced_k8 | setup | medium | 33.38 | clarabel | 13.24 | 2.52 |
| reduced_k8 | setup | low | 32.53 | clarabel | 13.07 | 2.49 |
| di_box_N20 | cold_total | low | 1.40 | osqp | 0.577 | 2.43 |
| reduced_k8 | setup | e8 | 34.51 | mumblebee_fast_ct | 14.50 | 2.38 |
| fleet_ring_box_b4_n4 | cold_total | medium | 4.28 | piqp | 1.89 | 2.27 |
| fleet_ring_box_n1 | cold_total | low | 0.850 | hpipm | 0.395 | 2.15 |
| fleet_ring_box_n16 | cold_total | low | 18.81 | piqp | 8.94 | 2.10 |
| di_box_N20 | cold_total | medium | 1.31 | piqp | 0.646 | 2.02 |
| osqprand_nx20_s1 | cold | low | 0.798 | hpipm | 0.406 | 1.97 |
| fleet_ring_box_b4_n4 | cold_total | low | 4.09 | osqp | 2.12 | 1.93 |
| fleet_ring_box_n16 | cold_total | medium | 18.51 | piqp | 11.48 | 1.61 |
| fleet_ring_box_n4 | cold | low | 1.14 | hpipm | 0.745 | 1.53 |
| fleet_ring_box_n1 | cold_total | medium | 0.725 | hpipm | 0.503 | 1.44 |
| fleet_ring_box_n16 | cold_total | high | 18.77 | piqp | 13.05 | 1.44 |
| fleet_ring_box_n4 | cold | medium | 1.35 | hpipm | 0.944 | 1.43 |
| fleet_ring_box_n4 | warm | high | 1.01 | hpipm | 0.720 | 1.41 |
| osqprand_nx20_s1 | cold_total | high | 6.91 | piqp | 4.95 | 1.40 |
| fleet_ring_box_n1 | cold_total | high | 0.758 | piqp | 0.544 | 1.39 |
| chain_M4 | cold | low | 0.262 | hpipm | 0.192 | 1.37 |
| fleet_ring_box_n4 | cold | high | 1.33 | hpipm | 0.975 | 1.36 |
| reduced_k8 | cold_total | low | 39.09 | mumblebee_fast_ct | 28.92 | 1.35 |
| osqprand_nx20_s1 | cold | medium | 0.939 | hpipm | 0.736 | 1.28 |
| fleet_ring_soc_n4 | cold_total | low | 6.76 | clarabel | 5.33 | 1.27 |
| reduced_k8 | cold_total | high | 38.72 | mumblebee_fast_ct | 30.95 | 1.25 |
| reduced_k8 | cold_total | medium | 40.02 | mumblebee_fast_ct | 32.54 | 1.23 |
| reduced_k8 | cold_total | e8 | 41.15 | mumblebee_fast_ct | 35.31 | 1.17 |
| fleet_ring_box_n16 | cold | low | 7.71 | piqp | 6.81 | 1.13 |
| fleet_ring_soc_n4 | cold_total | medium | 7.26 | clarabel | 6.62 | 1.10 |
| fleet_ring_box_n4 | warm | low | 0.650 | hpipm | 0.598 | 1.09 |
| chain_M4 | cold | medium | 0.276 | hpipm | 0.260 | 1.06 |
| fleet_ring_soc_n4 | cold_total | e8 | 7.74 | clarabel | 7.34 | 1.05 |
| fleet_ring_box_n16 | warm | low | 7.35 | piqp | 7.21 | 1.02 |

sheafmpc is fastest (ratio <= 1) in 54 of 128 (instance, mode, tier) cells with a finite ratio; median ratio 1.27.

## Gate: sheafmpc against mumblebee_fast (median time ratio; <= 1 passes)

| mode | tier | cells | pass | sheafmpc misses the tier | median ratio | worst ratio (instance) |
|---|---|---:|---:|---:|---:|---|
| cold | low | 10 | 10 | 0 | 0.23 | 0.47 (fleet_ring_soc_n4) |
| cold | medium | 10 | 10 | 0 | 0.23 | 0.38 (fleet_ring_soc_n4) |
| cold | e8 | 2 | 2 | 0 | 0.35 | 0.40 (fleet_ring_soc_n4) |
| cold | high | 10 | 10 | 0 | 0.16 | 0.36 (fleet_ring_soc_n4) |
| setup | low | 10 | 1 | 0 | 1.55 | 2.13 (reduced_k8) |
| setup | medium | 10 | 0 | 0 | 1.62 | 2.27 (reduced_k8) |
| setup | e8 | 2 | 0 | 0 | 2.02 | 2.26 (reduced_k8) |
| setup | high | 10 | 1 | 0 | 1.54 | 2.18 (fleet_ring_soc_n4) |
| cold_total | low | 10 | 8 | 0 | 0.85 | 1.30 (reduced_k8) |
| cold_total | medium | 10 | 9 | 0 | 0.76 | 1.21 (reduced_k8) |
| cold_total | e8 | 2 | 1 | 0 | 0.92 | 1.08 (reduced_k8) |
| cold_total | high | 10 | 10 | 0 | 0.63 | 0.90 (reduced_k8) |
| warm | low | 10 | 10 | 0 | 0.09 | 0.48 (fleet_ring_soc_n4) |
| warm | medium | 10 | 10 | 0 | 0.07 | 0.35 (fleet_ring_box_n16) |
| warm | e8 | 2 | 2 | 0 | 0.19 | 0.33 (fleet_ring_soc_n4) |
| warm | high | 10 | 10 | 0 | 0.05 | 0.33 (fleet_ring_soc_n4) |
