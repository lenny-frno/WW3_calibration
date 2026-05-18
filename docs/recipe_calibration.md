# Recipe: Calibration Study

Calibrate WW3 physics parameters (e.g. `BETAMAX`) by running experiments across multiple storm periods and comparing Hs against observations. Each combo of config × period is one row in `periods/calibration_log.csv`.

## What it produces

- One experiment directory per (config, period) pair
- NetCDF output with `HS`, `ICE`, `WND`, `T02`, `DP` for each run
- Rows appended to `periods/calibration_log.csv`

## Config choices

| Config | Forcings | Use when |
|--------|----------|----------|
| `CARRA2_exp_1` | Wind only | Baseline, open-ocean areas |
| `with_sic` | Wind + SIC | Arctic/marginal ice zone runs |
| `with_sithick` | Wind + SIC + thickness | Full IC1 dissipation |
| `everything_betamax_1_65` | All + BETAMAX=1.65 | Pre-set calibration sweep |
| `everything_betamax_1_75` | All + BETAMAX=1.75 | Pre-set calibration sweep |

## Step 1 — Register storm periods

```bash
./scripts/manage_periods.sh add winter_2022 \
  --start 20220101 --end 20220228 \
  --description "Winter 2022 calibration period" \
  --tags "calibration,winter"

./scripts/manage_periods.sh add storm_eunice_2022 \
  --start 20220218 --end 20220221 \
  --description "Storm Eunice, North Sea" \
  --tags "storm,calibration"

./scripts/manage_periods.sh list
```

## Step 2 — Single config × single period (manual)

Useful for quick checks before launching a full sweep.

```bash
# Setup
./scripts/setup.sh \
  -e with_sic__eunice \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -t "calibration,sic,storm"

# Override a parameter without editing any file:
# -X BETAMAX=1.50  -X OUTPUT_FIELDS="HS ICE WND T02"

# Submit (fastest OMPH binary)
OMPH_WW3="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/p4_omph/WW3"

ENV="experiments/with_sic__eunice/metadata/setup/env.sh"
chmod u+w "${ENV}"
echo "export WW3_OMP_THREADS=2"   >> "${ENV}"
echo "export I_MPI_ASYNC_PROGRESS=0" >> "${ENV}"
chmod a-w "${ENV}"

./scripts/run_exp.sh \
  -e with_sic__eunice \
  -N 16 -n 60 --cpus-per-task 2 \
  -t 00:20:00 -d 3d --post
```

## Step 3 — Multi-period sweep (run_calibration.sh)

Use `run_calibration.sh` to dispatch one config across several periods automatically. Each period is set up and submitted in sequence; results are logged to `calibration_log.csv`.

```bash
# Dispatch with_sic across two periods
./scripts/run_calibration.sh \
  -c configs/with_sic \
  -P storm_eunice_2022,winter_2022 \
  -e sic_calib \
  -N 16 -n 60 --cpus-per-task 2 -t 00:30:00 -d 3d

# Or run all registered periods:
./scripts/run_calibration.sh \
  -c configs/with_sic \
  --all-periods \
  -e sic_calib_all
```

## Step 4 — BETAMAX parameter sweep, multiple periods

Combine the `-X` override with `run_calibration.sh` to sweep physics params without creating separate config folders.

```bash
# Sweep BETAMAX: 1.43 → 1.55 → 1.65 over storm_eunice
for BM in 1.43 1.50 1.55 1.60 1.65; do
  TAG="bm_${BM//./_}"
  ./scripts/setup.sh \
    -e "with_sic__eunice__${TAG}" \
    -c configs/with_sic \
    -P storm_eunice_2022 \
    -X BETAMAX=${BM} \
    -t "calibration,sic,betamax_sweep"
  ./scripts/run_exp.sh \
    -e "with_sic__eunice__${TAG}" \
    -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
done
```

> All substitutions happen at setup time — no `.nml` file is edited manually.

## Step 5 — Check progress

```bash
# Status of all calibration experiments
for d in experiments/with_sic__*; do
  exp=$(basename "${d}")
  ./scripts/check_exp.sh "${exp}" 2>/dev/null | grep -E "WW3 status|Elapsed"
done

# Summary table
grep "calibration" benchmark_summary.csv | \
  awk -F',' '{printf "%-40s %8s s   %6s days/h\n", $1, $13, $15}' | sort
```

## Step 6 — Collect output for validation

After runs complete, postprocess if not done automatically:

```bash
./scripts/run_exp.sh -e with_sic__eunice__bm_1_50 -d 3d -p   # postprocess only
```

NetCDF files land in `experiments/<exp>/work/Wave_wind_sic_CARRA2*.nc`. Load with:

```python
import xarray as xr
ds = xr.open_mfdataset('experiments/with_sic__eunice__bm_1_50/work/Wave_wind_sic_CARRA2*.nc')
print(ds['hs'].max())  # check Hs peak during Eunice
```

## Step 7 — Check calibration log

```bash
./scripts/manage_periods.sh log
cat periods/calibration_log.csv | column -t -s ','
```

## Tips

- Use `--dry-run` on `setup.sh` to preview all substitutions without creating files: `./scripts/setup.sh ... --dry-run`
- `{{OUTPUT_FIELDS}}` defaults to `HS ICE WND T02 DP` in `with_sic/params.env`. Override to add `DIR UST` for wind-sea coupling validation.
- Run a **3-day storm period** for quick iteration; a **30-day winter period** for full statistical calibration.
- The `everything_betamax_1_65` and `_1_75` configs have pre-set BETAMAX via their `params.env` — use them with `run_calibration.sh` for a ready-made 2-point calibration sweep.
