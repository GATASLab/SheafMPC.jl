#!/bin/bash
# make_jobs.sh: write hpg/jobs/<tier>_<group><suffix>.sbatch.
#
# Grouping (HPG_GROUPING): fine (default): quick is one job, tier hpg one job
# per instance, tier full one job per family and variant. coarse (for exclusive
# nodes, fewer nodes held): quick one job; full four jobs (ring fleets, grid
# fleets, single-agent, chain + OSQP random + reduced); hpg two jobs for n = 256
# (ring, grid) and one per n = 1024 instance.
#
# Every job pins one core of a Rome node (EPYC 7702), one Julia and one BLAS
# thread, runs the main solvers, then the Mumblebee variants of the other
# environments. HPG_EXCLUSIVE=1 holds the whole node (no neighbours sharing
# memory bandwidth or L3). The load gate is off on HPG; the load is recorded.
#
# HPG_CPUS: cores reserved per job (default 2; one is pinned). HPG_PKGDIR: the SheafMPC.jl tree to run (default $ROOT/SheafMPC.jl; a ref
# snapshot from prepare_ref.sh). HPG_SOLVERS=a,b restricts the main pass;
# HPG_SUFFIX names the job set and its results directory.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${HPG_ROOT:-/blue/fairbanksj/itaykadosh/sheafmpc_bench}"
PKGDIR="${HPG_PKGDIR:-$ROOT/SheafMPC.jl}"
STAMP="${HPG_STAMP:-$(date +%Y%m%d)}"
SOLVERS_ARG=""; [ -n "${HPG_SOLVERS:-}" ] && SOLVERS_ARG="--solvers ${HPG_SOLVERS}"
SUF="${HPG_SUFFIX:-}"
GROUPING="${HPG_GROUPING:-fine}"
EXCL=""; [ "${HPG_EXCLUSIVE:-0}" = 1 ] && EXCL="#SBATCH --exclusive"
# HPG_QOS: e.g. fairbanksj-b (burst: the investment QOS caps the group at 262 cores, two exclusive nodes)
[ -n "${HPG_QOS:-}" ] && EXCL="$EXCL
#SBATCH --qos=${HPG_QOS}"
mkdir -p "$HERE/hpg/jobs"; rm -f "$HERE/hpg/jobs/"*${SUF}.sbatch

groups() {   # tier -> lines "name|only-pattern"
  local TIER=$1 KEYS
  KEYS=$(julia --project="$HERE" "$HERE/run.jl" $TIER --list 2>/dev/null)
  if [ $TIER = quick ]; then echo "all|"; return; fi
  if [ $GROUPING = coarse ]; then
    if [ $TIER = full ]; then
      printf "%s\n" "fleet_ring|fleet_ring_" "fleet_grid|fleet_grid_" "single|di_box_,di_soc_,quad_" "other|chain_,osqprand_,reduced_"
    else
      printf "%s\n" "ring_n256|fleet_ring_box_n256,fleet_ring_soc_n256,fleet_ring_box_b4_n256,fleet_ring_soc_b4_n256" \
                    "grid_n256|fleet_grid_box_n256,fleet_grid_soc_n256,fleet_grid_box_b4_n256,fleet_grid_soc_b4_n256"
      echo "$KEYS" | grep n1024 | sed 's/.*/&|&/'
    fi
  elif [ $TIER = hpg ]; then
    echo "$KEYS" | sed 's/.*/&|&/'
  else
    echo "$KEYS" | sed -E 's/(_n|_N|_M|_nx|_k)[0-9]+(_s[0-9]+)?$/\1/' | sort -u | sed 's/.*/&|&/'
  fi
}

for TIER in quick hpg full; do
  for line in $(groups $TIER); do
    G=${line%%|*}; PAT=${line#*|}
    ONLY=""; [ -n "$PAT" ] && ONLY="--only $PAT"
    MEM=16gb; TIME=12:00:00
    case "$G" in
      all) TIME=06:00:00;;
      *n1024) MEM=96gb; TIME=96:00:00;;
      *n256) MEM=48gb; TIME=72:00:00;;
      fleet_ring|fleet_grid|fleet_*_n) MEM=48gb; TIME=48:00:00;;
    esac
    cat > "$HERE/hpg/jobs/${TIER}_${G}${SUF}.sbatch" <<EOT
#!/bin/bash
#SBATCH --job-name=smb_${TIER}_${G}${SUF}
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --constraint=rome
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=${HPG_CPUS:-2} --mem=${MEM} --time=${TIME}
${EXCL}
#SBATCH --output=${ROOT}/logs/%x_%j.log
module load julia/1.12.6
export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
export HPIPM_LIB_DIR=/blue/fairbanksj/itaykadosh/central_bench/acados/lib PIQP_LIB=${ROOT}/tools/piqp-install/lib/libpiqpc.so
export BENCH_MAX_LOAD=1e9 BENCH_TIME_LIMIT=600 BENCH_FLEET_MAXN=64   # n = 256 runs in the hpg tier
cd ${PKGDIR}/benchmarks
CORE=\$(taskset -cp \$\$ | awk -F': ' '{print \$2}' | cut -d, -f1 | cut -d- -f1)
[ \$(nproc) -gt 8 ] && CORE=16          # exclusive node: a core away from 0 (interrupts)
lscpu | grep "Model name"; echo "core \$CORE"; nproc
OUT=${ROOT}/results/${TIER}_${STAMP}${SUF}
taskset -c \$CORE julia --startup-file=no -t 1 --project=. run.jl ${TIER} ${ONLY} ${SOLVERS_ARG} --out \$OUT
for V in mumblebee_fast mumblebee_fast_ct; do
  [ -d envs/\$V ] || continue
  BENCH_MUMBLEBEE_NAME=\$V taskset -c \$CORE julia --startup-file=no -t 1 --project=envs/\$V run.jl ${TIER} ${ONLY} \\
    --solvers \$V --out \$OUT/\$V
done
echo "done \$(date -Is)"
EOT
  done
done
ls "$HERE/hpg/jobs/"*${SUF}.sbatch | wc -l
