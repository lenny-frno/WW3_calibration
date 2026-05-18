# Recipe: Compiler Benchmarking

Compile WW3 with different Intel Fortran flag combinations and compare throughput to find the fastest binary. Covers Phases 1–4 of the flag-search strategy on Fahrenheit (AMD EPYC 9005 / Zen 4).

## Hardware context

| Property | Value |
|----------|-------|
| Cluster | Fahrenheit (NSC) |
| Node | AMD EPYC 9005 (Genoa, Zen 4), 144 physical cores |
| Default SIMD tier | SSE2 (128-bit) from `sse2/el9_epyc9005` stack |
| Best SIMD target | `-mavx2 -mfma` (256-bit) — **NEVER use `-xHost`** (Intel CPUID dispatch → SSE2 fallback on AMD) |
| Compiler | Intel oneAPI 2023.1.0 (`mpiifort`) |

## Best known results

| Exp | Elapsed (10 h sim) | Flags summary |
|-----|--------------------|---------------|
| `comp_ref` | 417 s | `-O3 -fp-model precise` |
| `p2_fp2_ipo_unroll` | 367 s | `-fp-model fast=2 -ipo -unroll-aggressive` |
| `p3_fp2_ipo_unroll_avx2_nd` | 355 s | `+ -mavx2` |
| `p3_pgo_avx2_nd` (69 t/n) | **324 s** | `+ PGO` |
| `p4_omph_varB_n60` | **290 s** | `+ OMPH/OMPG + OMP_NUM_THREADS=2` |

## Phase overview

```
Phase 1: single-flag ablation  (benchmarking/run_flag_experiments.sh)
Phase 2: multi-flag combos     (benchmarking/run_phase2_experiments.sh)
Phase 3: AVX2 + PGO            (benchmarking/run_phase3_pgo.sh)
Phase 4: DTXY / MPI pinning / OMPH  (benchmarking/run_phase4_*.sh)
```

## Step 1 — Build reference binary

```bash
# From the WW3 source root (e.g. test_Hamish/WW3):
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/test_Hamish/WW3

# Default build (reference flags in CMakeLists.txt):
bash cmake/cmake_build_intel.sh   # or your build script
```

## Step 2 — Run Phase 1 single-flag ablation

Each experiment compiles WW3 with one changed flag, runs 10 h sim, logs throughput.

```bash
cd /home/lehuc2580/work/WW3/WW3_compilation/benchmarking

# Dry-run to preview all experiments:
bash run_flag_experiments.sh --dry-run

# Submit all Phase 1 flags:
bash run_flag_experiments.sh
```

Results land in `benchmark_summary.csv`. Each line is one compile+run combo.

## Step 3 — Run Phase 2 multi-flag combos

Edit `phase2_experiments.txt` to define flag combinations (Format A = additive; Format B = full replacement), then:

```bash
bash run_phase2_experiments.sh -i phase2_experiments.txt --dry-run
bash run_phase2_experiments.sh -i phase2_experiments.txt
```

Best from Phase 2: `p2_fp2_ipo_unroll` (367 s, +13.6 % vs ref).

## Step 4 — Phase 3: AVX2 vectorisation + PGO

```bash
# Step 3A: compile with AVX2 + best Phase 2 flags
bash run_phase3_pgo.sh --step 1 --exp-id p3_avx2

# Step 3B: profile-guided optimisation (PGO)
#   1. Compile instrumented binary:
bash run_phase3_pgo.sh --step 2 --exp-id p3_pgo_avx2_nd

#   2. Run profile collection (1h sim, sets INTEL_PROF_DUMP_CUMULATIVE=1):
bash run_phase3_pgo.sh --step 3 --exp-id p3_pgo_avx2_nd

#   3. Compile PGO-optimised binary with profiling data:
bash run_phase3_pgo.sh --step 4 --exp-id p3_pgo_avx2_nd

#   4. Benchmark:
bash run_phase3_pgo.sh --step 5 --exp-id p3_pgo_avx2_nd
```

Best from Phase 3: `p3_pgo_avx2_nd` 324 s @ 69 tasks/node (+30 % vs ref).

## Step 5 — Phase 4: hybrid parallelism (OMPH + OMPG)

```bash
# Compile with OpenMP (adds OMPH + OMPG to switch file, -qopenmp to flags):
bash run_phase4_omph.sh --step 1 --exp-id p4_omph

# Benchmark Variant B (cpus=2, async MPI off, OMP_THREADS=2) — best so far:
bash run_phase4_omph.sh --step 3 --exp-id p4_omph
```

> Variant B (290 s) outperforms Variant A (cpus=3) because the third CPU is wasted on the async-progress thread while OMP parallelism is more valuable on Zen 4.

## Step 6 — Compare results

```bash
# Top 10 by throughput:
sort -t ',' -k15 -rn benchmark_summary.csv | \
  awk -F',' 'NR<=11 {printf "%-35s %7s s  %6s days/h\n", $1, $13, $15}'

# Plot (requires python + matplotlib):
python3 - << 'EOF'
import pandas as pd, matplotlib.pyplot as plt
df = pd.read_csv('benchmark_summary.csv', comment='#')
df = df[df.status == 'SUCCESS'].dropna(subset=['throughput_days_per_hour'])
df = df.sort_values('throughput_days_per_hour', ascending=False).head(20)
df.plot.barh(x='exp_name', y='throughput_days_per_hour', legend=False)
plt.xlabel('Throughput (sim days / wall hour)')
plt.tight_layout()
plt.savefig('benchmark_top20.png', dpi=150)
print('saved benchmark_top20.png')
EOF
```

## Step 7 — Rerun performance logging for an existing job

If a run completed but `benchmark_summary.csv` is missing the entry (e.g. sacct was unavailable):

```bash
./scripts/log_performance.sh -e <exp_name> -j <slurm_job_id>
```

## Critical flag rules for AMD EPYC / Zen 4

```
ALWAYS:   -mavx2 -mfma        (256-bit SIMD, recognised by AMD)
NEVER:    -xHost -xCORE-AVX2  (Intel CPUID dispatch → falls back to SSE2 on AMD)

Key flag effects (from Phase 1 results):
  -fp-model fast=2   +13 %    (most impactful single flag)
  -ipo               +2 %     (link-time inter-procedural optimisation)
  -unroll-aggressive +1 %
  -mavx2             +3 %     (over fp_fast2 + ipo baseline)
  PGO               +10 %     (hot-path branch + inlining decisions)
  OMPH+OMPG          +8 %     (OMP inner loops, 2 threads per rank)
```

## Experiment naming convention

```
<phase>_<flags_summary>[_n<tasks_per_node>]
e.g.  p3_fp2_ipo_unroll_avx2_nd   — Phase 3, fp fast=2, ipo, unroll, AVX2, no debug
      p4_omph_varB_n60             — Phase 4, OMPH variant B at 60 tasks/node
```
