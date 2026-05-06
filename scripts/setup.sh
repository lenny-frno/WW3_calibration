#!/bin/bash
# =============================================================================
# setup.sh — WW3 Experiment Environment Setup
# =============================================================================
# Version: 2.0
#
# Usage: ./setup.sh [OPTIONS]
#   -w  WW3 model path         (default: from_waveXtrems)
#   -e  Experiment name        (default: exp_YYYYMMDD_HHMMSS), convention <grid><physics><config>
#   -y  Year                   (default: 2021)
#   -m  Month                  (default: 01)
#   -D  Data root              (default: /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2)
#   -s  Switch name            (default: dnora)
#   -g  Grid name              (default: CARRA2)
#   -c  Config/namelist dir    (default: none — copy namelists manually)
#   -t  Tags (comma-separated) (default: none)
#   -f  Force overwrite existing experiment
#   --dry-run                  Print actions without executing
#
# Example:
#   ./setup.sh -e exp_512ranks -g CARRA2 -s dnora -c configs/case1/ -t "scaling,intel"
#   ./setup.sh -e CARRA2_ref_oneVar -c configs/oneVAR_noSaving/ -t "scaling,ref"
#   ./setup.sh -w /home/sm_lenal/programs/compiling/PR2_UQ/WW3 -e CARRA2_PR2_UQ_oneVar -g CARRA2 -s PR2_UQ -c configs/oneVar_noSaving/ -t "scaling,physics,switch,PR2"
#   ./setup.sh -w /home/sm_lenal/programs/compiling/PR2_UNO/WW3 -e CARRA2_PR2_UNO_oneVar -g CARRA2 -s PR2_UNO -c configs/oneVar_noSaving/ -t "scaling,switch,physics,UNO,PR2"
#   ./setup.sh -w /home/sm_lenal/programs/compiling/PR3_UNO/WW3 -e CARRA2_PR3_UNO_oneVar -g CARRA2 -s PR3_UNO -c configs/oneVar_noSaving/ -t "scaling,switch,physics,UNO"
#   ./setup.sh -w /home/sm_lenal/programs/compiling/no_RTD/WW3 -e CARRA2_no_RTD_oneVar -g CARRA2 -s noRTD -c configs/oneVar_noSaving/ -t "scaling,switch,physics,RTD"
#   ./setup.sh -w /home/sm_lenal/programs/compiling/no_SCRIP/WW3 -e CARRA2_no_SCRIP_oneVar -g CARRA2 -s noSCRIP -c configs/oneVar_noSaving/ -t "scaling,switch,physics,SCRIP"
#   ./setup.sh -e CARRA2_ref_noSCUM -g CARRA2 -c configs/noSCUM/ -t "scaling,namelist,physics,noSCUM"
# =============================================================================
set -euo pipefail

FRAMEWORK_VERSION="2.0"
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
WW3="/home/sm_lenal/programs/compiling/from_waveXtrems/WW3"
EXP_NAME="exp_$(date +%Y%m%d_%H%M%S)"
YEAR="2021"
MONTH="01"
DATA_ROOT="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2"
SWITCH="dnora"
GRID="CARRA2"
CONFIG_DIR=""          # optional namelist source directory
TAGS=""                # comma-separated tags e.g. "scaling,intel,arctic"
FORCE=false
DRY_RUN=false

# --------------------------------------------------------------------------
# Pre-process long options (getopts cannot handle --)
# --------------------------------------------------------------------------
ARGS=()
for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        *)         ARGS+=("${arg}") ;;
    esac
done
set -- "${ARGS[@]:-}"
 
while getopts "w:e:y:m:D:s:g:c:t:f" opt; do
    case $opt in
        w) WW3="$OPTARG" ;;
        e) EXP_NAME="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        m) MONTH="$OPTARG" ;;
        D) DATA_ROOT="$OPTARG" ;;
        s) SWITCH="$OPTARG" ;;
        g) GRID="$OPTARG" ;;
        c) CONFIG_DIR="$OPTARG" ;;
        t) TAGS="$OPTARG" ;;
        f) FORCE=true ;;
        *) echo "Unknown option: -$opt"; exit 1 ;;
    esac
done

EXE_SRC="${WW3}/model/exe"
EXE_LINK_DIR="${BENCH_DIR}/exe"
DATA_DIR="${DATA_ROOT}/${YEAR}/${MONTH}/forcings"
GRID_DIR="${DATA_ROOT}/const/grid/${GRID}"
EXP_DIR="${BENCH_DIR}/experiments/${EXP_NAME}"
WORK_DIR="${EXP_DIR}/work"
LOGS_DIR="${EXP_DIR}/logs"
META_DIR="${EXP_DIR}/metadata"
CONFIG_FILE="${EXP_DIR}/exp_config.sh"

