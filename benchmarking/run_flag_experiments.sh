#!/usr/bin/env bash
# =============================================================================
# run_flag_experiments.sh — WW3 compiler flag ablation study (Phase 1)
# =============================================================================
# Version: 2.0
#
# WHAT IT DOES
# ------------
# For each experiment (one flag change from the reference):
#   1. Copies the reference model folder (test_Hamish) to a new directory
#   2. Patches WW3/model/src/CMakeLists.txt with the target compiler flags
#   3. Compiles WW3 from scratch using the patched flags
#   4. Sets up a benchmark experiment in the time_Benchmark framework
#   5. Submits a Slurm benchmark run
#
# REFERENCE FLAGS (from test_Hamish CMakeLists.txt, Intel Fortran block)
# -----------------------------------------------------------------------
# compile_flags (base — applied to ALL build types):
#   -no-fma -ip -g -traceback -i4 -real-size 32 -fp-model precise
#   -assume byterecl -fno-alias -fno-fnalias
#   ( -sox is appended by cmake automatically on Linux )
#
# compile_flags_release (added only for -DCMAKE_BUILD_TYPE=Release):
#   -O3
#
# PHASE 1 EXPERIMENTS (one flag changed at a time)
# -------------------------------------------------
# Release-flag changes:
#   comp_ref       reference (must reproduce ~107 sim_h/h)
#   comp_O2        release: -O2 (weaker; quantify cost of -O3)
#   comp_xHost     release: -O3 -xHost
#   comp_unroll    release: -O3 -unroll-aggressive
#   comp_align     release: -O3 -align array64byte
#
# Base-flag changes:
#   comp_fma       base: -fma  (was -no-fma)
#   comp_fp_fast1  base: -fp-model fast=1  (was precise)
#   comp_fp_fast2  base: -fp-model fast=2  (was precise)
#   comp_ipo       base: -ipo  (was -ip; stronger cross-file IPO)
#   comp_no_ip     base: remove -ip entirely
#
# USAGE
# -----
#   bash run_flag_experiments.sh [--dry-run] [--skip-compile] [--only EXP_ID]
#
# OPTIONS
#   --dry-run        Print all actions without executing anything
#   --skip-compile   Skip copy + compile; only setup and submit (binary must exist)
#   --only EXP_ID    Run a single experiment by ID (e.g. --only comp_O2)
#   -h | --help      Show this help message
#
# RESULTS
#   column -t -s, <BENCH_DIR>/benchmark_summary.csv
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="2.0"

# External tools this script depends on
DEPENDENCIES=(python3 bash cp rm find ls)

# ---------------------------------------------------------------------------
# Colour output (suppress with NO_COLOR=1 or when terminal is dumb)
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
# PATHS — edit if your HPC layout changes
# =============================================================================

MODELS_ROOT="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/compilation_Benchmark/models"
REFERENCE_MODEL="${MODELS_ROOT}/test_Hamish"

# Switch file taken from the reference model itself (defines physics switches)
SWITCH_FILE="${REFERENCE_MODEL}/WW3/model/bin/switch_dnora"

# Workspace root — derived from this script's location (benchmarking/ subdir)
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BENCH_DIR}/configs/oneVar_noSaving"

# Slurm layout — kept IDENTICAL across all experiments for a fair comparison
RUN_NODES=16
RUN_TASKS_PER_NODE=60
RUN_CPUS_PER_TASK=2
RUN_DURATION="10h"

# =============================================================================
# EXPERIMENTS
# =============================================================================
#
# Format: "EXP_ID|short description|base_flags|release_flags"
#
#   base_flags     replaces the set(compile_flags ...)    block in CMakeLists.txt
#   release_flags  replaces the set(compile_flags_release ...) block
#
# Flags are space-separated tokens. Multi-token flags like "-fp-model fast=1"
# are split by the space —  each token becomes its own CMake list element,
# which is standard cmake/ifort practice.
#
# NOTE: -sox is NOT listed here because cmake appends it automatically for
# Linux builds via an if(LINUX) block that we do not touch.
# =============================================================================

# Convenience variable: base flags that are the same across ALL experiments
_REF_BASE="-no-fma -ip -g -traceback -i4 -real-size 32 -fp-model precise -assume byterecl -fno-alias -fno-fnalias"

