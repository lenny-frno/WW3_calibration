#!/usr/bin/env bash
# =============================================================================
# run_phase4_mpi_pinning.sh — MPI process-pinning & async-progress tuning
# =============================================================================
# Version: 1.0
#
# WHAT IT DOES
# ------------
# Benchmarks four Intel MPI tuning variants on top of the best compiled binary
# (p3_pgo_avx2_nd, 348 s @ 60 tasks/node / 324 s @ 69 tasks/node).
# No recompilation is needed — only environment variables in env.sh change.
#
# Variants tested
# ---------------
#   baseline    — current config (no explicit pinning)
#   compact     — I_MPI_PIN=1, I_MPI_PIN_DOMAIN=auto:compact
#                 Pack ranks into the fewest NUMA domains possible.
#                 Improves shared L3 locality for intra-node MPI (shm path).
#   scatter     — I_MPI_PIN=1, I_MPI_PIN_DOMAIN=auto:scatter
#                 Spread ranks evenly across all NUMA domains.
#                 Maximises total L3 capacity available across the node.
#   async_off   — I_MPI_ASYNC_PROGRESS=0
#                 Disables the async-progress thread that currently occupies
#                 the 2nd CPU slot.  Useful as a controlled test to measure
#                 the value of the overlap, and serves as the starting point
#                 for OMPH experiments where OMP_NUM_THREADS=2 replaces it.
#
# AMD EPYC 9005 (Turin-Zen 5) topology reminder
# -----------------------------------------------
#   144 cores / node.  Exact NUMA topology: run 'numactl --hardware' on a node.
#   60 tasks × 2 CPUs/task = 120 CPUs used (83.3% of node).
#   compact: ranks packed into fewest NUMA domains → maximises shared L3 per domain.
#   scatter: ranks spread evenly across all NUMA domains → maximises total L3.
#
# USAGE
# -----
#   # Run all four variants at 60 tasks/node (standard benchmark):
#   bash run_phase4_mpi_pinning.sh --all
#
#   # Run a single variant:
#   bash run_phase4_mpi_pinning.sh --variant compact
#
#   # Run at 69 tasks/node (best scaling point from Phase 3):
#   bash run_phase4_mpi_pinning.sh --all --tasks-per-node 69
#
#   # Dry-run preview:
#   bash run_phase4_mpi_pinning.sh --all --dry-run
#
# OPTIONS
#   --variant NAME        Run only one variant (baseline|compact|scatter|async_off)
#   --all                 Run all four variants (default if nothing else specified)
#   --tasks-per-node N    Tasks per node (default: 60)
#   --cpus-per-task N     CPUs per task (default: 2)
#   --dry-run             Print all actions without executing
#   --poll-interval N     Seconds between Slurm polls in --all mode (default: 120)
#   --source-exp ID       Source experiment ID containing compiled binary
#                         (default: p3_pgo_avx2_nd)
#   -h | --help           Show this message
#
# EXPECTED GAIN
# -------------
#   compact/scatter : 3–8 % runtime reduction (cache locality)
#   async_off       : gives a clear measurement of async-progress overhead;
#                     likely slower without it but required as OMPH baseline
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"

DEPENDENCIES=(bash cp cat chmod sed sbatch squeue sacct python3)

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
# PATHS — edit if HPC layout changes
# =============================================================================

MODELS_ROOT="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models"
BENCH_DIR="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/time_Benchmark"
SCRIPT_DIR="${BENCH_DIR}"
CONFIG_DIR="${BENCH_DIR}/configs/oneVar_noSaving"

# Default Slurm layout (match Phase 3 benchmark for fair comparison)
RUN_NODES=16
RUN_TASKS_PER_NODE=60
RUN_CPUS_PER_TASK=2
BENCH_DURATION="10h"

POLL_INTERVAL=120

# Source experiment — binary must already exist here
DEFAULT_SOURCE_EXP="p3_pgo_avx2_nd"

# =============================================================================
# Helpers
# =============================================================================
function print_header() { echo -e "\n${BLUE}══ $* ══${NC}"; }
function print_info()   { echo -e "  ${BLUE}[INFO]${NC} $*"; }
function print_success(){ echo -e "  ${GREEN}[OK]${NC} $*"; }
function print_warning(){ echo -e "  ${YELLOW}[WARN]${NC} $*" >&2; }
function print_error()  { echo -e "  ${RED}[ERR]${NC} $*" >&2; }

function run_or_dry() {
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} $*"
        return 0
    fi
    "$@"
}

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

WW3 Phase 4 — MPI process-pinning & async-progress tuning.

usage: ${SCRIPT_NAME} [options]

