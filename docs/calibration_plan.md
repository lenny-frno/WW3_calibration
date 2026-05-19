# WW3 Calibration Plan — BETAMAX + WCOR sweep (`with_sic` config)

**Generated**: 2026-05-19  
**Config**: `configs/with_sic` (wind + sea-ice concentration + sea-ice thickness)  
**HPC run path**: `/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration/`  
**Registered periods**: `storm_eunice_2022` (2022-02-18 → 2022-02-21, 3 days)

---

## Parameter knowledge

### BETAMAX

- **Namelist**: `&SIN4`
- **WW3 physics package**: ST4 (Ardhuin et al. 2010, *J. Phys. Oceanogr.*)
- **Physical meaning**: Maximum non-dimensional growth rate for the wind-input source term S_in.
  In the ST4 formulation, wave growth follows a modified Miles (1957) instability mechanism.
  BETAMAX scales the effective coupling coefficient between wind and waves, setting an upper
  bound on the exponential growth rate β_max in the input term
  S_in(f,θ) ∝ β(u_*/c_ph) · F(f,θ).
  Physically it controls how efficiently the atmospheric boundary layer energises the wave field.
- **Effect on model output**:
  - Larger BETAMAX → stronger wind input → faster wave growth, higher significant wave height
    (Hs), more energetic swell generation.
  - Smaller BETAMAX → suppressed growth, lower Hs, narrower spectra in extreme storms.
  - The impact is largest when the wave age (c_ph / u_*) is small, i.e., young, actively-growing
    sea under strong winds — exactly the Arctic storm conditions targeted here.
- **Tuning guidance**: Calibrate against Hs from wave buoys or satellite altimetry in storm
  conditions. Run the BETAMAX sweep (Phase 1) first, holding WCOR1=99 and WCOR2=0.0 to isolate
  the growth-rate effect. The WW3 community default for ST4 is ~1.33–1.75; ECWAM-like runs
  commonly use 1.43. Values above ~1.65 risk overestimating Hs in strong open-ocean storms.

---

### WCOR1 (MISC%WCOR1)

- **Namelist**: `&MISC`
- **Physical meaning**: Lower wind-speed threshold (m/s) for a wind-input correction scheme that
  reduces wave growth at very high wind speeds. Above this threshold, the parameterisation
  applies a gradual reduction to the effective wind forcing, preventing unrealistic Hs in
  extreme storms where wave-breaking feedback and spray physics are not fully resolved by ST4.
- **Effect**: When WCOR1 is set to a physically reachable value (e.g., 15–25 m/s), the
  correction activates for all model grid points where the 10-m wind speed exceeds the threshold.
  This reduces Hs in the most extreme tail of the wind-speed distribution while leaving
  moderate-wind cells largely unaffected. Lower WCOR1 values apply more aggressive correction
  over a broader portion of the storm.
- **Value 99**: Acts as an OFF switch — no real storm ever produces 99 m/s 10-m winds, so the
  correction is never triggered and the model behaves exactly as ST4 without any high-wind
  damping.

---

### WCOR2 (MISC%WCOR2)

- **Namelist**: `&MISC`
- **Physical meaning**: Fractional correction coefficient applied together with WCOR1. Once the
  wind speed exceeds WCOR1, the effective wind input is reduced by a factor governed by WCOR2.
  A value of 0.0 means no correction is applied regardless of WCOR1. Increasing WCOR2 increases
  the strength of the high-wind damping.
- **Effect**: At WCOR2=0.0, the correction is completely off. At WCOR2=0.1–0.2, a moderate
  damping is introduced above WCOR1. The correction is cumulative with the WCOR1 threshold:
  both parameters must be set to non-trivial values for any effect. Tune WCOR2 last — after
  identifying the best BETAMAX and a suitable WCOR1 range — to fine-tune the storm-peak bias.

---

## Experiment matrix

### Phase 1 — BETAMAX sweep (WCOR1=99, WCOR2=0.0 fixed)

