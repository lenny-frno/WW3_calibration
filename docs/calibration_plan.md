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

11 storm periods available for calibration. `storm_eunice_2022` is pre-registered; the
remaining 10 are registered in §Prerequisites.

| # | Period name | Start | End | Basin | Peak gust | Days |
|---|-------------|-------|-----|-------|-----------|------|
| 0 | `storm_eunice_2022` ✓ | 2022-02-18 | 2022-02-21 | North Sea | — | 3 |
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

---

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

`storm_eunice_2022` is already registered. Paste to add the remaining 10:

```bash
bash scripts/manage_periods.sh add storm_berit_2011 \
  --start 20111122 --end 20111129 \
  --description "Cyclone Berit: extreme windstorm over Norwegian Sea/Faroe Islands, 944 hPa, gusts ~51 m/s" \
  --tags "storm,calibration,norwegian_sea,bft12,2011"

bash scripts/manage_periods.sh add storm_friedhelm_2011 \
  --start 20111208 --end 20111213 \
  --description "Cyclone Friedhelm (Hurricane Bawbag): powerful North Sea windstorm, 956 hPa, gusts ~47 m/s" \
  --tags "storm,calibration,north_sea,bft12,2011"

bash scripts/manage_periods.sh add storm_dagmar_2011 \
  --start 20111224 --end 20111228 \
  --description "Cyclone Dagmar (Patrick/Tapani): Christmas 2011, Norwegian coast landfall, 956 hPa, 44 m/s sustained" \
  --tags "storm,calibration,norwegian_sea,bft12,2011"

bash scripts/manage_periods.sh add storm_hilde_2013 \
  --start 20131113 --end 20131119 \
  --description "Storm Hilde: extreme weather warning Norway, Norwegian Sea, 971 hPa, gusts ~45 m/s" \
  --tags "storm,calibration,norwegian_sea,bft12,2013"

bash scripts/manage_periods.sh add storm_xaver_2013 \
  --start 20131204 --end 20131211 \
  --description "Cyclone Xaver: most serious North Sea storm surge in 60 years, 962 hPa, Force 12" \
  --tags "storm,calibration,north_sea,norwegian_sea,bft12,2013"

bash scripts/manage_periods.sh add storm_ciara_2020 \
  --start 20200208 --end 20200213 \
  --description "Storm Ciara (Sabine/Elsa): Norwegian Sea/North Sea, 943 hPa, gusts ~49 m/s Lofoten" \
  --tags "storm,calibration,norwegian_sea,north_sea,bft12,2020"

bash scripts/manage_periods.sh add storm_dennis_2020 \
  --start 20200213 --end 20200218 \
  --description "Storm Dennis (Victoria): 920 hPa, among deepest N Atlantic extratropical cyclones on record" \
  --tags "storm,calibration,norwegian_sea,north_sea,bft12,2020"

bash scripts/manage_periods.sh add storm_malik_2022 \
  --start 20220128 --end 20220131 \
  --description "Storm Malik: North Sea/Norwegian Sea, 965 hPa, gusts ~54 m/s (196 km/h)" \
  --tags "storm,calibration,north_sea,norwegian_sea,bft12,2022"

bash scripts/manage_periods.sh add storm_ingunn_2024 \
  --start 20240130 --end 20240202 \
  --description "Storm Ingunn (Margrit): 941 hPa, strongest Norway storm in 30 yrs, gusts 249 km/h Faroes" \
  --tags "storm,calibration,norwegian_sea,bft12,2024"

bash scripts/manage_periods.sh add storm_eowyn_2025 \
  --start 20250121 --end 20250127 \
  --description "Storm Eowyn (Gilles): 941.9 hPa, powerful Norwegian Sea system, Bft 12, Jan 2025" \
  --tags "storm,calibration,norwegian_sea,bft12,2025"

# Verify all 11 are registered:
./scripts/manage_periods.sh list
```

