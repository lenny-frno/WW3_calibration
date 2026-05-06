#!/bin/bash
# =============================================================================
# check_exp.sh — Inspect and diagnose a WW3 experiment
# =============================================================================
# Version: 1.0
#
# Usage: ./check_exp.sh -e <exp_name> [OPTIONS]
#   -e  Experiment name  (required)
#   -j  Slurm job ID     (optional — query sacct/seff for a specific job)
#   -v  Verbose          (show full log tails)
#   --fix-status         Re-evaluate status and update last performance_*.txt
#
# What it checks:
#   1. Experiment directory structure
#   2. Work directory: required files, symlinks, namelists
#   3. Slurm job status (from last_jobids.txt + sacct)
#   4. WW3 run status (from log.ww3, test001.ww3, timing_raw.txt)
#   5. Performance summary (from performance_*.txt)
#   6. Flags common problems with actionable advice
# =============================================================================

set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXP_NAME=""
JOB_ID=""
VERBOSE=false
FIX_STATUS=false

# --------------------------------------------------------------------------
# Parse args
# --------------------------------------------------------------------------
ARGS=()
for arg in "$@"; do
    case "${arg}" in
        --fix-status) FIX_STATUS=true ;;
        *)            ARGS+=("${arg}") ;;
    esac
done
set -- "${ARGS[@]:-}"

while getopts "e:j:v" opt; do
    case $opt in
        e) EXP_NAME="$OPTARG" ;;
        j) JOB_ID="$OPTARG" ;;
        v) VERBOSE=true ;;
        *) echo "Unknown option: -$opt"; exit 1 ;;
    esac
done

if [[ -z "${EXP_NAME}" ]]; then
    echo "Usage: $0 -e <exp_name> [-j <job_id>] [-v] [--fix-status]"
    echo ""
    echo "Available experiments:"
    ls "${BENCH_DIR}/experiments/" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    exit 1
fi

EXP_DIR="${BENCH_DIR}/experiments/${EXP_NAME}"
WORK_DIR="${EXP_DIR}/work"
LOGS_DIR="${EXP_DIR}/logs"
META_DIR="${EXP_DIR}/metadata"
RUNTIME_DIR="${META_DIR}/runtime"
SETUP_DIR="${META_DIR}/setup"

# --------------------------------------------------------------------------
# Helper: print a section header
# --------------------------------------------------------------------------
section() { echo ""; echo "──────────────────────────────────────────────"; echo " $*"; echo "──────────────────────────────────────────────"; }
ok()   { echo "  ✓  $*"; }
warn() { echo "  ⚠  $*"; }
fail() { echo "  ✗  $*"; }
info() { echo "     $*"; }

ISSUES=0
issue() { (( ISSUES++ )) || true; fail "$*"; }

# --------------------------------------------------------------------------
echo "============================================================"
echo " WW3 Experiment Inspector  (framework v1.0)"
echo " Experiment: ${EXP_NAME}"
echo " Date      : $(date --iso-8601=seconds)"
echo "============================================================"

# --------------------------------------------------------------------------
section "1. Directory Structure"
# --------------------------------------------------------------------------
for d in "${EXP_DIR}" "${WORK_DIR}" "${LOGS_DIR}" "${META_DIR}" "${RUNTIME_DIR}" "${SETUP_DIR}"; do
    if [[ -d "${d}" ]]; then
        ok "${d##*/EXP_NAME}"
    else
        issue "Missing: ${d}"
    fi
done

CONFIG_FILE="${EXP_DIR}/exp_config.sh"
if [[ -f "${CONFIG_FILE}" ]]; then
    ok "exp_config.sh found"
    source "${CONFIG_FILE}" || true
else
    issue "exp_config.sh missing"
fi

# --------------------------------------------------------------------------
section "2. Work Directory — Required Files"
# --------------------------------------------------------------------------
REQUIRED_FILES=(mod_def.ww3 ww3_shel.nml wind.ww3)
for f in "${REQUIRED_FILES[@]}"; do
    path="${WORK_DIR}/${f}"
    if [[ -L "${path}" ]]; then
        target=$(readlink -f "${path}" 2>/dev/null || echo "broken")
        if [[ -e "${target}" ]]; then
            ok "${f}  → ${target}"
        else
            issue "${f}  → BROKEN SYMLINK: ${target}"
        fi
    elif [[ -f "${path}" ]]; then
        size=$(du -sh "${path}" 2>/dev/null | awk '{print $1}')
        ok "${f}  (${size})"
    else
        issue "${f}  NOT FOUND"
    fi
done

