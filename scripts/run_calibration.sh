#!/usr/bin/env bash
# =============================================================================
# run_calibration.sh — Dispatch a WW3 config across multiple named storm periods
# =============================================================================
# Version: 1.0
#
# For each specified period:
#   1. Calls setup.sh -c <config_dir> -P <period> -e <prefix>__<period>
#   2. Calls run_exp.sh -e <prefix>__<period> [...forwarded options...]
#   3. Appends a row to periods/calibration_log.csv
#
# Usage:
#   run_calibration.sh -c <config_dir> -P <p1>[,<p2>,...] [run_exp options]
#   run_calibration.sh -c <config_dir> --all-periods [run_exp options]
#
# Options:
#   -c  <config_dir>          Config/namelist directory (required)
#                             e.g. configs/CARRA2_exp_1  or  CARRA2_exp_1
#   -P  <p1>[,<p2>,...]       Comma-separated period name(s) (required unless --all-periods)
#   -e  <prefix>              Experiment name prefix (default: config dir basename)
#                             Exp dirs will be named  <prefix>__<period>
#   --all-periods             Use every .period file found in periods/
#   --dry-run                 Passed to both setup.sh and run_exp.sh; no submissions
#   -h|--help                 Show this help
#
# All other flags are forwarded verbatim to run_exp.sh:
#   -N, -n, --ntasks, --cpus-per-task, --mem-per-cpu, -t, --post, -s, -p, etc.
#
# Examples:
#   ./run_calibration.sh -c configs/CARRA2_exp_1 -P storm_eunice_2022 -N 12 -n 56 -t 02:00:00 --post
#   ./run_calibration.sh -c configs/CARRA2_exp_1 -P storm_eunice_2022,storm_babet_2023 -N 12 -n 56
#   ./run_calibration.sh -c configs/CARRA2_exp_1 --all-periods -N 12 -n 56 --dry-run
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERIODS_DIR="${BENCH_DIR}/periods"
CAL_LOG="${PERIODS_DIR}/calibration_log.csv"
CAL_LOG_HEADER="timestamp,config,period,exp_name,start_date,end_date,nodes,ntasks,shel_job_id,status"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BOLD="" NC=""
fi

function usage() {
    cat <<EOM

${BOLD}run_calibration.sh${NC} — Dispatch a WW3 config across multiple periods  (v${VERSION})

${BOLD}Usage:${NC}
  ${SCRIPT_NAME} -c <config_dir> -P <period1>[,<period2>,...] [run_exp options]
  ${SCRIPT_NAME} -c <config_dir> --all-periods [run_exp options]

${BOLD}Required:${NC}
  -c  <config_dir>            Config/namelist directory  (e.g. configs/CARRA2_exp_1)
  -P  <p1>[,<p2>,...]         Comma-separated period names  OR  use --all-periods

${BOLD}Optional:${NC}
  -e  <prefix>                Experiment name prefix (default: config dirname)
                              Experiment dirs: <prefix>__<period_name>
  --all-periods               Run every .period file found in ${PERIODS_DIR}/
  --dry-run                   No submissions or directories created
  -h|--help                   Show this help

${BOLD}Forwarded to run_exp.sh (pass after your -c / -P flags):${NC}
  -N <nodes>  -n <tasks/node>  --ntasks <N>  --cpus-per-task <N>
  --mem-per-cpu <MB>  -t <wall_time>  --post  -s  -p

${BOLD}Examples:${NC}
  ${SCRIPT_NAME} -c configs/CARRA2_exp_1 -P storm_eunice_2022 -N 12 -n 56 -t 02:00:00 --post
  ${SCRIPT_NAME} -c configs/CARRA2_exp_1 -P storm_eunice_2022,storm_babet_2023 -N 12 -n 56
  ${SCRIPT_NAME} -c configs/CARRA2_exp_1 --all-periods -N 12 -n 56 --dry-run

${BOLD}Period management:${NC}
  Register periods first:
    ./manage_periods.sh add storm_eunice_2022 --start 20220218 --end 20220221 --desc "Storm Eunice"
  View log:
    ./manage_periods.sh log --config CARRA2_exp_1

EOM
    exit 1
}

function ensure_log() {
    mkdir -p "${PERIODS_DIR}"
    if [[ ! -f "${CAL_LOG}" ]]; then
        echo "${CAL_LOG_HEADER}" > "${CAL_LOG}"
    fi
}

