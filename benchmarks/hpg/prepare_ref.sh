#!/bin/bash
# prepare_ref.sh REF: gate a given package ref on HPG.
#
#   benchmarks/hpg/prepare_ref.sh master        # or opt/admm, opt/conic, a SHA
#   HPG_TIER=all HPG_AFTER=<build id or none> benchmarks/hpg/submit_ref.sh REF
#
# Builds $ROOT/refs/<sha>/SheafMPC.jl from `git archive REF src Project.toml`
# (the package under test, exactly as committed at REF) and `git archive HEAD
# benchmarks` (the harness at its own commit), records both in PACKAGE_REF and
# HARNESS_REF, copies the generated data and the reference cache, links the
# Mumblebee and CliqueTrees variants next to it, resolves the three Julia
# environments on the login node, and writes exclusive-node jobs whose results
# go to $ROOT/results/<tier>_<sha>_excl.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$(dirname "$HERE")"
ROOT="${HPG_ROOT:-/blue/fairbanksj/itaykadosh/sheafmpc_bench}"
REF="${1:?usage: prepare_ref.sh REF}"
SHA=$(git -C "$PKG" rev-parse --short=10 "$REF")
FULL=$(git -C "$PKG" rev-parse "$REF")
HSHA=$(git -C "$PKG" rev-parse HEAD)
[ -z "$(git -C "$PKG" status --porcelain -- benchmarks/src benchmarks/run.jl benchmarks/summarize.jl benchmarks/hpg)" ] || \
  { echo "commit the harness first (the snapshot takes benchmarks/ at HEAD)"; exit 1; }
TMP=$(mktemp -d)
git -C "$PKG" archive "$REF" src Project.toml | tar -x -C "$TMP"
git -C "$PKG" archive HEAD benchmarks | tar -x -C "$TMP"
echo "$FULL $REF" > "$TMP/PACKAGE_REF"
echo "$HSHA HEAD" > "$TMP/HARNESS_REF"
DEST="$ROOT/refs/$SHA"
ssh hpg "mkdir -p $DEST && ln -sfn $ROOT/Mumblebee.jl $DEST/Mumblebee.jl && ln -sfn $ROOT/CliqueTrees-fast-0015e2b $DEST/CliqueTrees-fast-0015e2b"
rsync -a --delete "$TMP/" "hpg:$DEST/SheafMPC.jl/"
rm -rf "$TMP"
rsync -a "$HERE/data/osqprand" "$HERE/data/reduced" "hpg:$DEST/SheafMPC.jl/benchmarks/data/"
ssh hpg "mkdir -p $DEST/SheafMPC.jl/benchmarks/data/refcache && cp -n $ROOT/SheafMPC.jl/benchmarks/data/refcache/*.jls $DEST/SheafMPC.jl/benchmarks/data/refcache/ 2>/dev/null || true"
ssh hpg "bash -lc 'module load julia/1.12.6; export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot: JULIA_PKG_PRECOMPILE_AUTO=0;
  cd $DEST/SheafMPC.jl/benchmarks && for e in . envs/mumblebee_fast envs/mumblebee_fast_ct; do
    julia --project=\$e -e \"using Pkg; Pkg.resolve(); Pkg.instantiate()\" 2>&1 | tail -1; done'"
HPG_PKGDIR="$DEST/SheafMPC.jl" HPG_EXCLUSIVE=1 HPG_GROUPING=coarse HPG_SUFFIX="_${SHA}_excl" bash "$HERE/hpg/make_jobs.sh"
rsync -a "$HERE/hpg/jobs/" "hpg:$DEST/SheafMPC.jl/benchmarks/hpg/jobs/"
echo "prepared $DEST ($REF = $FULL); submit with: HPG_TIER=all HPG_SUFFIX=_${SHA}_excl HPG_PKGDIR=$DEST/SheafMPC.jl benchmarks/hpg/submit.sh"
