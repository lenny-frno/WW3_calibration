#!/usr/bin/env bash
# =============================================================================
# manage_periods.sh — WW3 Period Registry Manager
# =============================================================================
# Version: 1.0
#
# Manages named simulation periods used for WW3 calibration runs.
# Periods define start/end dates for specific storm events or time windows.
# Each period is stored as a <name>.period file in periods/.
#
# Usage: manage_periods.sh <subcommand> [options]
#
# Subcommands:
#   list                                               List all periods (table)
#   add  <name> --start YYYYMMDD --end YYYYMMDD        Register a new period
#              [--desc "text"] [--tags t1,t2]
#   show <name>                                        Print full period details
#   remove <name>                                      Delete period file
#   log  [--config <name>] [--period <name>]           Query calibration log
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

${BOLD}manage_periods.sh${NC} — WW3 Period Registry Manager  (v${VERSION})

Manages named simulation periods for WW3 calibration.
Period files: ${PERIODS_DIR}/<name>.period

${BOLD}Usage:${NC}
  ${SCRIPT_NAME} list
  ${SCRIPT_NAME} add  <name> --start YYYYMMDD --end YYYYMMDD [--desc "..."] [--tags t1,t2]
  ${SCRIPT_NAME} show <name>
  ${SCRIPT_NAME} remove <name>
  ${SCRIPT_NAME} log  [--config <config_name>] [--period <period_name>]

${BOLD}Subcommands:${NC}
  list      Table of all registered periods with dates, duration, and tags.
  add       Register a new named period.
  show      Print full details of a period.
  remove    Delete a period file (warns if log entries exist).
  log       Show calibration run log, optionally filtered by config or period.

${BOLD}Options for 'add':${NC}
  --start YYYYMMDD     Simulation start date (required)
  --end   YYYYMMDD     Simulation end date   (required)
  --desc  "text"       Human-readable description (optional)
  --tags  tag1,tag2    Comma-separated tags (optional)

${BOLD}Examples:${NC}
  ${SCRIPT_NAME} list
  ${SCRIPT_NAME} add storm_eunice_2022 --start 20220218 --end 20220221 --desc "Storm Eunice, North Sea" --tags storm,calibration
  ${SCRIPT_NAME} show storm_eunice_2022
  ${SCRIPT_NAME} remove storm_eunice_2022
  ${SCRIPT_NAME} log --config CARRA2_exp_1
  ${SCRIPT_NAME} log --period storm_eunice_2022

EOM
    exit 1
}

function ensure_dir() {
    if [[ ! -d "${PERIODS_DIR}" ]]; then
        mkdir -p "${PERIODS_DIR}"
    fi
    if [[ ! -f "${CAL_LOG}" ]]; then
        echo "${CAL_LOG_HEADER}" > "${CAL_LOG}"
    fi
}

