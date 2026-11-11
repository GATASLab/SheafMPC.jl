# TeamMPC benchmark harness

The referee for performance work on TeamMPC: every solver gets the same QPs,
is held to the same achieved accuracy by one checker, and is timed by one
clock around the same call boundary.

## Run

```
benchmarks/run.sh quick                     # local, small instances of every family, then the summary
benchmarks/run.sh full                      # local, every family, fleets up to n = 256, both Mumblebee variants
benchmarks/run.sh hpg-prepare               # sync to HPG, instantiate on the login node, build HPIPM/PIQP, write jobs
HPG_TIER=hpg benchmarks/run.sh hpg-submit   # one job per instance (fleets n = 256, 1024); HPG_TIER=full for the rest
benchmarks/run.sh summarize OUT DIR...      # markdown tables and pgfplots .dat files
julia --project=benchmarks benchmarks/run.jl full --list   # instance keys; --only KEY, --solvers a,b, --families f
```

Tests: `test/test_settings.jl` (every solver holds the requested settings, read back from the live object; cold is cold), `test/test_families.jl` (generators against the paper's `qp.jl`, stage
forms against the canonical QPs), `test/test_hpipm.jl`, `test/test_piqp.jl`.

## Layout

| path | role |
|---|---|
| `src/qp.jl` | canonical QP, stage form (`StageOCP`), the shared checker, binary exchange format |
| `src/reference.jl` | high-accuracy reference per QP (Clarabel 1e-11, active-set polish on polyhedral problems), cached by data hash |
| `src/families/` | fleet (paper), single-agent (double integrator, quadrotor), chain of masses, OSQP random MPC, reduced fleets; closed-loop sequences |
| `src/protocol.jl` | calibration, cold mode, warm sequence mode |
| `src/solvers/` | one adapter per solver; `teammpc.jl` is the only file touching the package API |
| `gen/` | data generated outside this environment (OSQP random MPC in numpy, reduced fleets in the paper's environment) |
| `hpg/` | HPG setup, build and job scripts |
| `envs/mumblebee_fast/` | the same harness with the local Mumblebee branch |

## Protocol

* **Problems.** Each instance is a closed-loop sequence: QP k is built from
  the measured state, solved by the reference, its first input applied to the
  plant with a seeded disturbance. The recorded sequence is replayed open loop
  to every solver, so all see identical QPs.
* **Accuracy.** Tiers low 1e-3, medium 1e-6, high 1e-9. A solve meets a tier
  when its relative objective error (constant excluded) and relative primal
  residual, computed on the unscaled problem by `check`, are within it.
  Dual residuals are reported where the solver returns multipliers.
* **Calibration.** Per solver, instance and tier: every documented variant
  (OSQP polish on/off; Clarabel QDLDL/CHOLMOD; Mumblebee AMF/ND ordering; PIQP's
  five KKT solvers; HPIPM's four modes x five partial-condensing levels) with
  its tolerance at eps, eps/10, eps/100, eps/1000; the loosest tolerance meeting
  the tier on the first, middle and last QP; the fastest variant wins.
* **Settings read-back.** After every calibration setup the harness reads the
  settings back from the live solver object (OSQP's C settings struct,
  Clarabel's and Mumblebee's settings, TeamMPC's `Settings`, HPIPM's ipm arg
  struct; for PIQP, which has no getter, the struct passed to setup) and
  disqualifies a variant whose tolerances differ from the requested ones or
  whose warm start is on at setup (OSQP.jl drops unknown keywords silently).
  `test/test_settings.jl` also checks that a warm-mode step of an
  interior-point solver iterates like a cold solve.
* **Cold mode.** Per QP, k repeats of setup (timed separately) and a solve
  from zero (timed).
* **Warm mode.** k replays of the sequence: setup and a cold solve of QP 1,
  then per QP one timed call of data update (factorization kept) + warm start
  + solve. ADMM solvers (TeamMPC, OSQP) start from their own previous
  solution moved one stage (the family's shift map; unshifted when the family
  has none). Interior-point solvers have no warm start; they reuse setup.
* **Statistics.** Per QP the median over repeats; per instance median, p90,
  max; a QP missing the tier is a failure. Over families: shifted geometric
  means (shift 0.1 ms, failures charged the time limit) and Dolan-More
  performance profiles.
* **Timer.** `time_ns` around the call, in process for every solver (HPIPM and
  PIQP through `ccall`), one Julia and one BLAS thread, one pinned core; a
  young-generation GC before each timed call, outside the clock. Every result
  file records CPU, governor, affinity, the load before and after, the
  package's commit and a hash of its working-tree diff (saved next to the
  results), and every solver's version and settings.
