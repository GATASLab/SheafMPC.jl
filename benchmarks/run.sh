#!/bin/bash
# run.sh: one command per tier.
#
#   benchmarks/run.sh quick        local, a few minutes: small instances of every family, then the summary
#   benchmarks/run.sh full         local, every family and size up to n = 256, plus the second Mumblebee variant
#   benchmarks/run.sh hpg-prepare  sync to HPG, instantiate on the login node, write one sbatch per instance
#   benchmarks/run.sh hpg-submit   submit the jobs written by hpg-prepare (tier in $HPG_TIER: hpg or full)
#   benchmarks/run.sh summarize OUT DIR...
#
# Timing runs pin one core (BENCH_CORE, default 3), one Julia and one BLAS
# thread, and wait for the 1-minute load to drop below BENCH_MAX_LOAD (4).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="${BENCH_CORE:-3}"
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
STAMP="$(date +%Y%m%d_%H%M)"
jl() { taskset -c "$CORE" julia --startup-file=no -t 1 "$@"; }

[ -d "$HERE/data/osqprand" ] && [ -d "$HERE/data/reduced" ] || bash "$HERE/gen/make_data.sh"

case "${1:-}" in
  quick)
    OUT="${OUT:-$HERE/results/quick_$STAMP}"
    jl --project="$HERE" "$HERE/run.jl" quick --out "$OUT"
    julia --project="$HERE" "$HERE/summarize.jl" "$OUT/summary" "$OUT"
    ;;
  full)
    OUT="${OUT:-$HERE/results/full_$STAMP}"
    jl --project="$HERE" "$HERE/run.jl" full --out "$OUT"
    if [ -d "$HERE/envs/mumblebee_fast" ]; then
      BENCH_MUMBLEBEE_NAME=mumblebee_fast jl --project="$HERE/envs/mumblebee_fast" "$HERE/run.jl" full \
        --solvers mumblebee_fast --out "$OUT/mumblebee_fast"
    fi
    julia --project="$HERE" "$HERE/summarize.jl" "$OUT/summary" "$OUT" $( [ -d "$OUT/mumblebee_fast" ] && echo "$OUT/mumblebee_fast" )
    ;;
  hpg-prepare)
    bash "$HERE/hpg/prepare.sh"
    ;;
  hpg-submit)
    bash "$HERE/hpg/submit.sh"
    ;;
  summarize)
    shift; OUTS="$1"; shift
    julia --project="$HERE" "$HERE/summarize.jl" "$OUTS" "$@"
    ;;
  *)
    sed -n 2,12p "$0"; exit 1
    ;;
esac
