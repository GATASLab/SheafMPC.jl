#!/bin/bash
#SBATCH --job-name=e63_canary
#SBATCH --mem=32gb --time=3:00:00
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=2
#SBATCH --output=/blue/fairbanksj/itaykadosh/e63/logs/%x_%j.log
export BENCH_DISC=zoh BENCH_FLEET=dronecar
module load julia/1.12.6
LOCAL=${TMPDIR:-/tmp}/e63_depot_$SLURM_JOB_ID; mkdir -p $LOCAL
export JULIA_DEPOT_PATH=$LOCAL:/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
cd /blue/fairbanksj/itaykadosh/e63/tree/teammpc-paper
echo "host $(hostname); load $(cat /proc/loadavg)"
julia --startup-file=no --project=env -e 'using Pkg; Pkg.precompile(); using TeamMPC, Clarabel, JSON; println("precompiled")'

EX=scripts/resolution/experiments
R=/blue/fairbanksj/itaykadosh/e63
set -o pipefail
ok=1
BENCH_INSTANCE=natural E63_N=256 E63_SEEDS=1 E63_STEPS=4 E63_PARTDIR=$R/canary julia --startup-file=no -t 1 --project=env $EX/e63_gap.jl || ok=0
BENCH_INSTANCE=natural E63_CONE=box E63_N=256 E63_SEEDS=1 E63_STEPS=4 E63_PARTDIR=$R/canary julia --startup-file=no -t 1 --project=env $EX/e63_gap.jl || ok=0
BENCH_INSTANCE=squads E63_N=256 E63_SEEDS=1 E63_STEPS=6 E63_PATHS=team,orbits,coord,lifted,replay,diag,admm E63_PARTDIR=$R/canary julia --startup-file=no -t 1 --project=env $EX/e63_time.jl || ok=0
BENCH_INSTANCE=natural E63_TEAMS=geo8 E63_N=1024 E63_SEEDS=1 E63_STEPS=6 E63_PATHS=team,coord E63_PARTDIR=$R/canary julia --startup-file=no -t 1 --project=env $EX/e63_time.jl || ok=0
BENCH_INSTANCE=squads E63_N=256 julia --startup-file=no -t 1 --project=env -e '
include("scripts/resolution/experiments/e63_time.jl")
BLAS.set_num_threads(1)
inst = sq_instance(256, 1); lab, _ = sq_teams(inst, "aep", 1)
sc = scenario63(inst, 1, lab); Q = Quot51(sc, lab)
for m in ("full", "quot"); r, _ = tune52(m, sc, Q); println("RHO ", m, " ", r); end' || ok=0
[ $ok = 1 ] && touch $R/done_canary
touch $R/finished_canary
