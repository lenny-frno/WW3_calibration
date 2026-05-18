#!/usr/bin/env bash
# =============================================================================
# run_phase3_pgo.sh — WW3 Profile-Guided Optimisation (PGO) workflow
# =============================================================================
# Version: 1.0
#
# WHAT IT DOES
# ------------
# Runs a two-compile PGO cycle on top of the best Phase 3 flag set:
#
#   Step 1 — compile-gen  : Compile WW3 with Intel ifort -prof-gen
#                           (produces profiling-instrumented binaries).
#   Step 2 — run-prof     : Submit a short (1h) MPI run to collect
#                           per-rank *.dyn profile files in PROF_DIR.
#   Step 3 — merge        : Run profmerge in PROF_DIR to merge all *.dyn
#                           files into pgopti.dpi (login-node operation).
#   Step 4 — compile-use  : Recompile WW3 with -prof-use -prof-dir PROF_DIR.
#   Step 5 — run-bench    : Submit the full 10h benchmark run.
#
# USAGE
# -----
#   # Interactive — run one step at a time (recommended first time):
#   bash run_phase3_pgo.sh --step 1 --exp-id p3_pgo_avx2
#   bash run_phase3_pgo.sh --step 2 --exp-id p3_pgo_avx2
#   # ... wait for profiling job to complete ...
#   bash run_phase3_pgo.sh --step 3 --exp-id p3_pgo_avx2
#   bash run_phase3_pgo.sh --step 4 --exp-id p3_pgo_avx2
#   bash run_phase3_pgo.sh --step 5 --exp-id p3_pgo_avx2
#
#   # Auto mode — runs all steps (polling for SLURM job completion):
#   bash run_phase3_pgo.sh --auto --exp-id p3_pgo_avx2
#
#   # Dry-run preview:
#   bash run_phase3_pgo.sh --auto --exp-id p3_pgo_avx2 --dry-run
#
# OPTIONS
#   --exp-id ID        Experiment name (default: p3_pgo_avx2)
#   --step N           Run only step N (1-5)
#   --auto             Run all steps in sequence (polls SLURM for step 3/4/5 gate)
#   --base-flags STR   Override default base compiler flags
#   --release-flags STR Override default release compiler flags
#   --dry-run          Print all actions without executing
#   --poll-interval N  Seconds between SLURM job status polls (default: 60)
#   -h | --help        Show this help message
#
# DEFAULT COMPILER FLAGS (best Phase 3 config from Phase 2 analysis)
# -------------------------------------------------------------------
#   Base:    -no-fma -ipo -i4 -real-size 32 -fp-model fast=2
#            -assume byterecl -fno-alias -fno-fnalias
#            (NOTE: -g -traceback deliberately omitted — release build)
#   Release: -O3 -unroll-aggressive -mavx2 -mfma
#
# PGO MECHANICS
# -------------
# - -prof-gen at compile time:  instruments binary to count execution frequency.
# - Each MPI rank writes pgopti_<rank>.dyn to PROF_DIR = <model_dir>/pgocache/
# - profmerge (Intel tool) merges all .dyn → pgopti.dpi (oneAPI 2023+ format).
# - -prof-use -prof-dir PROF_DIR at recompile: uses profile to guide inlining,
#   block ordering, and vectorisation decisions.
# - Expected gain over Phase 3A best: 5–15%.
#
# IMPORTANT — PROF_DIR must be on a shared filesystem all compute nodes
# can write to simultaneously. The path below (under MODELS_ROOT on
# /nobackup/forsk) is on Fahrenheit's Lustre shared storage.
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"

DEPENDENCIES=(bash cp rm find ls sbatch squeue)

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
REFERENCE_MODEL="${MODELS_ROOT}/test_Hamish"
SWITCH_FILE="${REFERENCE_MODEL}/WW3/model/bin/switch_dnora"

# Workspace root -- derived from this script location (benchmarking/ subdir)
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${BENCH_DIR}/scripts"
CONFIG_DIR="${BENCH_DIR}/configs/oneVar_noSaving"

# Slurm layout — identical to Phase 1/2 for fair comparison
RUN_NODES=16
RUN_TASKS_PER_NODE=60
RUN_CPUS_PER_TASK=2
PROF_DURATION="1h"    # short sim for profiling collection
BENCH_DURATION="10h"  # full benchmark run

# SLURM poll interval (auto mode only)
POLL_INTERVAL=60

# =============================================================================
# DEFAULT PGO FLAGS
# (best Phase 3 config: fp_fast2 + ipo + AVX2 + no debug overhead)
# Override with --base-flags / --release-flags.
# =============================================================================

