# WW3 Calibration Plan — BETAMAX + WCOR sweep (`with_sic` config)

**Generated**: 2026-05-19  
**Config**: `configs/with_sic` (wind + sea-ice concentration + sea-ice thickness)  
**HPC run path**: `/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration/`  
**Registered periods**: `storm_eunice_2022` (pre-registered) + 10 catalogue storms — see §Prerequisites for registration commands

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

## Storm periods

23 storm periods from automated catalogue (`storm_periods_reduced.csv`, peak-wind threshold ≥ 14 m/s).
All periods registered in §Prerequisites.

| #  | Period name | Start | End | Basin | Peak wind (m/s) | Days |
|----|-------------|-------|-----|-------|-----------------|------|
|  1 | `storm_natl_20110211` | 2011-02-11 | 2011-02-12 | North Atlantic | 38.2 | 1 |
|  2 | `storm_natl_20120311` | 2012-03-11 | 2012-03-13 | North Atlantic | 30.9 | 2 |
|  3 | `storm_iceland_20120829` | 2012-08-29 | 2012-08-30 | Iceland/Jan Mayen | 23.0 | 1 |
|  4 | `storm_arctic_20121024` | 2012-10-24 | 2012-10-25 | Arctic Ocean | 27.3 | 1 |
|  5 | `storm_nsea_20131205` | 2013-12-05 | 2013-12-06 | North Sea | 30.2 | 1 |
|  6 | `storm_norsea_20140809` | 2014-08-09 | 2014-08-10 | Norwegian Sea | 23.2 | 1 |
|  7 | `storm_natl_20150309` | 2015-03-09 | 2015-03-13 | North Atlantic | 30.3 | 4 |
|  8 | `storm_nsea_20160129` | 2016-01-29 | 2016-01-30 | North Sea | 29.0 | 1 |
|  9 | `storm_barents_20170310` | 2017-03-10 | 2017-03-12 | Barents Sea | 28.5 | 2 |
| 10 | `storm_norsea_20191021` | 2019-10-21 | 2019-10-22 | Norwegian Sea | 27.8 | 1 |
| 11 | `storm_greenland_20200405` | 2020-04-05 | 2020-04-07 | Greenland Sea | 32.9 | 2 |
| 12 | `storm_nsea_20210310` | 2021-03-10 | 2021-03-11 | North Sea | 24.9 | 1 |
| 13 | `storm_nsea_20211126` | 2021-11-26 | 2021-11-27 | North Sea | 25.8 | 1 |
| 14 | `storm_arctic_20220122` | 2022-01-22 | 2022-01-25 | Arctic Ocean | 30.4 | 3 |
| 15 | `storm_norsea_20220320` | 2022-03-20 | 2022-03-22 | Norwegian Sea | 27.3 | 2 |
| 16 | `storm_greenland_20230202` | 2023-02-02 | 2023-02-04 | Greenland Sea | 39.9 | 2 |
| 17 | `storm_greenland_20231121` | 2023-11-21 | 2023-11-23 | Greenland Sea | 31.5 | 2 |
| 18 | `storm_norsea_20240130` | 2024-01-30 | 2024-02-01 | Norwegian Sea | 31.0 | 2 |
| 19 | `storm_norsea_20241128` | 2024-11-28 | 2024-11-30 | Norwegian Sea | 28.3 | 2 |
| 20 | `storm_norsea_20250206` | 2025-02-06 | 2025-02-07 | Norwegian Sea | 29.4 | 1 |
| 21 | `storm_labrador_20250215` | 2025-02-15 | 2025-02-17 | Labrador Sea | 42.3 | 2 |
| 22 | `storm_nsea_20250804` | 2025-08-04 | 2025-08-06 | North Sea | 24.4 | 2 |
| 23 | `storm_nsea_20251003` | 2025-10-03 | 2025-10-05 | North Sea | 26.9 | 2 |
---
## Storm periods — legacy catalog (pre-2026-06)

Manually curated named storms used in the original calibration plan. Superseded by the
automated catalogue above. Kept for reference and cross-identification.

