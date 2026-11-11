#!/bin/bash
# mk97w.sh VARIANT ARMS CONES : 31 steps (30 warm), one exclusive hpg-dev node, one pinned core
B=/blue/fairbanksj/itaykadosh/e97; v=$1; P=$B/parts_prof; mkdir -p $P
cat > $B/jobs/prof_$v.sbatch <<EOT
#!/bin/bash
#SBATCH --job-name=e97p_$v
#SBATCH --mem=64gb --time=4:00:00
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --output=$B/logs/%x_%j.log
cd $B/tree_prof/teammpc-paper
module load julia/1.12.6
LOCAL=\${TMPDIR:-/tmp}/e97_depot_\$SLURM_JOB_ID; mkdir -p \$LOCAL
export JULIA_DEPOT_PATH=\$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
C1=\$(python3 -c "import os;print(sorted(os.sched_getaffinity(0))[0])")
lscpu | grep "Model name"; echo "host \$(hostname) core \$C1 load \$(cat /proc/loadavg)"
julia --startup-file=no --project=env -e "using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, OSQP, JSON; println(\"precompiled\")"
ok=1
E97_VARIANTS=$v E97_N=1024 E97_STEPS=11 E97_CONES=$3 E97_ARMS=$2 E97_DIR=$P taskset -c \$C1 julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e97_baselines.jl || ok=0
[ \$ok = 1 ] && touch $B/done/prof_$v
touch $B/finished/prof_$v
exit \$((1-ok))
EOT
echo $B/jobs/prof_$v.sbatch