DEFAULT_BASE_FLAGS="-no-fma -ipo -i4 -real-size 32 -fp-model fast=2 -assume byterecl -fno-alias -fno-fnalias"
DEFAULT_RELEASE_FLAGS="-O3 -unroll-aggressive -mavx2 -mfma"

# =============================================================================
# Helpers
# =============================================================================
function print_header() { echo -e "\n${BLUE}══ $* ══${NC}"; }
function print_step()   { echo -e "\n${GREEN}[Step $1/$2]${NC} $3"; }
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

WW3 Profile-Guided Optimisation (PGO) — Phase 3 workflow.

usage: ${SCRIPT_NAME} [options]

options:
    --exp-id ID           Experiment name  (default: p3_pgo_avx2)
    --step N              Run only step N  (1=compile-gen, 2=run-prof,
                            3=merge, 4=compile-use, 5=run-bench)
    --auto                Run all 5 steps in sequence; polls Slurm for gates
    --base-flags STR      Override base compiler flags (default below)
    --release-flags STR   Override release compiler flags (default below)
    --dry-run             Print all actions without executing
    --poll-interval N     Seconds between Slurm polls in --auto mode (default: 60)
    -h | --help           Show this help message
    --version             Print version string

default base flags:
    ${DEFAULT_BASE_FLAGS}

default release flags:
    ${DEFAULT_RELEASE_FLAGS}

examples:
    # Run all steps automatically
    ${SCRIPT_NAME} --auto --exp-id p3_pgo_avx2

    # Step-by-step (run after each previous step completes)
    ${SCRIPT_NAME} --step 1 --exp-id p3_pgo_avx2
    ${SCRIPT_NAME} --step 2 --exp-id p3_pgo_avx2
    # ... wait for Slurm job to finish (squeue -u \$(whoami)) ...
    ${SCRIPT_NAME} --step 3 --exp-id p3_pgo_avx2
    ${SCRIPT_NAME} --step 4 --exp-id p3_pgo_avx2
    ${SCRIPT_NAME} --step 5 --exp-id p3_pgo_avx2

    # Preview everything without running
    ${SCRIPT_NAME} --auto --exp-id p3_pgo_avx2 --dry-run

results:
    column -t -s, ${BENCH_DIR}/benchmark_summary.csv

EOM
    exit 1
}

# =============================================================================
# patch_cmake — write base + release flags into CMakeLists.txt
# =============================================================================
function patch_cmake() {
    local cmake_file="$1"
    local base_flags="$2"
    local release_flags="$3"

    # Convert space-separated flags to CMake list (semicolon-separated)
    local base_cmake release_cmake
    base_cmake=$(echo "${base_flags}"    | sed 's/ /;/g')
    release_cmake=$(echo "${release_flags}" | sed 's/ /;/g')

    python3 - "${cmake_file}" "${base_cmake}" "${release_cmake}" << 'PYEOF'
import sys, re

cmake_file   = sys.argv[1]
base_flags   = sys.argv[2]
release_flags = sys.argv[3]

with open(cmake_file, 'r') as f:
    content = f.read()

# Replace compile_flags block (base, all build types)
content = re.sub(
    r'(set\s*\(\s*compile_flags\s+)([^)]+)(\))',
    lambda m: m.group(1) + base_flags + m.group(3),
    content, count=1, flags=re.DOTALL
)

# Replace compile_flags_release block
content = re.sub(
    r'(set\s*\(\s*compile_flags_release\s+)([^)]+)(\))',
    lambda m: m.group(1) + release_flags + m.group(3),
    content, count=1, flags=re.DOTALL
)

with open(cmake_file, 'w') as f:
    f.write(content)

print(f"  patched: {cmake_file}")
PYEOF
}

