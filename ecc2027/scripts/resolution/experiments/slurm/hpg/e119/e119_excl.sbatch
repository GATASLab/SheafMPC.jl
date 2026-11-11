#!/bin/bash
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=150gb --time=3:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e119/logs/%x_%j.log
# E119 on an exclusive hpg-dev node (E118's setup): the seeds of the job name e119x_<s1>[-<s2>...] run in parallel,
# each pinned to its own core, cores 16 apart. E119_COMMIT is passed with sbatch --export.
R=/blue/fairbanksj/itaykadosh/e119/tree/mpc-ecc-combined
SEEDS=${SLURM_JOB_NAME#e119x_}; SEEDS=${SEEDS//-/ }
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e119_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
export BENCH_DISC=zoh BENCH_FLEET=dronecar BENCH_INSTANCE=natural E71_FALLBACK=shift E102_FALLBACK=shift E71_CERT_IN_STEP=1
export E119_COMMIT_NOTE=ecc-combined E119_EXCLUSIVE=1
export E119_E106_PARTS=/blue/fairbanksj/itaykadosh/e106/parts4h E119_PARTDIR=/blue/fairbanksj/itaykadosh/e119/parts119
export E119_N=4096 E119_STEPS=30 E119_REPS=5 E119_INLOOP=1
cd $R
echo "seeds $SEEDS host $(hostname); load $(cat /proc/loadavg)"; lscpu | grep "Model name"; taskset -pc $$
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")' || exit 1
pids=(); i=0
for s in $SEEDS; do
  c=$((16 * i)); i=$((i + 1))
  E119_SEEDS=$s E119_AFFINITY="core $c of exclusive node" taskset -c $c \
    julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e119_fast_q.jl \
    > /blue/fairbanksj/itaykadosh/e119/logs/e119_seed${s}_$SLURM_JOB_ID.log 2>&1 &
  pids+=($!)
done
st=0; for p in ${pids[@]}; do wait $p || st=1; done
echo "end $(date -Is) load $(cat /proc/loadavg) status $st"; exit $st
