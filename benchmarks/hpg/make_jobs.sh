#!/bin/bash
# make_jobs.sh: write hpg/jobs/<tier>_<group>.sbatch. Tier hpg (fleets n = 256
# and 1024): one job per instance. Tier full: one job per family and variant
# (all its sizes in sequence). Every job pins one core of a Rome node
# (EPYC 7702), one Julia and one BLAS thread, and runs the second Mumblebee
# variant after the main solvers. The load gate is off on HPG (the node's load
# counts other users' jobs); the load is still recorded.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${HPG_ROOT:-/blue/fairbanksj/itaykadosh/sheafmpc_bench}"
STAMP="${HPG_STAMP:-$(date +%Y%m%d)}"
# HPG_SOLVERS=a,b restricts the main pass to these solvers (and HPG_SUFFIX names
# the job set and its results directory), for a supplementary run of some solvers
SOLVERS_ARG=""; [ -n "${HPG_SOLVERS:-}" ] && SOLVERS_ARG="--solvers ${HPG_SOLVERS}"
SUF="${HPG_SUFFIX:-}"
mkdir -p "$HERE/hpg/jobs"; rm -f "$HERE/hpg/jobs/"*${SUF}.sbatch
for TIER in quick hpg full; do
  KEYS=$(julia --project="$HERE" "$HERE/run.jl" $TIER --list 2>/dev/null)
  if [ $TIER = quick ]; then GROUPS_="all"; elif [ $TIER = hpg ]; then GROUPS_="$KEYS"; else GROUPS_=$(echo "$KEYS" | sed -E 's/(_n|_N|_M|_nx|_k)[0-9]+(_s[0-9]+)?$/\1/' | sort -u); fi
  for G in $GROUPS_; do
    MEM=16gb; TIME=12:00:00; ONLY="--only ${G}"; [ "$G" = all ] && ONLY="" && TIME=04:00:00
    case "$G" in *n1024) MEM=96gb; TIME=48:00:00;; *n256) MEM=48gb; TIME=24:00:00;; fleet_*_n) MEM=48gb; TIME=48:00:00;; esac
    cat > "$HERE/hpg/jobs/${TIER}_${G}${SUF}.sbatch" <<EOT
#!/bin/bash
#SBATCH --job-name=smb_${TIER}_${G}${SUF}
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --constraint=rome
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2 --mem=${MEM} --time=${TIME}
#SBATCH --output=${ROOT}/logs/%x_%j.log
module load julia/1.12.6
export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
export HPIPM_LIB_DIR=/blue/fairbanksj/itaykadosh/central_bench/acados/lib PIQP_LIB=${ROOT}/tools/piqp-install/lib/libpiqpc.so
export BENCH_MAX_LOAD=1e9 BENCH_TIME_LIMIT=600 BENCH_FLEET_MAXN=64   # n = 256 runs in the hpg tier
cd ${ROOT}/SheafMPC.jl/benchmarks
CORE=\$(taskset -cp \$\$ | awk -F': ' '{print \$2}' | cut -d, -f1 | cut -d- -f1)
lscpu | grep "Model name"; echo "core \$CORE"
OUT=${ROOT}/results/${TIER}_${STAMP}${SUF}
taskset -c \$CORE julia --startup-file=no -t 1 --project=. run.jl ${TIER} ${ONLY} ${SOLVERS_ARG} --out \$OUT
BENCH_MUMBLEBEE_NAME=mumblebee_fast taskset -c \$CORE julia --startup-file=no -t 1 --project=envs/mumblebee_fast run.jl ${TIER} \\
  ${ONLY} --solvers mumblebee_fast --out \$OUT/mumblebee_fast
echo "done \$(date -Is)"
EOT
  done
done
ls "$HERE/hpg/jobs" | wc -l
