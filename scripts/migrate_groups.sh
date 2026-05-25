#!/usr/bin/env bash
# =============================================================================
# migrate_groups.sh — Reorganise WW3 experiments into group subdirectories
# =============================================================================
# Version: 1.0
#
# Converts the flat experiments layout:
#   experiments/<exp_name>/
#
# into a grouped layout:
#   experiments/<group>/<sub_name>/
#
# and updates the hardcoded absolute paths inside each exp_config.sh.
#
# Usage:
#   migrate_groups.sh --by-physics [OPTIONS]
#   migrate_groups.sh --by-tag     [OPTIONS]
#   migrate_groups.sh --group <GRP> --experiments <e1>[,<e2>,...] [OPTIONS]
#
# Grouping modes (choose one):
#   --by-physics        Calibration experiments: strip the period suffix from
#                       the experiment name (__<period> last token, matched
#                       against periods/*.period files).
#                       Group  = everything before the last __ period token
#                       Subdir = just the period name
#                       e.g. with_sic__bm155__storm_eunice_2022
#                         →  with_sic__bm155 / storm_eunice_2022
#
#   --by-tag            Benchmark experiments: use the primary phase/type tag
#                       read from EXP_TAGS in each exp_config.sh.
#                       Tag priority: phase1 phase2 phase3 phase4 calibration
#                                     ref scaling compiler ablation
#                       (first match wins; falls back to "other")
#                       Subdir = same name as before (exp_name unchanged)
#
#   --group <GRP>       Manual: move the experiments listed with --experiments
#   --experiments <E>   Comma-separated experiment names to move (with --group)
#
# Safety options:
#   --dry-run           Show the plan without moving anything (default if --apply
#                       is not given)
#   --apply             Actually perform the moves (requires explicit flag)
#   --no-color          Disable ANSI colour codes
#   -h|--help           Show this help
#
# After migrating, use scan_experiments.sh to verify the new layout.
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXP_ROOT="${BENCH_DIR}/experiments"
PERIODS_DIR="${BENCH_DIR}/periods"
CAL_LOG="${PERIODS_DIR}/calibration_log.csv"

# --------------------------------------------------------------------------
# Colours
# --------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
GREY='\033[0;90m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]] || [[ ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" BOLD="" GREY="" NC=""
fi

# --------------------------------------------------------------------------
function usage() {
    cat <<EOM

${BOLD}${SCRIPT_NAME}${NC}  v${VERSION}  — Reorganise WW3 experiments into group subdirectories

${BOLD}Usage:${NC}
  ${SCRIPT_NAME} --by-physics [--dry-run|--apply] [--no-color]
  ${SCRIPT_NAME} --by-tag     [--dry-run|--apply] [--no-color]
  ${SCRIPT_NAME} --group <GRP> --experiments <e1>[,<e2>,...] [--dry-run|--apply]

${BOLD}Grouping modes:${NC}
  --by-physics      Strip period suffix → physics fingerprint becomes group,
                    period name becomes sub-experiment name.
                    Requires experiments named: <prefix>__<period>
  --by-tag          Group by primary tag in exp_config.sh (phase1/phase2/…/calibration)
                    Sub-experiment name stays the same as exp_name.
  --group <GRP>     Manually move listed experiments into <GRP>/.
  --experiments <E> Comma-separated experiment names (required with --group).

${BOLD}Safety:${NC}
  --dry-run  (default) Show plan only — nothing is moved.
  --apply             Perform the moves, updating exp_config.sh paths afterwards.

${BOLD}Examples:${NC}
  ${SCRIPT_NAME} --by-physics --dry-run
  ${SCRIPT_NAME} --by-physics --apply
  ${SCRIPT_NAME} --by-tag --dry-run
  ${SCRIPT_NAME} --group phase4 --experiments p4_pin_scatter_n60,p4_pin_compact_n60 --apply
EOM
    exit 0
}

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
ok()   { printf "  ${GREEN}✓${NC}  %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC}  %s\n" "$*"; }
fail() { printf "  ${RED}✗${NC}  %s\n" "$*" >&2; }
info() { printf "     %s\n" "$*"; }
step() { printf "\n${BOLD}%s${NC}\n" "$*"; }