| # | Period name | Start | End | Basin | Peak gust | Days |
|---|-------------|-------|-----|-------|-----------|------|
| 0 | `storm_eunice_2022` | 2022-02-18 | 2022-02-21 | North Sea | — | 3 |
| 1 | `storm_berit_2011` | 2011-11-22 | 2011-11-29 | Norwegian Sea | ~51 m/s | 7 |
| 2 | `storm_friedhelm_2011` | 2011-12-08 | 2011-12-13 | North Sea | ~47 m/s | 5 |
| 3 | `storm_dagmar_2011` | 2011-12-24 | 2011-12-28 | Norwegian coast | ~44 m/s sust. | 4 |
| 4 | `storm_hilde_2013` | 2013-11-13 | 2013-11-19 | Norwegian Sea | ~45 m/s | 6 |
| 5 | `storm_xaver_2013` | 2013-12-04 | 2013-12-11 | North Sea | ~47 m/s | 7 |
| 6 | `storm_ciara_2020` | 2020-02-08 | 2020-02-13 | Norwegian Sea | ~49 m/s | 5 |
| 7 | `storm_dennis_2020` | 2020-02-13 | 2020-02-18 | Norwegian Sea | ~55 m/s | 5 |
| 8 | `storm_malik_2022` | 2022-01-28 | 2022-01-31 | North Sea | ~54 m/s | 3 |
| 9 | `storm_ingunn_2024` | 2024-01-30 | 2024-02-02 | Norwegian Sea | ~69 m/s | 3 |
| 10 | `storm_eowyn_2025` | 2025-01-21 | 2025-01-27 | Norwegian Sea | ~50+ m/s | 6 |

*Cross-reference*: `storm_xaver_2013` ≈ `storm_nsea_20131205`; `storm_ingunn_2024` ≈ `storm_norsea_20240130`.

## Compiled binary variants

Three compiled WW3 binaries cover the performance spectrum from reference to fastest.
Physics output must be bit-equivalent across all three; any difference > 10⁻⁴ relative in
Hs flags a compilation regression.

| Tag | Benchmark experiment | Elapsed/10h sim | Parallelism | Optimal layout | Wall/3d-sim |
|-----|---------------------|-----------------|-------------|----------------|-------------|
| `ref` | `from_waveXtrems` | 417 s | MPI | `-N 16 -n 60` | `00:45:00` |
| `p3avx2` | `p3_fp2_ipo_unroll_avx2_nd` | 355 s | MPI | `-N 16 -n 69` | `00:30:00` |
| `omph` | `p4_omph_varB_n60` | 290 s | MPI + OMP | `-N 16 -n 60 --cpus-per-task 2` | `00:20:00` |

Binary paths (`BASE` = `/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models`):

```
ref    : /home/sm_lenal/programs/compiling/from_waveXtrems/WW3
p3avx2 : ${BASE}/p3_fp2_ipo_unroll_avx2_nd/WW3
omph   : ${BASE}/p4_omph/WW3
```

**OMPH-specific env patch** — required after every `setup.sh` call that uses the `omph` binary:

```bash
ENV="experiments/${EXP}/metadata/setup/env.sh"
chmod u+w "${ENV}"
echo "export WW3_OMP_THREADS=2"        >> "${ENV}"
echo "export I_MPI_ASYNC_PROGRESS=0"   >> "${ENV}"
chmod a-w "${ENV}"
```

Without this patch, OpenMP regions run single-threaded and the throughput advantage is lost.

**Naming convention** (extended with binary tag):
```
with_sic__bm{BM}_w1{W1}_w2{W2}__{bin}__{period}
e.g.  with_sic__bm155_w1_99_w2_00__omph__storm_eunice_2022
      with_sic__bm155_w1_15_w2_01__p3avx2__storm_xaver_2013
```

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

**Scale**: 6 BM × 11 periods × 3 binaries = **198 experiments**.
Recommended: run `storm_eunice_2022` × all BM × all binaries first (18 jobs) to validate
cross-binary Hs agreement before scaling to all periods.

### Phase 2 — WCOR sweep (BETAMAX = BEST, OMPH binary, all periods)

| # | WCOR1 | WCOR2 | Note                        |
|---|-------|-------|-----------------------------|
| 1 | 99    | 0.0   | Re-run baseline (Phase 1 ✓) |
| 2 | 99    | 0.1   |                             |
| 3 | 99    | 0.2   |                             |
| 4 | 15.0  | 0.0   |                             |
| 5 | 15.0  | 0.1   |                             |
| 6 | 15.0  | 0.2   |                             |
| 7 | 20.0  | 0.0   |                             |
| 8 | 20.0  | 0.1   |                             |
| 9 | 20.0  | 0.2   |                             |
|10 | 25.0  | 0.0   |                             |
|11 | 25.0  | 0.1   |                             |
|12 | 25.0  | 0.2   |                             |

