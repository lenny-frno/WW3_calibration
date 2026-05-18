#!/usr/bin/env bash
# =============================================================================
# run_phase4_dtxy.sh — DTXY propagation timestep sensitivity study
# =============================================================================
# Version: 1.0
#
# WHAT IT DOES
# ------------
# Tests larger values of TIMESTEPS%DTXY in ww3_grid.nml to reduce the number
# of spatial-propagation sub-steps taken inside W3XYP2/W3UNO2 each timestep.
#
# Current settings (from DATA_ROOT/const/grid/CARRA2/ww3_grid.nml):
#   DTXY  = 90 s   ← CFL timestep for x-y propagation
#   DTMAX = 270 s  ← maximum global timestep  (3 × DTXY)
#   DTKTH = 135 s  ← CFL timestep for k-theta refraction  (1.5 × DTXY)
#   DTMIN = 10 s   ← minimum source-term timestep  (unchanged)
#
# DTXY determines the maximum number of calls to W3XYP2 per model step.
# The model calls W3XYP2 NTLOC = ceil(DTMAX / DTXY) times per global step.
# Increasing DTXY from 90 s → 120 s reduces NTLOC from 3 → 2:
#   90 s  → NTLOC = 3 calls  (current)
#  120 s  → NTLOC = 2 calls  (~33% fewer propagation steps)
#  135 s  → NTLOC = 2 calls  (same as 120 if DTMAX=270, but right at the edge)
#
# SAFETY NOTE
# -----------
# Increasing DTXY above the true CFL limit causes numerical instabilities.
# The 90 s value was chosen as ~90% of a conservative Tcfl.  The actual
# Tcfl for the CARRA2 grid depends on the minimum grid spacing (in meters)
# and the maximum group velocity (≈ g/2ω_min).  If results look reasonable
# (smooth fields, no NaN/Inf in output), the new timestep is acceptable.
#
# Recommended test sequence
# -------------------------
#   100 s → safe incremental step
#   120 s → likely stable; reduces NTLOC 3→2 if DTMAX≥240
#   135 s → same NTLOC as 120 (NTLOC=2 because ceil(270/135)=2 exactly)
#   180 s → NTLOC=2 but at the CFL edge; only try if 120/135 are stable
#
# WHAT CHANGES BY DTXY VALUE
# --------------------------
#   DTXY    NTLOC   DTMAX kept   DTKTH kept   Expected gain vs 90 s
#   90      3       270          135          baseline
#   100     3       270          150          ~0% (same NTLOC)
#   120     3*      270          180          ~0% at 270/3=90 eff steps BUT
#                                              each step is larger → may allow
#                                              a larger actual propagation step
#   120     2       240          180          ~33% if DTMAX also raised to 240
#   135     2       270          135          ~33% (ceil(270/135)=2 exactly)
#   180     2       360          180          ~33% with DTMAX=360
#
# * Note: ceil(270/120)=3, so DTXY=120 with DTMAX=270 still gives NTLOC=3.
#   To benefit from NTLOC=2 at DTXY=120, set DTMAX=240, DTKTH=120.
#
# This script tests three strategies:
#   90_ref   : reference; DTXY=90 DTMAX=270 DTKTH=135  (NTLOC=3)
#   120_dtmax240 : DTXY=120 DTMAX=240 DTKTH=120        (NTLOC=2, -33%)
#   135_dtmax270 : DTXY=135 DTMAX=270 DTKTH=135        (NTLOC=2, -33%)
#   180_dtmax360 : DTXY=180 DTMAX=360 DTKTH=180        (NTLOC=2, bolder)
#
# USAGE
# -----
#   # Run all strategies:
#   bash run_phase4_dtxy.sh --all
#
#   # Run a single strategy:
#   bash run_phase4_dtxy.sh --strategy 135_dtmax270
#
#   # Dry-run preview:
#   bash run_phase4_dtxy.sh --all --dry-run
#
# OPTIONS
#   --strategy NAME     Run one strategy (90_ref | 120_dtmax240 |
#                       135_dtmax270 | 180_dtmax360)
#   --all               Run all strategies (default)
#   --tasks-per-node N  Tasks per node (default: 69 — best scaling point)
#   --cpus-per-task N   CPUs per task  (default: 2)
#   --source-exp ID     Source experiment for binary (default: p3_pgo_avx2_nd)
#   --dry-run           Print actions without executing
#   --poll-interval N   Seconds between Slurm polls (default: 120)
#   -h | --help         Show this help message
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"

