#!/bin/bash
# E112 at n = 1024 (fallback, no exclusive node free before the deadline): 20 dedicated cores on a shared hpg-default
# node, 10 single-threaded processes, one per (seed 1..5, omega 0.2 and 1), each pinned to every other allocated core.
# 8 samples per loop and eps in {0.01, 1e-3, 1e-4}: the converged centralized solve takes tens of seconds per sample.
#SBATCH --job-name=e112k
#SBATCH --account=fairbanksj
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=20
#SBATCH --mem=160gb --time=04:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e112/logs/%x_%j.log
set -uo pipefail
B=/blue/fairbanksj/itaykadosh/e112
module load julia/1.12.6
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar
cd $B/tree_${TREE}
L=/blue/fairbanksj/itaykadosh/e71/tree/teammpc-paper/scripts/resolution/experiments
export E112_COMMIT=$(cat COMMIT) E112_LIBDIR=$L E112_LIBMD5=$(cat $L/*.jl | md5sum | cut -c1-32)
export E112_N=1024 E112_STEPS=8 E112_EPS=0.01,0.001,0.0001
echo "host $(hostname); job $SLURM_JOB_ID; tree $TREE; load $(cat /proc/loadavg); cpus $(taskset -pc $$)"
CPUS=$(python3 -c 'import os; print(",".join(map(str, sorted(os.sched_getaffinity(0)))))'); echo cpus $CPUS
ok=1; pids=(); slot=0
for om in 1.0 0.2; do
  mkdir -p $B/parts_1024_om$om
  for s in 1 2 3 4 5; do
    core=$(echo $CPUS | cut -d, -f$((2*slot+1))); slot=$((slot+1))
    E112_OMEGAS=$om E112_SEEDS=$s E112_PARTDIR=$B/parts_1024_om$om E112_AFFINITY="core $core (dedicated cores on a shared node, 2 cores per run, 10 runs in parallel)" taskset -c $core \
      julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e112_refine_structured.jl > $B/logs/e112_n1024_om${om}_s${s}_$SLURM_JOB_ID.out 2>&1 &
    pids+=($!)
  done
done
for p in "${pids[@]}"; do wait $p || ok=0; done
[ $ok = 1 ] && touch $B/done/n1024_$SLURM_JOB_ID
touch $B/done/finished_$SLURM_JOB_ID
exit $((1-ok))
