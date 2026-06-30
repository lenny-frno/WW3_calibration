#!/usr/bin/env bash
#
# debug_PR2_UNO.sh — Build WW3 with PR2+UNO switches and debug flags
#
# This script compiles WW3 using CMake in Debug mode to enable:
#   - Full runtime array bounds checking (-check all)
#   - Stack traceback on crash (-traceback)
#   - Floating-point exception trapping (-fpe0)
#   - Debug symbols for line-level diagnostics (-g)
#
# Two builds are created:
#   1. Sequential (SHRD) — for single-process debugging
#   2. Parallel (DIST MPI) — for comparing behavior with MPI
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

Build WW3 with PR2+UNO switches in debug mode for crash diagnosis.

usage: ${SCRIPT_NAME} [options]

options:
    -w|--ww3-dir      <path>    WW3 source directory (default: \$WW3_DIR or ../WW3_ref/WW3)
    -b|--build-dir    <path>    Build output directory (default: <ww3>/build_debug_pr2uno)
    -s|--sequential             Build only sequential version (SHRD, no MPI)
    -p|--parallel               Build only parallel version (DIST MPI)
    -j|--jobs         <n>       Parallel make jobs (default: 16)
    --clean                     Remove existing build directories first
    -v|--verbose                Verbose CMake output
    -h|--help                   Show this help message
    --version                   Show version

By default, both sequential and parallel debug builds are created.

examples:
    ${SCRIPT_NAME}                              # Build both versions
    ${SCRIPT_NAME} -s                           # Sequential only
    ${SCRIPT_NAME} -w /path/to/WW3 --clean      # Clean build

EOM
    exit 1
}

function log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
function log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
function log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
function log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

function check_dependencies() {
    local missing=()
    for cmd in cmake make; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        return 1
    fi
    return 0
}

function build_ww3_debug() {
    local ww3_dir="$1"
    local build_name="$2"
    local switch_file="$3"
    local jobs="$4"
    local verbose="$5"
    local clean="$6"

    local build_dir="${ww3_dir}/${build_name}"

    log_info "Building ${build_name} with switch: ${switch_file}"

    # Clean if requested
    if [[ "$clean" == "true" ]] && [[ -d "$build_dir" ]]; then
        log_info "Removing existing build directory: ${build_dir}"
        rm -rf "$build_dir"
    fi

    # Create build directory
    if ! mkdir -p "$build_dir"; then
        log_error "Failed to create build directory: ${build_dir}"
        return 1
    fi

    # CMake configure
    log_info "Configuring CMake (Debug mode)..."
    local cmake_args=(
        -DSWITCH="${switch_file}"
        -DCMAKE_BUILD_TYPE=Debug
        -DCMAKE_INSTALL_PREFIX="${ww3_dir}/install_debug"
    )
    if [[ "$verbose" == "true" ]]; then
        cmake_args+=(-DCMAKE_VERBOSE_MAKEFILE=ON)
    fi

    if ! (cd "$build_dir" && cmake "${cmake_args[@]}" ..); then
        log_error "CMake configure failed for ${build_name}"
        return 1
    fi

    # Build
    log_info "Building with ${jobs} parallel jobs..."
    if ! (cd "$build_dir" && make -j"${jobs}"); then
        log_error "Build failed for ${build_name}"
        return 1
    fi

    # Install executables
    log_info "Installing executables..."
    if ! (cd "$build_dir" && make install); then
        log_error "Install failed for ${build_name}"
        return 1
    fi

    log_ok "Build complete: ${build_dir}"
    log_info "Executables in: ${ww3_dir}/install_debug/bin/"
    return 0
}

