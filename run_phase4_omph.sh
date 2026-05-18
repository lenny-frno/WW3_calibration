#!/usr/bin/env bash
# =============================================================================
# run_phase4_omph.sh — WW3 OpenMP Hybrid (OMPH + OMPG) compilation & benchmark
# =============================================================================
# Version: 1.0
#
# WHAT IT DOES
# ------------
# Compiles WW3 with OpenMP support enabled via two WW3 preprocessor switches:
#
#   OMPH — threads the inner NSEA loops in W3XYP2/W3UNO2 (propagation scheme
#          in w3pro2md.F90 / w3uno2md.F90).  Each MPI rank's propagation work
#          over the ~4 200 local sea points is shared across OMP threads.
#
#   OMPG — threads the outer spectral-source loop in w3srcemd.F90 (source
#          terms).  NSPEC=1152 spectral bins are divided across OMP threads.
#
# Both switches add !$OMP PARALLEL DO directives that are currently compiled
# out (guarded by #ifdef W3_OMPH / W3_OMPG).  Enabling them requires:
#   1. Adding OMPH and OMPG to the WW3 switch file.
#   2. Adding -qopenmp to the Intel Fortran base compile flags.
#
# WHY cpus-per-task MATTERS
# -------------------------
# Without OpenMP changes, cpus-per-task=2 is needed because Intel MPI
# (I_MPI_FABRICS=shm:ofi) spawns an async-progress thread that handles
# inter-node OFI transfers.  This thread needs a dedicated CPU to prevent
# it from starving the compute thread (causing ~2× slowdown).
#
# With OMPH/OMPG + OMP_NUM_THREADS=2:
#   Variant A (cpus=3): compute thread + 1 OMP worker + async-progress thread
#                       All three get a dedicated CPU.
#                       → Safest: OMP parallelism + async progress overlap.
#   Variant B (cpus=2): I_MPI_ASYNC_PROGRESS=0 + OMP_NUM_THREADS=2
#                       Both CPUs used for OMP computation; MPI progress is
#                       synchronous.  MPI_WAITALL blocks until transfers done.
#                       → More OMP compute but loses the MPI overlap window.
#
# EXPECTED GAIN
# -------------
#   Variant A: 15–30 % speedup over current best (324 s @ 69 tasks/node).
#              Each rank's propagation loops run 2× faster; source terms 2×.
#              Cost: 1 extra CPU per rank (cpus=3 vs 2), so need to lower
#              tasks/node or accept fewer nodes.
#              Fahrenheit has 144 cores/node: floor(144/3) = 48 tasks max.
#   Variant B (cpus=2, no async): similar OMP gain but MPI burdened.
#              Net gain depends on overlap quality; expected 10–25 % speedup.
#
# NODE BUDGET WITH cpus-per-task  (Fahrenheit: 144 cores / node)
# ---------------------------------------------------------------
#   cpus/task=3, tasks/node=48  → 48×3 = 144 CPUs  (100%, max)
#   cpus/task=3, tasks/node=46  → 46×3 = 138 CPUs  (95.8%, safe default)
#   cpus/task=2, tasks/node=60  → 60×2 = 120 CPUs  (current benchmark)
#   cpus/task=2, tasks/node=72  → 72×2 = 144 CPUs  (max for cpus=2)
#
# STEPS
# -----
#   1. compile  — copy reference model, patch switch file and CMakeLists.txt,
#                 compile with -qopenmp on the login node.
#   2. bench-A  — setup + submit at cpus=3, n=42, OMP_NUM_THREADS=2
#                 (async-progress thread on 3rd CPU)
#   3. bench-B  — setup + submit at cpus=2, n=60, OMP_NUM_THREADS=2,
#                 I_MPI_ASYNC_PROGRESS=0 (both CPUs for OMP, no async MPI)
#
# USAGE
# -----
#   # compile then benchmark variant A:
#   bash run_phase4_omph.sh --step 1 --exp-id p4_omph
#   bash run_phase4_omph.sh --step 2 --exp-id p4_omph
#
#   # compile then benchmark variant B:
#   bash run_phase4_omph.sh --step 1 --exp-id p4_omph
#   bash run_phase4_omph.sh --step 3 --exp-id p4_omph
#
#   # run all three steps in sequence:
#   bash run_phase4_omph.sh --auto --exp-id p4_omph
#
#   # dry-run preview:
#   bash run_phase4_omph.sh --auto --exp-id p4_omph --dry-run
#
# OPTIONS
#   --exp-id ID           Experiment base name (default: p4_omph)
#   --step N              Run only step N (1=compile, 2=bench-A, 3=bench-B)
#   --auto                Run steps 1, 2 and 3 in sequence
#   --base-flags STR      Override base compiler flags
#   --release-flags STR   Override release compiler flags
#   --dry-run             Print all actions without executing
#   --poll-interval N     Seconds between Slurm polls (default: 120)
#   -h | --help           Show this help
#
# DEFAULT COMPILER FLAGS (best Phase 3 config)
# (same as p3_pgo_avx2_nd without PGO)
# ----------------------------------------------------
#   Base:    -no-fma -ipo -i4 -real-size 32 -fp-model fast=2
#            -assume byterecl -fno-alias -fno-fnalias -qopenmp   ← ADDED
#   Release: -O3 -unroll-aggressive -mavx2 -mfma
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.0"