| # | BETAMAX | WCOR1 | WCOR2 | Note              |
|---|---------|-------|-------|-------------------|
| 1 | 1.33    | 99    | 0.0   | Lower bound       |
| 2 | **1.43**| 99    | 0.0   | **Baseline**      |
| 3 | 1.50    | 99    | 0.0   |                   |
| 4 | 1.55    | 99    | 0.0   |                   |
| 5 | 1.65    | 99    | 0.0   |                   |
| 6 | 1.75    | 99    | 0.0   | Upper bound       |

Run for each registered period: `storm_eunice_2022`. → **6 experiments total**.

### Phase 2 — WCOR sweep (BETAMAX = BEST from Phase 1)

Replace `BEST_BM` / `bm{BEST}` below with the winning value from Phase 1 before submitting.

| # | BETAMAX   | WCOR1 | WCOR2 | Note                        |
|---|-----------|-------|-------|-----------------------------|
| 1 | BEST_BM   | 99    | 0.0   | Re-run baseline (Phase 1 ✓) |
| 2 | BEST_BM   | 99    | 0.1   |                             |
| 3 | BEST_BM   | 99    | 0.2   |                             |
| 4 | BEST_BM   | 15.0  | 0.0   |                             |
| 5 | BEST_BM   | 15.0  | 0.1   |                             |
| 6 | BEST_BM   | 15.0  | 0.2   |                             |
| 7 | BEST_BM   | 20.0  | 0.0   |                             |
| 8 | BEST_BM   | 20.0  | 0.1   |                             |
| 9 | BEST_BM   | 20.0  | 0.2   |                             |
|10 | BEST_BM   | 25.0  | 0.0   |                             |
|11 | BEST_BM   | 25.0  | 0.1   |                             |
|12 | BEST_BM   | 25.0  | 0.2   |                             |

**12 experiments** (row 1 was already run in Phase 1; skip or use it as a consistency check).

---

## Prerequisites (one-time)

```bash
# 1. Change to the HPC calibration workspace
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration

# 2. Verify storm_eunice_2022 is registered
./scripts/manage_periods.sh list

# 3. (Optional) Register additional periods as they become available
#    ./scripts/manage_periods.sh add <name> --start YYYYMMDD --end YYYYMMDD \
#        --desc "..." --tags "storm,calibration"

# 4. Confirm the OMPH binary exists (fastest option)
OMPH_WW3="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/p4_omph/WW3"
ls -lh "${OMPH_WW3}" || echo "OMPH binary not found — will use from_waveXtrems default"
```

> **OMPH binary note**: The `-w` flag in `setup.sh` sets the WW3 binary path. If the OMPH binary
> is not yet compiled, omit `-w` and the default `from_waveXtrems` binary is used automatically.
> To use OMPH, patch `env.sh` after each `setup.sh` call:
>
> ```bash
> ENV="experiments/${EXP_NAME}/metadata/setup/env.sh"
> chmod u+w "${ENV}"
> echo "export WW3_OMP_THREADS=2"        >> "${ENV}"
> echo "export I_MPI_ASYNC_PROGRESS=0"   >> "${ENV}"
> chmod a-w "${ENV}"
> ```
>
> Or pass `-w "${OMPH_WW3}"` directly to `setup.sh`.

---

## Phase 1 commands — BETAMAX sweep

All experiments use `MISC_WCOR1=99` and `MISC_WCOR2=0.0` (correction disabled).

```bash
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration
```

---

### BM 1.33

```bash
# BETAMAX=1.33 | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm133_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX=1.33 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm133_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### BM 1.43 (baseline)

```bash
# BETAMAX=1.43 | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm143_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX=1.43 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm143_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### BM 1.50

```bash
# BETAMAX=1.50 | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm150_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX=1.50 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm150_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### BM 1.55

```bash
# BETAMAX=1.55 | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm155_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX=1.55 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm155_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### BM 1.65

