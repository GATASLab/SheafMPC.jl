#!/bin/bash
#SBATCH --job-name=e106f_s1
#SBATCH --mem=64gb --time=3:00:00
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --output=/blue/fairbanksj/itaykadosh/e106/logs/%x_%j.log
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e106_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar BENCH_INSTANCE=natural E102_EXCLUSIVE=1 E71_FALLBACK=shift E71_CERT_IN_STEP=1
cd /blue/fairbanksj/itaykadosh/e106/tree3/teammpc-paper
CPU=$(taskset -pc $$ | awk -F": " "{print \$2}" | cut -d, -f1 | cut -d- -f1)
export E71_AFFINITY="core $CPU of $(taskset -pc $$ | awk -F": " "{print \$2}")"
echo "host $(hostname); $E71_AFFINITY; load $(cat /proc/loadavg)"
julia --startup-file=no --project=env -e "using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println(\"precompiled\")"
ok=1
E102_ARMS=coord,team E102_PARTDIR=/blue/fairbanksj/itaykadosh/e106/parts3 E102_N=4096 E102_SEEDS=1 E102_STEPS=30 E102_FRACS=0.3,0.42,0.5,0.7 taskset -c $CPU julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e102_irregular4096.jl || ok=0
[ $ok = 1 ] && touch /blue/fairbanksj/itaykadosh/e106/done/e106f_s1
touch /blue/fairbanksj/itaykadosh/e106/finished/e106f_s1
exit $((1-ok))