DEPENDENCIES=(bash cp rm find ls sed python3 sbatch squeue sacct)

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
REFERENCE_MODEL="${MODELS_ROOT}/test_Hamish"

# Switch file patching chain (step 1):
#   1. REFERENCE_MODEL (test_Hamish) is NEVER modified.
#   2. cp -r test_Hamish → MODELS_ROOT/<exp_id>   (full copy)
#   3. <exp_id>/WW3/model/bin/switch_dnora   ← THIS file is patched (OMPH+OMPG added)
#   4. cmake is invoked with -DSWITCH=<patched switch file in the copy>
# To find the reference switch before patching:
#   cat "${REFERENCE_MODEL}/WW3/model/bin/switch_dnora"

BENCH_DIR="/nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/time_Benchmark"
SCRIPT_DIR="${BENCH_DIR}"
CONFIG_DIR="${BENCH_DIR}/configs/oneVar_noSaving"

# Slurm layout
RUN_NODES=16
BENCH_DURATION="10h"
POLL_INTERVAL=120

# Variant A: cpus=3 (async-progress thread on 3rd CPU)
#   48 tasks/node × 3 CPUs = 144 — fills all cores on Fahrenheit (144 cores/node)
VA_TASKS_PER_NODE=48
VA_CPUS_PER_TASK=3
VA_OMP_THREADS=2

# Variant B: cpus=2, async off, both CPUs for OMP
VB_TASKS_PER_NODE=60
VB_CPUS_PER_TASK=2
VB_OMP_THREADS=2

# =============================================================================
# DEFAULT FLAGS: Phase 3 best (fp_fast2 + ipo + AVX2 + no debug)
# -qopenmp is injected in the compile step, NOT here, to keep the
# base/release split visible.  See patch_cmake_and_switch().
# =============================================================================

DEFAULT_BASE_FLAGS="-no-fma -ipo -i4 -real-size 32 -fp-model fast=2 -assume byterecl -fno-alias -fno-fnalias"
DEFAULT_RELEASE_FLAGS="-O3 -unroll-aggressive -mavx2 -mfma"

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

WW3 Phase 4 — OMPH+OMPG OpenMP hybrid compilation & benchmark.

usage: ${SCRIPT_NAME} [options]

options:
    --exp-id ID           Experiment base name (default: p4_omph)
    --step N              Run step N only:
                            1 = compile (copy ref, patch switch+cmake, build)
                            2 = bench-A (cpus=3, n=42, OMP_THREADS=2, async ON)
                            3 = bench-B (cpus=2, n=60, OMP_THREADS=2, async OFF)
    --auto                Run steps 1, 2 and 3 in sequence
    --base-flags STR      Override base compiler flags
    --release-flags STR   Override release compiler flags
    --dry-run             Print all actions without executing
    --poll-interval N     Seconds between Slurm polls (default: ${POLL_INTERVAL})
    -h | --help           Show this help message
    --version             Print version string

