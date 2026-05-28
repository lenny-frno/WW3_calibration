---
name: claude-skill-change-routine
description: "MANDATORY after any file edit in this workspace. Covers syntax checks, dependent file review, documentation update, version bumping, and repo memory update. Triggers on: any code change, script edit, config edit, namelist change, or documentation update request."
---

# Change Routine Skill — WW3 Workspace

This skill defines the complete post-edit procedure every agent must follow after modifying
any file in the WW3 benchmark/calibration workspace. It is complementary to the always-on
checklist in `.github/copilot-instructions.md`; this file provides the full detail.

---

## Step 0 — Cleanup (after any test or diagnostic work)

Whenever the agent creates temporary files, test scripts, auxiliary LaTeX files, or
intermediate artefacts during diagnosis or problem-solving, they **must be deleted** once
the mission is complete — before reporting "done".

### What to clean up

| Artefact type | Examples | How to remove |
|---|---|---|
| LaTeX auxiliary files | `*.aux`, `*.nav`, `*.snm`, `*.toc`, `*.vrb`, `*.out`, `*.log` | `rm -f <basename>.{aux,nav,snm,toc,vrb,out,log}` |
| Test / scratch scripts | `test_hpc.tex`, `test_part1.sh`, `scratch_*.sh` | `rm -f <file>` |
| Test compiled output | `test_hpc.pdf`, `test_part1.pdf` and their `.log`/`.out` | `rm -f <file>` |
| Temporary data files | `*.tmp`, `tmp_*`, `debug_*` | `rm -f <file>` |
| Intermediate build files | `*.o`, `*.mod` left in source tree | `rm -f <file>` |

### Rules

1. **Scan before reporting done**: after any session involving test/debug work, check the
   working directory (and any subdirectory touched) for leftover artefacts.
2. **Never delete user files**: only remove files the agent itself created during the
   current session. When in doubt, ask.
3. **LaTeX**: always remove auxiliary files (`*.aux`, `*.nav`, `*.snm`, `*.toc`, `*.vrb`)
   after a successful compilation — they are reproducible and clutter the repo.
4. **Test scripts**: any `.sh`, `.tex`, `.py`, or other file with a name starting with
   `test_`, `tmp_`, `scratch_`, or `debug_` that the agent created should be removed.
5. **PDF proofs**: intermediate PDF compilations used only to verify a fix should be
   removed; the final PDF (if it is the deliverable) must be kept.

```bash
# Example: clean LaTeX auxiliaries after a presentation build
rm -f docs/presentation.{aux,nav,snm,toc,vrb,out}

# Example: clean leftover test files
rm -f docs/test_hpc*.{aux,nav,snm,toc} docs/test_part1.{aux,nav,snm,toc}
```

---

## Step 1 — Syntax check

Run immediately after editing any `.sh` file, before doing anything else.

```bash
bash -n <modified_file>.sh && echo "OK"
```

If it fails, fix the syntax error before proceeding. Do not report the change as done until
this passes.

**Also check**: if the file sources another script (`source x.sh` or `. x.sh`), syntax-check
that one too.

---

## Step 2 — Dependency scan

Search the entire repo for references to the modified file's name and any changed
flags/subcommands. This tells you what else needs updating.

```bash
# Find all files that reference the modified script
grep -r "run_calibration\|setup\.sh\|run_exp\|manage_periods" --include="*.md" --include="*.sh" --include="*.prompt.md" -l

# Find all uses of a changed flag or subcommand
grep -r "\-\-sweep\|--omph\|-X " --include="*.md" -n
```

Use the **Dependency map** in `.github/copilot-instructions.md` as the authoritative list
of what to check for each file type. Do not skip any entry in the map.

---

## Step 3 — Interface change detection

For each modified script, determine if its **external interface** changed:

| Interface element | Examples |
|---|---|
| New CLI flag added | `--sweep`, `--omph`, `-w` |
| Flag renamed or removed | `-B` → removed |
| New subcommand | `manage_periods.sh help` |
| Output format changed | new column in `list`, changed exp naming pattern |
| New period file field | `SPINUP_DAYS` added to `.period` format |
| New token in namelist | `{{ANALYSIS_START}}` added |

