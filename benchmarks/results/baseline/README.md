# Baselines

| directory | package | where | notes |
|---|---|---|---|
| `hpg_shared_a284b72/` | SheafMPC master a284b72 (the release candidate), harness 638707f | HPG, AMD EPYC 7702 (Rome), shared nodes, 8 cores reserved per job, 1 pinned, 1 thread | full tier (60 of 68 instances when summarized: fleets n <= 64 and every other family; all three Mumblebee variants) and quick tier, with setup, solve and setup + solve as separate modes. Large fleets (n = 256, 1024) and the exclusive-node run were still queued or running. |
| `hpg_shared_f93303f/` | SheafMPC master f93303f (src = fa5390d), harness 1e48122 | HPG, AMD EPYC 7702 (Rome), shared nodes, 8 cores reserved per job, 1 pinned, 1 thread | full tier (fleets n <= 64 and every other family) and quick tier; `summary_full/`, `summary_quick/` (tables, `dat/` for pgfplots). Large fleets (n = 256, 1024) and the exclusive-node run are pending at the time of writing. |
| `laptop_quick/` | SheafMPC master as of 05:45 on 2026-10-18 (recorded per instance) | AMD Ryzen AI 7 350, core 3 pinned, load gate 4 | quick tier with the Mumblebee variants; `summary/summary.md` |

Solvers: SheafMPC (defaults), OSQP 0.6.2 (OSQP.jl 0.8.1), Clarabel 0.11.1, HPIPM bad1123
(acados build, AVX2 on HPG), PIQP 0.6.4 (C interface, -march=native), Mumblebee pinned
e78d9b9, fast-symbolic 9416b46, and fast-symbolic with CliqueTrees 0015e2b; every
version and setting is in each result file.
