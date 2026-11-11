#!/bin/bash
#SBATCH --job-name=can_py
#SBATCH --mem=16gb --time=0:40:00
#SBATCH --account=fairbanksj
#SBATCH --nodes=1 --ntasks=1
#SBATCH --partition=hpg-default --constraint=rome --cpus-per-task=2
#SBATCH --output=/blue/fairbanksj/itaykadosh/e97/logs/%x_%j.log
module purge; module load python/3.11
export ACADOS_SOURCE_DIR=/blue/fairbanksj/itaykadosh/central_bench/acados LD_LIBRARY_PATH=/blue/fairbanksj/itaykadosh/central_bench/acados/lib:/apps/gcc/12.2.0/lib64:$LD_LIBRARY_PATH XDG_CACHE_HOME=/blue/fairbanksj/itaykadosh/central_bench/cache MPLCONFIGDIR=/blue/fairbanksj/itaykadosh/central_bench/cache/mpl
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BENCH_BUILD=$TMPDIR/e97_build
cd /blue/fairbanksj/itaykadosh/e97/tree/teammpc-paper
echo "host $(hostname); cpus $(nproc); load $(cat /proc/loadavg)"; lscpu | grep "Model name"
ok=1
 BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_C1_N64.json BENCH_PROGRAM=stacked BENCH_B=2 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_C1_N64.json BENCH_PROGRAM=team BENCH_B=1 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_E1t_N64.json BENCH_PROGRAM=stacked BENCH_B=2 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_E1t_N64.json BENCH_PROGRAM=team BENCH_B=1 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_W1_N64.json BENCH_PROGRAM=stacked BENCH_B=2 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_W1_N64.json BENCH_PROGRAM=team BENCH_B=1 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_Ccyl_N64.json BENCH_PROGRAM=stacked BENCH_B=2 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && BENCH_IN=/blue/fairbanksj/itaykadosh/e97/parts_canary/e55_input_e97_Ccyl_N64.json BENCH_PROGRAM=team BENCH_B=1 BENCH_STEPS=0:1 BENCH_OUT_DIR=/blue/fairbanksj/itaykadosh/e97/parts_canary /blue/fairbanksj/itaykadosh/central_bench/venv/bin/python env/e55_hpipm_dc.py && true || ok=0
echo "load end $(cat /proc/loadavg)"
[ $ok = 1 ] && touch /blue/fairbanksj/itaykadosh/e97/done/can_py
touch /blue/fairbanksj/itaykadosh/e97/finished/can_py
exit $((1-ok))