**Scale**: 12 WCOR combos × 11 periods (OMPH only) = **132 experiments**.
Row 1 was produced per period in Phase 1; skip or reuse as a consistency check.

---

## Prerequisites (one-time)

### 1 — Change to the HPC calibration workspace

```bash
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration
```

### 2 — Register all catalogue storm periods

bash scripts/manage_periods.sh add storm_natl_20110211 \
  --start 20110211 --end 20110212 \
  --description "North Atlantic storm, peak 38.2 m/s, merged regions: Baffin Bay + N Atlantic" \
  --tags "storm,calibration,north_atlantic,2011"

bash scripts/manage_periods.sh add storm_natl_20120311 \
  --start 20120311 --end 20120313 \
  --description "North Atlantic storm, peak 30.9 m/s" \
  --tags "storm,calibration,north_atlantic,2012"

bash scripts/manage_periods.sh add storm_iceland_20120829 \
  --start 20120829 --end 20120830 \
  --description "Iceland/Jan Mayen storm, peak 23.0 m/s, merged regions: Iceland + Norwegian Sea" \
  --tags "storm,calibration,iceland,2012"

bash scripts/manage_periods.sh add storm_arctic_20121024 \
  --start 20121024 --end 20121025 \
  --description "Arctic Ocean storm, peak 27.3 m/s" \
  --tags "storm,calibration,arctic,2012"

bash scripts/manage_periods.sh add storm_nsea_20131205 \
  --start 20131205 --end 20131206 \
  --description "North Sea storm (cf. Xaver), peak 30.2 m/s" \
  --tags "storm,calibration,north_sea,2013"

bash scripts/manage_periods.sh add storm_norsea_20140809 \
  --start 20140809 --end 20140810 \
  --description "Norwegian/North Sea storm, peak 23.2 m/s" \
  --tags "storm,calibration,norwegian_sea,2014"

bash scripts/manage_periods.sh add storm_natl_20150309 \
  --start 20150309 --end 20150313 \
  --description "North Atlantic storm, peak 30.3 m/s, 4-region merged event" \
  --tags "storm,calibration,north_atlantic,2015"

bash scripts/manage_periods.sh add storm_nsea_20160129 \
  --start 20160129 --end 20160130 \
  --description "North Sea storm, peak 29.0 m/s, 12h event" \
  --tags "storm,calibration,north_sea,2016"

bash scripts/manage_periods.sh add storm_barents_20170310 \
  --start 20170310 --end 20170312 \
  --description "Barents Sea storm, peak 28.5 m/s" \
  --tags "storm,calibration,barents_sea,2017"

bash scripts/manage_periods.sh add storm_norsea_20191021 \
  --start 20191021 --end 20191022 \
  --description "Norwegian Sea storm, peak 27.8 m/s" \
  --tags "storm,calibration,norwegian_sea,2019"

bash scripts/manage_periods.sh add storm_greenland_20200405 \
  --start 20200405 --end 20200407 \
  --description "Greenland Sea storm, peak 32.9 m/s" \
  --tags "storm,calibration,greenland_sea,2020"

bash scripts/manage_periods.sh add storm_nsea_20210310 \
  --start 20210310 --end 20210311 \
  --description "North Sea storm, peak 24.9 m/s" \
  --tags "storm,calibration,north_sea,2021"

bash scripts/manage_periods.sh add storm_nsea_20211126 \
  --start 20211126 --end 20211127 \
  --description "North Sea storm, peak 25.8 m/s" \
  --tags "storm,calibration,north_sea,2021"

bash scripts/manage_periods.sh add storm_arctic_20220122 \
  --start 20220122 --end 20220125 \
  --description "Arctic/Barents Sea merged storm, peak 30.4 m/s" \
  --tags "storm,calibration,arctic,barents_sea,2022"

bash scripts/manage_periods.sh add storm_norsea_20220320 \
  --start 20220320 --end 20220322 \
  --description "Norwegian Sea storm, peak 27.3 m/s" \
  --tags "storm,calibration,norwegian_sea,2022"

bash scripts/manage_periods.sh add storm_greenland_20230202 \
  --start 20230202 --end 20230204 \
  --description "Greenland Sea storm, peak 39.9 m/s" \
  --tags "storm,calibration,greenland_sea,2023"

