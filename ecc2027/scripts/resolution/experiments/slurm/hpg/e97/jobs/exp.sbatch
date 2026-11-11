#!/bin/bash
#SBATCH --job-name=exp
#SBATCH --mem=32gb --time=1:00:00
#SBATCH --account=fairbanksj
#SBATCH --nodes=1 --ntasks=1
#SBATCH --partition=hpg-default --constraint=rome --cpus-per-task=2
#SBATCH --output=/blue/fairbanksj/itaykadosh/e97/logs/%x_%j.log
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e97_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar
cd /blue/fairbanksj/itaykadosh/e97/tree/teammpc-paper
echo "host $(hostname); cpus $(nproc); load $(cat /proc/loadavg)"; lscpu | grep "Model name"
ok=1
julia --startup-file=no --project=env -e "using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, OSQP, JSON; println(\"precompiled\")"
E97_VARIANTS=C1,E1t,W1,Ccyl E97_N=1024 E97_CONES=box E97_ARMS=clarabel_cond_team E97_DIR=/blue/fairbanksj/itaykadosh/e97/parts_export julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e97_baselines.jl || ok=0
echo "load end $(cat /proc/loadavg)"
[ $ok = 1 ] && touch /blue/fairbanksj/itaykadosh/e97/done/exp
touch /blue/fairbanksj/itaykadosh/e97/finished/exp
exit $((1-ok))
