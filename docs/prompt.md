Context: sm_lenal is running WaveWatch3 (WW3) on HPC cluster Fahrenheit.
Hardware: AMD EPYC 9005 (Genoa, Zen 4) — confirmed from compiler path:
  /software/sse2/el9_epyc9005/manual/intel/oneapi/2023.1.0/mpi/2021.15/bin/mpiifort
  Default SIMD tier: SSE2 (128-bit). AVX2 and AVX-512 available but NOT enabled by default.
  Run layout: 16 nodes × 60 tasks/node × 2 CPUs/task = 1920 cores.
Compiler: Intel oneAPI 2023.1.0, mpiifort
Domain: Pan-Arctic CARRA2 grid, ~4M sea points.

CRITICAL FLAG RULE: NEVER use -x<ISA> flags (e.g. -xHost, -xCORE-AVX2).
  These embed Intel CPUID dispatch → SSE2 fallback on AMD → catastrophic slowdown.
  Always use -m<isa> flags (-mavx2, -mavx512f) which have NO CPUID check.

Best known result: 367s (p2_fp2_ipo_unroll: fp_fast2 + ipo + unroll-aggressive)
GOAL: 300s  (18.3% further reduction from current best)

Strategy:
  Phase 3A: -mavx2 -mfma  (SSE2→AVX2 upgrade, expected 10-20% → 297-330s)
  Phase 3B: AVX-512 flags  (try _safe variant first; SIGILL risk from SVML-ZMM)
  Phase 3D: PGO (run_phase3_pgo.sh: compile -prof-gen → 1h run → profmerge → compile -prof-use)
  Expected combined: ~240-290s with AVX2 + PGO

NOTE: The local workspace (WW3_compilation/) is a copy of the files that live
on the HPC. Scripts are edited here and then copied to the HPC for execution.
Paths in the scripts refer to HPC paths, not local paths.

Reference model folder (on HPC) to copy each time:
  /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/test_Hamish/

Benchmark framework (on HPC):
  /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/time_Benchmark/

Config for all experiments:
  configs/oneVar_noSaving/

Run command template:
  ./run_exp.sh -e <EXP_NAME> -N 16 -n 60 --cpus-per-task 2 -d 10h

Switch file used by cmake (from the reference model):
  /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/test_Hamish/WW3/model/bin/switch_dnora

Compilation template (run inside <model_folder>/WW3/, removes and recreates build/):
  module purge
  module load buildenv-intel/2023.1.0-hpc1
  module load CMake/3.31.7-hpc1
  module load netCDF-HDF5/4.9.2-1.12.2-hpc1
  export CC=mpiicc
  export FC=mpiifort
  export NETCDF_ROOT=$NETCDF_DIR
  mkdir build && cd build
  cmake .. -DSWITCH=<switch_file> -DCMAKE_INSTALL_PREFIX=install -DCMAKE_BUILD_TYPE=Release
  make -j 24 && make install

File to patch per experiment:
  <model_folder>/WW3/model/src/CMakeLists.txt

Reference Intel flags (from test_Hamish CMakeLists.txt):
  Base flags — compile_flags (applied to ALL build types):
    -no-fma -ip -g -traceback -i4 -real-size 32 -fp-model precise
    -assume byterecl -fno-alias -fno-fnalias
    ( -sox appended automatically by cmake on Linux )
  Release flags — compile_flags_release (added only for Release builds):
    -O3

Phase 1 results (May 8 batch, corrected):
  comp_ref       417s (reference)  ← fp-model precise is the main bottleneck
  comp_fp_fast1  369s (+13.0%)
  comp_fp_fast2  369s (+13.0%)     ← best single-flag change
  comp_O2        407s (+2.5%)
  comp_ipo       408s (+2.2%)
  comp_fma       412s (+1.2%)
  comp_unroll    412s (+1.2%)
  comp_align     413s (+1.0%)
  comp_no_ip     421s (-0.9%)
  comp_xHost     1188s (-65%)      ← DISQUALIFIED (Intel CPUID dispatch, AMD SSE2 fallback)

Phase 2 results (May 8):
  p2_fp2_ipo_unroll 367s (+13.6%, BEST)  — fp_fast2 + ipo + unroll-aggressive
  p2_fp2_ipo        370s (+12.7%)
  p2_fp2_unroll     374s (+11.5%)
  p2_fp2_fma        371s (+12.4%)  — fma redundant with fast=2
  p2_fp1_ipo        370s (+12.7%)  — fast=1 == fast=2 in practice
  p2_fp2_O2         381s (+9.5%)   — O2 HURTS with fp_fast2
  p2_fp2_ipo_xHost  575s (-27%)    ← DISQUALIFIED (ISA mismatch)

Phase 3 results (May 8):
  p3_fp2_ipo_unroll_avx2_nd     355s (+17.4%, NEW BEST)  — AVX2 + no -g/-traceback
  p3_fp2_ipo_unroll_avx2_vecabi 356s (+17.1%)  — AVX2 + vecabi=cmdtarget
  p3_fp2_ipo_unroll_avx2_align  357s (+16.8%)  — AVX2 + align64
  p3_fp2_ipo_unroll_avx2        360s (+15.8%)  — base AVX2
  p3_fp2_ipo_unroll_avx512_safe 373s (+11.8%)  ← AVX-512 SLOWER than AVX2 → abandoned
  (pending) p3_fp2_ipo_unroll_avx2_nd_vecabi   — nd + vecabi combined (~351s expected)

  Streaming HURTS (p2_fp2_streaming=401s), AVX-512 hurts on AMD Zen4: both abandoned.
  ONLY remaining path to 300s: PGO via run_phase3_pgo.sh
  PGO base: p3_fp2_ipo_unroll_avx2_nd flags (355s)
  PGO expected: 5-15% → ~303-337s

Phase 3 experiments: see phase2_experiments.txt (Phase 3 section at bottom)
Phase 3 PGO workflow: run_phase3_pgo.sh --exp-id p3_pgo_avx2_nd

Results compared via:
  column -t -s, benchmark_summary.csv
