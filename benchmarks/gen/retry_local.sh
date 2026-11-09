#!/bin/bash
# retry_local.sh TIER OUT: rerun a local tier until every instance has a result
# (each pass waits up to BENCH_MAX_WAIT per instance for the load gate).
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TIER=$1; OUT=$2
N=$(julia --project="$HERE" "$HERE/run.jl" $TIER --list 2>/dev/null | wc -l)
for pass in $(seq 1 ${PASSES:-24}); do
  OUT="$OUT" "$HERE/run.sh" $TIER
  [ $(ls "$OUT"/*.json 2>/dev/null | wc -l) -ge $N ] && break
done
