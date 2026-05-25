# WW3 Benchmark & Calibration Framework
 
A structured environment for running, comparing, and logging WW3 experiments
across different model configurations, compiler settings, and HPC parameters.
Also includes a compiler benchmarking suite (Phases 1–4) for optimising WW3
on AMD EPYC 9005 (Genoa/Zen 4) via Intel oneAPI.

Framework version: **2.3** | Cluster: **Fahrenheit** (Intel oneAPI MPI) | MPI launcher: `mpprun`
---

## Directory Structure

```
WW3_compilation/
├── scripts/
│   ├── setup.sh              # Step 1 — initialise a new experiment
│   ├── run_exp.sh            # Step 2 — submit jobs and chain dependencies
│   ├── check_exp.sh          # Diagnose a single experiment in detail
│   ├── scan_experiments.sh   # Batch dashboard + interactive cleanup for all experiments
│   ├── migrate_groups.sh     # Reorganise flat experiments/ into group subdirectories
│   └── log_performance.sh    # Post-run metrics collection
├── jobs/
│   ├── run_shel.job          # WW3 MPI job (called by run_exp.sh)
│   ├── prep.job              # Preprocessing: ww3_grid + ww3_prnc
│   └── post.job              # Postprocessing: ww3_ounf (opt-in via --post)
├── benchmarking/             # Compiler & runtime optimisation study (Phases 1–4)
│   ├── README.md
│   ├── run_flag_experiments.sh      # Phase 1: single-flag ablation
│   ├── run_phase2_experiments.sh    # Phase 2: flag combinations
│   ├── run_phase3_pgo.sh            # Phase 3: AVX2 + PGO
│   ├── run_phase4_dtxy.sh           # Phase 4: propagation timestep
│   ├── run_phase4_mpi_pinning.sh    # Phase 4: MPI process affinity
│   ├── run_phase4_omph.sh           # Phase 4: MPI+OpenMP hybrid
│   ├── phase2_experiments.txt       # Experiment definitions for Phase 2
│   └── phase4_knowledge.md          # Runtime optimisation notes
├── configs/                  # Namelist configs + config manager
│   ├── manage_config.sh
│   ├── REGISTRY.md / REGISTRY_SUMMARY.md
│   ├── nml_files_template/
│   └── CARRA2_exp_1/         # Baseline config (tracked in git)
├── docs/
│   └── prompt.md             # Context document for AI-assisted work
├── benchmark_summary.csv     # Auto-generated master results table (schema v2.3)
└── README.md
 
└── experiments/              # gitignored — created at runtime by setup.sh
    ├── <exp_name>/               # Flat layout (default)
    │   ├── exp_config.sh
    │   ├── work/
    │   ├── logs/
    │   └── metadata/
    └── <group>/                  # Grouped layout (run_calibration.sh --use-groups or setup.sh --exp-group)
        └── <exp_name>/
            ├── exp_config.sh
            ├── work/
            ├── logs/
            └── metadata/
```
---
## Motivation

This framework was developed to standardize and automate WW3 benchmark experiments on HPC systems. It ensures reproducibility across:

- compiler configurations
- physics parameterizations
- grid setups
- computational scaling studies

---

## Compiler Benchmarking Suite

The `benchmarking/` directory contains a systematic study of Intel oneAPI compiler
flags and runtime parameters on AMD EPYC 9005 (Zen 4). See
[benchmarking/README.md](benchmarking/README.md) for full details.

Best result: **290 s** (Phase 4, OpenMP hybrid varB: 60 tasks × 2 threads, async I/O off)
vs reference **417 s** — a **30 % speedup**.

```bash
# Dry-run the Phase 1 flag ablation
./benchmarking/run_flag_experiments.sh --dry-run

# Run Phase 2 (edit phase2_experiments.txt first)
./benchmarking/run_phase2_experiments.sh
```

---

## Quickstart

### 1. Initialise a new experiment
 
```bash
./scripts/setup.sh \
    -e CARRA2_ref_oneVar \
    -w /home/sm_lenal/programs/compiling/from_waveXtrems/WW3 \
    -g CARRA2 \
    -s dnora \
    -c configs/CARRA2_exp_1/ \
    -t "scaling,ref"
```
 
