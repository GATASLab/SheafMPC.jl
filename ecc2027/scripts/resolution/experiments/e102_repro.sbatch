#!/bin/bash
# Reproduce the committed E102 (results/e102_irregular4096.json) before changing it.
#
# Same settings as the committed run: E102's defaults (arms coord, rt_admm and
# team at 1, 1/2, 0.35 and 1/4 of the q=8 count; no overrun rule; certificate
# not counted in the step), 30 steps, one pinned core of a shared node. Only
# what is deterministic is compared exactly: vehicles, edges, classes, teams
# per arm, and the closed-loop cost of the converged and team arms. The
# early-stopped arm stops at a wall-clock budget, so its cost depends on the node.
#
# HiPerGator sandbox notes: every path is under the checkout on /blue; Julia runs
# with --pkgimages=no, because the linker crashes (SIGBUS) writing package
# images into the depot on /blue; step 0 is untimed, so compiling on first use
# does not enter the timings.
#
#   E102_N=1024 sbatch --array=1-5 scripts/resolution/experiments/e102_repro.sbatch
#   E102_N=4096 sbatch --array=1-5 --mem=64G -t 6:00:00 scripts/resolution/experiments/e102_repro.sbatch
#
#SBATCH -A fairbanksj
#SBATCH -p hpg-default
#SBATCH -c 2
#SBATCH --mem=16G
#SBATCH -t 3:00:00
#SBATCH -J e102repro
#SBATCH -o slurm-e102repro-%A_%a.out

set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"
export JULIA_CPU_TARGET=x86-64-v3
export E102_N=${E102_N:-1024}
export E102_SEEDS="${SLURM_ARRAY_TASK_ID}"
export E102_PARTDIR="${SLURM_SUBMIT_DIR}/results/parts102_repro"
export E71_AFFINITY="shared node, pinned to the first allocated core (reproduction)"
mkdir -p "${E102_PARTDIR}"

CORE=$(taskset -cp $$ | sed 's/.*: //; s/[,-].*//')
in-sandbox bash -lc "source /etc/profile.d/modules.sh && module load julia/1.12.6 && \
  taskset -c ${CORE} julia --startup-file=no --pkgimages=no --project=env \
  scripts/resolution/experiments/e102_irregular4096.jl"