function main() {
    local ww3_dir="${WW3_DIR:-}"
    local build_dir=""
    local build_seq=true
    local build_par=true
    local jobs=16
    local verbose=false
    local clean=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -w|--ww3-dir)
            shift
            ww3_dir="$1"
            ;;
        -b|--build-dir)
            shift
            build_dir="$1"
            ;;
        -s|--sequential)
            build_seq=true
            build_par=false
            ;;
        -p|--parallel)
            build_seq=false
            build_par=true
            ;;
        -j|--jobs)
            shift
            jobs="$1"
            ;;
        --clean)
            clean=true
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

    # Determine WW3 directory
    if [[ -z "$ww3_dir" ]]; then
        # Try relative path from script location
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        ww3_dir="${script_dir}/../WW3_ref/WW3"
    fi

    # Validate WW3 directory
    if [[ ! -d "$ww3_dir" ]]; then
        log_error "WW3 directory not found: ${ww3_dir}"
        log_error "Set WW3_DIR environment variable or use -w option"
        exit 1
    fi

    ww3_dir="$(cd "$ww3_dir" && pwd)"  # Resolve to absolute path
    log_info "WW3 source directory: ${ww3_dir}"

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Verify switch files exist
    local switch_seq="${ww3_dir}/model/bin/switch_PR2_UNO_seq"
    local switch_par="${ww3_dir}/model/bin/switch_PR2_UNO"

    if [[ "$build_seq" == "true" ]] && [[ ! -f "$switch_seq" ]]; then
        log_error "Sequential switch file not found: ${switch_seq}"
        log_error "Create it with: NOGRB SHRD PR2 UNO FLX0 LN1 ST4 STAB0 NL1 BT4 DB1 MLIM TR0 BS0 IC0 IS0 REF0 WNT1 WNX0 CRT0 CRX0 O0 O1 O2 O2a O2c O4 O5"
        exit 1
    fi

    if [[ "$build_par" == "true" ]] && [[ ! -f "$switch_par" ]]; then
        log_error "Parallel switch file not found: ${switch_par}"
        exit 1
    fi

    # Build sequential version
    if [[ "$build_seq" == "true" ]]; then
        log_info "=== Building SEQUENTIAL debug version ==="
        if ! build_ww3_debug "$ww3_dir" "build_debug_pr2uno_seq" "PR2_UNO_seq" "$jobs" "$verbose" "$clean"; then
            log_error "Sequential build failed"
            exit 1
        fi
        # Copy executables with suffix
        log_info "Copying executables with _seq suffix..."
        for exe in ww3_grid ww3_prnc ww3_shel ww3_ounf ww3_bounc; do
            if [[ -f "${ww3_dir}/install_debug/bin/${exe}" ]]; then
                cp "${ww3_dir}/install_debug/bin/${exe}" "${ww3_dir}/install_debug/bin/${exe}_seq_debug"
                log_ok "Created ${exe}_seq_debug"
            fi
        done
    fi

    # Build parallel version
    if [[ "$build_par" == "true" ]]; then
        log_info "=== Building PARALLEL debug version ==="
        if ! build_ww3_debug "$ww3_dir" "build_debug_pr2uno_mpi" "PR2_UNO" "$jobs" "$verbose" "$clean"; then
            log_error "Parallel build failed"
            exit 1
        fi
        # Copy executables with suffix
        log_info "Copying executables with _mpi_debug suffix..."
        for exe in ww3_grid ww3_prnc ww3_shel ww3_ounf ww3_bounc; do
            if [[ -f "${ww3_dir}/install_debug/bin/${exe}" ]]; then
                cp "${ww3_dir}/install_debug/bin/${exe}" "${ww3_dir}/install_debug/bin/${exe}_mpi_debug"
                log_ok "Created ${exe}_mpi_debug"
            fi
        done
    fi

    echo ""
    log_ok "All builds complete!"
    echo ""
    log_info "Next steps:"
    echo "  1. Copy executables to HPC experiment directory"
    echo "  2. Run: ./run_debug_test.sh -e <experiment_dir>"
    echo "  3. Check traceback output for crash location"
    echo ""
}

# Guard clause — only run main if script is executed, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