| Flag | Description | Default |
|------|-------------|---------|
| `-e` | Experiment name — use a descriptive convention: `<grid><physics><config>` | `exp_YYYYMMDD_HHMMSS` |
| `-w` | WW3 model root (determines which binary is used) | `from_waveXtrems/WW3` |
| `-g` | Grid name — must match a directory under `const/grid/` | `CARRA2` |
| `-s` | Switch name — used for metadata labelling | `dnora` |
| `-c` | Config/namelist directory — namelists are **copied** (not symlinked) | none |
| `-t` | Comma-separated tags for filtering the CSV | none |
| `-y` | Year of forcing data | `2021` |
| `-m` | Month of forcing data | `01` |
| `-D` | Data root path | `/nobackup/.../NewHindcast_CARRA2` |
| `-f` | Force overwrite existing experiment | false |
| `--dry-run` | Print actions without creating any files | false |
 
After setup, namelists can also be copied manually if `-c` is not given:
 
```bash
cp /path/to/ww3_prnc.nml       experiments/CARRA2_ref_oneVar/work/
cp /path/to/ww3_shel_1h.nml    experiments/CARRA2_ref_oneVar/work/
cp /path/to/ww3_shel_10h.nml   experiments/CARRA2_ref_oneVar/work/
cp /path/to/ww3_shel_1d.nml    experiments/CARRA2_ref_oneVar/work/
```

> **Namelist locations — important distinction:**
>
> | Namelist | Location | Notes |
> |----------|----------|-------|
> | `ww3_grid.nml` | `DATA_ROOT/const/grid/<GRID>/` | Defines spectral resolution, timesteps, and grid topology. Shared across experiments using the same grid. **Do not put in `configs/`.** |
> | `ww3_prnc.nml`, `ww3_shel.nml`, etc. | `configs/<config_name>/` | Experiment-specific; copied by `setup.sh -c`. |
>
> For CARRA2 on Fahrenheit:
> ```bash
> ls /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/const/grid/CARRA2/
> # → ww3_grid.nml  (and grid binary files)
> ```

### 2. Submit the experiment
 
```bash
# Classic: explicit nodes × tasks/node
./scripts/run_exp.sh -e CARRA2_ref_oneVar -N 12 -n 56 -t 01:00:00 -d 10h
 
# Flexible: total tasks, let Slurm pick nodes
./scripts/run_exp.sh -e CARRA2_ref_oneVar --ntasks 672 -d 10h
 
# With memory control (recommended on Fahrenheit)
./scripts/run_exp.sh -e CARRA2_ref_oneVar -N 16 -n 63 -d 10h --mem-per-cpu 0
 
# With postprocessing
./scripts/run_exp.sh -e CARRA2_ref_oneVar -N 12 -n 56 -d 1d --post
```
 
| Flag | Description | Default |
|------|-------------|---------|
| `-e` | Experiment name (must match a `setup.sh` run) | required |
| `-N` | Number of nodes | `12` |
| `-n` | Tasks per node | `56` |
| `--ntasks N` | Total MPI tasks — Slurm picks node layout | — |
| `--cpus-per-task N` | OpenMP threads per MPI rank | `1` |
| `--mem-per-cpu MB` | Memory per CPU in MB; use `0` for `--mem=0` (all node memory) | cluster default |
| `-t` | Wall time | `01:00:00` |
| `-d` | Sim duration: `1h`, `10h`, `1d`, `3d`, `7d` | `1h` |
| `-s` | Skip preprocessing (if `mod_def.ww3` and `wind.ww3` already exist) | false |
| `--post` | Also run postprocessing (`ww3_ounf`) after shel succeeds | false |
| `-p` | Only postprocessing — skip prep and shel | false |
| `--dry-run` | Print sbatch commands without submitting | false |
 
**Memory guidance for Fahrenheit** (288 cores/node, ~741 GB RAM):
- `--mem-per-cpu 0` — request all node memory; simplest, avoids OOM kills on homogeneous nodes
- `--mem-per-cpu 1200` — cap at 1200 MB × n_tasks/node (e.g. 63 × 1200 ≈ 76 GB/node)
- Omit entirely — use cluster default (works but not predictable across node types)

### 3. Diagnose an experiment

**Overview of all experiments at once:**