# =============================================================================
# write_compile_script — emit a bash script that builds WW3 with given flags
#
# $1 exp_id
# $2 model_dir
# $3 ww3_dir
# $4 build_dir
# $5 binary path
# $6 label (human-readable, used in log filename)
# $7 extra_post_builddir  (optional bash lines injected after 'mkdir build && cd build')
# =============================================================================
function write_compile_script() {
    local exp_id="$1"
    local model_dir="$2"
    local ww3_dir="$3"
    local build_dir="$4"
    local binary="$5"
    local label="$6"   # human-readable label for the log file
    local extra_post_builddir="${7:-}"  # optional commands after mkdir build

    local compile_script="${model_dir}/compile_${exp_id}_${label}.sh"

    cat > "${compile_script}" << COMPEOF
#!/usr/bin/env bash
# Auto-generated by run_phase3_pgo.sh  (${label})
set -euo pipefail

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
${extra_post_builddir}
cmake .. \\
    -DSWITCH="${SWITCH_FILE}" \\
    -DCMAKE_INSTALL_PREFIX=install \\
    -DCMAKE_BUILD_TYPE=Release

# Build only the executables needed for CARRA2 runs (skip unused tools).
make -j 24 ww3_grid ww3_prnc ww3_ounf ww3_bounc ww3_shel

# Install only those binaries (cmake --install with --component is not set,
# so just copy them manually to match what 'make install' would do).
mkdir -p install/bin
for exe in ww3_grid ww3_prnc ww3_ounf ww3_bounc ww3_shel; do
    find . -name "\${exe}" -type f ! -path "*/CMakeFiles/*" -exec cp {} install/bin/ \;
done

echo "Build complete (${label}): ${exp_id}"
ls -lh "${binary}" 2>/dev/null || echo "WARNING: binary not found after install"
COMPEOF
    chmod +x "${compile_script}"
    echo "${compile_script}"
}

# =============================================================================
# create_model_exe_symlinks — bridge cmake install/bin → model/exe/
# Required because setup.sh expects executables in WW3/model/exe/
# =============================================================================
function create_model_exe_symlinks() {
    local build_dir="$1"
    local ww3_dir="$2"

    local bin_dir="${build_dir}/install/bin"
    local exe_dir="${ww3_dir}/model/exe"

    mkdir -p "${exe_dir}"

    for prog in ww3_grid ww3_bounc ww3_prnc ww3_shel ww3_multi ww3_ounf; do
        local target="${bin_dir}/${prog}"
        local link="${exe_dir}/${prog}"
        if [[ -f "${target}" ]]; then
            ln -sf "${target}" "${link}"
            echo "  symlink: ${link} → ${target}"
        else
            print_warning "Binary not found, symlink skipped: ${target}"
        fi
    done
}

# =============================================================================
# wait_for_slurm_job — poll until job is COMPLETED or FAILED
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
            # Job no longer in queue — check sacct
            state=$(sacct -j "${job_id}" --format=State --noheader -X 2>/dev/null | awk '{print $1}' | head -1 | xargs)
        fi

        case "${state}" in
            COMPLETED)
                echo ""
                print_success "Job ${job_id} completed successfully."
                return 0
                ;;
            FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL)
                echo ""
                print_error "Job ${job_id} finished with state: ${state}"
                return 1
                ;;
            "")
                echo ""
                print_warning "Could not determine state of job ${job_id} — assuming completed."
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
# STEP 1 — compile with -prof-gen
# =============================================================================
function step1_compile_gen() {
    local exp_id="$1"
    local base_flags="$2"
    local release_flags="$3"

    local model_dir="${MODELS_ROOT}/${exp_id}"
    local ww3_dir="${model_dir}/WW3"
    local build_dir="${ww3_dir}/build"
    local cmake_file="${ww3_dir}/model/src/CMakeLists.txt"
    local binary="${build_dir}/install/bin/ww3_shel"
    local prof_dir="${model_dir}/pgocache"   # OUTSIDE build/ — safe from rm -rf build

    print_step 1 5 "Compile with -prof-gen  [${exp_id}]"
    echo "  Base flags   : ${base_flags}"
    echo "  Release flags: ${release_flags} -prof-gen -prof-dir ${prof_dir}"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} Would copy ${REFERENCE_MODEL} → ${model_dir}"
        echo -e "  ${BLUE}[DRY]${NC} Would patch CMakeLists.txt with -prof-gen in release flags"
        echo -e "  ${BLUE}[DRY]${NC} Would compile WW3"
        return 0
    fi

    # Copy reference model
    if [[ -d "${model_dir}" ]]; then
        print_warning "Model dir exists — removing: ${model_dir}"
        rm -rf "${model_dir}"
    fi
    cp -r "${REFERENCE_MODEL}" "${model_dir}"

    # Create PROF_DIR now — it lives outside build/ so rm -rf build cannot wipe it.
    mkdir -p "${prof_dir}"

    # Patch CMakeLists.txt with base + release + -prof-gen flags
    if [[ ! -f "${cmake_file}" ]]; then
        print_error "CMakeLists.txt not found: ${cmake_file}"
        return 1
    fi
    cp "${cmake_file}" "${cmake_file}.bak_pgo_gen"

    local gen_release="${release_flags} -prof-gen -prof-dir ${prof_dir}"
    if ! patch_cmake "${cmake_file}" "${base_flags}" "${gen_release}"; then
        print_error "patch_cmake failed for -prof-gen build"
        return 1
    fi

    # Write and run compile script.
    # pgocache lives outside build/ so the compile script's 'rm -rf build' is safe.
    local compile_script
    compile_script=$(write_compile_script \
        "${exp_id}" "${model_dir}" "${ww3_dir}" "${build_dir}" "${binary}" "gen")

    echo "  Running -prof-gen compile (this takes a few minutes) ..."
    if ! bash "${compile_script}" 2>&1 | tee "${model_dir}/compile_${exp_id}_gen.log"; then
        print_error "Compilation (gen) failed. See: ${model_dir}/compile_${exp_id}_gen.log"
        return 1
    fi

    if [[ ! -f "${binary}" ]]; then
        print_error "ww3_shel not found after -prof-gen build: ${binary}"
        return 1
    fi

    # Create model/exe symlinks so setup.sh can find the binary
    create_model_exe_symlinks "${build_dir}" "${ww3_dir}"

    print_success "Step 1 done. Instrumented binary: ${binary}"
    print_info "Next: run  --step 2 --exp-id ${exp_id}"
}