bash scripts/manage_periods.sh add storm_greenland_20231121 \
  --start 20231121 --end 20231123 \
  --description "Greenland/Arctic merged storm, peak 31.5 m/s" \
  --tags "storm,calibration,greenland_sea,arctic,2023"

bash scripts/manage_periods.sh add storm_norsea_20240130 \
  --start 20240130 --end 20240201 \
  --description "Norwegian/Faroe merged storm, peak 31.0 m/s (cf. Ingunn)" \
  --tags "storm,calibration,norwegian_sea,2024"

bash scripts/manage_periods.sh add storm_norsea_20241128 \
  --start 20241128 --end 20241130 \
  --description "Norwegian/Barents merged storm, peak 28.3 m/s" \
  --tags "storm,calibration,norwegian_sea,barents_sea,2024"

bash scripts/manage_periods.sh add storm_norsea_20250206 \
  --start 20250206 --end 20250207 \
  --description "Norwegian Sea storm, peak 29.4 m/s" \
  --tags "storm,calibration,norwegian_sea,2025"

bash scripts/manage_periods.sh add storm_labrador_20250215 \
  --start 20250215 --end 20250217 \
  --description "Labrador Sea storm, peak 42.3 m/s" \
  --tags "storm,calibration,labrador_sea,2025"

bash scripts/manage_periods.sh add storm_nsea_20250804 \
  --start 20250804 --end 20250806 \
  --description "North Sea/Faroe merged storm, peak 24.4 m/s" \
  --tags "storm,calibration,north_sea,2025"

bash scripts/manage_periods.sh add storm_nsea_20251003 \
  --start 20251003 --end 20251005 \
  --description "North Sea/Faroe merged storm, peak 26.9 m/s" \
  --tags "storm,calibration,north_sea,2025"

# Verify all 23 are registered (plus storm_eunice_2022 if kept):
./scripts/manage_periods.sh list

### 3 — Verify compiled binaries

```bash
source ww3_binaries.env

for bin_path in "${REF_WW3}" "${P3AVX2_WW3}" "${OMPH_WW3}"; do
  [[ -x "${bin_path}" ]] \
    && echo "OK      ${bin_path}" \
    || echo "MISSING ${bin_path}"
done
```

---

## Phase 1 commands — BETAMAX sweep

All experiments: `MISC_WCOR1=99`, `MISC_WCOR2=0.0`. Binary and period are free dimensions.

```bash
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration

# Load all compiled binary paths (REF_WW3, P3AVX2_WW3, OMPH_WW3, CAL_DIR)
source ww3_binaries.env

GRID="CARRA2"   # optional override; if omitted in run_calibration.sh, setup.sh default is CARRA2
```

---

### Worked example — BM 1.43, OMPH binary, storm_eunice_2022

Single experiment; `run_calibration.sh` handles setup, OMPH patch, and submission in one call.

```bash
./scripts/run_calibration.sh \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -g "${GRID}" \
  -w "${OMPH_WW3}" --omph \
  -X BETAMAX=1.43 -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \
  -e with_sic__w1_99_w2_00__omph \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 --post
```

Experiment directory produced:
```
experiments/with_sic__w1_99_w2_00__omph__BETAMAX_143__storm_eunice_2022/
```

---

### Phase 1 — all BM values × all periods, per binary

Run once per binary. `--sweep` generates the Cartesian product (6 BM × 11 periods = 66 exp/binary).
When `-t` is not provided, wall time auto-scales from `PERIOD_DURATION_DAYS` in the `.period`
file using a fixed 5:1 ratio: `wall_hours = sim_days / 5` (e.g. 3 days -> `00:36:00`).
If you pass `-t`, that explicit value overrides autoscaling.