GIT_COMMIT="none"
FW_COMMIT="none"

# --------------------------------------------------------------------------
# Dry-run wrapper — prints commands instead of running them
# --------------------------------------------------------------------------
run() {
    if [[ "${DRY_RUN}" == true ]]; then
        echo "  [DRY-RUN] $*"
    else
        "$@"
    fi
}

# --------------------------------------------------------------------------
# Print header
# --------------------------------------------------------------------------
echo "============================================================"
echo " WW3 Experiment Setup  (framework v${FRAMEWORK_VERSION})"
echo "============================================================"
echo "  Experiment : ${EXP_NAME}"
echo "  Tags       : ${TAGS:-none}"
echo "  WW3 root   : ${WW3}"
echo "  Switch     : ${SWITCH}"
echo "  Grid       : ${GRID}"
echo "  Config dir : ${CONFIG_DIR:-none (manual)}"
echo "  Data dir   : ${DATA_DIR}"
echo "  Exp dir    : ${EXP_DIR}"
echo "  Dry-run    : ${DRY_RUN}"
echo "  Date       : $(date --iso-8601=seconds)"
echo "============================================================"

# --------------------------------------------------------------------------
# Guard: refuse to overwrite existing experiment unless --force
# --------------------------------------------------------------------------
if [[ -d "${EXP_DIR}" ]]; then
    if [[ "${FORCE}" == true ]]; then
        echo "WARNING: Overwriting existing experiment (--force): ${EXP_NAME}"
        run chmod -R u+w "${EXP_DIR}" 2>/dev/null || true   # unlock metadata if locked
    else
        echo "ERROR: Experiment already exists: ${EXP_DIR}"
        echo "       Use --force to overwrite, or choose a different -e name"
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# Validate required paths
# --------------------------------------------------------------------------
if [[ ! -d "${EXE_SRC}" ]]; then
    echo "ERROR: WW3 exe directory not found: ${EXE_SRC}"
    exit 1
fi
if [[ ! -d "${GRID_DIR}" ]]; then
    echo "ERROR: Grid directory not found: ${GRID_DIR}"
    echo "       Expected: ${DATA_ROOT}/const/grid/${GRID}/"
    exit 1
fi
if [[ -n "${CONFIG_DIR}" && ! -d "${CONFIG_DIR}" ]]; then
    echo "ERROR: Config/namelist directory not found: ${CONFIG_DIR}"
    exit 1
fi

# --------------------------------------------------------------------------
# [1/7] Create experiment directory structure
# --------------------------------------------------------------------------
echo "[1/7] Creating experiment directories..."
run mkdir -p "${WORK_DIR}" "${LOGS_DIR}" "${META_DIR}"
echo "      ${EXP_DIR}/"
echo "      ├── work/"
echo "      ├── logs/"
echo "      └── metadata/"

# --------------------------------------------------------------------------
# [2/7] Link executables
# --------------------------------------------------------------------------
echo "[2/7] Linking executables..."
run mkdir -p "${EXE_LINK_DIR}"
EXE_LIST=(ww3_grid ww3_bounc ww3_prnc ww3_shel ww3_ounf)
for exe in "${EXE_LIST[@]}"; do
    src="${EXE_SRC}/${exe}"
    if [[ -f "${src}" ]]; then
        run ln -sf "${src}" "${WORK_DIR}/${exe}"
        echo "      linked: ${exe}"
    else
        echo "      WARNING: ${exe} not found in ${EXE_SRC} — skipping"
    fi
done

# --------------------------------------------------------------------------
# [3/7] Link grid files
# --------------------------------------------------------------------------
echo "[3/7] Linking grid files (${GRID})..."
GRID_LIST_TOLINK=(lon.txt lat.txt mapsta.txt depth.txt)
GRID_LIST_TOCP=(ww3_grid.nml)
missing_grid=0
for grid_file in "${GRID_LIST_TOLINK[@]}"; do
    src="${GRID_DIR}/${grid_file}"
    if [[ -f "${src}" ]]; then
        run ln -sf "${src}" "${WORK_DIR}/${grid_file}"
        echo "      linked: ${grid_file}"
    else
        echo "      WARNING: ${grid_file} not found in ${GRID_DIR}"
        (( missing_grid++ )) || true
    fi