options:
    --variant NAME        Run one variant: baseline | compact | scatter | async_off
    --all                 Run all four variants sequentially
    --tasks-per-node N    Tasks per node (default: ${RUN_TASKS_PER_NODE})
    --cpus-per-task N     CPUs per task  (default: ${RUN_CPUS_PER_TASK})
    --source-exp ID       Compiled binary source experiment (default: ${DEFAULT_SOURCE_EXP})
    --dry-run             Print actions without executing
    --poll-interval N     Seconds between Slurm polls (default: ${POLL_INTERVAL})
    -h | --help           Show this help message
    --version             Print version string

variants:
    baseline   — repeat current reference; validates scoring reproducibility
    compact    — I_MPI_PIN=1 + I_MPI_PIN_DOMAIN=auto:compact
    scatter    — I_MPI_PIN=1 + I_MPI_PIN_DOMAIN=auto:scatter
    async_off  — I_MPI_ASYNC_PROGRESS=0 (disables async-progress thread)

examples:
    ${SCRIPT_NAME} --all --tasks-per-node 69 --dry-run
    ${SCRIPT_NAME} --variant compact --tasks-per-node 60
    ${SCRIPT_NAME} --all

results:
    column -t -s, ${BENCH_DIR}/benchmark_summary.csv

EOM
    exit 1
}

# =============================================================================
# wait_for_slurm_job
# Returns 0 if COMPLETED, 1 if FAILED/CANCELLED/TIMEOUT
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
                echo ""
                print_success "Job ${job_id} completed."
                return 0
                ;;
            FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL)
                echo ""
                print_error "Job ${job_id} finished with state: ${state}"
                return 1
                ;;
            "")
                echo ""
                print_warning "Cannot determine state of job ${job_id} — assuming completed."
                return 0
                ;;
            *)
                echo -n "."
                sleep "${interval}"
                ;;
        esac
    done
}

# =============================================================================
# run_variant — setup + patch env.sh + submit
#
# $1  variant_name   (baseline|compact|scatter|async_off)
# $2  source_exp     (model dir with compiled ww3_shel)
# $3  tasks_per_node
# $4  cpus_per_task
# =============================================================================
function run_variant() {
    local variant="$1"
    local source_exp="$2"
    local tasks_per_node="$3"
    local cpus_per_task="$4"

    local exp_id="p4_pin_${variant}_n${tasks_per_node}"
    local ww3_dir="${MODELS_ROOT}/${source_exp}/WW3"
    local env_file="${BENCH_DIR}/experiments/${exp_id}/metadata/setup/env.sh"

    print_header "Variant: ${variant}  (${tasks_per_node} tasks/node)"
    echo "  exp_id     : ${exp_id}"
    echo "  source_exp : ${source_exp}"
    echo "  ww3_dir    : ${ww3_dir}"

    # Verify binary exists
    local binary="${ww3_dir}/model/exe/ww3_shel"
    if [[ "${DRY_RUN}" == false ]]; then
        if [[ ! -f "${binary}" && ! -L "${binary}" ]]; then
            print_error "ww3_shel not found: ${binary}"
            print_error "Run Phase 3 PGO step 4 first, or set --source-exp correctly."
            return 1
        fi
    fi

    # ------------------------------------------------------------------
    # Step 1: Setup experiment
    # ------------------------------------------------------------------
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} setup.sh --force -e ${exp_id} -w ${ww3_dir} -c ${CONFIG_DIR} -t 'phase4;mpi_pinning;${variant}'"
    else
        cd "${BENCH_DIR}" || { print_error "Cannot cd to ${BENCH_DIR}"; return 1; }
        bash "${SCRIPT_DIR}/setup.sh" --force \
            -e "${exp_id}" \
            -w "${ww3_dir}" \
            -c "${CONFIG_DIR}" \
            -t "phase4;mpi_pinning;${variant}" || {
            print_error "setup.sh failed for ${exp_id}"
            return 1
        }
    fi

    # ------------------------------------------------------------------
    # Step 2: Patch env.sh with variant-specific MPI variables
    # ------------------------------------------------------------------
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} Patch env.sh with MPI settings for variant '${variant}'"
    else
        # Unlock the setup dir (it's written read-only by setup.sh)
        chmod u+w "$(dirname "${env_file}")" "${env_file}" 2>/dev/null || true

        # Append variant-specific vars
        case "${variant}" in
            baseline)
                # No extra pinning — keep current defaults
                {
                    echo "# Phase 4 MPI pinning — variant: baseline (no explicit pinning)"
                    echo "# I_MPI_ASYNC_PROGRESS defaults to 1 (enabled) with I_MPI_FABRICS=shm:ofi"
                } >> "${env_file}"
                ;;
            compact)
                # Pack ranks into fewest NUMA domains to maximise shared L3 cache reuse
                # I_MPI_PIN_DOMAIN=auto:compact fills NUMA domains sequentially.
                {
                    echo "# Phase 4 MPI pinning — variant: compact"
                    echo "export I_MPI_PIN=1"
                    echo "export I_MPI_PIN_DOMAIN=auto:compact"
                } >> "${env_file}"
                ;;
            scatter)
                # Spread ranks evenly across all NUMA domains for maximum aggregate L3
                {
                    echo "# Phase 4 MPI pinning — variant: scatter"
                    echo "export I_MPI_PIN=1"
                    echo "export I_MPI_PIN_DOMAIN=auto:scatter"
                } >> "${env_file}"
                ;;
            async_off)
                # Disable async-progress thread so the 2nd CPU slot is idle.
                # This measures async-progress value and serves as the baseline
                # for OMPH experiments (which replace the 2nd CPU with OMP work).
                {
                    echo "# Phase 4 MPI pinning — variant: async_off"
                    echo "export I_MPI_ASYNC_PROGRESS=0"
                } >> "${env_file}"
                ;;
            *)
                print_error "Unknown variant: ${variant}"
                return 1
                ;;
        esac

        # Re-lock the setup dir
        chmod a-w "${env_file}" 2>/dev/null || true
        print_info "env.sh patched for variant '${variant}'"
    fi

    # ------------------------------------------------------------------
    # Step 3: Submit benchmark
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
        print_info "Monitor: squeue -j ${job_id}"
        echo "${job_id}"       # caller can capture this
    else
        print_warning "Could not extract job ID — check the submit output above"
        echo ""
    fi
}

