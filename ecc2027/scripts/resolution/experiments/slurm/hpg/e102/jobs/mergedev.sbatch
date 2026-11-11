#!/bin/bash
#SBATCH --job-name=e102_mergedev
#SBATCH --mem=8gb --time=0:30:00
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=1
#SBATCH --output=/blue/fairbanksj/itaykadosh/e102/logs/%x_%j.log
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e102_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_PKG_PRECOMPILE_AUTO=0
cd /blue/fairbanksj/itaykadosh/e71/tree/teammpc-paper
E102_MODE=merge E102_PARTDIR=/blue/fairbanksj/itaykadosh/e102/parts_dev E102_OUT=/blue/fairbanksj/itaykadosh/e102/e102_dev.json julia --startup-file=no --project=env scripts/resolution/experiments/e102_irregular4096.jl && touch /blue/fairbanksj/itaykadosh/e102/MERGED_DEV
