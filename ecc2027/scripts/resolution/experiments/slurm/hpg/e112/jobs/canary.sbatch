#!/bin/bash
#SBATCH --job-name=e112_canary
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --mem=24gb --time=01:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e112/logs/%x_%j.log
set -uo pipefail
B=/blue/fairbanksj/itaykadosh/e112
module load julia/1.12.6
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar
cd $B/tree_76911c3
export E112_COMMIT=$(cat COMMIT)
echo "host $(hostname); job $SLURM_JOB_ID; load $(cat /proc/loadavg)"
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")'
ok=1
E112_N=64 E112_SEEDS=1 E112_STEPS=5 E112_PARTDIR=$B/parts_canary julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e112_refine_structured.jl || ok=0
E112_N=1024 E112_SEEDS=1 E112_STEPS=3 E112_OMEGAS=0.2 E112_WARMUP=0 E112_PARTDIR=$B/parts_canary julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e112_refine_structured.jl || ok=0
[ $ok = 1 ] && touch $B/done/canary
exit $((1-ok))