DEPENDENCIES=(bash cp cat sed awk python3 sbatch squeue sacct)

# ---------------------------------------------------------------------------
# Colour output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

# =============================================================================
# PATHS
# =============================================================================

MODELS_ROOT="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models"
# Workspace root -- derived from this script location (benchmarking/ subdir)
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${BENCH_DIR}/scripts"
DATA_ROOT="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2"
GRID="CARRA2"

# Source config dir for other namelists (ww3_prnc.nml, ww3_shel.nml, etc.)
SOURCE_CONFIG_DIR="${BENCH_DIR}/configs/oneVar_noSaving"

# ww3_grid.nml lives in the grid constants directory, NOT in configs/.
# This file defines the spectral resolution, timesteps, and grid path.
# See: DATA_ROOT/const/grid/GRID/ww3_grid.nml
GRID_NML_DIR="${DATA_ROOT}/const/grid/${GRID}"

# Modified config dirs written by this script (cleaned up after use)
DTXY_CONFIGS_DIR="${BENCH_DIR}/configs/_dtxy_tmp"

# Default run layout — use 69 tasks/node (best scaling point from Phase 3)
RUN_NODES=16
RUN_TASKS_PER_NODE=69
RUN_CPUS_PER_TASK=2
BENCH_DURATION="10h"

POLL_INTERVAL=120

DEFAULT_SOURCE_EXP="p3_pgo_avx2_nd"

# =============================================================================
# Helpers
# =============================================================================
function print_header() { echo -e "\n${BLUE}══ $* ══${NC}"; }
function print_info()   { echo -e "  ${BLUE}[INFO]${NC} $*"; }
function print_success(){ echo -e "  ${GREEN}[OK]${NC} $*"; }
function print_warning(){ echo -e "  ${YELLOW}[WARN]${NC} $*" >&2; }
function print_error()  { echo -e "  ${RED}[ERR]${NC} $*" >&2; }

function check_dependencies() {
    local missing=()
    for cmd in "${DEPENDENCIES[@]}"; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

# =============================================================================
# usage
# =============================================================================
function usage() {
    cat << EOM

WW3 Phase 4 — DTXY propagation timestep sensitivity study.

usage: ${SCRIPT_NAME} [options]

options:
    --strategy NAME       Run one strategy: 90_ref | 120_dtmax240 |
                                            135_dtmax270 | 180_dtmax360
    --all                 Run all strategies sequentially
    --tasks-per-node N    Tasks per node (default: ${RUN_TASKS_PER_NODE})
    --cpus-per-task N     CPUs per task  (default: ${RUN_CPUS_PER_TASK})
    --source-exp ID       Binary source experiment (default: ${DEFAULT_SOURCE_EXP})
    --dry-run             Print actions without executing
    --poll-interval N     Seconds between Slurm polls (default: ${POLL_INTERVAL})
    -h | --help           Show this help message
    --version             Print version string

strategies and expected NTLOC gain:
    90_ref        DTXY=90  DTMAX=270 DTKTH=135  NTLOC=3  (reference, no gain)
    120_dtmax240  DTXY=120 DTMAX=240 DTKTH=120  NTLOC=2  (~33% fewer prop steps)
    135_dtmax270  DTXY=135 DTMAX=270 DTKTH=135  NTLOC=2  (~33% fewer prop steps)
    180_dtmax360  DTXY=180 DTMAX=360 DTKTH=180  NTLOC=2  (bolder; verify stability)

examples:
    ${SCRIPT_NAME} --all --dry-run
    ${SCRIPT_NAME} --strategy 135_dtmax270

results:
    column -t -s, ${BENCH_DIR}/benchmark_summary.csv

EOM
    exit 1
}

# =============================================================================
# wait_for_slurm_job
# =============================================================================
function wait_for_slurm_job() {
    local job_id="$1"
    local interval="${2:-${POLL_INTERVAL}}"

    echo -n "  Polling Slurm job ${job_id}"
    while true; do
        local state
        state=$(squeue -j "${job_id}" -h -o '%T' 2>/dev/null || true)
        if [[ -z "${state}" ]]; then
            state=$(sacct -j "${job_id}" --format=State --noheader -X 2>/dev/null \
                    | awk '{print $1}' | head -1 | xargs)
        fi

        case "${state}" in
            COMPLETED)
                echo ""; print_success "Job ${job_id} completed."; return 0 ;;
            FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL)
                echo ""; print_error "Job ${job_id} ended: ${state}"; return 1 ;;
            "")
                echo ""; print_warning "Cannot determine state — assuming completed."; return 0 ;;
            *)
                echo -n "."; sleep "${interval}" ;;
        esac
    done
}