done
for grid_file in "${GRID_LIST_TOCP[@]}"; do
    src="${GRID_DIR}/${grid_file}"
    if [[ -f "${src}" ]]; then
        run cp "${src}" "${WORK_DIR}/${grid_file}"
        echo "     copied: ${grid_file}"
    else
        echo "      WARNING: ${grid_file} not found in ${GRID_DIR}"
        (( missing_grid++ )) || true
    fi
done

[[ "${missing_grid}" -gt 0 ]] && \
    echo "      WARNING: ${missing_grid} grid file(s) missing — check ${GRID_DIR}"

# --------------------------------------------------------------------------
# [4/7] Link forcing files
# Naming convention: YYYY_MM_<GRID>_wind.nc / YYYY_MM_<GRID>_ice.nc
# --------------------------------------------------------------------------
echo "[4/7] Linking forcing files..."
 
WIND_SRC="${DATA_DIR}/${YEAR}_${MONTH}_wind.nc"
if [[ -f "${WIND_SRC}" ]]; then
    run ln -sf "${WIND_SRC}" "${WORK_DIR}/wind.nc"
    echo "      linked: wind.nc → ${WIND_SRC}"
else
    echo "      WARNING: wind forcing not found: ${WIND_SRC}"
    echo "               Link manually: ln -s <path> ${WORK_DIR}/wind.nc"
fi
 
ICE_SRC="${DATA_DIR}/${YEAR}_${MONTH}_ice.nc"
if [[ -f "${ICE_SRC}" ]]; then
    run ln -sf "${ICE_SRC}" "${WORK_DIR}/ice.nc"
    echo "      linked: ice.nc → ${ICE_SRC}"
else
    echo "      WARNING: ice forcing not found: ${ICE_SRC}"
    echo "               Link manually: ln -s <path> ${WORK_DIR}/ice.nc"
fi

# --------------------------------------------------------------------------
# [5/7] Copy namelists from config directory (if provided)
# Namelists are COPIED (not symlinked) so each experiment can edit them
# --------------------------------------------------------------------------
echo "[5/7] Setting up namelists..."
if [[ -n "${CONFIG_DIR}" ]]; then
    NML_LIST=(ww3_prnc.nml namelist.nml ww3_shel.nml ww3_shel_1h.nml ww3_shel_10h.nml \
              ww3_shel_1d.nml ww3_shel_3d.nml ww3_shel_7d.nml ww3_ounf.nml)
    copied=0
    for nml in "${NML_LIST[@]}"; do
        src="${CONFIG_DIR}/${nml}"
        if [[ -f "${src}" ]]; then
            run cp "${src}" "${WORK_DIR}/${nml}"
            echo "      copied: ${nml}"
            (( copied++ )) || true
        fi
    done
    echo "      ${copied} namelist(s) copied from ${CONFIG_DIR}"
else
    echo "      No -c config dir — copy namelists manually to ${WORK_DIR}/"
fi


# --------------------------------------------------------------------------
# [6/7] Save model metadata and provenance
# --------------------------------------------------------------------------
echo "[6/7] Saving model metadata..."
 
if [[ "${DRY_RUN}" == false ]]; then

# ------------------------------------------------------------------
# Directories (separating setup vs runtime)
# ------------------------------------------------------------------
SETUP_DIR="${META_DIR}/setup"
RUNTIME_DIR="${META_DIR}/runtime"
mkdir -p "${SETUP_DIR}" "${RUNTIME_DIR}"

# ------------------------------------------------------------------
# Safe initialization (avoid unbound variables)
# ------------------------------------------------------------------
META_FILE="${SETUP_DIR}/model_info.txt"
META_JSON="${SETUP_DIR}/metadata.json"

GIT_COMMIT="none"
FW_COMMIT="none"


# Git info
if git -C "${WW3}" rev-parse --git-dir &>/dev/null 2>&1; then
    GIT_COMMIT=$(git -C "${WW3}" rev-parse HEAD 2>/dev/null || echo "unknown")
fi
if git -C "${BENCH_DIR}" rev-parse --git-dir &>/dev/null 2>&1; then
    FW_COMMIT=$(git -C "${BENCH_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")
fi
 
cat > "${META_FILE}" << EOF
============================================================
 WW3 Experiment Metadata