# =============================================================================
# run_all — run all variants sequentially, polling between each
# =============================================================================
function run_all() {
    local source_exp="$1"
    local tasks_per_node="$2"
    local cpus_per_task="$3"

    print_header "Phase 4 MPI Pinning — all variants  (n=${tasks_per_node}, cpus=${cpus_per_task})"

    local variants=("baseline" "compact" "scatter" "async_off")
    local failed=()

    for variant in "${variants[@]}"; do
        local job_id
        job_id=$(run_variant "${variant}" "${source_exp}" "${tasks_per_node}" "${cpus_per_task}")
        local rc=$?

        if [[ ${rc} -ne 0 ]]; then
            print_error "Variant '${variant}' setup/submit failed — skipping poll."
            failed+=("${variant}")
            continue
        fi

        if [[ "${DRY_RUN}" == false && -n "${job_id}" ]]; then
            if ! wait_for_slurm_job "${job_id}" "${POLL_INTERVAL}"; then
                print_warning "Variant '${variant}' job ${job_id} did not complete successfully."
                failed+=("${variant}")
            fi
        fi
    done

    echo ""
    print_header "Phase 4 MPI Pinning — summary"
    if [[ ${#failed[@]} -eq 0 ]]; then
        print_success "All variants completed."
    else
        print_warning "Failed variants: ${failed[*]}"
    fi
    print_info "Results: column -t -s, ${BENCH_DIR}/benchmark_summary.csv"
}

# =============================================================================
# main
# =============================================================================
function main() {
    local variant=""
    local do_all=false
    local source_exp="${DEFAULT_SOURCE_EXP}"
    local tasks_per_node="${RUN_TASKS_PER_NODE}"
    local cpus_per_task="${RUN_CPUS_PER_TASK}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --variant)
                shift
                [[ -z "${1:-}" ]] && { print_error "--variant requires a value"; usage; }
                variant="$1"
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

    # Default: run all if nothing specified
    if [[ -z "${variant}" && "${do_all}" == false ]]; then
        do_all=true
    fi

    # Export DRY_RUN as global so helper functions see it
    DRY_RUN="${DRY_RUN:-false}"

    check_dependencies

    print_header "WW3 Phase 4 — MPI Pinning  v${VERSION}"
    echo "  Source exp      : ${source_exp}"
    echo "  Tasks/node      : ${tasks_per_node}"
    echo "  CPUs/task       : ${cpus_per_task}"
    echo "  Bench duration  : ${BENCH_DURATION}"
    echo "  Dry-run         : ${DRY_RUN}"

    if "${do_all}"; then
        run_all "${source_exp}" "${tasks_per_node}" "${cpus_per_task}"
    else
        run_variant "${variant}" "${source_exp}" "${tasks_per_node}" "${cpus_per_task}"
    fi
}

main "$@"
