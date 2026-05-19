---
mode: 'agent'
tools: ['codebase', 'editFiles', 'readFile', 'findFiles']
description: 'Generate WW3 calibration experiment commands (BETAMAX + WCOR1/2) with all forcings, across multiple storm periods'
---

# Task: Plan and generate WW3 calibration experiment commands

You are working in the WW3 benchmarking and calibration workspace at
`/home/lehuc2580/work/WW3/WW3_compilation`.

## What you must produce

Create a file `docs/calibration_plan.md` containing:

1. **Knowledge section** — explain what BETAMAX, WCOR1 and WCOR2 do physically (see template below).
2. **Experiment matrix** — all parameter combinations to run.
3. **Step-by-step commands** tailored to this codebase, copy-pasteable on the HPC.

---

## Context you must read first

Read these files before generating any commands:

| File | Purpose |
|------|---------|
| `scripts/setup.sh` | Understand `-e`, `-c`, `-P`, `-X KEY=VALUE` flags |
| `scripts/run_exp.sh` | Understand `-N`, `-n`, `--cpus-per-task`, `-d`, `--post` |
| `scripts/run_calibration.sh` | Multi-period dispatch |
| `configs/with_sic/params.env` | Current baseline parameter values |
| `configs/with_sic/namelist.nml` | Placeholders confirmed: `{{BETAMAX}}`, `{{MISC_WCOR1}}`, `{{MISC_WCOR2}}` |
| `docs/recipe_calibration.md` | Full calibration recipe |
| `periods/` (list all `.period` files) | Available storm periods |

Key facts:
- **Config to use**: `configs/with_sic` — this is the only config that activates all three forcings: wind, sea-ice concentration (`ww3_prnc_ice.nml.sic`) and sea-ice thickness (`ww3_prnc_ice.nml.thick`).
- **HPC run path**: `/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration/`
- **Parameter overrides** use `setup.sh -X KEY=VALUE` which substitutes `{{KEY}}` in all namelists — no file editing needed.
- **Best binary**: the OMPH compilation at `…/compilation_Benchmark/models/p4_omph/WW3` (if not yet built, fall back to `from_waveXtrems`).

---

## Parameter ranges to sweep

Generate one experiment per combination:

| Parameter | Baseline | Values to test |
|-----------|----------|----------------|
| `BETAMAX` | 1.43 | 1.33, 1.43, 1.50, 1.55, 1.65, 1.75 |
| `MISC_WCOR1` | 99 | 99 (off), 15.0, 20.0, 25.0 |
| `MISC_WCOR2` | 0.0 | 0.0, 0.1, 0.2 |

Run the full BETAMAX sweep first (WCOR1=99, WCOR2=0.0 held constant).
Then run the WCOR sweep with the best BETAMAX found.

---

## Knowledge section template (fill in accurately)

Include this section verbatim in `docs/calibration_plan.md`, filled in:

```
## Parameter knowledge

### BETAMAX
- Namelist: `&SIN4`
- WW3 physics package: ST4 (Ardhuin et al. 2010, J. Phys. Oceanogr.)
- Physical meaning: …
- Effect on model output: …
- Tuning guidance: …

### WCOR1 (MISC%WCOR1)
- Namelist: `&MISC`
- Physical meaning: …
- Effect: …
- Value 99: …

### WCOR2 (MISC%WCOR2)
- Namelist: `&MISC`
- Physical meaning: …
- Effect: …
```

---

## Required output format for commands

For each experiment, emit a block like:

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

Use a consistent experiment naming scheme: `with_sic__bm{BM}_w1{W1}_w2{W2}__{period}`.
Run across all storm periods found in `periods/`.
