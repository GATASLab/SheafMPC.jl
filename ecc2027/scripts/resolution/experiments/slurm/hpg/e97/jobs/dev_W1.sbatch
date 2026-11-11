#!/bin/bash
#SBATCH --job-name=dev_W1
#SBATCH --mem=0 --time=11:00:00
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8
#SBATCH --output=/blue/fairbanksj/itaykadosh/e97/logs/%x_%j.log
cd /blue/fairbanksj/itaykadosh/e97/tree/teammpc-paper
CPUS=$(taskset -pc $$ | awk -F": " '{print $2}')
C1=$(python3 -c "import os;print(sorted(os.sched_getaffinity(0))[0])")
C4=$(python3 -c "import os;c=sorted(os.sched_getaffinity(0));print(','.join(map(str,c[:4])))")
stamp() { echo "[$1] host $(hostname); cpus $CPUS; load $(cat /proc/loadavg); $(date +%T)"; }
lscpu | grep "Model name"; stamp start
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e97_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar
julia --startup-file=no --project=env -e "using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, OSQP, JSON; println(\"precompiled\")"
ok=1
stamp julia_t1
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 E97_VARIANTS=W1 E97_N=1024 E97_CONES=box,soc E97_DIR=/blue/fairbanksj/itaykadosh/e97/parts_dev taskset -c $C1 julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e97_baselines.jl || ok=0
stamp julia_t4
JULIA_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 E97_VARIANTS=W1 E97_N=1024 E97_CONES=box,soc E97_THREADS=4 E97_ARMS=sm_fine_full,sm_cond_full,sm_fine_team,sm_cond_team E97_DIR=/blue/fairbanksj/itaykadosh/e97/parts_dev taskset -c $C4 julia --startup-file=no -t 4 --project=env scripts/resolution/experiments/e97_baselines.jl || ok=0
module purge; module load python/3.11
export ACADOS_SOURCE_DIR=/blue/fairbanksj/itaykadosh/central_bench/acados LD_LIBRARY_PATH=/blue/fairbanksj/itaykadosh/central_bench/acados/lib:/apps/gcc/12.2.0/lib64:$LD_LIBRARY_PATH XDG_CACHE_HOME=/blue/fairbanksj/itaykadosh/central_bench/cache MPLCONFIGDIR=/blue/fairbanksj/itaykadosh/central_bench/cache/mpl
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BENCH_BUILD=$TMPDIR/e97_build
IN=/blue/fairbanksj/itaykadosh/e97/parts_dev/e55_input_e97_W1_N1024.json
stamp hpipm_team
BENCH_IN=$IN BENCH_PROGRAM=team BENCH_B=1 BENCH_STEPS=0:2 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_dev taskset -c $C1 /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py || ok=0
stamp hpipm_stacked
BENCH_IN=$IN BENCH_PROGRAM=stacked BENCH_B=2 BENCH_STEPS=0:0 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_dev taskset -c $C1 /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py || ok=0
stamp end
[ $ok = 1 ] && touch /blue/fairbanksj/itaykadosh/e97/done/dev_W1
touch /blue/fairbanksj/itaykadosh/e97/finished/dev_W1
exit $((1-ok))
