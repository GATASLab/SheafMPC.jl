# ECC 2027: experiments, data, and figures

Everything behind the numbers, tables, and figures of
"Exact and Certified Team Reduction for Large-Fleet Formation MPC"
(Kadosh, Samuelson, and Fairbanks, submitted to ECC 2027).

The experiments use the TeamMPC package of this repository, pinned by commit in
`env/Project.toml`, and a small research library of their own in
`scripts/resolution/src` (graph programs on the time-expanded graph, their
reduction along vertex partitions, and a direct conic solver).

## Layout

| Path | Contents |
|---|---|
| `env/` | The Julia environment of every script (TeamMPC, Clarabel, OSQP, Mumblebee, JSON) |
| `scripts/resolution/src/` | The research library (`Resolution`) |
| `scripts/resolution/experiments/` | One script per experiment, `eNN_*.jl`, with the SLURM job files of its cluster runs |
| `results/` | Raw results as JSON, as produced on the cluster (merged across seeds and jobs) |
| `scripts/gen_numbers*.{jl,py}`, `scripts/resolution/numbers_*.jl` | Turn `results/*.json` into the LaTeX macros the paper prints |
| `preamble/numbers*.tex` | Those macros, each preceded by a comment naming its JSON file and key path |
| `render/` | Figure scripts (Python, matplotlib) |
| `figures/` | The three figures as submitted |

## From paper to experiment

| Paper | Results file | Script |
|---|---|---|
| Table I (exact teams, speedups) | `e97_baselines.json`, `e74_mission.json` | `e97_baselines.jl`, `e74_mission.jl` |
| Table II(a) (irregular fleets) | `e106_overrun_full.json`, `e119_fast_q.json`, `parts119/` | `e102_irregular4096.jl`, `e119_fast_q.jl` |
| Table II(b) (consensus ADMM) | `e52_admm.json` | `e52_admm.jl` |
| Fig. 1 | `overview_fleet.json` | `dump_overview.jl`, `render/fig_overview.py` |
| Fig. 2 | `teams_map.json` | `dump_teams.jl`, `render/gallery/Scale_fig.py` |
| Fig. 3 and the certificate statistics | `fig_certgap_data.json` | `extract_certgap.py`, `merge_certgap.py`, `render/fig_certgap.py` |
| Certified refinement (Sec. VI) | `e112_refine_structured.json`, `e118_refine_irregular.json` | `e112_refine_structured.jl`, `e118_refine_irregular.jl` |
| Off-formation starts (Sec. VI) | `e111_offformation.json` | `e111_offformation.jl` |
| Distributed MPC baseline | `e113_distributed.json` | `e113_distributed.jl` |
| Nonlinear vehicles, acados RTI (Sec. III-B) | `e114_acados_rti.json` | `e114_acados_rti.py` |
| Fleet sizes, horizons, weights | `setup.json`, `e15_summary.json`, `e26_flagship.json` | `setup_params.py`, `e15_summary.jl`, `e26_flagship.jl` |

Every results file records the cluster job, host, CPU, and seeds it came from.
For any number in the paper, search `preamble/numbers*.tex` for its macro; the
comment above it names the source.

## Running

From this directory, with Julia 1.12:

```sh
julia --project=env -e 'using Pkg; Pkg.instantiate()'

# a small run of one experiment (64 vehicles, 3 samples, about a minute)
E119_N=64 E119_SEEDS=1 E119_STEPS=3 E119_WARMUP=0 E119_PARTDIR=/tmp/e119 E119_OUT=/tmp/e119/e119.json \
  julia --project=env scripts/resolution/experiments/e119_fast_q.jl

# regenerate the paper's macros from the stored results
julia --project=env scripts/gen_numbers.jl
for f in certgap e52 offformation refine nonlinear; do
  julia --project=env scripts/resolution/numbers_$f.jl
done
python3 scripts/gen_numbers_e118.py && python3 scripts/gen_numbers_e119.py
```

The full experiments ran on the University of Florida's HiPerGator cluster (AMD
EPYC 75F3, one pinned core per run, exclusive nodes for timing); the job files
next to each script record the exact settings. They contain paths on that
cluster, which you will need to change. Timings depend on the machine; costs,
gaps, and certificates do not.