```bash
# ---- OMPH binary (fastest; run first) ----
./scripts/run_calibration.sh \
  -c configs/with_sic --all-periods \
  -g "${GRID}" \
  -w "${OMPH_WW3}" --omph \
  --sweep BETAMAX=1.33,1.43,1.50,1.55,1.65,1.75 \
  -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \
  -e with_sic__w1_99_w2_00__omph \
  -N 16 -n 60 --cpus-per-task 2 --post

# ---- p3avx2 binary ----
./scripts/run_calibration.sh \
  -c configs/with_sic --all-periods \
  -g "${GRID}" \
  -w "${P3AVX2_WW3}" \
  --sweep BETAMAX=1.33,1.43,1.50,1.55,1.65,1.75 \
  -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \
  -e with_sic__w1_99_w2_00__p3avx2 \
  -N 16 -n 69 --post

# ---- ref binary ----
./scripts/run_calibration.sh \
  -c configs/with_sic --all-periods \
  -g "${GRID}" \
  -w "${REF_WW3}" \
  --sweep BETAMAX=1.33,1.43,1.50,1.55,1.65,1.75 \
  -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \
  -e with_sic__w1_99_w2_00__ref \
  -N 16 -n 60 --post
```

Experiment naming pattern: `with_sic__w1_99_w2_00__<bin>__BETAMAX_<tag>__<period>`
e.g. `with_sic__w1_99_w2_00__omph__BETAMAX_143__storm_eunice_2022`

> **198 jobs total** (66 per binary × 3 binaries). Stagger binary submissions to stay within
> cluster queue limits.
> Recommended start: run the OMPH block with `-P storm_eunice_2022` only (6 jobs) to validate
> cross-binary Hs agreement, then release all 3 full blocks.

---

## Phase 1 — post-run evaluation

```bash
# Dashboard: all Phase 1 experiments at a glance
./scripts/scan_experiments.sh --tag calibration

# Filter to only failures / cancellations
./scripts/scan_experiments.sh --tag calibration --status FAILED,CANCELLED

# Clean up unwanted experiments interactively
./scripts/scan_experiments.sh --status FAILED,CANCELLED --clean --dry-run
./scripts/scan_experiments.sh --status FAILED,CANCELLED --clean

# Full calibration log
./scripts/manage_periods.sh log
```

**Decision gate**: Pick `BEST_BM`. Then proceed to Phase 2 with OMPH only.

---

## Phase 2 commands — WCOR sweep

OMPH binary used for all Phase 2 runs. Set `BEST_BM` from Phase 1, then dispatch the full
WCOR grid in a single call using two `--sweep` flags (Cartesian product: 4 W1 × 3 W2 = 12
combos, minus the W1=99/W2=0.0 baseline already run in Phase 1 = **11 new combos × 11 periods
= 121 experiments**).

```bash
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration

BEST_BM="1.55"           # ← replace with actual best from Phase 1
OMPH_WW3="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/p4_omph/WW3"

# -----------------------------------------------------------------------
# Full WCOR grid — 4 W1 × 3 W2 = 12 combos × 11 periods
# Add --use-groups to place experiments in a grouped layout:
#   experiments/<physics_fingerprint>/<period>/
# e.g. experiments/with_sic__bm155__omph__MISC_WCOR1_150__MISC_WCOR2_01/storm_eunice_2022/
# -----------------------------------------------------------------------
./scripts/run_calibration.sh \
  -c configs/with_sic --all-periods \
  -g "${GRID}" \
  -w "${OMPH_WW3}" --omph \
  --sweep MISC_WCOR1=99,15.0,20.0,25.0 \
  --sweep MISC_WCOR2=0.0,0.1,0.2 \
  -X BETAMAX="${BEST_BM}" \
  -e "with_sic__bm${BEST_BM//./}__omph" \
  --use-groups \
  -N 16 -n 60 --cpus-per-task 2 --post
```

With `--use-groups`, experiments for the same physics combo are collected under one
group directory — each storm period is a distinct sub-experiment. This makes it easy
to compare all periods for a given parameter combination at a glance.

Flat naming (without `--use-groups`):
`with_sic__bm155__omph__MISC_WCOR1_150__MISC_WCOR2_01__storm_xaver_2013`

Grouped naming (`--use-groups`):
`experiments/with_sic__bm155__omph__MISC_WCOR1_150__MISC_WCOR2_01/storm_xaver_2013/`

> **132 jobs** (12 WCOR combos × 11 periods). The W1=99/W2=0.0 row matches Phase 1 physics
> and can serve as a cross-check. To skip it, split into two calls: one for W1=99 with
> `--sweep MISC_WCOR2=0.1,0.2`, and one for `--sweep MISC_WCOR1=15.0,20.0,25.0`.

---

## Monitoring