# =============================================================================
# patch_ww3_grid_nml — write a modified ww3_grid.nml with new timestep values
#
# Uses Python (same pattern as existing cmake patcher) for reliable in-place
# editing of the namelist numeric fields.
#
# $1  source_nml   path to original ww3_grid.nml
# $2  output_nml   path to write the patched copy
# $3  dtxy         new DTXY  value
# $4  dtmax        new DTMAX value
# $5  dtkth        new DTKTH value
# =============================================================================
function patch_ww3_grid_nml() {
    local source_nml="$1"
    local output_nml="$2"
    local dtxy="$3"
    local dtmax="$4"
    local dtkth="$5"

    python3 - "${source_nml}" "${output_nml}" "${dtxy}" "${dtmax}" "${dtkth}" << 'PYEOF'
import sys, re

src, dst, dtxy, dtmax, dtkth = sys.argv[1:]

with open(src) as f:
    content = f.read()

def replace_param(txt, name, value):
    # Matches:  TIMESTEPS%<NAME>  <whitespace>=<whitespace>  <old_value>.
    pattern = r'(TIMESTEPS%' + re.escape(name) + r'\s*=\s*)[\d.]+'
    repl = r'\g<1>' + str(value) + '.'
    new_txt, n = re.subn(pattern, repl, txt)
    if n == 0:
        print(f"WARNING: could not find TIMESTEPS%{name} in {src}", file=sys.stderr)
    return new_txt

content = replace_param(content, 'DTXY',  dtxy)
content = replace_param(content, 'DTMAX', dtmax)
content = replace_param(content, 'DTKTH', dtkth)

with open(dst, 'w') as f:
    f.write(content)

print(f"  patched: {dst}  (DTXY={dtxy} DTMAX={dtmax} DTKTH={dtkth})")
PYEOF
}