### 3 — Verify compiled binaries

```bash
BASE="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models"
REF_WW3="/home/sm_lenal/programs/compiling/from_waveXtrems/WW3"
P3AVX2_WW3="${BASE}/p3_fp2_ipo_unroll_avx2_nd/WW3"
OMPH_WW3="${BASE}/p4_omph/WW3"

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
```

---

### Worked example — BM 1.43, OMPH binary, storm_eunice_2022

Full three-step sequence including the mandatory OMPH env patch.
For `p3avx2` or `ref`: skip step 2 (no patch needed) and adjust `-n`/`-t` per the binary table.

```bash
BASE_MODELS="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models"
OMPH_WW3="${BASE_MODELS}/p4_omph/WW3"
EXP="with_sic__bm143_w1_99_w2_00__omph__storm_eunice_2022"

# 1. Setup — substitutes dates, params, copies namelists
./scripts/setup.sh \
  -e "${EXP}" \
  -c configs/with_sic \
  -P storm_eunice_2022 \
  -w "${OMPH_WW3}" \
  -X BETAMAX=1.43 \
  -X MISC_WCOR1=99 \
  -X MISC_WCOR2=0.0 \
  -t "calibration,sic,betamax,wcor,omph"

# 2. Inject OpenMP settings — REQUIRED for OMPH binary
ENV="experiments/${EXP}/metadata/setup/env.sh"
chmod u+w "${ENV}"
echo "export WW3_OMP_THREADS=2"        >> "${ENV}"
echo "export I_MPI_ASYNC_PROGRESS=0"   >> "${ENV}"
chmod a-w "${ENV}"

# 3. Submit to Slurm
./scripts/run_exp.sh \
  -e "${EXP}" \
  -N 16 -n 60 --cpus-per-task 2 -t 00:20:00 -d 3d --post
```

---

### Phase 1 — master loop (all binaries × all periods × all BM values)

```bash
# -----------------------------------------------------------------------
# Binary paths
# -----------------------------------------------------------------------
BASE_MODELS="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models"
REF_WW3="/home/sm_lenal/programs/compiling/from_waveXtrems/WW3"
P3AVX2_WW3="${BASE_MODELS}/p3_fp2_ipo_unroll_avx2_nd/WW3"
OMPH_WW3="${BASE_MODELS}/p4_omph/WW3"

PERIODS=(storm_eunice_2022 storm_berit_2011 storm_friedhelm_2011 storm_dagmar_2011
         storm_hilde_2013 storm_xaver_2013 storm_ciara_2020 storm_dennis_2020
         storm_malik_2022 storm_ingunn_2024 storm_eowyn_2025)

# -----------------------------------------------------------------------
# Loop — 6 BM × 11 periods × 3 binaries = 198 experiments
# -----------------------------------------------------------------------
for PERIOD in "${PERIODS[@]}"; do
  source "periods/${PERIOD}.period"           # sets PERIOD_DURATION_DAYS

  for BM in 1.33 1.43 1.50 1.55 1.65 1.75; do
    BM_TAG="${BM//./}"                         # 1.43 → 143

    for BIN in ref p3avx2 omph; do
      case "${BIN}" in
        ref)
          BIN_WW3="${REF_WW3}"
          RUN_ARGS=(-N 16 -n 60)
          MINS_PER_DAY=60                      # ~45 min for 3-day storm
          ;;
        p3avx2)
          BIN_WW3="${P3AVX2_WW3}"
          RUN_ARGS=(-N 16 -n 69)
          MINS_PER_DAY=60                      # ~30 min for 3-day storm
          ;;
        omph)
          BIN_WW3="${OMPH_WW3}"
          RUN_ARGS=(-N 16 -n 60 --cpus-per-task 2)
          MINS_PER_DAY=40                       # ~20 min for 3-day storm
          ;;
      esac

      # Scale wall time to storm duration (+ 10 min buffer)
      WALL_MIN=$(( PERIOD_DURATION_DAYS * MINS_PER_DAY + 10 ))
      WALL=$(printf "%02d:%02d:00" $(( WALL_MIN / 60 )) $(( WALL_MIN % 60 )))

      EXP="with_sic__bm${BM_TAG}_w1_99_w2_00__${BIN}__${PERIOD}"

      ./scripts/setup.sh \
        -e "${EXP}" \
        -c configs/with_sic \
        -P "${PERIOD}" \
        -w "${BIN_WW3}" \
        -X BETAMAX="${BM}" \
        -X MISC_WCOR1=99 \
        -X MISC_WCOR2=0.0 \
        -t "calibration,sic,betamax,wcor,${BIN}"\
        --force

      # OMPH binary requires OpenMP thread count injected into env.sh
      if [[ "${BIN}" == "omph" ]]; then
        ENV="experiments/${EXP}/metadata/setup/env.sh"
        chmod u+w "${ENV}"
        echo "export WW3_OMP_THREADS=2"        >> "${ENV}"
        echo "export I_MPI_ASYNC_PROGRESS=0"   >> "${ENV}"
        chmod a-w "${ENV}"
      fi

      ./scripts/run_exp.sh \
        -e "${EXP}" \
        "${RUN_ARGS[@]}" -t "${WALL}" -d "${PERIOD_DURATION_DAYS}d" --post
    done
  done
done
```

