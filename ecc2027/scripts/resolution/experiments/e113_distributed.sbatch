#!/bin/bash
# E113 (distributed MPC baseline): one exclusive hpg-dev node per seed (array task = seed). The 4096-vehicle run
# is pinned to core 0 and the 1024-vehicle run to core 32 (the other socket), concurrently; every arm of a size runs
# sequentially in its process. Run from the HPG copy of E106's tree with this script added (E113_TREE), env
# env (pinned TeamMPC baa542b) in the default ~/.julia depot, instantiated on the login node.
#
#   E113_COMMIT=<sha> sbatch --wait scripts/resolution/experiments/e113_distributed.sbatch
#   E113_MODE=merge E113_PARTDIR=<parts> julia --project=env scripts/resolution/experiments/e113_distributed.jl
#
#SBATCH -A fairbanksj
#SBATCH -p hpg-dev
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --mem=96G
#SBATCH -t 4:00:00
#SBATCH --array=1-5
#SBATCH -J e113
#SBATCH -o /blue/fairbanksj/itaykadosh/e113/logs/%x_%A_%a.log

set -uo pipefail
source /etc/profile.d/modules.sh
module load julia/1.12.6
unset JULIA_DEPOT_PATH
B=/blue/fairbanksj/itaykadosh/e113
cd "${SLURM_SUBMIT_DIR}"
S=${SLURM_ARRAY_TASK_ID}
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar BENCH_INSTANCE=natural
export E102_EXCLUSIVE=1 E71_FALLBACK=shift E71_CERT_IN_STEP=1 E102_FRACS=0.25 E113_SEEDS=$S E113_STEPS=30
export E113_PARTDIR=${E113_PARTDIR:-$B/parts} E113_TREE=$B/tree E113_COMMIT=${E113_COMMIT:-}
echo "host $(hostname); load $(cat /proc/loadavg)"; lscpu | grep -E "Model name|Socket|NUMA node[0-9]"
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, JSON; println("precompiled")'
E71_AFFINITY="exclusive node, core 0 (1024 run concurrently on core 32)" E113_N=4096 \
  taskset -c 0 julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e113_distributed.jl \
  > $B/logs/e113_n4096_s$S.out 2>&1 &
P1=$!
E71_AFFINITY="exclusive node, core 32 (4096 run concurrently on core 0)" E113_N=1024 \
  taskset -c 32 julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e113_distributed.jl \
  > $B/logs/e113_n1024_s$S.out 2>&1 &
P2=$!
ok=1; wait $P1 || ok=0; wait $P2 || ok=0
[ $ok = 1 ] && touch $B/done/seed$S
exit $((1-ok))