default base flags:
    ${DEFAULT_BASE_FLAGS}  -qopenmp  (appended automatically)

default release flags:
    ${DEFAULT_RELEASE_FLAGS}

examples:
    # All steps in sequence
    ${SCRIPT_NAME} --auto --exp-id p4_omph

    # Step by step
    ${SCRIPT_NAME} --step 1 --exp-id p4_omph
    ${SCRIPT_NAME} --step 2 --exp-id p4_omph    # bench-A: cpus=3
    ${SCRIPT_NAME} --step 3 --exp-id p4_omph    # bench-B: cpus=2 async_off

    # Dry run
    ${SCRIPT_NAME} --auto --exp-id p4_omph --dry-run

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
# patch_cmake — set compile_flags and compile_flags_release in CMakeLists.txt
# Same Python-based patcher as run_phase3_pgo.sh.
# =============================================================================
function patch_cmake() {
    local cmake_file="$1"
    local base_flags="$2"
    local release_flags="$3"

    local base_cmake release_cmake
    base_cmake=$(echo "${base_flags}"    | sed 's/ /;/g')
    release_cmake=$(echo "${release_flags}" | sed 's/ /;/g')

    python3 - "${cmake_file}" "${base_cmake}" "${release_cmake}" << 'PYEOF'
import sys, re

cmake_file    = sys.argv[1]
base_flags    = sys.argv[2]
release_flags = sys.argv[3]

with open(cmake_file, 'r') as f:
    content = f.read()

content = re.sub(
    r'(set\s*\(\s*compile_flags\s+)([^)]+)(\))',
    lambda m: m.group(1) + base_flags + m.group(3),
    content, count=1, flags=re.DOTALL
)

content = re.sub(
    r'(set\s*\(\s*compile_flags_release\s+)([^)]+)(\))',
    lambda m: m.group(1) + release_flags + m.group(3),
    content, count=1, flags=re.DOTALL
)

with open(cmake_file, 'w') as f:
    f.write(content)

print(f"  patched cmake: {cmake_file}")
PYEOF
}

# =============================================================================
# patch_switch_file — add OMPH and OMPG tokens to a WW3 switch file
#
# The switch file is a single line of space-separated switch tokens.
# We add OMPH before the first 'O' output switch and OMPG after OMPH.
# If OMPH/OMPG already present, this is a no-op.
# =============================================================================
function patch_switch_file() {
    local switch_file="$1"

    python3 - "${switch_file}" << 'PYEOF'
import sys, re

sf = sys.argv[1]
with open(sf) as f:
    line = f.read().strip()

tokens = line.split()

for tok in ('OMPH', 'OMPG'):
    if tok not in tokens:
        # Insert OMPH/OMPG right before the first output switch (O0, O1...)
        # so they appear in a logical group with other OMP switches.
        inserted = False
        for i, t in enumerate(tokens):
            if re.match(r'^O\d', t):
                tokens.insert(i, tok)
                inserted = True
                break
        if not inserted:
            tokens.append(tok)
        print(f"  added {tok} to switch file")
    else:
        print(f"  {tok} already present — no change")

with open(sf, 'w') as f:
    f.write(' '.join(tokens) + '\n')

print(f"  switch file: {sf}")
PYEOF
}

# =============================================================================
# create_model_exe_symlinks — bridge cmake install/bin → model/exe/
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
            print_info "symlink: ${link} → ${target}"
        else
            print_warning "Binary not found, symlink skipped: ${target}"
        fi
    done
}

