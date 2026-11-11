#!/bin/bash
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=150gb --time=6:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e118/logs/%x_%j.log
# E118 on an exclusive hpg-dev node: the seeds of E118_JOBSEEDS (from the job name e118x_<s1>[-<s2>...]) run in
# parallel, each pinned to its own core, cores 16 apart.
R=/blue/fairbanksj/itaykadosh/e118/tree/mpc-ecc-final
SEEDS=${SLURM_JOB_NAME#e118x_}; SEEDS=${SEEDS//-/ }
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e118_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
export BENCH_DISC=zoh BENCH_FLEET=dronecar BENCH_INSTANCE=natural E71_FALLBACK=shift E102_FALLBACK=shift E71_CERT_IN_STEP=1
export E118_COMMIT=08cfc5bcf7b421c5840fec0d4fe41602ee92ba47 E118_COMMIT_NOTE=ecc-final_HEAD_plus_untracked_e117_e118_scripts E118_EXCLUSIVE=1
export E118_E106_PARTS=/blue/fairbanksj/itaykadosh/e106/parts4h E118_PARTDIR=/blue/fairbanksj/itaykadosh/e118/parts118
export E118_N=4096 E118_STEPS=30 E118_EPS=0.03:0.01 E118_FB=shift:none
cd $R
echo "seeds $SEEDS host $(hostname); load $(cat /proc/loadavg)"; lscpu | grep "Model name"; taskset -pc $$
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")' || exit 1
pids=(); i=0
for s in $SEEDS; do
  c=$((16 * i)); i=$((i + 1))
  E118_SEEDS=$s E118_AFFINITY="core $c of exclusive node" taskset -c $c \
    julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e118_refine_irregular.jl \
    > /blue/fairbanksj/itaykadosh/e118/logs/e118_seed${s}_$SLURM_JOB_ID.log 2>&1 &
  pids+=($!)
done
st=0; for p in ${pids[@]}; do wait $p || st=1; done
echo "end $(date -Is) load $(cat /proc/loadavg) status $st"; exit $st