```bash
# Full dashboard (colour-coded table)
./scripts/scan_experiments.sh

# Show only failed or cancelled experiments
./scripts/scan_experiments.sh --status FAILED,CANCELLED

# Filter by tag (e.g. only calibration runs)
./scripts/scan_experiments.sh --tag calibration

# Experiments in a specific group subfolder
./scripts/scan_experiments.sh --group phase3

# Machine-readable CSV
./scripts/scan_experiments.sh --csv > scan_$(date +%Y%m%d).csv

# Interactive cleanup — select experiments to remove
./scripts/scan_experiments.sh --status FAILED,CANCELLED --clean
./scripts/scan_experiments.sh --status FAILED,CANCELLED --clean --dry-run  # preview first
```

`scan_experiments.sh` supports both a flat `experiments/<name>/` layout and a grouped
`experiments/<group>/<name>/` layout simultaneously.

**Reorganise existing flat experiments into groups:**

```bash
# Preview what would be grouped (always start with dry-run)
./scripts/migrate_groups.sh --by-physics --dry-run   # calibration: group=physics, sub=period
./scripts/migrate_groups.sh --by-tag     --dry-run   # benchmarks: group=phase tag

# Execute (asks for confirmation)
./scripts/migrate_groups.sh --by-physics --apply

# Move specific experiments manually
./scripts/migrate_groups.sh --group phase4 --experiments p4_pin_scatter_n60,p4_dtxy_90_ref_n60 --apply
```

After migration, `exp_config.sh` paths are automatically updated. Both
`scan_experiments.sh`, `run_exp.sh`, and `check_exp.sh` detect the grouped layout
transparently (no flags needed after migration).

**Detailed single-experiment inspection:**

```bash
./scripts/check_exp.sh -e CARRA2_ref_oneVar       # summary
./scripts/check_exp.sh -e CARRA2_ref_oneVar -v    # verbose (full log tails)
./scripts/check_exp.sh -e CARRA2_ref_oneVar -j 36239  # query a specific job ID
```

`check_exp.sh` inspects without resubmitting: directory structure, symlink health,
WW3 log analysis (`End of program`, FATAL ERROR, timestep count), sacct state,
Slurm ERR log snippets, and the performance report summary.

### 4. Monitor

```bash
squeue -u $USER
tail -f experiments/CARRA2_ref_oneVar/logs/shel.*.LOG
tail -f experiments/CARRA2_ref_oneVar/work/log.ww3
```

### 5. Results
 
```bash
# Single experiment — full report
cat experiments/CARRA2_ref_oneVar/metadata/runtime/performance_*.txt
 
# Timing raw data
cat experiments/CARRA2_ref_oneVar/metadata/runtime/timing_raw.txt
 
# All experiments side by side
column -t -s, benchmark_summary.csv
```

---

## Job Chain
 
Each `run_exp.sh` call submits up to four Slurm jobs with automatic dependencies:
 
```
prep.job  ──afterok──►  run_shel.job  ──afterok──►  post.job  (if --post)
                              │
                         afterany
                              │
                              ▼
                       log_performance.sh   (always runs, even on crash)
```
 
The performance logger runs under `--dependency=afterany` so timing and status
are captured regardless of whether the model succeeded or failed.
 
---

Machine-friendly summaries
- For quick programmatic access to configs and registry data see: [configs/REGISTRY_SUMMARY.md](configs/REGISTRY_SUMMARY.md) (compact), and the full registry at [configs/REGISTRY.md](configs/REGISTRY.md).
- Use [configs/manage_config.sh](configs/manage_config.sh) to script config creation and inspection; `--list-templates` and `rebuild-registry` are available.
 
## Run Status Values
 
Status is determined from two sources and reconciled:
 
| Status | Meaning |
|--------|---------|
| `SUCCESS` | `End of program` found in `log.ww3` and Slurm exit 0 |
| `INCOMPLETE` | WW3 ran but `End of program` not found — wall-time limit hit? |
| `FATAL_ERROR` | `FATAL ERROR` found in `test001.ww3` |
| `CRASHED` | `srun`/`ww3_shel` returned non-zero exit code |
| `TIMEOUT` | Slurm killed the job at wall-time limit (from sacct) |
| `OUT_OF_MEMORY` | Node ran out of memory (from sacct) — reduce tasks/node or use `--mem-per-cpu` |
| `FAILED` | Slurm reports FAILED but cause unclear — check `.ERR` logs |
| `UNKNOWN` | `timing_raw.txt` not written — job may have been killed before WW3 started |
 
---

## Recipes
 
### Scaling Study
 
