#!/bin/bash
#SBATCH --job-name=e63t_sq_n4096_s4
#SBATCH --mem=64gb --time=24:00:00
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --output=/blue/fairbanksj/itaykadosh/e63/logs/%x_%j.log
export BENCH_DISC=zoh BENCH_FLEET=dronecar
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e63_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
cd /blue/fairbanksj/itaykadosh/e63/tree/teammpc-paper
echo "host $(hostname); load $(cat /proc/loadavg)"
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")'

ok=1
BENCH_INSTANCE=squads E63_N=4096 E63_SEEDS=4 E63_STEPS=30 E63_PATHS=team,orbits,coord,lifted E63_RHO_FULL=0.1 E63_RHO_QUOT=1 E63_PARTDIR=/blue/fairbanksj/itaykadosh/e63/parts julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e63_time.jl || ok=0
[ $ok = 1 ] && touch /blue/fairbanksj/itaykadosh/e63/done/e63t_sq_n4096_s4
touch /blue/fairbanksj/itaykadosh/e63/finished/e63t_sq_n4096_s4