# =============================================================================
# STEP 1 — compile
# =============================================================================
function step1_compile() {
    local exp_id="$1"
    local base_flags="$2"
    local release_flags="$3"

    local model_dir="${MODELS_ROOT}/${exp_id}"
    local ww3_dir="${model_dir}/WW3"
    local build_dir="${ww3_dir}/build"
    local cmake_file="${ww3_dir}/model/src/CMakeLists.txt"
    # switch_file points to the COPY's switch file (inside model_dir, NOT the reference).
    # This script adds OMPH+OMPG to the copy; the reference in REFERENCE_MODEL is untouched.
    local switch_file="${ww3_dir}/model/bin/switch_dnora"
    local binary="${build_dir}/install/bin/ww3_shel"

    # -qopenmp must be in the base flags (applied for ALL build types)
    local base_with_omp="${base_flags} -qopenmp"

    print_header "Step 1/3 — Compile with OMPH+OMPG+OpenMP  [${exp_id}]"
    echo "  Base flags   : ${base_with_omp}"
    echo "  Release flags: ${release_flags}"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} cp -r ${REFERENCE_MODEL} → ${model_dir}"
        echo -e "  ${BLUE}[DRY]${NC} patch switch file: add OMPH OMPG"
        echo -e "  ${BLUE}[DRY]${NC} patch CMakeLists.txt: add -qopenmp to compile_flags"
        echo -e "  ${BLUE}[DRY]${NC} compile WW3"
        return 0
    fi

    # Clean any previous attempt
    if [[ -d "${model_dir}" ]]; then
        print_warning "Model dir exists — removing: ${model_dir}"
        rm -rf "${model_dir}"
    fi

    # Copy reference model
    cp -r "${REFERENCE_MODEL}" "${model_dir}" || {
        print_error "Failed to copy reference model to ${model_dir}"
        return 1
    }
    print_info "Copied reference model → ${model_dir}"

    # Patch switch file (OMPH + OMPG)
    if [[ ! -f "${switch_file}" ]]; then
        print_error "Switch file not found: ${switch_file}"
        return 1
    fi
    cp "${switch_file}" "${switch_file}.bak_omph"
    if ! patch_switch_file "${switch_file}"; then
        print_error "patch_switch_file failed"
        return 1
    fi
    print_info "Switch file after patching: $(cat "${switch_file}")"

    # Patch CMakeLists.txt (base flags + -qopenmp, release flags)
    if [[ ! -f "${cmake_file}" ]]; then
        print_error "CMakeLists.txt not found: ${cmake_file}"
        return 1
    fi
    cp "${cmake_file}" "${cmake_file}.bak_omph"
    if ! patch_cmake "${cmake_file}" "${base_with_omp}" "${release_flags}"; then
        print_error "patch_cmake failed"
        return 1
    fi

    # Write compile script
    local compile_script="${model_dir}/compile_${exp_id}.sh"
    cat > "${compile_script}" << COMPEOF
#!/usr/bin/env bash
# Auto-generated by run_phase4_omph.sh
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
cmake .. \\
    -DSWITCH="${switch_file}" \\
    -DCMAKE_INSTALL_PREFIX=install \\
    -DCMAKE_BUILD_TYPE=Release

make -j 24 ww3_grid ww3_prnc ww3_ounf ww3_bounc ww3_shel

mkdir -p install/bin
for exe in ww3_grid ww3_prnc ww3_ounf ww3_bounc ww3_shel; do
    find . -name "\${exe}" -type f ! -path "*/CMakeFiles/*" -exec cp {} install/bin/ \;
done

echo "Build complete: ${exp_id}"
ls -lh "${binary}" 2>/dev/null || echo "WARNING: binary not found after build"
COMPEOF
    chmod +x "${compile_script}"

    print_info "Running compile script (takes a few minutes) ..."
    if ! bash "${compile_script}" 2>&1 | tee "${model_dir}/compile_${exp_id}.log"; then
        print_error "Compilation failed — see: ${model_dir}/compile_${exp_id}.log"
        return 1
    fi

    if [[ ! -f "${binary}" ]]; then
        print_error "ww3_shel not found after build: ${binary}"
        return 1
    fi

    create_model_exe_symlinks "${build_dir}" "${ww3_dir}"
    print_success "Step 1 done.  Binary: ${binary}"
}

