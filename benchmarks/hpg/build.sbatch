#!/bin/bash
# build.sbatch: build PIQP (C interface, -march=native on the benchmark node type)
# with Eigen and BLASFEO, and precompile both Julia environments. HPIPM is the
# acados build in central_bench (HPIPM_TARGET=AVX2, BLASFEO X64_AUTOMATIC).
#SBATCH --job-name=smb_build
#SBATCH --account=fairbanksj
#SBATCH --partition=hpg-default
#SBATCH --constraint=rome
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8 --mem=24gb --time=02:00:00
#SBATCH --output=/blue/fairbanksj/itaykadosh/sheafmpc_bench/logs/%x_%j.log
set -euo pipefail
ROOT=/blue/fairbanksj/itaykadosh/sheafmpc_bench
module load cmake/3.26.4 gcc/12.2.0 julia/1.12.6
T=$ROOT/tools
lscpu | grep "Model name"
if [ ! -f $T/piqp-install/lib/libpiqpc.so ]; then
  mkdir -p $T/build/eigen $T/build/blasfeo $T/build/piqp
  (cd $T/build/eigen && cmake $T/eigen-3.4.0 -DCMAKE_INSTALL_PREFIX=$T/eigen-install -DBUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF >/dev/null && cmake --install . >/dev/null)
  (cd $T/build/blasfeo && cmake $T/blasfeo-src -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DTARGET=X64_INTEL_HASWELL \
      -DBLAS_API=OFF -DBLASFEO_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=$T/blasfeo-install >/dev/null && make -j8 >/dev/null && cmake --install . >/dev/null)
  (cd $T/build/piqp && cmake $T/piqp-src -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="-O3 -march=native -DNDEBUG" \
      -DCMAKE_PREFIX_PATH="$T/eigen-install;$T/blasfeo-install" -DCMAKE_INSTALL_PREFIX=$T/piqp-install -DBUILD_C_INTERFACE=ON \
      -DBUILD_SHARED_LIBS=ON -DBUILD_WITH_TEMPLATE_INSTANTIATION=OFF -DBUILD_WITH_BLASFEO=ON -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF \
      -DBUILD_BENCHMARKS=OFF -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--exclude-libs,ALL" >/dev/null && make -j8 >/dev/null && cmake --install . >/dev/null)
  printf "PIQP %s built on %s (%s), gcc %s, -O3 -march=native, BLASFEO X64_INTEL_HASWELL static, Eigen 3.4.0, job %s\n" \
    "$(git -C $T/piqp-src rev-parse HEAD 2>/dev/null || echo v0.6.4)" "$(hostname)" "$(lscpu | grep 'Model name' | sed 's/.*: *//')" \
    "$(gcc -dumpfullversion)" "$SLURM_JOB_ID" > $T/piqp-install/BUILD_INFO
fi
export JULIA_DEPOT_PATH=/blue/fairbanksj/itaykadosh/julia_depot: JULIA_NUM_THREADS=1
cd $ROOT/SheafMPC.jl/benchmarks
julia --project=. -e 'using Pkg; Pkg.precompile()'
julia --project=envs/mumblebee_fast -e 'using Pkg; Pkg.precompile()'
export HPIPM_LIB_DIR=/blue/fairbanksj/itaykadosh/central_bench/acados/lib PIQP_LIB=$T/piqp-install/lib/libpiqpc.so
export SHEAFMPC_PAPER=/blue/fairbanksj/itaykadosh/pushforward_bench/mpc-sheaf-pushforward
julia --project=. test/test_families.jl
HPIPM_TEST_HARNESS=1 julia --project=. test/test_hpipm.jl
julia --project=. test/test_piqp.jl
echo "build done $(date -Is)"
