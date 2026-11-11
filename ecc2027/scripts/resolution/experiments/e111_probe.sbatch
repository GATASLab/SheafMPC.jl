#!/bin/bash
#SBATCH --job-name=e111p --account=fairbanksj --partition=hpg-dev --nodes=1 --ntasks=1 --cpus-per-task=2 --mem=32gb --time=01:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e111/logs/%x_%j.log
module load julia/1.12.6
export JULIA_DEPOT_PATH=${TMPDIR:-/tmp}/d$SLURM_JOB_ID:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
cd /blue/fairbanksj/itaykadosh/e111/tree3/teammpc-paper
for n in 256 1024; do E111_N=$n E111_SEEDS=1 E111_STEPS=4 E111_SIGMAS=0.3 E111_DIST_SIGMA=0 E111_ARMS=central,team E111_WARMUP=0 E111_PARTDIR=/blue/fairbanksj/itaykadosh/e111/probe julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e111_offformation.jl; done
