# Benchmark summary

Sources: results/hpg_a284b72/full_20261018_a284b72a48_shared, results/hpg_a284b72/full_20261018_a284b72a48_shared/mumblebee_fast, results/hpg_a284b72/full_20261018_a284b72a48_shared/mumblebee_fast_ct; 60 instances.

## Setup

- host `c0706a-s25.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0700a-s21.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0707a-s7.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0702a-s6.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0704a-s18.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0705a-s25.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0704a-s22.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0702a-s4.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0705a-s14.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0704a-s27.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0705a-s5.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- host `c0707a-s26.ufhpc`, CPU AMD EPYC 7702 64-Core Processor
- Julia 1.12.6, 1 thread, BLAS threads 1; governor ``, boost ``
- 1-minute load before each instance: median 93.3, max 153.3; gate passed 60, timed out 0, skipped 0
- involuntary context switches while timing an instance: median 116, max 6667 (fleet_grid_soc_b4_n64)
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
| chain_M3 | 160 | 0.718 | 0.107 | 1.30 | 0.874 | 0.777 | 0.406 | 0.305 | 0.039 | 0.36 (hpipm) | 0.04 |
| chain_M4 | 220 | 1.10 | 0.149 | 1.87 | 1.18 | 1.24 | 0.687 | 0.398 | 0.053 | 0.36 (hpipm) | 0.04 |
| chain_M6 | 340 | 2.15 | 0.285 | 3.88 | 2.00 | 2.15 | 1.31 | 0.669 | 0.864 | 3.02 (hpipm) | 0.43 |
| chain_M8 | 460 | 3.51 | 0.388 | 5.86 | 3.10 | 3.03 | 2.09 | 0.887 | 1.33 | 3.41 (hpipm) | 0.43 |
| chain_M10 | 580 | 5.45 | 0.524 | 8.24 | 4.23 | 4.14 | 3.10 | 1.30 | 2.13 | 4.07 (hpipm) | 0.51 |

Cold cells: median ms of the solve alone; setup is its own mode.

### chain, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.989 | 0.137 | 1.86 | 1.17 | 1.08 | 0.413 | 0.349 | 0.050 | 0.36 (hpipm) | 0.04 |
| chain_M4 | 220 | 1.46 | 0.184 | 2.56 | 1.58 | 1.69 | 0.694 | 0.451 | 0.077 | 0.42 (hpipm) | 0.05 |
| chain_M6 | 340 | 2.92 | 0.324 | 5.40 | 2.99 | 2.98 | 1.33 | 0.827 | 0.974 | 3.01 (hpipm) | 0.33 |
| chain_M8 | 460 | 5.22 | 0.553 | 8.85 | 4.63 | 4.49 | 2.13 | 1.11 | 1.45 | 2.62 (hpipm) | 0.31 |
| chain_M10 | 580 | 7.29 | 0.693 | 10.98 | 5.49 | 5.68 | 3.15 | 1.60 | 2.20 | 3.17 (hpipm) | 0.40 |

Cold cells: median ms of the solve alone; setup is its own mode.

### chain, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.20 | 0.162 | 2.24 [1/5] | 1.46 [1/5] | 1.36 [1/5] | 0.609 | 0.451 | 0.048 | 0.29 (hpipm) | -- |
| chain_M4 | 220 | 1.59 | 0.229 | 3.21 | 1.86 | 1.82 | 0.965 | 0.599 | 0.099 | 0.43 (hpipm) | 0.05 |
| chain_M6 | 340 | 3.42 | 0.391 | 6.38 [1/5] | 3.36 [1/5] | 3.26 [1/5] | 1.85 | 0.906 | 0.945 | 2.42 (hpipm) | -- |
| chain_M8 | 460 | 6.27 | 0.577 [1/5] | 9.78 | 5.33 | 5.28 | 2.97 | 1.25 | 1.52 | 1.22 (piqp) | 0.28 |
| chain_M10 | 580 | 8.74 | 0.886 | 13.41 [3/5] | 6.57 [3/5] | 6.52 [3/5] | 4.39 | 1.86 | 2.19 | 2.47 (hpipm) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### chain, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.401 | 0.102 | 2.16 | 0.605 | 0.660 | 0.231 | 0.301 | 1.20 | 11.73 (hpipm) | 1.98 |
| chain_M4 | 220 | 0.552 | 0.124 | 4.19 | 1.01 | 1.12 | 0.367 | 0.479 | 2.00 | 16.20 (hpipm) | 1.98 |
| chain_M6 | 340 | 0.982 | 0.104 | 12.50 | 2.05 | 2.22 | 0.745 | 0.933 | 3.46 | 33.20 (hpipm) | 1.68 |
| chain_M8 | 460 | 1.46 | 0.122 | 27.53 | 3.60 | 3.59 | 1.21 | 1.37 | 5.96 | 48.69 (hpipm) | 1.66 |
| chain_M10 | 580 | 2.17 | 0.143 | 52.35 | 5.91 | 6.03 | 1.76 | 2.17 | 9.30 | 65.02 (hpipm) | 1.57 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### chain, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.378 | 0.100 | 2.11 | 0.616 | 0.648 | 0.233 | 0.287 | 1.16 | 11.62 (hpipm) | 1.88 |
| chain_M4 | 220 | 0.564 | 0.116 | 4.20 | 0.986 | 1.09 | 0.368 | 0.464 | 2.00 | 17.23 (hpipm) | 2.02 |
| chain_M6 | 340 | 1.02 | 0.134 | 12.37 | 2.04 | 2.05 | 0.711 | 0.916 | 3.37 | 25.22 (hpipm) | 1.65 |
| chain_M8 | 460 | 1.56 | 0.117 | 27.67 | 3.67 | 3.65 | 1.22 | 1.35 | 5.91 | 50.63 (hpipm) | 1.61 |
| chain_M10 | 580 | 2.25 | 0.197 | 52.49 | 5.79 | 6.10 | 1.86 | 2.22 | 9.17 | 46.55 (hpipm) | 1.58 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### chain, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.390 | 0.106 | 2.09 [1/5] | 0.616 [1/5] | 0.605 [1/5] | 0.232 | 0.285 | 1.13 | 10.60 (hpipm) | -- |
| chain_M4 | 220 | 0.556 | 0.116 | 4.29 | 1.15 | 1.03 | 0.368 | 0.478 | 1.93 | 16.69 (hpipm) | 1.67 |
| chain_M6 | 340 | 1.01 | 0.135 | 12.53 [1/5] | 2.09 [1/5] | 2.07 [1/5] | 0.735 | 0.900 | 3.29 | 24.31 (hpipm) | -- |
| chain_M8 | 460 | 1.52 | 0.113 [1/5] | 27.62 | 3.72 | 3.98 | 1.19 | 1.34 | 5.92 | 4.96 (osqp) | 1.59 |
| chain_M10 | 580 | 2.24 | 0.148 | 52.44 [3/5] | 5.86 [3/5] | 6.04 [3/5] | 1.85 | 2.18 | 9.03 | 61.22 (hpipm) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### chain, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.12 | 0.211 | 3.43 | 1.47 | 1.44 | 0.639 | 0.601 | 1.24 | 5.88 (hpipm) | 0.84 |
| chain_M4 | 220 | 1.66 | 0.274 | 6.06 | 2.18 | 2.38 | 1.05 | 0.877 | 2.05 | 7.51 (hpipm) | 0.94 |
| chain_M6 | 340 | 3.13 | 0.391 | 16.38 | 4.04 | 4.37 | 2.06 | 1.60 | 4.30 | 10.99 (hpipm) | 1.06 |
| chain_M8 | 460 | 4.98 | 0.508 | 33.43 | 6.69 | 6.62 | 3.30 | 2.26 | 7.06 | 13.91 (hpipm) | 1.06 |
| chain_M10 | 580 | 7.62 | 0.666 | 60.47 | 10.11 | 10.17 | 4.88 | 3.48 | 11.23 | 16.85 (hpipm) | 1.11 |

Setup + solve cells: median ms of a cold setup plus its solve.

### chain, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.37 | 0.236 | 3.97 | 1.79 | 1.77 | 0.645 | 0.633 | 1.21 | 5.12 (hpipm) | 0.68 |
| chain_M4 | 220 | 2.02 | 0.300 | 6.76 | 2.58 | 2.76 | 1.07 | 0.909 | 2.07 | 6.91 (hpipm) | 0.80 |
| chain_M6 | 340 | 4.14 | 0.456 | 17.75 | 5.01 | 5.00 | 2.04 | 1.76 | 4.36 | 9.57 (hpipm) | 0.87 |
| chain_M8 | 460 | 6.73 | 0.669 | 36.48 | 8.29 | 8.11 | 3.35 | 2.49 | 7.41 | 11.07 (hpipm) | 0.89 |
| chain_M10 | 580 | 9.62 | 0.889 | 63.45 | 11.30 | 11.76 | 5.01 | 3.81 | 11.30 | 12.70 (hpipm) | 1.00 |

Setup + solve cells: median ms of a cold setup plus its solve.

### chain, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.59 | 0.262 | 4.32 [1/5] | 2.07 [1/5] | 1.97 [1/5] | 0.843 | 0.743 | 1.18 | 4.49 (hpipm) | -- |
| chain_M4 | 220 | 2.15 | 0.340 | 7.53 | 3.02 | 2.93 | 1.34 | 1.08 | 2.03 | 5.96 (hpipm) | 0.67 |
| chain_M6 | 340 | 4.39 | 0.526 | 18.98 [1/5] | 5.44 [1/5] | 5.33 [1/5] | 2.59 | 1.81 | 4.22 | 8.04 (hpipm) | -- |
| chain_M8 | 460 | 7.79 | 0.689 [1/5] | 37.50 | 9.12 | 9.26 | 4.17 | 2.60 | 7.44 | 2.86 (piqp) | 0.82 |
| chain_M10 | 580 | 10.93 | 1.03 | 65.84 [3/5] | 12.43 [3/5] | 12.55 [3/5] | 6.24 | 4.04 | 11.18 | 10.82 (hpipm) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### chain, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.620 (0.649) | 0.100 (0.108) | 1.25 (1.32) | 0.816 (0.859) | 0.765 (0.832) | 0.199 (0.204) | 0.280 (0.296) | 0.037 (0.041) | 0.37 (hpipm) | 0.05 |
| chain_M4 | 220 | 1.06 (1.08) | 0.135 (0.142) | 1.83 (1.89) | 1.12 (1.16) | 1.13 (1.19) | 0.314 (0.654) [1/11] | 0.358 (0.410) | 0.054 (0.061) | 0.40 (hpipm) | 0.05 |
| chain_M6 | 340 | 2.11 (2.14) | 0.294 (0.300) [1/11] | 3.44 (3.49) [1/11] | 1.88 (1.92) [1/11] | 1.90 (1.95) [1/11] | 0.580 (0.594) | 0.509 (0.631) | 0.097 (0.192) | 0.19 (piqp) | -- |
| chain_M8 | 460 | 3.52 (3.60) | 0.381 (0.406) [3/11] | 5.50 (5.69) [3/11] | 2.78 (2.83) [3/11] | 2.75 (2.82) [3/11] | 0.962 (1.01) | 0.726 (0.860) | 0.184 (0.265) | 0.25 (piqp) | -- |
| chain_M10 | 580 | 5.38 (5.49) | 0.544 (0.561) | 8.00 (8.13) [2/11] | 3.80 (4.05) [2/11] | 3.73 (3.77) [2/11] | 1.40 (1.44) | 1.04 (1.27) | 0.265 (0.373) | 0.49 (hpipm) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### chain, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 0.839 (0.956) | 0.128 (0.134) | 1.72 (1.88) [1/11] | 1.09 (1.27) [1/11] | 0.979 (1.10) [1/11] | 0.378 (0.392) | 0.338 (0.402) | 0.052 (0.056) | 0.41 (hpipm) | -- |
| chain_M4 | 220 | 1.38 (1.60) | 0.161 (0.188) | 6.68 (7.13) | 1.50 (1.86) | 1.52 (1.87) | 0.621 (0.966) | 0.459 (0.585) | 0.079 (0.085) | 0.49 (hpipm) | 0.05 |
| chain_M6 | 340 | 2.74 (3.12) | 0.306 (0.329) [1/11] | 4.82 (5.59) [1/11] | 2.57 (2.91) [1/11] | 2.49 (2.85) [1/11] | 1.17 (1.81) | 0.673 (0.803) | 0.096 (0.231) | 0.14 (piqp) | -- |
| chain_M8 | 460 | 4.73 (5.30) | 0.509 (0.593) | 34.57 (35.53) [1/11] | 3.90 (4.33) [1/11] | 3.82 (4.36) [1/11] | 1.87 (2.88) | 0.958 (1.14) | 0.177 (0.337) | 0.35 (hpipm) | -- |
| chain_M10 | 580 | 7.14 (8.15) | 0.717 (0.794) [3/11] | 10.76 (10.89) [3/11] | 5.12 (5.20) [3/11] | 5.21 (5.24) [3/11] | 2.74 (4.35) | 1.44 (1.51) | 0.259 (0.507) | 0.18 (piqp) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### chain, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 160 | 1.01 (1.13) | 0.132 (0.158) [1/11] | 3.91 (4.18) [5/11] | 1.33 (1.51) [5/11] | 1.19 (1.37) [5/11] | 0.531 (0.551) | 0.410 (0.487) | 0.052 (0.056) | 0.13 (piqp) | -- |
| chain_M4 | 220 | 1.51 (2.00) | 0.206 (0.266) | 6.83 (7.31) | 1.69 (2.06) | 1.71 (2.08) | 0.969 (1.03) | 0.516 (0.675) | 0.080 (0.086) | 0.39 (hpipm) | 0.05 |
| chain_M6 | 340 | 3.37 (3.71) | 0.324 (0.392) | 17.50 (18.20) [2/11] | 2.90 (3.27) [2/11] | 2.85 (3.20) [2/11] | 1.80 (1.83) | 0.746 (0.936) | 0.148 (0.245) | 0.46 (hpipm) | -- |
| chain_M8 | 460 | 5.67 (6.95) | 0.514 (0.602) [3/11] | 36.48 (38.39) | 4.87 (6.09) | 4.71 (5.77) | 1.90 (2.93) | 1.12 (1.39) | 0.264 (0.333) | 0.24 (piqp) | 0.05 |
| chain_M10 | 580 | 8.69 (9.71) | 0.838 (1.04) | 61.99 (64.90) [6/11] | 5.17 (6.49) [6/11] | 5.10 (6.48) [6/11] | 2.78 (4.32) | 1.57 (1.78) | 0.363 (0.507) | 0.43 (hpipm) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### chain, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain_M3 | 5 / 8 / -- / 10 | 5 / 7 / -- / 9 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 6 / 8 / -- / 10 | 50 / 50 / -- / 75 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| chain_M4 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 50 / 50 / -- / 75 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| chain_M6 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 50 / 50 / -- / 75 | 6 / 8 / -- / 9 | 20 / 20 / -- / 20 |
| chain_M8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 9 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 6 / 9 / -- / 10 | 50 / 50 / -- / 75 | 6 / 8 / -- / 9 | 15 / 15 / -- / 15 |
| chain_M10 | 5 / 7 / -- / 9 | 5 / 7 / -- / 8 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 6 / 8 / -- / 9 | 50 / 50 / -- / 75 | 6 / 8 / -- / 9 | 15 / 15 / -- / 15 |

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
| chain_M3 | 0.378 | 0.100 | 2.11 | 0.616 | 0.648 | 0.233 | 0.287 | 1.16 |
| chain_M4 | 0.564 | 0.116 | 4.20 | 0.986 | 1.09 | 0.368 | 0.464 | 2.00 |
| chain_M6 | 1.02 | 0.134 | 12.37 | 2.04 | 2.05 | 0.711 | 0.916 | 3.37 |
| chain_M8 | 1.56 | 0.117 | 27.67 | 3.67 | 3.65 | 1.22 | 1.35 | 5.91 |
| chain_M10 | 2.25 | 0.197 | 52.49 | 5.79 | 6.10 | 1.86 | 2.22 | 9.17 |

## fleet_grid_box

### fleet_grid_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.311 | 0.079 | 0.950 | 0.119 [2/6] | 0.096 | 0.035 | 0.44 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.09 | 0.464 [1/6] | 4.63 | 2.15 | 0.699 | 1.17 | 1.67 (piqp) |
| fleet_grid_box_n16 | 2240 | 17.99 | 9.44 | 22.77 | 13.30 | 13.16 | 9.19 | 0.97 (hpipm) |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.429 | 0.089 | 1.44 | 0.514 [2/6] | 0.115 | 0.035 | 0.40 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.88 | 0.636 | 6.37 | 4.63 | 1.03 | 1.17 | 1.83 (hpipm) |
| fleet_grid_box_n16 | 2240 | 25.03 | 12.11 | 32.27 | 29.24 [1/6] | 17.25 | 9.39 | 0.78 (hpipm) |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.523 | 0.098 [1/6] | 1.71 | 1.12 [1/6] | 0.152 | 0.039 | 0.26 (piqp) |
| fleet_grid_box_n4 | 560 | 3.49 | 0.841 | 7.37 | 7.13 | 1.23 | 1.21 | 1.43 (hpipm) |
| fleet_grid_box_n16 | 2240 | 29.72 | 13.98 | 36.62 | 65.26 | 21.30 | 8.86 | 0.63 (hpipm) |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_box, setup, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.277 | 0.115 | 0.619 | 0.157 [2/6] | 0.119 | 0.559 | 4.87 (hpipm) |
| fleet_grid_box_n4 | 560 | 1.03 | 0.179 [1/6] | 2.54 | 0.715 | 0.393 | 2.64 | 6.73 (piqp) |
| fleet_grid_box_n16 | 2240 | 4.48 | 1.71 | 10.12 | 3.92 | 1.92 | 15.99 | 9.34 (hpipm) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_box, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.276 | 0.113 | 0.647 | 0.164 [2/6] | 0.118 | 0.595 | 5.26 (hpipm) |
| fleet_grid_box_n4 | 560 | 1.02 | 0.175 | 2.45 | 0.740 | 0.447 | 2.59 | 14.84 (hpipm) |
| fleet_grid_box_n16 | 2240 | 4.57 | 0.928 | 10.23 | 4.10 [1/6] | 1.99 | 16.08 | 17.33 (hpipm) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_box, setup, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.294 | 0.111 [1/6] | 0.634 | 0.148 [1/6] | 0.122 | 0.521 | 4.27 (piqp) |
| fleet_grid_box_n4 | 560 | 1.07 | 0.180 | 2.49 | 0.709 | 0.490 | 2.55 | 14.19 (hpipm) |
| fleet_grid_box_n16 | 2240 | 4.60 | 1.66 | 10.22 | 4.21 | 2.10 | 15.88 | 9.59 (hpipm) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_box, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.591 | 0.190 | 1.58 | 0.281 [2/6] | 0.214 | 0.598 | 3.14 (hpipm) |
| fleet_grid_box_n4 | 560 | 3.11 | 0.643 [1/6] | 7.24 | 2.85 | 1.09 | 3.79 | 3.47 (piqp) |
| fleet_grid_box_n16 | 2240 | 22.50 | 11.34 | 33.06 | 17.25 | 15.13 | 25.34 | 2.23 (hpipm) |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_box, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.701 | 0.202 | 2.08 | 0.703 [2/6] | 0.232 | 0.623 | 3.08 (hpipm) |
| fleet_grid_box_n4 | 560 | 3.90 | 0.813 | 8.94 | 5.46 | 1.48 | 3.73 | 4.59 (hpipm) |
| fleet_grid_box_n16 | 2240 | 29.46 | 13.21 | 42.41 | 33.39 [1/6] | 19.12 | 26.09 | 1.97 (hpipm) |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_box, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.816 | 0.206 [1/6] | 2.36 | 1.27 [1/6] | 0.274 | 0.570 | 2.08 (piqp) |
| fleet_grid_box_n4 | 560 | 4.58 | 1.04 | 9.88 | 7.83 | 1.76 | 3.76 | 3.60 (hpipm) |
| fleet_grid_box_n16 | 2240 | 34.04 | 16.23 | 46.73 | 69.39 | 23.33 | 24.37 | 1.50 (hpipm) |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.307 (0.423) | 0.082 (0.095) | 1.38 (1.59) | 0.218 (0.232) [8/11] | 0.103 (0.142) [1/11] | 0.021 (0.037) | 0.26 (hpipm) |
| fleet_grid_box_n4 | 560 | 2.11 (2.44) | 0.443 (0.527) [1/11] | 5.19 (6.38) | 1.17 (1.76) | 0.757 (1.03) | 1.01 (1.80) | 1.34 (piqp) |
| fleet_grid_box_n16 | 2240 | 21.95 (25.06) | 8.61 (10.58) | 28.21 (31.55) | 10.31 (20.10) | 14.86 (16.99) | 9.41 (11.84) | 1.09 (hpipm) |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.443 (0.512) | 0.089 (0.102) | 1.62 (1.92) | 0.432 (0.788) | 0.141 (0.181) | 0.023 (0.036) | 0.25 (hpipm) |
| fleet_grid_box_n4 | 560 | 3.04 (3.17) | 0.601 (0.681) | 6.70 (8.52) | 3.83 (6.21) | 1.06 (1.21) | 0.983 (1.78) | 1.63 (hpipm) |
| fleet_grid_box_n16 | 2240 | 27.27 (33.03) | 12.97 (14.83) | 34.28 (43.77) | 25.02 (27.27) [5/11] | 18.74 (24.36) | 9.33 (14.42) | 0.72 (hpipm) |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 140 | 0.548 (0.612) | 0.091 (0.099) [1/11] | 1.94 (2.14) | 0.808 (1.08) [1/11] | 0.175 (0.195) | 0.028 (0.041) | 0.16 (piqp) |
| fleet_grid_box_n4 | 560 | 3.59 (3.84) | 0.736 (0.861) | 7.89 (9.55) | 6.60 (8.92) | 1.23 (1.37) | 0.955 (1.72) | 1.30 (hpipm) |
| fleet_grid_box_n16 | 2240 | 31.84 (37.51) | 13.82 (15.57) | 39.71 (45.83) | 46.71 (79.98) [3/11] | 22.02 (24.40) | 9.32 (14.58) | 0.67 (hpipm) |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 4 / 6 / -- / 7.5 | 5 / 6.5 / -- / 7.5 | 6 / 8.5 / -- / 10 | 25 / 137.5 / -- / 250 | 4 / 5 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_grid_box_n4 | 6 / 8.5 / -- / 10 | 6 / 9 / -- / 11 | 7.5 / 10 / -- / 12 | 100 / 212.5 / -- / 312.5 | 5.5 / 9 / -- / 10 | 55 / 60 / -- / 60 |
| fleet_grid_box_n16 | 6 / 9 / -- / 11 | 7 / 9.5 / -- / 11 | 8 / 11.5 / -- / 13 | 100 / 200 / -- / 487.5 | 7 / 9.5 / -- / 12 | 50 / 50 / -- / 50 |

### fleet_grid_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 4 / 6 / -- / 8 | 6 / 8 / -- / 8 | 8 / 9 / -- / 11 | 25 / 100 / -- / 150 | 4 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| fleet_grid_box_n4 | 6 / 9 / -- / 11 | 7 / 10 / -- / 11 | 9 / 11 / -- / 13 | 50 / 175 / -- / 275 | 6 / 9 / -- / 11 | 40 / 40 / -- / 40 |
| fleet_grid_box_n16 | 8 / 10 / -- / 12 | 8 / 11 / -- / 13 | 10 / 12 / -- / 14 | 75 / 175 / -- / 350 | 8 / 10 / -- / 12 | 50 / 50 / -- / 50 |

### fleet_grid_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_n1 | 0.276 | 0.113 | 0.647 | 0.159 | 0.118 | 0.595 |
| fleet_grid_box_n4 | 1.02 | 0.175 | 2.45 | 0.740 | 0.447 | 2.59 |
| fleet_grid_box_n16 | 4.57 | 0.928 | 10.23 | 4.12 | 1.99 | 16.08 |

## fleet_grid_box_b4

### fleet_grid_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.265 | 0.613 | 0.438 | 0.387 | 0.114 [1/6] | 0.066 | 0.029 | 0.44 (piqp) | 0.07 |
| fleet_grid_box_b4_n4 | 272 | 1.64 | 3.54 | 2.51 | 2.41 | 1.21 | 0.594 | 0.565 | 0.95 (piqp) | 0.22 |
| fleet_grid_box_b4_n16 | 1088 | 15.38 | 19.38 | 14.75 | 14.08 | 9.32 [1/6] | 10.48 | 5.09 | 0.49 (piqp) | 0.35 |
| fleet_grid_box_b4_n64 | 4352 | 296 | 124 | 103 | 99.98 | 241 | 440 | 41.37 | 0.41 (mumblebee_fast_ct) | 0.40 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.337 | 0.873 | 0.644 | 0.538 | 0.339 | 0.077 | 0.028 | 0.36 (piqp) | 0.04 |
| fleet_grid_box_b4_n4 | 272 | 2.24 | 4.78 | 3.33 | 3.23 | 3.46 | 0.880 | 0.598 | 0.68 (piqp) | 0.18 |
| fleet_grid_box_b4_n16 | 1088 | 20.07 | 28.07 | 21.29 | 19.87 | 31.23 [2/6] | 13.77 | 5.14 | 0.37 (piqp) | 0.24 |
| fleet_grid_box_b4_n64 | 4352 | 370 | 166 | 135 | 134 | 644 [1/6] | 714 | 42.20 | 0.31 (mumblebee_fast_ct) | 0.31 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.372 | 1.04 | 0.738 | 0.630 | 0.556 | 0.103 | 0.032 | 0.31 (piqp) | 0.04 |
| fleet_grid_box_b4_n4 | 272 | 2.59 | 5.50 | 4.06 | 3.86 | 5.11 | 0.977 | 0.610 | 0.62 (piqp) | 0.15 |
| fleet_grid_box_b4_n16 | 1088 | 23.54 | 31.67 | 24.34 | 22.60 | 52.62 | 16.43 | 5.07 | 0.31 (piqp) | 0.21 |
| fleet_grid_box_b4_n64 | 4352 | 444 | 190 | 168 | 160 | 936 [1/6] | 520 | 42.15 | 0.26 (mumblebee_fast_ct) | 0.25 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_box_b4, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.191 | 0.469 | 0.298 | 0.304 | 0.102 [1/6] | 0.062 | 0.390 | 6.29 (piqp) | 1.31 |
| fleet_grid_box_b4_n4 | 272 | 0.684 | 1.96 | 1.27 | 1.31 | 0.483 | 0.344 | 2.44 | 7.09 (piqp) | 1.92 |
| fleet_grid_box_b4_n16 | 1088 | 3.07 | 8.10 | 5.82 | 5.90 | 3.05 [1/6] | 1.15 | 10.71 | 9.29 (piqp) | 1.84 |
| fleet_grid_box_b4_n64 | 4352 | 15.30 | 35.93 | 25.98 | 26.41 | 42.30 | 6.52 | 88.82 | 13.62 (piqp) | 3.42 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_box_b4, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.184 | 0.458 | 0.292 | 0.299 | 0.106 | 0.051 | 0.377 | 7.33 (piqp) | 1.29 |
| fleet_grid_box_b4_n4 | 272 | 0.675 | 1.97 | 1.26 | 1.30 | 0.488 | 0.338 | 2.38 | 7.02 (piqp) | 1.89 |
| fleet_grid_box_b4_n16 | 1088 | 3.06 | 8.15 | 5.83 | 5.86 | 3.03 [2/6] | 1.34 | 10.67 | 7.95 (piqp) | 1.83 |
| fleet_grid_box_b4_n64 | 4352 | 15.19 | 36.08 | 25.40 | 26.44 | 40.15 [1/6] | 5.99 | 89.49 | 14.95 (piqp) | 3.52 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_box_b4, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.187 | 0.456 | 0.293 | 0.304 | 0.099 | 0.057 | 0.367 | 6.43 (piqp) | 1.25 |
| fleet_grid_box_b4_n4 | 272 | 0.683 | 1.95 | 1.25 | 1.27 | 0.493 | 0.254 | 2.41 | 9.50 (piqp) | 1.92 |
| fleet_grid_box_b4_n16 | 1088 | 3.14 | 8.11 | 5.80 | 5.89 | 3.08 | 1.01 | 10.63 | 10.49 (piqp) | 1.83 |
| fleet_grid_box_b4_n64 | 4352 | 15.27 | 35.30 | 25.92 | 26.25 | 41.87 [1/6] | 6.46 | 89.36 | 13.84 (piqp) | 3.45 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_box_b4, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.459 | 1.08 | 0.736 | 0.713 | 0.224 [1/6] | 0.126 | 0.419 | 3.33 (piqp) | 0.57 |
| fleet_grid_box_b4_n4 | 272 | 2.31 | 5.47 | 3.79 | 3.71 | 1.69 | 0.938 | 3.01 | 3.21 (piqp) | 0.79 |
| fleet_grid_box_b4_n16 | 1088 | 18.54 | 27.52 | 20.58 | 19.97 | 12.38 [1/6] | 11.65 | 16.03 | 1.38 (piqp) | 0.78 |
| fleet_grid_box_b4_n64 | 4352 | 311 | 160 | 129 | 126 | 283 | 447 | 130 | 1.03 (mumblebee_fast_ct) | 1.00 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_box_b4, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.522 | 1.34 | 0.937 | 0.839 | 0.447 | 0.128 | 0.409 | 3.19 (piqp) | 0.44 |
| fleet_grid_box_b4_n4 | 272 | 2.91 | 6.77 | 4.58 | 4.57 | 3.94 | 1.22 | 2.96 | 2.43 (piqp) | 0.65 |
| fleet_grid_box_b4_n16 | 1088 | 23.13 | 36.19 | 27.00 | 25.70 | 34.25 [2/6] | 15.10 | 15.87 | 1.05 (piqp) | 0.59 |
| fleet_grid_box_b4_n64 | 4352 | 385 | 202 | 161 | 161 | 684 [1/6] | 720 | 132 | 0.82 (mumblebee_fast_ct) | 0.82 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_box_b4, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.563 | 1.49 | 1.02 | 0.931 | 0.657 | 0.161 | 0.400 | 2.48 (piqp) | 0.39 |
| fleet_grid_box_b4_n4 | 272 | 3.26 | 7.45 | 5.33 | 5.13 | 5.61 | 1.23 | 3.05 | 2.48 (piqp) | 0.57 |
| fleet_grid_box_b4_n16 | 1088 | 26.69 | 39.82 | 30.09 | 28.44 | 55.77 | 17.45 | 15.70 | 0.90 (piqp) | 0.52 |
| fleet_grid_box_b4_n64 | 4352 | 460 | 224 | 194 | 187 | 978 [1/6] | 526 | 131 | 0.70 (mumblebee_fast_ct) | 0.68 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.282 (0.333) | 0.785 (0.928) | 0.574 (0.656) | 0.499 (0.578) | 0.109 (0.119) [1/11] | 0.068 (0.094) | 0.020 (0.028) | 0.29 (piqp) | 0.03 |
| fleet_grid_box_b4_n4 | 272 | 1.72 (2.14) | 4.14 (5.06) | 2.99 (3.69) | 2.78 (3.44) | 1.01 (1.32) | 0.634 (0.813) | 0.581 (1.49) | 0.92 (piqp) | 0.19 |
| fleet_grid_box_b4_n16 | 1088 | 18.71 (20.99) | 23.63 (26.51) | 18.23 (20.10) | 17.12 (19.73) | 4.77 (7.26) [5/11] | 12.32 (13.27) | 4.01 (7.56) | 0.33 (piqp) | 0.22 |
| fleet_grid_box_b4_n64 | 4352 | 333 (406) | 158 (177) | 131 (145) | 126 (142) | 120 (352) | 423 (501) | 43.36 (104) | 0.36 (osqp) | 0.33 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.330 (0.399) | 0.903 (1.10) | 0.711 (0.840) | 0.570 (0.689) | 0.273 (0.443) | 0.089 (0.112) | 0.019 (0.027) | 0.21 (piqp) | 0.03 |
| fleet_grid_box_b4_n4 | 272 | 2.38 (2.59) | 5.12 (5.99) | 3.69 (4.25) | 3.48 (4.08) | 2.23 (4.56) [1/11] | 0.892 (0.992) | 0.543 (1.45) | 0.61 (piqp) | 0.15 |
| fleet_grid_box_b4_n16 | 1088 | 22.72 (27.62) | 29.33 (36.15) | 21.98 (27.18) | 21.55 (26.61) | 29.72 (35.38) [2/11] | 14.48 (17.22) | 4.04 (7.97) | 0.28 (piqp) | 0.18 |
| fleet_grid_box_b4_n64 | 4352 | 442 (555) | 209 (227) | 171 (187) | 167 (183) | 481 (565) | 525 (614) | 43.85 (107) | 0.26 (mumblebee_fast_ct) | 0.26 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 68 | 0.392 (0.431) | 1.09 (1.23) | 0.840 (0.919) | 0.684 (0.753) | 0.429 (0.655) [1/11] | 0.119 (0.134) | 0.023 (0.031) | 0.20 (piqp) | 0.03 |
| fleet_grid_box_b4_n4 | 272 | 2.75 (2.99) | 5.98 (6.93) | 4.29 (4.93) | 4.08 (4.75) | 3.77 (5.34) | 1.03 (1.07) | 0.507 (1.43) | 0.49 (piqp) | 0.12 |
| fleet_grid_box_b4_n16 | 1088 | 26.54 (32.27) | 34.62 (39.11) | 25.97 (29.95) | 24.89 (29.09) | 50.74 (69.58) | 17.31 (20.30) | 4.01 (7.98) | 0.23 (piqp) | 0.15 |
| fleet_grid_box_b4_n64 | 4352 | 514 (624) | 225 (260) | 188 (217) | 184 (212) | 930 (1720) [1/11] | 631 (726) | 42.34 (109) | 0.23 (mumblebee_fast_ct) | 0.23 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_box_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 5 / 6.5 / -- / 8 | 6 / 8.5 / -- / 10 | 6 / 8.5 / -- / 10 | 6 / 8.5 / -- / 10 | 50 / 125 / -- / 225 | 4 / 5 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_grid_box_b4_n4 | 6 / 9 / -- / 11 | 7.5 / 10 / -- / 12 | 7.5 / 10 / -- / 12 | 7.5 / 10 / -- / 12 | 87.5 / 262.5 / -- / 400 | 5.5 / 9 / -- / 10.5 | 22.5 / 22.5 / -- / 22.5 |
| fleet_grid_box_b4_n16 | 7 / 9.5 / -- / 11.5 | 8 / 11.5 / -- / 13 | 8 / 11.5 / -- / 13 | 8 / 11.5 / -- / 13 | 100 / 312.5 / -- / 537.5 | 7 / 9.5 / -- / 11.5 | 50 / 50 / -- / 50 |
| fleet_grid_box_b4_n64 | 7 / 9 / -- / 11 | 8 / 10.5 / -- / 12.5 | 8 / 10.5 / -- / 12.5 | 8 / 10.5 / -- / 12.5 | 250 / 500 / -- / 850 | 8 / 10 / -- / 11.5 | 75 / 75 / -- / 75 |

### fleet_grid_box_b4, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 6 / 7 / -- / 9 | 8 / 9 / -- / 11 | 8 / 9 / -- / 11 | 8 / 9 / -- / 11 | 50 / 100 / -- / 200 | 4 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| fleet_grid_box_b4_n4 | 7 / 10 / -- / 12 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 9 / 11 / -- / 13 | 75 / 175 / -- / 300 | 6 / 9 / -- / 11 | 20 / 20 / -- / 20 |
| fleet_grid_box_b4_n16 | 9 / 11 / -- / 13 | 10 / 12 / -- / 14 | 10 / 12 / -- / 14 | 10 / 12 / -- / 14 | 50 / 275 / -- / 525 | 8 / 10 / -- / 12 | 40 / 40 / -- / 40 |
| fleet_grid_box_b4_n64 | 8 / 11 / -- / 13 | 10 / 13 / -- / 14 | 10 / 13 / -- / 14 | 10 / 13 / -- / 14 | 150 / 475 / -- / 1050 | 9 / 11 / -- / 13 | 80 / 80 / -- / 80 |

### fleet_grid_box_b4, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_box_b4_n1 | 0.184 | 0.458 | 0.292 | 0.299 | 0.106 | 0.051 | 0.377 |
| fleet_grid_box_b4_n4 | 0.675 | 1.97 | 1.26 | 1.30 | 0.488 | 0.338 | 2.38 |
| fleet_grid_box_b4_n16 | 3.06 | 8.15 | 5.83 | 5.86 | 3.03 | 1.34 | 10.67 |
| fleet_grid_box_b4_n64 | 15.19 | 36.08 | 25.40 | 26.44 | 40.28 | 5.99 | 89.49 |

## fleet_grid_soc

### fleet_grid_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.437 | 0.807 | 0.708 | 0.142 | 0.33 (clarabel) | 0.20 |
| fleet_grid_soc_n4 | 560 | 2.87 | 4.67 | 4.38 | 2.16 | 0.75 (clarabel) | 0.49 |
| fleet_grid_soc_n16 | 2240 | 41.30 | 35.98 | 34.64 | 21.17 | 0.61 (mumblebee_fast) | 0.61 |
| fleet_grid_soc_n64 | 8960 | 603 | 270 | n/a | 365 | 1.35 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.609 | 1.09 | 0.975 | 0.184 | 0.30 (clarabel) | 0.19 |
| fleet_grid_soc_n4 | 560 | 4.57 | 6.86 | 6.16 | 2.51 | 0.55 (clarabel) | 0.41 |
| fleet_grid_soc_n16 | 2240 | 63.22 | 52.16 | 48.93 | 25.18 | 0.51 (mumblebee_fast) | 0.51 |
| fleet_grid_soc_n64 | 8960 | 902 | 396 | n/a | 403 | 1.02 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.729 | 1.23 | 1.09 | 0.191 | 0.26 (clarabel) | 0.17 |
| fleet_grid_soc_n4 | 560 | 5.63 | 8.36 | 7.65 | 2.81 | 0.50 (clarabel) | 0.37 |
| fleet_grid_soc_n16 | 2240 | 78.88 | 62.08 | 58.64 | 26.78 | 0.46 (mumblebee_fast) | 0.46 |
| fleet_grid_soc_n64 | 8960 | 1199 | 521 | n/a | 423 | 0.81 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.740 | 1.32 | 1.19 | 0.193 | 0.26 (clarabel) | 0.16 |
| fleet_grid_soc_n4 | 560 | 5.97 | 9.13 | 8.19 | 2.89 | 0.48 (clarabel) | 0.35 |
| fleet_grid_soc_n16 | 2240 | 85.82 | 67.50 | 62.80 | 26.84 | 0.43 (mumblebee_fast) | 0.43 |
| fleet_grid_soc_n64 | 8960 | 1323 | 574 | n/a | 426 | 0.74 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.325 | 0.546 | 0.405 | 0.600 | 1.84 (clarabel) | 1.48 |
| fleet_grid_soc_n4 | 560 | 1.20 | 2.18 | 1.43 | 3.97 | 3.30 (clarabel) | 2.77 |
| fleet_grid_soc_n16 | 2240 | 5.84 | 9.30 | 6.46 | 26.32 | 4.50 (clarabel) | 4.08 |
| fleet_grid_soc_n64 | 8960 | 26.76 | 38.40 | n/a | 209 | 7.83 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.315 | 0.552 | 0.356 | 0.599 | 1.90 (clarabel) | 1.68 |
| fleet_grid_soc_n4 | 560 | 1.24 | 2.13 | 1.36 | 3.90 | 3.15 (clarabel) | 2.87 |
| fleet_grid_soc_n16 | 2240 | 5.94 | 9.55 | 6.51 | 26.26 | 4.42 (clarabel) | 4.03 |
| fleet_grid_soc_n64 | 8960 | 26.52 | 38.55 | n/a | 209 | 7.86 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.344 | 0.541 | 0.330 | 0.576 | 1.75 (mumblebee_fast) | 1.75 |
| fleet_grid_soc_n4 | 560 | 1.26 | 2.13 | 1.37 | 3.95 | 3.14 (clarabel) | 2.88 |
| fleet_grid_soc_n16 | 2240 | 5.86 | 9.55 | 6.43 | 26.26 | 4.48 (clarabel) | 4.08 |
| fleet_grid_soc_n64 | 8960 | 26.57 | 38.35 | n/a | 208 | 7.84 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.330 | 0.558 | 0.323 | 0.571 | 1.77 (mumblebee_fast) | 1.77 |
| fleet_grid_soc_n4 | 560 | 1.25 | 2.14 | 1.34 | 3.97 | 3.19 (clarabel) | 2.97 |
| fleet_grid_soc_n16 | 2240 | 6.29 | 9.56 | 6.40 | 26.26 | 4.18 (clarabel) | 4.10 |
| fleet_grid_soc_n64 | 8960 | 26.85 | 38.03 | n/a | 208 | 7.76 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.762 | 1.49 | 1.17 | 0.756 | 0.99 (clarabel) | 0.64 |
| fleet_grid_soc_n4 | 560 | 4.07 | 6.96 | 5.98 | 6.13 | 1.51 (clarabel) | 1.03 |
| fleet_grid_soc_n16 | 2240 | 47.09 | 45.17 | 41.10 | 47.56 | 1.16 (mumblebee_fast) | 1.16 |
| fleet_grid_soc_n64 | 8960 | 630 | 308 | n/a | 574 | 1.86 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.924 | 1.63 | 1.32 | 0.790 | 0.86 (clarabel) | 0.60 |
| fleet_grid_soc_n4 | 560 | 5.84 | 9.01 | 7.52 | 6.40 | 1.10 (clarabel) | 0.85 |
| fleet_grid_soc_n16 | 2240 | 69.18 | 61.89 | 55.44 | 51.73 | 0.93 (mumblebee_fast) | 0.93 |
| fleet_grid_soc_n64 | 8960 | 929 | 435 | n/a | 614 | 1.41 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 1.07 | 1.77 | 1.42 | 0.765 | 0.71 (clarabel) | 0.54 |
| fleet_grid_soc_n4 | 560 | 6.89 | 10.67 | 9.05 | 6.84 | 0.99 (clarabel) | 0.76 |
| fleet_grid_soc_n16 | 2240 | 84.83 | 71.60 | 65.09 | 53.49 | 0.82 (mumblebee_fast) | 0.82 |
| fleet_grid_soc_n64 | 8960 | 1226 | 560 | n/a | 630 | 1.13 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 1.08 | 1.90 | 1.51 | 0.764 | 0.71 (clarabel) | 0.50 |
| fleet_grid_soc_n4 | 560 | 7.19 | 11.29 | 9.54 | 7.00 | 0.97 (clarabel) | 0.73 |
| fleet_grid_soc_n16 | 2240 | 92.13 | 77.07 | 69.18 | 53.08 | 0.77 (mumblebee_fast) | 0.77 |
| fleet_grid_soc_n64 | 8960 | 1349 | 612 | n/a | 634 | 1.04 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.430 (0.522) | 0.962 (0.973) | 0.859 (0.867) | 0.156 (0.231) | 0.36 (clarabel) | 0.18 |
| fleet_grid_soc_n4 | 560 | 2.89 (3.39) | 5.96 (6.70) | 5.37 (6.08) | 1.89 (3.25) | 0.65 (clarabel) | 0.35 |
| fleet_grid_soc_n16 | 2240 | 45.15 (53.68) | 36.03 (46.58) | 34.07 (44.27) | 17.71 (31.57) | 0.52 (mumblebee_fast) | 0.52 |
| fleet_grid_soc_n64 | 8960 | 672 (770) | 333 (336) | n/a | 356 (553) | 1.07 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.614 (0.705) | 1.10 (1.23) | 0.971 (1.09) | 0.227 (0.266) | 0.37 (clarabel) | 0.23 |
| fleet_grid_soc_n4 | 560 | 4.50 (5.00) | 8.21 (9.69) | 7.42 (8.84) | 2.06 (3.63) | 0.46 (clarabel) | 0.28 |
| fleet_grid_soc_n16 | 2240 | 67.83 (84.32) | 53.37 (57.71) | 49.43 (54.21) | 22.59 (32.13) | 0.46 (mumblebee_fast) | 0.46 |
| fleet_grid_soc_n64 | 8960 | 954 (1048) | 454 (498) | n/a | 413 (601) | 0.91 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.717 (0.812) | 1.25 (1.39) | 1.09 (1.20) | 0.233 (0.272) | 0.32 (clarabel) | 0.21 |
| fleet_grid_soc_n4 | 560 | 5.57 (6.14) | 9.02 (11.95) | 8.20 (10.69) | 2.43 (3.60) | 0.44 (clarabel) | 0.30 |
| fleet_grid_soc_n16 | 2240 | 82.29 (89.07) | 62.99 (67.64) | 57.54 (62.42) | 24.21 (31.17) | 0.42 (mumblebee_fast) | 0.42 |
| fleet_grid_soc_n64 | 8960 | 1161 (1257) | 533 (614) | n/a | 413 (619) | 0.77 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 140 | 0.807 (0.819) | 1.35 (1.50) | 1.22 (1.33) | 0.230 (0.277) | 0.28 (clarabel) | 0.19 |
| fleet_grid_soc_n4 | 560 | 5.72 (6.21) | 9.82 (12.66) | 8.82 (11.41) | 2.44 (3.52) | 0.43 (clarabel) | 0.28 |
| fleet_grid_soc_n16 | 2240 | 88.66 (97.86) [2/11] | 67.63 (72.22) | 61.60 (66.80) | 24.25 (33.14) | 0.39 (mumblebee_fast) | 0.39 |
| fleet_grid_soc_n64 | 8960 | 1246 (1350) | 574 (655) | n/a | 664 (1246) | 1.16 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 4 / 6 / 7 / 7 | 6 / 9 / 10 / 10.5 | 6 / 9 / 10 / 10.5 | 20 / 20 / 20 / 20 |
| fleet_grid_soc_n4 | 5 / 8 / 10 / 11 | 7 / 10 / 12 / 13 | 7 / 10 / 12 / 13 | 40 / 40 / 40 / 40 |
| fleet_grid_soc_n16 | 5 / 8 / 10 / 11 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 70 / 70 / 70 / 70 |
| fleet_grid_soc_n64 | 5 / 8 / 11 / 12 | 7.5 / 10.5 / 13.5 / 15 | n/a | 150 / 150 / 150 / 150 |

### fleet_grid_soc, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 4 / 6 / 7 / 8 | 8 / 9 / 10 / 11 | 8 / 9 / 10 / 11 | 20 / 20 / 20 / 20 |
| fleet_grid_soc_n4 | 5 / 8 / 10 / 10 | 9 / 12 / 13 / 14 | 9 / 12 / 13 / 14 | 30 / 30 / 30 / 30 |
| fleet_grid_soc_n16 | 5 / 8 / 10 / 11 | 8 / 11 / 13 / 14 | 8 / 11 / 13 / 14 | 30 / 30 / 30 / 30 |
| fleet_grid_soc_n64 | 6 / 9 / 11 / 12 | 9 / 12 / 14 / 15 | n/a | 80 / 120 / 120 / 120 |

### fleet_grid_soc, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | mumblebee | mumblebee_fast | sheafmpc |
|---|---:|---:|---:|---:|
| fleet_grid_soc_n1 | 0.315 | 0.552 | 0.356 | 0.599 |
| fleet_grid_soc_n4 | 1.24 | 2.13 | 1.36 | 3.90 |
| fleet_grid_soc_n16 | 5.94 | 9.55 | 6.51 | 26.26 |
| fleet_grid_soc_n64 | 26.52 | 38.55 | -- | 209 |

## fleet_grid_soc_b4

### fleet_grid_soc_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.340 | 0.501 | 0.429 | 0.100 | 0.29 (clarabel) | 0.23 |
| fleet_grid_soc_b4_n4 | 272 | 2.52 | 3.20 | 2.92 | 1.41 | 0.56 (clarabel) | 0.48 |
| fleet_grid_soc_b4_n16 | 1088 | 44.80 | 23.10 | 23.10 | 11.09 | 0.48 (mumblebee) | 0.48 |
| fleet_grid_soc_b4_n64 | 4352 | 894 | 253 | n/a | 203 | 0.80 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.522 | 0.742 | 0.648 | 0.135 | 0.26 (clarabel) | 0.21 |
| fleet_grid_soc_b4_n4 | 272 | 3.97 | 4.67 | 4.21 | 1.62 | 0.41 (clarabel) | 0.38 |
| fleet_grid_soc_b4_n16 | 1088 | 64.82 | 32.54 | 34.75 | 14.51 | 0.45 (mumblebee) | 0.42 |
| fleet_grid_soc_b4_n64 | 4352 | 1315 | 361 | n/a | 239 | 0.66 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc_b4, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.623 | 0.867 | 0.737 | 0.136 | 0.22 (clarabel) | 0.19 |
| fleet_grid_soc_b4_n4 | 272 | 4.63 | 5.48 | 5.14 | 1.86 | 0.40 (clarabel) | 0.36 |
| fleet_grid_soc_b4_n16 | 1088 | 77.52 | 38.71 | 37.84 | 14.53 | 0.38 (mumblebee_fast) | 0.38 |
| fleet_grid_soc_b4_n64 | 4352 | 1765 | 470 | n/a | 245 | 0.52 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.609 | 0.897 | 0.759 | 0.134 | 0.22 (clarabel) | 0.18 |
| fleet_grid_soc_b4_n4 | 272 | 4.69 | 5.99 | 5.49 | 1.84 | 0.39 (clarabel) | 0.34 |
| fleet_grid_soc_b4_n16 | 1088 | 89.32 | 41.71 | 40.91 | 15.33 | 0.37 (mumblebee_fast) | 0.37 |
| fleet_grid_soc_b4_n64 | 4352 | 1789 | 543 | n/a | 270 | 0.50 (mumblebee) | -- |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_grid_soc_b4, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.237 | 0.424 | 0.266 | 0.438 | 1.84 (clarabel) | 1.64 |
| fleet_grid_soc_b4_n4 | 272 | 0.890 | 1.63 | 1.19 | 2.50 | 2.80 (clarabel) | 2.10 |
| fleet_grid_soc_b4_n16 | 1088 | 4.22 | 7.29 | 6.33 | 17.01 | 4.03 (clarabel) | 2.69 |
| fleet_grid_soc_b4_n64 | 4352 | 24.93 | 33.83 | n/a | 145 | 5.80 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc_b4, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.247 | 0.446 | 0.296 | 0.437 | 1.77 (clarabel) | 1.47 |
| fleet_grid_soc_b4_n4 | 272 | 0.915 | 1.70 | 1.15 | 2.53 | 2.76 (clarabel) | 2.19 |
| fleet_grid_soc_b4_n16 | 1088 | 4.42 | 7.36 | 6.85 | 16.57 | 3.75 (clarabel) | 2.42 |
| fleet_grid_soc_b4_n64 | 4352 | 25.60 | 33.69 | n/a | 144 | 5.62 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc_b4, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.226 | 0.413 | 0.275 | 0.413 | 1.83 (clarabel) | 1.50 |
| fleet_grid_soc_b4_n4 | 272 | 0.918 | 1.67 | 1.18 | 2.54 | 2.77 (clarabel) | 2.16 |
| fleet_grid_soc_b4_n16 | 1088 | 4.48 | 7.33 | 6.40 | 16.72 | 3.74 (clarabel) | 2.61 |
| fleet_grid_soc_b4_n64 | 4352 | 26.50 | 33.52 | n/a | 149 | 5.63 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc_b4, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.233 | 0.404 | 0.287 | 0.423 | 1.82 (clarabel) | 1.47 |
| fleet_grid_soc_b4_n4 | 272 | 0.870 | 1.74 | 1.19 | 2.52 | 2.89 (clarabel) | 2.12 |
| fleet_grid_soc_b4_n16 | 1088 | 4.59 | 7.35 | 6.47 | 16.47 | 3.59 (clarabel) | 2.54 |
| fleet_grid_soc_b4_n64 | 4352 | 24.85 | 34.21 | n/a | 159 | 6.38 (clarabel) | -- |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_grid_soc_b4, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.590 | 0.938 | 0.702 | 0.543 | 0.92 (clarabel) | 0.77 |
| fleet_grid_soc_b4_n4 | 272 | 3.41 | 4.82 | 4.10 | 3.89 | 1.14 (clarabel) | 0.95 |
| fleet_grid_soc_b4_n16 | 1088 | 49.02 | 30.17 | 29.30 | 28.03 | 0.96 (mumblebee_fast) | 0.96 |
| fleet_grid_soc_b4_n64 | 4352 | 919 | 287 | n/a | 348 | 1.21 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc_b4, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.773 | 1.19 | 0.931 | 0.566 | 0.73 (clarabel) | 0.61 |
| fleet_grid_soc_b4_n4 | 272 | 4.89 | 6.39 | 5.38 | 4.16 | 0.85 (clarabel) | 0.77 |
| fleet_grid_soc_b4_n16 | 1088 | 69.29 | 39.91 | 41.66 | 31.46 | 0.79 (mumblebee) | 0.76 |
| fleet_grid_soc_b4_n64 | 4352 | 1341 | 394 | n/a | 382 | 0.97 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc_b4, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.849 | 1.28 | 1.02 | 0.553 | 0.65 (clarabel) | 0.54 |
| fleet_grid_soc_b4_n4 | 272 | 5.55 | 7.17 | 6.33 | 4.38 | 0.79 (clarabel) | 0.69 |
| fleet_grid_soc_b4_n16 | 1088 | 81.80 | 46.04 | 44.18 | 31.05 | 0.70 (mumblebee_fast) | 0.70 |
| fleet_grid_soc_b4_n64 | 4352 | 1791 | 504 | n/a | 394 | 0.78 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc_b4, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.840 | 1.31 | 1.05 | 0.559 | 0.67 (clarabel) | 0.53 |
| fleet_grid_soc_b4_n4 | 272 | 5.56 | 7.75 | 6.63 | 4.34 | 0.78 (clarabel) | 0.65 |
| fleet_grid_soc_b4_n16 | 1088 | 93.78 | 48.29 | 47.30 | 31.80 | 0.67 (mumblebee_fast) | 0.67 |
| fleet_grid_soc_b4_n64 | 4352 | 1814 | 577 | n/a | 435 | 0.75 (mumblebee) | -- |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_grid_soc_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.388 (0.461) | 0.629 (0.649) | 0.562 (0.583) | 0.122 (0.233) | 0.31 (clarabel) | 0.22 |
| fleet_grid_soc_b4_n4 | 272 | 2.79 (3.23) | 4.02 (4.56) | 3.76 (4.25) | 1.12 (2.24) | 0.40 (clarabel) | 0.30 |
| fleet_grid_soc_b4_n16 | 1088 | 50.97 (57.97) | 23.04 (29.34) | 23.64 (30.05) | 9.46 (25.39) | 0.41 (mumblebee) | 0.40 |
| fleet_grid_soc_b4_n64 | 4352 | 1048 (1164) | 305 (310) | n/a | 185 (404) | 0.61 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.496 (0.581) | 0.770 (0.899) | 0.660 (0.744) | 0.161 (0.271) | 0.33 (clarabel) | 0.24 |
| fleet_grid_soc_b4_n4 | 272 | 4.11 (4.53) | 5.42 (6.38) | 4.96 (5.74) | 1.44 (3.04) | 0.35 (clarabel) | 0.29 |
| fleet_grid_soc_b4_n16 | 1088 | 71.02 (77.45) | 32.42 (35.55) | 33.21 (35.41) | 12.44 (62.17) | 0.38 (mumblebee) | 0.37 |
| fleet_grid_soc_b4_n64 | 4352 | 1556 (1814) | 412 (456) | n/a | 239 (467) | 0.58 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc_b4, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.587 (0.715) | 0.850 (0.930) | 0.725 (0.804) | 0.163 (0.410) | 0.28 (clarabel) | 0.23 |
| fleet_grid_soc_b4_n4 | 272 | 4.54 (6.00) | 5.92 (7.67) | 5.42 (7.02) | 1.37 (2.87) | 0.30 (clarabel) | 0.25 |
| fleet_grid_soc_b4_n16 | 1088 | 79.62 (84.79) | 38.56 (41.24) | 37.64 (40.53) | 13.04 (69.18) | 0.35 (mumblebee_fast) | 0.35 |
| fleet_grid_soc_b4_n64 | 4352 | 1906 (2052) | 489 (563) | n/a | 255 (513) | 0.52 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_grid_soc_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc_b4_n1 | 68 | 0.656 (0.729) | 0.912 (0.994) | 0.804 (0.898) | 0.161 (1.10) | 0.25 (clarabel) | 0.20 |
| fleet_grid_soc_b4_n4 | 272 | 4.88 (6.35) | 6.37 (8.22) | 6.00 (7.72) | 1.65 (3.01) | 0.34 (clarabel) | 0.27 |
| fleet_grid_soc_b4_n16 | 1088 | 98.35 (105) [1/11] | 41.87 (45.23) | 40.51 (43.58) | 14.35 (89.53) | 0.35 (mumblebee_fast) | 0.35 |
| fleet_grid_soc_b4_n64 | 4352 | 1724 (1846) | 536 (609) | n/a | 274 (586) | 0.51 (mumblebee) | -- |

Warm cells: median (max) ms of update + warm start + solve.

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
| fleet_grid_soc_b4_n1 | 0.247 | 0.446 | 0.296 | 0.437 |
| fleet_grid_soc_b4_n4 | 0.915 | 1.70 | 1.15 | 2.53 |
| fleet_grid_soc_b4_n16 | 4.42 | 7.36 | 6.85 | 16.57 |
| fleet_grid_soc_b4_n64 | 25.60 | 33.69 | -- | 144 |

## fleet_ring_box

### fleet_ring_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.306 | 0.067 | 0.976 | 0.233 [1/6] | 0.091 | 0.041 | 0.61 (hpipm) |
| fleet_ring_box_n4 | 560 | 2.08 | 0.534 | 4.50 | 1.17 [1/6] | 0.731 [1/6] | 1.06 | 1.99 (hpipm) |
| fleet_ring_box_n16 | 2240 | 14.07 | 9.05 [1/6] | 21.30 | 8.05 [2/6] | 6.50 | 6.90 | 1.06 (piqp) |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.421 | 0.079 | 1.20 | 0.446 | 0.114 | 0.041 | 0.52 (hpipm) |
| fleet_ring_box_n4 | 560 | 2.69 | 0.631 | 5.66 | 5.23 | 0.997 | 1.13 | 1.79 (hpipm) |
| fleet_ring_box_n16 | 2240 | 19.37 | 11.82 | 28.82 | 21.62 [1/6] | 8.91 | 6.98 | 0.78 (piqp) |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.466 | 0.083 | 1.44 | 0.809 | 0.141 | 0.046 | 0.56 (hpipm) |
| fleet_ring_box_n4 | 560 | 3.26 | 0.686 | 6.79 | 10.88 | 1.22 | 1.14 | 1.66 (hpipm) |
| fleet_ring_box_n16 | 2240 | 23.08 | 13.55 [1/6] | 33.82 | 52.75 [1/6] | 10.32 | 6.97 | 0.67 (piqp) |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box, setup, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.262 | 0.096 | 0.577 | 0.139 [1/6] | 0.111 | 0.508 | 5.27 (hpipm) |
| fleet_ring_box_n4 | 560 | 0.981 | 0.172 | 2.26 | 0.670 [1/6] | 0.368 [1/6] | 2.41 | 14.00 (hpipm) |
| fleet_ring_box_n16 | 2240 | 3.61 | 1.76 [1/6] | 8.95 | 2.91 [2/6] | 1.35 | 9.06 | 6.73 (piqp) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.258 | 0.096 | 0.555 | 0.140 | 0.106 | 0.512 | 5.32 (hpipm) |
| fleet_ring_box_n4 | 560 | 0.962 | 0.172 | 2.26 | 0.672 | 0.372 | 2.40 | 13.98 (hpipm) |
| fleet_ring_box_n16 | 2240 | 3.63 | 1.76 | 8.89 | 2.95 [1/6] | 1.34 | 8.98 | 6.72 (piqp) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box, setup, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.251 | 0.096 | 0.560 | 0.140 | 0.104 | 0.508 | 5.29 (hpipm) |
| fleet_ring_box_n4 | 560 | 0.971 | 0.171 | 2.25 | 0.675 | 0.444 | 2.39 | 13.97 (hpipm) |
| fleet_ring_box_n16 | 2240 | 3.62 | 1.78 [1/6] | 8.87 | 2.86 [1/6] | 1.44 | 9.01 | 6.25 (piqp) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.575 | 0.162 | 1.55 | 0.375 [1/6] | 0.201 | 0.570 | 3.52 (hpipm) |
| fleet_ring_box_n4 | 560 | 3.08 | 0.707 | 6.79 | 1.84 [1/6] | 1.10 [1/6] | 3.47 | 4.91 (hpipm) |
| fleet_ring_box_n16 | 2240 | 17.72 | 10.78 [1/6] | 30.23 | 10.96 [2/6] | 7.84 | 15.92 | 2.03 (piqp) |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.685 | 0.175 | 1.75 | 0.588 | 0.220 | 0.553 | 3.16 (hpipm) |
| fleet_ring_box_n4 | 560 | 3.65 | 0.800 | 7.94 | 5.90 | 1.36 | 3.54 | 4.42 (hpipm) |
| fleet_ring_box_n16 | 2240 | 22.99 | 13.57 | 37.70 | 24.61 [1/6] | 10.24 | 16.01 | 1.56 (piqp) |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.715 | 0.179 | 2.00 | 0.951 | 0.245 | 0.560 | 3.13 (hpipm) |
| fleet_ring_box_n4 | 560 | 4.23 | 0.860 | 9.04 | 11.55 | 1.66 | 3.53 | 4.10 (hpipm) |
| fleet_ring_box_n16 | 2240 | 26.71 | 15.35 [1/6] | 42.69 | 55.61 [1/6] | 11.76 | 16.06 | 1.37 (piqp) |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.348 (0.406) | 0.070 (0.082) | 1.08 (1.39) | 0.114 (0.121) | 0.099 (0.113) | 0.023 (0.167) | 0.32 (hpipm) |
| fleet_ring_box_n4 | 560 | 2.10 (2.40) | 0.484 (0.543) | 5.00 (5.06) | 1.10 (1.63) [4/11] | 0.787 (0.848) [1/11] | 0.912 (1.34) | 1.89 (hpipm) |
| fleet_ring_box_n16 | 2240 | 15.67 (17.43) | 8.62 (9.95) [1/11] | 23.96 (26.51) | 8.14 (8.32) [3/11] | 6.95 (8.42) | 6.64 (10.93) | 0.96 (piqp) |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.408 (0.519) | 0.076 (0.111) | 1.36 (1.69) | 0.333 (0.743) | 0.126 (0.167) | 0.022 (0.165) | 0.30 (hpipm) |
| fleet_ring_box_n4 | 560 | 2.92 (3.20) | 0.546 (0.641) | 6.24 (6.91) | 4.66 (5.70) | 1.03 (1.15) | 0.870 (1.29) | 1.59 (hpipm) |
| fleet_ring_box_n16 | 2240 | 19.36 (21.25) | 11.00 (11.93) | 31.44 (34.09) | 21.21 (30.31) [6/11] | 9.64 (10.77) | 6.66 (10.90) | 0.69 (piqp) |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 140 | 0.501 (0.627) | 0.083 (0.131) | 1.69 (1.87) | 1.09 (1.29) | 0.147 (0.175) | 0.029 (0.166) | 0.35 (hpipm) |
| fleet_ring_box_n4 | 560 | 3.41 (3.74) | 0.653 (0.781) | 7.36 (8.07) | 6.70 (11.30) | 1.25 (1.45) | 0.881 (1.34) | 1.35 (hpipm) |
| fleet_ring_box_n16 | 2240 | 23.05 (24.86) | 12.78 (13.74) [1/11] | 36.09 (38.99) | 38.89 (109) [4/11] | 10.60 (11.97) | 6.73 (11.05) | 0.64 (piqp) |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 4 / 6 / -- / 7 | 5 / 6.5 / -- / 7 | 6.5 / 8 / -- / 9.5 | 62.5 / 100 / -- / 162.5 | 4 / 5.5 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_ring_box_n4 | 6 / 8 / -- / 10 | 7.5 / 9 / -- / 10 | 8 / 10 / -- / 12 | 50 / 200 / -- / 537.5 | 6 / 8 / -- / 10 | 50 / 50 / -- / 50 |
| fleet_ring_box_n16 | 7 / 10 / -- / 12 | 7 / 10 / -- / 12 | 9 / 12 / -- / 14 | 75 / 225 / -- / 500 | 7.5 / 10 / -- / 12 | 60 / 60 / -- / 60 |

### fleet_ring_box, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 5 / 6 / -- / 8 | 6 / 7 / -- / 8 | 7 / 9 / -- / 11 | 25 / 75 / -- / 250 | 4 / 6 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_ring_box_n4 | 6 / 9 / -- / 11 | 8 / 9 / -- / 11 | 9 / 11 / -- / 13 | 50 / 200 / -- / 325 | 6 / 8 / -- / 10 | 30 / 30 / -- / 30 |
| fleet_ring_box_n16 | 8 / 10 / -- / 12 | 8 / 11 / -- / 13 | 10 / 13 / -- / 15 | 75 / 200 / -- / 350 | 8 / 11 / -- / 12 | 60 / 60 / -- / 60 |

### fleet_ring_box, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_n1 | 0.258 | 0.096 | 0.555 | 0.140 | 0.106 | 0.512 |
| fleet_ring_box_n4 | 0.962 | 0.172 | 2.26 | 0.672 | 0.372 | 2.40 |
| fleet_ring_box_n16 | 3.63 | 1.76 | 8.89 | 2.94 | 1.34 | 8.98 |

## fleet_ring_box_b4

### fleet_ring_box_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.253 | 0.651 | 0.475 | 0.399 | 0.112 [1/6] | 0.065 | 0.042 | 0.64 (piqp) | 0.09 |
| fleet_ring_box_b4_n4 | 272 | 1.68 | 3.63 | 2.63 | 2.44 | 1.28 | 0.591 [1/6] | 0.557 | 0.43 (osqp) | 0.21 |
| fleet_ring_box_b4_n16 | 1088 | 12.01 | 18.72 | 13.41 | 12.49 | 11.14 | 7.09 | 4.24 | 0.60 (piqp) | 0.32 |
| fleet_ring_box_b4_n64 | 4352 | 65.47 | 76.04 | 55.71 | 51.10 | 79.67 | 47.52 | 20.93 | 0.44 (piqp) | 0.38 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.309 | 0.778 | 0.584 | 0.516 | 0.225 | 0.077 | 0.035 | 0.46 (piqp) | 0.06 |
| fleet_ring_box_b4_n4 | 272 | 2.11 | 4.48 | 3.13 | 2.97 | 4.80 | 0.759 | 0.594 | 0.78 (piqp) | 0.19 |
| fleet_ring_box_b4_n16 | 1088 | 15.88 | 25.16 | 17.71 | 16.60 | 35.23 [2/6] | 9.31 | 4.35 | 0.47 (piqp) | 0.25 |
| fleet_ring_box_b4_n64 | 4352 | 91.52 | 102 | 73.66 | 68.31 | 194 | 56.55 | 22.93 | 0.41 (piqp) | 0.31 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.353 | 0.967 | 0.695 | 0.622 | 0.381 | 0.093 | 0.039 | 0.42 (piqp) | 0.06 |
| fleet_ring_box_b4_n4 | 272 | 2.47 | 5.30 | 3.70 | 3.46 | 7.46 | 0.864 | 0.653 | 0.76 (piqp) | 0.18 |
| fleet_ring_box_b4_n16 | 1088 | 18.90 | 29.24 | 20.69 | 19.35 | 49.46 | 10.71 | 4.41 | 0.41 (piqp) | 0.21 |
| fleet_ring_box_b4_n64 | 4352 | 103 | 118 | 86.53 | 79.28 | 249 | 68.22 | 23.49 | 0.34 (piqp) | 0.27 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_box_b4, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.176 | 0.466 | 0.269 | 0.267 | 0.095 [1/6] | 0.057 | 0.358 | 6.33 (piqp) | 1.33 |
| fleet_ring_box_b4_n4 | 272 | 0.649 | 1.97 | 1.22 | 1.20 | 0.463 | 0.325 [1/6] | 2.31 | 4.99 (osqp) | 1.90 |
| fleet_ring_box_b4_n16 | 1088 | 2.78 | 7.61 | 4.64 | 4.78 | 2.18 | 1.09 | 7.24 | 6.67 (piqp) | 1.56 |
| fleet_ring_box_b4_n64 | 4352 | 10.38 | 29.02 | 17.62 | 17.56 | 9.79 | 4.48 | 30.13 | 6.73 (piqp) | 1.71 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box_b4, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.176 | 0.492 | 0.265 | 0.260 | 0.094 | 0.049 | 0.361 | 7.37 (piqp) | 1.36 |
| fleet_ring_box_b4_n4 | 272 | 0.641 | 2.00 | 1.18 | 1.20 | 0.460 | 0.327 | 2.29 | 7.01 (piqp) | 1.95 |
| fleet_ring_box_b4_n16 | 1088 | 2.77 | 7.69 | 4.61 | 4.85 | 2.26 [2/6] | 1.11 | 7.36 | 6.63 (piqp) | 1.60 |
| fleet_ring_box_b4_n64 | 4352 | 10.35 | 29.07 | 17.54 | 17.67 | 9.71 | 4.43 | 30.05 | 6.78 (piqp) | 1.71 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box_b4, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.172 | 0.449 | 0.263 | 0.259 | 0.091 | 0.049 | 0.354 | 7.28 (piqp) | 1.35 |
| fleet_ring_box_b4_n4 | 272 | 0.650 | 2.00 | 1.20 | 1.23 | 0.480 | 0.252 | 2.43 | 9.63 (piqp) | 2.03 |
| fleet_ring_box_b4_n16 | 1088 | 2.84 | 7.80 | 4.71 | 4.75 | 2.40 | 1.16 | 7.26 | 6.25 (piqp) | 1.54 |
| fleet_ring_box_b4_n64 | 4352 | 10.34 | 28.97 | 17.52 | 17.67 | 9.81 | 4.45 | 30.20 | 6.78 (piqp) | 1.72 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_box_b4, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.429 | 1.12 | 0.744 | 0.692 | 0.207 [1/6] | 0.122 | 0.405 | 3.33 (piqp) | 0.54 |
| fleet_ring_box_b4_n4 | 272 | 2.33 | 5.60 | 3.87 | 3.66 | 1.75 | 0.917 [1/6] | 2.86 | 1.63 (osqp) | 0.74 |
| fleet_ring_box_b4_n16 | 1088 | 14.76 | 26.37 | 18.05 | 17.33 | 13.31 | 8.23 | 11.45 | 1.39 (piqp) | 0.63 |
| fleet_ring_box_b4_n64 | 4352 | 75.87 | 105 | 73.48 | 68.65 | 89.46 | 52.03 | 51.02 | 0.98 (piqp) | 0.69 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box_b4, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.487 | 1.23 | 0.852 | 0.778 | 0.319 | 0.126 | 0.398 | 3.15 (piqp) | 0.47 |
| fleet_ring_box_b4_n4 | 272 | 2.76 | 6.49 | 4.34 | 4.22 | 5.25 | 1.09 | 2.89 | 2.66 (piqp) | 0.67 |
| fleet_ring_box_b4_n16 | 1088 | 18.71 | 32.83 | 22.27 | 21.45 | 37.48 [2/6] | 10.41 | 11.75 | 1.13 (piqp) | 0.53 |
| fleet_ring_box_b4_n64 | 4352 | 102 | 131 | 91.14 | 86.07 | 204 | 60.94 | 53.00 | 0.87 (piqp) | 0.58 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box_b4, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.524 | 1.42 | 0.956 | 0.920 | 0.472 | 0.141 | 0.400 | 2.83 (piqp) | 0.42 |
| fleet_ring_box_b4_n4 | 272 | 3.12 | 7.30 | 4.90 | 4.69 | 7.93 | 1.12 | 3.05 | 2.73 (piqp) | 0.62 |
| fleet_ring_box_b4_n16 | 1088 | 21.67 | 37.07 | 25.39 | 24.10 | 51.84 | 11.84 | 11.80 | 1.00 (piqp) | 0.46 |
| fleet_ring_box_b4_n64 | 4352 | 113 | 147 | 104 | 96.95 | 258 | 72.64 | 53.57 | 0.74 (piqp) | 0.51 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_box_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.294 (0.330) | 0.721 (0.942) | 0.540 (0.633) | 0.457 (0.567) | 0.113 (0.166) | 0.066 (0.078) | 0.048 (0.126) | 0.73 (piqp) | 0.09 |
| fleet_ring_box_b4_n4 | 272 | 1.64 (2.04) | 3.95 (4.00) | 2.71 (2.88) | 2.57 (2.63) | 0.643 (1.29) [3/11] | 0.654 (0.692) [1/11] | 0.615 (1.24) | 0.37 (clarabel) | 0.23 |
| fleet_ring_box_b4_n16 | 1088 | 13.96 (15.61) | 20.70 (22.77) | 14.69 (16.23) | 13.72 (15.15) | 10.38 (18.88) | 7.56 (9.22) | 3.64 (7.16) | 0.48 (piqp) | 0.25 |
| fleet_ring_box_b4_n64 | 4352 | 79.94 (88.36) | 82.24 (98.90) | 59.34 (71.77) | 55.83 (66.75) | 55.89 (71.59) | 51.20 (61.17) | 20.26 (31.57) | 0.40 (piqp) | 0.34 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.347 (0.436) | 0.913 (1.07) | 0.650 (0.793) | 0.553 (0.708) | 0.225 (0.274) | 0.087 (0.112) | 0.051 (0.121) | 0.59 (piqp) | 0.08 |
| fleet_ring_box_b4_n4 | 272 | 2.09 (2.38) | 4.86 (5.34) | 3.30 (3.62) | 3.18 (3.45) | 2.66 (3.34) [3/11] | 0.803 (0.939) | 0.614 (1.39) | 0.76 (piqp) | 0.19 |
| fleet_ring_box_b4_n16 | 1088 | 18.11 (19.51) | 27.08 (29.36) | 19.04 (20.71) | 17.74 (19.14) | 24.10 (36.66) | 9.98 (10.86) | 3.68 (7.19) | 0.37 (piqp) | 0.19 |
| fleet_ring_box_b4_n64 | 4352 | 102 (116) | 115 (132) | 84.13 (96.70) | 78.02 (90.78) | 73.38 (140) [4/11] | 61.75 (70.97) | 23.47 (36.71) | 0.38 (piqp) | 0.28 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 68 | 0.379 (0.470) | 1.05 (1.16) | 0.769 (0.855) | 0.675 (0.732) | 0.349 (0.435) [1/11] | 0.100 (0.123) | 0.050 (0.123) | 0.50 (piqp) | 0.06 |
| fleet_ring_box_b4_n4 | 272 | 2.40 (2.80) | 5.72 (6.28) | 3.91 (4.20) | 3.67 (4.05) | 4.96 (6.26) | 0.923 (1.03) | 0.597 (1.36) | 0.65 (piqp) | 0.15 |
| fleet_ring_box_b4_n16 | 1088 | 19.73 (22.45) | 30.84 (33.68) | 22.02 (23.69) | 20.50 (21.84) | 34.88 (101) | 11.09 (12.84) | 3.66 (7.17) | 0.33 (piqp) | 0.17 |
| fleet_ring_box_b4_n64 | 4352 | 116 (131) | 131 (150) | 96.25 (109) | 89.88 (101) | 169 (289) | 71.14 (80.72) | 23.39 (36.72) | 0.33 (piqp) | 0.24 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_box_b4, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_box_b4_n1 | 5 / 6.5 / -- / 8 | 6.5 / 8 / -- / 9.5 | 6.5 / 8 / -- / 9.5 | 6.5 / 8 / -- / 9.5 | 50 / 100 / -- / 175 | 4 / 5.5 / -- / 7 | 0 / 0 / -- / 0 |
| fleet_ring_box_b4_n4 | 7 / 9 / -- / 11 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 8 / 10 / -- / 12 | 100 / 400 / -- / 625 | 6 / 8 / -- / 9.5 | 20 / 20 / -- / 20 |
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
| fleet_ring_box_b4_n1 | 0.176 | 0.492 | 0.265 | 0.260 | 0.094 | 0.049 | 0.361 |
| fleet_ring_box_b4_n4 | 0.641 | 2.00 | 1.18 | 1.20 | 0.460 | 0.327 | 2.29 |
| fleet_ring_box_b4_n16 | 2.77 | 7.69 | 4.61 | 4.85 | 2.26 | 1.11 | 7.36 |
| fleet_ring_box_b4_n64 | 10.35 | 29.07 | 17.54 | 17.67 | 9.71 | 4.43 | 30.05 |

## fleet_ring_soc

### fleet_ring_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.471 | 0.803 | 0.691 | 0.622 | 0.178 | 0.38 (clarabel) | 0.26 |
| fleet_ring_soc_n4 | 560 | 3.17 | 4.77 | 4.35 | 3.95 | 1.92 | 0.61 (clarabel) | 0.44 |
| fleet_ring_soc_n16 | 2240 | 21.38 | 22.90 | 21.94 | 20.07 | 12.43 | 0.62 (mumblebee_fast_ct) | 0.57 |
| fleet_ring_soc_n64 | 8960 | 122 | 99.12 | 98.71 | 86.36 | 66.16 | 0.77 (mumblebee_fast_ct) | 0.67 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.690 | 0.986 | 0.879 | 0.760 | 0.218 | 0.32 (clarabel) | 0.25 |
| fleet_ring_soc_n4 | 560 | 4.32 | 6.99 | 6.28 | 5.71 | 2.20 | 0.51 (clarabel) | 0.35 |
| fleet_ring_soc_n16 | 2240 | 32.76 | 35.34 | 31.32 | 27.62 | 14.29 | 0.52 (mumblebee_fast_ct) | 0.46 |
| fleet_ring_soc_n64 | 8960 | 175 | 141 | 137 | 122 | 76.41 | 0.63 (mumblebee_fast_ct) | 0.56 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.791 | 1.20 | 1.05 | 0.904 | 0.253 | 0.32 (clarabel) | 0.24 |
| fleet_ring_soc_n4 | 560 | 5.38 | 8.01 | 7.37 | 6.56 | 2.51 | 0.47 (clarabel) | 0.34 |
| fleet_ring_soc_n16 | 2240 | 40.60 | 42.01 | 37.31 | 33.64 | 15.43 | 0.46 (mumblebee_fast_ct) | 0.41 |
| fleet_ring_soc_n64 | 8960 | 217 | 170 | 163 | 146 | 77.70 | 0.53 (mumblebee_fast_ct) | 0.48 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.895 | 1.25 | 1.26 | 0.957 | 0.254 | 0.28 (clarabel) | 0.20 |
| fleet_ring_soc_n4 | 560 | 5.97 | 8.72 | 8.12 | 7.23 | 2.58 | 0.43 (clarabel) | 0.32 |
| fleet_ring_soc_n16 | 2240 | 42.53 | 43.89 | 41.05 | 35.54 | 15.99 | 0.45 (mumblebee_fast_ct) | 0.39 |
| fleet_ring_soc_n64 | 8960 | 226 | 194 | 177 | 157 | 83.22 | 0.53 (mumblebee_fast_ct) | 0.47 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.356 | 0.559 | 0.321 | 0.347 | 0.658 | 2.05 (mumblebee_fast) | 2.05 |
| fleet_ring_soc_n4 | 560 | 1.24 | 2.16 | 1.44 | 1.62 | 4.07 | 3.28 (clarabel) | 2.83 |
| fleet_ring_soc_n16 | 2240 | 5.04 | 8.54 | 5.22 | 6.09 | 17.02 | 3.38 (clarabel) | 3.26 |
| fleet_ring_soc_n64 | 8960 | 20.82 | 31.22 | 20.70 | 20.93 | 74.26 | 3.59 (mumblebee_fast) | 3.59 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.357 | 0.551 | 0.328 | 0.344 | 0.656 | 2.00 (mumblebee_fast) | 2.00 |
| fleet_ring_soc_n4 | 560 | 1.28 | 2.15 | 1.41 | 1.50 | 3.90 | 3.05 (clarabel) | 2.77 |
| fleet_ring_soc_n16 | 2240 | 5.09 | 8.50 | 5.33 | 5.40 | 17.20 | 3.38 (clarabel) | 3.23 |
| fleet_ring_soc_n64 | 8960 | 20.06 | 31.26 | 20.40 | 20.73 | 74.43 | 3.71 (clarabel) | 3.65 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.352 | 0.554 | 0.325 | 0.339 | 0.638 | 1.96 (mumblebee_fast) | 1.96 |
| fleet_ring_soc_n4 | 560 | 1.26 | 2.12 | 1.42 | 1.48 | 4.00 | 3.17 (clarabel) | 2.81 |
| fleet_ring_soc_n16 | 2240 | 5.02 | 8.57 | 5.33 | 5.49 | 17.08 | 3.40 (clarabel) | 3.21 |
| fleet_ring_soc_n64 | 8960 | 21.12 | 31.60 | 20.39 | 20.82 | 74.21 | 3.64 (mumblebee_fast) | 3.64 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.357 | 0.552 | 0.533 | 0.336 | 0.630 | 1.88 (mumblebee_fast_ct) | 1.18 |
| fleet_ring_soc_n4 | 560 | 1.28 | 2.14 | 1.42 | 1.50 | 3.92 | 3.05 (clarabel) | 2.75 |
| fleet_ring_soc_n16 | 2240 | 5.29 | 8.54 | 5.53 | 5.57 | 17.16 | 3.25 (clarabel) | 3.10 |
| fleet_ring_soc_n64 | 8960 | 19.85 | 33.15 | 20.39 | 21.05 | 74.42 | 3.75 (clarabel) | 3.65 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.828 | 1.36 | 1.01 | 0.971 | 0.840 | 1.02 (clarabel) | 0.83 |
| fleet_ring_soc_n4 | 560 | 4.41 | 6.93 | 5.78 | 5.57 | 6.01 | 1.36 (clarabel) | 1.04 |
| fleet_ring_soc_n16 | 2240 | 26.41 | 31.38 | 27.18 | 26.17 | 29.44 | 1.13 (mumblebee_fast_ct) | 1.08 |
| fleet_ring_soc_n64 | 8960 | 143 | 130 | 119 | 107 | 140 | 1.30 (mumblebee_fast_ct) | 1.17 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 1.05 | 1.54 | 1.21 | 1.11 | 0.873 | 0.83 (clarabel) | 0.72 |
| fleet_ring_soc_n4 | 560 | 5.59 | 9.12 | 7.71 | 7.20 | 6.14 | 1.10 (clarabel) | 0.80 |
| fleet_ring_soc_n16 | 2240 | 37.83 | 43.84 | 36.65 | 33.02 | 31.74 | 0.96 (mumblebee_fast_ct) | 0.87 |
| fleet_ring_soc_n64 | 8960 | 195 | 172 | 158 | 143 | 151 | 1.06 (mumblebee_fast_ct) | 0.96 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 1.15 | 1.75 | 1.38 | 1.24 | 0.890 | 0.78 (clarabel) | 0.65 |
| fleet_ring_soc_n4 | 560 | 6.63 | 10.13 | 8.78 | 8.03 | 6.51 | 0.98 (clarabel) | 0.74 |
| fleet_ring_soc_n16 | 2240 | 45.61 | 50.51 | 42.58 | 39.13 | 32.63 | 0.83 (mumblebee_fast_ct) | 0.77 |
| fleet_ring_soc_n64 | 8960 | 239 | 202 | 183 | 167 | 152 | 0.91 (mumblebee_fast_ct) | 0.83 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 1.25 | 1.81 | 1.82 | 1.29 | 0.884 | 0.71 (clarabel) | 0.49 |
| fleet_ring_soc_n4 | 560 | 7.25 | 10.87 | 9.54 | 8.77 | 6.53 | 0.90 (clarabel) | 0.68 |
| fleet_ring_soc_n16 | 2240 | 47.84 | 52.41 | 46.61 | 41.12 | 33.15 | 0.81 (mumblebee_fast_ct) | 0.71 |
| fleet_ring_soc_n64 | 8960 | 245 | 227 | 198 | 178 | 157 | 0.89 (mumblebee_fast_ct) | 0.80 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.473 (0.570) | 0.867 (1.12) | 0.778 (0.959) | 0.678 (0.870) | 0.138 (0.389) | 0.29 (clarabel) | 0.18 |
| fleet_ring_soc_n4 | 560 | 3.13 (4.62) | 5.43 (6.18) | 4.84 (5.57) | 4.47 (5.07) | 1.67 (4.32) | 0.53 (clarabel) | 0.35 |
| fleet_ring_soc_n16 | 2240 | 24.72 (28.30) | 25.13 (28.44) | 24.98 (28.17) | 21.99 (24.66) | 13.37 (21.35) | 0.61 (mumblebee_fast_ct) | 0.54 |
| fleet_ring_soc_n64 | 8960 | 131 (150) | 113 (128) | 112 (126) | 97.91 (110) | 65.55 (143) | 0.67 (mumblebee_fast_ct) | 0.58 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.680 (0.784) | 1.12 (1.36) | 0.975 (1.24) | 0.852 (1.05) | 0.174 (0.381) | 0.26 (clarabel) | 0.18 |
| fleet_ring_soc_n4 | 560 | 4.67 (5.90) | 6.89 (8.29) | 6.41 (7.50) | 5.56 (6.73) | 2.01 (4.58) | 0.43 (clarabel) | 0.31 |
| fleet_ring_soc_n16 | 2240 | 33.07 (40.10) | 35.27 (45.52) | 31.18 (40.39) | 27.35 (35.32) | 14.95 (24.20) | 0.55 (mumblebee_fast_ct) | 0.48 |
| fleet_ring_soc_n64 | 8960 | 197 (217) | 156 (184) | 151 (178) | 134 (158) | 77.97 (327) | 0.58 (mumblebee_fast_ct) | 0.51 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.782 (0.972) | 1.36 (1.50) | 1.20 (1.37) | 1.06 (1.16) | 0.213 (0.424) | 0.27 (clarabel) | 0.18 |
| fleet_ring_soc_n4 | 560 | 5.40 (6.34) | 8.45 (9.92) | 7.63 (8.65) | 6.78 (7.96) | 2.25 (4.70) | 0.42 (clarabel) | 0.30 |
| fleet_ring_soc_n16 | 2240 | 40.84 (48.80) | 45.65 (55.99) | 37.94 (47.19) | 36.71 (45.07) | 16.22 (25.48) | 0.44 (mumblebee_fast_ct) | 0.43 |
| fleet_ring_soc_n64 | 8960 | 236 (279) | 197 (214) | 192 (206) | 170 (182) | 78.23 (341) | 0.46 (mumblebee_fast_ct) | 0.41 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_n1 | 140 | 0.892 (1.08) | 1.38 (1.61) | 1.25 (1.44) | 1.09 (1.25) | 0.219 (0.424) | 0.25 (clarabel) | 0.18 |
| fleet_ring_soc_n4 | 560 | 6.02 (7.01) [1/11] | 9.11 (10.55) | 8.29 (9.84) | 7.46 (8.65) | 2.46 (4.68) | 0.33 (mumblebee_fast_ct) | 0.30 |
| fleet_ring_soc_n16 | 2240 | 42.46 (53.31) | 45.67 (59.26) | 42.80 (55.81) | 36.74 (47.84) | 16.10 (26.15) | 0.44 (mumblebee_fast_ct) | 0.38 |
| fleet_ring_soc_n64 | 8960 | 241 (278) | 225 (240) | 204 (220) | 169 (181) | 78.41 (377) | 0.46 (mumblebee_fast_ct) | 0.38 |

Warm cells: median (max) ms of update + warm start + solve.

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
| fleet_ring_soc_n1 | 0.357 | 0.551 | 0.328 | 0.344 | 0.656 |
| fleet_ring_soc_n4 | 1.28 | 2.15 | 1.41 | 1.50 | 3.90 |
| fleet_ring_soc_n16 | 5.09 | 8.50 | 5.33 | 5.40 | 17.20 |
| fleet_ring_soc_n64 | 20.06 | 31.26 | 20.40 | 20.73 | 74.43 |

## fleet_ring_soc_b4

### fleet_ring_soc_b4, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.345 | 0.506 | 0.471 | 0.453 | 0.112 | 0.32 (clarabel) | 0.24 |
| fleet_ring_soc_b4_n4 | 272 | 2.92 | 3.50 | 3.02 | 2.85 | 1.24 | 0.43 (mumblebee_fast_ct) | 0.41 |
| fleet_ring_soc_b4_n16 | 1088 | 30.28 | 19.50 | 17.81 | 17.13 | 9.07 | 0.53 (mumblebee_fast_ct) | 0.51 |
| fleet_ring_soc_b4_n64 | 4352 | 143 | 89.21 | 81.93 | 78.66 | 40.74 | 0.52 (mumblebee_fast_ct) | 0.50 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc_b4, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.484 | 0.673 | 0.575 | 0.568 | 0.136 | 0.28 (clarabel) | 0.24 |
| fleet_ring_soc_b4_n4 | 272 | 3.77 | 4.82 | 4.25 | 4.10 | 1.41 | 0.37 (clarabel) | 0.33 |
| fleet_ring_soc_b4_n16 | 1088 | 46.15 | 27.25 | 24.97 | 24.04 | 10.40 | 0.43 (mumblebee_fast_ct) | 0.42 |
| fleet_ring_soc_b4_n64 | 4352 | 209 | 124 | 115 | 114 | 48.50 | 0.42 (mumblebee_fast_ct) | 0.42 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc_b4, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.610 | 0.809 | 0.688 | 0.667 | 0.158 | 0.26 (clarabel) | 0.23 |
| fleet_ring_soc_b4_n4 | 272 | 4.81 | 5.49 | 4.95 | 4.73 | 1.55 | 0.33 (mumblebee_fast_ct) | 0.31 |
| fleet_ring_soc_b4_n16 | 1088 | 45.61 | 33.91 | 29.16 | 28.02 | 11.28 | 0.40 (mumblebee_fast_ct) | 0.39 |
| fleet_ring_soc_b4_n64 | 4352 | 252 | 154 | 138 | 133 | 53.41 | 0.40 (mumblebee_fast_ct) | 0.39 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc_b4, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.634 | 0.899 | 0.725 | 0.716 | 0.157 | 0.25 (clarabel) | 0.22 |
| fleet_ring_soc_b4_n4 | 272 | 5.07 | 6.04 | 5.39 | 5.13 | 1.63 | 0.32 (clarabel) | 0.30 |
| fleet_ring_soc_b4_n16 | 1088 | 50.17 | 33.70 | 30.61 | 30.21 | 11.48 | 0.38 (mumblebee_fast_ct) | 0.38 |
| fleet_ring_soc_b4_n64 | 4352 | 261 | 161 | 148 | 148 | 55.48 | 0.38 (mumblebee_fast_ct) | 0.37 |

Cold cells: median ms of the solve alone; setup is its own mode.

### fleet_ring_soc_b4, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.241 | 0.388 | 0.275 | 0.265 | 0.447 | 1.86 (clarabel) | 1.62 |
| fleet_ring_soc_b4_n4 | 272 | 0.919 | 1.70 | 1.24 | 1.18 | 2.69 | 2.93 (clarabel) | 2.18 |
| fleet_ring_soc_b4_n16 | 1088 | 3.85 | 6.34 | 4.75 | 4.62 | 12.45 | 3.23 (clarabel) | 2.62 |
| fleet_ring_soc_b4_n64 | 4352 | 14.67 | 24.67 | 18.05 | 17.93 | 50.68 | 3.45 (clarabel) | 2.81 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc_b4, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.238 | 0.389 | 0.270 | 0.272 | 0.429 | 1.80 (clarabel) | 1.59 |
| fleet_ring_soc_b4_n4 | 272 | 0.913 | 1.74 | 1.16 | 1.17 | 2.61 | 2.87 (clarabel) | 2.26 |
| fleet_ring_soc_b4_n16 | 1088 | 3.81 | 6.37 | 4.64 | 4.64 | 12.40 | 3.25 (clarabel) | 2.68 |
| fleet_ring_soc_b4_n64 | 4352 | 14.78 | 24.54 | 18.05 | 18.12 | 50.99 | 3.45 (clarabel) | 2.82 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc_b4, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.239 | 0.388 | 0.262 | 0.260 | 0.415 | 1.74 (clarabel) | 1.58 |
| fleet_ring_soc_b4_n4 | 272 | 1.04 | 1.64 | 1.22 | 1.18 | 2.64 | 2.54 (clarabel) | 2.16 |
| fleet_ring_soc_b4_n16 | 1088 | 3.88 | 6.88 | 4.66 | 4.62 | 12.65 | 3.26 (clarabel) | 2.72 |
| fleet_ring_soc_b4_n64 | 4352 | 14.79 | 25.01 | 18.10 | 17.88 | 50.69 | 3.43 (clarabel) | 2.80 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc_b4, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.231 | 0.391 | 0.271 | 0.260 | 0.409 | 1.77 (clarabel) | 1.51 |
| fleet_ring_soc_b4_n4 | 272 | 0.935 | 1.63 | 1.34 | 1.17 | 2.59 | 2.77 (clarabel) | 1.93 |
| fleet_ring_soc_b4_n16 | 1088 | 3.88 | 6.32 | 4.65 | 4.67 | 12.42 | 3.20 (clarabel) | 2.67 |
| fleet_ring_soc_b4_n64 | 4352 | 14.81 | 24.75 | 18.07 | 18.41 | 50.76 | 3.43 (clarabel) | 2.81 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### fleet_ring_soc_b4, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.587 | 0.893 | 0.747 | 0.716 | 0.564 | 0.96 (clarabel) | 0.76 |
| fleet_ring_soc_b4_n4 | 272 | 3.84 | 5.36 | 4.26 | 4.04 | 3.91 | 1.02 (clarabel) | 0.92 |
| fleet_ring_soc_b4_n16 | 1088 | 34.05 | 26.05 | 22.49 | 21.75 | 21.52 | 0.99 (mumblebee_fast_ct) | 0.96 |
| fleet_ring_soc_b4_n64 | 4352 | 158 | 114 | 99.88 | 96.85 | 91.56 | 0.95 (mumblebee_fast_ct) | 0.92 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc_b4, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.728 | 1.07 | 0.845 | 0.845 | 0.560 | 0.77 (clarabel) | 0.66 |
| fleet_ring_soc_b4_n4 | 272 | 4.68 | 6.53 | 5.42 | 5.27 | 4.04 | 0.86 (clarabel) | 0.74 |
| fleet_ring_soc_b4_n16 | 1088 | 50.00 | 33.56 | 29.66 | 28.64 | 22.92 | 0.80 (mumblebee_fast_ct) | 0.77 |
| fleet_ring_soc_b4_n64 | 4352 | 223 | 149 | 133 | 132 | 99.49 | 0.75 (mumblebee_fast_ct) | 0.75 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc_b4, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.844 | 1.20 | 0.946 | 0.928 | 0.573 | 0.68 (clarabel) | 0.61 |
| fleet_ring_soc_b4_n4 | 272 | 5.84 | 7.12 | 6.16 | 5.90 | 4.26 | 0.73 (clarabel) | 0.69 |
| fleet_ring_soc_b4_n16 | 1088 | 49.51 | 40.86 | 33.82 | 32.70 | 24.05 | 0.74 (mumblebee_fast_ct) | 0.71 |
| fleet_ring_soc_b4_n64 | 4352 | 267 | 180 | 156 | 150 | 103 | 0.69 (mumblebee_fast_ct) | 0.66 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc_b4, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.864 | 1.29 | 0.994 | 0.974 | 0.561 | 0.65 (clarabel) | 0.56 |
| fleet_ring_soc_b4_n4 | 272 | 6.05 | 7.66 | 6.70 | 6.30 | 4.18 | 0.69 (clarabel) | 0.62 |
| fleet_ring_soc_b4_n16 | 1088 | 54.01 | 40.02 | 35.31 | 34.97 | 23.85 | 0.68 (mumblebee_fast_ct) | 0.68 |
| fleet_ring_soc_b4_n64 | 4352 | 276 | 185 | 166 | 166 | 106 | 0.64 (mumblebee_fast_ct) | 0.64 |

Setup + solve cells: median ms of a cold setup plus its solve.

### fleet_ring_soc_b4, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.395 (0.464) | 0.555 (0.721) | 0.504 (0.645) | 0.496 (0.628) | 0.113 (0.251) | 0.28 (clarabel) | 0.22 |
| fleet_ring_soc_b4_n4 | 272 | 2.85 (3.30) | 3.73 (4.21) | 3.38 (3.84) | 3.22 (3.68) | 1.13 (2.93) | 0.40 (clarabel) | 0.33 |
| fleet_ring_soc_b4_n16 | 1088 | 29.78 (34.22) | 21.86 (24.74) | 20.09 (22.43) | 19.11 (21.39) | 7.48 (15.15) | 0.39 (mumblebee_fast_ct) | 0.37 |
| fleet_ring_soc_b4_n64 | 4352 | 162 (184) | 102 (113) | 93.29 (105) | 89.62 (101) | 44.69 (73.12) | 0.50 (mumblebee_fast_ct) | 0.48 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc_b4, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.533 (0.606) | 0.786 (0.961) | 0.644 (0.795) | 0.625 (0.767) | 0.133 (0.240) | 0.25 (clarabel) | 0.21 |
| fleet_ring_soc_b4_n4 | 272 | 3.79 (4.62) | 4.77 (5.67) | 4.31 (5.29) | 4.09 (4.87) | 1.37 (2.74) | 0.36 (clarabel) | 0.32 |
| fleet_ring_soc_b4_n16 | 1088 | 38.16 (45.63) | 27.35 (35.21) | 24.59 (31.04) | 23.61 (30.25) | 9.03 (18.42) | 0.38 (mumblebee_fast_ct) | 0.37 |
| fleet_ring_soc_b4_n64 | 4352 | 226 (249) | 137 (163) | 128 (149) | 125 (147) | 58.59 (80.51) | 0.47 (mumblebee_fast_ct) | 0.46 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc_b4, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.610 (0.683) | 0.909 (1.04) | 0.791 (0.877) | 0.775 (0.851) | 0.153 (0.257) | 0.25 (clarabel) | 0.19 |
| fleet_ring_soc_b4_n4 | 272 | 4.74 (5.47) | 5.74 (6.55) | 5.17 (6.13) | 4.92 (5.82) | 1.57 (3.11) | 0.33 (clarabel) | 0.30 |
| fleet_ring_soc_b4_n16 | 1088 | 49.50 (57.82) | 34.62 (43.35) | 31.33 (38.95) | 29.94 (36.65) | 9.78 (18.41) | 0.33 (mumblebee_fast_ct) | 0.31 |
| fleet_ring_soc_b4_n64 | 4352 | 270 (313) | 173 (187) | 160 (173) | 154 (166) | 61.28 (84.83) | 0.40 (mumblebee_fast_ct) | 0.38 |

Warm cells: median (max) ms of update + warm start + solve.

### fleet_ring_soc_b4, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_ring_soc_b4_n1 | 68 | 0.677 (0.758) | 0.903 (1.11) | 0.802 (0.949) | 0.777 (0.926) | 0.155 (0.259) | 0.23 (clarabel) | 0.19 |
| fleet_ring_soc_b4_n4 | 272 | 5.12 (5.93) [1/11] | 6.23 (7.27) | 5.58 (6.50) | 5.31 (6.16) | 1.63 (2.97) | 0.31 (mumblebee_fast_ct) | 0.29 |
| fleet_ring_soc_b4_n16 | 1088 | 51.26 (60.87) [1/11] | 35.02 (45.17) | 32.14 (41.14) | 31.50 (39.00) | 10.01 (18.84) | 0.32 (mumblebee_fast_ct) | 0.31 |
| fleet_ring_soc_b4_n64 | 4352 | 291 (332) | 185 (198) | 171 (183) | 171 (183) | 61.31 (85.25) | 0.36 (mumblebee_fast_ct) | 0.36 |

Warm cells: median (max) ms of update + warm start + solve.

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
| fleet_ring_soc_b4_n1 | 0.238 | 0.389 | 0.270 | 0.272 | 0.429 |
| fleet_ring_soc_b4_n4 | 0.913 | 1.74 | 1.16 | 1.17 | 2.61 |
| fleet_ring_soc_b4_n16 | 3.81 | 6.37 | 4.64 | 4.64 | 12.40 |
| fleet_ring_soc_b4_n64 | 14.78 | 24.54 | 18.05 | 18.12 | 50.99 |

## osqprand

### osqprand, cold, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.26 | 0.163 [1/5] | 2.23 | 0.570 | 0.561 | 0.059 | 0.11 (piqp) |
| osqprand_nx10_s2 | 160 | 1.00 | 0.109 | 1.85 | 0.298 | 0.525 | 0.102 | 0.94 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.44 | 0.149 [2/5] | 2.54 | 0.964 | 0.567 | 0.159 | 0.28 (piqp) |
| osqprand_nx20_s1 | 320 | 4.41 | 0.475 | 6.34 | 4.71 | 2.53 | 0.567 | 1.19 (hpipm) |
| osqprand_nx20_s2 | 320 | 4.53 | 0.347 | 6.28 [2/5] | 1.91 | 2.88 | 0.372 | 1.07 (hpipm) |
| osqprand_nx20_s3 | 320 | 4.51 | 0.560 | 6.30 | 0.956 | 2.55 | 0.363 | 0.65 (hpipm) |
| osqprand_nx40_s1 | 640 | 20.16 | 1.43 | 17.29 [1/5] | 11.13 | 14.10 | 4.05 | 2.82 (hpipm) |
| osqprand_nx40_s2 | 640 | 20.61 | 1.45 | 20.56 | 8.37 [2/5] | 14.86 | 15.56 | 10.75 (hpipm) |
| osqprand_nx40_s3 | 640 | 16.52 | 1.26 | 14.40 [1/5] | 3.50 | 12.24 | 3.81 | 3.03 (hpipm) |

Cold cells: median ms of the solve alone; setup is its own mode.

### osqprand, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.61 | 0.199 [1/5] | 3.27 [2/5] | 1.49 | 0.711 | 0.101 | 0.14 (piqp) |
| osqprand_nx10_s2 | 160 | 1.30 | 0.121 | 2.19 | 0.597 | 0.587 | 0.139 | 1.14 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.99 | 0.189 | 3.47 [2/5] | 0.853 [1/5] | 0.792 | 0.154 | 0.81 (hpipm) |
| osqprand_nx20_s1 | 320 | 5.02 | 0.562 | 8.06 | 7.97 [2/5] | 3.21 | 0.690 | 1.23 (hpipm) |
| osqprand_nx20_s2 | 320 | 5.71 | 0.483 | 9.25 | 4.07 | 3.17 | 0.402 | 0.83 (hpipm) |
| osqprand_nx20_s3 | 320 | 5.80 | 0.504 | 8.62 | 2.64 | 3.43 | 0.573 | 1.14 (hpipm) |
| osqprand_nx40_s1 | 640 | 24.92 | 1.86 | 27.55 | 29.02 | 17.96 | 4.08 | 2.19 (hpipm) |
| osqprand_nx40_s2 | 640 | 25.76 | 1.80 [2/5] | 27.51 [4/5] | 53.49 | 17.37 | 15.88 | 0.91 (piqp) |
| osqprand_nx40_s3 | 640 | 21.76 | 1.54 | 24.19 | 9.72 | 16.12 | 3.79 | 2.45 (hpipm) |

Cold cells: median ms of the solve alone; setup is its own mode.

### osqprand, cold, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.92 | 0.184 [1/5] | 3.53 [2/5] | 1.79 | 0.770 | 0.113 | 0.15 (piqp) |
| osqprand_nx10_s2 | 160 | 1.50 | 0.143 | 2.89 | 0.614 | 0.748 | 0.119 | 0.83 (hpipm) |
| osqprand_nx10_s3 | 160 | 2.23 | 0.262 [1/5] | 4.39 | 1.38 | 0.868 | 0.203 | 0.23 (piqp) |
| osqprand_nx20_s1 | 320 | 5.97 | 0.510 [1/5] | 9.59 [2/5] | 11.48 | 3.69 | 0.674 | 0.18 (piqp) |
| osqprand_nx20_s2 | 320 | 6.78 | 0.616 | 9.49 | 7.15 | 3.98 | 0.457 | 0.74 (hpipm) |
| osqprand_nx20_s3 | 320 | 6.86 | 0.605 [1/5] | 10.48 | 4.33 | 3.82 | 0.489 | 0.13 (piqp) |
| osqprand_nx40_s1 | 640 | 29.37 | 2.14 | 35.55 | 61.77 | 21.91 | 4.05 | 1.90 (hpipm) |
| osqprand_nx40_s2 | 640 | 30.77 | 2.04 [3/5] | 31.47 [3/5] | 88.00 | 21.98 | 15.88 | 0.72 (piqp) |
| osqprand_nx40_s3 | 640 | 24.35 | 1.70 | 29.18 | 12.59 | 18.35 | 3.78 | 2.23 (hpipm) |

Cold cells: median ms of the solve alone; setup is its own mode.

### osqprand, setup, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 0.737 | 0.259 [1/5] | 6.14 | 0.416 | 0.396 | 2.46 | 6.21 (piqp) |
| osqprand_nx10_s2 | 160 | 0.800 | 0.242 | 6.05 | 0.500 | 0.448 | 2.42 | 10.01 (hpipm) |
| osqprand_nx10_s3 | 160 | 0.749 | 0.185 [2/5] | 6.04 | 0.550 | 0.404 | 2.47 | 6.12 (piqp) |
| osqprand_nx20_s1 | 320 | 1.85 | 0.288 | 36.39 | 1.46 | 1.12 | 6.73 | 23.34 (hpipm) |
| osqprand_nx20_s2 | 320 | 1.82 | 0.232 | 37.11 [2/5] | 1.53 | 1.17 | 6.69 | 28.87 (hpipm) |
| osqprand_nx20_s3 | 320 | 1.83 | 0.234 | 37.38 | 1.46 | 1.08 | 6.67 | 28.43 (hpipm) |
| osqprand_nx40_s1 | 640 | 4.99 | 0.318 | 256 [1/5] | 5.70 | 3.73 | 27.01 | 84.87 (hpipm) |
| osqprand_nx40_s2 | 640 | 5.14 | 0.391 | 263 | 5.78 [2/5] | 3.30 | 25.59 | 65.47 (hpipm) |
| osqprand_nx40_s3 | 640 | 5.03 | 0.385 | 261 [1/5] | 5.67 | 3.84 | 26.46 | 68.81 (hpipm) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### osqprand, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 0.588 | 0.231 [1/5] | 6.17 [2/5] | 0.428 | 0.435 | 2.42 | 5.66 (osqp) |
| osqprand_nx10_s2 | 160 | 0.747 | 0.129 | 6.02 | 0.438 | 0.426 | 2.48 | 19.18 (hpipm) |
| osqprand_nx10_s3 | 160 | 0.764 | 0.107 | 6.03 [2/5] | 0.502 [1/5] | 0.454 | 2.30 | 21.47 (hpipm) |
| osqprand_nx20_s1 | 320 | 1.89 | 0.314 | 35.41 | 1.54 [2/5] | 1.13 | 6.70 | 21.34 (hpipm) |
| osqprand_nx20_s2 | 320 | 1.84 | 0.169 | 37.74 | 1.52 | 1.14 | 6.82 | 40.39 (hpipm) |
| osqprand_nx20_s3 | 320 | 1.90 | 0.140 | 37.33 | 1.52 | 1.14 | 6.82 | 48.75 (hpipm) |
| osqprand_nx40_s1 | 640 | 5.06 | 0.326 | 256 | 5.74 | 3.77 | 26.99 | 82.86 (hpipm) |
| osqprand_nx40_s2 | 640 | 5.17 | 0.370 [2/5] | 263 [4/5] | 5.39 | 3.14 | 27.23 | 8.67 (piqp) |
| osqprand_nx40_s3 | 640 | 5.07 | 0.330 | 259 | 5.58 | 3.87 | 26.78 | 81.25 (hpipm) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### osqprand, setup, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 0.676 | 0.106 [1/5] | 6.11 [2/5] | 0.449 | 0.321 | 2.37 | 7.39 (piqp) |
| osqprand_nx10_s2 | 160 | 0.794 | 0.244 | 6.14 | 0.515 | 0.341 | 2.35 | 9.65 (hpipm) |
| osqprand_nx10_s3 | 160 | 0.794 | 0.201 [1/5] | 6.13 | 0.507 | 0.360 | 2.34 | 6.49 (piqp) |
| osqprand_nx20_s1 | 320 | 1.93 | 0.272 [1/5] | 37.24 [2/5] | 1.51 | 1.14 | 6.63 | 5.81 (piqp) |
| osqprand_nx20_s2 | 320 | 1.84 | 0.234 | 36.99 | 1.52 | 1.12 | 6.91 | 29.52 (hpipm) |
| osqprand_nx20_s3 | 320 | 1.89 | 0.168 [1/5] | 37.55 | 1.54 | 1.10 | 6.84 | 6.22 (piqp) |
| osqprand_nx40_s1 | 640 | 4.91 | 0.232 | 274 | 5.68 | 3.79 | 27.29 | 117.76 (hpipm) |
| osqprand_nx40_s2 | 640 | 4.99 | 0.370 [3/5] | 269 [3/5] | 5.81 | 3.65 | 27.37 | 7.50 (piqp) |
| osqprand_nx40_s3 | 640 | 5.09 | 0.350 | 274 | 5.57 | 3.74 | 26.71 | 76.28 (hpipm) |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### osqprand, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.95 | 0.421 [1/5] | 8.37 | 1.01 | 0.926 | 2.52 | 2.72 (piqp) |
| osqprand_nx10_s2 | 160 | 1.80 | 0.351 | 7.91 | 0.810 | 0.973 | 2.49 | 7.09 (hpipm) |
| osqprand_nx10_s3 | 160 | 2.15 | 0.329 [2/5] | 8.58 | 1.53 | 0.971 | 2.75 | 2.83 (piqp) |
| osqprand_nx20_s1 | 320 | 6.28 | 0.763 | 42.73 | 6.22 | 3.66 | 7.29 | 9.56 (hpipm) |
| osqprand_nx20_s2 | 320 | 6.40 | 0.575 | 43.30 [2/5] | 3.26 | 4.09 | 7.16 | 12.44 (hpipm) |
| osqprand_nx20_s3 | 320 | 6.31 | 0.778 | 43.91 | 2.44 | 3.64 | 7.06 | 9.08 (hpipm) |
| osqprand_nx40_s1 | 640 | 25.15 | 1.82 | 274 [1/5] | 16.83 | 17.98 | 31.47 | 17.34 (hpipm) |
| osqprand_nx40_s2 | 640 | 25.72 | 1.84 | 284 | 14.18 [2/5] | 18.15 | 41.29 | 22.46 (hpipm) |
| osqprand_nx40_s3 | 640 | 21.72 | 1.67 | 275 [1/5] | 9.24 | 16.25 | 30.31 | 18.18 (hpipm) |

Setup + solve cells: median ms of a cold setup plus its solve.

### osqprand, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 2.18 | 0.430 [1/5] | 9.45 [2/5] | 1.98 | 1.09 | 2.52 | 2.31 (piqp) |
| osqprand_nx10_s2 | 160 | 2.04 | 0.251 | 8.26 | 1.10 | 1.01 | 2.61 | 10.43 (hpipm) |
| osqprand_nx10_s3 | 160 | 2.76 | 0.291 | 9.50 [2/5] | 1.35 [1/5] | 1.20 | 2.70 | 9.28 (hpipm) |
| osqprand_nx20_s1 | 320 | 7.00 | 0.876 | 43.25 | 9.51 [2/5] | 4.32 | 7.51 | 8.58 (hpipm) |
| osqprand_nx20_s2 | 320 | 7.54 | 0.689 | 47.17 | 5.65 | 4.34 | 7.40 | 10.74 (hpipm) |
| osqprand_nx20_s3 | 320 | 7.78 | 0.652 | 46.55 | 4.20 | 4.62 | 7.39 | 11.33 (hpipm) |
| osqprand_nx40_s1 | 640 | 29.98 | 2.20 | 284 | 34.75 | 21.88 | 31.11 | 14.13 (hpipm) |
| osqprand_nx40_s2 | 640 | 31.18 | 2.16 [2/5] | 290 [4/5] | 58.86 | 20.56 | 43.19 | 2.10 (piqp) |
| osqprand_nx40_s3 | 640 | 26.96 | 1.87 | 282 | 15.16 | 20.14 | 30.53 | 16.31 (hpipm) |

Setup + solve cells: median ms of a cold setup plus its solve.

### osqprand, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 2.52 | 0.279 [1/5] | 9.64 [2/5] | 2.26 | 1.14 | 2.51 | 2.20 (piqp) |
| osqprand_nx10_s2 | 160 | 2.30 | 0.387 | 9.08 | 1.09 | 1.08 | 2.46 | 6.35 (hpipm) |
| osqprand_nx10_s3 | 160 | 3.03 | 0.460 [1/5] | 10.48 | 1.86 | 1.27 | 2.71 | 2.13 (piqp) |
| osqprand_nx20_s1 | 320 | 7.90 | 0.795 [1/5] | 47.10 [2/5] | 13.12 | 4.83 | 7.23 | 1.50 (piqp) |
| osqprand_nx20_s2 | 320 | 8.61 | 0.851 | 46.33 | 8.69 | 5.10 | 7.33 | 8.62 (hpipm) |
| osqprand_nx20_s3 | 320 | 8.75 | 0.773 [1/5] | 47.33 | 5.87 | 4.92 | 7.30 | 1.48 (piqp) |
| osqprand_nx40_s1 | 640 | 34.29 | 2.37 | 310 | 67.55 | 25.67 | 31.37 | 13.22 (hpipm) |
| osqprand_nx40_s2 | 640 | 35.72 | 2.41 [3/5] | 301 [3/5] | 93.74 | 25.63 | 41.55 | 1.62 (piqp) |
| osqprand_nx40_s3 | 640 | 29.43 | 2.03 | 302 | 18.21 | 21.89 | 30.85 | 15.23 (hpipm) |

Setup + solve cells: median ms of a cold setup plus its solve.

### osqprand, warm, low

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.07 (1.30) | 0.118 (0.181) [1/11] | 2.11 (2.26) | 0.283 (0.605) | 0.504 (0.594) | 0.043 (0.060) | 0.15 (osqp) |
| osqprand_nx10_s2 | 160 | 0.925 (1.02) | 0.086 (0.093) | 1.67 (1.73) | 0.289 (0.331) | 0.520 (0.562) | 0.064 (0.072) | 0.74 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.32 (1.42) | 0.134 (0.166) [2/11] | 2.33 (2.58) | 0.568 (0.685) | 0.571 (0.625) | 0.084 (0.610) | 0.15 (osqp) |
| osqprand_nx20_s1 | 320 | 5.01 (5.09) | 0.405 (0.492) | 6.24 (6.28) | 2.74 (3.03) | 2.63 (2.96) | 0.128 (0.148) | 0.32 (hpipm) |
| osqprand_nx20_s2 | 320 | 4.28 (4.90) | 0.364 (0.477) | 5.45 (6.24) [2/11] | 0.946 (2.18) | 2.62 (2.88) | 0.932 (2.11) | 2.56 (hpipm) |
| osqprand_nx20_s3 | 320 | 4.39 (4.58) | 0.523 (0.556) | 5.45 (7.25) | 0.930 (2.08) | 2.44 (2.54) | 0.133 (0.561) | 0.26 (hpipm) |
| osqprand_nx40_s1 | 640 | 19.59 (23.19) | 1.15 (1.43) | 14.60 (17.70) [2/11] | 3.53 (8.34) | 14.07 (16.65) | 1.07 (39.38) | 0.92 (hpipm) |
| osqprand_nx40_s2 | 640 | 20.44 (21.37) | 1.05 (1.36) | 20.54 (23.81) | 3.29 (14.80) | 13.13 (14.93) | 2.97 (12.52) | 2.83 (hpipm) |
| osqprand_nx40_s3 | 640 | 16.54 (17.57) | 1.07 (1.47) | 14.15 (14.92) [1/11] | 3.30 (3.50) | 12.15 (12.56) | 0.855 (7.08) | 0.80 (hpipm) |

Warm cells: median (max) ms of update + warm start + solve.

### osqprand, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.30 (1.79) | 0.115 (0.176) [1/11] | 2.35 (3.31) [2/11] | 0.568 (1.20) | 0.610 (0.744) | 0.064 (0.073) | 0.11 (osqp) |
| osqprand_nx10_s2 | 160 | 1.23 (1.35) | 0.091 (0.124) | 2.00 (2.34) | 0.564 (0.578) | 0.561 (0.613) | 0.072 (0.088) | 0.79 (hpipm) |
| osqprand_nx10_s3 | 160 | 1.83 (1.93) | 0.183 (0.210) | 3.19 (3.43) [2/11] | 0.850 (0.884) [4/11] | 0.740 (0.849) | 0.078 (0.671) | 0.42 (hpipm) |
| osqprand_nx20_s1 | 320 | 5.59 (6.22) | 0.490 (0.562) | 7.96 (8.20) | 6.81 (6.82) [8/11] | 3.28 (3.43) | 0.203 (0.231) | 0.41 (hpipm) |
| osqprand_nx20_s2 | 320 | 5.68 (6.03) | 0.520 (0.627) | 8.58 (9.54) | 1.86 (4.55) | 3.20 (3.66) | 0.870 (2.15) | 1.67 (hpipm) |
| osqprand_nx20_s3 | 320 | 5.61 (6.26) | 0.454 (0.633) | 7.52 (10.33) | 1.81 (3.09) | 3.08 (3.69) | 0.192 (0.682) | 0.42 (hpipm) |
| osqprand_nx40_s1 | 640 | 24.82 (27.86) | 1.71 (1.97) | 26.98 (31.51) | 16.63 (48.82) | 15.93 (17.78) | 1.75 (47.40) | 1.02 (hpipm) |
| osqprand_nx40_s2 | 640 | 25.66 (29.56) | 1.49 (1.65) [2/11] | 23.71 (30.80) [4/11] | 11.76 (38.99) | 15.24 (17.20) | 0.731 (7.34) | 0.06 (osqp) |
| osqprand_nx40_s3 | 640 | 22.31 (25.76) | 1.39 (1.54) [1/11] | 21.11 (25.12) [2/11] | 8.28 (9.43) | 15.99 (16.53) | 0.909 (6.92) | 0.11 (osqp) |

Warm cells: median (max) ms of update + warm start + solve.

### osqprand, warm, high

| instance | vars | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc | sheafmpc / best other |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 160 | 1.54 (1.91) | 0.164 (0.231) [1/11] | 8.60 (9.47) [2/11] | 0.560 (1.80) | 0.741 (0.821) | 0.062 (0.070) | 0.11 (osqp) |
| osqprand_nx10_s2 | 160 | 1.42 (1.48) | 0.133 (0.153) | 2.72 (2.89) | 0.579 (0.611) | 0.732 (0.754) | 0.075 (0.087) | 0.57 (hpipm) |
| osqprand_nx10_s3 | 160 | 2.10 (2.48) | 0.218 (0.272) [1/11] | 9.95 (10.56) | 1.21 (1.51) [3/11] | 0.912 (0.965) | 0.099 (3.79) | 0.11 (piqp) |
| osqprand_nx20_s1 | 320 | 6.43 (6.67) | 0.575 (0.613) [1/11] | 46.23 (46.68) [3/11] | 28.26 (28.63) | 3.78 (4.18) | 0.203 (0.244) | 0.05 (piqp) |
| osqprand_nx20_s2 | 320 | 6.06 (7.14) | 0.547 (0.677) [1/11] | 9.20 (10.14) [1/11] | 3.44 (8.06) | 3.80 (3.97) | 0.875 (2.16) | 0.25 (osqp) |
| osqprand_nx20_s3 | 320 | 6.30 (7.54) | 0.446 (0.637) [1/11] | 46.18 (47.82) | 1.92 (4.64) | 3.68 (4.15) | 0.210 (0.713) | 0.11 (osqp) |
| osqprand_nx40_s1 | 640 | 27.43 (32.49) | 1.81 (2.03) | 304 (308) | 34.24 (68.25) | 19.94 (21.83) | 1.84 (51.56) | 1.01 (hpipm) |
| osqprand_nx40_s2 | 640 | 28.03 (37.60) | 1.48 (1.82) [3/11] | 28.95 (36.71) [3/11] | 11.53 (67.18) | 19.76 (23.89) | 0.831 (8.10) | 0.07 (osqp) |
| osqprand_nx40_s3 | 640 | 24.09 (27.44) | 1.54 (1.85) [1/11] | 28.94 (29.80) [1/11] | 6.60 (12.46) | 18.48 (21.04) | 0.839 (7.26) | 0.13 (osqp) |

Warm cells: median (max) ms of update + warm start + solve.

### osqprand, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 6 / 8 / -- / 10 | 4 / 6 / -- / 8 | 6 / 8 / -- / 10 | 50 / 125 / -- / 150 | 5 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx10_s2 | 4 / 6 / -- / 7 | 3 / 4 / -- / 4 | 5 / 6 / -- / 8 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| osqprand_nx10_s3 | 6 / 9 / -- / 10 | 5 / 8 / -- / 9 | 7 / 9 / -- / 12 | 50 / 75 / -- / 125 | 6 / 9 / -- / 10 | 0 / 0 / -- / 0 |
| osqprand_nx20_s1 | 6 / 7 / -- / 9 | 6 / 7 / -- / 7 | 7 / 9 / -- / 10 | 100 / 225 / -- / 300 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx20_s2 | 6 / 8 / -- / 10 | 5 / 8 / -- / 8 | 6 / 10 / -- / 10 | 50 / 100 / -- / 175 | 7 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| osqprand_nx20_s3 | 6 / 8 / -- / 10 | 6 / 8 / -- / 9 | 7 / 9 / -- / 11 | 25 / 75 / -- / 125 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| osqprand_nx40_s1 | 6 / 8 / -- / 10 | 5 / 8 / -- / 9 | 6 / 9 / -- / 11 | 75 / 200 / -- / 375 | 6 / 8 / -- / 10 | 20 / 20 / -- / 20 |
| osqprand_nx40_s2 | 6 / 8 / -- / 10 | 5 / 7 / -- / 9 | 7 / 8 / -- / 10 | 50 / 400 / -- / 650 | 7 / 8 / -- / 10 | 100 / 100 / -- / 100 |
| osqprand_nx40_s3 | 5 / 7 / -- / 8 | 5 / 6 / -- / 6 | 5 / 8 / -- / 9 | 25 / 75 / -- / 100 | 5 / 7 / -- / 8 | 20 / 20 / -- / 20 |

### osqprand, warm, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 5 / 6 / -- / 8 | 3 / 4 / -- / 5 | 6 / 7 / -- / 8 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| osqprand_nx10_s2 | 4 / 6 / -- / 7 | 3 / 3 / -- / 4 | 5 / 6 / -- / 8 | 25 / 50 / -- / 50 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| osqprand_nx10_s3 | 6 / 8 / -- / 10 | 5 / 7 / -- / 8 | 7 / 9 / -- / 11 | 25 / 50 / -- / 125 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| osqprand_nx20_s1 | 7 / 8 / -- / 10 | 6 / 7 / -- / 7 | 7 / 9 / -- / 10 | 50 / 475 / -- / 825 | 6 / 8 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx20_s2 | 6 / 8 / -- / 9 | 5 / 7 / -- / 8 | 6 / 9 / -- / 10 | 25 / 50 / -- / 100 | 6 / 8 / -- / 10 | 20 / 20 / -- / 20 |
| osqprand_nx20_s3 | 6 / 8 / -- / 9 | 5 / 7 / -- / 7 | 6 / 8 / -- / 10 | 25 / 50 / -- / 50 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx40_s1 | 6 / 8 / -- / 9 | 5 / 8 / -- / 8 | 5 / 9 / -- / 10 | 25 / 125 / -- / 175 | 6 / 7 / -- / 9 | 0 / 0 / -- / 0 |
| osqprand_nx40_s2 | 6 / 8 / -- / 9 | 4 / 7 / -- / 8 | 7 / 8 / -- / 10 | 25 / 75 / -- / 75 | 6 / 7 / -- / 9 | 20 / 0 / -- / 0 |
| osqprand_nx40_s3 | 5 / 7 / -- / 8 | 4 / 6 / -- / 6 | 5 / 7 / -- / 9 | 25 / 50 / -- / 50 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |

### osqprand, setup (ms, median over the cold repeats, medium tier)

| instance | clarabel | hpipm | mumblebee | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|
| osqprand_nx10_s1 | 0.588 | 0.201 | 6.16 | 0.428 | 0.435 | 2.42 |
| osqprand_nx10_s2 | 0.747 | 0.129 | 6.02 | 0.438 | 0.426 | 2.48 |
| osqprand_nx10_s3 | 0.764 | 0.107 | 6.03 | 0.468 | 0.454 | 2.30 |
| osqprand_nx20_s1 | 1.89 | 0.314 | 35.41 | 1.55 | 1.13 | 6.70 |
| osqprand_nx20_s2 | 1.84 | 0.169 | 37.74 | 1.52 | 1.14 | 6.82 |
| osqprand_nx20_s3 | 1.90 | 0.140 | 37.33 | 1.52 | 1.14 | 6.82 |
| osqprand_nx40_s1 | 5.06 | 0.326 | 256 | 5.74 | 3.77 | 26.99 |
| osqprand_nx40_s2 | 5.17 | 0.377 | 262 | 5.39 | 3.14 | 27.23 |
| osqprand_nx40_s3 | 5.07 | 0.330 | 259 | 5.58 | 3.87 | 26.78 |

## reduced

### reduced, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 18.52 | 13.98 | 13.34 | 12.03 | 5.16 | 0.43 (mumblebee_fast_ct) | 0.39 |
| reduced_k4 | 3880 | 16.86 | 14.45 | 13.52 | 11.51 | 5.26 | 0.46 (mumblebee_fast_ct) | 0.39 |
| reduced_k2 | 3920 | 17.48 | 14.25 | 13.28 | 12.23 | 5.31 | 0.43 (mumblebee_fast_ct) | 0.40 |
| reduced_k0 | 5120 | 45.39 | 28.72 | 27.53 | 27.01 | 8.50 | 0.31 (mumblebee_fast_ct) | 0.31 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 21.31 | 17.96 | 17.42 | 15.31 | 5.17 | 0.34 (mumblebee_fast_ct) | 0.30 |
| reduced_k4 | 3880 | 20.06 | 18.83 | 17.72 | 15.74 | 5.25 | 0.33 (mumblebee_fast_ct) | 0.30 |
| reduced_k2 | 3920 | 21.01 | 19.08 | 17.18 | 15.82 | 5.34 | 0.34 (mumblebee_fast_ct) | 0.31 |
| reduced_k0 | 5120 | 68.96 | 38.21 | 36.13 | 35.91 | 8.60 | 0.24 (mumblebee_fast_ct) | 0.24 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 24.81 | 21.82 | 21.49 | 18.82 | 5.13 | 0.27 (mumblebee_fast_ct) | 0.24 |
| reduced_k4 | 3880 | 23.64 | 23.06 | 21.65 | 19.35 | 5.31 | 0.27 (mumblebee_fast_ct) | 0.25 |
| reduced_k2 | 3920 | 23.37 | 23.57 | 21.07 | 19.47 | 5.33 | 0.27 (mumblebee_fast_ct) | 0.25 |
| reduced_k0 | 5120 | 81.34 | 47.22 | 44.80 | 45.34 | 8.59 | 0.19 (mumblebee_fast) | 0.19 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 27.65 | 25.79 | 25.46 | 22.50 | 5.12 | 0.23 (mumblebee_fast_ct) | 0.20 |
| reduced_k4 | 3880 | 26.57 | 27.57 | 25.83 | 22.94 | 5.28 | 0.23 (mumblebee_fast_ct) | 0.20 |
| reduced_k2 | 3920 | 26.03 | 27.46 | 24.66 | 23.44 | 5.28 | 0.23 (mumblebee_fast_ct) | 0.21 |
| reduced_k0 | 5120 | 80.50 | 56.18 | 53.46 | 54.95 | 8.62 | 0.16 (mumblebee_fast) | 0.16 |

Cold cells: median ms of the solve alone; setup is its own mode.

### reduced, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 10.98 | 19.24 | 12.11 | 12.81 | 26.30 | 2.40 (clarabel) | 2.17 |
| reduced_k4 | 3880 | 9.82 | 19.44 | 11.99 | 11.95 | 22.73 | 2.32 (clarabel) | 1.90 |
| reduced_k2 | 3920 | 9.55 | 18.63 | 11.38 | 12.17 | 21.56 | 2.26 (clarabel) | 1.90 |
| reduced_k0 | 5120 | 12.07 | 22.86 | 15.19 | 16.19 | 53.03 | 4.40 (clarabel) | 3.49 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 10.89 | 19.00 | 12.11 | 12.52 | 26.54 | 2.44 (clarabel) | 2.19 |
| reduced_k4 | 3880 | 9.95 | 19.48 | 11.96 | 12.60 | 21.86 | 2.20 (clarabel) | 1.83 |
| reduced_k2 | 3920 | 9.69 | 19.37 | 11.36 | 12.05 | 21.36 | 2.20 (clarabel) | 1.88 |
| reduced_k0 | 5120 | 12.09 | 23.20 | 15.25 | 16.42 | 53.61 | 4.43 (clarabel) | 3.51 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 10.97 | 18.66 | 12.23 | 12.54 | 26.51 | 2.42 (clarabel) | 2.17 |
| reduced_k4 | 3880 | 10.19 | 19.33 | 11.88 | 12.53 | 21.69 | 2.13 (clarabel) | 1.83 |
| reduced_k2 | 3920 | 9.50 | 19.41 | 11.30 | 12.07 | 21.39 | 2.25 (clarabel) | 1.89 |
| reduced_k0 | 5120 | 12.28 | 23.23 | 15.23 | 16.77 | 53.29 | 4.34 (clarabel) | 3.50 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 10.91 | 18.73 | 12.18 | 12.58 | 26.29 | 2.41 (clarabel) | 2.16 |
| reduced_k4 | 3880 | 10.15 | 19.57 | 11.95 | 12.53 | 21.91 | 2.16 (clarabel) | 1.83 |
| reduced_k2 | 3920 | 9.48 | 18.99 | 11.24 | 12.22 | 21.45 | 2.26 (clarabel) | 1.91 |
| reduced_k0 | 5120 | 12.17 | 22.98 | 15.23 | 17.04 | 53.49 | 4.39 (clarabel) | 3.51 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### reduced, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 29.52 | 33.24 | 25.45 | 24.79 | 31.44 | 1.27 (mumblebee_fast_ct) | 1.24 |
| reduced_k4 | 3880 | 26.67 | 33.87 | 25.49 | 23.46 | 28.00 | 1.19 (mumblebee_fast_ct) | 1.10 |
| reduced_k2 | 3920 | 27.04 | 32.83 | 24.66 | 24.40 | 26.88 | 1.10 (mumblebee_fast_ct) | 1.09 |
| reduced_k0 | 5120 | 57.45 | 51.58 | 42.73 | 43.16 | 61.53 | 1.44 (mumblebee_fast) | 1.44 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 32.10 | 36.97 | 29.54 | 27.88 | 31.70 | 1.14 (mumblebee_fast_ct) | 1.07 |
| reduced_k4 | 3880 | 29.98 | 38.31 | 29.63 | 28.34 | 27.19 | 0.96 (mumblebee_fast_ct) | 0.92 |
| reduced_k2 | 3920 | 30.72 | 38.45 | 28.45 | 27.90 | 26.68 | 0.96 (mumblebee_fast_ct) | 0.94 |
| reduced_k0 | 5120 | 81.02 | 61.49 | 51.37 | 52.33 | 62.21 | 1.21 (mumblebee_fast) | 1.21 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 35.79 | 40.49 | 33.71 | 31.36 | 31.65 | 1.01 (mumblebee_fast_ct) | 0.94 |
| reduced_k4 | 3880 | 33.85 | 42.41 | 33.53 | 31.88 | 27.01 | 0.85 (mumblebee_fast_ct) | 0.81 |
| reduced_k2 | 3920 | 32.88 | 42.95 | 32.36 | 31.54 | 26.68 | 0.85 (mumblebee_fast_ct) | 0.82 |
| reduced_k0 | 5120 | 93.66 | 70.46 | 60.04 | 62.21 | 61.90 | 1.03 (mumblebee_fast) | 1.03 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 38.61 | 44.54 | 37.66 | 35.02 | 31.41 | 0.90 (mumblebee_fast_ct) | 0.83 |
| reduced_k4 | 3880 | 36.73 | 47.03 | 37.78 | 35.47 | 27.18 | 0.77 (mumblebee_fast_ct) | 0.72 |
| reduced_k2 | 3920 | 35.46 | 46.46 | 35.87 | 35.64 | 26.71 | 0.75 (clarabel) | 0.74 |
| reduced_k0 | 5120 | 92.65 | 79.08 | 68.61 | 72.05 | 62.06 | 0.90 (mumblebee_fast) | 0.90 |

Setup + solve cells: median ms of a cold setup plus its solve.

### reduced, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 17.75 (18.10) | 13.96 (14.03) | 13.31 (13.39) | 11.94 (12.12) | 0.963 (1.16) | 0.08 (mumblebee_fast_ct) | 0.07 |
| reduced_k4 | 3880 | 16.78 (16.98) | 14.34 (14.43) | 13.51 (13.64) | 11.63 (11.71) | 0.978 (1.17) | 0.08 (mumblebee_fast_ct) | 0.07 |
| reduced_k2 | 3920 | 16.87 (17.68) | 14.44 (14.60) | 13.05 (13.15) | 11.89 (12.00) | 1.01 (1.14) | 0.08 (mumblebee_fast_ct) | 0.08 |
| reduced_k0 | 5120 | 45.40 (45.80) | 28.35 (28.54) | 27.53 (27.64) | 27.54 (27.77) | 1.70 (1.86) | 0.06 (mumblebee_fast) | 0.06 |

Warm cells: median (max) ms of update + warm start + solve.

### reduced, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 20.70 (21.09) | 17.72 (17.94) | 17.41 (17.57) | 15.31 (15.41) | 0.968 (1.15) | 0.06 (mumblebee_fast_ct) | 0.06 |
| reduced_k4 | 3880 | 20.11 (20.51) | 18.76 (23.04) | 17.47 (21.65) | 15.57 (19.32) | 0.969 (1.18) | 0.06 (mumblebee_fast_ct) | 0.06 |
| reduced_k2 | 3920 | 21.10 (21.48) | 19.09 (23.82) | 17.39 (21.74) | 15.60 (19.40) | 0.992 (1.17) | 0.06 (mumblebee_fast_ct) | 0.06 |
| reduced_k0 | 5120 | 68.01 (68.35) | 38.17 (38.39) | 36.29 (36.58) | 36.16 (36.73) | 1.71 (1.85) | 0.05 (mumblebee_fast_ct) | 0.05 |

Warm cells: median (max) ms of update + warm start + solve.

### reduced, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 24.02 (24.60) | 21.51 (21.66) | 21.24 (21.49) | 19.08 (19.23) | 0.957 (1.09) | 0.05 (mumblebee_fast_ct) | 0.05 |
| reduced_k4 | 3880 | 23.68 (24.16) | 23.06 (27.67) | 21.66 (25.92) | 19.06 (22.83) | 0.971 (1.10) | 0.05 (mumblebee_fast_ct) | 0.04 |
| reduced_k2 | 3920 | 24.04 (24.50) | 22.77 (27.27) | 20.96 (25.03) | 19.48 (23.29) | 0.993 (1.14) | 0.05 (mumblebee_fast_ct) | 0.05 |
| reduced_k0 | 5120 | 81.30 (81.54) | 46.35 (46.84) | 44.61 (44.81) | 44.74 (45.08) | 1.71 (1.77) | 0.04 (mumblebee_fast) | 0.04 |

Warm cells: median (max) ms of update + warm start + solve.

### reduced, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| reduced_k8 | 3860 | 26.71 (27.08) | 25.52 (25.82) | 25.55 (25.96) | 22.65 (22.84) | 0.968 (1.07) | 0.04 (mumblebee_fast_ct) | 0.04 |
| reduced_k4 | 3880 | 26.77 (27.08) | 27.57 (27.72) | 25.87 (26.02) | 23.10 (23.22) | 0.988 (1.18) | 0.04 (mumblebee_fast_ct) | 0.04 |
| reduced_k2 | 3920 | 26.76 (27.05) | 27.49 (27.88) | 24.57 (24.72) | 23.13 (23.29) | 0.984 (1.18) | 0.04 (mumblebee_fast_ct) | 0.04 |
| reduced_k0 | 5120 | 79.53 (80.68) | 56.37 (56.71) | 52.53 (53.10) | 53.70 (54.27) | 1.72 (1.74) | 0.03 (mumblebee_fast) | 0.03 |

Warm cells: median (max) ms of update + warm start + solve.

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
| reduced_k8 | 10.89 | 19.00 | 12.11 | 12.52 | 26.54 |
| reduced_k4 | 9.95 | 19.48 | 11.96 | 12.60 | 21.86 |
| reduced_k2 | 9.69 | 19.37 | 11.36 | 12.05 | 21.36 |
| reduced_k0 | 12.09 | 23.20 | 15.25 | 16.42 | 53.61 |

## single_di_box

### single_di_box, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.329 | 0.089 | 0.688 | 0.496 | 0.354 | 0.082 | 0.100 | 0.028 | 0.34 (osqp) | 0.06 |
| di_box_N25 | 225 | 0.777 | 0.158 | 1.54 | 1.26 | 0.873 | 0.218 | 0.263 | 0.089 | 0.56 (hpipm) | 0.07 |
| di_box_N50 | 450 | 1.22 | 0.268 | 2.89 | 2.29 | 1.71 | 0.451 | 0.516 | 0.277 | 1.03 (hpipm) | 0.12 |
| di_box_N100 | 900 | 2.19 | 0.551 | 5.51 | 4.47 | 3.20 | 0.912 | 0.968 | 1.18 | 2.14 (hpipm) | 0.26 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_box, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.431 | 0.104 | 0.945 | 0.811 | 0.543 | 0.162 | 0.118 | 0.028 | 0.27 (hpipm) | 0.03 |
| di_box_N25 | 225 | 1.08 | 0.240 | 2.44 | 1.95 | 1.39 | 0.436 | 0.314 | 0.136 | 0.56 (hpipm) | 0.07 |
| di_box_N50 | 450 | 1.86 | 0.417 | 4.65 | 3.81 | 2.68 | 0.920 | 0.616 | 0.278 | 0.67 (hpipm) | 0.07 |
| di_box_N100 | 900 | 3.46 | 0.881 | 8.91 | 7.17 | 5.21 | 1.66 | 1.18 | 1.24 | 1.41 (hpipm) | 0.17 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_box, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.490 | 0.111 | 1.14 | 0.852 | 0.699 | 0.243 | 0.150 | 0.030 | 0.27 (hpipm) | 0.04 |
| di_box_N25 | 225 | 1.37 | 0.262 | 3.20 | 2.42 | 1.83 | 0.643 | 0.384 | 0.162 | 0.62 (hpipm) | 0.07 |
| di_box_N50 | 450 | 2.25 | 0.515 | 5.82 | 4.56 | 3.35 | 1.27 | 0.730 | 0.285 | 0.55 (hpipm) | 0.06 |
| di_box_N100 | 900 | 4.16 | 0.996 | 11.20 | 8.96 | 6.53 | 2.36 | 1.39 | 1.31 | 1.31 (hpipm) | 0.15 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_box, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.244 | 0.170 | 0.702 | 0.394 | 0.317 | 0.114 | 0.125 | 0.492 | 4.32 (osqp) | 1.25 |
| di_box_N25 | 225 | 0.611 | 0.197 | 1.46 | 0.908 | 0.694 | 0.354 | 0.294 | 1.48 | 7.53 (hpipm) | 1.63 |
| di_box_N50 | 450 | 1.04 | 0.304 | 2.66 | 1.65 | 1.33 | 0.581 | 0.443 | 2.89 | 9.53 (hpipm) | 1.76 |
| di_box_N100 | 900 | 1.75 | 0.488 | 4.82 | 2.91 | 2.49 | 1.03 | 0.711 | 2.66 | 5.44 (hpipm) | 0.91 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_box, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.245 | 0.200 | 0.570 | 0.482 | 0.327 | 0.116 | 0.125 | 0.501 | 4.33 (osqp) | 1.04 |
| di_box_N25 | 225 | 0.612 | 0.249 | 1.50 | 0.909 | 0.690 | 0.377 | 0.253 | 1.42 | 5.68 (hpipm) | 1.56 |
| di_box_N50 | 450 | 1.07 | 0.291 | 2.74 | 1.74 | 1.30 | 0.629 | 0.442 | 2.94 | 10.09 (hpipm) | 1.69 |
| di_box_N100 | 900 | 1.79 | 0.488 | 5.01 | 3.01 | 2.54 | 0.938 | 0.761 | 2.69 | 5.51 (hpipm) | 0.89 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_box, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.243 | 0.153 | 0.638 | 0.350 | 0.319 | 0.118 | 0.125 | 0.465 | 3.93 (osqp) | 1.33 |
| di_box_N25 | 225 | 0.670 | 0.197 | 1.64 | 0.841 | 0.707 | 0.329 | 0.274 | 1.46 | 7.40 (hpipm) | 1.74 |
| di_box_N50 | 450 | 1.04 | 0.376 | 2.81 | 1.70 | 1.30 | 0.594 | 0.478 | 2.87 | 7.63 (hpipm) | 1.69 |
| di_box_N100 | 900 | 1.88 | 0.431 | 5.10 | 3.02 | 2.48 | 0.968 | 0.811 | 2.73 | 6.34 (hpipm) | 0.90 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_box, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.568 | 0.260 | 1.38 | 0.890 | 0.674 | 0.196 | 0.226 | 0.520 | 2.65 (osqp) | 0.58 |
| di_box_N25 | 225 | 1.39 | 0.367 | 2.99 | 2.17 | 1.57 | 0.569 | 0.558 | 1.56 | 4.25 (hpipm) | 0.72 |
| di_box_N50 | 450 | 2.25 | 0.569 | 5.54 | 3.94 | 3.04 | 1.03 | 0.988 | 3.17 | 5.57 (hpipm) | 0.80 |
| di_box_N100 | 900 | 3.93 | 1.04 | 10.33 | 7.41 | 5.69 | 1.94 | 1.66 | 3.86 | 3.71 (hpipm) | 0.52 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_box, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.676 | 0.306 | 1.50 | 1.29 | 0.873 | 0.278 | 0.249 | 0.535 | 2.15 (piqp) | 0.41 |
| di_box_N25 | 225 | 1.70 | 0.486 | 3.95 | 2.83 | 2.08 | 0.819 | 0.563 | 1.55 | 3.20 (hpipm) | 0.55 |
| di_box_N50 | 450 | 2.90 | 0.711 | 7.39 | 5.55 | 3.98 | 1.55 | 1.05 | 3.20 | 4.50 (hpipm) | 0.58 |
| di_box_N100 | 900 | 5.26 | 1.37 | 13.90 | 10.18 | 7.76 | 2.59 | 1.95 | 3.93 | 2.86 (hpipm) | 0.39 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_box, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.746 | 0.258 | 1.76 | 1.20 | 1.02 | 0.362 | 0.274 | 0.492 | 1.91 (hpipm) | 0.41 |
| di_box_N25 | 225 | 2.07 | 0.456 | 4.83 | 3.24 | 2.53 | 0.978 | 0.658 | 1.61 | 3.54 (hpipm) | 0.50 |
| di_box_N50 | 450 | 3.30 | 0.895 | 8.63 | 6.28 | 4.63 | 1.86 | 1.20 | 3.14 | 3.51 (hpipm) | 0.50 |
| di_box_N100 | 900 | 6.06 | 1.44 | 16.30 | 11.99 | 8.99 | 3.30 | 2.21 | 4.05 | 2.81 (hpipm) | 0.34 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_box, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.305 (0.344) | 0.070 (0.078) | 0.610 (0.744) | 0.474 (0.580) | 0.357 (0.446) | 0.083 (0.091) | 0.107 (0.115) | 0.021 (0.023) | 0.30 (hpipm) | 0.04 |
| di_box_N25 | 225 | 0.701 (0.766) | 0.158 (0.168) | 1.49 (1.80) | 1.13 (1.38) | 0.874 (1.07) | 0.216 (0.225) | 0.242 (0.278) | 0.048 (0.053) | 0.30 (hpipm) | 0.04 |
| di_box_N50 | 450 | 1.16 (1.49) | 0.272 (0.325) | 2.88 (3.39) | 2.19 (2.64) | 1.64 (2.05) | 0.451 (0.499) | 0.488 (0.569) | 0.081 (0.086) | 0.30 (hpipm) | 0.04 |
| di_box_N100 | 900 | 2.09 (2.47) | 0.580 (0.666) | 5.38 (6.48) | 4.30 (5.14) | 3.16 (3.80) | 0.856 (0.878) | 0.887 (0.986) | 0.585 (0.769) | 1.01 (hpipm) | 0.14 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_box, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.435 (0.452) | 0.091 (0.097) | 1.03 (1.10) | 0.813 (0.911) | 0.581 (0.610) | 0.161 (0.167) | 0.136 (0.156) | 0.020 (0.022) | 0.22 (hpipm) | 0.02 |
| di_box_N25 | 225 | 0.978 (1.10) | 0.211 (0.225) | 2.39 (2.46) | 1.82 (1.86) | 1.41 (1.44) | 0.425 (0.452) | 0.299 (0.326) | 0.050 (0.057) | 0.24 (hpipm) | 0.03 |
| di_box_N50 | 450 | 1.76 (1.93) | 0.444 (0.486) | 4.70 (4.79) | 3.64 (3.70) | 2.69 (2.76) | 0.860 (0.891) | 0.606 (0.630) | 0.083 (0.091) | 0.19 (hpipm) | 0.02 |
| di_box_N100 | 900 | 3.32 (3.72) | 0.813 (0.823) | 8.95 (9.08) | 7.11 (7.18) | 5.20 (5.23) | 1.60 (1.65) | 1.10 (1.15) | 0.553 (0.829) | 0.68 (hpipm) | 0.08 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_box, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 90 | 0.522 (0.586) | 0.108 (0.133) | 1.75 (1.86) | 0.955 (1.07) | 0.756 (0.847) | 0.159 (0.237) | 0.168 (0.197) | 0.025 (0.029) | 0.23 (hpipm) | 0.03 |
| di_box_N25 | 225 | 1.25 (1.29) | 0.234 (0.272) | 4.27 (4.40) | 2.36 (2.41) | 1.77 (1.81) | 0.428 (0.642) | 0.393 (0.433) | 0.063 (0.069) | 0.27 (hpipm) | 0.03 |
| di_box_N50 | 450 | 2.17 (2.33) | 0.491 (0.508) | 7.96 (8.17) | 4.52 (4.58) | 3.33 (3.40) | 0.854 (1.26) | 0.734 (0.817) | 0.108 (0.117) | 0.22 (hpipm) | 0.02 |
| di_box_N100 | 900 | 4.14 (4.46) | 0.880 (0.947) | 15.16 (16.35) | 8.80 (9.68) | 6.52 (7.23) | 1.57 (2.28) | 1.40 (1.51) | 0.580 (0.825) | 0.66 (hpipm) | 0.07 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_box, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_box_N10 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 9 | 5 / 7 / -- / 9 | 5 / 7 / -- / 9 | 25 / 50 / -- / 75 | 5 / 6 / -- / 8 | 0 / 0 / -- / 0 |
| di_box_N25 | 5 / 7 / -- / 9 | 4 / 7 / -- / 9 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
| di_box_N50 | 4 / 7 / -- / 9 | 4 / 7 / -- / 8 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 5 / 8 / -- / 10 | 25 / 50 / -- / 75 | 6 / 8 / -- / 10 | 0 / 0 / -- / 0 |
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
| di_box_N10 | 0.245 | 0.200 | 0.570 | 0.482 | 0.327 | 0.116 | 0.125 | 0.501 |
| di_box_N25 | 0.612 | 0.249 | 1.50 | 0.909 | 0.690 | 0.377 | 0.253 | 1.42 |
| di_box_N50 | 1.07 | 0.291 | 2.74 | 1.74 | 1.30 | 0.629 | 0.442 | 2.94 |
| di_box_N100 | 1.79 | 0.488 | 5.01 | 3.01 | 2.54 | 0.938 | 0.761 | 2.69 |

## single_di_soc

### single_di_soc, cold, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.320 | 0.416 | 0.358 | 0.310 | 0.101 | 0.32 (mumblebee_fast_ct) | 0.28 |
| di_soc_N25 | 225 | 0.924 | 1.09 | 0.980 | 0.870 | 0.442 | 0.51 (mumblebee_fast_ct) | 0.45 |
| di_soc_N50 | 450 | 1.47 | 2.18 | 1.85 | 1.76 | 1.00 | 0.68 (clarabel) | 0.54 |
| di_soc_N100 | 900 | 2.70 | 4.09 | 3.77 | 3.20 | 1.79 | 0.66 (clarabel) | 0.48 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_soc, cold, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.472 | 0.616 | 0.502 | 0.432 | 0.097 | 0.22 (mumblebee_fast_ct) | 0.19 |
| di_soc_N25 | 225 | 1.26 | 1.48 | 1.33 | 1.17 | 0.575 | 0.49 (mumblebee_fast_ct) | 0.43 |
| di_soc_N50 | 450 | 2.26 | 2.92 | 2.73 | 2.32 | 1.44 | 0.63 (clarabel) | 0.53 |
| di_soc_N100 | 900 | 4.27 | 5.53 | 5.02 | 4.33 | 2.07 | 0.48 (clarabel) | 0.41 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_soc, cold, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.519 | 0.693 | 0.581 | 0.544 | 0.123 | 0.24 (clarabel) | 0.21 |
| di_soc_N25 | 225 | 1.38 | 1.80 | 1.61 | 1.45 | 0.597 | 0.43 (clarabel) | 0.37 |
| di_soc_N50 | 450 | 2.64 | 3.63 | 3.15 | 2.89 | 1.34 | 0.51 (clarabel) | 0.43 |
| di_soc_N100 | 900 | 4.86 | 6.82 | 6.15 | 5.51 | 2.01 | 0.41 (clarabel) | 0.33 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_soc, cold, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.541 | 0.659 | 0.613 | 0.508 | 0.125 | 0.25 (mumblebee_fast_ct) | 0.20 |
| di_soc_N25 | 225 | 1.39 | 1.91 | 1.66 | 1.55 | 0.633 | 0.46 (clarabel) | 0.38 |
| di_soc_N50 | 450 | 2.80 | 3.99 | 3.57 | 3.24 | 1.41 | 0.51 (clarabel) | 0.40 |
| di_soc_N100 | 900 | 5.55 | 6.85 | 6.37 | 5.63 | 2.13 | 0.38 (clarabel) | 0.33 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_di_soc, setup, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.250 | 0.519 | 0.323 | 0.287 | 0.499 | 2.00 (clarabel) | 1.54 |
| di_soc_N25 | 225 | 0.704 | 1.13 | 0.679 | 0.656 | 1.16 | 1.77 (mumblebee_fast_ct) | 1.71 |
| di_soc_N50 | 450 | 0.927 | 2.06 | 1.12 | 1.16 | 1.97 | 2.12 (clarabel) | 1.75 |
| di_soc_N100 | 900 | 1.70 | 3.63 | 2.29 | 2.13 | 3.47 | 2.04 (clarabel) | 1.52 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_soc, setup, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.245 | 0.496 | 0.314 | 0.280 | 0.526 | 2.15 (clarabel) | 1.67 |
| di_soc_N25 | 225 | 0.599 | 1.11 | 0.647 | 0.651 | 1.26 | 2.11 (clarabel) | 1.95 |
| di_soc_N50 | 450 | 0.956 | 2.10 | 1.30 | 1.14 | 1.98 | 2.07 (clarabel) | 1.52 |
| di_soc_N100 | 900 | 1.71 | 3.63 | 2.25 | 2.14 | 3.42 | 1.99 (clarabel) | 1.52 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_soc, setup, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.266 | 0.532 | 0.303 | 0.337 | 0.486 | 1.82 (clarabel) | 1.60 |
| di_soc_N25 | 225 | 0.579 | 1.20 | 0.787 | 0.635 | 1.29 | 2.23 (clarabel) | 1.64 |
| di_soc_N50 | 450 | 0.975 | 2.24 | 1.11 | 1.39 | 1.90 | 1.95 (clarabel) | 1.72 |
| di_soc_N100 | 900 | 1.77 | 3.75 | 2.25 | 2.34 | 3.38 | 1.91 (clarabel) | 1.50 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_soc, setup, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.251 | 0.497 | 0.308 | 0.273 | 0.492 | 1.96 (clarabel) | 1.60 |
| di_soc_N25 | 225 | 0.593 | 1.22 | 0.771 | 0.678 | 1.26 | 2.13 (clarabel) | 1.64 |
| di_soc_N50 | 450 | 0.942 | 2.10 | 1.35 | 1.29 | 1.96 | 2.08 (clarabel) | 1.45 |
| di_soc_N100 | 900 | 1.84 | 3.82 | 2.37 | 2.39 | 3.43 | 1.86 (clarabel) | 1.45 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_di_soc, cold_total, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.575 | 0.929 | 0.686 | 0.597 | 0.615 | 1.07 (clarabel) | 0.90 |
| di_soc_N25 | 225 | 1.63 | 2.24 | 1.64 | 1.52 | 1.60 | 1.05 (mumblebee_fast_ct) | 0.98 |
| di_soc_N50 | 450 | 2.39 | 4.21 | 2.96 | 2.89 | 2.97 | 1.24 (clarabel) | 1.00 |
| di_soc_N100 | 900 | 4.39 | 7.64 | 6.02 | 5.28 | 5.24 | 1.19 (clarabel) | 0.87 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_soc, cold_total, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.717 | 1.11 | 0.814 | 0.713 | 0.623 | 0.87 (mumblebee_fast_ct) | 0.77 |
| di_soc_N25 | 225 | 1.86 | 2.60 | 1.99 | 1.84 | 1.82 | 0.99 (mumblebee_fast_ct) | 0.92 |
| di_soc_N50 | 450 | 3.22 | 5.02 | 4.05 | 3.46 | 3.41 | 1.06 (clarabel) | 0.84 |
| di_soc_N100 | 900 | 5.99 | 9.10 | 7.27 | 6.60 | 5.67 | 0.95 (clarabel) | 0.78 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_soc, cold_total, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.784 | 1.21 | 0.891 | 0.857 | 0.609 | 0.78 (clarabel) | 0.68 |
| di_soc_N25 | 225 | 1.96 | 3.02 | 2.39 | 2.09 | 1.89 | 0.96 (clarabel) | 0.79 |
| di_soc_N50 | 450 | 3.66 | 5.77 | 4.26 | 4.19 | 3.19 | 0.87 (clarabel) | 0.75 |
| di_soc_N100 | 900 | 6.70 | 10.58 | 8.39 | 7.82 | 5.42 | 0.81 (clarabel) | 0.65 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_soc, cold_total, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.819 | 1.17 | 0.925 | 0.776 | 0.618 | 0.80 (mumblebee_fast_ct) | 0.67 |
| di_soc_N25 | 225 | 1.98 | 3.16 | 2.44 | 2.26 | 1.89 | 0.96 (clarabel) | 0.78 |
| di_soc_N50 | 450 | 3.75 | 6.14 | 4.78 | 4.53 | 3.37 | 0.90 (clarabel) | 0.71 |
| di_soc_N100 | 900 | 7.41 | 10.63 | 8.74 | 8.00 | 5.54 | 0.75 (clarabel) | 0.63 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_di_soc, warm, low

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.297 (0.314) | 0.388 (0.417) | 0.331 (0.340) | 0.293 (0.305) | 0.072 (0.126) | 0.24 (mumblebee_fast_ct) | 0.22 |
| di_soc_N25 | 225 | 0.745 (0.769) | 0.901 (1.09) | 0.767 (0.961) | 0.771 (0.961) | 0.269 (0.505) | 0.36 (clarabel) | 0.35 |
| di_soc_N50 | 450 | 1.33 (1.38) | 1.65 (2.05) | 1.47 (1.84) | 1.30 (1.58) | 0.471 (0.924) | 0.36 (mumblebee_fast_ct) | 0.32 |
| di_soc_N100 | 900 | 2.58 (2.63) | 3.19 (3.86) | 2.92 (3.57) | 2.52 (3.21) | 0.901 (1.69) | 0.36 (mumblebee_fast_ct) | 0.31 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_soc, warm, medium

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.418 (0.474) | 0.589 (0.675) | 0.483 (0.545) | 0.420 (0.480) | 0.098 (0.175) | 0.23 (clarabel) | 0.20 |
| di_soc_N25 | 225 | 1.14 (1.20) | 1.42 (1.47) | 1.28 (1.36) | 1.13 (1.20) | 0.355 (0.825) | 0.31 (mumblebee_fast_ct) | 0.28 |
| di_soc_N50 | 450 | 2.14 (2.21) | 2.76 (3.18) | 2.45 (2.86) | 2.16 (2.44) | 0.614 (1.33) | 0.29 (clarabel) | 0.25 |
| di_soc_N100 | 900 | 3.66 (4.19) | 4.73 (5.48) | 4.35 (4.97) | 3.86 (4.30) | 1.17 (2.40) | 0.32 (clarabel) | 0.27 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_soc, warm, e8

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.511 (0.589) | 0.662 (0.778) | 0.572 (0.651) | 0.487 (0.570) | 0.124 (0.192) | 0.25 (mumblebee_fast_ct) | 0.22 |
| di_soc_N25 | 225 | 1.26 (1.40) | 2.51 (2.65) | 1.44 (1.59) | 1.28 (1.41) | 0.439 (0.830) | 0.35 (clarabel) | 0.30 |
| di_soc_N50 | 450 | 2.46 (2.83) | 3.17 (3.88) | 2.82 (3.48) | 2.41 (2.95) | 0.768 (1.73) | 0.32 (mumblebee_fast_ct) | 0.27 |
| di_soc_N100 | 900 | 4.66 (5.42) | 6.13 (6.94) | 5.53 (6.22) | 4.83 (5.50) | 1.21 (2.47) | 0.26 (clarabel) | 0.22 |

Warm cells: median (max) ms of update + warm start + solve.

### single_di_soc, warm, high

| instance | vars | clarabel | mumblebee | mumblebee_fast | mumblebee_fast_ct | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| di_soc_N10 | 90 | 0.525 (0.621) | 1.15 (1.22) | 0.653 (0.681) | 0.565 (0.641) | 0.125 (0.183) | 0.24 (clarabel) | 0.19 |
| di_soc_N25 | 225 | 1.32 (1.54) | 2.65 (2.87) | 1.72 (1.95) | 1.40 (1.58) | 0.455 (0.793) | 0.35 (clarabel) | 0.27 |
| di_soc_N50 | 450 | 2.48 (3.07) | 5.14 (5.83) | 3.09 (3.80) | 2.68 (3.26) | 0.765 (5.40) | 0.31 (clarabel) | 0.25 |
| di_soc_N100 | 900 | 4.78 (5.81) | 9.54 (10.92) | 6.05 (7.31) | 5.41 (6.56) | 1.42 (2.51) | 0.30 (clarabel) | 0.23 |

Warm cells: median (max) ms of update + warm start + solve.

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
| di_soc_N10 | 0.245 | 0.496 | 0.314 | 0.280 | 0.526 |
| di_soc_N25 | 0.599 | 1.11 | 0.647 | 0.651 | 1.26 |
| di_soc_N50 | 0.956 | 2.10 | 1.30 | 1.14 | 1.98 |
| di_soc_N100 | 1.71 | 3.63 | 2.25 | 2.14 | 3.42 |

## single_quad

### single_quad, cold, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.677 | 0.104 | 1.06 | 0.864 | 0.690 | 0.197 | 0.233 | 0.030 | 0.29 (hpipm) | 0.03 |
| quad_N25 | 400 | 1.79 | 0.249 | 2.62 | 2.18 | 1.79 | 0.537 | 0.591 | 0.122 | 0.49 (hpipm) | 0.06 |
| quad_N50 | 800 | 3.29 | 0.404 | 5.07 | 3.76 | 3.55 | 1.07 | 1.20 | 0.224 | 0.56 (hpipm) | 0.06 |
| quad_N100 | 1600 | 6.28 | 0.976 | 9.57 | 6.91 | 6.89 | 2.09 | 2.90 | 2.57 | 2.63 (hpipm) | 0.37 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_quad, cold, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.905 | 0.119 | 1.51 | 1.24 | 0.989 | 0.377 | 0.300 | 0.030 | 0.25 (hpipm) | 0.02 |
| quad_N25 | 400 | 2.28 | 0.298 | 3.72 | 2.88 | 2.55 | 1.06 | 0.785 | 0.117 | 0.39 (hpipm) | 0.04 |
| quad_N50 | 800 | 4.43 | 0.530 | 7.15 | 5.14 | 5.00 | 2.01 | 1.51 | 0.233 | 0.44 (hpipm) | 0.05 |
| quad_N100 | 1600 | 8.33 | 1.31 | 13.75 | 9.81 | 9.92 | 3.90 | 3.21 | 2.54 | 1.95 (hpipm) | 0.26 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_quad, cold, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.998 | 0.128 | 1.73 | 1.41 | 1.17 | 0.593 | 0.341 | 0.042 | 0.33 (hpipm) | 0.03 |
| quad_N25 | 400 | 2.52 | 0.316 | 4.33 | 3.32 | 2.92 | 1.61 | 0.897 | 0.156 | 0.49 (hpipm) | 0.05 |
| quad_N50 | 800 | 4.76 | 0.577 | 8.12 | 5.88 | 5.82 | 3.04 | 1.69 | 0.344 | 0.60 (hpipm) | 0.06 |
| quad_N100 | 1600 | 9.30 | 1.50 | 15.48 | 11.11 | 11.44 | 5.89 | 3.54 | 2.61 | 1.74 (hpipm) | 0.23 |

Cold cells: median ms of the solve alone; setup is its own mode.

### single_quad, setup, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.418 | 0.125 | 1.66 | 0.930 | 0.749 | 0.277 | 0.295 | 1.33 | 10.70 (hpipm) | 1.44 |
| quad_N25 | 400 | 0.966 | 0.132 | 3.65 | 1.92 | 1.64 | 0.665 | 0.545 | 2.81 | 21.25 (hpipm) | 1.46 |
| quad_N50 | 800 | 1.73 | 0.214 | 6.85 | 3.11 | 3.05 | 1.14 | 1.10 | 4.97 | 23.18 (hpipm) | 1.60 |
| quad_N100 | 1600 | 3.17 | 0.446 | 13.30 | 5.66 | 5.85 | 2.17 | 2.37 | 7.76 | 17.40 (hpipm) | 1.37 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_quad, setup, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.421 | 0.137 | 1.78 | 0.906 | 0.756 | 0.276 | 0.290 | 1.31 | 9.56 (hpipm) | 1.45 |
| quad_N25 | 400 | 0.946 | 0.169 | 3.61 | 1.84 | 1.65 | 0.662 | 0.542 | 2.77 | 16.40 (hpipm) | 1.50 |
| quad_N50 | 800 | 1.81 | 0.265 | 6.91 | 2.98 | 3.02 | 1.16 | 1.00 | 4.92 | 18.58 (hpipm) | 1.65 |
| quad_N100 | 1600 | 3.18 | 0.643 | 13.29 | 5.74 | 6.01 | 2.25 | 2.25 | 7.77 | 12.08 (hpipm) | 1.35 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_quad, setup, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.408 | 0.129 | 1.55 | 0.889 | 0.755 | 0.273 | 0.280 | 1.30 | 10.08 (hpipm) | 1.47 |
| quad_N25 | 400 | 0.893 | 0.171 | 3.67 | 1.84 | 1.66 | 0.653 | 0.554 | 2.74 | 16.01 (hpipm) | 1.49 |
| quad_N50 | 800 | 1.78 | 0.260 | 6.88 | 3.03 | 3.04 | 1.17 | 1.05 | 4.90 | 18.85 (hpipm) | 1.62 |
| quad_N100 | 1600 | 3.29 | 0.480 | 12.88 | 5.71 | 6.03 | 2.19 | 2.10 | 7.72 | 16.10 (hpipm) | 1.35 |

Setup cells: median ms of the setup (scaling, ordering, factorization) of a cold solve.

### single_quad, cold_total, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 1.09 | 0.238 | 2.71 | 1.79 | 1.42 | 0.476 | 0.525 | 1.37 | 5.75 (hpipm) | 0.76 |
| quad_N25 | 400 | 2.74 | 0.384 | 6.27 | 4.10 | 3.43 | 1.20 | 1.13 | 2.94 | 7.67 (hpipm) | 0.72 |
| quad_N50 | 800 | 5.05 | 0.623 | 11.95 | 6.86 | 6.60 | 2.20 | 2.30 | 5.24 | 8.41 (hpipm) | 0.76 |
| quad_N100 | 1600 | 9.45 | 1.41 | 22.86 | 12.57 | 12.74 | 4.26 | 5.23 | 10.29 | 7.32 (hpipm) | 0.82 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_quad, cold_total, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 1.33 | 0.267 | 3.28 | 2.13 | 1.74 | 0.653 | 0.590 | 1.34 | 5.02 (hpipm) | 0.63 |
| quad_N25 | 400 | 3.16 | 0.469 | 7.35 | 4.73 | 4.20 | 1.72 | 1.33 | 2.90 | 6.18 (hpipm) | 0.61 |
| quad_N50 | 800 | 6.22 | 0.795 | 14.05 | 8.13 | 8.02 | 3.16 | 2.51 | 5.25 | 6.60 (hpipm) | 0.65 |
| quad_N100 | 1600 | 11.51 | 2.01 | 27.13 | 15.62 | 15.91 | 6.13 | 5.50 | 10.36 | 5.16 (hpipm) | 0.66 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_quad, cold_total, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 1.41 | 0.256 | 3.35 | 2.31 | 1.93 | 0.865 | 0.620 | 1.35 | 5.27 (hpipm) | 0.58 |
| quad_N25 | 400 | 3.47 | 0.498 | 8.08 | 5.13 | 4.62 | 2.27 | 1.47 | 2.91 | 5.84 (hpipm) | 0.57 |
| quad_N50 | 800 | 6.54 | 0.851 | 14.97 | 9.00 | 8.86 | 4.19 | 2.75 | 5.26 | 6.19 (hpipm) | 0.58 |
| quad_N100 | 1600 | 12.61 | 1.99 | 28.43 | 16.83 | 17.50 | 8.06 | 5.56 | 10.32 | 5.19 (hpipm) | 0.61 |

Setup + solve cells: median ms of a cold setup plus its solve.

### single_quad, warm, low

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.533 (0.651) | 0.071 (0.094) | 0.786 (1.10) | 0.626 (0.894) | 0.530 (0.745) | 0.192 (0.198) | 0.199 (0.248) | 0.030 (0.033) | 0.43 (hpipm) | 0.05 |
| quad_N25 | 400 | 1.42 (1.73) | 0.189 (0.244) | 1.96 (2.49) | 1.61 (1.98) | 1.31 (1.74) | 0.526 (0.534) | 0.500 (0.584) | 0.073 (0.077) | 0.39 (hpipm) | 0.05 |
| quad_N50 | 800 | 2.69 (3.24) | 0.354 (0.506) | 3.93 (4.96) | 2.75 (3.52) | 2.63 (3.40) | 1.04 (1.08) | 0.930 (1.13) | 0.133 (0.139) | 0.38 (hpipm) | 0.05 |
| quad_N100 | 1600 | 5.15 (6.21) | 0.732 (0.984) | 7.25 (9.41) | 5.31 (6.87) | 5.07 (6.52) | 1.99 (2.01) | 2.39 (2.73) | 0.438 (2.15) | 0.60 (hpipm) | 0.08 |

Warm cells: median (max) ms of update + warm start + solve.

### single_quad, warm, medium

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.636 (0.845) | 0.075 (0.108) | 1.23 (1.52) | 0.973 (1.24) | 0.831 (1.05) | 0.361 (0.370) | 0.242 (0.304) | 0.029 (0.032) | 0.39 (hpipm) | 0.03 |
| quad_N25 | 400 | 1.94 (2.24) | 0.188 (0.277) | 3.11 (3.66) | 2.25 (2.67) | 2.06 (2.45) | 1.03 (1.08) | 0.669 (0.795) | 0.074 (0.076) | 0.39 (hpipm) | 0.03 |
| quad_N50 | 800 | 3.64 (4.30) | 0.402 (0.587) | 5.98 (7.07) | 4.19 (4.89) | 4.05 (4.83) | 1.98 (2.04) | 1.25 (1.49) | 0.140 (0.150) | 0.35 (hpipm) | 0.03 |
| quad_N100 | 1600 | 7.07 (8.29) | 0.760 (1.09) | 11.55 (13.72) | 8.11 (9.53) | 8.20 (9.75) | 3.83 (3.88) | 2.63 (3.03) | 0.438 (2.16) | 0.58 (hpipm) | 0.05 |

Warm cells: median (max) ms of update + warm start + solve.

### single_quad, warm, high

| instance | vars | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc | sheafmpc / best other | sheafmpc / mumblebee_fast |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 160 | 0.814 (1.05) | 0.077 (0.122) | 2.94 (3.31) | 1.17 (1.47) | 0.974 (1.28) | 0.368 (0.579) | 0.317 (0.345) | 0.043 (0.045) | 0.57 (hpipm) | 0.04 |
| quad_N25 | 400 | 2.11 (2.72) | 0.202 (0.333) | 3.75 (4.72) | 2.65 (3.39) | 2.45 (3.16) | 1.04 (1.63) | 0.749 (0.933) | 0.113 (0.119) | 0.56 (hpipm) | 0.04 |
| quad_N50 | 800 | 4.03 (5.09) | 0.370 (0.670) | 7.03 (9.07) | 4.95 (6.54) | 4.83 (6.27) | 1.98 (3.07) | 1.43 (1.70) | 0.218 (0.224) | 0.59 (hpipm) | 0.04 |
| quad_N100 | 1600 | 8.06 (10.28) | 0.926 (1.54) | 13.58 (17.54) | 9.67 (12.34) | 9.86 (12.76) | 3.81 (5.91) | 2.99 (3.33) | 0.444 (2.18) | 0.48 (hpipm) | 0.05 |

Warm cells: median (max) ms of update + warm start + solve.

### single_quad, cold, iterations (median over the QPs; low / medium / high)

| instance | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| quad_N10 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |
| quad_N25 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |
| quad_N50 | 5 / 7 / -- / 8 | 4 / 6 / -- / 7 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 5 / 7 / -- / 8 | 0 / 0 / -- / 0 |
| quad_N100 | 5 / 7 / -- / 8 | 4 / 5 / -- / 6 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 5 / 7 / -- / 8 | 25 / 50 / -- / 75 | 6 / 7 / -- / 9 | 20 / 20 / -- / 20 |

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
| quad_N10 | 0.421 | 0.137 | 1.78 | 0.906 | 0.756 | 0.276 | 0.290 | 1.31 |
| quad_N25 | 0.946 | 0.169 | 3.61 | 1.84 | 1.65 | 0.662 | 0.542 | 2.77 |
| quad_N50 | 1.81 | 0.265 | 6.91 | 2.98 | 3.02 | 1.16 | 1.00 | 4.92 |
| quad_N100 | 3.18 | 0.643 | 13.29 | 5.74 | 6.01 | 2.25 | 2.25 | 7.77 |

## Shifted geometric means (ms; shift 0.1 ms; failures charged the time limit) and failure rates

### cold, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.03 (0% fail) | 0.255 (0% fail) | 3.43 (0% fail) | 1.96 (0% fail) | 1.95 (0% fail) | 1.21 (0% fail) | 0.632 (0% fail) | 0.439 (0% fail) |
| fleet_grid_box | 2.45 (0% fail) | 2.04 (6% fail) | 4.93 (0% fail) | -- | -- | 9.75 (11% fail) | 1.17 (0% fail) | 1.09 (0% fail) |
| fleet_grid_box_b4 | 7.37 (0% fail) | -- | 9.24 (0% fail) | 7.02 (0% fail) | 6.60 (0% fail) | 14.41 (8% fail) | 4.65 (0% fail) | 2.08 (0% fail) |
| fleet_grid_soc | 14.26 (0% fail) | -- | 14.39 (0% fail) | -- | -- | -- | -- | 7.95 (0% fail) |
| fleet_grid_soc_b4 | 14.93 (0% fail) | -- | 10.54 (0% fail) | -- | -- | -- | -- | 4.98 (0% fail) |
| fleet_ring_box | 2.28 (0% fail) | 1.77 (6% fail) | 4.67 (0% fail) | -- | -- | 25.83 (22% fail) | 2.06 (6% fail) | 0.977 (0% fail) |
| fleet_ring_box_b4 | 4.64 (0% fail) | -- | 7.87 (0% fail) | 5.77 (0% fail) | 5.28 (0% fail) | 6.90 (4% fail) | 4.37 (4% fail) | 1.61 (0% fail) |
| fleet_ring_soc | 8.46 (0% fail) | -- | 10.05 (0% fail) | 9.41 (0% fail) | 8.48 (0% fail) | -- | -- | 4.76 (0% fail) |
| fleet_ring_soc_b4 | 8.68 (0% fail) | -- | 7.91 (0% fail) | 7.21 (0% fail) | 6.95 (0% fail) | -- | -- | 3.22 (0% fail) |
| osqprand | 4.80 (0% fail) | 1.46 (7% fail) | 16.78 (9% fail) | -- | -- | 3.27 (4% fail) | 2.83 (0% fail) | 0.943 (0% fail) |
| reduced | 22.14 (0% fail) | -- | 17.00 (0% fail) | 16.04 (0% fail) | 14.65 (0% fail) | -- | -- | 5.92 (0% fail) |
| single_di_box | 0.937 (0% fail) | 0.231 (0% fail) | 2.06 (0% fail) | 1.64 (0% fail) | 1.17 (0% fail) | 0.330 (0% fail) | 0.367 (0% fail) | 0.226 (0% fail) |
| single_di_soc | 1.08 (0% fail) | -- | 1.44 (0% fail) | 1.28 (0% fail) | 1.13 (0% fail) | -- | -- | 0.601 (0% fail) |
| single_quad | 2.28 (0% fail) | 0.345 (0% fail) | 3.44 (0% fail) | 2.66 (0% fail) | 2.38 (0% fail) | 0.738 (0% fail) | 0.868 (0% fail) | 0.310 (0% fail) |
| all | 4.80 (0% fail) | -- | 7.11 (1% fail) | -- | -- | -- | -- | 1.56 (0% fail) |

### cold, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.79 (0% fail) | 0.326 (0% fail) | 4.82 (0% fail) | 2.75 (0% fail) | 2.73 (0% fail) | 1.31 (0% fail) | 0.786 (0% fail) | 0.474 (0% fail) |
| fleet_grid_box | 3.33 (0% fail) | 1.10 (0% fail) | 6.71 (0% fail) | -- | -- | 35.25 (17% fail) | 1.52 (0% fail) | 1.12 (0% fail) |
| fleet_grid_box_b4 | 9.40 (0% fail) | -- | 12.12 (0% fail) | 9.21 (0% fail) | 8.62 (0% fail) | 38.55 (12% fail) | 6.21 (0% fail) | 2.11 (0% fail) |
| fleet_grid_soc | 20.82 (0% fail) | -- | 20.22 (0% fail) | -- | -- | -- | -- | 9.40 (0% fail) |
| fleet_grid_soc_b4 | 21.59 (0% fail) | -- | 14.62 (0% fail) | -- | -- | -- | -- | 5.90 (0% fail) |
| fleet_ring_box | 2.94 (0% fail) | 1.07 (0% fail) | 5.90 (0% fail) | -- | -- | 7.06 (6% fail) | 1.19 (0% fail) | 0.983 (0% fail) |
| fleet_ring_box_b4 | 5.96 (0% fail) | -- | 10.04 (0% fail) | 7.23 (0% fail) | 6.69 (0% fail) | 22.62 (8% fail) | 2.89 (0% fail) | 1.89 (0% fail) |
| fleet_ring_soc | 11.93 (0% fail) | -- | 13.90 (0% fail) | 12.75 (0% fail) | 11.34 (0% fail) | -- | -- | 5.63 (0% fail) |
| fleet_ring_soc_b4 | 11.96 (0% fail) | -- | 10.59 (0% fail) | 9.51 (0% fail) | 9.30 (0% fail) | -- | -- | 3.88 (0% fail) |
| osqprand | 6.16 (0% fail) | 1.55 (7% fail) | 62.79 (18% fail) | -- | -- | 10.36 (7% fail) | 3.54 (0% fail) | 1.04 (0% fail) |
| reduced | 28.11 (0% fail) | -- | 22.21 (0% fail) | 20.92 (0% fail) | 19.23 (0% fail) | -- | -- | 5.95 (0% fail) |
| single_di_box | 1.34 (0% fail) | 0.332 (0% fail) | 3.18 (0% fail) | 2.60 (0% fail) | 1.86 (0% fail) | 0.609 (0% fail) | 0.435 (0% fail) | 0.258 (0% fail) |
| single_di_soc | 1.57 (0% fail) | -- | 2.02 (0% fail) | 1.79 (0% fail) | 1.57 (0% fail) | -- | -- | 0.736 (0% fail) |
| single_quad | 2.97 (0% fail) | 0.429 (0% fail) | 4.90 (0% fail) | 3.69 (0% fail) | 3.39 (0% fail) | 1.37 (0% fail) | 1.07 (0% fail) | 0.320 (0% fail) |
| all | 6.48 (0% fail) | -- | 11.15 (2% fail) | -- | -- | -- | -- | 1.73 (0% fail) |

### cold, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc | 25.73 (0% fail) | -- | 24.36 (0% fail) | -- | -- | -- | -- | 9.99 (0% fail) |
| fleet_grid_soc_b4 | 25.62 (0% fail) | -- | 17.47 (0% fail) | -- | -- | -- | -- | 6.29 (0% fail) |
| fleet_ring_soc | 14.42 (0% fail) | -- | 16.48 (0% fail) | 15.04 (0% fail) | 13.35 (0% fail) | -- | -- | 6.06 (0% fail) |
| fleet_ring_soc_b4 | 14.12 (0% fail) | -- | 12.66 (0% fail) | 11.17 (0% fail) | 10.76 (0% fail) | -- | -- | 4.19 (0% fail) |
| reduced | 32.45 (0% fail) | -- | 27.28 (0% fail) | 25.73 (0% fail) | 23.84 (0% fail) | -- | -- | 5.93 (0% fail) |
| single_di_soc | 1.82 (0% fail) | -- | 2.37 (0% fail) | 2.08 (0% fail) | 1.93 (0% fail) | -- | -- | 0.761 (0% fail) |
| all | 14.71 (0% fail) | -- | 13.84 (0% fail) | -- | -- | -- | -- | 4.64 (0% fail) |

### cold, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 3.32 (0% fail) | 0.751 (4% fail) | 55.12 (20% fail) | 35.71 (20% fail) | 34.74 (20% fail) | 1.78 (0% fail) | 0.927 (0% fail) | 0.496 (0% fail) |
| fleet_grid_box | 4.00 (0% fail) | 3.09 (6% fail) | 7.80 (0% fail) | -- | -- | 16.56 (6% fail) | 1.80 (0% fail) | 1.11 (0% fail) |
| fleet_grid_box_b4 | 10.75 (0% fail) | -- | 14.09 (0% fail) | 10.82 (0% fail) | 10.05 (0% fail) | 26.22 (4% fail) | 6.48 (0% fail) | 2.15 (0% fail) |
| fleet_grid_soc | 27.69 (0% fail) | -- | 26.32 (0% fail) | -- | -- | -- | -- | 10.12 (0% fail) |
| fleet_grid_soc_b4 | 27.12 (0% fail) | -- | 18.94 (0% fail) | -- | -- | -- | -- | 6.55 (0% fail) |
| fleet_ring_box | 3.45 (0% fail) | 2.21 (6% fail) | 7.01 (0% fail) | -- | -- | 13.10 (6% fail) | 1.38 (0% fail) | 0.996 (0% fail) |
| fleet_ring_box_b4 | 6.81 (0% fail) | -- | 11.75 (0% fail) | 8.50 (0% fail) | 7.85 (0% fail) | 15.39 (0% fail) | 3.31 (0% fail) | 1.95 (0% fail) |
| fleet_ring_soc | 15.45 (0% fail) | -- | 17.88 (0% fail) | 16.64 (0% fail) | 14.39 (0% fail) | -- | -- | 6.23 (0% fail) |
| fleet_ring_soc_b4 | 15.10 (0% fail) | -- | 13.43 (0% fail) | 11.97 (0% fail) | 11.68 (0% fail) | -- | -- | 4.26 (0% fail) |
| osqprand | 7.16 (0% fail) | 5.86 (16% fail) | 56.83 (16% fail) | -- | -- | 6.71 (0% fail) | 4.16 (0% fail) | 1.06 (0% fail) |
| reduced | 35.23 (0% fail) | -- | 32.28 (0% fail) | 30.52 (0% fail) | 28.69 (0% fail) | -- | -- | 5.93 (0% fail) |
| single_di_box | 1.63 (0% fail) | 0.373 (0% fail) | 3.98 (0% fail) | 3.05 (0% fail) | 2.30 (0% fail) | 0.866 (0% fail) | 0.526 (0% fail) | 0.268 (0% fail) |
| single_di_soc | 1.89 (0% fail) | -- | 2.48 (0% fail) | 2.25 (0% fail) | 2.01 (0% fail) | -- | -- | 0.778 (0% fail) |
| single_quad | 3.34 (0% fail) | 0.482 (0% fail) | 5.72 (0% fail) | 4.29 (0% fail) | 4.03 (0% fail) | 2.07 (0% fail) | 1.20 (0% fail) | 0.378 (0% fail) |
| all | 7.82 (0% fail) | -- | 15.69 (4% fail) | -- | -- | -- | -- | 1.82 (0% fail) |

### setup, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.946 (0% fail) | 0.118 (0% fail) | 11.11 (0% fail) | 1.98 (0% fail) | 2.08 (0% fail) | 0.701 (0% fail) | 0.865 (0% fail) | 3.42 (0% fail) |
| fleet_grid_box | 1.16 (0% fail) | 1.03 (6% fail) | 2.62 (0% fail) | -- | -- | 4.76 (11% fail) | 0.507 (0% fail) | 2.96 (0% fail) |
| fleet_grid_box_b4 | 1.73 (0% fail) | -- | 4.21 (0% fail) | 2.93 (0% fail) | 2.99 (0% fail) | 6.07 (8% fail) | 0.781 (0% fail) | 5.79 (0% fail) |
| fleet_grid_soc | 3.03 (0% fail) | -- | 4.86 (0% fail) | -- | -- | -- | -- | 11.18 (0% fail) |
| fleet_grid_soc_b4 | 2.36 (0% fail) | -- | 3.77 (0% fail) | -- | -- | -- | -- | 7.57 (0% fail) |
| fleet_ring_box | 1.04 (0% fail) | 0.839 (6% fail) | 2.34 (0% fail) | -- | -- | 15.25 (22% fail) | 1.05 (6% fail) | 2.34 (0% fail) |
| fleet_ring_box_b4 | 1.49 (0% fail) | -- | 3.93 (0% fail) | 2.46 (0% fail) | 2.50 (0% fail) | 2.24 (4% fail) | 1.31 (4% fail) | 3.93 (0% fail) |
| fleet_ring_soc | 2.75 (0% fail) | -- | 4.37 (0% fail) | 2.81 (0% fail) | 3.05 (0% fail) | -- | -- | 7.88 (0% fail) |
| fleet_ring_soc_b4 | 2.02 (0% fail) | -- | 3.39 (0% fail) | 2.50 (0% fail) | 2.42 (0% fail) | -- | -- | 5.50 (0% fail) |
| osqprand | 1.92 (0% fail) | 0.824 (7% fail) | 84.44 (9% fail) | -- | -- | 2.80 (4% fail) | 1.22 (0% fail) | 7.55 (0% fail) |
| reduced | 10.56 (0% fail) | -- | 20.04 (0% fail) | 12.59 (0% fail) | 13.19 (0% fail) | -- | -- | 28.68 (0% fail) |
| single_di_box | 0.746 (0% fail) | 0.275 (0% fail) | 1.93 (0% fail) | 1.17 (0% fail) | 0.958 (0% fail) | 0.433 (0% fail) | 0.346 (0% fail) | 1.57 (0% fail) |
| single_di_soc | 0.761 (0% fail) | -- | 1.48 (0% fail) | 0.903 (0% fail) | 0.874 (0% fail) | -- | -- | 1.45 (0% fail) |
| single_quad | 1.26 (0% fail) | 0.211 (0% fail) | 4.91 (0% fail) | 2.39 (0% fail) | 2.20 (0% fail) | 0.850 (0% fail) | 0.831 (0% fail) | 3.49 (0% fail) |
| all | 1.76 (0% fail) | -- | 6.35 (1% fail) | -- | -- | -- | -- | 5.12 (0% fail) |

### setup, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.980 (0% fail) | 0.134 (0% fail) | 11.07 (0% fail) | 1.98 (0% fail) | 2.08 (0% fail) | 0.700 (0% fail) | 0.859 (0% fail) | 3.37 (0% fail) |
| fleet_grid_box | 1.16 (0% fail) | 0.314 (0% fail) | 2.62 (0% fail) | -- | -- | 9.74 (17% fail) | 0.538 (0% fail) | 3.10 (0% fail) |
| fleet_grid_box_b4 | 1.71 (0% fail) | -- | 4.20 (0% fail) | 2.89 (0% fail) | 2.96 (0% fail) | 8.07 (12% fail) | 0.775 (0% fail) | 5.71 (0% fail) |
| fleet_grid_soc | 3.00 (0% fail) | -- | 4.88 (0% fail) | -- | -- | -- | -- | 11.21 (0% fail) |
| fleet_grid_soc_b4 | 2.43 (0% fail) | -- | 3.86 (0% fail) | -- | -- | -- | -- | 7.54 (0% fail) |
| fleet_ring_box | 1.02 (0% fail) | 0.364 (0% fail) | 2.31 (0% fail) | -- | -- | 1.53 (6% fail) | 0.419 (0% fail) | 2.32 (0% fail) |
| fleet_ring_box_b4 | 1.48 (0% fail) | -- | 3.99 (0% fail) | 2.40 (0% fail) | 2.46 (0% fail) | 3.46 (8% fail) | 0.670 (0% fail) | 3.86 (0% fail) |
| fleet_ring_soc | 2.75 (0% fail) | -- | 4.35 (0% fail) | 2.81 (0% fail) | 2.91 (0% fail) | -- | -- | 7.81 (0% fail) |
| fleet_ring_soc_b4 | 2.01 (0% fail) | -- | 3.36 (0% fail) | 2.43 (0% fail) | 2.43 (0% fail) | -- | -- | 5.42 (0% fail) |
| osqprand | 1.92 (0% fail) | 0.717 (7% fail) | 215 (18% fail) | -- | -- | 4.08 (7% fail) | 1.21 (0% fail) | 7.56 (0% fail) |
| reduced | 10.61 (0% fail) | -- | 20.09 (0% fail) | 12.58 (0% fail) | 13.30 (0% fail) | -- | -- | 28.54 (0% fail) |
| single_di_box | 0.766 (0% fail) | 0.293 (0% fail) | 1.90 (0% fail) | 1.26 (0% fail) | 0.956 (0% fail) | 0.425 (0% fail) | 0.337 (0% fail) | 1.57 (0% fail) |
| single_di_soc | 0.730 (0% fail) | -- | 1.46 (0% fail) | 0.907 (0% fail) | 0.857 (0% fail) | -- | -- | 1.49 (0% fail) |
| single_quad | 1.25 (0% fail) | 0.268 (0% fail) | 4.96 (0% fail) | 2.34 (0% fail) | 2.23 (0% fail) | 0.856 (0% fail) | 0.802 (0% fail) | 3.46 (0% fail) |
| all | 1.76 (0% fail) | -- | 7.22 (2% fail) | -- | -- | -- | -- | 5.11 (0% fail) |

### setup, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc | 3.08 (0% fail) | -- | 4.81 (0% fail) | -- | -- | -- | -- | 11.05 (0% fail) |
| fleet_grid_soc_b4 | 2.42 (0% fail) | -- | 3.77 (0% fail) | -- | -- | -- | -- | 7.53 (0% fail) |
| fleet_ring_soc | 2.77 (0% fail) | -- | 4.36 (0% fail) | 2.81 (0% fail) | 2.90 (0% fail) | -- | -- | 7.79 (0% fail) |
| fleet_ring_soc_b4 | 2.08 (0% fail) | -- | 3.39 (0% fail) | 2.45 (0% fail) | 2.40 (0% fail) | -- | -- | 5.41 (0% fail) |
| reduced | 10.67 (0% fail) | -- | 20.04 (0% fail) | 12.57 (0% fail) | 13.36 (0% fail) | -- | -- | 28.39 (0% fail) |
| single_di_soc | 0.746 (0% fail) | -- | 1.54 (0% fail) | 0.907 (0% fail) | 0.953 (0% fail) | -- | -- | 1.44 (0% fail) |
| all | 2.66 (0% fail) | -- | 4.46 (0% fail) | -- | -- | -- | -- | 7.34 (0% fail) |

### setup, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 0.969 (0% fail) | 0.306 (4% fail) | 87.31 (20% fail) | 24.22 (20% fail) | 23.98 (20% fail) | 0.704 (0% fail) | 0.839 (0% fail) | 3.34 (0% fail) |
| fleet_grid_box | 1.23 (0% fail) | 1.04 (6% fail) | 2.61 (0% fail) | -- | -- | 2.04 (6% fail) | 0.578 (0% fail) | 2.91 (0% fail) |
| fleet_grid_box_b4 | 1.73 (0% fail) | -- | 4.17 (0% fail) | 2.90 (0% fail) | 2.95 (0% fail) | 2.88 (4% fail) | 0.699 (0% fail) | 5.69 (0% fail) |
| fleet_grid_soc | 3.08 (0% fail) | -- | 4.79 (0% fail) | -- | -- | -- | -- | 11.00 (0% fail) |
| fleet_grid_soc_b4 | 2.38 (0% fail) | -- | 3.80 (0% fail) | -- | -- | -- | -- | 7.66 (0% fail) |
| fleet_ring_box | 1.02 (0% fail) | 0.840 (6% fail) | 2.31 (0% fail) | -- | -- | 1.52 (6% fail) | 0.458 (0% fail) | 2.30 (0% fail) |
| fleet_ring_box_b4 | 1.49 (0% fail) | -- | 3.93 (0% fail) | 2.44 (0% fail) | 2.48 (0% fail) | 1.20 (0% fail) | 0.649 (0% fail) | 3.91 (0% fail) |
| fleet_ring_soc | 2.77 (0% fail) | -- | 4.42 (0% fail) | 3.07 (0% fail) | 2.93 (0% fail) | -- | -- | 7.73 (0% fail) |
| fleet_ring_soc_b4 | 2.04 (0% fail) | -- | 3.32 (0% fail) | 2.52 (0% fail) | 2.42 (0% fail) | -- | -- | 5.34 (0% fail) |
| osqprand | 1.92 (0% fail) | 2.91 (16% fail) | 170 (16% fail) | -- | -- | 1.66 (0% fail) | 1.19 (0% fail) | 7.52 (0% fail) |
| reduced | 10.64 (0% fail) | -- | 19.92 (0% fail) | 12.56 (0% fail) | 13.49 (0% fail) | -- | -- | 28.47 (0% fail) |
| single_di_box | 0.774 (0% fail) | 0.276 (0% fail) | 1.98 (0% fail) | 1.14 (0% fail) | 0.951 (0% fail) | 0.410 (0% fail) | 0.357 (0% fail) | 1.55 (0% fail) |
| single_di_soc | 0.736 (0% fail) | -- | 1.52 (0% fail) | 0.943 (0% fail) | 0.904 (0% fail) | -- | -- | 1.46 (0% fail) |
| single_quad | 1.24 (0% fail) | 0.237 (0% fail) | 4.79 (0% fail) | 2.33 (0% fail) | 2.23 (0% fail) | 0.853 (0% fail) | 0.795 (0% fail) | 3.44 (0% fail) |
| all | 1.77 (0% fail) | -- | 8.17 (4% fail) | -- | -- | -- | -- | 5.06 (0% fail) |

### cold_total, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.96 (0% fail) | 0.378 (0% fail) | 14.81 (0% fail) | 3.94 (0% fail) | 4.02 (0% fail) | 1.89 (0% fail) | 1.49 (0% fail) | 3.90 (0% fail) |
| fleet_grid_box | 3.61 (0% fail) | 2.86 (6% fail) | 7.49 (0% fail) | -- | -- | 13.15 (11% fail) | 1.69 (0% fail) | 4.02 (0% fail) |
| fleet_grid_box_b4 | 9.44 (0% fail) | -- | 13.41 (0% fail) | 9.86 (0% fail) | 9.53 (0% fail) | 18.93 (8% fail) | 5.78 (0% fail) | 7.64 (0% fail) |
| fleet_grid_soc | 18.43 (0% fail) | -- | 19.72 (0% fail) | -- | -- | -- | -- | 19.48 (0% fail) |
| fleet_grid_soc_b4 | 18.38 (0% fail) | -- | 14.64 (0% fail) | -- | -- | -- | -- | 12.45 (0% fail) |
| fleet_ring_box | 3.30 (0% fail) | 2.37 (6% fail) | 6.95 (0% fail) | -- | -- | 33.62 (22% fail) | 2.87 (6% fail) | 3.31 (0% fail) |
| fleet_ring_box_b4 | 6.10 (0% fail) | -- | 11.71 (0% fail) | 8.10 (0% fail) | 7.70 (0% fail) | 8.81 (4% fail) | 5.45 (4% fail) | 5.45 (0% fail) |
| fleet_ring_soc | 11.32 (0% fail) | -- | 14.38 (0% fail) | 12.15 (0% fail) | 11.47 (0% fail) | -- | -- | 12.57 (0% fail) |
| fleet_ring_soc_b4 | 10.94 (0% fail) | -- | 11.28 (0% fail) | 9.66 (0% fail) | 9.30 (0% fail) | -- | -- | 8.58 (0% fail) |
| osqprand | 6.76 (0% fail) | 2.11 (7% fail) | 99.74 (9% fail) | -- | -- | 5.96 (4% fail) | 4.07 (0% fail) | 9.00 (0% fail) |
| reduced | 33.09 (0% fail) | -- | 37.27 (0% fail) | 28.78 (0% fail) | 28.03 (0% fail) | -- | -- | 34.67 (0% fail) |
| single_di_box | 1.66 (0% fail) | 0.501 (0% fail) | 3.96 (0% fail) | 2.78 (0% fail) | 2.10 (0% fail) | 0.740 (0% fail) | 0.698 (0% fail) | 1.81 (0% fail) |
| single_di_soc | 1.81 (0% fail) | -- | 2.90 (0% fail) | 2.16 (0% fail) | 1.98 (0% fail) | -- | -- | 2.03 (0% fail) |
| single_quad | 3.52 (0% fail) | 0.554 (0% fail) | 8.32 (0% fail) | 5.04 (0% fail) | 4.55 (0% fail) | 1.56 (0% fail) | 1.67 (0% fail) | 3.86 (0% fail) |
| all | 6.74 (0% fail) | -- | 14.82 (1% fail) | -- | -- | -- | -- | 6.93 (0% fail) |

### cold_total, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 3.75 (0% fail) | 0.464 (0% fail) | 16.27 (0% fail) | 4.74 (0% fail) | 4.81 (0% fail) | 1.99 (0% fail) | 1.63 (0% fail) | 3.87 (0% fail) |
| fleet_grid_box | 4.50 (0% fail) | 1.45 (0% fail) | 9.27 (0% fail) | -- | -- | 40.69 (17% fail) | 2.08 (0% fail) | 4.20 (0% fail) |
| fleet_grid_box_b4 | 11.44 (0% fail) | -- | 16.28 (0% fail) | 12.02 (0% fail) | 11.52 (0% fail) | 43.49 (12% fail) | 7.36 (0% fail) | 7.57 (0% fail) |
| fleet_grid_soc | 25.06 (0% fail) | -- | 25.67 (0% fail) | -- | -- | -- | -- | 21.25 (0% fail) |
| fleet_grid_soc_b4 | 25.24 (0% fail) | -- | 18.90 (0% fail) | -- | -- | -- | -- | 13.41 (0% fail) |
| fleet_ring_box | 3.96 (0% fail) | 1.42 (0% fail) | 8.15 (0% fail) | -- | -- | 8.24 (6% fail) | 1.60 (0% fail) | 3.28 (0% fail) |
| fleet_ring_box_b4 | 7.45 (0% fail) | -- | 13.98 (0% fail) | 9.52 (0% fail) | 9.03 (0% fail) | 25.31 (8% fail) | 3.51 (0% fail) | 5.83 (0% fail) |
| fleet_ring_soc | 14.88 (0% fail) | -- | 18.29 (0% fail) | 15.53 (0% fail) | 14.22 (0% fail) | -- | -- | 13.46 (0% fail) |
| fleet_ring_soc_b4 | 14.27 (0% fail) | -- | 13.97 (0% fail) | 11.91 (0% fail) | 11.70 (0% fail) | -- | -- | 9.21 (0% fail) |
| osqprand | 8.12 (0% fail) | 2.07 (7% fail) | 259 (18% fail) | -- | -- | 14.13 (7% fail) | 4.79 (0% fail) | 9.12 (0% fail) |
| reduced | 39.43 (0% fail) | -- | 42.58 (0% fail) | 33.66 (0% fail) | 32.75 (0% fail) | -- | -- | 34.56 (0% fail) |
| single_di_box | 2.08 (0% fail) | 0.626 (0% fail) | 5.04 (0% fail) | 3.83 (0% fail) | 2.79 (0% fail) | 1.01 (0% fail) | 0.755 (0% fail) | 1.84 (0% fail) |
| single_di_soc | 2.28 (0% fail) | -- | 3.45 (0% fail) | 2.67 (0% fail) | 2.40 (0% fail) | -- | -- | 2.22 (0% fail) |
| single_quad | 4.19 (0% fail) | 0.688 (0% fail) | 9.83 (0% fail) | 6.01 (0% fail) | 5.60 (0% fail) | 2.20 (0% fail) | 1.85 (0% fail) | 3.84 (0% fail) |
| all | 8.44 (0% fail) | -- | 19.97 (2% fail) | -- | -- | -- | -- | 7.17 (0% fail) |

### cold_total, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc | 30.38 (0% fail) | -- | 29.89 (0% fail) | -- | -- | -- | -- | 21.60 (0% fail) |
| fleet_grid_soc_b4 | 29.25 (0% fail) | -- | 21.72 (0% fail) | -- | -- | -- | -- | 13.75 (0% fail) |
| fleet_ring_soc | 17.42 (0% fail) | -- | 20.87 (0% fail) | 17.82 (0% fail) | 16.23 (0% fail) | -- | -- | 13.85 (0% fail) |
| fleet_ring_soc_b4 | 16.51 (0% fail) | -- | 16.09 (0% fail) | 13.59 (0% fail) | 13.13 (0% fail) | -- | -- | 9.49 (0% fail) |
| reduced | 43.86 (0% fail) | -- | 47.62 (0% fail) | 38.48 (0% fail) | 37.44 (0% fail) | -- | -- | 34.40 (0% fail) |
| single_di_soc | 2.54 (0% fail) | -- | 3.89 (0% fail) | 2.97 (0% fail) | 2.86 (0% fail) | -- | -- | 2.20 (0% fail) |
| all | 18.07 (0% fail) | -- | 18.90 (0% fail) | -- | -- | -- | -- | 12.25 (0% fail) |

### cold_total, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 4.27 (0% fail) | 0.973 (4% fail) | 126 (20% fail) | 51.67 (20% fail) | 50.59 (20% fail) | 2.46 (0% fail) | 1.76 (0% fail) | 3.86 (0% fail) |
| fleet_grid_box | 5.28 (0% fail) | 3.93 (6% fail) | 10.35 (0% fail) | -- | -- | 18.08 (6% fail) | 2.41 (0% fail) | 3.97 (0% fail) |
| fleet_grid_box_b4 | 12.87 (0% fail) | -- | 18.22 (0% fail) | 13.64 (0% fail) | 12.95 (0% fail) | 28.51 (4% fail) | 7.43 (0% fail) | 7.58 (0% fail) |
| fleet_grid_soc | 32.27 (0% fail) | -- | 31.85 (0% fail) | -- | -- | -- | -- | 21.67 (0% fail) |
| fleet_grid_soc_b4 | 30.88 (0% fail) | -- | 23.29 (0% fail) | -- | -- | -- | -- | 14.18 (0% fail) |
| fleet_ring_box | 4.47 (0% fail) | 2.82 (6% fail) | 9.27 (0% fail) | -- | -- | 14.28 (6% fail) | 1.82 (0% fail) | 3.27 (0% fail) |
| fleet_ring_box_b4 | 8.31 (0% fail) | -- | 15.59 (0% fail) | 10.83 (0% fail) | 10.23 (0% fail) | 16.70 (0% fail) | 3.90 (0% fail) | 5.95 (0% fail) |
| fleet_ring_soc | 18.44 (0% fail) | -- | 22.34 (0% fail) | 19.86 (0% fail) | 17.29 (0% fail) | -- | -- | 13.97 (0% fail) |
| fleet_ring_soc_b4 | 17.43 (0% fail) | -- | 16.77 (0% fail) | 14.48 (0% fail) | 14.06 (0% fail) | -- | -- | 9.51 (0% fail) |
| osqprand | 9.15 (0% fail) | 7.55 (16% fail) | 214 (16% fail) | -- | -- | 8.67 (0% fail) | 5.36 (0% fail) | 9.09 (0% fail) |
| reduced | 46.46 (0% fail) | -- | 52.54 (0% fail) | 43.27 (0% fail) | 42.44 (0% fail) | -- | -- | 34.46 (0% fail) |
| single_di_box | 2.38 (0% fail) | 0.645 (0% fail) | 5.93 (0% fail) | 4.16 (0% fail) | 3.23 (0% fail) | 1.25 (0% fail) | 0.864 (0% fail) | 1.83 (0% fail) |
| single_di_soc | 2.61 (0% fail) | -- | 3.97 (0% fail) | 3.17 (0% fail) | 2.88 (0% fail) | -- | -- | 2.23 (0% fail) |
| single_quad | 4.56 (0% fail) | 0.715 (0% fail) | 10.48 (0% fail) | 6.60 (0% fail) | 6.24 (0% fail) | 2.90 (0% fail) | 1.97 (0% fail) | 3.86 (0% fail) |
| all | 9.83 (0% fail) | -- | 25.69 (4% fail) | -- | -- | -- | -- | 7.23 (0% fail) |

### warm, low

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 1.93 (0% fail) | 0.867 (7% fail) | 11.31 (11% fail) | 6.88 (11% fail) | 6.79 (11% fail) | 0.792 (2% fail) | 0.535 (0% fail) | 0.114 (0% fail) |
| fleet_grid_box | 2.67 (0% fail) | 1.35 (3% fail) | 5.67 (0% fail) | -- | -- | 57.57 (24% fail) | 2.10 (3% fail) | 1.01 (0% fail) |
| fleet_grid_box_b4 | 7.97 (0% fail) | -- | 10.30 (0% fail) | 7.89 (0% fail) | 7.44 (0% fail) | 18.17 (14% fail) | 4.98 (0% fail) | 1.99 (0% fail) |
| fleet_grid_soc | 14.99 (0% fail) | -- | 15.66 (0% fail) | -- | -- | -- | -- | 7.19 (0% fail) |
| fleet_grid_soc_b4 | 16.11 (0% fail) | -- | 11.36 (0% fail) | -- | -- | -- | -- | 5.08 (0% fail) |
| fleet_ring_box | 2.37 (0% fail) | 1.22 (3% fail) | 5.11 (0% fail) | -- | -- | 17.19 (21% fail) | 1.54 (3% fail) | 0.865 (0% fail) |
| fleet_ring_box_b4 | 5.04 (0% fail) | -- | 8.57 (0% fail) | 6.15 (0% fail) | 5.72 (0% fail) | 7.66 (7% fail) | 3.56 (2% fail) | 1.67 (0% fail) |
| fleet_ring_soc | 8.73 (0% fail) | -- | 10.94 (0% fail) | 10.34 (0% fail) | 9.18 (0% fail) | -- | -- | 4.67 (0% fail) |
| fleet_ring_soc_b4 | 9.02 (0% fail) | -- | 8.55 (0% fail) | 7.82 (0% fail) | 7.55 (0% fail) | -- | -- | 3.31 (0% fail) |
| osqprand | 4.57 (0% fail) | 0.709 (3% fail) | 10.18 (5% fail) | -- | -- | 1.33 (0% fail) | 2.71 (0% fail) | 0.437 (0% fail) |
| reduced | 21.89 (0% fail) | -- | 16.89 (0% fail) | 15.95 (0% fail) | 14.62 (0% fail) | -- | -- | 1.14 (0% fail) |
| single_di_box | 0.898 (0% fail) | 0.225 (0% fail) | 2.02 (0% fail) | 1.57 (0% fail) | 1.19 (0% fail) | 0.319 (0% fail) | 0.354 (0% fail) | 0.101 (0% fail) |
| single_di_soc | 0.956 (0% fail) | -- | 1.20 (0% fail) | 1.05 (0% fail) | 0.960 (0% fail) | -- | -- | 0.335 (0% fail) |
| single_quad | 1.94 (0% fail) | 0.260 (0% fail) | 2.89 (0% fail) | 2.19 (0% fail) | 1.99 (0% fail) | 0.713 (0% fail) | 0.743 (0% fail) | 0.147 (0% fail) |
| all | 4.62 (0% fail) | -- | 7.31 (2% fail) | -- | -- | -- | -- | 0.957 (0% fail) |

### warm, medium

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 2.59 (0% fail) | 0.975 (7% fail) | 24.87 (11% fail) | 9.35 (11% fail) | 9.13 (11% fail) | 1.16 (0% fail) | 0.679 (0% fail) | 0.130 (0% fail) |
| fleet_grid_box | 3.52 (0% fail) | 1.10 (0% fail) | 7.44 (0% fail) | -- | -- | 17.32 (15% fail) | 1.65 (0% fail) | 1.02 (0% fail) |
| fleet_grid_box_b4 | 10.12 (0% fail) | -- | 13.24 (0% fail) | 10.24 (0% fail) | 9.53 (0% fail) | 21.13 (7% fail) | 6.06 (0% fail) | 1.99 (0% fail) |
| fleet_grid_soc | 21.83 (0% fail) | -- | 21.62 (0% fail) | -- | -- | -- | -- | 8.77 (0% fail) |
| fleet_grid_soc_b4 | 22.66 (0% fail) | -- | 15.60 (0% fail) | -- | -- | -- | -- | 6.35 (0% fail) |
| fleet_ring_box | 3.07 (0% fail) | 0.992 (0% fail) | 6.52 (0% fail) | -- | -- | 22.96 (18% fail) | 1.26 (0% fail) | 0.891 (0% fail) |
| fleet_ring_box_b4 | 6.30 (0% fail) | -- | 11.02 (0% fail) | 7.84 (0% fail) | 7.28 (0% fail) | 32.87 (16% fail) | 3.12 (0% fail) | 1.76 (0% fail) |
| fleet_ring_soc | 12.61 (0% fail) | -- | 15.04 (0% fail) | 13.79 (0% fail) | 12.15 (0% fail) | -- | -- | 5.45 (0% fail) |
| fleet_ring_soc_b4 | 12.18 (0% fail) | -- | 11.45 (0% fail) | 10.29 (0% fail) | 9.94 (0% fail) | -- | -- | 3.86 (0% fail) |
| osqprand | 5.87 (0% fail) | 0.937 (4% fail) | 24.20 (10% fail) | -- | -- | 13.05 (12% fail) | 3.33 (0% fail) | 0.453 (0% fail) |
| reduced | 27.82 (0% fail) | -- | 22.63 (0% fail) | 21.33 (0% fail) | 19.53 (0% fail) | -- | -- | 1.14 (0% fail) |
| single_di_box | 1.30 (0% fail) | 0.313 (0% fail) | 3.22 (0% fail) | 2.51 (0% fail) | 1.86 (0% fail) | 0.589 (0% fail) | 0.431 (0% fail) | 0.106 (0% fail) |
| single_di_soc | 1.41 (0% fail) | -- | 1.85 (0% fail) | 1.64 (0% fail) | 1.44 (0% fail) | -- | -- | 0.477 (0% fail) |
| single_quad | 2.56 (0% fail) | 0.289 (0% fail) | 4.30 (0% fail) | 3.13 (0% fail) | 2.95 (0% fail) | 1.34 (0% fail) | 0.935 (0% fail) | 0.148 (0% fail) |
| all | 6.19 (0% fail) | -- | 11.38 (2% fail) | -- | -- | -- | -- | 1.05 (0% fail) |

### warm, e8

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_grid_soc | 25.85 (0% fail) | -- | 25.49 (0% fail) | -- | -- | -- | -- | 9.35 (0% fail) |
| fleet_grid_soc_b4 | 26.49 (0% fail) | -- | 18.14 (0% fail) | -- | -- | -- | -- | 6.69 (0% fail) |
| fleet_ring_soc | 15.06 (0% fail) | -- | 17.85 (0% fail) | 16.10 (0% fail) | 14.55 (0% fail) | -- | -- | 5.81 (0% fail) |
| fleet_ring_soc_b4 | 14.62 (0% fail) | -- | 13.53 (0% fail) | 12.09 (0% fail) | 11.67 (0% fail) | -- | -- | 4.09 (0% fail) |
| reduced | 32.50 (0% fail) | -- | 27.33 (0% fail) | 26.02 (0% fail) | 24.12 (0% fail) | -- | -- | 1.13 (0% fail) |
| single_di_soc | 1.67 (0% fail) | -- | 2.44 (0% fail) | 1.95 (0% fail) | 1.70 (0% fail) | -- | -- | 0.534 (0% fail) |
| all | 14.29 (0% fail) | -- | 14.03 (0% fail) | -- | -- | -- | -- | 3.18 (0% fail) |

### warm, high

| family | clarabel | hpipm | mumblebee | mumblebee_fast | mumblebee_fast_ct | osqp | piqp | sheafmpc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| chain | 3.04 (0% fail) | 1.11 (7% fail) | 191 (24% fail) | 52.61 (24% fail) | 51.44 (24% fail) | 1.34 (0% fail) | 0.781 (0% fail) | 0.161 (0% fail) |
| fleet_grid_box | 4.12 (0% fail) | 1.96 (3% fail) | 8.59 (0% fail) | -- | -- | 23.36 (12% fail) | 1.89 (0% fail) | 1.03 (0% fail) |
| fleet_grid_box_b4 | 11.66 (0% fail) | -- | 15.27 (0% fail) | 11.82 (0% fail) | 10.96 (0% fail) | 27.21 (5% fail) | 7.11 (0% fail) | 2.01 (0% fail) |
| fleet_grid_soc | 41.39 (5% fail) | -- | 27.25 (0% fail) | -- | -- | -- | -- | 10.68 (0% fail) |
| fleet_grid_soc_b4 | 34.05 (2% fail) | -- | 19.48 (0% fail) | -- | -- | -- | -- | 7.16 (0% fail) |
| fleet_ring_box | 3.57 (0% fail) | 1.58 (3% fail) | 7.58 (0% fail) | -- | -- | 21.49 (12% fail) | 1.45 (0% fail) | 0.911 (0% fail) |
| fleet_ring_box_b4 | 7.20 (0% fail) | -- | 12.58 (0% fail) | 9.02 (0% fail) | 8.31 (0% fail) | 14.58 (2% fail) | 3.53 (0% fail) | 1.76 (0% fail) |
| fleet_ring_soc | 20.72 (2% fail) | -- | 19.36 (0% fail) | 17.73 (0% fail) | 15.32 (0% fail) | -- | -- | 5.99 (0% fail) |
| fleet_ring_soc_b4 | 25.22 (5% fail) | -- | 14.26 (0% fail) | 12.92 (0% fail) | 12.58 (0% fail) | -- | -- | 4.22 (0% fail) |
| osqprand | 6.65 (0% fail) | 2.12 (9% fail) | 61.34 (10% fail) | -- | -- | 6.13 (3% fail) | 3.95 (0% fail) | 0.501 (0% fail) |
| reduced | 35.16 (0% fail) | -- | 32.34 (0% fail) | 30.41 (0% fail) | 28.38 (0% fail) | -- | -- | 1.14 (0% fail) |
| single_di_box | 1.58 (0% fail) | 0.344 (0% fail) | 5.50 (0% fail) | 3.08 (0% fail) | 2.32 (0% fail) | 0.641 (0% fail) | 0.535 (0% fail) | 0.121 (0% fail) |
| single_di_soc | 1.77 (0% fail) | -- | 3.49 (0% fail) | 2.14 (0% fail) | 1.87 (0% fail) | -- | -- | 0.590 (0% fail) |
| single_quad | 2.93 (0% fail) | 0.336 (0% fail) | 5.98 (0% fail) | 3.73 (0% fail) | 3.54 (0% fail) | 1.48 (0% fail) | 1.05 (0% fail) | 0.187 (0% fail) |
| all | 8.11 (1% fail) | -- | 19.27 (3% fail) | -- | -- | -- | -- | 1.15 (0% fail) |

## Where sheafmpc loses (median time over the best other solver, ratio > 1, or misses the tier)

| instance | mode | tier | sheafmpc ms | best other | its ms | ratio |
|---|---|---|---:|---|---:|---:|
| osqprand_nx40_s1 | setup | high | 27.29 | hpipm | 0.232 | 117.76 |
| osqprand_nx40_s1 | setup | low | 27.01 | hpipm | 0.318 | 84.87 |
| osqprand_nx40_s1 | setup | medium | 26.99 | hpipm | 0.326 | 82.86 |
| osqprand_nx40_s3 | setup | medium | 26.78 | hpipm | 0.330 | 81.25 |
| osqprand_nx40_s3 | setup | high | 26.71 | hpipm | 0.350 | 76.28 |
| osqprand_nx40_s3 | setup | low | 26.46 | hpipm | 0.385 | 68.81 |
| osqprand_nx40_s2 | setup | low | 25.59 | hpipm | 0.391 | 65.47 |
| chain_M10 | setup | low | 9.30 | hpipm | 0.143 | 65.02 |
| chain_M10 | setup | high | 9.03 | hpipm | 0.148 | 61.22 |
| chain_M8 | setup | medium | 5.91 | hpipm | 0.117 | 50.63 |
| osqprand_nx20_s3 | setup | medium | 6.82 | hpipm | 0.140 | 48.75 |
| chain_M8 | setup | low | 5.96 | hpipm | 0.122 | 48.69 |
| chain_M10 | setup | medium | 9.17 | hpipm | 0.197 | 46.55 |
| osqprand_nx20_s2 | setup | medium | 6.82 | hpipm | 0.169 | 40.39 |
| chain_M6 | setup | low | 3.46 | hpipm | 0.104 | 33.20 |
| osqprand_nx20_s2 | setup | high | 6.91 | hpipm | 0.234 | 29.52 |
| osqprand_nx20_s2 | setup | low | 6.69 | hpipm | 0.232 | 28.87 |
| osqprand_nx20_s3 | setup | low | 6.67 | hpipm | 0.234 | 28.43 |
| chain_M6 | setup | medium | 3.37 | hpipm | 0.134 | 25.22 |
| chain_M6 | setup | high | 3.29 | hpipm | 0.135 | 24.31 |
| osqprand_nx20_s1 | setup | low | 6.73 | hpipm | 0.288 | 23.34 |
| quad_N50 | setup | low | 4.97 | hpipm | 0.214 | 23.18 |
| osqprand_nx40_s2 | cold_total | low | 41.29 | hpipm | 1.84 | 22.46 |
| osqprand_nx10_s3 | setup | medium | 2.30 | hpipm | 0.107 | 21.47 |
| osqprand_nx20_s1 | setup | medium | 6.70 | hpipm | 0.314 | 21.34 |
| quad_N25 | setup | low | 2.81 | hpipm | 0.132 | 21.25 |
| osqprand_nx10_s2 | setup | medium | 2.48 | hpipm | 0.129 | 19.18 |
| quad_N50 | setup | high | 4.90 | hpipm | 0.260 | 18.85 |
| quad_N50 | setup | medium | 4.92 | hpipm | 0.265 | 18.58 |
| osqprand_nx40_s3 | cold_total | low | 30.31 | hpipm | 1.67 | 18.18 |
| quad_N100 | setup | low | 7.76 | hpipm | 0.446 | 17.40 |
| osqprand_nx40_s1 | cold_total | low | 31.47 | hpipm | 1.82 | 17.34 |
| fleet_grid_box_n16 | setup | medium | 16.08 | hpipm | 0.928 | 17.33 |
| chain_M4 | setup | medium | 2.00 | hpipm | 0.116 | 17.23 |
| chain_M10 | cold_total | low | 11.23 | hpipm | 0.666 | 16.85 |
| chain_M4 | setup | high | 1.93 | hpipm | 0.116 | 16.69 |
| quad_N25 | setup | medium | 2.77 | hpipm | 0.169 | 16.40 |
| osqprand_nx40_s3 | cold_total | medium | 30.53 | hpipm | 1.87 | 16.31 |
| chain_M4 | setup | low | 2.00 | hpipm | 0.124 | 16.20 |
| quad_N100 | setup | high | 7.72 | hpipm | 0.480 | 16.10 |
| quad_N25 | setup | high | 2.74 | hpipm | 0.171 | 16.01 |
| osqprand_nx40_s3 | cold_total | high | 30.85 | hpipm | 2.03 | 15.23 |
| fleet_grid_box_b4_n64 | setup | medium | 89.49 | piqp | 5.99 | 14.95 |
| fleet_grid_box_n4 | setup | medium | 2.59 | hpipm | 0.175 | 14.84 |
| fleet_grid_box_n4 | setup | high | 2.55 | hpipm | 0.180 | 14.19 |
| osqprand_nx40_s1 | cold_total | medium | 31.11 | hpipm | 2.20 | 14.13 |
| fleet_ring_box_n4 | setup | low | 2.41 | hpipm | 0.172 | 14.00 |
| fleet_ring_box_n4 | setup | medium | 2.40 | hpipm | 0.172 | 13.98 |
| fleet_ring_box_n4 | setup | high | 2.39 | hpipm | 0.171 | 13.97 |
| chain_M8 | cold_total | low | 7.06 | hpipm | 0.508 | 13.91 |
| fleet_grid_box_b4_n64 | setup | high | 89.36 | piqp | 6.46 | 13.84 |
| fleet_grid_box_b4_n64 | setup | low | 88.82 | piqp | 6.52 | 13.62 |
| osqprand_nx40_s1 | cold_total | high | 31.37 | hpipm | 2.37 | 13.22 |
| chain_M10 | cold_total | medium | 11.30 | hpipm | 0.889 | 12.70 |
| osqprand_nx20_s2 | cold_total | low | 7.16 | hpipm | 0.575 | 12.44 |
| quad_N100 | setup | medium | 7.77 | hpipm | 0.643 | 12.08 |
| chain_M3 | setup | low | 1.20 | hpipm | 0.102 | 11.73 |
| chain_M3 | setup | medium | 1.16 | hpipm | 0.100 | 11.62 |
| osqprand_nx20_s3 | cold_total | medium | 7.39 | hpipm | 0.652 | 11.33 |
| chain_M8 | cold_total | medium | 7.41 | hpipm | 0.669 | 11.07 |
| chain_M6 | cold_total | low | 4.30 | hpipm | 0.391 | 10.99 |
| chain_M10 | cold_total | high | 11.18 | hpipm | 1.03 | 10.82 |
| osqprand_nx40_s2 | cold | low | 15.56 | hpipm | 1.45 | 10.75 |
| osqprand_nx20_s2 | cold_total | medium | 7.40 | hpipm | 0.689 | 10.74 |
| quad_N10 | setup | low | 1.33 | hpipm | 0.125 | 10.70 |
| chain_M3 | setup | high | 1.13 | hpipm | 0.106 | 10.60 |
| fleet_grid_box_b4_n16 | setup | high | 10.63 | piqp | 1.01 | 10.49 |
| osqprand_nx10_s2 | cold_total | medium | 2.61 | hpipm | 0.251 | 10.43 |
| di_box_N50 | setup | medium | 2.94 | hpipm | 0.291 | 10.09 |
| quad_N10 | setup | high | 1.30 | hpipm | 0.129 | 10.08 |
| osqprand_nx10_s2 | setup | low | 2.42 | hpipm | 0.242 | 10.01 |
| osqprand_nx10_s2 | setup | high | 2.35 | hpipm | 0.244 | 9.65 |
| fleet_ring_box_b4_n4 | setup | high | 2.43 | piqp | 0.252 | 9.63 |
| fleet_grid_box_n16 | setup | high | 15.88 | hpipm | 1.66 | 9.59 |
| chain_M6 | cold_total | medium | 4.36 | hpipm | 0.456 | 9.57 |
| quad_N10 | setup | medium | 1.31 | hpipm | 0.137 | 9.56 |
| osqprand_nx20_s1 | cold_total | low | 7.29 | hpipm | 0.763 | 9.56 |
| di_box_N50 | setup | low | 2.89 | hpipm | 0.304 | 9.53 |
| fleet_grid_box_b4_n4 | setup | high | 2.41 | piqp | 0.254 | 9.50 |
| fleet_grid_box_n16 | setup | low | 15.99 | hpipm | 1.71 | 9.34 |
| fleet_grid_box_b4_n16 | setup | low | 10.71 | piqp | 1.15 | 9.29 |
| osqprand_nx10_s3 | cold_total | medium | 2.70 | hpipm | 0.291 | 9.28 |
| osqprand_nx20_s3 | cold_total | low | 7.06 | hpipm | 0.778 | 9.08 |
| osqprand_nx40_s2 | setup | medium | 27.23 | piqp | 3.14 | 8.67 |
| osqprand_nx20_s2 | cold_total | high | 7.33 | hpipm | 0.851 | 8.62 |
| osqprand_nx20_s1 | cold_total | medium | 7.51 | hpipm | 0.876 | 8.58 |
| quad_N50 | cold_total | low | 5.24 | hpipm | 0.623 | 8.41 |
| chain_M6 | cold_total | high | 4.22 | hpipm | 0.526 | 8.04 |
| fleet_grid_box_b4_n16 | setup | medium | 10.67 | piqp | 1.34 | 7.95 |
| fleet_grid_soc_n64 | setup | medium | 209 | clarabel | 26.52 | 7.86 |
| fleet_grid_soc_n64 | setup | e8 | 208 | clarabel | 26.57 | 7.84 |
| fleet_grid_soc_n64 | setup | low | 209 | clarabel | 26.76 | 7.83 |
| fleet_grid_soc_n64 | setup | high | 208 | clarabel | 26.85 | 7.76 |
| quad_N25 | cold_total | low | 2.94 | hpipm | 0.384 | 7.67 |
| di_box_N50 | setup | high | 2.87 | hpipm | 0.376 | 7.63 |
| di_box_N25 | setup | low | 1.48 | hpipm | 0.197 | 7.53 |
| chain_M4 | cold_total | low | 2.05 | hpipm | 0.274 | 7.51 |
| osqprand_nx40_s2 | setup | high | 27.37 | piqp | 3.65 | 7.50 |
| di_box_N25 | setup | high | 1.46 | hpipm | 0.197 | 7.40 |
| osqprand_nx10_s1 | setup | high | 2.37 | piqp | 0.321 | 7.39 |
| fleet_ring_box_b4_n1 | setup | medium | 0.361 | piqp | 0.049 | 7.37 |
| fleet_grid_box_b4_n1 | setup | medium | 0.377 | piqp | 0.051 | 7.33 |
| quad_N100 | cold_total | low | 10.29 | hpipm | 1.41 | 7.32 |
| fleet_ring_box_b4_n1 | setup | high | 0.354 | piqp | 0.049 | 7.28 |
| osqprand_nx10_s2 | cold_total | low | 2.49 | hpipm | 0.351 | 7.09 |
| fleet_grid_box_b4_n4 | setup | low | 2.44 | piqp | 0.344 | 7.09 |
| fleet_grid_box_b4_n4 | setup | medium | 2.38 | piqp | 0.338 | 7.02 |
| fleet_ring_box_b4_n4 | setup | medium | 2.29 | piqp | 0.327 | 7.01 |
| chain_M4 | cold_total | medium | 2.07 | hpipm | 0.300 | 6.91 |
| fleet_ring_box_b4_n64 | setup | high | 30.20 | piqp | 4.45 | 6.78 |
| fleet_ring_box_b4_n64 | setup | medium | 30.05 | piqp | 4.43 | 6.78 |
| fleet_ring_box_n16 | setup | low | 9.06 | piqp | 1.35 | 6.73 |
| fleet_ring_box_b4_n64 | setup | low | 30.13 | piqp | 4.48 | 6.73 |
| fleet_grid_box_n4 | setup | low | 2.64 | piqp | 0.393 | 6.73 |
| fleet_ring_box_n16 | setup | medium | 8.98 | piqp | 1.34 | 6.72 |
| fleet_ring_box_b4_n16 | setup | low | 7.24 | piqp | 1.09 | 6.67 |
| fleet_ring_box_b4_n16 | setup | medium | 7.36 | piqp | 1.11 | 6.63 |
| quad_N50 | cold_total | medium | 5.25 | hpipm | 0.795 | 6.60 |
| osqprand_nx10_s3 | setup | high | 2.34 | piqp | 0.360 | 6.49 |
| fleet_grid_box_b4_n1 | setup | high | 0.367 | piqp | 0.057 | 6.43 |
| fleet_grid_soc_b4_n64 | setup | high | 159 | clarabel | 24.85 | 6.38 |
| osqprand_nx10_s2 | cold_total | high | 2.46 | hpipm | 0.387 | 6.35 |
| di_box_N100 | setup | high | 2.73 | hpipm | 0.431 | 6.34 |
| fleet_ring_box_b4_n1 | setup | low | 0.358 | piqp | 0.057 | 6.33 |
| fleet_grid_box_b4_n1 | setup | low | 0.390 | piqp | 0.062 | 6.29 |
| fleet_ring_box_n16 | setup | high | 9.01 | piqp | 1.44 | 6.25 |
| fleet_ring_box_b4_n16 | setup | high | 7.26 | piqp | 1.16 | 6.25 |
| osqprand_nx20_s3 | setup | high | 6.84 | piqp | 1.10 | 6.22 |
| osqprand_nx10_s1 | setup | low | 2.46 | piqp | 0.396 | 6.21 |
| quad_N50 | cold_total | high | 5.26 | hpipm | 0.851 | 6.19 |
| quad_N25 | cold_total | medium | 2.90 | hpipm | 0.469 | 6.18 |
| osqprand_nx10_s3 | setup | low | 2.47 | piqp | 0.404 | 6.12 |
| chain_M4 | cold_total | high | 2.03 | hpipm | 0.340 | 5.96 |
| chain_M3 | cold_total | low | 1.24 | hpipm | 0.211 | 5.88 |
| quad_N25 | cold_total | high | 2.91 | hpipm | 0.498 | 5.84 |
| osqprand_nx20_s1 | setup | high | 6.63 | piqp | 1.14 | 5.81 |
| fleet_grid_soc_b4_n64 | setup | low | 145 | clarabel | 24.93 | 5.80 |
| quad_N10 | cold_total | low | 1.37 | hpipm | 0.238 | 5.75 |
| di_box_N25 | setup | medium | 1.42 | hpipm | 0.249 | 5.68 |
| osqprand_nx10_s1 | setup | medium | 2.42 | osqp | 0.428 | 5.66 |
| fleet_grid_soc_b4_n64 | setup | e8 | 149 | clarabel | 26.50 | 5.63 |
| fleet_grid_soc_b4_n64 | setup | medium | 144 | clarabel | 25.60 | 5.62 |
| di_box_N50 | cold_total | low | 3.17 | hpipm | 0.569 | 5.57 |
| di_box_N100 | setup | medium | 2.69 | hpipm | 0.488 | 5.51 |
| di_box_N100 | setup | low | 2.66 | hpipm | 0.488 | 5.44 |
| fleet_ring_box_n1 | setup | medium | 0.512 | hpipm | 0.096 | 5.32 |
| fleet_ring_box_n1 | setup | high | 0.508 | hpipm | 0.096 | 5.29 |
| fleet_ring_box_n1 | setup | low | 0.508 | hpipm | 0.096 | 5.27 |
| quad_N10 | cold_total | high | 1.35 | hpipm | 0.256 | 5.27 |
| fleet_grid_box_n1 | setup | medium | 0.595 | hpipm | 0.113 | 5.26 |
| quad_N100 | cold_total | high | 10.32 | hpipm | 1.99 | 5.19 |
| quad_N100 | cold_total | medium | 10.36 | hpipm | 2.01 | 5.16 |
| chain_M3 | cold_total | medium | 1.21 | hpipm | 0.236 | 5.12 |
| quad_N10 | cold_total | medium | 1.34 | hpipm | 0.267 | 5.02 |
| fleet_ring_box_b4_n4 | setup | low | 2.31 | osqp | 0.463 | 4.99 |
| chain_M8 | setup | high | 5.92 | osqp | 1.19 | 4.96 |
| fleet_ring_box_n4 | cold_total | low | 3.47 | hpipm | 0.707 | 4.91 |
| fleet_grid_box_n1 | setup | low | 0.559 | hpipm | 0.115 | 4.87 |
| fleet_grid_box_n4 | cold_total | medium | 3.73 | hpipm | 0.813 | 4.59 |
| fleet_grid_soc_n16 | setup | low | 26.32 | clarabel | 5.84 | 4.50 |
| di_box_N50 | cold_total | medium | 3.20 | hpipm | 0.711 | 4.50 |
| chain_M3 | cold_total | high | 1.18 | hpipm | 0.262 | 4.49 |
| fleet_grid_soc_n16 | setup | e8 | 26.26 | clarabel | 5.86 | 4.48 |
| reduced_k0 | setup | medium | 53.61 | clarabel | 12.09 | 4.43 |
| fleet_grid_soc_n16 | setup | medium | 26.26 | clarabel | 5.94 | 4.42 |
| fleet_ring_box_n4 | cold_total | medium | 3.54 | hpipm | 0.800 | 4.42 |
| reduced_k0 | setup | low | 53.03 | clarabel | 12.07 | 4.40 |
| reduced_k0 | setup | high | 53.49 | clarabel | 12.17 | 4.39 |
| reduced_k0 | setup | e8 | 53.29 | clarabel | 12.28 | 4.34 |
| di_box_N10 | setup | medium | 0.501 | osqp | 0.116 | 4.33 |
| di_box_N10 | setup | low | 0.492 | osqp | 0.114 | 4.32 |
| fleet_grid_box_n1 | setup | high | 0.521 | piqp | 0.122 | 4.27 |
| di_box_N25 | cold_total | low | 1.56 | hpipm | 0.367 | 4.25 |
| fleet_grid_soc_n16 | setup | high | 26.26 | clarabel | 6.29 | 4.18 |
| fleet_ring_box_n4 | cold_total | high | 3.53 | hpipm | 0.860 | 4.10 |
| chain_M10 | cold | low | 2.13 | hpipm | 0.524 | 4.07 |
| fleet_grid_soc_b4_n16 | setup | low | 17.01 | clarabel | 4.22 | 4.03 |
| di_box_N10 | setup | high | 0.465 | osqp | 0.118 | 3.93 |
| fleet_grid_soc_b4_n16 | setup | medium | 16.57 | clarabel | 4.42 | 3.75 |
| fleet_ring_soc_n64 | setup | high | 74.42 | clarabel | 19.85 | 3.75 |
| fleet_grid_soc_b4_n16 | setup | e8 | 16.72 | clarabel | 4.48 | 3.74 |
| di_box_N100 | cold_total | low | 3.86 | hpipm | 1.04 | 3.71 |
| fleet_ring_soc_n64 | setup | medium | 74.43 | clarabel | 20.06 | 3.71 |
| fleet_ring_soc_n64 | setup | e8 | 74.21 | mumblebee_fast | 20.39 | 3.64 |
| fleet_grid_box_n4 | cold_total | high | 3.76 | hpipm | 1.04 | 3.60 |
| fleet_grid_soc_b4_n16 | setup | high | 16.47 | clarabel | 4.59 | 3.59 |
| fleet_ring_soc_n64 | setup | low | 74.26 | mumblebee_fast | 20.70 | 3.59 |
| di_box_N25 | cold_total | high | 1.61 | hpipm | 0.456 | 3.54 |
| fleet_ring_box_n1 | cold_total | low | 0.570 | hpipm | 0.162 | 3.52 |
| di_box_N50 | cold_total | high | 3.14 | hpipm | 0.895 | 3.51 |
| fleet_grid_box_n4 | cold_total | low | 3.79 | piqp | 1.09 | 3.47 |
| fleet_ring_soc_b4_n64 | setup | low | 50.68 | clarabel | 14.67 | 3.45 |
| fleet_ring_soc_b4_n64 | setup | medium | 50.99 | clarabel | 14.78 | 3.45 |
| fleet_ring_soc_b4_n64 | setup | e8 | 50.69 | clarabel | 14.79 | 3.43 |
| fleet_ring_soc_b4_n64 | setup | high | 50.76 | clarabel | 14.81 | 3.43 |
| chain_M8 | cold | low | 1.33 | hpipm | 0.388 | 3.41 |
| fleet_ring_soc_n16 | setup | e8 | 17.08 | clarabel | 5.02 | 3.40 |
| fleet_ring_soc_n16 | setup | medium | 17.20 | clarabel | 5.09 | 3.38 |
| fleet_ring_soc_n16 | setup | low | 17.02 | clarabel | 5.04 | 3.38 |
| fleet_ring_box_b4_n1 | cold_total | low | 0.405 | piqp | 0.122 | 3.33 |
| fleet_grid_box_b4_n1 | cold_total | low | 0.419 | piqp | 0.126 | 3.33 |
| fleet_grid_soc_n4 | setup | low | 3.97 | clarabel | 1.20 | 3.30 |
| fleet_ring_soc_n4 | setup | low | 4.07 | clarabel | 1.24 | 3.28 |
| fleet_ring_soc_b4_n16 | setup | e8 | 12.65 | clarabel | 3.88 | 3.26 |
| fleet_ring_soc_b4_n16 | setup | medium | 12.40 | clarabel | 3.81 | 3.25 |
| fleet_ring_soc_n16 | setup | high | 17.16 | clarabel | 5.29 | 3.25 |
| fleet_ring_soc_b4_n16 | setup | low | 12.45 | clarabel | 3.85 | 3.23 |
| fleet_grid_box_b4_n4 | cold_total | low | 3.01 | piqp | 0.938 | 3.21 |
| di_box_N25 | cold_total | medium | 1.55 | hpipm | 0.486 | 3.20 |
| fleet_ring_soc_b4_n16 | setup | high | 12.42 | clarabel | 3.88 | 3.20 |
| fleet_grid_box_b4_n1 | cold_total | medium | 0.409 | piqp | 0.128 | 3.19 |
| fleet_grid_soc_n4 | setup | high | 3.97 | clarabel | 1.25 | 3.19 |
| chain_M10 | cold | medium | 2.20 | hpipm | 0.693 | 3.17 |
| fleet_ring_soc_n4 | setup | e8 | 4.00 | clarabel | 1.26 | 3.17 |
| fleet_ring_box_n1 | cold_total | medium | 0.553 | hpipm | 0.175 | 3.16 |
| fleet_grid_soc_n4 | setup | medium | 3.90 | clarabel | 1.24 | 3.15 |
| fleet_ring_box_b4_n1 | cold_total | medium | 0.398 | piqp | 0.126 | 3.15 |
| fleet_grid_box_n1 | cold_total | low | 0.598 | hpipm | 0.190 | 3.14 |
| fleet_grid_soc_n4 | setup | e8 | 3.95 | clarabel | 1.26 | 3.14 |
| fleet_ring_box_n1 | cold_total | high | 0.560 | hpipm | 0.179 | 3.13 |
| fleet_grid_box_n1 | cold_total | medium | 0.623 | hpipm | 0.202 | 3.08 |
| fleet_ring_soc_n4 | setup | high | 3.92 | clarabel | 1.28 | 3.05 |
| fleet_ring_soc_n4 | setup | medium | 3.90 | clarabel | 1.28 | 3.05 |
| osqprand_nx40_s3 | cold | low | 3.81 | hpipm | 1.26 | 3.03 |
| chain_M6 | cold | low | 0.864 | hpipm | 0.285 | 3.02 |
| chain_M6 | cold | medium | 0.974 | hpipm | 0.324 | 3.01 |
| fleet_ring_soc_b4_n4 | setup | low | 2.69 | clarabel | 0.919 | 2.93 |
| fleet_grid_soc_b4_n4 | setup | high | 2.52 | clarabel | 0.870 | 2.89 |
| fleet_ring_soc_b4_n4 | setup | medium | 2.61 | clarabel | 0.913 | 2.87 |
| chain_M8 | cold_total | high | 7.44 | piqp | 2.60 | 2.86 |
| di_box_N100 | cold_total | medium | 3.93 | hpipm | 1.37 | 2.86 |
| osqprand_nx40_s2 | warm | low | 2.97 | hpipm | 1.05 | 2.83 |
| osqprand_nx10_s3 | cold_total | low | 2.75 | piqp | 0.971 | 2.83 |
| fleet_ring_box_b4_n1 | cold_total | high | 0.400 | piqp | 0.141 | 2.83 |
| osqprand_nx40_s1 | cold | low | 4.05 | hpipm | 1.43 | 2.82 |
| di_box_N100 | cold_total | high | 4.05 | hpipm | 1.44 | 2.81 |
| fleet_grid_soc_b4_n4 | setup | low | 2.50 | clarabel | 0.890 | 2.80 |
| fleet_ring_soc_b4_n4 | setup | high | 2.59 | clarabel | 0.935 | 2.77 |
| fleet_grid_soc_b4_n4 | setup | e8 | 2.54 | clarabel | 0.918 | 2.77 |
| fleet_grid_soc_b4_n4 | setup | medium | 2.53 | clarabel | 0.915 | 2.76 |
| fleet_ring_box_b4_n4 | cold_total | high | 3.05 | piqp | 1.12 | 2.73 |
| osqprand_nx10_s1 | cold_total | low | 2.52 | piqp | 0.926 | 2.72 |
| fleet_ring_box_b4_n4 | cold_total | medium | 2.89 | piqp | 1.09 | 2.66 |
| di_box_N10 | cold_total | low | 0.520 | osqp | 0.196 | 2.65 |
| quad_N100 | cold | low | 2.57 | hpipm | 0.976 | 2.63 |
| chain_M8 | cold | medium | 1.45 | hpipm | 0.553 | 2.62 |
| osqprand_nx20_s2 | warm | low | 0.932 | hpipm | 0.364 | 2.56 |
| fleet_ring_soc_b4_n4 | setup | e8 | 2.64 | clarabel | 1.04 | 2.54 |
| fleet_grid_box_b4_n1 | cold_total | high | 0.400 | piqp | 0.161 | 2.48 |
| fleet_grid_box_b4_n4 | cold_total | high | 3.05 | piqp | 1.23 | 2.48 |
| chain_M10 | cold | high | 2.19 | hpipm | 0.886 | 2.47 |
| osqprand_nx40_s3 | cold | medium | 3.79 | hpipm | 1.54 | 2.45 |
| reduced_k8 | setup | medium | 26.54 | clarabel | 10.89 | 2.44 |
| fleet_grid_box_b4_n4 | cold_total | medium | 2.96 | piqp | 1.22 | 2.43 |
| chain_M6 | cold | high | 0.945 | hpipm | 0.391 | 2.42 |
| reduced_k8 | setup | e8 | 26.51 | clarabel | 10.97 | 2.42 |
| reduced_k8 | setup | high | 26.29 | clarabel | 10.91 | 2.41 |
| reduced_k8 | setup | low | 26.30 | clarabel | 10.98 | 2.40 |
| reduced_k4 | setup | low | 22.73 | clarabel | 9.82 | 2.32 |
| osqprand_nx10_s1 | cold_total | medium | 2.52 | piqp | 1.09 | 2.31 |
| reduced_k2 | setup | high | 21.45 | clarabel | 9.48 | 2.26 |
| reduced_k2 | setup | low | 21.56 | clarabel | 9.55 | 2.26 |
| reduced_k2 | setup | e8 | 21.39 | clarabel | 9.50 | 2.25 |
| fleet_grid_box_n16 | cold_total | low | 25.34 | hpipm | 11.34 | 2.23 |
| di_soc_N25 | setup | e8 | 1.29 | clarabel | 0.579 | 2.23 |
| osqprand_nx40_s3 | cold | high | 3.78 | hpipm | 1.70 | 2.23 |
| reduced_k2 | setup | medium | 21.36 | clarabel | 9.69 | 2.20 |
| reduced_k4 | setup | medium | 21.86 | clarabel | 9.95 | 2.20 |
| osqprand_nx10_s1 | cold_total | high | 2.51 | piqp | 1.14 | 2.20 |
| osqprand_nx40_s1 | cold | medium | 4.08 | hpipm | 1.86 | 2.19 |
| reduced_k4 | setup | high | 21.91 | clarabel | 10.15 | 2.16 |
| di_box_N10 | cold_total | medium | 0.535 | piqp | 0.249 | 2.15 |
| di_soc_N10 | setup | medium | 0.526 | clarabel | 0.245 | 2.15 |
| di_box_N100 | cold | low | 1.18 | hpipm | 0.551 | 2.14 |
| osqprand_nx10_s3 | cold_total | high | 2.71 | piqp | 1.27 | 2.13 |
| di_soc_N25 | setup | high | 1.26 | clarabel | 0.593 | 2.13 |
| reduced_k4 | setup | e8 | 21.69 | clarabel | 10.19 | 2.13 |
| di_soc_N50 | setup | low | 1.97 | clarabel | 0.927 | 2.12 |
| di_soc_N25 | setup | medium | 1.26 | clarabel | 0.599 | 2.11 |
| osqprand_nx40_s2 | cold_total | medium | 43.19 | piqp | 20.56 | 2.10 |
| fleet_grid_box_n1 | cold_total | high | 0.570 | piqp | 0.274 | 2.08 |
| di_soc_N50 | setup | high | 1.96 | clarabel | 0.942 | 2.08 |
| di_soc_N50 | setup | medium | 1.98 | clarabel | 0.956 | 2.07 |
| fleet_ring_soc_n1 | setup | low | 0.658 | mumblebee_fast | 0.321 | 2.05 |
| di_soc_N100 | setup | low | 3.47 | clarabel | 1.70 | 2.04 |
| fleet_ring_box_n16 | cold_total | low | 15.92 | piqp | 7.84 | 2.03 |
| di_soc_N10 | setup | low | 0.499 | clarabel | 0.250 | 2.00 |
| fleet_ring_soc_n1 | setup | medium | 0.656 | mumblebee_fast | 0.328 | 2.00 |
| fleet_ring_box_n4 | cold | low | 1.06 | hpipm | 0.534 | 1.99 |
| di_soc_N100 | setup | medium | 3.42 | clarabel | 1.71 | 1.99 |
| fleet_grid_box_n16 | cold_total | medium | 26.09 | hpipm | 13.21 | 1.97 |
| fleet_ring_soc_n1 | setup | e8 | 0.638 | mumblebee_fast | 0.325 | 1.96 |
| di_soc_N10 | setup | high | 0.492 | clarabel | 0.251 | 1.96 |
| di_soc_N50 | setup | e8 | 1.90 | clarabel | 0.975 | 1.95 |
| quad_N100 | cold | medium | 2.54 | hpipm | 1.31 | 1.95 |
| di_box_N10 | cold_total | high | 0.492 | hpipm | 0.258 | 1.91 |
| di_soc_N100 | setup | e8 | 3.38 | clarabel | 1.77 | 1.91 |
| fleet_grid_soc_n1 | setup | medium | 0.599 | clarabel | 0.315 | 1.90 |
| osqprand_nx40_s1 | cold | high | 4.05 | hpipm | 2.14 | 1.90 |
| fleet_ring_box_n4 | warm | low | 0.912 | hpipm | 0.484 | 1.89 |
| fleet_ring_soc_n1 | setup | high | 0.630 | mumblebee_fast_ct | 0.336 | 1.88 |
| fleet_grid_soc_n64 | cold_total | low | 574 | mumblebee | 308 | 1.86 |
| di_soc_N100 | setup | high | 3.43 | clarabel | 1.84 | 1.86 |
| fleet_ring_soc_b4_n1 | setup | low | 0.447 | clarabel | 0.241 | 1.86 |
| fleet_grid_soc_b4_n1 | setup | low | 0.438 | clarabel | 0.237 | 1.84 |
| fleet_grid_soc_n1 | setup | low | 0.600 | clarabel | 0.325 | 1.84 |
| fleet_grid_box_n4 | cold | medium | 1.17 | hpipm | 0.636 | 1.83 |
| fleet_grid_soc_b4_n1 | setup | e8 | 0.413 | clarabel | 0.226 | 1.83 |
| di_soc_N10 | setup | e8 | 0.486 | clarabel | 0.266 | 1.82 |
| fleet_grid_soc_b4_n1 | setup | high | 0.423 | clarabel | 0.233 | 1.82 |
| fleet_ring_soc_b4_n1 | setup | medium | 0.429 | clarabel | 0.238 | 1.80 |
| fleet_ring_box_n4 | cold | medium | 1.13 | hpipm | 0.631 | 1.79 |
| di_soc_N25 | setup | low | 1.16 | mumblebee_fast_ct | 0.656 | 1.77 |
| fleet_grid_soc_b4_n1 | setup | medium | 0.437 | clarabel | 0.247 | 1.77 |
| fleet_ring_soc_b4_n1 | setup | high | 0.409 | clarabel | 0.231 | 1.77 |
| fleet_grid_soc_n1 | setup | high | 0.571 | mumblebee_fast | 0.323 | 1.77 |
| fleet_grid_soc_n1 | setup | e8 | 0.576 | mumblebee_fast | 0.330 | 1.75 |
| quad_N100 | cold | high | 2.61 | hpipm | 1.50 | 1.74 |
| fleet_ring_soc_b4_n1 | setup | e8 | 0.415 | clarabel | 0.239 | 1.74 |
| osqprand_nx20_s2 | warm | medium | 0.870 | hpipm | 0.520 | 1.67 |
| fleet_grid_box_n4 | cold | low | 1.17 | piqp | 0.699 | 1.67 |
| fleet_ring_box_n4 | cold | high | 1.14 | hpipm | 0.686 | 1.66 |
| fleet_grid_box_n4 | warm | medium | 0.983 | hpipm | 0.601 | 1.63 |
| fleet_ring_box_b4_n4 | cold_total | low | 2.86 | osqp | 1.75 | 1.63 |
| osqprand_nx40_s2 | cold_total | high | 41.55 | piqp | 25.63 | 1.62 |
| fleet_ring_box_n4 | warm | medium | 0.870 | hpipm | 0.546 | 1.59 |
| fleet_ring_box_n16 | cold_total | medium | 16.01 | piqp | 10.24 | 1.56 |
| fleet_grid_soc_n4 | cold_total | low | 6.13 | clarabel | 4.07 | 1.51 |
| fleet_grid_box_n16 | cold_total | high | 24.37 | hpipm | 16.23 | 1.50 |
| osqprand_nx20_s1 | cold_total | high | 7.23 | piqp | 4.83 | 1.50 |
| osqprand_nx20_s3 | cold_total | high | 7.30 | piqp | 4.92 | 1.48 |
| reduced_k0 | cold_total | low | 61.53 | mumblebee_fast | 42.73 | 1.44 |
| fleet_grid_box_n4 | cold | high | 1.21 | hpipm | 0.841 | 1.43 |
| fleet_grid_soc_n64 | cold_total | medium | 614 | mumblebee | 435 | 1.41 |
| di_box_N100 | cold | medium | 1.24 | hpipm | 0.881 | 1.41 |
| fleet_ring_box_b4_n16 | cold_total | low | 11.45 | piqp | 8.23 | 1.39 |
| fleet_grid_box_b4_n16 | cold_total | low | 16.03 | piqp | 11.65 | 1.38 |
| fleet_ring_box_n16 | cold_total | high | 16.06 | piqp | 11.76 | 1.37 |
| fleet_ring_soc_n4 | cold_total | low | 6.01 | clarabel | 4.41 | 1.36 |
| fleet_grid_soc_n64 | cold | low | 365 | mumblebee | 270 | 1.35 |
| fleet_ring_box_n4 | warm | high | 0.881 | hpipm | 0.653 | 1.35 |
| fleet_grid_box_n4 | warm | low | 1.01 | piqp | 0.757 | 1.34 |
| di_box_N100 | cold | high | 1.31 | hpipm | 0.996 | 1.31 |
| fleet_ring_soc_n64 | cold_total | low | 140 | mumblebee_fast_ct | 107 | 1.30 |
| fleet_grid_box_n4 | warm | high | 0.955 | hpipm | 0.736 | 1.30 |
| reduced_k8 | cold_total | low | 31.44 | mumblebee_fast_ct | 24.79 | 1.27 |
| di_soc_N50 | cold_total | low | 2.97 | clarabel | 2.39 | 1.24 |
| osqprand_nx20_s1 | cold | medium | 0.690 | hpipm | 0.562 | 1.23 |
| chain_M8 | cold | high | 1.52 | piqp | 1.25 | 1.22 |
| fleet_grid_soc_b4_n64 | cold_total | low | 348 | mumblebee | 287 | 1.21 |
| reduced_k0 | cold_total | medium | 62.21 | mumblebee_fast | 51.37 | 1.21 |
| reduced_k4 | cold_total | low | 28.00 | mumblebee_fast_ct | 23.46 | 1.19 |
| osqprand_nx20_s1 | cold | low | 0.567 | hpipm | 0.475 | 1.19 |
| di_soc_N100 | cold_total | low | 5.24 | clarabel | 4.39 | 1.19 |
| fleet_grid_soc_n16 | cold_total | low | 47.56 | mumblebee_fast | 41.10 | 1.16 |
| fleet_grid_soc_n64 | warm | high | 664 | mumblebee | 574 | 1.16 |
| osqprand_nx10_s2 | cold | medium | 0.139 | hpipm | 0.121 | 1.14 |
| fleet_grid_soc_b4_n4 | cold_total | low | 3.89 | clarabel | 3.41 | 1.14 |
| reduced_k8 | cold_total | medium | 31.70 | mumblebee_fast_ct | 27.88 | 1.14 |
| osqprand_nx20_s3 | cold | medium | 0.573 | hpipm | 0.504 | 1.14 |
| fleet_ring_box_b4_n16 | cold_total | medium | 11.75 | piqp | 10.41 | 1.13 |
| fleet_grid_soc_n64 | cold_total | e8 | 630 | mumblebee | 560 | 1.13 |
| fleet_ring_soc_n16 | cold_total | low | 29.44 | mumblebee_fast_ct | 26.17 | 1.13 |
| reduced_k2 | cold_total | low | 26.88 | mumblebee_fast_ct | 24.40 | 1.10 |
| fleet_ring_soc_n4 | cold_total | medium | 6.14 | clarabel | 5.59 | 1.10 |
| fleet_grid_soc_n4 | cold_total | medium | 6.40 | clarabel | 5.84 | 1.10 |
| fleet_grid_box_n16 | warm | low | 9.41 | hpipm | 8.61 | 1.09 |
| osqprand_nx20_s2 | cold | low | 0.372 | hpipm | 0.347 | 1.07 |
| di_soc_N10 | cold_total | low | 0.615 | clarabel | 0.575 | 1.07 |
| fleet_grid_soc_n64 | warm | low | 356 | mumblebee | 333 | 1.07 |
| fleet_ring_box_n16 | cold | low | 6.90 | piqp | 6.50 | 1.06 |
| di_soc_N50 | cold_total | medium | 3.41 | clarabel | 3.22 | 1.06 |
| fleet_ring_soc_n64 | cold_total | medium | 151 | mumblebee_fast_ct | 143 | 1.06 |
| di_soc_N25 | cold_total | low | 1.60 | mumblebee_fast_ct | 1.52 | 1.05 |
| fleet_grid_box_b4_n16 | cold_total | medium | 15.87 | piqp | 15.10 | 1.05 |
| fleet_grid_soc_n64 | cold_total | high | 634 | mumblebee | 612 | 1.04 |
| di_box_N50 | cold | low | 0.277 | hpipm | 0.268 | 1.03 |
| reduced_k0 | cold_total | e8 | 61.90 | mumblebee_fast | 60.04 | 1.03 |
| fleet_grid_box_b4_n64 | cold_total | low | 130 | mumblebee_fast_ct | 126 | 1.03 |
| osqprand_nx40_s1 | warm | medium | 1.75 | hpipm | 1.71 | 1.02 |
| fleet_grid_soc_n64 | cold | medium | 403 | mumblebee | 396 | 1.02 |
| fleet_ring_soc_b4_n4 | cold_total | low | 3.91 | clarabel | 3.84 | 1.02 |
| fleet_ring_soc_n1 | cold_total | low | 0.840 | clarabel | 0.828 | 1.02 |
| osqprand_nx40_s1 | warm | high | 1.84 | hpipm | 1.81 | 1.01 |
| di_box_N100 | warm | low | 0.585 | hpipm | 0.580 | 1.01 |
| reduced_k8 | cold_total | e8 | 31.65 | mumblebee_fast_ct | 31.36 | 1.01 |

sheafmpc is fastest (ratio <= 1) in 430 of 816 (instance, mode, tier) cells with a finite ratio; median ratio 0.94.

## Gate: sheafmpc against mumblebee_fast (median time ratio; <= 1 passes)

| mode | tier | cells | pass | sheafmpc misses the tier | median ratio | worst ratio (instance) |
|---|---|---:|---:|---:|---:|---|
| cold | low | 43 | 43 | 0 | 0.37 | 0.67 (fleet_ring_soc_n64) |
| cold | medium | 43 | 43 | 0 | 0.26 | 0.56 (fleet_ring_soc_n64) |
| cold | e8 | 22 | 22 | 0 | 0.33 | 0.48 (fleet_ring_soc_n64) |
| cold | high | 40 | 40 | 0 | 0.21 | 0.47 (fleet_ring_soc_n64) |
| setup | low | 43 | 1 | 0 | 1.76 | 4.08 (fleet_grid_soc_n16) |
| setup | medium | 43 | 1 | 0 | 1.83 | 4.03 (fleet_grid_soc_n16) |
| setup | e8 | 22 | 0 | 0 | 2.16 | 4.08 (fleet_grid_soc_n16) |
| setup | high | 40 | 1 | 0 | 1.73 | 4.10 (fleet_grid_soc_n16) |
| cold_total | low | 43 | 29 | 0 | 0.90 | 1.44 (reduced_k0) |
| cold_total | medium | 43 | 41 | 0 | 0.75 | 1.21 (reduced_k0) |
| cold_total | e8 | 22 | 21 | 0 | 0.73 | 1.03 (reduced_k0) |
| cold_total | high | 40 | 40 | 0 | 0.63 | 0.90 (reduced_k0) |
| warm | low | 40 | 40 | 0 | 0.22 | 0.58 (fleet_ring_soc_n64) |
| warm | medium | 39 | 39 | 0 | 0.19 | 0.51 (fleet_ring_soc_n64) |
| warm | e8 | 22 | 22 | 0 | 0.26 | 0.43 (fleet_ring_soc_n16) |
| warm | high | 40 | 40 | 0 | 0.17 | 0.39 (fleet_grid_soc_n16) |
