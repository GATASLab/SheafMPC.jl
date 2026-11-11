#!/bin/bash
# E112: one exclusive node, 10 single-threaded processes (n = 256 and 1024, seeds 1..5), each pinned to its own core
# on its own core complex (cores 0, 8, ..., 72), so no two processes share an L3 cache.
#SBATCH --job-name=e112
#SBATCH --account=fairbanksj
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=96
#SBATCH --mem=128gb --time=04:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e112/logs/%x_%j.log
set -uo pipefail
B=/blue/fairbanksj/itaykadosh/e112
module load julia/1.12.6
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar
cd $B/tree_${TREE}
export E112_COMMIT=$(cat COMMIT) E112_PARTDIR=$B/parts E112_LIBDIR=/blue/fairbanksj/itaykadosh/e71/tree/teammpc-paper/scripts/resolution/experiments E112_LIBMD5=$(cat /blue/fairbanksj/itaykadosh/e71/tree/teammpc-paper/scripts/resolution/experiments/*.jl | md5sum | cut -c1-32)
echo "host $(hostname); job $SLURM_JOB_ID; tree $TREE; load $(cat /proc/loadavg); cpus $(taskset -pc $$)"
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")'
ok=1; pids=(); slot=0
for n in ${SIZES:-1024 256}; do
  for s in 1 2 3 4 5; do
    core=$(( slot*8 )); slot=$((slot+1))
    E112_N=$n E112_SEEDS=$s E112_AFFINITY="core $core of an exclusive node, 10 runs in parallel, one per core complex" taskset -c $core \
      julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e112_refine_structured.jl > $B/logs/e112_n${n}_s${s}_$SLURM_JOB_ID.out 2>&1 &
    pids+=($!)
  done
done
for p in "${pids[@]}"; do wait $p || ok=0; done
[ $ok = 1 ] && touch $B/done/main_$SLURM_JOB_ID
touch $B/done/finished_$SLURM_JOB_ID
exit $((1-ok))
