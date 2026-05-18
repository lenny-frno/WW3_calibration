# Recipe: Scaling Study

Measure how WW3 throughput scales with MPI rank count on Fahrenheit. The goal is to find the knee of the scaling curve — the point where adding more cores stops giving proportional speedup.

## What it produces

A set of `benchmark_summary.csv` rows comparing throughput (sim_days/h) and CPU efficiency across different task counts (e.g. 480, 640, 768, 960, 1072, 1120 ranks), all using the same binary and config.

## Prerequisites

- A compiled WW3 binary (e.g. fastest: `p4_omph varB`, or use the default `from_waveXtrems`)
- Data for at least one month (wind forcing, grid files)
- A registered period (or use `-y`/`-m` for manual dates)

## Step 1 — Setup the reference experiment once

Run setup once to create the grid, link forcings, and copy namelists. All scaling jobs reuse the same preprocessed `work/` directory.

```bash
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration

./scripts/setup.sh \
  -e scaling_ref \
  -c configs/CARRA2_exp_1 \
  -P storm_eunice_2022 \
  -t "scaling,ref"
```

> To override physics params without editing files:
> ```bash
> ./scripts/setup.sh -e scaling_ref -c configs/CARRA2_exp_1 \
>   -P storm_eunice_2022 -X BETAMAX=1.50 -X OUTPUT_STRIDE=7200
> ```

## Step 2 — Run preprocessing (once)

```bash
./scripts/run_exp.sh -e scaling_ref -N 1 -n 1 -t 00:10:00 -d 3d
# Wait for prep to finish, then cancel the shel job if you only want prep:
# squeue -u $USER   →   scancel <shel_job_id>
```

Or skip the shel entirely with a targeted prep-only submission:
```bash
sbatch --account=eu-interchange --nodes=1 --ntasks=1 --time=00:10:00 \
  jobs/prep.job \
  experiments/scaling_ref/work \
  experiments/scaling_ref/work \
  experiments/scaling_ref/metadata
```

## Step 3 — Submit scaling runs (skip prep with -s)

Submit the same experiment at increasing task counts. Use `-s` to skip preprocessing (reuse the already-built `mod_def.ww3` and forcing `.ww3` files).

```bash
for N_TASKS in 480 640 768 960 1072 1120; do
  ./scripts/run_exp.sh \
    -e scaling_ref \
    --ntasks ${N_TASKS} \
    --cpus-per-task 2 \
    -t 00:30:00 \
    -d 3d \
    -s        # skip preprocessing — reuse work/ from Step 2
done
```

> **Fahrenheit layout reference** (144 cores/node):
> | Tasks | Nodes | Tasks/node | Cores used |
> |-------|-------|------------|-----------|
> | 480   | ~4    | 60 (auto)  | 960       |
> | 640   | ~6    | ~53        | 1280      |
> | 768   | ~7    | ~55        | 1536      |
> | 960   | 8     | 60         | 1920      |
> | 1072  | 8     | 67         | 2144      |
> | 1120  | 8     | 70         | 2240      |

## Step 4 — Check results

```bash
./scripts/check_exp.sh scaling_ref
grep "scaling_ref" benchmark_summary.csv | column -t -s ','
```

Key columns: `total_tasks`, `elapsed_seconds`, `throughput_days_per_hour`, `cpu_efficiency_pct`.

## Step 5 — Log additional runs

If you resubmit without setup (e.g. after a failure), log performance manually:

```bash
./scripts/log_performance.sh -e scaling_ref -j <job_id>
```

## Quick reference: one-liner parameter sweep

```bash
# Sweep BETAMAX at fixed rank count — no file editing needed
for BM in 1.43 1.50 1.55 1.60; do
  EXP="scaling_betamax_${BM//./_}"
  ./scripts/setup.sh -e "${EXP}" -c configs/CARRA2_exp_1 \
    -P storm_eunice_2022 -X BETAMAX=${BM} -t "scaling,betamax"
  ./scripts/run_exp.sh -e "${EXP}" -N 16 -n 60 --cpus-per-task 2 -d 3d -t 00:20:00
done
```

## Tips

- Use a **short period** (3–5 days) for scaling: fast wall time, enough to amortise startup.
- Fix the **data input** by running setup only once and reusing with `-s`. This isolates compute from I/O variance.
- Enable `--post` on the last run only to extract NetCDF for a sanity check on the output.