function append_log() {
    local config="$1" period="$2" exp_name="$3"
    local start_date="$4" end_date="$5"
    local nodes="$6" ntasks="$7"
    local shel_job_id="$8" status="$9"
    local ts
    ts=$(date --iso-8601=seconds)
    echo "${ts},${config},${period},${exp_name},${start_date},${end_date},${nodes},${ntasks},${shel_job_id},${status}" \
        >> "${CAL_LOG}"
}

function main() {
    local config_dir=""
    local periods_arg=""
    local exp_prefix=""
    local all_periods=false
    local dry_run=false
    local fwd_args=()

    # Manual argument parsing — collect our flags, forward everything else
    local i=0
    local args=("$@")

    while [[ ${i} -lt ${#args[@]} ]]; do
        local arg="${args[${i}]}"
        case "${arg}" in
            -c)
                i=$(( i + 1 )); config_dir="${args[${i}]}" ;;
            -c*)
                config_dir="${arg#-c}" ;;
            -P)
                i=$(( i + 1 )); periods_arg="${args[${i}]}" ;;
            -P*)
                periods_arg="${arg#-P}" ;;
            -e)
                i=$(( i + 1 )); exp_prefix="${args[${i}]}" ;;
            -e*)
                exp_prefix="${arg#-e}" ;;
            --all-periods)
                all_periods=true ;;
            --dry-run)
                dry_run=true
                fwd_args+=("--dry-run") ;;
            -h|--help)
                usage ;;
            # Forward everything else to run_exp.sh
            *)
                fwd_args+=("${arg}") ;;
        esac
        i=$(( i + 1 ))
    done

    # Validate required arguments
    if [[ -z "${config_dir}" ]]; then
        echo -e "${RED}Error:${NC} -c <config_dir> is required." >&2; usage
    fi
    if [[ -z "${periods_arg}" && "${all_periods}" == false ]]; then
        echo -e "${RED}Error:${NC} -P <periods> or --all-periods is required." >&2; usage
    fi

    # Resolve config directory (try relative to BENCH_DIR if not found directly)
    if [[ ! -d "${config_dir}" ]]; then
        if [[ -d "${BENCH_DIR}/${config_dir}" ]]; then
            config_dir="${BENCH_DIR}/${config_dir}"
        else
            echo -e "${RED}Error:${NC} Config directory not found: ${config_dir}" >&2
            exit 1
        fi
    fi
    config_dir="$(cd "${config_dir}" && pwd)"
    local config_name
    config_name="$(basename "${config_dir}")"

    # Default experiment prefix = config name
    if [[ -z "${exp_prefix}" ]]; then
        exp_prefix="${config_name}"
    fi

    # Build period list
    local period_list=()
    if [[ "${all_periods}" == true ]]; then
        local -a files=( "${PERIODS_DIR}"/*.period )
        if [[ ! -e "${files[0]}" ]]; then
            echo -e "${RED}Error:${NC} No .period files found in ${PERIODS_DIR}" >&2
            exit 1
        fi
        for f in "${files[@]}"; do
            [[ -f "$f" ]] && period_list+=("$(basename "${f}" .period)")
        done
    else
        IFS=',' read -r -a period_list <<< "${periods_arg}"
    fi

    # Validate all period files exist before submitting anything
    for period in "${period_list[@]}"; do
        local pf="${PERIODS_DIR}/${period}.period"
        if [[ ! -f "${pf}" ]]; then
            echo -e "${RED}Error:${NC} Period not found: '${period}'" >&2
            echo "  Expected: ${pf}" >&2
            echo "  Register it with:  ${BENCH_DIR}/scripts/manage_periods.sh add ${period} --start YYYYMMDD --end YYYYMMDD" >&2
            exit 1
        fi
    done

    ensure_log

    echo "============================================================"
    echo " WW3 Calibration Run Dispatcher  (v${VERSION})"
    echo "============================================================"
    echo "  Config dir  : ${config_dir}"
    echo "  Config name : ${config_name}"
    echo "  Exp prefix  : ${exp_prefix}"
    echo "  Periods     : ${#period_list[@]}  (${period_list[*]})"
    echo "  Dry-run     : ${dry_run}"
    [[ ${#fwd_args[@]} -gt 0 ]] && echo "  Fwd to run_exp: ${fwd_args[*]}"
    echo "============================================================"
    echo ""

    local n_success=0
    local n_failed=0

    for period in "${period_list[@]}"; do
        local pf="${PERIODS_DIR}/${period}.period"
        local exp_name="${exp_prefix}__${period}"

        # Extract period dates for logging (without sourcing into current shell)
        local start_date end_date
        start_date=$(grep '^START_DATE=' "${pf}" | cut -d'"' -f2 | awk '{print $1}')
        end_date=$(grep   '^END_DATE='   "${pf}" | cut -d'"' -f2 | awk '{print $1}')
        local period_duration_days
        period_duration_days=$(grep '^PERIOD_DURATION_DAYS=' "${pf}" | cut -d'"' -f2)

        echo "------------------------------------------------------------"
        echo "  Period    : ${period}"
        echo "  Exp name  : ${exp_name}"
        echo "  Dates     : ${start_date} → ${end_date}"
        [[ -n "${period_duration_days}" ]] && echo "  Duration  : ${period_duration_days} days"
        echo "------------------------------------------------------------"

        # ----------------------------------------------------------------
        # Step 1 — setup.sh
        # ----------------------------------------------------------------
        echo "[1/2] Setting up experiment: ${exp_name}"
        local setup_cmd=(
            "${BENCH_DIR}/scripts/setup.sh"
            -e "${exp_name}"
            -c "${config_dir}"
            -P "${period}"
        )
        [[ "${dry_run}" == true ]] && setup_cmd+=("--dry-run")

        if ! "${setup_cmd[@]}"; then
            echo -e "${RED}ERROR:${NC} setup.sh failed for period '${period}' — skipping." >&2
            append_log "${config_name}" "${period}" "${exp_name}" \
                "${start_date}" "${end_date}" "?" "?" "FAILED_SETUP" "SETUP_FAILED"
            (( n_failed++ )) || true
            echo ""
            continue
        fi

        # Build -d flag from stored duration if not already in fwd_args
        local extra_d_flag=()
        if [[ -n "${period_duration_days}" ]]; then
            local already_has_d=false
            for a in "${fwd_args[@]}"; do
                [[ "$a" == "-d" ]] && { already_has_d=true; break; }
            done
            if [[ "${already_has_d}" == false ]]; then
                extra_d_flag=(-d "${period_duration_days}")
            fi
        fi

        # ----------------------------------------------------------------
        # Step 2 — run_exp.sh
        # ----------------------------------------------------------------
        echo ""
        echo "[2/2] Submitting jobs: ${exp_name}"
        local run_cmd=(
            "${BENCH_DIR}/scripts/run_exp.sh"
            -e "${exp_name}"
            "${extra_d_flag[@]}"
            "${fwd_args[@]}"
        )

        local run_output
        if ! run_output=$("${run_cmd[@]}" 2>&1); then
            echo -e "${RED}ERROR:${NC} run_exp.sh failed for period '${period}'." >&2
            echo "${run_output}" >&2
            append_log "${config_name}" "${period}" "${exp_name}" \
                "${start_date}" "${end_date}" "?" "?" "FAILED_SUBMIT" "SUBMIT_FAILED"
            (( n_failed++ )) || true
            echo ""
            continue
        fi
        echo "${run_output}"

        # Parse shel job ID and task count from run_exp.sh output
        local shel_job_id ntasks_logged
        shel_job_id=$(echo "${run_output}" | grep -E 'Shel job\s*:' | grep -oE '[0-9]+' | tail -1)
        shel_job_id="${shel_job_id:-unknown}"
        ntasks_logged=$(echo "${run_output}" | grep -E 'Total tasks\s*:' | grep -oE '[0-9]+' | head -1)
        ntasks_logged="${ntasks_logged:-?}"

        append_log "${config_name}" "${period}" "${exp_name}" \
            "${start_date}" "${end_date}" "?" "${ntasks_logged}" \
            "${shel_job_id}" "SUBMITTED"

        echo -e "${GREEN}Logged:${NC} ${exp_name} (shel job: ${shel_job_id})"
        (( n_success++ )) || true
        echo ""
    done

    echo "============================================================"
    echo " Calibration dispatch complete"
    echo "  Submitted : ${n_success}/${#period_list[@]}"
    echo "  Failed    : ${n_failed}/${#period_list[@]}"
    echo "  Log       : ${CAL_LOG}"
    echo "============================================================"
    echo ""
    echo " Review log:"
    echo "   ${BENCH_DIR}/scripts/manage_periods.sh log --config ${config_name}"
    echo ""

    if [[ "${n_failed}" -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
