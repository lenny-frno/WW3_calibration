# WW3 Benchmarking Suite

Compiler-flag and runtime optimisation experiments for WaveWatch III on the
Fahrenheit HPC cluster (AMD EPYC 9005, Intel oneAPI MPI).

---

## Overview

The benchmarking suite is organised into four phases that were run in sequence:

| Phase | Script | Goal |
|-------|--------|------|
| 1 — Flag ablation | `run_flag_experiments.sh` | Measure individual compiler-flag impact |
| 2 — Flag combinations | `run_phase2_experiments.sh` | Find synergistic multi-flag combos |
| 3 — AVX2 + PGO | `run_phase3_pgo.sh` | Profile-guided optimisation with AVX2 |
| 4a — MPI pinning | `run_phase4_mpi_pinning.sh` | CPU affinity strategies |
| 4b — dt_xy tuning | `run_phase4_dtxy.sh` | Propagation timestep study |
| 4c — OpenMP hybrid | `run_phase4_omph.sh` | MPI+OpenMP thread configurations |

Results land in `../benchmark_summary.csv` (schema v2.3) and are read with:
```bash
column -t -s, ../benchmark_summary.csv | less -S
```

---

## Quick Start

All scripts derive `BENCH_DIR` automatically (workspace root = parent of this
directory). The only user-specific section is the **`USER CONFIGURATION`** block
near the top of each script, which you must update before first use:

| Variable | Meaning |
|----------|---------|
| `MODELS_ROOT` | Where your compiled WW3 copies live |
| `REFERENCE_MODEL` | Path to the "golden" WW3 build used as baseline |
| `SWITCH_FILE` | WW3 `switch_*` file from the reference model |
| `CONFIG_DIR` | `configs/<name>/` directory with namelists to use |

Example:
```bash
# Dry-run to check what would happen
./run_flag_experiments.sh --dry-run

# Run for real
./run_flag_experiments.sh
```

For Phase 2, edit `phase2_experiments.txt` first, then:
```bash
./run_phase2_experiments.sh --dry-run
./run_phase2_experiments.sh
# or run only specific experiments:
./run_phase2_experiments.sh --only p2_fp2_ipo_unroll
```

---

## Key Findings

Best result so far: **p3_pgo_avx2_nd** at 16 nodes × 69 tasks × 2 CPUs/task → **324 s** (4.63 sim_days/h over 10 h sim).

Highlights:
- Phase 1: `-fp-model fast=2` and `-unroll-aggressive` each give ~1 % speedup; `-xHost` hurts on AMD (SSE2 fallback → ×3.2 slowdown).
- Phase 2: Combined `fp-fast2 + ipo + unroll` → 367 s (best pre-PGO).
- Phase 3: AVX2 `-mavx2 -mfma` + no-debug → 355 s; PGO on top → **324 s**.
- Phase 4: OpenMP hybrid varB (60 tasks × 2 threads, async I/O off) hit **290 s** — best overall.

See `phase4_knowledge.md` for detailed analysis and next steps.

---

## Files

| File | Description |
|------|-------------|
| `run_flag_experiments.sh` | Phase 1: single-flag ablation |
| `run_phase2_experiments.sh` | Phase 2: combination search (reads `phase2_experiments.txt`) |
| `run_phase3_pgo.sh` | Phase 3: PGO profiling + optimised build pipeline |
| `run_phase4_dtxy.sh` | Phase 4: propagation timestep variations |
| `run_phase4_mpi_pinning.sh` | Phase 4: MPI process-to-core affinity |
| `run_phase4_omph.sh` | Phase 4: OpenMP hybrid thread configurations |
| `phase2_experiments.txt` | Editable experiment definitions for Phase 2 |
| `phase4_knowledge.md` | Detailed notes on runtime optimisation findings |