OPTIONAL_FILES=(wind.nc ice.nc ww3_grid.nml ww3_prnc.nml ww3_ounf.nml)
echo ""
echo "  Optional files:"
for f in "${OPTIONAL_FILES[@]}"; do
    path="${WORK_DIR}/${f}"
    if [[ -f "${path}" || -L "${path}" ]]; then
        ok "${f}"
    else
        info "${f}  (absent)"
    fi
done

# Namelists by duration
echo ""
echo "  Duration namelists:"
for nml in ww3_shel_1h.nml ww3_shel_10h.nml ww3_shel_1d.nml ww3_shel_3d.nml ww3_shel_7d.nml; do
    if [[ -f "${WORK_DIR}/${nml}" ]]; then
        ok "${nml}"
    else
        info "${nml}  (absent)"
    fi
done

# --------------------------------------------------------------------------
section "3. Slurm Job Status"
# --------------------------------------------------------------------------
JOBIDS_FILE="${RUNTIME_DIR}/last_jobids.txt"
if [[ -f "${JOBIDS_FILE}" ]]; then
    ok "last_jobids.txt found"
    source "${JOBIDS_FILE}" || true
    echo ""
    info "  shel_job_id : ${shel_job_id:-unknown}"
    info "  prep_job_id : ${prep_job_id:-unknown}"
    info "  perf_job_id : ${perf_job_id:-unknown}"
    info "  post_job_id : ${post_job_id:-skipped}"
    info "  submitted   : ${submitted:-unknown}"
    info "  layout      : ${layout:-unknown}"
    echo ""

    # Use provided job ID or last known shel job
    QUERY_JOB="${JOB_ID:-${shel_job_id:-}}"

    if [[ -n "${QUERY_JOB}" && "${QUERY_JOB}" =~ ^[0-9]+$ ]]; then
        echo "  Querying sacct for job ${QUERY_JOB}..."
        SACCT_OUT=$(sacct -j "${QUERY_JOB}" \
            --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS,MaxVMSize \
            --noheader 2>/dev/null || echo "sacct unavailable")
        echo "${SACCT_OUT}" | head -4 | while read -r line; do
            info "${line}"
        done
    fi
else
    warn "last_jobids.txt not found — has run_exp.sh been called?"
fi

# --------------------------------------------------------------------------
section "4. WW3 Run Status"
# --------------------------------------------------------------------------
TIMING_RAW="${RUNTIME_DIR}/timing_raw.txt"
if [[ -f "${TIMING_RAW}" ]]; then
    ok "timing_raw.txt found"
    source "${TIMING_RAW}" || true
    echo ""
    info "  WW3 status  : ${WW3_STATUS:-UNKNOWN}"
    info "  Exit code   : ${WW3_EXIT_CODE:-N/A}"
    info "  Elapsed     : ${ELAPSED_SECONDS:-N/A}s  (${ELAPSED_MINUTES:-N/A} min)"
    info "  Throughput  : ${THROUGHPUT_DAYS_PER_HOUR:-N/A} sim-days/hour"
    info "  Sim duration: ${SIM_DURATION:-N/A}  (${SIM_DAYS:-N/A} days)"
    info "  Start       : ${RUN_START_ISO:-N/A}"
    info "  End         : ${RUN_END_ISO:-N/A}"
    info "  Tasks       : ${TOTAL_TASKS:-N/A}  (${NODES:-N/A} nodes × ${NTASKS_PER_NODE:-N/A}/node)"
    info "  CPUs/task   : ${CPUS_PER_TASK:-N/A}"
    info "  Mem/CPU     : ${MEM_PER_CPU:-N/A} MB"
else
    warn "timing_raw.txt not found"
    info "  run_shel.job may not have completed or was killed before writing timing"
fi

echo ""
echo "  WW3 log analysis:"
LOG_WW3="${WORK_DIR}/log.ww3"
if [[ -f "${LOG_WW3}" ]]; then
    SIZE=$(du -sh "${LOG_WW3}" | awk '{print $1}')
    LINES=$(wc -l < "${LOG_WW3}")
    ok "log.ww3 found  (${SIZE}, ${LINES} lines)"

    if grep -q "End of program" "${LOG_WW3}" 2>/dev/null; then
        ok "  'End of program' found → run completed"
    else
        warn "  'End of program' NOT found → run may be incomplete"
    fi

    if grep -q "WW3 - Done" "${LOG_WW3}" 2>/dev/null; then
        ok "  'WW3 - Done' found"
    fi

    TIMESTEP_COUNT=$(grep -c "^  [0-9]" "${LOG_WW3}" 2>/dev/null || echo 0)
    info "  Timesteps logged: ${TIMESTEP_COUNT}"

    if [[ "${VERBOSE}" == true ]]; then
        echo ""
        echo "  --- log.ww3 tail (20 lines) ---"
        tail -20 "${LOG_WW3}" | while read -r line; do info "${line}"; done
    fi