```bash
# BETAMAX=1.65 | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm165_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX=1.65 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm165_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### BM 1.75

```bash
# BETAMAX=1.75 | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm175_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX=1.75 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm175_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### Phase 1 — shorthand loop (alternative)

The 6 blocks above can also be submitted as a shell loop:

```bash
for BM in 1.33 1.43 1.50 1.55 1.65 1.75; do
  BM_TAG="${BM//./}"          # 1.43 → 143
  EXP="with_sic__bm${BM_TAG}_w1_99_w2_00__storm_eunice_2022"

  ./scripts/setup.sh \
    -e "${EXP}" \
    -c configs/with_sic \
    -P storm_eunice_2022 \
    -X BETAMAX="${BM}" \
    -X MISC_WCOR1=99 \
    -X MISC_WCOR2=0.0 \
    -t "calibration,sic,betamax,wcor"

  ./scripts/run_exp.sh \
    -e "${EXP}" \
    -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
done
```

---

## Phase 1 — post-run evaluation

After all 6 jobs complete, compare Hs against observations to find the best BETAMAX:

```bash
# Check job status
./scripts/check_exp.sh with_sic__bm133_w1_99_w2_00__storm_eunice_2022
./scripts/check_exp.sh with_sic__bm143_w1_99_w2_00__storm_eunice_2022
./scripts/check_exp.sh with_sic__bm150_w1_99_w2_00__storm_eunice_2022
./scripts/check_exp.sh with_sic__bm155_w1_99_w2_00__storm_eunice_2022
./scripts/check_exp.sh with_sic__bm165_w1_99_w2_00__storm_eunice_2022
./scripts/check_exp.sh with_sic__bm175_w1_99_w2_00__storm_eunice_2022

# View calibration log
./scripts/manage_periods.sh log --period storm_eunice_2022
```

**Decision gate**: Select `BEST_BM` from Phase 1 before proceeding.

---

## Phase 2 commands — WCOR sweep

**Before running**: replace `BEST_BM` and `bm{BEST}` in every command below with the winning
BETAMAX value found in Phase 1 (e.g., `BEST_BM=1.55`, `bm{BEST}=bm155`).

Row 1 (WCOR1=99, WCOR2=0.0) is a repeat of the Phase 1 best-BM run; skip it or use as a
cross-check for reproducibility.

```bash
# Set this once before running the blocks below:
BEST_BM="1.55"          # ← replace with actual best value from Phase 1
BM_TAG="${BEST_BM//./}" # e.g. 1.55 → 155
```

---

### WCOR1=99, WCOR2=0.0 (Phase 1 repeat — skip or verify)

```bash
# BETAMAX=BEST_BM | WCOR1=99 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_99_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_99_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=99, WCOR2=0.1

```bash
# BETAMAX=BEST_BM | WCOR1=99 | WCOR2=0.1 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_99_w2_01__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.1 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_99_w2_01__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=99, WCOR2=0.2

```bash
# BETAMAX=BEST_BM | WCOR1=99 | WCOR2=0.2 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_99_w2_02__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.2 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_99_w2_02__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=15.0, WCOR2=0.0

```bash
# BETAMAX=BEST_BM | WCOR1=15.0 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_15_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=15.0 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_15_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=15.0, WCOR2=0.1

```bash
# BETAMAX=BEST_BM | WCOR1=15.0 | WCOR2=0.1 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_15_w2_01__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=15.0 \
  -X MISC_WCOR2=0.1 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_15_w2_01__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=15.0, WCOR2=0.2

```bash
# BETAMAX=BEST_BM | WCOR1=15.0 | WCOR2=0.2 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_15_w2_02__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=15.0 \
  -X MISC_WCOR2=0.2 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_15_w2_02__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=20.0, WCOR2=0.0