# =============================================================================
# STEP 2 — submit profiling run (1h sim)
# Writes the SLURM job ID to a state file so subsequent steps can use it.
# =============================================================================
function step2_run_prof() {
    local exp_id="$1"

    local model_dir="${MODELS_ROOT}/${exp_id}"
    local ww3_dir="${model_dir}/WW3"
    local build_dir="${ww3_dir}/build"
    local prof_dir="${model_dir}/pgocache"   # OUTSIDE build/ — safe from rm -rf build
    local state_file="${model_dir}/pgo_state.env"

    print_step 2 5 "Submit profiling run (${PROF_DURATION} sim)  [${exp_id}]"

    if [[ ! -d "${model_dir}" ]]; then
        print_error "Model dir not found — run Step 1 first: ${model_dir}"
        return 1
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} Would call: ./setup.sh --force -e ${exp_id}_prof -w ${ww3_dir} -c ${CONFIG_DIR}"
        echo -e "  ${BLUE}[DRY]${NC} Would call: ./run_exp.sh -e ${exp_id}_prof -N ${RUN_NODES} -n ${RUN_TASKS_PER_NODE} --cpus-per-task ${RUN_CPUS_PER_TASK} -d ${PROF_DURATION}"
        echo -e "  ${BLUE}[DRY]${NC} Would export I_MPI_DAPL_TRANSLATION_CACHE=0 OMP_NUM_THREADS=${RUN_CPUS_PER_TASK} PROF_DIR=${prof_dir}"
        return 0
    fi

    # Set profile data directory in the job environment via env.sh
    local env_file="${BENCH_DIR}/experiments/${exp_id}_prof/metadata/setup/env.sh"

    # Setup experiment
    cd "${BENCH_DIR}" || { print_error "Cannot cd to ${BENCH_DIR}"; return 1; }
    bash "${SCRIPT_DIR}/setup.sh" --force -e "${exp_id}_prof" -w "${ww3_dir}" -c "${CONFIG_DIR}" || {
        print_error "setup.sh failed for ${exp_id}_prof"
        return 1
    }

    # Append profiling env vars to env.sh so run_shel.job inherits them:
    #   PROF_DIR        — tells the instrumented binary where to write .dyn files
    #   INTEL_PROF_DUMP_CUMULATIVE=1 — each MPI rank writes a uniquely-named
    #     pgopti_<rank>.dyn file instead of competing for a shared lock.
    #     Critical with 960 MPI ranks to avoid Lustre contention.
    if [[ -f "${env_file}" ]]; then
        chmod u+w "${env_file}"
        {
            echo "export PROF_DIR=\"${prof_dir}\""
            echo "export INTEL_PROF_DUMP_CUMULATIVE=1"
        } >> "${env_file}"
        chmod a-w "${env_file}"
        print_info "Appended PROF_DIR and INTEL_PROF_DUMP_CUMULATIVE to env.sh"
    else
        print_warning "env.sh not found at ${env_file} — PROF_DIR may not be set for compute nodes"
    fi

    # Submit profiling run and capture job ID
    local submit_output
    submit_output=$(bash "${SCRIPT_DIR}/run_exp.sh" \
        -e "${exp_id}_prof" \
        -N "${RUN_NODES}" \
        -n "${RUN_TASKS_PER_NODE}" \
        --cpus-per-task "${RUN_CPUS_PER_TASK}" \
        -d "${PROF_DURATION}" 2>&1)

    echo "${submit_output}"

    local prof_job_id
    prof_job_id=$(echo "${submit_output}" | grep -oP 'Shel job\s*:\s*\K[0-9]+' | tail -1)

    if [[ -z "${prof_job_id}" ]]; then
        print_error "Could not extract SLURM job ID from submit output"
        print_error "Output was: ${submit_output}"
        return 1
    fi

    # Persist state for subsequent steps
    cat > "${state_file}" << STEOF
