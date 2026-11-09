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
CORE="${BENCH_CORE:-6}"; export BENCH_CORE="$CORE"     # another agent times on cores 3 and 10
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
STAMP="$(date +%Y%m%d_%H%M)"
jl() { taskset -c "$CORE" julia --startup-file=no -t 1 "$@"; }

[ -d "$HERE/data/osqprand" ] && [ -d "$HERE/data/reduced" ] || bash "$HERE/gen/make_data.sh"

case "${1:-}" in
  quick)
    OUT="${OUT:-$HERE/results/quick_$STAMP}"
    jl --project="$HERE" "$HERE/run.jl" quick --out "$OUT"
    for V in mumblebee_fast mumblebee_fast_ct; do
      [ -d "$HERE/envs/$V" ] && BENCH_MUMBLEBEE_NAME=$V jl --project="$HERE/envs/$V" "$HERE/run.jl" quick --solvers $V --out "$OUT/$V"
    done
    julia --project="$HERE" "$HERE/summarize.jl" "$OUT/summary" "$OUT" $(for V in mumblebee_fast mumblebee_fast_ct; do [ -d "$OUT/$V" ] && echo "$OUT/$V"; done)
    ;;
  full)
    OUT="${OUT:-$HERE/results/full_$STAMP}"
    jl --project="$HERE" "$HERE/run.jl" full --out "$OUT"
    for V in mumblebee_fast mumblebee_fast_ct; do
      [ -d "$HERE/envs/$V" ] && BENCH_MUMBLEBEE_NAME=$V jl --project="$HERE/envs/$V" "$HERE/run.jl" full --solvers $V --out "$OUT/$V"
    done
    julia --project="$HERE" "$HERE/summarize.jl" "$OUT/summary" "$OUT" $(for V in mumblebee_fast mumblebee_fast_ct; do [ -d "$OUT/$V" ] && echo "$OUT/$V"; done)
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