```bash
for N in 4 8 12 16; do
    ./scripts/setup.sh -e scale_${N}n -g CARRA2 -s dnora -c configs/CARRA2_exp_1/ -t "scaling,ref"
    ./scripts/run_exp.sh -e scale_${N}n -N $N -n 56 -d 10h --mem-per-cpu 0
done
column -t -s, benchmark_summary.csv
```
 
### Physics Comparison (different WW3 builds)
 
```bash
./scripts/setup.sh -e CARRA2_PR2_UQ \
    -w /home/sm_lenal/programs/compiling/PR2_UQ/WW3 \
    -s PR2_UQ -g CARRA2 -c configs/CARRA2_exp_1/ -t "physics,PR2"
 
./setup.sh -e CARRA2_PR3_UNO \
    -w /home/sm_lenal/programs/compiling/PR3_UNO/WW3 \
    -s PR3_UNO -g CARRA2 -c configs/oneVar_noSaving/ -t "physics,UNO"
 
./run_exp.sh -e CARRA2_PR2_UQ  -N 12 -n 56 -d 10h
./run_exp.sh -e CARRA2_PR3_UNO -N 12 -n 56 -d 10h
```
### Re-run Performance Logging Only
 
If the perf job failed or `seff` timed out, re-run it manually against an existing job ID:
 
```bash
sbatch \
    --account=eu-interchange \
    --job-name=WW3-perf-manual \
    --time=00:15:00 --nodes=1 --ntasks-per-node=1 \
    log_performance.sh \
    experiments/CARRA2_ref_oneVar  36239  \
    16  63  10h  \
    experiments/CARRA2_ref_oneVar/metadata  1008
```
 
### Skip Preprocessing (files already exist)
 
```bash
./run_exp.sh -e CARRA2_ref_oneVar -N 12 -n 56 -d 10h -s
```

---
## What Gets Logged Automatically
 
For every experiment (in `metadata/setup/`, locked after creation):
 
- **WW3 switch file** — exact physics/numerics compilation options
- **Executable timestamps** — which binary was linked
- **Module environment** — `module list` at setup time
- **Git commit** — WW3 repo HEAD hash (if git repo)
- **JSON metadata** — structured provenance for scripted analysis
For every run (in `metadata/runtime/`, appended on each submission):
 
- **Job configuration** — nodes, tasks/node, CPUs/task, mem/CPU, wall time, sim duration
- **Cluster state** — `sinfo` snapshot at submission and at logging time
- **Timing** — wall-clock seconds and minutes, sim-days/hour throughput
- **WW3 status** — exit code + log analysis (see status table above)
- **sacct state** — Slurm's authoritative job state (catches OOM, timeout)
- **seff metrics** — CPU efficiency (with sacct fallback), memory utilisation
- **WW3 log tail** — last 20 lines of `log.ww3` and `test001.ww3`
- **CSV row** — appended to `benchmark_summary.csv` (schema v2.3)
---
 
## CSV Schema (v2.3)
 
```
exp_name, tags, job_id, status, sacct_state,
nodes, tasks_per_node, total_tasks, cpus_per_task, mem_per_cpu_mb, total_cores,
sim_duration, elapsed_seconds, elapsed_minutes, throughput_days_per_hour,
cpu_efficiency_pct, mem_efficiency_pct,
switch, grid, ww3_commit, date
```
 
The schema version is stored in the CSV header comment (`# schema=v2.3`).
If the framework detects a schema mismatch, the old CSV is archived to
`benchmark_summary.csv.pre-v2.3` before a fresh one is started.
 
---
 
## Known Cluster Notes (Fahrenheit)
 
- MPI launcher: `srun --mpi=pmix` (Intel oneAPI, replaces `mpprun` from Nebula)
- Required modules at runtime (loaded by `metadata/setup/env.sh`):
  - `netCDF-HDF5-utils/4.9.2-1.12.2-hpc1-intel2023.1.0-hpc1`
  - `eccodes-utils/2.32.0-ENABLE-AEC-hpc1-intel-2023.1.0-hpc1`
- Node spec: 288 cores/node, ~741 GB RAM
- Memory recommendation: `--mem-per-cpu 0` (use all node memory)
- Safe tasks/node: ≤ 63 (leaving headroom for OS; 63 × ~1.3 GB/rank ≈ 82 GB)
- `seff` accounting may lag job end by 30–120 s; `log_performance.sh` retries up to 8×