# PGO state file — generated by run_phase3_pgo.sh
# Do not edit.
PGO_EXP_ID="${exp_id}"
PGO_PROF_JOB_ID="${prof_job_id}"
PGO_PROF_DIR="${prof_dir}"
PGO_BASE_FLAGS="${BASE_FLAGS}"
PGO_RELEASE_FLAGS="${RELEASE_FLAGS}"
STEOF

    print_success "Profiling job submitted: ${prof_job_id}"
    print_info "State saved to: ${state_file}"
    print_info "Monitor: squeue -j ${prof_job_id}"
    print_info "Next after job completes: --step 3 --exp-id ${exp_id}"
}

# =============================================================================
# STEP 3 — merge profile data (profmerge)
# =============================================================================
function step3_merge() {
    local exp_id="$1"

    local model_dir="${MODELS_ROOT}/${exp_id}"
    local state_file="${model_dir}/pgo_state.env"

    print_step 3 5 "Merge profile data (profmerge)  [${exp_id}]"

    if [[ ! -f "${state_file}" ]]; then
        print_error "State file not found — run Steps 1 and 2 first: ${state_file}"
        return 1
    fi

    # shellcheck source=/dev/null
    source "${state_file}"

    local prof_dir="${PGO_PROF_DIR}"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} Would cd ${prof_dir} && profmerge"
        return 0
    fi

    if [[ ! -d "${prof_dir}" ]]; then
        print_error "Profile directory not found: ${prof_dir}"
        print_error "Did the profiling run (Step 2) complete successfully?"
        return 1
    fi

    # -maxdepth must come before -name (global option in GNU find)
    local dyn_count
    dyn_count=$(find "${prof_dir}" -maxdepth 2 -name "*.dyn" | wc -l)

    if [[ "${dyn_count}" -eq 0 ]]; then
        print_error "No .dyn profile files found in ${prof_dir}"
        print_error "The profiling run may have failed or PROF_DIR was not set correctly."
        print_error "Check: ls ${prof_dir}"
        return 1
    fi

    # Remove zero-byte .dyn files — they're from ranks that crashed before
    # writing any profile data and will cause profmerge error #30024.
    local removed_count=0
    while IFS= read -r -d '' bad_file; do
        print_warning "Removing zero-byte .dyn file: $(basename "${bad_file}")"
        rm -f "${bad_file}"
        (( removed_count++ )) || true
    done < <(find "${prof_dir}" -maxdepth 2 -name "*.dyn" -size 0 -print0)
    [[ "${removed_count}" -gt 0 ]] && print_info "Removed ${removed_count} zero-byte .dyn file(s)"

    # Re-count after cleanup
    dyn_count=$(find "${prof_dir}" -maxdepth 2 -name "*.dyn" | wc -l)
    print_info "Merging ${dyn_count} .dyn profile files ..."

    # profmerge scans the current directory by default; run it from PROF_DIR.
    # NOTE: profmerge does NOT accept -a <files>; just run it from the dir.
    cd "${prof_dir}" || { print_error "Cannot cd to ${prof_dir}"; return 1; }

    local merge_log="${prof_dir}/profmerge.log"
    # Use a subshell to avoid polluting the calling environment.
    # Redirect inside the subshell so the exit code is not masked by tee.
    #
    # IMPORTANT: do NOT do 'module purge' before running profmerge — it strips
    # LD_LIBRARY_PATH and causes profmerge to exit 0 silently producing nothing.
    # The buildenv module should already be loaded on the login node; if not,
    # load it without purging the existing environment first.
    # profmerge and ifort are in the same bin dir; always use that one.
    local merge_ok=0
    (
        exec > >(tee "${merge_log}") 2>&1
        module load buildenv-intel/2023.1.0-hpc1 2>/dev/null || true

        # Locate profmerge colocated with ifort (guarantees format compatibility).
        local ifort_bin
        ifort_bin=$(dirname "$(command -v ifort 2>/dev/null)")
        local profmerge_bin="${ifort_bin}/profmerge"
        if [[ ! -x "${profmerge_bin}" ]]; then
            profmerge_bin=$(command -v profmerge 2>/dev/null)
        fi
        if [[ -z "${profmerge_bin}" ]]; then
            echo "ERROR: profmerge not found (checked ${ifort_bin} and PATH)"
            exit 1
        fi
        echo "Using profmerge: ${profmerge_bin}"
        echo "ifort:          $(command -v ifort 2>/dev/null)"
        echo "Running: profmerge (scanning ${prof_dir})"
        "${profmerge_bin}"
    ) && merge_ok=1

    # oneAPI 2023+ writes pgopti.dpi (not pgopti.ddf); check for either.
    local merged_file=""
    [[ -f "${prof_dir}/pgopti.dpi" ]] && merged_file="${prof_dir}/pgopti.dpi"
    [[ -f "${prof_dir}/pgopti.ddf" ]] && merged_file="${prof_dir}/pgopti.ddf"

    # If profmerge succeeded but produced no merged file, LD_LIBRARY_PATH or
    # version mismatch — print diagnostics.
    if [[ "${merge_ok}" -eq 1 ]] && [[ -z "${merged_file}" ]]; then
        print_warning "profmerge exited 0 but produced no pgopti.dpi/ddf — diagnostic info:"
        cat "${merge_log}" 2>/dev/null
        local dyn_example
        dyn_example=$(find "${prof_dir}" -maxdepth 1 -name "*.dyn" | head -1)
        [[ -n "${dyn_example}" ]] && print_warning "Example .dyn file: $(ls -lh "${dyn_example}")"
        merge_ok=0
    fi

    # If profmerge failed (exit non-zero), check for "unrecognized header" errors
    # (error #30024) — partially-written .dyn from ranks killed mid-write.
    # Remove those files and retry once.
    if [[ "${merge_ok}" -eq 0 ]]; then
        local bad_files
        bad_files=$(grep -oP "(?<=: )\.+/[^\s]+\.dyn" "${merge_log}" 2>/dev/null | sort -u)
        if [[ -n "${bad_files}" ]]; then
            print_warning "profmerge found corrupted .dyn files — removing and retrying:"
            while IFS= read -r bad; do
                local abs_bad="${prof_dir}/${bad#./}"
                abs_bad="${abs_bad//\/\///}"
                print_warning "  Removing: ${abs_bad}"
                rm -f "${abs_bad}"
            done <<< "${bad_files}"

            merge_ok=0
            (
                exec >> >(tee -a "${merge_log}") 2>&1
                module load buildenv-intel/2023.1.0-hpc1 2>/dev/null || true
                local ifort_bin; ifort_bin=$(dirname "$(command -v ifort 2>/dev/null)")
                local profmerge_bin="${ifort_bin}/profmerge"
                [[ -x "${profmerge_bin}" ]] || profmerge_bin=$(command -v profmerge)
                echo "--- Retry after removing corrupted files ---"
                "${profmerge_bin}"
            ) && merge_ok=1
            [[ -f "${prof_dir}/pgopti.dpi" ]] && merged_file="${prof_dir}/pgopti.dpi"
            [[ -f "${prof_dir}/pgopti.ddf" ]] && merged_file="${prof_dir}/pgopti.ddf"
        fi
    fi

    if [[ "${merge_ok}" -eq 0 ]] || [[ -z "${merged_file}" ]]; then
        print_error "profmerge failed — see ${merge_log}"
        cat "${merge_log}" 2>/dev/null
        return 1
    fi

    print_success "Profile merged: ${merged_file}"
    print_info "Next: --step 4 --exp-id ${exp_id}"
}

