#!/bin/bash
#SBATCH --job-name=e118
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=16 --mem=320gb --time=8:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e118/logs/%x_%j.log
# E118: the 5 seeds of E106 in parallel on one exclusive node, one pinned core each (cores spread over the sockets).
R=/blue/fairbanksj/itaykadosh/e118/tree/mpc-ecc-final
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e118_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
export BENCH_DISC=zoh BENCH_FLEET=dronecar BENCH_INSTANCE=natural E71_FALLBACK=shift E102_FALLBACK=shift E71_CERT_IN_STEP=1
export E118_COMMIT=08cfc5bcf7b421c5840fec0d4fe41602ee92ba47 E118_COMMIT_NOTE=ecc-final_HEAD_plus_untracked_e117_e118_scripts E118_EXCLUSIVE=1
export E118_E106_PARTS=/blue/fairbanksj/itaykadosh/e106/parts4h E118_PARTDIR=/blue/fairbanksj/itaykadosh/e118/parts118
export E118_N=4096 E118_STEPS=30 E118_EPS=0.03:0.01
cd $R
echo "host $(hostname); load $(cat /proc/loadavg)"; lscpu | grep "Model name"; nproc
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")' || exit 1
CORES=($(taskset -pc $$ | awk -F": " '{print $2}' | tr ',' '\n' | while IFS=- read a b; do seq $a ${b:-$a}; done))
echo "cores ${CORES[@]}"
pids=()
for s in 1 2 3 4 5; do
  c=${CORES[$(( (s-1)*3 ))]}
  E118_SEEDS=$s E118_AFFINITY="core $c of ${#CORES[@]} allocated" taskset -c $c \
    julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e118_refine_irregular.jl \
    > /blue/fairbanksj/itaykadosh/e118/logs/e118_seed${s}_$SLURM_JOB_ID.log 2>&1 &
  pids+=($!)
done
st=0; for p in ${pids[@]}; do wait $p || st=1; done
echo "end $(date -Is) load $(cat /proc/loadavg) status $st"
exit $st