> **198 jobs total.** Stagger submissions to stay within cluster queue limits.
> Recommended start: `storm_eunice_2022` alone first (18 jobs: 6 BM × 3 binaries) — verify
> cross-binary Hs agreement before scaling to all periods.

---

## Phase 1 — post-run evaluation

```bash
# Status — grouped by binary
for BIN in ref p3avx2 omph; do
  echo "=== Binary: ${BIN} ==="
  for d in experiments/with_sic__bm*_w1_99_w2_00__${BIN}__*; do
    exp=$(basename "${d}")
    printf "  %-70s  " "${exp}"
    ./scripts/check_exp.sh "${exp}" 2>/dev/null | grep -E "WW3 status|Elapsed" || echo "(no info)"
  done
done

# Full calibration log
./scripts/manage_periods.sh log
```

**Decision gate**: Pick `BEST_BM`. Then proceed to Phase 2 with OMPH only.

---

## Phase 2 commands — WCOR sweep

OMPH binary used for all Phase 2 runs.

```bash
# -----------------------------------------------------------------------
# Set this from Phase 1 results
# -----------------------------------------------------------------------
BEST_BM="1.55"           # ← replace with actual best from Phase 1
BM_TAG="${BEST_BM//./}"
OMPH_WW3="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models/p4_omph/WW3"

PERIODS=(storm_eunice_2022 storm_berit_2011 storm_friedhelm_2011 storm_dagmar_2011
         storm_hilde_2013 storm_xaver_2013 storm_ciara_2020 storm_dennis_2020
         storm_malik_2022 storm_ingunn_2024 storm_eowyn_2025)

# -----------------------------------------------------------------------
# Loop — 12 WCOR combos × 11 periods = 132 experiments
# -----------------------------------------------------------------------
for PERIOD in "${PERIODS[@]}"; do
  source "periods/${PERIOD}.period"

  # Scale wall time for OMPH: ~7 min/day + 10 min buffer
  WALL_MIN=$(( PERIOD_DURATION_DAYS * 7 + 10 ))
  WALL=$(printf "%02d:%02d:00" $(( WALL_MIN / 60 )) $(( WALL_MIN % 60 )))

  for W1 in 99 15.0 20.0 25.0; do
    W1_TAG="${W1%%.*}"                         # 15.0 → 15, 99 → 99
    for W2 in 0.0 0.1 0.2; do
      # Skip Phase 1 repeat (already run)
      [[ "${W1}" == "99" && "${W2}" == "0.0" ]] && continue

      W2_TAG=$(printf "%s" "${W2}" | sed 's/0\.\([0-9]\)/0\1/; s/0\.0/00/')
      EXP="with_sic__bm${BM_TAG}_w1_${W1_TAG}_w2_${W2_TAG}__omph__${PERIOD}"

      ./scripts/setup.sh \
        -e "${EXP}" \
        -c configs/with_sic \
        -P "${PERIOD}" \
        -w "${OMPH_WW3}" \
        -X BETAMAX="${BEST_BM}" \
        -X MISC_WCOR1="${W1}" \
        -X MISC_WCOR2="${W2}" \
        -t "calibration,sic,betamax,wcor,omph"

      ENV="experiments/${EXP}/metadata/setup/env.sh"
      chmod u+w "${ENV}"
      echo "export WW3_OMP_THREADS=2"        >> "${ENV}"
      echo "export I_MPI_ASYNC_PROGRESS=0"   >> "${ENV}"
      chmod a-w "${ENV}"

      ./scripts/run_exp.sh \
        -e "${EXP}" \
        -N 16 -n 60 --cpus-per-task 2 -t "${WALL}" \
        -d "${PERIOD_DURATION_DAYS}d" --post
    done
  done
done
```

