#!/bin/bash
# submit.sh: submit the build job, then every job of HPG_TIER (hpg, full or all)
# after it; records the job IDs in hpg/submitted_<date>.txt. No polling.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${HPG_ROOT:-/blue/fairbanksj/itaykadosh/sheafmpc_bench}"
TIER="${HPG_TIER:-hpg}"
J="$ROOT/SheafMPC.jl/benchmarks/hpg"
LOG="$HERE/hpg/submitted_$(date +%Y%m%d_%H%M).txt"
B=$(ssh hpg "sbatch --parsable $J/build.sbatch")
echo "build $B" | tee "$LOG"
for f in "$HERE/hpg/jobs/"*.sbatch; do
  n=$(basename "$f" .sbatch)
  case "$TIER" in all) ;; *) [[ "$n" == ${TIER}_* ]] || continue;; esac
  id=$(ssh hpg "sbatch --parsable --dependency=afterok:$B $J/jobs/$n.sbatch")
  echo "$n $id" | tee -a "$LOG"
done
