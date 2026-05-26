#!/bin/bash
# =============================================================================
# scan_experiments.sh — Batch diagnostic dashboard for all WW3 experiments
# =============================================================================
# Version: 1.1
#
# Usage: ./scan_experiments.sh [OPTIONS]
#
# Options:
#   -s, --status <S[,S...]>  Show only experiments matching comma-separated statuses.
#                            Valid values: SUCCESS INCOMPLETE FAILED CANCELLED
#                                         TIMEOUT DEAD NOT_RUN NOT_SETUP
#                                         PENDING RUNNING ALL
#                            Default: ALL
#   -g, --group  <G>         Show only experiments under group folder <G>
#   -t, --tag    <T>         Show only experiments whose exp_config.sh EXP_TAGS contains <T>
#       --clean              Interactive mode: select experiments to remove
#       --dry-run            With --clean: preview removals without deleting
#       --no-color           Disable ANSI colour codes (auto-disabled if not a TTY)
#       --csv                Output CSV instead of a formatted table
#   -h, --help               Show this help
#
# Directory layout (both are supported transparently):
#   Flat:    experiments/<exp_name>/           → group shown as "—"
#   Grouped: experiments/<group>/<exp_name>/   → group shown as <group>
#
# Status detection order (most-to-least authoritative):
#   1. metadata/runtime/timing_raw.txt → WW3_STATUS + wave output check  (most reliable)
#   2. metadata/runtime/last_jobids.txt exists, no timing → PENDING/RUNNING/DEAD/FAILED
#   3. exp_config.sh or work/ exists, no last_jobids.txt  → NOT_RUN
#   4. No exp_config.sh AND no work/                      → NOT_SETUP
#
# Extended statuses:
#   SUCCESS    = timed + wave output (Wave.nc / ww3.*.nc) found
#   INCOMPLETE = timed + "End of program" in log but NO wave output
#   FAILED     = timed + no "End of program" or FATAL ERROR
#   DEAD       = job submitted but no sacct record (silently disappeared)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXP_ROOT="${BENCH_DIR}/experiments"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
FILTER_STATUSES=("ALL")
FILTER_GROUP=""
FILTER_TAG=""
CLEAN_MODE=false
DRY_RUN=false
CSV_MODE=false
USE_COLOR=true

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--status)
            IFS=',' read -ra FILTER_STATUSES <<< "${2^^}"
            shift 2 ;;
        -g|--group)
            FILTER_GROUP="$2"; shift 2 ;;
        -t|--tag)
            FILTER_TAG="$2"; shift 2 ;;
        --clean)
            CLEAN_MODE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --no-color)
            USE_COLOR=false; shift ;;
        --csv)
            CSV_MODE=true; shift ;;
        -h|--help)
            sed -n '2,/^# ====/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *)
            echo "Unknown option: $1  (try --help)" >&2; exit 1 ;;
    esac
done

# Auto-disable colour when not writing to a terminal or CSV requested
if [[ "${CSV_MODE}" == true ]] || [[ ! -t 1 ]]; then
    USE_COLOR=false
fi

# --------------------------------------------------------------------------
# Colour helpers
# --------------------------------------------------------------------------
if [[ "${USE_COLOR}" == true ]]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'
    C_CYAN='\033[0;36m'
    C_BLUE='\033[0;34m'
    C_GREY='\033[0;90m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BLUE='' C_GREY='' C_BOLD='' C_RESET=''
fi

status_color() {
    case "$1" in
        SUCCESS)                      echo "${C_GREEN}" ;;
        INCOMPLETE)                   echo "${C_YELLOW}" ;;
        FAILED|TIMEOUT|DEAD|UNKNOWN)  echo "${C_RED}" ;;
        CANCELLED)                    echo "${C_YELLOW}" ;;
        RUNNING|PENDING)              echo "${C_CYAN}" ;;
        NOT_RUN|NOT_SETUP)            echo "${C_GREY}" ;;
        *)                            echo "${C_RESET}" ;;
    esac
}

