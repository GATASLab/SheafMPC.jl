#!/bin/bash
# hpg_kkt.sh: run a KKT kernel benchmark (or the tests) on HiPerGator.
#
#   sbatch --cpus-per-task=8 --export=ALL,KKT_CMD=bench,BENCH_KKT_SET=fleet+threads,BENCH_N=64+256 bench/hpg_kkt.sh
#
# KKT_CMD: precompile | test | bench (bench/kkt.jl) | e2e (bench/kkt_e2e.jl) | script (KKT_SCRIPT)
# The Julia thread count is the number of allocated cores.
#SBATCH --job-name=kkt
#SBATCH --account=fairbanksj
#SBATCH --qos=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16gb
#SBATCH --time=04:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/kkt_logs/%x_%j.out

set -e
module load julia/1.12.6
export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot:
export SHEAFMPC_PAPER=/blue/fairbanksj/itaykadosh/mpc-sheaf-pushforward
# no OPENBLAS_NUM_THREADS: it caps the pool that BLAS.set_num_threads can use later
cd /blue/fairbanksj/itaykadosh/SheafMPC.jl-kernel
NT=${SLURM_CPUS_PER_TASK:-1}
# sbatch --export splits on commas: lists are passed with + (BENCH_N=64+256)
for v in $(env | grep -o '^BENCH_[A-Z_0-9]*'); do export "$v=${!v//+/,}"; done
echo "host $(hostname) cpus $NT $(lscpu | grep 'Model name')"
uptime
case "${KKT_CMD:-bench}" in
    precompile) julia --project=. -e 'using Pkg; Pkg.precompile()'
                julia --project=bench -e 'using Pkg; Pkg.precompile()' ;;
    test)       julia --project=. -t "$NT" -e 'using Pkg; Pkg.test()' ;;
    bench)      julia --project=bench -t "$NT" bench/kkt.jl ;;
    e2e)        julia --project=bench -t "$NT" bench/kkt_e2e.jl ;;
    script)     julia --project=bench -t "$NT" "$KKT_SCRIPT" ;;
esac
uptime