# =============================================================================
# step_bench — generic benchmark submission
#
# $1  exp_id        label for this benchmark run
# $2  ww3_dir       path to WW3 installation
# $3  tasks_per_node
# $4  cpus_per_task
# $5  omp_threads   value to set OMP_NUM_THREADS in env.sh
# $6  async_off     "true" to add I_MPI_ASYNC_PROGRESS=0 to env.sh
# $7  tags
# =============================================================================
function step_bench() {
    local exp_id="$1"
    local ww3_dir="$2"
    local tasks_per_node="$3"
    local cpus_per_task="$4"
    local omp_threads="$5"
    local async_off="$6"
    local tags="$7"

    local env_file="${BENCH_DIR}/experiments/${exp_id}/metadata/setup/env.sh"

    print_header "Benchmark: ${exp_id}  (n=${tasks_per_node} cpus=${cpus_per_task} OMP=${omp_threads} async_off=${async_off})"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${BLUE}[DRY]${NC} setup.sh --force -e ${exp_id} -w ${ww3_dir} -c ${CONFIG_DIR} -t '${tags}'"
        echo -e "  ${BLUE}[DRY]${NC} patch env.sh: OMP_NUM_THREADS=${omp_threads}${async_off:+, I_MPI_ASYNC_PROGRESS=0}"
        echo -e "  ${BLUE}[DRY]${NC} run_exp.sh -e ${exp_id} -N ${RUN_NODES} -n ${tasks_per_node} --cpus-per-task ${cpus_per_task} -d ${BENCH_DURATION}"
        return 0
    fi

    cd "${BENCH_DIR}" || { print_error "Cannot cd to ${BENCH_DIR}"; return 1; }

    bash "${SCRIPT_DIR}/setup.sh" --force \
        -e "${exp_id}" \
        -w "${ww3_dir}" \
        -c "${CONFIG_DIR}" \
        -t "${tags}" || {
        print_error "setup.sh failed for ${exp_id}"
        return 1
    }

    # Patch env.sh:
    # - WW3_OMP_THREADS  : used by run_shel.job (overrides ACTUAL_CPUS_PER_TASK)
    #   → NOT named OMP_NUM_THREADS so that prep.job (ww3_prnc, ww3_grid) is
    #     unaffected.  prep.job keeps OMP_NUM_THREADS=1 (set by setup.sh) and
    #     mpprun does NOT activate --hint multithread for serial preprocessors.
    # - I_MPI_ASYNC_PROGRESS : controls the Intel MPI async-progress thread.
    chmod u+w "$(dirname "${env_file}")" "${env_file}" 2>/dev/null || true
    {
        echo "# Phase 4 OMPH — OpenMP hybrid settings"
        # WW3_OMP_THREADS is picked up only by run_shel.job.
        # prep.job remains at OMP_NUM_THREADS=1 from setup.sh → no breakage.
        echo "export WW3_OMP_THREADS=${omp_threads}"
        if [[ "${async_off}" == "true" ]]; then
            echo "# Async-progress thread disabled: both CPUs used for OMP computation"
            echo "export I_MPI_ASYNC_PROGRESS=0"
        else
            echo "# Async-progress thread enabled (ofi): uses 3rd CPU allocated by Slurm"
            echo "export I_MPI_ASYNC_PROGRESS=1"
        fi
    } >> "${env_file}"
    chmod a-w "${env_file}" 2>/dev/null || true
    print_info "env.sh patched: WW3_OMP_THREADS=${omp_threads}, async_off=${async_off}"

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
# auto_mode
# =============================================================================
function auto_mode() {
    local exp_id="$1"
    local base_flags="$2"
    local release_flags="$3"

    local ww3_dir="${MODELS_ROOT}/${exp_id}/WW3"

    # Step 1: compile
    step1_compile "${exp_id}" "${base_flags}" "${release_flags}" || return 1

    # Step 2: Variant A — cpus=3, OMP=2, async ON
    local bench_a_id="${exp_id}_varA_n${VA_TASKS_PER_NODE}"
    local job_a
    job_a=$(step_bench \
        "${bench_a_id}" \
        "${ww3_dir}" \
        "${VA_TASKS_PER_NODE}" \
        "${VA_CPUS_PER_TASK}" \
        "${VA_OMP_THREADS}" \
        "false" \
        "phase4;omph;varA;cpus${VA_CPUS_PER_TASK};n${VA_TASKS_PER_NODE}")

    if [[ "${DRY_RUN}" == false && -n "${job_a}" ]]; then
        if ! wait_for_slurm_job "${job_a}" "${POLL_INTERVAL}"; then
            print_warning "Variant A job did not complete successfully — continuing to Variant B."
        fi
    fi

    # Step 3: Variant B — cpus=2, OMP=2, async OFF
    local bench_b_id="${exp_id}_varB_n${VB_TASKS_PER_NODE}"
    local job_b
    job_b=$(step_bench \
        "${bench_b_id}" \
        "${ww3_dir}" \
        "${VB_TASKS_PER_NODE}" \
        "${VB_CPUS_PER_TASK}" \
        "${VB_OMP_THREADS}" \
        "true" \
        "phase4;omph;varB;cpus${VB_CPUS_PER_TASK};n${VB_TASKS_PER_NODE};async_off")

    if [[ "${DRY_RUN}" == false && -n "${job_b}" ]]; then
        if ! wait_for_slurm_job "${job_b}" "${POLL_INTERVAL}"; then
            print_warning "Variant B job did not complete successfully."
        fi
    fi

    print_success "Phase 4 OMPH workflow complete."
    print_info "Results: column -t -s, ${BENCH_DIR}/benchmark_summary.csv"
}

# =============================================================================
# main
# =============================================================================
function main() {
    local exp_id="p4_omph"
    local step=""
    local do_auto=false
    local base_flags="${DEFAULT_BASE_FLAGS}"
    local release_flags="${DEFAULT_RELEASE_FLAGS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --exp-id)
                shift
                [[ -z "${1:-}" ]] && { print_error "--exp-id requires a value"; usage; }
                exp_id="$1"
                ;;
            --step)
                shift
                [[ -z "${1:-}" ]] && { print_error "--step requires a value (1-3)"; usage; }
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

    if [[ -z "${step}" && "${do_auto}" == false ]]; then
        print_error "Specify --step N (1-3) or --auto"
        usage
    fi

    DRY_RUN="${DRY_RUN:-false}"

    check_dependencies

    local ww3_dir="${MODELS_ROOT}/${exp_id}/WW3"

    print_header "WW3 Phase 4 — OMPH+OMPG Hybrid OpenMP  v${VERSION}"
    echo "  Experiment      : ${exp_id}"
    echo "  Base flags      : ${base_flags} -qopenmp"
    echo "  Release flags   : ${release_flags}"
    echo "  Variant A       : cpus=${VA_CPUS_PER_TASK} n=${VA_TASKS_PER_NODE} OMP=${VA_OMP_THREADS} async=ON"
    echo "  Variant B       : cpus=${VB_CPUS_PER_TASK} n=${VB_TASKS_PER_NODE} OMP=${VB_OMP_THREADS} async=OFF"
    echo "  Bench duration  : ${BENCH_DURATION}"
    echo "  Dry-run         : ${DRY_RUN}"

    if "${do_auto}"; then
        auto_mode "${exp_id}" "${base_flags}" "${release_flags}"
        return
    fi

    case "${step}" in
        1)
            step1_compile "${exp_id}" "${base_flags}" "${release_flags}"
            ;;
        2)
            # Variant A: cpus=3, async progress ON
            local bench_a_id="${exp_id}_varA_n${VA_TASKS_PER_NODE}"
            step_bench \
                "${bench_a_id}" \
                "${ww3_dir}" \
                "${VA_TASKS_PER_NODE}" \
                "${VA_CPUS_PER_TASK}" \
                "${VA_OMP_THREADS}" \
                "false" \
                "phase4;omph;varA;cpus${VA_CPUS_PER_TASK};n${VA_TASKS_PER_NODE}"
            ;;
        3)
            # Variant B: cpus=2, async progress OFF
            local bench_b_id="${exp_id}_varB_n${VB_TASKS_PER_NODE}"
            step_bench \
                "${bench_b_id}" \
                "${ww3_dir}" \
                "${VB_TASKS_PER_NODE}" \
                "${VB_CPUS_PER_TASK}" \
                "${VB_OMP_THREADS}" \
                "true" \
                "phase4;omph;varB;cpus${VB_CPUS_PER_TASK};n${VB_TASKS_PER_NODE};async_off"
            ;;
        *)
            print_error "Invalid step: ${step}. Must be 1, 2, or 3."
            usage
            ;;
    esac
}

main "$@"