# Check if a completed experiment produced usable wave output.
# Returns 0 (true) if Wave.nc or any ww3.*.nc exists under work/.
_has_wave_output() {
    local work_dir="$1/work"
    [[ -f "${work_dir}/Wave*.nc" ]]           && return 0
    ls "${work_dir}"/Wave*.nc &>/dev/null    && return 0
    ls "${work_dir}"/ww3*.nc  &>/dev/null    && return 0
    return 1
}

# Check sacct for the actual Slurm state of a job (fast, non-blocking).
# Echoes one of: COMPLETED FAILED CANCELLED TIMEOUT RUNNING PENDING UNKNOWN
_sacct_state() {
    local jobid="$1"
    [[ ! "${jobid}" =~ ^[0-9]+$ ]] && echo "UNKNOWN" && return
    local state
    state=$(sacct -j "${jobid}" --noheader --format=State --parsable2 2>/dev/null \
            | head -1 | tr -d ' ')
    case "${state}" in
        COMPLETED)            echo "COMPLETED" ;;
        FAILED)               echo "FAILED" ;;
        CANCELLED*|CANCELED*) echo "CANCELLED" ;;
        TIMEOUT)              echo "TIMEOUT" ;;
        RUNNING)              echo "RUNNING" ;;
        PENDING)              echo "PENDING" ;;
        *)                    echo "UNKNOWN" ;;
    esac
}

# --------------------------------------------------------------------------
# Status detection — populates globals: _STATUS _ELAPSED _THROUGHPUT _JOBID _DATE _NOTE
# --------------------------------------------------------------------------
detect_status() {
    local exp_dir="$1"
    local config="${exp_dir}/exp_config.sh"
    local jobids="${exp_dir}/metadata/runtime/last_jobids.txt"
    local timing="${exp_dir}/metadata/runtime/timing_raw.txt"
    local log="${exp_dir}/work/log.ww3"
    local test001="${exp_dir}/work/test001.ww3"

    _STATUS="NOT_SETUP"
    _ELAPSED="—"
    _THROUGHPUT="—"
    _JOBID="—"
    _DATE="—"
    _NOTE=""

    # Level 4: neither exp_config.sh nor work/ → truly not set up
    if [[ ! -f "${config}" && ! -d "${exp_dir}/work" ]]; then
        return
    fi
    [[ ! -f "${config}" ]] && _NOTE="legacy (no exp_config.sh)"

    # Level 3: setup but not yet submitted
    # (For legacy experiments that have timing_raw.txt but no jobids, fall through)
    _STATUS="NOT_RUN"
    if [[ ! -f "${jobids}" && ! -f "${timing}" ]]; then
        return
    fi

    # Read job ID (if available)
    local shel_id=""
    if [[ -f "${jobids}" ]]; then
        shel_id=$(grep '^shel_job_id=' "${jobids}" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    fi
    _JOBID="${shel_id:-—}"

    # Level 2: job submitted (or legacy with work/ but no timing) → check live state
    if [[ ! -f "${timing}" ]]; then
        if [[ -f "${log}" ]]; then
            _STATUS="RUNNING"
            _NOTE="${_NOTE:+${_NOTE}; }log.ww3 exists but timing not written yet"
        elif [[ -n "${shel_id}" ]] && command -v sacct &>/dev/null; then
            local sstate
            sstate=$(_sacct_state "${shel_id}")
            case "${sstate}" in
                COMPLETED) _STATUS="INCOMPLETE"; _NOTE="${_NOTE:+${_NOTE}; }sacct=COMPLETED but no timing_raw" ;;
                FAILED)    _STATUS="FAILED"    ; _NOTE="${_NOTE:+${_NOTE}; }sacct=FAILED" ;;
                CANCELLED) _STATUS="CANCELLED" ; _NOTE="${_NOTE:+${_NOTE}; }sacct=CANCELLED" ;;
                TIMEOUT)   _STATUS="TIMEOUT"   ; _NOTE="${_NOTE:+${_NOTE}; }sacct=TIMEOUT" ;;
                RUNNING)   _STATUS="RUNNING" ;;
                PENDING)   _STATUS="PENDING" ;;
                UNKNOWN)   _STATUS="DEAD"       ; _NOTE="${_NOTE:+${_NOTE}; }no sacct record — may have expired" ;;
            esac
        else
            _STATUS="PENDING"
            _NOTE="${_NOTE:+${_NOTE}; }job submitted; waiting for log"
        fi
        return
    fi

    # Level 1: timing_raw exists — most authoritative
    local raw_status raw_elapsed raw_throughput raw_date
    raw_status=$(    grep '^WW3_STATUS='                "${timing}" | cut -d= -f2- | tr -d '"' || true)
    raw_elapsed=$(   grep '^ELAPSED_SECONDS='           "${timing}" | cut -d= -f2- | tr -d '"' || true)
    raw_throughput=$(grep '^THROUGHPUT_DAYS_PER_HOUR='  "${timing}" | cut -d= -f2- | tr -d '"' || true)
    raw_date=$(      grep '^RUN_END_ISO='               "${timing}" | cut -d= -f2- | tr -d '"' || true)

    _ELAPSED="${raw_elapsed:+${raw_elapsed}s}"
    _ELAPSED="${_ELAPSED:-—}"
    _THROUGHPUT="${raw_throughput:-—}"
    _DATE="${raw_date:0:10}"
    _DATE="${_DATE:-—}"

    # Normalise legacy "COMPLETED" (old framework) and empty → tentative SUCCESS
    local _tentative
    case "${raw_status}" in
        SUCCESS|COMPLETED|"") _tentative="SUCCESS"   ;;
        FAILED)               _tentative="FAILED"    ;;
        CANCELLED)            _tentative="CANCELLED" ;;
        TIMEOUT)              _tentative="TIMEOUT"   ;;
        *)                    _tentative="${raw_status:-UNKNOWN}" ;;
    esac

    # For success-class: verify wave output was actually produced
    if [[ "${_tentative}" == "SUCCESS" ]]; then
        if _has_wave_output "${exp_dir}"; then
            _STATUS="SUCCESS"
        elif [[ -f "${log}" ]] && grep -q "End of program" "${log}" 2>/dev/null; then
            _STATUS="INCOMPLETE"
            _NOTE="${_NOTE:+${_NOTE}; }ran to end but no wave output (Wave.nc missing)"
        else
            _STATUS="FAILED"
            _NOTE="${_NOTE:+${_NOTE}; }no wave output, no 'End of program' in log"
        fi
    else
        _STATUS="${_tentative}"
    fi

    # Flag FATAL ERROR regardless of reported status
    if [[ -f "${test001}" ]] && grep -q "FATAL ERROR" "${test001}" 2>/dev/null; then
        _NOTE="${_NOTE:+${_NOTE}; }FATAL ERROR in test001.ww3"
        [[ "${_STATUS}" == "SUCCESS" || "${_STATUS}" == "INCOMPLETE" ]] && _STATUS="FAILED"
    fi
}

