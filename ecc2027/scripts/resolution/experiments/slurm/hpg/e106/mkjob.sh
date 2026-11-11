#!/bin/bash
# mkjob.sh NAME ENVSTR TIME
B=/blue/fairbanksj/itaykadosh/e106
T=$B/tree/teammpc-paper
cat > $B/jobs/$1.sbatch <<EOT
#!/bin/bash
#SBATCH --job-name=$1
#SBATCH --mem=64gb --time=$3
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-dev
#SBATCH --exclusive
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --output=$B/logs/%x_%j.log
module load julia/1.12.6
LOCAL=\${TMPDIR:-/tmp}/e106_depot_\$SLURM_JOB_ID; mkdir -p \$LOCAL
export JULIA_DEPOT_PATH=\$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 BENCH_DISC=zoh BENCH_FLEET=dronecar BENCH_INSTANCE=natural E102_EXCLUSIVE=1 E71_FALLBACK=shift E102_ARMS=coord,rt_admm,qs8,team E71_CERT_IN_STEP=1
cd $T
CPU=\$(taskset -pc \$\$ | awk -F": " "{print \\\$2}" | cut -d, -f1 | cut -d- -f1)
export E71_AFFINITY="core \$CPU of \$(taskset -pc \$\$ | awk -F": " "{print \\\$2}")"
echo "host \$(hostname); \$E71_AFFINITY; load \$(cat /proc/loadavg)"
julia --startup-file=no --project=env -e "using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println(\"precompiled\")"
ok=1
$2 taskset -c \$CPU julia --startup-file=no -t 1 --project=env scripts/resolution/experiments/e102_irregular4096.jl || ok=0
[ \$ok = 1 ] && touch $B/done/$1
touch $B/finished/$1
exit \$((1-ok))
EOT
