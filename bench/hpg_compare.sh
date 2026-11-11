#!/bin/bash
# hpg_compare.sh: the package's own benchmarks (single.jl, rh.jl, reduced.jl)
# on the main branch and on this branch, back to back on one exclusive node.
#   sbatch bench/hpg_compare.sh
#SBATCH --job-name=kkt_cmp
#SBATCH --account=fairbanksj
#SBATCH --qos=fairbanksj-b
#SBATCH --partition=hpg-default
#SBATCH --exclusive
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=48gb
#SBATCH --time=10:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/kkt_logs/%x_%j.out
set -e
module load julia/1.12.6
export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot:
export TEAMMPC_PAPER=${TEAMMPC_PAPER:?set TEAMMPC_PAPER to the paper research code}
B=/blue/fairbanksj/itaykadosh
echo "host $(hostname) $(lscpu | grep 'Model name')"; uptime
for tree in TeamMPC.jl-main TeamMPC.jl-kernel; do
    cd $B/$tree
    echo "===== $tree single"; julia --project=bench bench/single.jl
    echo "===== $tree rh";     julia --project=bench bench/rh.jl
    echo "===== $tree reduced"; julia --project=bench bench/reduced.jl
done
uptime
