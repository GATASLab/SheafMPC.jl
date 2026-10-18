#!/bin/bash
# submit.sh: submit the build job, then every job of HPG_TIER (quick, hpg, full or all)
# of the job set HPG_SUFFIX in HPG_PKGDIR
# after it; records the job IDs in hpg/submitted_<date>.txt. No polling.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${HPG_ROOT:-/blue/fairbanksj/itaykadosh/sheafmpc_bench}"
TIER="${HPG_TIER:-hpg}"
PKGDIR="${HPG_PKGDIR:-$ROOT/SheafMPC.jl}"
J="$PKGDIR/benchmarks/hpg"
LOG="$HERE/hpg/submitted_$(date +%Y%m%d_%H%M).txt"
SUF="${HPG_SUFFIX:-}"
B="${HPG_AFTER:-}"                       # HPG_AFTER=none: no build (it already ran and passed), else a new build first
[ -n "$B" ] || B=$(ssh hpg "sbatch --parsable --export=ALL,PKGDIR=$PKGDIR $J/build.sbatch")
DEP="--dependency=afterok:$B"; [ "$B" = none ] && DEP=""
echo "build $B" | tee "$LOG"
for f in "$HERE/hpg/jobs/"*${SUF}.sbatch; do
  n=$(basename "$f" .sbatch)
  case "$TIER" in all) ;; *) [[ "$n" == ${TIER}_* ]] || continue;; esac
  [ -n "$SUF" ] || [[ "$n" != *_mb ]] || continue
  id=$(ssh hpg "sbatch --parsable $DEP $J/jobs/$n.sbatch")
  echo "$n $id" | tee -a "$LOG"
done