If ANY interface element changed → proceed to Steps 4 + 5 (docs + version).  
If only internal logic changed (no visible user-facing change) → Step 6 is sufficient.

---

## Step 4 — Dependency map lookup

Before touching any documentation, look up the modified file in the map below to get
the exact list of files to check. Do not rely on memory — consult the map.

### Scripts

| File modified | Must also review / update |
|---|---|
| `scripts/setup.sh` | `scripts/run_calibration.sh`, `scripts/run_exp.sh`, `docs/calibration_plan.md`, `docs/recipe_calibration.md`, `README.md`, `.github/prompts/calibration_experiments.prompt.md` |
| `scripts/run_exp.sh` | `scripts/run_calibration.sh`, `docs/calibration_plan.md`, `docs/recipe_calibration.md`, `README.md` |
| `scripts/run_calibration.sh` | `docs/calibration_plan.md`, `.github/prompts/calibration_experiments.prompt.md` |
| `scripts/manage_periods.sh` | `docs/calibration_plan.md`, `docs/recipe_calibration.md` |
| `scripts/check_exp.sh` | `docs/calibration_plan.md` (monitoring section), `README.md` |
| `jobs/prep.job` | `scripts/run_exp.sh`, `docs/recipe_calibration.md` |
| `jobs/run_shel.job` | `scripts/run_exp.sh`, `docs/calibration_plan.md` |
| `jobs/post.job` | `scripts/run_exp.sh` |

### Configs & namelists

| File modified | Must also review / update |
|---|---|
| `configs/nml_files_template/params.env` | All `configs/<name>/params.env` (same key may need adding), `docs/recipe_calibration.md` |
| `configs/<name>/params.env` | `docs/calibration_plan.md` if default param values changed |
| `configs/nml_files_template/*.nml` | Corresponding `configs/<name>/*.nml` (token changes must stay in sync) |
| `configs/<name>/*.nml` | `configs/nml_files_template/*.nml` (verify template remains canonical) |
| `configs/manage_config.sh` | `README.md`, `docs/recipe_calibration.md` |

### Documentation

| File modified | Must also review / update |
|---|---|
| `docs/calibration_plan.md` | Verify all commands match current `scripts/` interfaces |
| `docs/recipe_calibration.md` | Verify steps match current `scripts/` and `configs/` |
| `.github/prompts/calibration_experiments.prompt.md` | Verify file paths and flags still valid |
| `README.md` | Verify directory structure section is accurate |

### Periods

| File modified | Must also review / update |
|---|---|
| `periods/<name>.period` | `periods/calibration_log.csv` if run history affected |
| Add/remove `.period` file | `docs/calibration_plan.md` storm table |

---

## Step 5 — Explore review (for interface changes)

After identifying which `.md` files need updating (Step 4) but **before** making edits,
use the Explore subagent to do a targeted sweep of those files. This catches stale
command examples and mismatched patterns that a quick grep would miss.

```
runSubagent(Explore):
  "Review the following files for any command examples, flag references, or glob patterns
   that are inconsistent with the current interface of <modified_file>. Changed interface:
   <describe what changed>. Files to check: <list from dependency map>.
   Report each stale line with file path + line number + suggested fix. Thoroughness: thorough."
```

**When to invoke Explore:**
- CLI interface changed (new/removed/renamed flag, new subcommand)
- Experiment naming pattern changed
- New token added to substitution system (`{{KEY}}`)
- Any change that propagates to monitoring glob patterns

**When Explore is not needed:**
- Internal logic change with no user-facing effect
- Fixing a bug in existing behaviour (same interface)
- Updating a single `.md` file directly

Review Explore's report, confirm the list of stale locations, then proceed to Step 6.

---

## Step 6 — Documentation update

For each file identified in Steps 4 + 5, make ALL necessary updates:

### What to look for in `.md` files

- **Command examples** — update flags, option names, argument order.
- **Experiment naming patterns** — if exp names changed, update all glob patterns in
  monitoring sections to match the new naming.
