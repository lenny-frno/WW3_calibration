#!/usr/bin/env bash
# =============================================================================
# run_phase2_experiments.sh — WW3 compiler flag combination study (Phase 2)
# =============================================================================
# Version: 1.0
#
# WHAT IT DOES
# ------------
# Reads a user-defined experiment file and, for each experiment:
#   1. Validates that the specified extra flags don't duplicate or conflict
#      with the reference flags
#   2. Copies the reference model folder to a new directory
#   3. Patches WW3/model/src/CMakeLists.txt with the combined flags
#   4. Compiles WW3 from scratch
#   5. Creates model/exe/ symlinks (for setup.sh compatibility)
#   6. Sets up a benchmark experiment in the time_Benchmark framework
#   7. Saves the patched CMakeLists.txt to experiment metadata
#   8. Submits a Slurm benchmark run
#
# INPUT FILE FORMAT
# -----------------
# Two formats may be mixed in the same file.
# Lines starting with '#' are comments; blank lines are ignored.
#
# Format A — additive (extra flags appended to reference release block):
#
#   exp_name  FLAG [FLAG ...]
#
#   All listed flags are added to the reference release block.
#   Validation: each flag token must not already appear in the reference.
#   Semantic conflicts are also caught (e.g. -fma conflicts with -no-fma).
#   For experiments that need to REPLACE a base flag (e.g. -ipo for -ip,
#   -fma for -no-fma), use Format B instead.
#
# Format B — full specification (replaces reference flag blocks entirely):
#
#   exp_name | description | full_base_flags | full_release_flags
#
#   Same syntax as Phase 1. Use this when a base flag must be replaced.
#   The script verifies the flags differ from the reference.
#
# See phase2_experiments.txt for a ready-to-edit template.
#
# REFERENCE FLAGS (Intel Fortran, test_Hamish CMakeLists.txt)
# -----------------------------------------------------------
# compile_flags (base, ALL build types):
#   -no-fma -ip -g -traceback -i4 -real-size 32 -fp-model precise
#   -assume byterecl -fno-alias -fno-fnalias
#   ( -sox appended automatically by cmake on Linux )
#
# compile_flags_release (Release build only):
#   -O3
#
# USAGE
# -----
#   bash run_phase2_experiments.sh -i phase2_experiments.txt [options]
#
# OPTIONS
#   -i | --input FILE    Experiment definition file (required)
#   --dry-run            Print all actions without executing anything
#   --skip-compile       Skip copy + compile; only setup and submit
#   --only EXP_ID        Run a single experiment by ID
#   -h | --help          Show this help message
#
# RESULTS
#   column -t -s, <BENCH_DIR>/benchmark_summary.csv
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"

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
# REFERENCE FLAGS — must match test_Hamish CMakeLists.txt Intel block exactly.
# Used for duplicate-token and semantic-conflict validation.
# =============================================================================

REF_BASE="-no-fma -ip -g -traceback -i4 -real-size 32 -fp-model precise -assume byterecl -fno-alias -fno-fnalias"
REF_RELEASE="-O3"

# Token arrays for exact-duplicate detection
read -ra _REF_BASE_TOKENS    <<< "${REF_BASE}"
read -ra _REF_RELEASE_TOKENS <<< "${REF_RELEASE}"

# Semantic conflict map.
# If the user lists the KEY token, it semantically conflicts with the VALUE
# token already in the reference — ifort would receive both and behave
# unpredictably.  The script errors out and asks for Format B instead.
# Format: [user_token]="conflicting_reference_token"
declare -A SEMANTIC_CONFLICTS=(
    ["-fma"]="-no-fma"
    ["-ipo"]="-ip"
    ["fast=1"]="precise"
    ["fast=2"]="precise"
    ["-O0"]="-O3"
    ["-O1"]="-O3"
    ["-O2"]="-O3"
)