# =============================================================================
# STEP 4 — recompile with -prof-use
# =============================================================================
function step4_compile_use() {
    local exp_id="$1"

    local model_dir="${MODELS_ROOT}/${exp_id}"
    local state_file="${model_dir}/pgo_state.env"
    local ww3_dir="${model_dir}/WW3"
    local build_dir="${ww3_dir}/build"
    local cmake_file="${ww3_dir}/model/src/CMakeLists.txt"
    local binary="${build_dir}/install/bin/ww3_shel"

    print_step 4 5 "Recompile with -prof-use  [${exp_id}]"

    if [[ ! -f "${state_file}" ]]; then
        print_error "State file not found: ${state_file}"
        return 1
    fi

    # shellcheck source=/dev/null
    source "${state_file}"

    local prof_dir="${PGO_PROF_DIR}"
    local base_flags="${PGO_BASE_FLAGS}"
    local release_flags="${PGO_RELEASE_FLAGS}"

    echo "  Prof dir     : ${prof_dir}"
    echo "  Base flags   : ${base_flags}"
    echo "  Release flags: ${release_flags} -prof-use -prof-dir ${prof_dir}"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} Would restore CMakeLists.txt.bak_pgo_gen → patch with -prof-use flags"
        echo -e "  ${BLUE}[DRY]${NC} Would recompile WW3"
        return 0
    fi

    # Verify pgopti.dpi exists (produced by Step 3 profmerge).
    # pgocache lives outside build/ so rm -rf build cannot wipe it.
    if [[ ! -f "${prof_dir}/pgopti.dpi" ]] && [[ ! -f "${prof_dir}/pgopti.ddf" ]]; then
        print_error "pgopti.dpi not found — run Step 3 first: ${prof_dir}/pgopti.dpi"
        return 1
    fi

    # Restore original CMakeLists.txt backup, then patch for -prof-use
    if [[ -f "${cmake_file}.bak_pgo_gen" ]]; then
        cp "${cmake_file}.bak_pgo_gen" "${cmake_file}"
    elif [[ ! -f "${cmake_file}" ]]; then
        print_error "CMakeLists.txt not found: ${cmake_file}"
        return 1
    fi

    cp "${cmake_file}" "${cmake_file}.bak_pgo_use"

    local use_release="${release_flags} -prof-use -prof-dir ${prof_dir}"
    if ! patch_cmake "${cmake_file}" "${base_flags}" "${use_release}"; then
        print_error "patch_cmake failed for -prof-use build"
        return 1
    fi

    # pgocache lives at model_dir/pgocache (outside build/) — safe from rm -rf build.
    # No backup/restore needed.
    local compile_script
    compile_script=$(write_compile_script "${exp_id}" "${model_dir}" "${ww3_dir}" "${build_dir}" "${binary}" "use")

    echo "  Running -prof-use compile (this takes a few minutes) ..."
    if ! bash "${compile_script}" 2>&1 | tee "${model_dir}/compile_${exp_id}_use.log"; then
        print_error "Compilation (use) failed. See: ${model_dir}/compile_${exp_id}_use.log"
        return 1
    fi

    if [[ ! -f "${binary}" ]]; then
        print_error "ww3_shel not found after -prof-use build: ${binary}"
        return 1
    fi

    # Refresh model/exe symlinks (they now point to the new PGO-optimised binary)
    create_model_exe_symlinks "${build_dir}" "${ww3_dir}"

    print_success "Step 4 done. PGO-optimised binary: ${binary}"
    print_info "Next: --step 5 --exp-id ${exp_id}"
}

