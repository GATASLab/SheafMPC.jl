#!/bin/bash
# E106 (Table I): E102 on exclusive nodes with one overrun rule for every arm, one seed per array task.
#
# Every arm but the converged centralized reference applies, on a step over the 200 ms period, its previous
# plan shifted by one sample (E71_FALLBACK=shift), and a team arm's step includes the certificate eta
# (E71_CERT_IN_STEP=1). Team counts are fractions of the q=8 count, floored at the number of classes: teams must
# refine the classes, so no fraction can give fewer teams than classes, and the floor arm is one team per class
# (339 teams at 4096 vehicles, 84 at 1024). Smaller fractions (0.2, 0.15) would only repeat that arm.
# The paper's runs used hpg-dev (exclusive AMD EPYC 75F3 nodes); this script is the hpg-default equivalent.
#
#   sbatch scripts/resolution/experiments/e102_exclusive.sbatch            (E102_N=1024 for the other column)
#   E102_MODE=merge E102_PARTDIR=<parts> E102_OUT=results/e106_overrun.json \
#     julia --project=env scripts/resolution/experiments/e102_irregular4096.jl
#
#SBATCH -A fairbanksj
#SBATCH -p hpg-default
#SBATCH --exclusive
#SBATCH -c 4
#SBATCH --mem=64G
#SBATCH -t 6:00:00
#SBATCH --array=1-5
#SBATCH -J e106x
#SBATCH -o slurm-e106x-%A_%a.out

set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"
mkdir -p bench/irregular/results/parts102x

export JULIA_CPU_TARGET=x86-64-v3
export E102_N=${E102_N:-4096}
export E102_SEEDS="${SLURM_ARRAY_TASK_ID}"
export E102_FRACS="1,0.35,0.25" E102_ARMS="coord,rt_admm,qs8,team" E71_FALLBACK=shift E71_CERT_IN_STEP=1
export E102_PARTDIR="${SLURM_SUBMIT_DIR}/bench/irregular/results/parts102x"
export E71_AFFINITY="exclusive node, arms pinned to core 0"

in-sandbox bash -lc "source /etc/profile.d/modules.sh && module load julia/1.12.6 && \
  taskset -c 0 julia --startup-file=no --project=env \
  scripts/resolution/experiments/e102_irregular4096.jl"