declare -a EXPERIMENTS=(

    # ------------------------------------------------------------------
    # comp_ref — exact reproduction of test_Hamish
    # This is the sanity check: must reproduce ~107 sim_h/h.
    # All other results are only meaningful relative to this.
    # ------------------------------------------------------------------
    "comp_ref|\
Reference: exact test_Hamish flags (-O3, no changes)|\
${_REF_BASE}|\
-O3"

    # ------------------------------------------------------------------
    # Release-flag changes  (compile_flags_release block)
    # These flags are ADDED on top of the base flags in Release builds.
    # ------------------------------------------------------------------

    # Weaken optimisation level to quantify the benefit of -O3
    "comp_O2|\
Release: -O2 instead of -O3 (cost of O3)|\
${_REF_BASE}|\
-O2"

    # Enable host-CPU-specific vectorisation (SIMD auto)
    "comp_xHost|\
Release: add -xHost (CPU-native vectorisation)|\
${_REF_BASE}|\
-O3 -xHost"

    # Force aggressive loop unrolling
    "comp_unroll|\
Release: add -unroll-aggressive|\
${_REF_BASE}|\
-O3 -unroll-aggressive"

    # Align Fortran arrays to 64-byte boundaries (cache-line aligned)
    "comp_align|\
Release: add -align array64byte|\
${_REF_BASE}|\
-O3 -align array64byte"

    # ------------------------------------------------------------------
    # Base-flag changes  (compile_flags block)
    # These flags apply to ALL build types (Debug and Release).
    # ------------------------------------------------------------------

    # Allow fused multiply-add (was explicitly disabled via -no-fma)
    "comp_fma|\
Base: -fma instead of -no-fma (allow FMA instructions)|\
-fma -ip -g -traceback -i4 -real-size 32 -fp-model precise -assume byterecl -fno-alias -fno-fnalias|\
-O3"

    # Relax floating-point model (level 1: fewer reassociations allowed)
    "comp_fp_fast1|\
Base: -fp-model fast=1 instead of precise|\
-no-fma -ip -g -traceback -i4 -real-size 32 -fp-model fast=1 -assume byterecl -fno-alias -fno-fnalias|\
-O3"

    # Relax floating-point model further (level 2: more aggressive)
    "comp_fp_fast2|\
Base: -fp-model fast=2 instead of precise|\
-no-fma -ip -g -traceback -i4 -real-size 32 -fp-model fast=2 -assume byterecl -fno-alias -fno-fnalias|\
-O3"

    # Upgrade -ip (single-file inlining) to -ipo (cross-file IPO)
    "comp_ipo|\
Base: -ipo instead of -ip (cross-file inter-procedural optimisation)|\
-no-fma -ipo -g -traceback -i4 -real-size 32 -fp-model precise -assume byterecl -fno-alias -fno-fnalias|\
-O3"

    # Remove -ip entirely to quantify its current contribution
    "comp_no_ip|\
Base: remove -ip (quantify current single-file inlining cost)|\
-no-fma -g -traceback -i4 -real-size 32 -fp-model precise -assume byterecl -fno-alias -fno-fnalias|\
-O3"
)

# =============================================================================
# usage
# =============================================================================
function usage() {
    cat << EOM

WW3 single-flag compiler ablation study — Phase 1 (one change at a time).

usage: ${SCRIPT_NAME} [options]

options:
    --dry-run           Print all actions without executing anything
    --skip-compile      Skip copy + compile (binary must already exist)
    --only EXP_ID       Run a single experiment by ID
    -h | --help         Show this help message
    --version           Print version string

available experiments:
$(for entry in "${EXPERIMENTS[@]}"; do
    IFS='|' read -r id desc _ _ <<< "${entry}"
    id=$(echo "${id}" | xargs)
    printf "    %-18s %s\n" "${id}" "${desc}"
done)

dependencies: ${DEPENDENCIES[*]}

examples:
    # Full ablation (all experiments, sequential compile + submit)
    ${SCRIPT_NAME}

    # Dry-run to review what would happen
    ${SCRIPT_NAME} --dry-run

    # Compile and submit a single experiment
    ${SCRIPT_NAME} --only comp_xHost

    # Re-submit without recompiling (binary already exists)
    ${SCRIPT_NAME} --only comp_xHost --skip-compile

results:
    column -t -s, ${BENCH_DIR}/benchmark_summary.csv

EOM
    exit 1
}