============================================================
Framework version : ${FRAMEWORK_VERSION}
Framework commit  : ${FW_COMMIT}
Experiment name   : ${EXP_NAME}
Tags              : ${TAGS:-none}
Setup date        : $(date +"%Y-%m-%dT%H:%M:%S")
User              : $(whoami)
Host              : $(hostname)
WW3 root          : ${WW3}
WW3 git commit    : ${GIT_COMMIT}
Exe source        : ${EXE_SRC}
Switch            : ${SWITCH}
Grid              : ${GRID}
Grid dir          : ${GRID_DIR}
Config dir        : ${CONFIG_DIR:-none}
Data dir          : ${DATA_DIR}
Year/Month        : ${YEAR}/${MONTH}
Work dir          : ${WORK_DIR}
 
--- Executable timestamps ---
EOF
 
for exe in "${EXE_LIST[@]}"; do
    src="${EXE_SRC}/${exe}"
    [[ -f "${src}" ]] && \
        printf "%-20s %s\n" "${exe}" "$(ls -la "${src}" | awk '{print $6,$7,$8}')" >> "${META_FILE}"
done
 
# Switch file
SWITCH_SRC="${WW3}/model/bin/switch_${SWITCH}"
if [[ -f "${SWITCH_SRC}" ]]; then
    cp "${SWITCH_SRC}" "${SETUP_DIR}/switch_${SWITCH}"
    echo "" >> "${META_FILE}"
    echo "--- WW3 Switch: switch_${SWITCH} ---" >> "${META_FILE}"
    cat "${SWITCH_SRC}" >> "${META_FILE}"
    echo "      saved: switch_${SWITCH}"
else
    echo "      WARNING: switch file not found: ${SWITCH_SRC}"
fi
 
# Compiler/link scripts
for f in comp link; do
    src="${WW3}/model/exe/${f}"
    [[ -f "${src}" ]] && cp "${src}" "${SETUP_DIR}/${f}_script" && echo "      saved: ${f}_script"
done
 
# Loaded modules
{ echo ""; echo "--- Loaded modules at setup time ---"; module list 2>&1; } >> "${META_FILE}" \
    || echo "(module list unavailable)" >> "${META_FILE}"
 
# WW3 git log
if [[ "${GIT_COMMIT}" != "none" ]]; then
    { echo ""; echo "--- WW3 git log (last 5) ---";
      git -C "${WW3}" log --oneline -5 2>/dev/null;
      echo "--- git status ---";
      git -C "${WW3}" status --short 2>/dev/null; } >> "${META_FILE}"
    echo "      saved: git commit ${GIT_COMMIT:0:8}"
fi
 
# Cluster snapshot
{ echo ""; echo "--- Cluster state at setup ---";
  sinfo -o "%20N %8c %10m %20f %6t" 2>/dev/null || echo "sinfo unavailable"; } >> "${META_FILE}"
 
echo "      saved: ${META_FILE}"

# --------------------------------------------------------------------------
# Write structured JSON metadata (for analysis)
# --------------------------------------------------------------------------
echo "      writing: ${META_JSON}"

# ---- safe tag handling ----
    if [[ -n "${TAGS}" ]]; then
        TAGS_JSON=$(printf '%s\n' "${TAGS}" | awk -F',' '{
            printf "["
            for(i=1;i<=NF;i++) {
                gsub(/"/, "\\\"", $i)
                printf "\"%s\"%s",$i,(i<NF?",":"")
            }
            printf "]"
        }')
    else
        TAGS_JSON="[]"
    fi

    NOW=$(date +"%Y-%m-%dT%H:%M:%S")
# Convert tags to JSON array
if [[ -n "${TAGS}" ]]; then
    TAGS_JSON=$(printf '%s\n' "${TAGS}" | awk -F',' '{for(i=1;i<=NF;i++) printf "\"%s\"%s",$i,(i<NF?",":"")}')
    TAGS_JSON="[${TAGS_JSON}]"
else
    TAGS_JSON="[]"
fi

# Safe date (portable)
NOW=$(date +"%Y-%m-%dT%H:%M:%S")

cat > "${META_JSON}" << EOF
{
  "framework": {
    "version": "${FRAMEWORK_VERSION}",
    "git_commit": "${FW_COMMIT}"
  },
  "experiment": {
    "name": "${EXP_NAME}",
    "tags": ${TAGS_JSON},
    "created_at": "${NOW}"
  },
  "model": {
    "ww3_root": "${WW3}",
    "git_commit": "${GIT_COMMIT}",
    "switch": "${SWITCH}",
    "grid": "${GRID}"
  },
  "environment": {
    "user": "$(whoami)",
    "host": "$(hostname)"
  },
  "paths": {
    "experiment_dir": "${EXP_DIR}",
    "work_dir": "${WORK_DIR}",
    "data_dir": "${DATA_DIR}",
    "grid_dir": "${GRID_DIR}"
  }
}
EOF