# =============================================================================
# usage
# =============================================================================
function usage() {
    cat << EOM

WW3 compiler flag combination study — Phase 2 (multiple flags per experiment).

usage: ${SCRIPT_NAME} -i <experiment_file> [options]

options:
    -i | --input FILE    Experiment definition file (required)
    --dry-run            Print all actions without executing
    --skip-compile       Skip copy + compile (binary must already exist)
    --only EXP_ID        Run a single experiment by ID
    -h | --help          Show this help message
    --version            Print version string

input file formats (may be mixed in the same file):

  Format A — additive: extra flags appended to reference release block
    exp_name  FLAG [FLAG ...]

  Format B — full specification: replaces reference flag blocks entirely
    exp_name | description | full_base_flags | full_release_flags

  Lines starting with '#' are comments; blank lines are ignored.
  See phase2_experiments.txt for a ready-to-edit template.

reference flags:
    base:    ${REF_BASE}
    release: ${REF_RELEASE}

dependencies: ${DEPENDENCIES[*]}

examples:
    # Preview all experiments without running anything
    ${SCRIPT_NAME} -i phase2_experiments.txt --dry-run

    # Run all experiments
    ${SCRIPT_NAME} -i phase2_experiments.txt

    # Run a single experiment
    ${SCRIPT_NAME} -i phase2_experiments.txt --only p2_unroll_xHost

    # Re-setup and re-submit without recompiling
    ${SCRIPT_NAME} -i phase2_experiments.txt --only p2_unroll_xHost --skip-compile

results:
    column -t -s, ${BENCH_DIR}/benchmark_summary.csv

EOM
    exit 1
}

