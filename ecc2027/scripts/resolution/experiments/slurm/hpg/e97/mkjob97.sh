#!/bin/bash
# mkjob97.sh NAME KIND(jl|py) ENVSTR TIME MEM EXTRA_SBATCH THREADS PYARGS
B=/blue/fairbanksj/itaykadosh/e97
NAME=$1; KIND=$2; ENVSTR=$3; TIME=$4; MEM=$5; EXTRA=$6; TH=${7:-1}
if [ "$KIND" = jl ]; then
RUN="julia --startup-file=no --project=env -e \"using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, OSQP, JSON; println(\\\"precompiled\\\")\"
$ENVSTR julia --startup-file=no -t $TH --project=env scripts/resolution/experiments/e97_baselines.jl || ok=0"
PRE="module load julia/1.12.6
LOCAL=\${TMPDIR:-/tmp}/e97_depot_\$SLURM_JOB_ID; mkdir -p \$LOCAL
export JULIA_DEPOT_PATH=\$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=$TH OPENBLAS_NUM_THREADS=$TH JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar"
else
PRE="module purge; module load python/3.11
export ACADOS_SOURCE_DIR=/blue/fairbanksj/itaykadosh/central_bench/acados LD_LIBRARY_PATH=/blue/fairbanksj/itaykadosh/central_bench/acados/lib:/apps/gcc/12.2.0/lib64:\$LD_LIBRARY_PATH XDG_CACHE_HOME=/blue/fairbanksj/itaykadosh/central_bench/cache MPLCONFIGDIR=/blue/fairbanksj/itaykadosh/central_bench/cache/mpl
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 BENCH_BUILD=\$TMPDIR/e97_build"
RUN="$ENVSTR || ok=0"
fi
cat > $B/jobs/$NAME.sbatch <<EOT
#!/bin/bash
#SBATCH --job-name=$NAME
#SBATCH --mem=$MEM --time=$TIME
#SBATCH --account=fairbanksj
#SBATCH --nodes=1 --ntasks=1
#SBATCH $EXTRA
#SBATCH --output=$B/logs/%x_%j.log
$PRE
cd $B/tree/teammpc-paper
echo "host \$(hostname); cpus \$(nproc); load \$(cat /proc/loadavg)"; lscpu | grep "Model name"
ok=1
$RUN
echo "load end \$(cat /proc/loadavg)"
[ \$ok = 1 ] && touch $B/done/$NAME
touch $B/finished/$NAME
exit \$((1-ok))
EOT
echo $B/jobs/$NAME.sbatch