- **Tables** — new flags → new rows; removed flags → remove rows.
- **Step counts** — if a 2-step flow became 3-step, update ordinals (`[1/2]` → `[1/3]`).
- **Notes** — any "you must manually do X" notes that are now automated should be revised.
- **Prompt files** — `.prompt.md` agent context must list correct flags and file paths.

### Priority order

1. `docs/calibration_plan.md` — highest churn; most command examples
2. `docs/recipe_calibration.md` — workflow steps
3. `README.md` — directory structure, script list
4. `.github/prompts/calibration_experiments.prompt.md` — context the agent reads
5. `docs/recipe_benchmarking.md` / `docs/recipe_scaling.md` — if benchmarking scripts changed

---

## Step 7 — Version bump

In the modified script's header, increment the version if the CLI interface changed:

```bash
# Minor change (new optional flag, new optional output column):
VERSION="1.0" → VERSION="1.1"

# Major change (required flag added, output format breaking change, new mandatory step):
VERSION="1.1" → VERSION="2.0"
```

Also update any version reference in `README.md` if it lists version numbers.

---

## Step 8 — Repo memory update

After any session where a new pattern, convention, or "gotcha" was discovered, record it in
`/memories/repo/ww3_compilation.md`. This file persists across sessions and is read at the
start of future conversations.

**When to add a memory:**
- A previously unknown dependency was discovered (e.g., "prep.job overwrites ww3_prnc.nml
  with ww3_prnc_wind.nml")
- A bash quirk caused a bug (e.g., "`local` is invalid at top level; setup.sh runs at
  top level so must use plain assignment")
- A new best practice was established for this codebase
- User corrected the agent on something important

**Format for new entries:**

```markdown
## <Category>
- **<Short label>**: <Concise fact>. Discovered: <date or context>.
```

---

## Step 9 — Final response

After completing all steps, end your response with a compact **Change summary block**:

```
### Changes made
- `scripts/run_calibration.sh` v1.0→1.1: added -w, -X, --sweep, --omph flags
- `docs/calibration_plan.md`: Phase 1 + Phase 2 commands updated; monitoring globs updated
- `docs/calibration_plan.md`: Notes section updated (--omph now automatic)
- Syntax check: OK
- Dependents reviewed: run_calibration.sh → setup.sh ✓, run_exp.sh ✓, prompt.md ✓
- Explore review: 2 stale lines found and fixed in calibration_plan.md
```

This block makes it easy for the user to see at a glance that the full routine was followed
and gives them a changelog ready to copy into a commit message.

---

## Codebase-specific gotchas

These are known traps that have caused bugs; check for them whenever editing related code:

| Area | Gotcha |
|---|---|
| `setup.sh` | Runs at top level — `local` keyword is invalid outside of functions |
| `setup.sh` sed loop | `2>/dev/null \|\| true` silently hides substitution errors — we replaced this with explicit error reporting + unresolved `{{...}}` scan |
| `run_shel.job` | Copies `ww3_shel_Xd.nml` over `ww3_shel.nml` if it exists; could overwrite substituted dates. With numeric `PERIOD_DURATION_DAYS`, falls back to existing `ww3_shel.nml` (correct but fragile) |
| `prep.job` | Copies `ww3_prnc_wind.nml` → `ww3_prnc.nml` before running wind prnc. Undocumented — any `.nml` named `ww3_prnc.nml` in `work/` gets overwritten |
| `manage_periods.sh` | `local -n` (nameref) used in `build_combos`; requires bash ≥ 4.3 |
| Forcing symlinks | `setup.sh` links `wind.nc` and `ice.nc` for `YEAR/MONTH` of period START. Spin-up crossing month boundary breaks this — there is a warning but no auto-fix |
| AMD EPYC 9005 | `-xHost` and all `-x<ISA>` flags → Intel CPUID dispatch → SSE2 fallback. Always use `-m<isa>` |
| `run_calibration.sh --sweep` | Value tag strips dots: `1.43→143`, `15.0→150`. Monitoring globs must use the stripped form |