# =============================================================================
# main
# =============================================================================
function main() {
    # Default to phase2_experiments.txt in the same directory as this script
    local input_file="$(dirname "${BASH_SOURCE[0]}")/phase2_experiments.txt"
    local dry_run=false
    local skip_compile=false
    local only_exp=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i | --input)
                shift
                if [[ -z "${1:-}" ]]; then
                    print_error "--input requires a file path"
                    usage
                fi
                input_file="$1"
                ;;
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

    if [[ -z "${input_file}" ]]; then
        print_error "Input file is required (-i / --input)"
        usage
    fi
    if [[ ! -f "${input_file}" ]]; then
        print_error "Input file not found: ${input_file}"
        exit 1
    fi

    # Publish as globals so helper functions can read them
    DRY_RUN="${dry_run}"
    SKIP_COMPILE="${skip_compile}"
    ONLY_EXP="${only_exp}"

    check_dependencies

    # Load and validate all experiment definitions up front
    print_header "Parsing experiment file: ${input_file}"
    declare -a EXPERIMENTS=()
    if ! parse_input_file "${input_file}" EXPERIMENTS; then
        exit 1
    fi

    if [[ ${#EXPERIMENTS[@]} -eq 0 ]]; then
        print_error "No valid experiments found in: ${input_file}"
        exit 1
    fi

    # Validate --only argument up front
    if [[ -n "${ONLY_EXP}" ]]; then
        local found=false
        for entry in "${EXPERIMENTS[@]}"; do
            IFS='|' read -r id _ _ _ <<< "${entry}"
            id=$(echo "${id}" | xargs)
            [[ "${id}" == "${ONLY_EXP}" ]] && found=true && break
        done
        if [[ "${found}" == false ]]; then
            print_error "Unknown experiment ID: '${ONLY_EXP}'"
            print_error "Available IDs in ${input_file}:"
            for entry in "${EXPERIMENTS[@]}"; do
                IFS='|' read -r id _ _ _ <<< "${entry}"
                id=$(echo "${id}" | xargs)
                echo "    ${id}"
            done
            exit 1
        fi
    fi

    print_header "WW3 Compiler Flag Combination Study  v${VERSION}"
    echo "  Input file       : ${input_file}"
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
        exp_id=$(echo "${exp_id}" | xargs)

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
    print_header "Phase 2 Study Complete"
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
    echo "  Full results when done:"
    echo "    column -t -s, ${BENCH_DIR}/benchmark_summary.csv"

    [[ ${#failed[@]} -gt 0 ]] && exit 1
    exit 0
}

# =============================================================================
# parse_input_file — read and validate experiments from the input file
#
# Arguments:
#   $1  path to the input file
#   $2  name of the output array variable (populated via nameref)
#
# Each output entry has the unified format:
#   "exp_id|description|base_flags|release_flags"
#
# Returns 0 on success, 1 if any validation error is found (no experiments
# are run when the input file contains errors).
# =============================================================================
function parse_input_file() {
    local input_file="$1"
    local -n _out="$2"

    local line_num=0
    local errors=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        (( line_num++ ))

        # Strip inline comments and trim whitespace
        line="${line%%#*}"
        line=$(echo "${line}" | xargs)
        [[ -z "${line}" ]] && continue

        if [[ "${line}" == *"|"* ]]; then
            # ------------------------------------------------------------------
            # Format B — full flag specification
            # exp_name | description | full_base_flags | full_release_flags
            # ------------------------------------------------------------------
            IFS='|' read -r exp_id description base_flags release_flags <<< "${line}"
            exp_id=$(echo "${exp_id}"           | xargs)
            description=$(echo "${description}" | xargs)
            base_flags=$(echo "${base_flags}"   | xargs)
            release_flags=$(echo "${release_flags}" | xargs)

            if [[ -z "${exp_id}" || -z "${base_flags}" || -z "${release_flags}" ]]; then
                print_error "Line ${line_num}: Format B requires exactly 4 '|'-separated fields:"
                print_error "  exp_id | description | full_base_flags | full_release_flags"
                (( errors++ ))
                continue
            fi

            # Catch accidental copy-paste of the reference unchanged
            if [[ "${base_flags}" == "${REF_BASE}" && "${release_flags}" == "${REF_RELEASE}" ]]; then
                print_warning "Line ${line_num}: '${exp_id}' flags are identical to the reference — skipping"
                continue
            fi

            _out+=("${exp_id}|${description}|${base_flags}|${release_flags}")
            echo -e "  ${GREEN}[B]${NC} ${exp_id}"
            echo    "      base:    ${base_flags}"
            echo    "      release: ${release_flags}"

        else
            # ------------------------------------------------------------------
            # Format A — additive: extra flags appended to reference release block
            # exp_name  FLAG [FLAG ...]
            # ------------------------------------------------------------------
            read -ra tokens <<< "${line}"
            local exp_id="${tokens[0]}"
            local extra=("${tokens[@]:1}")

            if [[ ${#extra[@]} -eq 0 ]]; then
                print_error "Line ${line_num}: '${exp_id}': Format A requires at least one flag after the experiment name"
                (( errors++ ))
                continue
            fi

            local valid=true

            for token in "${extra[@]}"; do
                # Exact-duplicate check: reference base tokens
                for ref_tok in "${_REF_BASE_TOKENS[@]}"; do
                    if [[ "${token}" == "${ref_tok}" ]]; then
                        print_error "Line ${line_num}: '${exp_id}': '${token}' is already in the reference base block."
                        print_error "  Adding it again would create a duplicate in CMakeLists.txt."
                        print_error "  Remove it from the experiment, or use Format B for a full flag override."
                        valid=false
                    fi
                done

                # Exact-duplicate check: reference release tokens
                for ref_tok in "${_REF_RELEASE_TOKENS[@]}"; do
                    if [[ "${token}" == "${ref_tok}" ]]; then
                        print_error "Line ${line_num}: '${exp_id}': '${token}' is already in the reference release block."
                        print_error "  Adding it again would create a duplicate in CMakeLists.txt."
                        print_error "  Remove it from the experiment, or use Format B for a full flag override."
                        valid=false
                    fi
                done

                # Semantic conflict check
                if [[ -n "${SEMANTIC_CONFLICTS["${token}"]+_}" ]]; then
                    local conflict_ref="${SEMANTIC_CONFLICTS["${token}"]}"
                    print_error "Line ${line_num}: '${exp_id}': '${token}' semantically conflicts with '${conflict_ref}' already in the reference."
                    print_error "  ifort cannot have both simultaneously. Use Format B to replace '${conflict_ref}' with '${token}'."
                    valid=false
                fi
            done

            if [[ "${valid}" == false ]]; then
                (( errors++ ))
                continue
            fi

            local extra_str="${extra[*]}"
            local final_base="${REF_BASE}"
            local final_release="${REF_RELEASE} ${extra_str}"
            local desc="Phase 2 combo: ref + ${extra_str}"

            _out+=("${exp_id}|${desc}|${final_base}|${final_release}")
            echo -e "  ${GREEN}[A]${NC} ${exp_id}"
            echo    "      extra release flags: ${extra_str}"
        fi

    done < "${input_file}"

    if [[ ${errors} -gt 0 ]]; then
        echo ""
        print_error "${errors} validation error(s) found in ${input_file} — fix them before running."
        return 1
    fi

    return 0
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
            if ! cp "${cmake_file}" "${cmake_file}.bak_phase2"; then
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
        # ------------------------------------------------------------------
        print_step 3 5 "Compile WW3 (make -j24)"

        local compile_script="${model_dir}/compile_${exp_id}.sh"

        if [[ "${DRY_RUN}" == false ]]; then

            cat > "${compile_script}" << COMPEOF
#!/usr/bin/env bash
# Auto-generated by run_phase2_experiments.sh for: ${exp_id}
# Do not edit — re-run the parent script to regenerate.

cd "${ww3_dir}"

rm -rf build

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
        print_info "[SKIP-COMPILE] Assuming binary exists at ${binary}"
        if [[ "${DRY_RUN}" == false && ! -f "${binary}" ]]; then
            print_error "Binary not found (--skip-compile is set): ${binary}"
            return 1
        fi
    fi

    # ------------------------------------------------------------------
    # Step 3b — Populate model/exe/ with symlinks to cmake-installed bins
    # setup.sh resolves executables as ${ww3_dir}/model/exe/<name> (legacy
    # w3_make layout). cmake installs to build/install/bin/. Symlinks bridge
    # both layouts. Runs unconditionally — ln -sf is idempotent.
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

    local tags="ablation,phase2,multi_flag"

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

    # Save the patched CMakeLists.txt to metadata for provenance
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
# (identical to Phase 1 version)
# =============================================================================
function patch_cmake() {
    local cmake_file="$1"
    local base_flags="$2"
    local release_flags="$3"

    local cmake_base cmake_release
    cmake_base=$(echo "${base_flags}"    | tr ' ' '\n' | awk '{printf "    \"%s\"\n", $0}')
    cmake_release=$(echo "${release_flags}" | tr ' ' '\n' | awk '{printf "    \"%s\"\n", $0}')

    python3 - "${cmake_file}" "${cmake_base}" "${cmake_release}" << 'PYEOF'
import sys, re

cmake_file = sys.argv[1]
base_fmt   = sys.argv[2]
rel_fmt    = sys.argv[3]

with open(cmake_file) as fh:
    content = fh.read()

# Replace compile_flags_release FIRST to avoid the shorter name matching inside it
new_release = f'set(compile_flags_release\n{rel_fmt}\n)'
content, n_rel = re.subn(
    r'set\(compile_flags_release[^)]*\)',
    new_release,
    content,
    flags=re.DOTALL
)
if n_rel == 0:
    print("WARNING: set(compile_flags_release ...) not found — check CMakeLists.txt", file=sys.stderr)

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
# verify_flags — confirm compiler flags from flags.make after compilation
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