echo "      saved: ${META_JSON}"

# --------------------------------------------------------------------------
# Save runtime environment (for jobs)
# --------------------------------------------------------------------------
ENV_FILE="${SETUP_DIR}/env.sh"
mkdir -p "$(dirname "${ENV_FILE}")"

cat > "${ENV_FILE}" << EOF
#!/bin/bash
# Auto-generated environment for experiment: ${EXP_NAME}

# Clean environment
module purge

# Load required runtime modules (NO buildenv!)
module load netCDF-HDF5-utils/4.9.2-1.12.2-hpc1-intel2023.1.0-hpc1
module load eccodes-utils/2.32.0-ENABLE-AEC-hpc1-intel-2023.1.0-hpc1

# NetCDF detection (robust)
if command -v nf-config >/dev/null 2>&1; then
    export NETCDF_CONFIG=\$(which nf-config)
elif command -v nc-config >/dev/null 2>&1; then
    export NETCDF_CONFIG=\$(which nc-config)
else
    echo "ERROR: NetCDF not found in environment"
    exit 1
fi

# WW3 environment
export WWATCH3_NETCDF=NC4

# MPI / OpenMP defaults
export OMP_NUM_THREADS=1
export I_MPI_FABRICS=shm:ofi

echo "[env.sh] Environment loaded"
EOF

chmod +x "${ENV_FILE}"
echo "      saved: ${ENV_FILE}"

# ------------------------------------------------------------------
# Permissions (clean separation setup vs runtime)
# ------------------------------------------------------------------
chmod -R a-w "${SETUP_DIR}"
chmod -R u+rwX "${RUNTIME_DIR}"
fi  # end DRY_RUN guard


# --------------------------------------------------------------------------
# [7/7] Write exp_config.sh — single source of truth for all job scripts
# --------------------------------------------------------------------------
echo "[7/7] Writing experiment config..."
if [[ "${DRY_RUN}" == false ]]; then
cat > "${CONFIG_FILE}" << EOF
# =============================================================================
# exp_config.sh — Auto-generated by setup.sh v${FRAMEWORK_VERSION}
# Generated  : $(date --iso-8601=seconds)
# Experiment : ${EXP_NAME}
#
# Source this file from run_exp.sh and job scripts.
# DO NOT EDIT manually after submission — use --force to regenerate.
# =============================================================================

# --- Identity ---
export EXP_NAME="${EXP_NAME}"
export TAGS="${TAGS}"
export FRAMEWORK_VERSION="${FRAMEWORK_VERSION}"
export WW3_GIT_COMMIT="${GIT_COMMIT:-none}"

# --- Framework paths ---
export BENCH_DIR="${BENCH_DIR}"
export WW3="${WW3}"

# --- Experiment paths ---
export EXP_DIR="${EXP_DIR}"
export WORK_DIR="${WORK_DIR}"
export LOGS_DIR="${LOGS_DIR}"
export META_DIR="${META_DIR}"
export EXE_DIR="${EXE_SRC}"

# --- Data / forcing ---
export YEAR="${YEAR}"
export MONTH="${MONTH}"
export DATA_ROOT="${DATA_ROOT}"
export DATA_DIR="${DATA_DIR}"
export GRID="${GRID}"
export GRID_DIR="${GRID_DIR}"
export SWITCH="${SWITCH}"

# --- Run parameters (populated at submission by run_exp.sh) ---
# NODES, NTASKS_PER_NODE, NTASKS, WALL_TIME, SIM_DURATION
EOF

# Lock metadata against accidental edits
chmod -w "${META_DIR}/model_info.txt" "${CONFIG_FILE}" 2>/dev/null || true
echo "      saved and locked: ${CONFIG_FILE}"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================================"
[[ "${DRY_RUN}" == true ]] && echo " *** DRY-RUN — no files were created ***"
echo " Setup complete: ${EXP_NAME}"
echo "============================================================"
[[ -z "${CONFIG_DIR}" ]] && cat << EOF

 ⚠  No config dir (-c) — copy namelists manually:
    cp <your>.nml  ${WORK_DIR}/

EOF
echo " Submit:"
echo "   ./run_exp.sh -e ${EXP_NAME} -N 12 -n 56 -d 1d"
echo "   ./run_exp.sh -e ${EXP_NAME} --ntasks 600 -d 1d"
echo ""
echo " Monitor:"
echo "   tail -f ${LOGS_DIR}/shel.*.LOG"
echo "   tail -f ${WORK_DIR}/log.ww3"
echo "============================================================"