else
    issue "log.ww3 not found in ${WORK_DIR}"
fi

TEST001="${WORK_DIR}/test001.ww3"
if [[ -f "${TEST001}" ]]; then
    if grep -q "FATAL ERROR" "${TEST001}" 2>/dev/null; then
        issue "FATAL ERROR found in test001.ww3"
        tail -10 "${TEST001}" | while read -r line; do info "${line}"; done
    else
        ok "test001.ww3 — no FATAL ERROR"
    fi
else
    info "test001.ww3 not found (normal if prep didn't run)"
fi

# --------------------------------------------------------------------------
section "5. Performance Reports"
# --------------------------------------------------------------------------
PERF_FILES=("${RUNTIME_DIR}"/performance_*.txt)
if ls "${RUNTIME_DIR}"/performance_*.txt &>/dev/null; then
    for pf in "${PERF_FILES[@]}"; do
        ok "$(basename "${pf}")"
        if [[ "${VERBOSE}" == true ]]; then
            cat "${pf}"
        else
            # Show just the summary block
            grep -A 20 "PERFORMANCE SUMMARY\|Run status\|Throughput\|CPU eff\|Elapsed" "${pf}" 2>/dev/null \
                | head -15 | while read -r line; do info "${line}"; done
        fi
    done
else
    warn "No performance_*.txt found — log_performance.sh may not have run yet"
fi

# --------------------------------------------------------------------------
section "6. Slurm Log Snippets"
# --------------------------------------------------------------------------
echo "  Most recent shel log:"
SHEL_LOGS=("${LOGS_DIR}"/shel.*.LOG)
if ls "${LOGS_DIR}"/shel.*.LOG &>/dev/null 2>&1; then
    LATEST_LOG=$(ls -t "${LOGS_DIR}"/shel.*.LOG | head -1)
    ok "$(basename "${LATEST_LOG}")"
    echo ""
    if [[ "${VERBOSE}" == true ]]; then
        tail -50 "${LATEST_LOG}" | while read -r line; do info "${line}"; done
    else
        tail -20 "${LATEST_LOG}" | while read -r line; do info "${line}"; done
    fi
else
    warn "No shel.*.LOG found in ${LOGS_DIR}"
fi

echo ""
echo "  Most recent shel ERR:"
if ls "${LOGS_DIR}"/shel.*.ERR &>/dev/null 2>&1; then
    LATEST_ERR=$(ls -t "${LOGS_DIR}"/shel.*.ERR | head -1)
    ERR_SIZE=$(wc -c < "${LATEST_ERR}")
    if [[ "${ERR_SIZE}" -gt 0 ]]; then
        warn "$(basename "${LATEST_ERR}")  (${ERR_SIZE} bytes — may contain errors)"
        tail -20 "${LATEST_ERR}" | while read -r line; do info "${line}"; done
    else
        ok "$(basename "${LATEST_ERR}")  (empty — no errors)"
    fi
fi

# --------------------------------------------------------------------------
section "7. Model Provenance"
# --------------------------------------------------------------------------
if [[ -f "${SETUP_DIR}/model_info.txt" ]]; then
    ok "model_info.txt found"
    grep -E "Switch|Grid|WW3 git|Framework|Experiment" "${SETUP_DIR}/model_info.txt" 2>/dev/null \
        | while read -r line; do info "${line}"; done
fi

if [[ -f "${SETUP_DIR}/metadata.json" ]]; then
    ok "metadata.json found"
    grep -E "name|switch|git_commit|tags" "${SETUP_DIR}/metadata.json" 2>/dev/null \
        | head -8 | while read -r line; do info "${line}"; done
fi

# --------------------------------------------------------------------------
section "8. Summary"
# --------------------------------------------------------------------------
if [[ "${ISSUES}" -eq 0 ]]; then
    echo "  ✓  No structural issues found"
else
    echo "  ✗  ${ISSUES} issue(s) found — see above"
fi

echo ""
echo " Quick commands:"
echo "   tail -f ${LOGS_DIR}/shel.*.LOG"
echo "   tail -f ${WORK_DIR}/log.ww3"
echo "   cat ${RUNTIME_DIR}/timing_raw.txt"
echo "   cat \$(ls -t ${RUNTIME_DIR}/performance_*.txt | head -1)"
echo "============================================================"