# =============================================================================
# run_strategy — create config, setup experiment, submit benchmark
#
# $1  strategy_name  (e.g. "135_dtmax270")
# $2  dtxy           new DTXY value in seconds
# $3  dtmax          new DTMAX value in seconds
# $4  dtkth          new DTKTH value in seconds
# $5  source_exp
# $6  tasks_per_node
# $7  cpus_per_task
# =============================================================================
function run_strategy() {
    local strategy="$1"
    local dtxy="$2"
    local dtmax="$3"
    local dtkth="$4"
    local source_exp="$5"
    local tasks_per_node="$6"
    local cpus_per_task="$7"

    local exp_id="p4_dtxy_${strategy}_n${tasks_per_node}"
    local ww3_dir="${MODELS_ROOT}/${source_exp}/WW3"
    local tmp_config="${DTXY_CONFIGS_DIR}/${strategy}"
    # ww3_grid.nml comes from the grid constants dir, not the experiment config dir
    local src_nml="${GRID_NML_DIR}/ww3_grid.nml"
    local patched_nml="${tmp_config}/ww3_grid.nml"

    print_header "Strategy: ${strategy}  (DTXY=${dtxy} DTMAX=${dtmax} DTKTH=${dtkth}, n=${tasks_per_node})"
    echo "  exp_id     : ${exp_id}"
    echo "  source_exp : ${source_exp}"
    print_info "NTLOC = ceil(${dtmax}/${dtxy}) = $(python3 -c "import math; print(math.ceil(${dtmax}/${dtxy}))")"

    # Check binary exists
    local binary="${ww3_dir}/model/exe/ww3_shel"
    if [[ "${DRY_RUN}" == false && ! -f "${binary}" && ! -L "${binary}" ]]; then
        print_error "ww3_shel not found: ${binary}"
        return 1
    fi

    # Check source config exists
    if [[ "${DRY_RUN}" == false && ! -f "${src_nml}" ]]; then
        print_error "Source ww3_grid.nml not found: ${src_nml}"
        print_error "Expected at: ${GRID_NML_DIR}/ww3_grid.nml"
        print_error "(grid namelists live in DATA_ROOT/const/grid/GRID/, not in configs/)"
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 1: Create patched config directory
    # ------------------------------------------------------------------
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} mkdir -p ${tmp_config}"
        echo -e "  ${BLUE}[DRY]${NC} cp ${SOURCE_CONFIG_DIR}/* ${tmp_config}/"
        echo -e "  ${BLUE}[DRY]${NC} patch ww3_grid.nml: DTXY=${dtxy} DTMAX=${dtmax} DTKTH=${dtkth}"
    else
        mkdir -p "${tmp_config}"
        cp "${SOURCE_CONFIG_DIR}"/* "${tmp_config}/" 2>/dev/null || {
            # cp may fail if some source files are missing — that is OK
            # as long as ww3_grid.nml gets copied
            true
        }

        if [[ ! -f "${tmp_config}/ww3_grid.nml" ]]; then
            if [[ -f "${src_nml}" ]]; then
                cp "${src_nml}" "${tmp_config}/ww3_grid.nml"
            else
                print_error "ww3_grid.nml not found in source config: ${src_nml}"
                return 1
            fi
        fi

        if ! patch_ww3_grid_nml "${tmp_config}/ww3_grid.nml" "${patched_nml}" \
                                 "${dtxy}" "${dtmax}" "${dtkth}"; then
            print_error "patch_ww3_grid_nml failed for strategy ${strategy}"
            return 1
        fi
        print_info "Created patched config: ${tmp_config}"
    fi

    # ------------------------------------------------------------------
    # Step 2: Setup experiment with patched config
    # ------------------------------------------------------------------
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} setup.sh --force -e ${exp_id} -w ${ww3_dir} -c ${tmp_config} -t 'phase4;dtxy;${strategy}'"
    else
        cd "${BENCH_DIR}" || { print_error "Cannot cd to ${BENCH_DIR}"; return 1; }
        bash "${SCRIPT_DIR}/setup.sh" --force \
            -e "${exp_id}" \
            -w "${ww3_dir}" \
            -c "${tmp_config}" \
            -t "phase4;dtxy;${strategy}" || {
            print_error "setup.sh failed for ${exp_id}"
            return 1
        }
    fi

    # ------------------------------------------------------------------
    # Step 3: Submit benchmark
    # prep.job will re-run ww3_grid with the patched ww3_grid.nml,
    # regenerating mod_def.ww3 with the new DTXY baked in.
    # ------------------------------------------------------------------
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} run_exp.sh -e ${exp_id} -N ${RUN_NODES} -n ${tasks_per_node} --cpus-per-task ${cpus_per_task} -d ${BENCH_DURATION}"
        return 0
    fi

    local submit_output
    submit_output=$(bash "${SCRIPT_DIR}/run_exp.sh" \
        -e "${exp_id}" \
        -N "${RUN_NODES}" \
        -n "${tasks_per_node}" \
        --cpus-per-task "${cpus_per_task}" \
        -d "${BENCH_DURATION}" 2>&1)

    echo "${submit_output}"

    local job_id
    job_id=$(echo "${submit_output}" | grep -oP 'Shel job\s*:\s*\K[0-9]+' | tail -1)

    if [[ -n "${job_id}" ]]; then
        print_success "Benchmark submitted: job ${job_id}"
        echo "${job_id}"
    else
        print_warning "Could not extract job ID"
        echo ""
    fi
}

# =============================================================================
# strategy_params — echo "dtxy dtmax dtkth" for a named strategy
# =============================================================================
function strategy_params() {
    local strategy="$1"
    case "${strategy}" in
        90_ref)        echo "90  270 135" ;;
        120_dtmax240)  echo "120 240 120" ;;
        135_dtmax270)  echo "135 270 135" ;;
        180_dtmax360)  echo "180 360 180" ;;
        *)
            print_error "Unknown strategy: ${strategy}"
            print_error "Valid: 90_ref | 120_dtmax240 | 135_dtmax270 | 180_dtmax360"
            return 1
            ;;
    esac
}

# =============================================================================
# run_all
# =============================================================================
function run_all() {
    local source_exp="$1"
    local tasks_per_node="$2"
    local cpus_per_task="$3"

    print_header "Phase 4 DTXY — all strategies  (n=${tasks_per_node})"

    local strategies=("90_ref" "120_dtmax240" "135_dtmax270" "180_dtmax360")
    local failed=()

    for strategy in "${strategies[@]}"; do
        local params
        params=$(strategy_params "${strategy}") || { failed+=("${strategy}"); continue; }
        read -r dtxy dtmax dtkth <<< "${params}"

        local job_id
        job_id=$(run_strategy "${strategy}" "${dtxy}" "${dtmax}" "${dtkth}" \
                              "${source_exp}" "${tasks_per_node}" "${cpus_per_task}")
        local rc=$?

        if [[ ${rc} -ne 0 ]]; then
            failed+=("${strategy}")
            continue
        fi

        if [[ "${DRY_RUN}" == false && -n "${job_id}" ]]; then
            if ! wait_for_slurm_job "${job_id}" "${POLL_INTERVAL}"; then
                print_warning "Strategy '${strategy}' job ${job_id} did not complete."
                failed+=("${strategy}")
            fi
        fi
    done

    echo ""
    print_header "Phase 4 DTXY — summary"
    if [[ ${#failed[@]} -eq 0 ]]; then
        print_success "All strategies completed."
    else
        print_warning "Failed strategies: ${failed[*]}"
    fi
    print_info "Results: column -t -s, ${BENCH_DIR}/benchmark_summary.csv"
}

# =============================================================================
# main
# =============================================================================
function main() {
    local strategy=""
    local do_all=false
    local source_exp="${DEFAULT_SOURCE_EXP}"
    local tasks_per_node="${RUN_TASKS_PER_NODE}"
    local cpus_per_task="${RUN_CPUS_PER_TASK}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy)
                shift
                [[ -z "${1:-}" ]] && { print_error "--strategy requires a value"; usage; }
                strategy="$1"
                ;;
            --all)
                do_all=true
                ;;
            --source-exp)
                shift
                [[ -z "${1:-}" ]] && { print_error "--source-exp requires a value"; usage; }
                source_exp="$1"
                ;;
            --tasks-per-node)
                shift
                [[ -z "${1:-}" ]] && { print_error "--tasks-per-node requires a value"; usage; }
                tasks_per_node="$1"
                ;;
            --cpus-per-task)
                shift
                [[ -z "${1:-}" ]] && { print_error "--cpus-per-task requires a value"; usage; }
                cpus_per_task="$1"
                ;;
            --poll-interval)
                shift
                [[ -z "${1:-}" ]] && { print_error "--poll-interval requires a value"; usage; }
                POLL_INTERVAL="$1"
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --version)
                echo "${SCRIPT_NAME} version ${VERSION}"
                exit 0
                ;;
            -h | --help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done

    if [[ -z "${strategy}" && "${do_all}" == false ]]; then
        do_all=true
    fi

    DRY_RUN="${DRY_RUN:-false}"

    check_dependencies

    print_header "WW3 Phase 4 — DTXY Timestep Study  v${VERSION}"
    echo "  Source exp      : ${source_exp}"
    echo "  Tasks/node      : ${tasks_per_node}"
    echo "  CPUs/task       : ${cpus_per_task}"
    echo "  Bench duration  : ${BENCH_DURATION}"
    echo "  Config source   : ${SOURCE_CONFIG_DIR}"
    echo "  Grid nml dir    : ${GRID_NML_DIR}"
    echo "  Dry-run         : ${DRY_RUN}"

    if "${do_all}"; then
        run_all "${source_exp}" "${tasks_per_node}" "${cpus_per_task}"
    else
        local params
        params=$(strategy_params "${strategy}") || exit 1
        read -r dtxy dtmax dtkth <<< "${params}"
        run_strategy "${strategy}" "${dtxy}" "${dtmax}" "${dtkth}" \
                     "${source_exp}" "${tasks_per_node}" "${cpus_per_task}"
    fi
}

main "$@"