# =============================================================================
# STEP 5 — submit benchmark run
# =============================================================================
function step5_run_bench() {
    local exp_id="$1"

    local model_dir="${MODELS_ROOT}/${exp_id}"
    local ww3_dir="${model_dir}/WW3"

    print_step 5 5 "Submit benchmark run (${BENCH_DURATION} sim)  [${exp_id}]"

    if [[ ! -d "${model_dir}" ]]; then
        print_error "Model dir not found — run Steps 1–4 first: ${model_dir}"
        return 1
    fi

    local binary="${model_dir}/WW3/build/install/bin/ww3_shel"
    if [[ "${DRY_RUN}" == false && ! -f "${binary}" ]]; then
        print_error "PGO-optimised binary not found: ${binary}"
        print_error "Check Step 4 completed successfully."
        return 1
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} Would call: ./setup.sh --force -e ${exp_id} -w ${ww3_dir} -c ${CONFIG_DIR}"
        echo -e "  ${BLUE}[DRY]${NC} Would call: ./run_exp.sh -e ${exp_id} -N ${RUN_NODES} -n ${RUN_TASKS_PER_NODE} --cpus-per-task ${RUN_CPUS_PER_TASK} -d ${BENCH_DURATION}"
        return 0
    fi

    cd "${BENCH_DIR}" || { print_error "Cannot cd to ${BENCH_DIR}"; return 1; }

    bash "${SCRIPT_DIR}/setup.sh" --force -e "${exp_id}" -w "${ww3_dir}" -c "${CONFIG_DIR}" || {
        print_error "setup.sh failed for ${exp_id}"
        return 1
    }

    local submit_output
    submit_output=$(bash "${SCRIPT_DIR}/run_exp.sh" \
        -e "${exp_id}" \
        -N "${RUN_NODES}" \
        -n "${RUN_TASKS_PER_NODE}" \
        --cpus-per-task "${RUN_CPUS_PER_TASK}" \
        -d "${BENCH_DURATION}" 2>&1)

    echo "${submit_output}"

    local bench_job_id
    bench_job_id=$(echo "${submit_output}" | grep -oP 'Shel job\s*:\s*\K[0-9]+' | tail -1)

    if [[ -n "${bench_job_id}" ]]; then
        print_success "Benchmark job submitted: ${bench_job_id}"
        print_info "Monitor: squeue -j ${bench_job_id}"
    else
        print_warning "Could not extract job ID — check submit output above"
    fi

    print_info "Results when done:"
    print_info "  column -t -s, ${BENCH_DIR}/benchmark_summary.csv"
}