# --------------------------------------------------------------------------
# Load known period names from periods/*.period into an associative array
# --------------------------------------------------------------------------
declare -A KNOWN_PERIODS

load_known_periods() {
    shopt -s nullglob
    local pf
    for pf in "${PERIODS_DIR}"/*.period; do
        [[ -f "${pf}" ]] && KNOWN_PERIODS["$(basename "${pf}" .period)"]=1
    done
    shopt -u nullglob
}

# --------------------------------------------------------------------------
# Determine group + sub-name for --by-physics mode.
# Sets globals: _GROUP  _SUBNAME  _SKIP_REASON
# --------------------------------------------------------------------------
physics_group() {
    local exp_name="$1"
    _GROUP=""
    _SUBNAME="${exp_name}"
    _SKIP_REASON=""

    # The exp_name must contain at least one __ separator
    if [[ "${exp_name}" != *__* ]]; then
        _SKIP_REASON="no __ separator — not a calibration experiment"
        return
    fi

    # Extract the last __-delimited token
    local last_token="${exp_name##*__}"

    # Check it's a known period
    if [[ -z "${KNOWN_PERIODS[${last_token}]+x}" ]]; then
        _SKIP_REASON="last token '${last_token}' is not a known period (not in periods/*.period)"
        return
    fi

    _GROUP="${exp_name%__*}"   # everything before the last __
    _SUBNAME="${last_token}"   # just the period name
}

# --------------------------------------------------------------------------
# Determine group for --by-tag mode.
# Sets globals: _GROUP  _SUBNAME  _SKIP_REASON
# Tag priority list (first matching tag wins).
# --------------------------------------------------------------------------
TAG_PRIORITY=(phase1 phase2 phase3 phase4 calibration ref scaling compiler ablation storm)

tag_group() {
    local exp_dir="$1"
    local exp_name="$2"
    local config="${exp_dir}/exp_config.sh"
    _GROUP=""
    _SUBNAME="${exp_name}"
    _SKIP_REASON=""

    if [[ ! -f "${config}" ]]; then
        _SKIP_REASON="no exp_config.sh"
        return
    fi

    local raw_tags
    raw_tags=$(grep '^export TAGS=' "${config}" 2>/dev/null | cut -d'"' -f2 || true)
    if [[ -z "${raw_tags}" ]]; then
        _SKIP_REASON="TAGS not set in exp_config.sh"
        return
    fi

    local t
    for t in "${TAG_PRIORITY[@]}"; do
        if [[ ",${raw_tags}," == *",${t},"* ]]; then
            _GROUP="${t}"
            return
        fi
    done

    _GROUP="other"
}

# --------------------------------------------------------------------------
# Perform one migration move.
# Moves experiments/<exp_name>/ → experiments/<group>/<subname>/
# Updates hardcoded absolute paths in exp_config.sh.
# --------------------------------------------------------------------------
do_migrate() {
    local old_name="$1"
    local group="$2"
    local subname="$3"
    local dry_run="$4"

    local old_dir="${EXP_ROOT}/${old_name}"
    local new_group_dir="${EXP_ROOT}/${group}"
    local new_dir="${new_group_dir}/${subname}"
    local config_in_new="${new_dir}/exp_config.sh"

    if [[ ! -d "${old_dir}" ]]; then
        fail "Source not found: ${old_dir}"
        return 1
    fi

    if [[ -d "${new_dir}" ]]; then
        fail "Destination already exists: ${new_dir} — skipping '${old_name}'"
        return 1
    fi

    local disk
    disk=$(du -sh "${old_dir}" 2>/dev/null | awk '{print $1}' || echo "?")

    printf "  %-52s → ${BOLD}%s${NC}/${YELLOW}%s${NC}  [%s]\n" \
        "${old_name}" "${group}" "${subname}" "${disk}"

    if [[ "${dry_run}" == true ]]; then
        return 0
    fi

    # Create group directory if needed
    if ! mkdir -p "${new_group_dir}"; then
        fail "Could not create group dir: ${new_group_dir}"
        return 1
    fi

    # Move the experiment directory
    if ! mv "${old_dir}" "${new_dir}"; then
        fail "mv failed: ${old_dir} → ${new_dir}"
        return 1
    fi

    # Update hardcoded paths in exp_config.sh
    if [[ -f "${config_in_new}" ]]; then
        # The config is write-locked; unlock briefly, patch, re-lock
        chmod u+w "${config_in_new}"
        sed -i "s|${old_dir}|${new_dir}|g" "${config_in_new}"
        # Also update EXP_NAME if it changes (--by-physics renames subname)
        if [[ "${old_name}" != "${subname}" ]]; then
            sed -i "s|^export EXP_NAME=\"${old_name}\"|export EXP_NAME=\"${subname}\"|" \
                "${config_in_new}"
            # Add EXP_GROUP if not already present
            if ! grep -q '^export EXP_GROUP=' "${config_in_new}"; then
                printf '\nexport EXP_GROUP="%s"\n' "${group}" >> "${config_in_new}"
            fi
        fi
        chmod a-w "${config_in_new}"
    else
        warn "exp_config.sh not found in ${new_dir} — paths not updated"
    fi

    # Update calibration_log.csv: replace old exp_name with group/subname
    if [[ -f "${CAL_LOG}" && "${old_name}" != "${subname}" ]]; then
        local new_logname="${group}/${subname}"
        sed -i "s|,${old_name},|,${new_logname},|g" "${CAL_LOG}"
    fi

    ok "Moved: ${old_name} → ${group}/${subname}"
    return 0
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
function main() {
    local mode=""
    local manual_group=""
    local manual_exps=""
    local dry_run=true   # safe default: must pass --apply to actually move
    local no_color=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --by-physics)    mode="by-physics";  shift ;;
            --by-tag)        mode="by-tag";      shift ;;
            --group)         mode="manual"; manual_group="$2"; shift 2 ;;
            --experiments)   manual_exps="$2"; shift 2 ;;
            --dry-run)       dry_run=true;        shift ;;
            --apply)         dry_run=false;       shift ;;
            --no-color)      no_color=true;       shift ;;
            -h|--help)       usage ;;
            *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
        esac
    done

    if [[ -z "${mode}" ]]; then
        echo -e "${RED}Error:${NC} specify one of --by-physics, --by-tag, or --group <GRP>." >&2
        usage
    fi

    if [[ "${mode}" == "manual" ]]; then
        if [[ -z "${manual_group}" ]]; then
            echo -e "${RED}Error:${NC} --group requires a group name." >&2
            exit 1
        fi
        if [[ -z "${manual_exps}" ]]; then
            echo -e "${RED}Error:${NC} --group requires --experiments <e1,e2,...>." >&2
            exit 1
        fi
    fi

    load_known_periods

    # ------------------------------------------------------------------
    echo ""
    echo -e "${BOLD}WW3 Experiment Group Migration  (v${VERSION})${NC}"
    echo "  Root    : ${EXP_ROOT}"
    echo "  Mode    : ${mode}"
    echo "  Action  : $(if [[ "${dry_run}" == true ]]; then echo 'DRY RUN (pass --apply to execute)'; else echo 'APPLY'; fi)"
    echo "  Known periods: ${#KNOWN_PERIODS[@]}"
    # ------------------------------------------------------------------

    # Build list of (exp_name, group, subname) triples
    declare -a PLAN_OLD PLAN_GROUP PLAN_SUB PLAN_SKIP_REASON

    if [[ "${mode}" == "manual" ]]; then
        IFS=',' read -ra manual_list <<< "${manual_exps}"
        for en in "${manual_list[@]}"; do
            en="${en// /}"
            local edir="${EXP_ROOT}/${en}"
            if [[ ! -d "${edir}" ]]; then
                PLAN_OLD+=("${en}")
                PLAN_GROUP+=("")
                PLAN_SUB+=("")
                PLAN_SKIP_REASON+=("directory not found: ${edir}")
            else
                PLAN_OLD+=("${en}")
                PLAN_GROUP+=("${manual_group}")
                PLAN_SUB+=("${en}")
                PLAN_SKIP_REASON+=("")
            fi
        done
    else
        # Enumerate flat experiments (top-level dirs that contain exp_config.sh)
        shopt -s nullglob
        local entry
        for entry in "${EXP_ROOT}"/*/; do
            [[ ! -d "${entry}" ]] && continue
            local ename
            ename="$(basename "${entry%/}")"
            local config="${entry}/exp_config.sh"
            # Skip if already grouped (no exp_config.sh at this level = it's a group dir)
            [[ ! -f "${config}" ]] && continue

            if [[ "${mode}" == "by-physics" ]]; then
                physics_group "${ename}"
            else
                tag_group "${entry%/}" "${ename}"
            fi

            PLAN_OLD+=("${ename}")
            PLAN_GROUP+=("${_GROUP}")
            PLAN_SUB+=("${_SUBNAME}")
            PLAN_SKIP_REASON+=("${_SKIP_REASON}")
        done
        shopt -u nullglob
    fi

    if [[ ${#PLAN_OLD[@]} -eq 0 ]]; then
        echo ""
        echo "  No flat experiments found under ${EXP_ROOT}"
        exit 0
    fi

    # ------------------------------------------------------------------
    # Print plan
    # ------------------------------------------------------------------
    step "Migration plan:"
    printf "\n  %-52s  %-26s  %s\n" "EXPERIMENT" "GROUP" "SUBDIR"
    printf "  %s\n" "$(printf '%.0s─' {1..90})"

    local n_will_move=0 n_skip=0
    local i
    for i in "${!PLAN_OLD[@]}"; do
        local en="${PLAN_OLD[$i]}"
        local grp="${PLAN_GROUP[$i]}"
        local sub="${PLAN_SUB[$i]}"
        local why="${PLAN_SKIP_REASON[$i]}"

        if [[ -n "${why}" ]]; then
            printf "  ${GREY}%-52s  %-26s  SKIP: %s${NC}\n" "${en}" "" "${why}"
            (( n_skip++ )) || true
        elif [[ "${grp}" == "${en}" || ( "${grp}" == "${en%__*}" && "${sub}" == "${en}" ) ]]; then
            # Would create experiments/<exp>/<exp> — skip trivial moves
            printf "  ${GREY}%-52s  %-26s  SKIP: already in root, no period suffix${NC}\n" "${en}" ""
            (( n_skip++ )) || true
        else
            printf "  %-52s  ${BOLD}%-26s${NC}  ${YELLOW}%s${NC}\n" "${en}" "${grp}" "${sub}"
            (( n_will_move++ )) || true
        fi
    done

    printf "\n  Total: %d to move, %d skipped\n" "${n_will_move}" "${n_skip}"

    if [[ "${n_will_move}" -eq 0 ]]; then
        echo ""
        echo "  Nothing to do."
        exit 0
    fi

    if [[ "${dry_run}" == true ]]; then
        echo ""
        echo -e "  ${YELLOW}DRY RUN — pass --apply to execute the migration above.${NC}"
        exit 0
    fi

    # ------------------------------------------------------------------
    # Confirm and execute
    # ------------------------------------------------------------------
    echo ""
    echo -e "  ${RED}WARNING: This will move directories and edit exp_config.sh files.${NC}"
    echo -n "  Type 'yes' to proceed: "
    read -r CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "  Aborted."
        exit 0
    fi

    echo ""
    step "Executing migration:"
    local n_ok=0 n_err=0
    for i in "${!PLAN_OLD[@]}"; do
        local en="${PLAN_OLD[$i]}"
        local grp="${PLAN_GROUP[$i]}"
        local sub="${PLAN_SUB[$i]}"
        local why="${PLAN_SKIP_REASON[$i]}"

        [[ -n "${why}" ]] && continue
        # Skip trivial
        if [[ "${grp}" == "${en}" || ( "${grp}" == "${en%__*}" && "${sub}" == "${en}" ) ]]; then
            continue
        fi

        if do_migrate "${en}" "${grp}" "${sub}" "${dry_run}"; then
            (( n_ok++ )) || true
        else
            (( n_err++ )) || true
        fi
    done

    echo ""
    echo -e "${BOLD}Done:${NC}  ${GREEN}${n_ok} moved${NC}  |  ${RED}${n_err} errors${NC}"
    echo ""
    echo "  Verify with:"
    echo "    ./scripts/scan_experiments.sh"
}

main "$@"