```bash
# BETAMAX=BEST_BM | WCOR1=20.0 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_20_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=20.0 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_20_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=20.0, WCOR2=0.1

```bash
# BETAMAX=BEST_BM | WCOR1=20.0 | WCOR2=0.1 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_20_w2_01__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=20.0 \
  -X MISC_WCOR2=0.1 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_20_w2_01__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=20.0, WCOR2=0.2

```bash
# BETAMAX=BEST_BM | WCOR1=20.0 | WCOR2=0.2 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_20_w2_02__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=20.0 \
  -X MISC_WCOR2=0.2 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_20_w2_02__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=25.0, WCOR2=0.0

```bash
# BETAMAX=BEST_BM | WCOR1=25.0 | WCOR2=0.0 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_25_w2_00__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=25.0 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_25_w2_00__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=25.0, WCOR2=0.1

```bash
# BETAMAX=BEST_BM | WCOR1=25.0 | WCOR2=0.1 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_25_w2_01__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=25.0 \
  -X MISC_WCOR2=0.1 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_25_w2_01__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### WCOR1=25.0, WCOR2=0.2

```bash
# BETAMAX=BEST_BM | WCOR1=25.0 | WCOR2=0.2 | period: storm_eunice_2022
./scripts/setup.sh \
  -e "with_sic__bm${BM_TAG}_w1_25_w2_02__storm_eunice_2022" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -X BETAMAX="${BEST_BM}" \
  -X MISC_WCOR1=25.0 \
  -X MISC_WCOR2=0.2 \
  -t "calibration,sic,betamax,wcor"

./scripts/run_exp.sh \
  -e "with_sic__bm${BM_TAG}_w1_25_w2_02__storm_eunice_2022" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### Phase 2 — shorthand loop (alternative)

```bash
# Set BEST_BM to the winner from Phase 1 before running
BEST_BM="1.55"           # ← replace
BM_TAG="${BEST_BM//./}"

for W1 in 99 15.0 20.0 25.0; do
  W1_TAG="${W1%%.*}"      # 15.0 → 15, 99 → 99
  for W2 in 0.0 0.1 0.2; do
    W2_TAG=$(echo "${W2}" | sed 's/0\.\([0-9]\)/0\1/; s/0\.0/00/')  # 0.0→00 0.1→01 0.2→02
    EXP="with_sic__bm${BM_TAG}_w1_${W1_TAG}_w2_${W2_TAG}__storm_eunice_2022"

    ./scripts/setup.sh \
      -e "${EXP}" \
      -c configs/with_sic \
      -P storm_eunice_2022 \
      -X BETAMAX="${BEST_BM}" \
      -X MISC_WCOR1="${W1}" \
      -X MISC_WCOR2="${W2}" \
      -t "calibration,sic,betamax,wcor"

    ./scripts/run_exp.sh \
      -e "${EXP}" \
      -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
  done
done
```

---

## Monitoring

```bash
# Check all calibration experiments
for d in experiments/with_sic__bm*; do
  exp=$(basename "${d}")
  echo "--- ${exp}"
  ./scripts/check_exp.sh "${exp}" 2>/dev/null | grep -E "WW3 status|Elapsed" || true
done

# View full calibration log
./scripts/manage_periods.sh log --period storm_eunice_2022

# Check calibration_log.csv directly
column -t -s',' periods/calibration_log.csv | grep with_sic
```

---

## Notes

- All parameter overrides (`-X`) are applied at setup time via `sed` substitution of `{{KEY}}`
  tokens in namelists — no `.nml` file is ever edited manually.
- If more storm periods are registered (via `manage_periods.sh add`), re-run the loops above
  substituting the new period name for `storm_eunice_2022`.
- The `--post` flag in `run_exp.sh` triggers the postprocessing job automatically after `ww3_shel`
  finishes.
- Wall time `00:20:00` is calibrated for 3-day runs at 16 nodes × 60 tasks × 2 threads (OMPH).
  If using the `from_waveXtrems` binary (no OpenMP), increase to `00:45:00`.
