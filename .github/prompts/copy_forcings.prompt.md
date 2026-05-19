---
mode: 'agent'
tools: ['codebase', 'editFiles', 'readFile']
description: 'Integrate ppi→Fahrenheit forcing file copy into setup.sh step [4/7] — copies and renames files from ppi if missing in DATA_DIR'
---

# Task: Integrate ppi forcing-file copy into `scripts/setup.sh`

You are working in the WW3 calibration workspace at
`/home/lehuc2580/work/WW3/WW3_compilation`.

## What you must do

Edit **`scripts/setup.sh`** to add automatic copy-from-ppi logic inside the existing
`[4/7] Linking forcing files` section. When a forcing file does not yet exist in the
local `DATA_DIR` on Fahrenheit, the script should copy it from `ppi` before creating the symlink.

---

## Context — read these files first

- `scripts/setup.sh` — full file; the target section is `[4/7] Linking forcing files`
- Understand the variables already in scope: `YEAR`, `MONTH`, `DATA_DIR`, `WORK_DIR`, `DRY_RUN`, `run()`

---

## Key facts

### Paths

| Side | Wind file | Ice file |
|------|-----------|----------|
| **ppi (source)** | `/lustre/storeB/project/fou/om/EuInterchange/WW3_hindcast/data/${YEAR}/${MONTH}/${YEAR}_${MONTH}_CARRA2_wind.nc` | same dir, `…_CARRA2_ice.nc` |
| **Fahrenheit DATA_DIR (dest)** | `${DATA_DIR}/${YEAR}_${MONTH}_wind.nc` | `${DATA_DIR}/${YEAR}_${MONTH}_ice.nc` |

Note the rename: the `_CARRA2` component is **removed** from the filename on arrival.

### ppi hostname

Add a variable near the top of the Defaults block:
```bash
PPI_HOST="ppi"                      # hostname of source HPC (must be in ~/.ssh/config)
PPI_FORCING_BASE="/lustre/storeB/project/fou/om/EuInterchange/WW3_hindcast/data"
```

These should be placed alongside the other path defaults (`DATA_ROOT`, etc.) so they are easy to override.

---

## Logic to implement

Replace the existing `[4/7]` block with the following logic for **each** of the two forcing files (wind and ice):

```
1. If DATA_DIR does not exist → mkdir -p DATA_DIR
2. If the destination file already exists → symlink directly (existing behaviour)
3. If the destination file does NOT exist:
   a. Print: "Forcing file not found locally — attempting copy from ppi..."
   b. If DRY_RUN=true → print the scp command, skip execution, proceed to symlink with a warning
   c. Otherwise: run scp ppi→local, renaming on arrival
      - scp "${PPI_HOST}:${PPI_FORCING_BASE}/${YEAR}/${MONTH}/${YEAR}_${MONTH}_CARRA2_<type>.nc" \
            "${WIND_SRC}"   (or ICE_SRC)
   d. If scp succeeds → print success, then symlink
   e. If scp fails → print ERROR with the manual scp command; do NOT exit (emit a WARNING instead,
      so the caller can decide); skip the symlink
```

### Respect DRY_RUN

Wrap the `scp` call in the existing `run()` function **or** handle separately — note that `run()` prefixes with `[DRY-RUN]` and skips execution when `DRY_RUN=true`. Prefer using `run()` for consistency. The symlink step should still be attempted (with a note) even in dry-run.

### mkdir -p DATA_DIR

Add this just before the wind block:
```bash
run mkdir -p "${DATA_DIR}"
```

---

## Style requirements

- Match the existing comment style: `# --- ... ---` headers, `echo "      ..."` indented messages
- Use `PIPESTATUS` or `$?` to detect scp failures, consistent with the rest of the file
- Do not change any logic outside the `[4/7]` block
- Do not change the section numbering or headings elsewhere in the file

---

## Expected result

After your edit, `[4/7]` should look approximately like:

```bash
# --------------------------------------------------------------------------
# [4/7] Link forcing files — auto-copy from ppi if missing locally
# --------------------------------------------------------------------------
echo "[4/7] Linking forcing files..."
run mkdir -p "${DATA_DIR}"

# -- Wind --
WIND_SRC="${DATA_DIR}/${YEAR}_${MONTH}_wind.nc"
PPI_WIND="${PPI_HOST}:${PPI_FORCING_BASE}/${YEAR}/${MONTH}/${YEAR}_${MONTH}_CARRA2_wind.nc"
if [[ ! -f "${WIND_SRC}" ]]; then
    echo "      wind forcing not found locally — copying from ppi..."
    # ... scp + error handling ...
fi
if [[ -f "${WIND_SRC}" ]]; then
    run ln -sf "${WIND_SRC}" "${WORK_DIR}/wind.nc"
    echo "      linked: wind.nc → ${WIND_SRC}"
else
    echo "      WARNING: wind.nc still missing after copy attempt — link manually"
fi

# -- Ice --
# ... same pattern for ice ...
```

Validate the edit by checking that no `{{...}}` placeholders or variable references are left unresolved in the modified section, and that the file remains valid bash (no syntax errors).