# --------------------------------------------------------------------------
# Status filter check
# --------------------------------------------------------------------------
status_matches_filter() {
    local status="$1"
    # "ALL" → always pass
    for f in "${FILTER_STATUSES[@]}"; do
        [[ "${f}" == "ALL" ]] && return 0
        [[ "${f}" == "${status}" ]] && return 0
    done
    return 1
}

# --------------------------------------------------------------------------
# Tag filter check
# --------------------------------------------------------------------------
tag_matches() {
    local exp_dir="$1"
    local config="${exp_dir}/exp_config.sh"
    [[ -z "${FILTER_TAG}" ]] && return 0
    [[ ! -f "${config}" ]] && return 1
    local tags
    tags=$(grep '^EXP_TAGS=' "${config}" 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    [[ "${tags}" == *"${FILTER_TAG}"* ]] && return 0
    return 1
}

# --------------------------------------------------------------------------
# Collect experiment list: outputs "GROUP::EXP_NAME::EXP_DIR" lines, one per exp
# --------------------------------------------------------------------------
collect_experiments() {
    local entry subentry
    if [[ ! -d "${EXP_ROOT}" ]]; then
        echo "ERROR: experiments directory not found: ${EXP_ROOT}" >&2
        return 1
    fi

    shopt -s nullglob
    for entry in "${EXP_ROOT}"/*/; do
        [[ ! -d "${entry}" ]] && continue
        local name
        name="$(basename "${entry}")"

        # Skip if group filter is active and name doesn't match
        if [[ -n "${FILTER_GROUP}" && "${name}" != "${FILTER_GROUP}" ]]; then
            # Still allow: maybe it matches as an ungrouped exp name
            if [[ -f "${entry}/exp_config.sh" && "${FILTER_GROUP}" != "—" ]]; then
                :  # ungrouped entry, but group filter is set — skip
                continue
            fi
        fi

        if [[ -f "${entry}/exp_config.sh" || -d "${entry}/work" ]]; then
            # Flat layout: this IS the experiment
            echo "—|${name}|${entry%/}"
        else
            # Potential group folder: look for experiments one level deeper
            for subentry in "${entry}"/*/; do
                [[ ! -d "${subentry}" ]] && continue
                local subname
                subname="$(basename "${subentry}")"
                [[ ! -f "${subentry}/exp_config.sh" && ! -d "${subentry}/work" ]] && continue
                echo "${name}|${subname}|${subentry%/}"
            done
            # If no matching sub-experiments found, silently skip
        fi
    done
    shopt -u nullglob
}

# --------------------------------------------------------------------------
# Disk usage helper
# --------------------------------------------------------------------------
du_human() {
    du -sh "$1" 2>/dev/null | awk '{print $1}' || echo "?"
}

# --------------------------------------------------------------------------
# CSV output
# --------------------------------------------------------------------------
print_csv_header() {
    echo "group,exp_name,status,elapsed_s,throughput_d_per_h,job_id,date,note,exp_dir"
}

print_csv_row() {
    local group="$1" name="$2" status="$3" elapsed="$4" tput="$5" \
          jobid="$6" date="$7" note="$8" dir="$9"
    # Escape any commas in fields
    printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "${group}" "${name}" "${status}" "${elapsed//—/}" \
        "${tput//—/}" "${jobid//—/}" "${date//—/}" "${note}" "${dir}"
}

# --------------------------------------------------------------------------
# Table output helpers
# --------------------------------------------------------------------------
COL_GROUP=14
COL_NAME=38
COL_STATUS=12
COL_ELAPSED=10
COL_TPUT=8
COL_JOBID=8
COL_DATE=12

pad() {
    local s="$1" w="$2"
    printf "%-${w}s" "${s:0:${w}}"
}

print_table_header() {
    printf "${C_BOLD}"
    printf "%-${COL_GROUP}s  %-${COL_NAME}s  %-${COL_STATUS}s  %-${COL_ELAPSED}s  %-${COL_TPUT}s  %-${COL_JOBID}s  %s\n" \
        "GROUP" "EXPERIMENT" "STATUS" "ELAPSED" "TPUT" "JOB_ID" "DATE"
    printf "${C_RESET}"
    printf '%0.s─' $(seq 1 $((COL_GROUP + COL_NAME + COL_STATUS + COL_ELAPSED + COL_TPUT + COL_JOBID + COL_DATE + 14)))
    printf '\n'
}

print_table_row() {
    local group="$1" name="$2" status="$3" elapsed="$4" tput="$5" \
          jobid="$6" date="$7" note="$8"
    local col
    col="$(status_color "${status}")"
    printf "%-${COL_GROUP}s  %-${COL_NAME}s  ${col}%-${COL_STATUS}s${C_RESET}  %-${COL_ELAPSED}s  %-${COL_TPUT}s  %-${COL_JOBID}s  %s" \
        "${group:0:${COL_GROUP}}" \
        "${name:0:${COL_NAME}}" \
        "${status}" \
        "${elapsed:0:${COL_ELAPSED}}" \
        "${tput:0:${COL_TPUT}}" \
        "${jobid:0:${COL_JOBID}}" \
        "${date:0:${COL_DATE}}"
    if [[ -n "${note}" ]]; then
        printf "  ${C_YELLOW}⚠ %s${C_RESET}" "${note}"
    fi
    printf '\n'
}

# --------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------

# Gather all experiments into arrays (so we can reuse for --clean)
declare -a EXP_GROUPS EXP_NAMES EXP_DIRS EXP_STATUSES EXP_DISKS

mapfile -t ENTRIES < <(collect_experiments | sort)

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
    echo "No experiments found under: ${EXP_ROOT}" >&2
    exit 0
fi

# First pass: collect into arrays, applying filters
declare -a VISIBLE_GROUPS VISIBLE_NAMES VISIBLE_DIRS

for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r grp name dir <<< "${entry}"

    # Group filter
    if [[ -n "${FILTER_GROUP}" && "${grp}" != "${FILTER_GROUP}" && "${FILTER_GROUP}" != "—" ]]; then
        continue
    fi

    # Tag filter
    tag_matches "${dir}" || continue

    # Detect status
    detect_status "${dir}"

    # Status filter
    status_matches_filter "${_STATUS}" || continue

    VISIBLE_GROUPS+=("${grp}")
    VISIBLE_NAMES+=("${name}")
    VISIBLE_DIRS+=("${dir}")
    EXP_STATUSES+=("${_STATUS}")
done

if [[ ${#VISIBLE_DIRS[@]} -eq 0 ]]; then
    echo "No experiments match the given filters." >&2
    exit 0
fi

# --------------------------------------------------------------------------
# Display
# --------------------------------------------------------------------------
if [[ "${CSV_MODE}" == true ]]; then
    print_csv_header
    for i in "${!VISIBLE_DIRS[@]}"; do
        detect_status "${VISIBLE_DIRS[i]}"
        print_csv_row \
            "${VISIBLE_GROUPS[i]}" "${VISIBLE_NAMES[i]}" "${_STATUS}" \
            "${_ELAPSED}" "${_THROUGHPUT}" "${_JOBID}" "${_DATE}" "${_NOTE}" \
            "${VISIBLE_DIRS[i]}"
    done
else
    echo ""
    echo -e "${C_BOLD}WW3 Experiment Scanner  (framework v1.0)${C_RESET}"
    echo "  Root : ${EXP_ROOT}"
    echo "  Date : $(date --iso-8601=seconds)"
    echo ""
    print_table_header

    # Counters for summary
    declare -A STATUS_COUNTS
    for i in "${!VISIBLE_DIRS[@]}"; do
        detect_status "${VISIBLE_DIRS[i]}"
        # Update storage arrays with fresh values (needed for --clean iteration)
        EXP_STATUSES[i]="${_STATUS}"
        print_table_row \
            "${VISIBLE_GROUPS[i]}" "${VISIBLE_NAMES[i]}" "${_STATUS}" \
            "${_ELAPSED}" "${_THROUGHPUT}" "${_JOBID}" "${_DATE}" "${_NOTE}"
        STATUS_COUNTS["${_STATUS}"]=$(( ${STATUS_COUNTS["${_STATUS}"]:-0} + 1 ))
    done

    echo ""
    echo -e "${C_BOLD}Summary:${C_RESET}  ${#VISIBLE_DIRS[@]} experiments shown"
    for s in SUCCESS INCOMPLETE FAILED TIMEOUT CANCELLED DEAD RUNNING PENDING NOT_RUN NOT_SETUP UNKNOWN; do
        cnt="${STATUS_COUNTS[${s}]:-0}"
        [[ "${cnt}" -gt 0 ]] && printf "  $(status_color "${s}")%-12s${C_RESET}  %d\n" "${s}" "${cnt}"
    done
fi

# --------------------------------------------------------------------------
# Clean mode: interactive selection and removal
# --------------------------------------------------------------------------
if [[ "${CLEAN_MODE}" == false ]]; then
    echo ""
    echo -e "${C_GREY}Tip: Use --clean to interactively remove experiments.${C_RESET}"
    echo -e "${C_GREY}     Use --status FAILED,CANCELLED to narrow the list first.${C_RESET}"
    exit 0
fi

echo ""
echo -e "${C_BOLD}──────────────────────────────────────────────────────────${C_RESET}"
echo -e "${C_BOLD} Clean Mode${C_RESET}"
if [[ "${DRY_RUN}" == true ]]; then
    echo -e "  ${C_YELLOW}DRY RUN — nothing will actually be deleted.${C_RESET}"
fi
echo ""

# Re-detect and number the visible experiments
declare -a CLEAN_CANDIDATES
echo "  Visible experiments:"
for i in "${!VISIBLE_DIRS[@]}"; do
    local_status="${EXP_STATUSES[i]}"
    disk="$(du_human "${VISIBLE_DIRS[i]}")"
    col="$(status_color "${local_status}")"
    printf "  [%3d]  ${col}%-12s${C_RESET}  %-36s  %6s  %s\n" \
        $((i+1)) "${local_status}" "${VISIBLE_NAMES[i]}" "${disk}" "${VISIBLE_GROUPS[i]}"
done

echo ""
echo "  Enter numbers to remove (space- or comma-separated), ranges (e.g. 2-5),"
echo "  'all' to remove everything listed, or 'q' to quit:"
echo -n "  > "
read -r SELECTION

[[ "${SELECTION}" == "q" || -z "${SELECTION}" ]] && echo "  Aborted." && exit 0

# Parse selection
declare -a SELECTED_INDICES

expand_selection() {
    local raw="$1"
    raw="${raw//,/ }"
    for tok in ${raw}; do
        if [[ "${tok}" == "all" ]]; then
            for j in "${!VISIBLE_DIRS[@]}"; do SELECTED_INDICES+=($j); done
        elif [[ "${tok}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}"
            for (( k=lo; k<=hi; k++ )); do
                local idx=$(( k - 1 ))
                [[ "${idx}" -ge 0 && "${idx}" -lt "${#VISIBLE_DIRS[@]}" ]] && SELECTED_INDICES+=("${idx}")
            done
        elif [[ "${tok}" =~ ^[0-9]+$ ]]; then
            local idx=$(( tok - 1 ))
            [[ "${idx}" -ge 0 && "${idx}" -lt "${#VISIBLE_DIRS[@]}" ]] && SELECTED_INDICES+=("${idx}")
        else
            echo "  WARNING: unrecognized token '${tok}' — skipped" >&2
        fi
    done
}

expand_selection "${SELECTION}"

# Deduplicate
mapfile -t SELECTED_INDICES < <(printf '%s\n' "${SELECTED_INDICES[@]}" | sort -nu)

if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
    echo "  No valid experiments selected. Aborted." >&2
    exit 0
fi

echo ""
echo "  The following experiments will be ${DRY_RUN:+[DRY-RUN] }PERMANENTLY DELETED:"
echo ""
TOTAL_BYTES=0
for idx in "${SELECTED_INDICES[@]}"; do
    dir="${VISIBLE_DIRS[idx]}"
    name="${VISIBLE_NAMES[idx]}"
    status="${EXP_STATUSES[idx]}"
    disk="$(du_human "${dir}")"
    col="$(status_color "${status}")"
    printf "    ${col}%-12s${C_RESET}  %-38s  %s  → %s\n" \
        "${status}" "${name}" "${disk}" "${dir}"
done
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo "  [DRY RUN] No files were deleted."
    exit 0
fi

echo -n "  Confirm deletion? Type 'yes' to proceed, anything else to abort: "
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "  Aborted."
    exit 0
fi

echo ""
REMOVED=0
ERRORED=0
for idx in "${SELECTED_INDICES[@]}"; do
    dir="${VISIBLE_DIRS[idx]}"
    name="${VISIBLE_NAMES[idx]}"
    # metadata/setup/ is write-locked by setup.sh (chmod -R a-w).
    # Unlock before removal so rm -rf can delete every file.
    chmod -R u+w "${dir}" 2>/dev/null || true
    if rm -rf "${dir}"; then
        echo -e "  ${C_GREEN}✓${C_RESET}  Removed: ${name}  (${dir})"
        (( REMOVED++ )) || true
    else
        echo -e "  ${C_RED}✗${C_RESET}  Failed to remove: ${name}  (${dir})" >&2
        (( ERRORED++ )) || true
    fi
done

echo ""
echo "  Done: ${REMOVED} removed, ${ERRORED} errors."
