#!/bin/bash
# make_data.sh: generate the problem data that is not built in Julia at run time.
#   osqprand: OSQP's random MPC model data (numpy + scipy; PYTHON, default ~/tools/bench-venv/bin/python)
#   reduced:  the paper's pushed-forward grid fleet (the paper repository's scripts environment; PAPER)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-$HOME/tools/bench-venv/bin/python}"
PAPER="${TEAMMPC_PAPER:?set TEAMMPC_PAPER to the paper research code}"
[ -d "$HERE/data/osqprand" ] || "$PY" -I "$HERE/gen/osqp_random.py" "$HERE/data/osqprand" 10,20,40,80,160 1,2,3
[ -d "$HERE/data/reduced" ] || julia --project="$PAPER/scripts" "$HERE/gen/reduced_export.jl" "$HERE/data/reduced" 8 8 10 12 0,2,4,8
