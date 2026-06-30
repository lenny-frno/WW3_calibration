# WW3 Benchmark & Calibration Workspace — Agent Instructions

## Workspace overview

Framework for running, comparing, and logging WW3 (WaveWatch 3) ocean-wave-model experiments
on the Fahrenheit HPC cluster (AMD EPYC 9005 / Zen 4, Intel oneAPI MPI). Two workstreams:

1. **Compiler benchmarking** (`benchmarking/`) — optimising WW3 build flags for throughput.
2. **Calibration** (`configs/`, `scripts/`, `periods/`) — storm-period parameter sweeps
   (BETAMAX, WCOR1/2) using config-driven `setup.sh` / `run_calibration.sh` / `run_exp.sh`.

HPC hostname: `fahrenheit1.nsc.liu.se` | HPC user: `sm_lenal`  
HPC run path: `/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration/`  
Local dev path: `/home/lehuc2580/work/WW3/WW3_compilation/`

---

## MANDATORY CHANGE ROUTINE

**After ANY edit to a file in this repository, always complete the following steps before
responding "done".** Consult the full routine skill at:
`.claude/skills/claude-skill-change-routine/SKILL.md`

### Quick checklist (expand with the skill for details)

- [ ] **Cleanup** — delete any test scripts, scratch files, and LaTeX auxiliaries created
      during diagnosis or problem-solving (see skill Step 0).
- [ ] **Syntax check** — run `bash -n <file>` for every `.sh` file modified.
- [ ] **Dependency map** — look up the modified file in the map inside the skill; check
      every dependent file listed there.
- [ ] **Explore review** — for interface changes, invoke the Explore subagent to sweep
      dependent `.md` files for stale examples before editing them.
- [ ] **Documentation update** — update every `.md` file with stale commands, examples,
      glob patterns, or step counts referencing the changed interface.
- [ ] **Prompt/skill sync** — update any `.prompt.md` or `SKILL.md` that references the
      changed file.
- [ ] **Version bump** — increment `VERSION=` in any modified script if its CLI interface
      (flags, subcommands, output format) changed.
- [ ] **Repo memory** — if a new convention, pattern, or “gotcha” was discovered, record
      it in `/memories/repo/ww3_compilation.md`.
- [ ] **Change summary** — end the response with a compact summary block (see skill Step 9)
      ready to use as a commit message.

---

## Dependency map

Use this to know **what else to check** when a file changes.

### Scripts

| File modified | Must also review / update |
|---|---|
| `scripts/setup.sh` | `scripts/run_calibration.sh` (calls it), `scripts/run_exp.sh` (sources exp_config.sh), `docs/calibration_plan.md`, `README.md`, `docs/recipe_calibration.md`, `.github/prompts/calibration_experiments.prompt.md` |
| `scripts/run_exp.sh` | `scripts/run_calibration.sh` (calls it), `docs/calibration_plan.md`, `README.md`, `docs/recipe_calibration.md` |
| `scripts/run_calibration.sh` | `docs/calibration_plan.md` (all command examples), `.github/prompts/calibration_experiments.prompt.md` |
| `scripts/manage_periods.sh` | `docs/calibration_plan.md` (period commands), `docs/recipe_calibration.md` |
| `scripts/check_exp.sh` | `docs/calibration_plan.md` (monitoring section), `README.md` |
| `jobs/prep.job` | `scripts/run_exp.sh`, `docs/recipe_calibration.md` |
| `jobs/run_shel.job` | `scripts/run_exp.sh`, `docs/calibration_plan.md` |
| `jobs/post.job` | `scripts/run_exp.sh` |

### Configs & namelists

| File modified | Must also review / update |
|---|---|
| `configs/nml_files_template/params.env` | All `configs/<name>/params.env` (may need same key added), `docs/recipe_calibration.md` |
| `configs/<name>/params.env` | `docs/calibration_plan.md` if default param values changed |
| `configs/nml_files_template/*.nml` | Corresponding `configs/<name>/*.nml` (token changes must stay in sync) |
| `configs/<name>/*.nml` | `configs/nml_files_template/*.nml` (verify template is still canonical) |
| `configs/manage_config.sh` | `README.md`, `docs/recipe_calibration.md` |

### Documentation

| File modified | Must also review / update |
|---|---|
| `docs/calibration_plan.md` | Verify all commands match current `scripts/` interfaces |
| `docs/recipe_calibration.md` | Verify steps match current `scripts/` and `configs/` |
| `.github/prompts/calibration_experiments.prompt.md` | Verify file paths and flags still valid |
| `README.md` | Verify directory structure section is accurate |
| `docs/validation_plan.md` | `ppi_setup/docs/ww3_validation_plan.md` (re-scp to PPI), `ppi_setup/.github/copilot-instructions.md` (interface contract section), `.github/prompts/validation.prompt.md` |
| `ppi_setup/.github/copilot-instructions.md` | `docs/validation_plan.md` §10 (staging section) |
| `configs/nml_files_template/params.env` (`OUTPUT_FIELDS`) | `docs/validation_plan.md` §3.1 output spec, `.github/prompts/validation.prompt.md` |

### Periods

| File modified | Must also review / update |
|---|---|
| `periods/<name>.period` | `periods/calibration_log.csv` if run history is affected |
| Add/remove `.period` file | `docs/calibration_plan.md` storm table |

---

## Key codebase facts (always true)

- **Token substitution**: `setup.sh` replaces `{{KEY}}` tokens in `.nml` files at setup time.
  Keys come from: period file → `params.env` → `-X` CLI overrides (highest priority).
- **OMPH binary requires env.sh patch**: `WW3_OMP_THREADS=2` + `I_MPI_ASYNC_PROGRESS=0`
  must be appended to `metadata/setup/env.sh`. `run_calibration.sh --omph` does this automatically.
- **Spin-up**: `SPINUP_DAYS` in `.period` files shifts `START_DATE` backward. `ANALYSIS_START`
  preserves the original date for reference.
- **AMD EPYC 9005**: NEVER use `-x<ISA>` Intel flags (CPUID dispatch → SSE2 fallback).
  Always use `-m<isa>` (e.g., `-mavx2 -mfma`).
- **No `local` at top level in bash**: setup.sh runs at top level — `local` is only valid
  inside functions.

---

## Communication style

- After completing a code change: briefly state what was changed AND what dependent files
  were checked/updated.
- Never say "done" without having completed the change checklist above.
- When the user asks to "modify X", treat it as implicit permission to also update all docs
  and dependent files that reference X — do not ask for separate approval for those updates.