# =============================================================================
# main
# =============================================================================
function main() {
    local dry_run=false
    local skip_compile=false
    local only_exp=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                ;;
            --skip-compile)
                skip_compile=true
                ;;
            --only)
                shift
                if [[ -z "${1:-}" ]]; then
                    print_error "--only requires an experiment ID"
                    usage
                fi
                only_exp="$1"
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

    # Publish as globals so helper functions can read them
    DRY_RUN="${dry_run}"
    SKIP_COMPILE="${skip_compile}"
    ONLY_EXP="${only_exp}"

    check_dependencies

    # Validate --only argument up front if provided
    if [[ -n "${ONLY_EXP}" ]]; then
        local found=false
        for entry in "${EXPERIMENTS[@]}"; do
            IFS='|' read -r id _ _ _ <<< "${entry}"
            id=$(echo "${id}" | xargs)
            [[ "${id}" == "${ONLY_EXP}" ]] && found=true && break
        done
        if [[ "${found}" == false ]]; then
            print_error "Unknown experiment ID: '${ONLY_EXP}'"
            print_error "Run with --help to see available experiments"
            exit 1
        fi
    fi

    print_header "WW3 Compiler Flag Ablation Study  v${VERSION}"
    echo "  Reference model  : ${REFERENCE_MODEL}"
    echo "  Models root      : ${MODELS_ROOT}"
    echo "  Benchmark dir    : ${BENCH_DIR}"
    echo "  Config dir       : ${CONFIG_DIR}"
    echo "  Run layout       : ${RUN_NODES}N × ${RUN_TASKS_PER_NODE} tasks/node × ${RUN_CPUS_PER_TASK} CPUs/task"
    echo "  Sim duration     : ${RUN_DURATION}"
    echo "  Dry-run          : ${DRY_RUN}"
    echo "  Skip compile     : ${SKIP_COMPILE}"
    [[ -n "${ONLY_EXP}" ]] && echo "  Only experiment  : ${ONLY_EXP}"
    echo "  Total experiments: ${#EXPERIMENTS[@]}"

    local submitted=()
    local failed=()
    local skipped=()

    for entry in "${EXPERIMENTS[@]}"; do
        IFS='|' read -r exp_id description base_flags release_flags <<< "${entry}"
        exp_id=$(echo "${exp_id}" | xargs)   # strip leading/trailing whitespace

        if [[ -n "${ONLY_EXP}" && "${exp_id}" != "${ONLY_EXP}" ]]; then
            skipped+=("${exp_id}")
            continue
        fi

        if run_experiment "${exp_id}" "${description}" "${base_flags}" "${release_flags}"; then
            submitted+=("${exp_id}")
        else
            failed+=("${exp_id}")
            print_error "Experiment ${exp_id} failed — continuing with the next one"
        fi
    done

    echo ""
    print_header "Ablation Study Complete"
    [[ "${DRY_RUN}" == true ]] && echo -e "  ${YELLOW}*** DRY-RUN — nothing was executed ***${NC}"
    echo ""
    printf "  %-12s (%d): %s\n" "Submitted"  "${#submitted[@]}"  "${submitted[*]:-—}"
    [[ ${#failed[@]}  -gt 0 ]] && \
        printf "${RED}  %-12s (%d): %s${NC}\n" "Failed"  "${#failed[@]}"  "${failed[*]}"
    [[ ${#skipped[@]} -gt 0 ]] && \
        printf "  %-12s (%d): %s\n" "Skipped" "${#skipped[@]}" "${skipped[*]}"
    echo ""
    echo "  Monitor queue:"
    echo "    watch -n 30 'squeue -u \$(whoami)'"
    echo ""
    echo "  Watch results appear live:"
    echo "    watch -n 60 'column -t -s, ${BENCH_DIR}/benchmark_summary.csv'"
    echo ""
    echo "  Full results when done:"
    echo "    column -t -s, ${BENCH_DIR}/benchmark_summary.csv"

    [[ ${#failed[@]} -gt 0 ]] && exit 1
    exit 0
}

# =============================================================================
# run_experiment — orchestrates one full copy → patch → compile → setup → submit
# =============================================================================
function run_experiment() {
    local exp_id="$1"
    local description="$2"
    local base_flags="$3"
    local release_flags="$4"

    # All paths derived from the experiment ID
    local model_dir="${MODELS_ROOT}/${exp_id}"
    local ww3_dir="${model_dir}/WW3"
    local build_dir="${ww3_dir}/build"
    local cmake_file="${ww3_dir}/model/src/CMakeLists.txt"
    local binary="${build_dir}/install/bin/ww3_shel"

    echo ""
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE} Experiment  : ${exp_id}${NC}"
    echo    "  Description: ${description}"
    echo    "  Base flags : ${base_flags}"
    echo    "  Rel. flags : ${release_flags}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"

    # ------------------------------------------------------------------
    # Step 1 — Copy reference model folder
    # ------------------------------------------------------------------
    if [[ "${SKIP_COMPILE}" == false ]]; then

        print_step 1 5 "Copy reference model → ${model_dir}"

        if [[ -d "${model_dir}" ]]; then
            print_warning "Model dir already exists — removing it first"
            if ! run_or_dry rm -rf "${model_dir}"; then
                print_error "Failed to remove existing dir: ${model_dir}"
                return 1
            fi
        fi

        if ! run_or_dry cp -r "${REFERENCE_MODEL}" "${model_dir}"; then
            print_error "Failed to copy reference model to ${model_dir}"
            return 1
        fi

        # ------------------------------------------------------------------
        # Step 2 — Patch CMakeLists.txt with the experiment's flags
        # ------------------------------------------------------------------
        print_step 2 5 "Patch ${cmake_file}"

        if [[ "${DRY_RUN}" == true ]]; then
            echo -e "  ${BLUE}[DRY]${NC} Would patch: ${cmake_file}"
            echo    "         Base flags    : ${base_flags}"
            echo    "         Release flags : ${release_flags}"
        else
            if [[ ! -f "${cmake_file}" ]]; then
                print_error "CMakeLists.txt not found: ${cmake_file}"
                print_error "Expected path inside model copy: WW3/model/src/CMakeLists.txt"
                return 1
            fi
            # Keep the original as a backup for manual inspection
            if ! cp "${cmake_file}" "${cmake_file}.bak_ablation"; then
                print_error "Failed to backup CMakeLists.txt"
                return 1
            fi
            if ! patch_cmake "${cmake_file}" "${base_flags}" "${release_flags}"; then
                print_error "patch_cmake failed for ${exp_id}"
                return 1
            fi
        fi

        # ------------------------------------------------------------------
        # Step 3 — Compile WW3
        # The compile script is written to the model dir so it can be
        # inspected later or re-run manually if needed.
        # ------------------------------------------------------------------
        print_step 3 5 "Compile WW3 (make -j24)"

        local compile_script="${model_dir}/compile_${exp_id}.sh"

        if [[ "${DRY_RUN}" == false ]]; then

            # Write the self-contained compile script
            cat > "${compile_script}" << COMPEOF
#!/usr/bin/env bash
# Auto-generated by run_flag_experiments.sh for: ${exp_id}
# Do not edit — re-run the parent script to regenerate.

cd "${ww3_dir}"

# Remove any previous build so flags are applied cleanly
rm -rf build

# Load the Intel oneAPI MPI build environment
module purge
module load buildenv-intel/2023.1.0-hpc1
module load CMake/3.31.7-hpc1
module load netCDF-HDF5/4.9.2-1.12.2-hpc1

export CC=mpiicc
export FC=mpiifort
export NETCDF_ROOT=\${NETCDF_DIR}

mkdir build && cd build

cmake .. \\
    -DSWITCH="${SWITCH_FILE}" \\
    -DCMAKE_INSTALL_PREFIX=install \\
    -DCMAKE_BUILD_TYPE=Release

make -j 24
make install

echo "Build complete: ${exp_id}"
ls -lh "${binary}" 2>/dev/null || echo "WARNING: binary not found after install"
COMPEOF
            chmod +x "${compile_script}"

            echo "  Running compile script (this takes a few minutes)..."
            if ! bash "${compile_script}" 2>&1 | tee "${model_dir}/compile_${exp_id}.log"; then
                print_error "Compilation failed for ${exp_id}"
                print_error "See log: ${model_dir}/compile_${exp_id}.log"
                return 1
            fi

            if [[ ! -f "${binary}" ]]; then
                print_error "ww3_shel binary not found after compilation: ${binary}"
                return 1
            fi
            print_success "Binary OK: $(ls -lh "${binary}")"
            verify_flags "${build_dir}"

        else
            echo -e "  ${BLUE}[DRY]${NC} Would write and run: ${compile_script}"
        fi

    else
        # --skip-compile: skip copy and compile, assume binary already exists
        print_info "[SKIP-COMPILE] Assuming binary exists at ${binary}"
        if [[ "${DRY_RUN}" == false && ! -f "${binary}" ]]; then
            print_error "Binary not found (--skip-compile is set): ${binary}"
            return 1
        fi
    fi

    # ------------------------------------------------------------------
    # Step 3b — Populate model/exe/ with symlinks to cmake-installed bins
    # setup.sh resolves executables as ${ww3_dir}/model/exe/<name>, which
    # is the legacy w3_make layout.  cmake installs to build/install/bin/.
    # Creating symlinks bridges the two conventions without patching setup.sh.
    # Runs unconditionally (also with --skip-compile) since ln -sf is idempotent.
    # ------------------------------------------------------------------
    local install_bin="${build_dir}/install/bin"
    local model_exe="${ww3_dir}/model/exe"
    local ww3_exes=(ww3_grid ww3_bounc ww3_prnc ww3_shel ww3_multi ww3_ounf)

    print_step "3b" 5 "Symlink cmake binaries → ${model_exe}"

    if [[ "${DRY_RUN}" == false ]]; then
        mkdir -p "${model_exe}"
        for exe in "${ww3_exes[@]}"; do
            local src="${install_bin}/${exe}"
            if [[ -f "${src}" ]]; then
                ln -sf "${src}" "${model_exe}/${exe}"
                echo "    linked: ${exe}"
            else
                print_warning "${exe} not found in ${install_bin} — skipping symlink"
            fi
        done
    else
        echo -e "  ${BLUE}[DRY]${NC} Would create ${model_exe}/ and symlink binaries from ${install_bin}/"
    fi

    # ------------------------------------------------------------------
    # Step 4 — Initialise benchmark experiment
    # ------------------------------------------------------------------
    print_step 4 5 "Set up benchmark experiment: ${exp_id}"

    local tags="ablation,phase1,single_flag"

    if ! run_or_dry bash "${BENCH_DIR}/scripts/setup.sh" \
            -e "${exp_id}" \
            -w "${ww3_dir}" \
            -g CARRA2 \
            -s dnora \
            -c "${CONFIG_DIR}" \
            -t "${tags}" \
            --force
    then
        print_error "setup.sh failed for ${exp_id}"
        return 1
    fi

    # Copy patched CMakeLists.txt into experiment metadata for provenance
    local meta_dir="${BENCH_DIR}/experiments/${exp_id}/metadata"
    if [[ "${DRY_RUN}" == false ]]; then
        if [[ -f "${cmake_file}" ]]; then
            cp "${cmake_file}" "${meta_dir}/CMakeLists.txt"
            print_info "Saved CMakeLists.txt → ${meta_dir}/CMakeLists.txt"
        else
            print_warning "CMakeLists.txt not found at ${cmake_file} — skipping metadata copy"
        fi
    else
        echo -e "  ${BLUE}[DRY]${NC} Would copy ${cmake_file} → ${meta_dir}/CMakeLists.txt"
    fi

    # ------------------------------------------------------------------
    # Step 5 — Submit Slurm benchmark run
    # ------------------------------------------------------------------
    print_step 5 5 "Submit Slurm benchmark run"

    if ! run_or_dry bash "${BENCH_DIR}/scripts/run_exp.sh" \
            -e "${exp_id}" \
            -N "${RUN_NODES}" \
            -n "${RUN_TASKS_PER_NODE}" \
            --cpus-per-task "${RUN_CPUS_PER_TASK}" \
            -d "${RUN_DURATION}"
    then
        print_error "run_exp.sh failed for ${exp_id}"
        return 1
    fi

    print_success "Experiment submitted: ${exp_id}"
    return 0
}

# =============================================================================
# patch_cmake — rewrite the Intel Fortran flag blocks in CMakeLists.txt
#
# Arguments:
#   $1  absolute path to the CMakeLists.txt file
#   $2  space-separated base flag string  (replaces compile_flags block)
#   $3  space-separated release flag string (replaces compile_flags_release block)
#
# Strategy: Python handles multi-line regex replacement reliably.
# Each space-separated token is written as its own quoted CMake list element.
# Example: "-fp-model fast=1" → two elements: "-fp-model" and "fast=1"
# (cmake passes each list element as a separate argument to the compiler)
# =============================================================================
function patch_cmake() {
    local cmake_file="$1"
    local base_flags="$2"
    local release_flags="$3"

    # Format each space-separated token as its own indented cmake list line
    local cmake_base cmake_release
    cmake_base=$(echo "${base_flags}"    | tr ' ' '\n' | awk '{printf "    \"%s\"\n", $0}')
    cmake_release=$(echo "${release_flags}" | tr ' ' '\n' | awk '{printf "    \"%s\"\n", $0}')

    python3 - "${cmake_file}" "${cmake_base}" "${cmake_release}" << 'PYEOF'
import sys, re

cmake_file  = sys.argv[1]
base_fmt    = sys.argv[2]
rel_fmt     = sys.argv[3]

with open(cmake_file) as fh:
    content = fh.read()

# Replace compile_flags_release FIRST (longer name) to avoid the shorter
# compile_flags pattern accidentally matching inside the longer name.
new_release = f'set(compile_flags_release\n{rel_fmt}\n)'
content, n_rel = re.subn(
    r'set\(compile_flags_release[^)]*\)',
    new_release,
    content,
    flags=re.DOTALL
)
if n_rel == 0:
    print("WARNING: set(compile_flags_release ...) not found — check CMakeLists.txt", file=sys.stderr)

# Replace compile_flags base block (\b avoids re-matching compile_flags_release)
new_base = f'set(compile_flags\n{base_fmt}\n)'
content, n_base = re.subn(
    r'set\(compile_flags\b[^)]*\)',
    new_base,
    content,
    flags=re.DOTALL
)
if n_base == 0:
    print("WARNING: set(compile_flags ...) not found — check CMakeLists.txt", file=sys.stderr)

with open(cmake_file, 'w') as fh:
    fh.write(content)

print(f"  Patched {cmake_file}  (base: {n_base} match, release: {n_rel} match)")
PYEOF
}

# =============================================================================
# verify_flags — read flags.make after compilation to confirm compiler flags
#               were actually passed to mpiifort
# =============================================================================
function verify_flags() {
    local build_dir="$1"
    local flags_file
    flags_file=$(find "${build_dir}" -name "flags.make" -path "*/ww3_lib*" 2>/dev/null | head -1)
    if [[ -n "${flags_file}" ]]; then
        print_info "Compiler flags recorded in the build:"
        grep "^Fortran_FLAGS" "${flags_file}" | sed 's/Fortran_FLAGS = /    /'
    else
        print_warning "flags.make not found — cannot confirm flags were applied"
    fi
}

# =============================================================================
# Utility: output helpers
# =============================================================================
function print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

function print_step() {
    echo -e "${YELLOW}  [$1/$2] $3${NC}"
}

function print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

function print_error() {
    echo -e "${RED}  ✗ Error: $1${NC}" >&2
}

function print_warning() {
    echo -e "${YELLOW}  ⚠ Warning: $1${NC}"
}

function print_info() {
    echo "  $1"
}

# =============================================================================
# Utility: run command or print it in dry-run mode
# =============================================================================
function run_or_dry() {
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} $*"
    else
        "$@"
    fi
}

# =============================================================================
# Utility: check that all required external tools are available
# =============================================================================
function check_dependencies() {
    local missing=()
    for cmd in "${DEPENDENCIES[@]}"; do
        if ! command -v "${cmd}" &>/dev/null; then
            missing+=("${cmd}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

# =============================================================================
# Guard clause — only execute main when run directly (not sourced)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