# Display YYYYMMDD as YYYY-MM-DD
function format_date() {
    local d="$1"
    if [[ "${d}" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    else
        echo "${d}"
    fi
}

# Compute integer days between two YYYYMMDD strings using GNU date
function days_between() {
    local start="$1"
    local end="$2"
    local s_fmt="${start:0:4}-${start:4:2}-${start:6:2}"
    local e_fmt="${end:0:4}-${end:4:2}-${end:6:2}"
    local ts_start ts_end
    ts_start=$(date -d "${s_fmt}" +%s 2>/dev/null) || { echo "?"; return; }
    ts_end=$(date   -d "${e_fmt}" +%s 2>/dev/null) || { echo "?"; return; }
    echo $(( (ts_end - ts_start) / 86400 ))
}

# -----------------------------------------------------------------------
# Subcommand: list
# -----------------------------------------------------------------------
function cmd_list() {
    ensure_dir
    local files=( "${PERIODS_DIR}"/*.period )
    if [[ ! -e "${files[0]}" ]]; then
        echo "No periods registered yet."
        echo "Add one with:  ${SCRIPT_NAME} add <name> --start YYYYMMDD --end YYYYMMDD"
        return 0
    fi

    printf "${BOLD}%-32s  %-12s  %-12s  %-6s  %s${NC}\n" \
        "NAME" "START" "END" "DAYS" "DESCRIPTION"
    printf '%s\n' "$(printf '%0.s-' {1..85})"

    for f in "${files[@]}"; do
        [[ ! -f "$f" ]] && continue
        local name start end desc
        name=$(grep '^PERIOD_NAME=' "$f" | cut -d'"' -f2)
        start=$(grep '^START_DATE='  "$f" | cut -d'"' -f2 | awk '{print $1}')
        end=$(grep   '^END_DATE='    "$f" | cut -d'"' -f2 | awk '{print $1}')
        desc=$(grep  '^DESCRIPTION=' "$f" | cut -d'"' -f2)
        local days
        days=$(days_between "${start}" "${end}")
        printf "%-32s  %-12s  %-12s  %-6s  %s\n" \
            "${name}" \
            "$(format_date "${start}")" \
            "$(format_date "${end}")" \
            "${days}d" \
            "${desc:-—}"
    done
}

# -----------------------------------------------------------------------
# Subcommand: add
# -----------------------------------------------------------------------
function cmd_add() {
    local name="$1"; shift
    local start="" end="" desc="" tags=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start) shift; start="$1" ;;
            --end)   shift; end="$1"   ;;
            --desc)  shift; desc="$1"  ;;
            --tags)  shift; tags="$1"  ;;
            *) echo -e "${RED}Error:${NC} Unknown option: $1" >&2; usage ;;
        esac
        shift
    done

    if [[ -z "${name}" ]]; then
        echo -e "${RED}Error:${NC} period name is required." >&2; usage
    fi
    if [[ -z "${start}" ]]; then
        echo -e "${RED}Error:${NC} --start YYYYMMDD is required." >&2; usage
    fi
    if [[ -z "${end}" ]]; then
        echo -e "${RED}Error:${NC} --end YYYYMMDD is required." >&2; usage
    fi
    if ! [[ "${name}"  =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error:${NC} name must use only letters, digits, underscores, or hyphens." >&2; exit 1
    fi
    if ! [[ "${start}" =~ ^[0-9]{8}$ ]]; then
        echo -e "${RED}Error:${NC} --start must be YYYYMMDD (e.g. 20220218)." >&2; exit 1
    fi
    if ! [[ "${end}" =~ ^[0-9]{8}$ ]]; then
        echo -e "${RED}Error:${NC} --end must be YYYYMMDD (e.g. 20220221)." >&2; exit 1
    fi
    if [[ "${end}" -le "${start}" ]]; then
        echo -e "${RED}Error:${NC} --end must be after --start." >&2; exit 1
    fi

    ensure_dir

    local period_file="${PERIODS_DIR}/${name}.period"
    if [[ -f "${period_file}" ]]; then
        echo -e "${YELLOW}Warning:${NC} Period '${name}' already exists: ${period_file}"
        echo "  Use 'remove' first to replace it."
        exit 1
    fi

    local year="${start:0:4}"
    local month="${start:4:2}"
    local now
    now=$(date --iso-8601=seconds)
    local dur_days
    dur_days=$(days_between "${start}" "${end}")

    # WW3 date-time format: "YYYYMMDD HHMMSS"
    local start_ww3="${start} 000000"
    local end_ww3="${end} 000000"

    cat > "${period_file}" << PERIODEOF
# WW3 Period definition — managed by manage_periods.sh
# DO NOT EDIT manually — use: manage_periods.sh add/remove
PERIOD_NAME="${name}"
START_DATE="${start_ww3}"
END_DATE="${end_ww3}"
YEAR="${year}"
MONTH="${month}"
PERIOD_DURATION_DAYS="${dur_days}"
DESCRIPTION="${desc}"
TAGS="${tags}"
ADDED_AT="${now}"
PERIODEOF

    echo -e "${GREEN}Added period:${NC} ${name}"
    echo "  Start  : $(format_date "${start}") → WW3 format: ${start_ww3}"
    echo "  End    : $(format_date "${end}") → WW3 format: ${end_ww3}"
    echo "  Days   : ${dur_days}"
    [[ -n "${desc}" ]] && echo "  Desc   : ${desc}"
    [[ -n "${tags}" ]] && echo "  Tags   : ${tags}"
    echo "  File   : ${period_file}"
}

# -----------------------------------------------------------------------
# Subcommand: show
# -----------------------------------------------------------------------
function cmd_show() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        echo -e "${RED}Error:${NC} period name required." >&2; usage
    fi
    local period_file="${PERIODS_DIR}/${name}.period"
    if [[ ! -f "${period_file}" ]]; then
        echo -e "${RED}Error:${NC} Period '${name}' not found." >&2
        echo "  Expected: ${period_file}"
        echo "  Use '${SCRIPT_NAME} list' to see registered periods." >&2
        exit 1
    fi
    echo "============================================================"
    echo "  Period : ${name}"
    echo "  File   : ${period_file}"
    echo "============================================================"
    grep -v '^#' "${period_file}" | grep -v '^$'
    echo ""
    if [[ -f "${CAL_LOG}" ]]; then
        local count
        count=$(tail -n +2 "${CAL_LOG}" | awk -F',' -v p="${name}" '$3 == p' | wc -l || echo 0)
        echo "  Calibration runs logged: ${count}"
        if [[ "${count}" -gt 0 ]]; then
            echo ""
            echo "  Recent runs (last 5):"
            tail -n +2 "${CAL_LOG}" | awk -F',' -v p="${name}" '$3 == p' | tail -5 | sed 's/^/    /'
        fi
    fi
}

# -----------------------------------------------------------------------
# Subcommand: remove
# -----------------------------------------------------------------------
function cmd_remove() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        echo -e "${RED}Error:${NC} period name required." >&2; usage
    fi
    local period_file="${PERIODS_DIR}/${name}.period"
    if [[ ! -f "${period_file}" ]]; then
        echo -e "${RED}Error:${NC} Period '${name}' not found." >&2; exit 1
    fi

    if [[ -f "${CAL_LOG}" ]]; then
        local count
        count=$(tail -n +2 "${CAL_LOG}" | awk -F',' -v p="${name}" '$3 == p' | wc -l || echo 0)
        if [[ "${count}" -gt 0 ]]; then
            echo -e "${YELLOW}Warning:${NC} Period '${name}' has ${count} entr(ies) in calibration_log.csv."
            echo "  Log entries will be preserved; only the .period definition file will be removed."
            echo ""
            read -r -p "  Proceed? [y/N] " confirm
            if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
                echo "  Aborted."
                exit 0
            fi
        fi
    fi

    rm "${period_file}"
    echo -e "${GREEN}Removed:${NC} ${period_file}"
}

# -----------------------------------------------------------------------
# Subcommand: log
# -----------------------------------------------------------------------
function cmd_log() {
    local filter_config="" filter_period=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) shift; filter_config="$1" ;;
            --period) shift; filter_period="$1" ;;
            *) echo -e "${RED}Error:${NC} Unknown option: $1" >&2; usage ;;
        esac
        shift
    done

    if [[ ! -f "${CAL_LOG}" ]]; then
        echo "No calibration log found: ${CAL_LOG}"
        echo "  (created automatically by run_calibration.sh)"
        return 0
    fi

    head -1 "${CAL_LOG}"
    printf '%s\n' "$(printf '%0.s-' {1..120})"

    local body
    body=$(tail -n +2 "${CAL_LOG}")

    if [[ -n "${filter_config}" ]]; then
        body=$(echo "${body}" | awk -F',' -v cfg="${filter_config}" '$2 == cfg')
    fi
    if [[ -n "${filter_period}" ]]; then
        body=$(echo "${body}" | awk -F',' -v per="${filter_period}" '$3 == per')
    fi

    if [[ -z "${body}" ]]; then
        echo "  (no matching entries)"
    else
        echo "${body}"
    fi
}

# -----------------------------------------------------------------------
# main
# -----------------------------------------------------------------------
function main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    local subcmd="$1"; shift
    case "${subcmd}" in
        list)               cmd_list   "$@" ;;
        add)                cmd_add    "$@" ;;
        show)               cmd_show   "$@" ;;
        remove)             cmd_remove "$@" ;;
        log)                cmd_log    "$@" ;;
        -h|--help|help)     usage ;;
        --version)          echo "${SCRIPT_NAME} version ${VERSION}"; exit 0 ;;
        *)
            echo -e "${RED}Error:${NC} Unknown subcommand: '${subcmd}'" >&2
            usage
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