```bash
# Dashboard: all calibration experiments at a glance (colour-coded table)
./scripts/scan_experiments.sh --tag calibration

# Filter to failures / cancellations only
./scripts/scan_experiments.sh --tag calibration --status FAILED,CANCELLED

# Interactively remove failed/cancelled experiments
./scripts/scan_experiments.sh --status FAILED,CANCELLED --clean --dry-run  # preview
./scripts/scan_experiments.sh --status FAILED,CANCELLED --clean             # confirm

# Detailed single-experiment inspection
./scripts/check_exp.sh -e <exp_name>

# Full calibration log
./scripts/manage_periods.sh log

# Quick CSV summary
column -t -s',' periods/calibration_log.csv | grep with_sic
```

---

## Rerunning cancelled or incomplete experiments

Use `--rerun` instead of deleting the experiment directory and starting over.
`run_calibration.sh` will clean partial outputs and resubmit without re-running setup.

**What `--rerun` does:**
- Skips `setup.sh` — namelists, symlinks, and env.sh are left untouched
- Deletes output files from `work/`: non-symlink `*.nc`, `out_grd.ww3`, `test001.ww3`, `log.ww3`
- Keeps preprocessing outputs (`mod_def.ww3`, `wind.ww3`, `ice.ww3`) — add `-s` to skip prep
- With `--omph`: checks for `WW3_OMP_THREADS=2` in `env.sh` and applies it only if missing

```bash
source ww3_binaries.env

# Rerun a single period with the same layout
./scripts/run_calibration.sh \
  -c configs/with_sic -P storm_eunice_2022 \
  -e with_sic__w1_99_w2_00__omph \
  --rerun --omph \
  -N 16 -n 60 --cpus-per-task 2 --post

# Rerun skipping preprocessing (prep outputs already in work/)
./scripts/run_calibration.sh \
  -c configs/with_sic -P storm_eunice_2022 \
  -e with_sic__w1_99_w2_00__omph \
  --rerun --omph -s \
  -N 16 -n 60 --cpus-per-task 2 --post

# Rerun all periods for a sweep combo (e.g. after cluster maintenance)
./scripts/run_calibration.sh \
  -c configs/with_sic --all-periods \
  -e with_sic__w1_99_w2_00__omph \
  --sweep BETAMAX=1.55 \
  --rerun --omph \
  -N 16 -n 60 --cpus-per-task 2 --post

# Scaling experiment: rerun with a different node layout (no setup, no clean needed)
./scripts/run_calibration.sh \
  -c configs/with_sic -P storm_eunice_2022 \
  -e with_sic__w1_99_w2_00__omph \
  --rerun --omph \
  -N 8 -n 60 --cpus-per-task 2 -t 00:40:00 --post
```

---

## Notes

- The `with_sic` config activates all three forcings: wind, sea-ice concentration
  (`ww3_prnc_ice.nml.sic`), and sea-ice thickness — making it the physically richest config
  for marginal-ice-zone calibration.
- All parameter overrides (`-X`) substitute `{{KEY}}` tokens in namelists at setup time;
  no `.nml` file is ever edited manually.
- **OMPH env.sh patch is mandatory**: without `WW3_OMP_THREADS=2`, OpenMP regions run
  single-threaded per MPI rank, negating the throughput gain. Pass `--omph` to
  `run_calibration.sh` and it is applied automatically after every `setup.sh` call.
  When running `setup.sh` + `run_exp.sh` manually, apply the patch by hand:
  ```bash
  ENV="experiments/${EXP}/metadata/setup/env.sh"
  chmod u+w "${ENV}"
  echo "export WW3_OMP_THREADS=2"      >> "${ENV}"
  echo "export I_MPI_ASYNC_PROGRESS=0" >> "${ENV}"
  chmod a-w "${ENV}"
  ```
- **Binary cross-check**: physics must be identical across `ref`, `p3avx2`, and `omph`.
  Fast-math (`-fp-model fast=2`) and AVX widening introduce rounding differences typically
  < 10⁻⁶ relative in Hs. Flag anything > 10⁻⁴ as a compilation regression to investigate.
- **Wall time scaling**: `run_calibration.sh` auto-sets `-t` from `PERIOD_DURATION_DAYS` when
  `-t` is not explicitly provided, using `wall_hours = sim_days / 5`.
  For a 3-day storm this yields `00:36:00`.
  To force binary-specific limits (for example `omph` 20 min), pass `-t` explicitly.
- When additional storm periods become available, add their names to the `PERIODS` arrays —
  the loops, wall-time scaling, and registration commands all work automatically.

