#!/bin/bash
# E111: off-formation starts, intra-team diffusion. One exclusive hpg-dev node per fleet size, the 5 seeds as 5
# single-threaded processes, each pinned to its own core (cores 0, 8, 16, 24, 32).
#SBATCH --job-name=e111
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8
#SBATCH --mem=128gb --time=05:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/e111/logs/%x_%j.log
set -uo pipefail
B=/blue/fairbanksj/itaykadosh/e111
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e111_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
export E111_PARTDIR=$B/parts
# at 1024 vehicles converged centralized MPC (Clarabel, 1e-9) is too slow for 400 closed-loop steps per seed
[ "$E111_N" = 1024 ] && export E111_ARMS=team,diffuse,diffuse_opt,alg1
cd $B/tree3/teammpc-paper
echo "host $(hostname); job $SLURM_JOB_ID; n $E111_N; load $(cat /proc/loadavg); cpus $(taskset -pc $$)"
julia --startup-file=no --project=env -e "using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println(\"precompiled\")"
ok=1; pids=()
for s in 1 2 3 4 5; do
  core=$(( (s-1)*8 ))
  E111_SEEDS=$s E111_AFFINITY="core $core of an exclusive node, 5 runs in parallel" taskset -c $core \
    julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e111_offformation.jl > $B/logs/e111_n${E111_N}_s${s}_$SLURM_JOB_ID.out 2>&1 &
  pids+=($!)
done
for p in "${pids[@]}"; do wait $p || ok=0; done
[ $ok = 1 ] && touch $B/done/n$E111_N
touch $B/done/finished_n$E111_N
exit $((1-ok))
