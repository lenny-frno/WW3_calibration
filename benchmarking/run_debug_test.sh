#!/usr/bin/env bash
#
# run_debug_test.sh — Run WW3 debug binary and capture crash traceback
#
# This script runs a WW3 experiment with debug executables to capture
# detailed crash information including file:line tracebacks.
#
# Designed for diagnosing PR2+UNO segmentation faults.
#

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

function usage() {
    cat <<EOM

Run WW3 debug binary and capture crash traceback for diagnosis.

usage: ${SCRIPT_NAME} [options]

options:
    -e|--exp-dir      <path>    Experiment work directory (required)
    -b|--binary       <path>    Path to ww3_shel binary (default: auto-detect)
    -m|--mode         <mode>    Run mode: seq|mpi|both (default: seq)
    -n|--np           <n>       MPI ranks for parallel mode (default: 1)
    -t|--threads      <n>       OMP threads (default: 1)
    -o|--output       <file>    Output log file (default: debug_traceback.log)
    --timesteps       <n>       Limit simulation to N timesteps (modifies ww3_shel.nml)
    --no-modify                 Don't modify namelists, run as-is
    -v|--verbose                Verbose output
    -h|--help                   Show this help message
    --version                   Show version

modes:
    seq   — Run sequential binary (ww3_shel_seq_debug) without MPI
    mpi   — Run MPI binary (ww3_shel_mpi_debug) with mpirun
    both  — Run both modes for comparison

examples:
    ${SCRIPT_NAME} -e /path/to/experiment/work -m seq
    ${SCRIPT_NAME} -e ./work -m mpi -n 4 -t 1
    ${SCRIPT_NAME} -e ./work --timesteps 3

EOM
    exit 1
}

function log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
function log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
function log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
function log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

function limit_timesteps() {
    local nml_file="$1"
    local max_steps="$2"

    if [[ ! -f "$nml_file" ]]; then
        log_error "ww3_shel.nml not found: ${nml_file}"
        return 1
    fi

    log_info "Backing up ${nml_file} to ${nml_file}.bak"
    cp "$nml_file" "${nml_file}.bak"

    # WW3 doesn't have a direct "max timesteps" option, but we can
    # reduce END_DATE to be very close to START_DATE
    # For now, just log a warning
    log_warn "Timestep limiting not implemented - run with existing namelist"
    log_warn "Consider manually editing ww3_shel.nml to reduce simulation period"
    return 0
}

function run_sequential() {
    local work_dir="$1"
    local binary="$2"
    local output_log="$3"
    local threads="$4"

    log_info "=== Running SEQUENTIAL debug test ==="
    log_info "Binary: ${binary}"
    log_info "Work dir: ${work_dir}"
    log_info "OMP_NUM_THREADS: ${threads}"

    # Set environment for Intel runtime checks
    export OMP_NUM_THREADS="${threads}"
    export OMP_STACKSIZE=64M
    export KMP_STACKSIZE=64M
    export FOR_DUMP_CORE_FILE=TRUE

    # Run and capture output
    log_info "Starting ww3_shel (sequential)..."
    echo "======================================" >> "$output_log"
    echo "SEQUENTIAL RUN - $(date)" >> "$output_log"
    echo "Binary: ${binary}" >> "$output_log"
    echo "OMP_NUM_THREADS: ${threads}" >> "$output_log"
    echo "======================================" >> "$output_log"

    (
        cd "$work_dir" || exit 1
        "${binary}" 2>&1 | tee -a "$output_log"
    )
    local exit_code=$?

    echo "" >> "$output_log"
    echo "EXIT CODE: ${exit_code}" >> "$output_log"
    echo "======================================" >> "$output_log"

    if [[ $exit_code -eq 0 ]]; then
        log_ok "Sequential run completed successfully"
    else
        log_error "Sequential run failed with exit code: ${exit_code}"
        log_info "Check traceback in: ${output_log}"
    fi

    return $exit_code
}

function run_mpi() {
    local work_dir="$1"
    local binary="$2"
    local output_log="$3"
    local np="$4"
    local threads="$5"

    log_info "=== Running MPI debug test ==="
    log_info "Binary: ${binary}"
    log_info "Work dir: ${work_dir}"
    log_info "MPI ranks: ${np}"
    log_info "OMP_NUM_THREADS: ${threads}"

    # Set environment
    export OMP_NUM_THREADS="${threads}"
    export OMP_STACKSIZE=64M
    export KMP_STACKSIZE=64M
    export FOR_DUMP_CORE_FILE=TRUE
    export I_MPI_DEBUG=5  # Intel MPI debug info

    # Determine mpirun command
    local mpi_cmd="mpirun"
    if command -v mpprun &>/dev/null; then
        mpi_cmd="mpprun"
    elif command -v srun &>/dev/null; then
        mpi_cmd="srun"
    fi

    log_info "Using MPI launcher: ${mpi_cmd}"

    # Run and capture output
    log_info "Starting ww3_shel (MPI, np=${np})..."
    echo "======================================" >> "$output_log"
    echo "MPI RUN - $(date)" >> "$output_log"
    echo "Binary: ${binary}" >> "$output_log"
    echo "MPI ranks: ${np}" >> "$output_log"
    echo "OMP_NUM_THREADS: ${threads}" >> "$output_log"
    echo "MPI launcher: ${mpi_cmd}" >> "$output_log"
    echo "======================================" >> "$output_log"

    local exit_code
    (
        cd "$work_dir" || exit 1
        case "$mpi_cmd" in
            mpprun)
                mpprun -np "$np" "${binary}" 2>&1 | tee -a "$output_log"
                ;;
            srun)
                srun -n "$np" --cpus-per-task="$threads" "${binary}" 2>&1 | tee -a "$output_log"
                ;;
            *)
                mpirun -np "$np" "${binary}" 2>&1 | tee -a "$output_log"
                ;;
        esac
    )
    exit_code=$?

    echo "" >> "$output_log"
    echo "EXIT CODE: ${exit_code}" >> "$output_log"
    echo "======================================" >> "$output_log"

    if [[ $exit_code -eq 0 ]]; then
        log_ok "MPI run completed successfully"
    else
        log_error "MPI run failed with exit code: ${exit_code}"
        log_info "Check traceback in: ${output_log}"
    fi

    return $exit_code
}