# =============================================================================
# auto_mode — run all 5 steps sequentially, gating on SLURM completion
# =============================================================================
function auto_mode() {
    local exp_id="$1"
    local base_flags="$2"
    local release_flags="$3"

    print_header "PGO Auto Mode  (exp: ${exp_id})"

    # Step 1
    step1_compile_gen "${exp_id}" "${base_flags}" "${release_flags}" || return 1

    # Step 2 — submit profiling run
    step2_run_prof "${exp_id}" || return 1

    if [[ "${DRY_RUN}" == false ]]; then
        # Read the profiling job ID from state file
        local state_file="${MODELS_ROOT}/${exp_id}/pgo_state.env"
        source "${state_file}"
        local prof_job_id="${PGO_PROF_JOB_ID}"

        # Poll until profiling job completes
        print_info "Waiting for profiling job ${prof_job_id} to finish ..."
        if ! wait_for_slurm_job "${prof_job_id}" "${POLL_INTERVAL}"; then
            print_error "Profiling job ${prof_job_id} did not complete successfully."
            print_error "Aborting PGO workflow. Inspect the job logs and retry --step 2."
            return 1
        fi
    fi

    # Step 3 — merge profiles
    step3_merge "${exp_id}" || return 1

    # Step 4 — recompile with -prof-use
    step4_compile_use "${exp_id}" || return 1

    # Step 5 — final benchmark
    step5_run_bench "${exp_id}" || return 1

    print_success "PGO workflow complete for ${exp_id}."
    print_info "Results: column -t -s, ${BENCH_DIR}/benchmark_summary.csv"
}

# =============================================================================
# main
# =============================================================================
function main() {
    local exp_id="p3_pgo_avx2"
    local step=""
    local do_auto=false
    local base_flags="${DEFAULT_BASE_FLAGS}"
    local release_flags="${DEFAULT_RELEASE_FLAGS}"
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --exp-id)
                shift
                [[ -z "${1:-}" ]] && { print_error "--exp-id requires a value"; usage; }
                exp_id="$1"
                ;;
            --step)
                shift
                [[ -z "${1:-}" ]] && { print_error "--step requires a value (1-5)"; usage; }
                step="$1"
                ;;
            --auto)
                do_auto=true
                ;;
            --base-flags)
                shift
                [[ -z "${1:-}" ]] && { print_error "--base-flags requires a value"; usage; }
                base_flags="$1"
                ;;
            --release-flags)
                shift
                [[ -z "${1:-}" ]] && { print_error "--release-flags requires a value"; usage; }
                release_flags="$1"
                ;;
            --dry-run)
                dry_run=true
                ;;
            --poll-interval)
                shift
                [[ -z "${1:-}" ]] && { print_error "--poll-interval requires a value"; usage; }
                POLL_INTERVAL="$1"
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

    if [[ "${dry_run}" == true && -z "${step}" && "${do_auto}" == false ]]; then
        print_error "--dry-run requires --step N or --auto"
        usage
    fi

    if [[ -z "${step}" && "${do_auto}" == false ]]; then
        print_error "Specify --step N (1-5) or --auto"
        usage
    fi

    # Export as globals so helper functions can reference them
    DRY_RUN="${dry_run}"
    BASE_FLAGS="${base_flags}"
    RELEASE_FLAGS="${release_flags}"

    check_dependencies

    print_header "WW3 PGO Workflow  v${VERSION}"
    echo "  Experiment          : ${exp_id}"
    echo "  Base flags          : ${base_flags}"
    echo "  Release flags       : ${release_flags}"
    echo "  PGO profile dir     : ${MODELS_ROOT}/${exp_id}/WW3/build/pgocache"
    echo "  Profiling sim       : ${PROF_DURATION}"
    echo "  Benchmark sim       : ${BENCH_DURATION}"
    echo "  Dry-run             : ${DRY_RUN}"
    [[ -n "${step}" ]] && echo "  Running step        : ${step}"
    "${do_auto}" && echo "  Mode                : AUTO (all steps)"

    if "${do_auto}"; then
        auto_mode "${exp_id}" "${base_flags}" "${release_flags}"
    else
        case "${step}" in
            1) step1_compile_gen   "${exp_id}" "${base_flags}" "${release_flags}" ;;
            2) step2_run_prof      "${exp_id}" ;;
            3) step3_merge         "${exp_id}" ;;
            4) step4_compile_use   "${exp_id}" ;;
            5) step5_run_bench     "${exp_id}" ;;
            *)
                print_error "Invalid step: ${step}. Must be 1-5."
                usage
                ;;
        esac
    fi
}

main "$@"