> **132 jobs** (11 WCOR combos × 11 periods — the W1=99/W2=0.0 row is skipped as it was
> already produced in Phase 1). Remove the `&& continue` line to re-run it as a check.

---

## Monitoring

```bash
# Phase 1 — all binary / period combinations
for BIN in ref p3avx2 omph; do
  echo "=== ${BIN} ==="
  for d in experiments/with_sic__bm*_w1_99_w2_00__${BIN}__*; do
    exp=$(basename "${d}")
    printf "  %-70s  " "${exp}"
    ./scripts/check_exp.sh "${exp}" 2>/dev/null | grep -E "WW3 status|Elapsed" || echo "(no info)"
  done
done

# Phase 2 — WCOR sweep (omph only)
for d in experiments/with_sic__bm*__omph__*; do
  [[ "${d}" == *"_w1_99_w2_00"* ]] && continue   # skip Phase 1 repeats
  exp=$(basename "${d}")
  printf "%-72s  " "${exp}"
  ./scripts/check_exp.sh "${exp}" 2>/dev/null | grep -E "WW3 status|Elapsed" || echo "(no info)"
done

# Full calibration log
./scripts/manage_periods.sh log

# Quick CSV summary
column -t -s',' periods/calibration_log.csv | grep with_sic
```

---

## Notes

- The `with_sic` config activates all three forcings: wind, sea-ice concentration
  (`ww3_prnc_ice.nml.sic`), and sea-ice thickness — making it the physically richest config
  for marginal-ice-zone calibration.
- All parameter overrides (`-X`) substitute `{{KEY}}` tokens in namelists at setup time;
  no `.nml` file is ever edited manually.
- **OMPH env.sh patch is mandatory**: without `WW3_OMP_THREADS=2`, OpenMP regions run
  single-threaded per MPI rank, negating the throughput gain. Both the `-w` binary path flag
  and the env.sh append are required — neither alone is sufficient.
- **Binary cross-check**: physics must be identical across `ref`, `p3avx2`, and `omph`.
  Fast-math (`-fp-model fast=2`) and AVX widening introduce rounding differences typically
  < 10⁻⁶ relative in Hs. Flag anything > 10⁻⁴ as a compilation regression to investigate.
- **Wall time scaling**: both loops auto-scale with `PERIOD_DURATION_DAYS` sourced from the
  `.period` file. Reference values for a 3-day storm: `omph` ≈ 20 min · `p3avx2` ≈ 30 min ·
  `ref` ≈ 45 min. No manual wall-time adjustment needed when adding new periods.
- When additional storm periods become available, add their names to the `PERIODS` arrays —
  the loops, wall-time scaling, and registration commands all work automatically.