function main() {
    local exp_dir=""
    local binary=""
    local mode="seq"
    local np=1
    local threads=1
    local output_log="debug_traceback.log"
    local timesteps=""
    local no_modify=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -e|--exp-dir)
            shift
            exp_dir="$1"
            ;;
        -b|--binary)
            shift
            binary="$1"
            ;;
        -m|--mode)
            shift
            mode="$1"
            ;;
        -n|--np)
            shift
            np="$1"
            ;;
        -t|--threads)
            shift
            threads="$1"
            ;;
        -o|--output)
            shift
            output_log="$1"
            ;;
        --timesteps)
            shift
            timesteps="$1"
            ;;
        --no-modify)
            no_modify=true
            ;;
        -v|--verbose)
            verbose=true
            ;;
        --version)
            echo "${SCRIPT_NAME} version ${VERSION}"
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
        esac
        shift
    done

    # Validate required arguments
    if [[ -z "$exp_dir" ]]; then
        log_error "Experiment directory is required (-e)"
        usage
    fi

    if [[ ! -d "$exp_dir" ]]; then
        log_error "Experiment directory not found: ${exp_dir}"
        exit 1
    fi

    exp_dir="$(cd "$exp_dir" && pwd)"  # Absolute path
    output_log="${exp_dir}/${output_log}"

    log_info "Experiment directory: ${exp_dir}"
    log_info "Output log: ${output_log}"

    # Validate mode
    case "$mode" in
        seq|mpi|both) ;;
        *)
            log_error "Invalid mode: ${mode}. Use: seq, mpi, or both"
            exit 1
            ;;
    esac

    # Find binaries
    local binary_seq="${exp_dir}/ww3_shel_seq_debug"
    local binary_mpi="${exp_dir}/ww3_shel_mpi_debug"

    # Also check in model/exe if not in work dir
    if [[ ! -f "$binary_seq" ]]; then
        # Try to find in common locations
        for candidate in \
            "${exp_dir}/../../../WW3_ref/WW3/model/exe/ww3_shel_seq_debug" \
            "${exp_dir}/ww3_shel"; do
            if [[ -f "$candidate" ]]; then
                binary_seq="$candidate"
                break
            fi
        done
    fi

    if [[ ! -f "$binary_mpi" ]]; then
        for candidate in \
            "${exp_dir}/../../../WW3_ref/WW3/model/exe/ww3_shel_mpi_debug" \
            "${exp_dir}/ww3_shel"; do
            if [[ -f "$candidate" ]]; then
                binary_mpi="$candidate"
                break
            fi
        done
    fi

    # Limit timesteps if requested
    if [[ -n "$timesteps" ]] && [[ "$no_modify" == "false" ]]; then
        limit_timesteps "${exp_dir}/ww3_shel.nml" "$timesteps"
    fi

    # Initialize log
    echo "WW3 PR2+UNO Debug Test" > "$output_log"
    echo "Started: $(date)" >> "$output_log"
    echo "Experiment: ${exp_dir}" >> "$output_log"
    echo "" >> "$output_log"

    local overall_exit=0

    # Run sequential
    if [[ "$mode" == "seq" ]] || [[ "$mode" == "both" ]]; then
        if [[ ! -f "$binary_seq" ]]; then
            log_warn "Sequential binary not found: ${binary_seq}"
            log_warn "Trying default ww3_shel..."
            binary_seq="${exp_dir}/ww3_shel"
        fi

        if [[ -f "$binary_seq" ]]; then
            if ! run_sequential "$exp_dir" "$binary_seq" "$output_log" "$threads"; then
                overall_exit=1
            fi
        else
            log_error "No sequential binary found"
            overall_exit=1
        fi
    fi

    # Run MPI
    if [[ "$mode" == "mpi" ]] || [[ "$mode" == "both" ]]; then
        if [[ ! -f "$binary_mpi" ]]; then
            log_warn "MPI binary not found: ${binary_mpi}"
            log_warn "Trying default ww3_shel..."
            binary_mpi="${exp_dir}/ww3_shel"
        fi

        if [[ -f "$binary_mpi" ]]; then
            if ! run_mpi "$exp_dir" "$binary_mpi" "$output_log" "$np" "$threads"; then
                overall_exit=1
            fi
        else
            log_error "No MPI binary found"
            overall_exit=1
        fi
    fi

    echo ""
    log_info "Debug test complete"
    log_info "Full output: ${output_log}"

    # Check for traceback patterns
    if grep -q "forrtl:" "$output_log" 2>/dev/null; then
        log_warn "Fortran runtime error detected!"
        echo ""
        log_info "=== TRACEBACK SUMMARY ==="
        grep -A 20 "forrtl:" "$output_log" | head -30
    fi

    if grep -qE "Line\s+[0-9]+" "$output_log" 2>/dev/null; then
        log_ok "Line numbers found in traceback - debug symbols working"
    elif grep -q "Unknown" "$output_log" 2>/dev/null; then
        log_warn "No line numbers in traceback - verify debug build"
    fi

    return $overall_exit
}

# Guard clause
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
