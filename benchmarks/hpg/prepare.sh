#!/bin/bash
# prepare.sh (run locally): copy the harness, the package, the second Mumblebee
# variant, PIQP's sources and the generated data to HPG, instantiate the Julia
# environments on the login node (internet; precompilation is left to the build
# job), and write the job scripts. Then hpg/submit.sh submits them.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"      # benchmarks/
PKG="$(dirname "$HERE")"
ROOT="${HPG_ROOT:-/blue/fairbanksj/itaykadosh/sheafmpc_bench}"
MB="${MUMBLEBEE_DIR:-$HOME/Projects/GATAS/Mumblebee.jl}"
ssh hpg "mkdir -p $ROOT/tools $ROOT/logs $ROOT/results"
rsync -a --delete --exclude 'benchmarks/results/' --exclude 'bench/results/' "$PKG/" "hpg:$ROOT/SheafMPC.jl/"
rsync -a --delete "$MB/" "hpg:$ROOT/Mumblebee.jl/"
for t in eigen-3.4.0 blasfeo-src piqp-src; do rsync -a --delete "$HOME/tools/$t/" "hpg:$ROOT/tools/$t/"; done
ssh hpg "bash -lc 'module load julia/1.12.6; export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot: JULIA_PKG_PRECOMPILE_AUTO=0;
  cd $ROOT/SheafMPC.jl/benchmarks && julia --project=. -e \"using Pkg; Pkg.instantiate()\" &&
  julia --project=envs/mumblebee_fast -e \"using Pkg; Pkg.instantiate()\" && echo instantiated'"
bash "$HERE/hpg/make_jobs.sh"
rsync -a "$HERE/hpg/jobs/" "hpg:$ROOT/SheafMPC.jl/benchmarks/hpg/jobs/"
echo "prepared $ROOT; submit with benchmarks/run.sh hpg-submit"
