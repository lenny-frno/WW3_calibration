#!/bin/bash
# =============================================================================
# run_exp.sh — Submit and monitor a WW3 benchmark experiment
# =============================================================================
# Version: 2.1
#
# Usage: ./run_exp.sh [OPTIONS]
#   -e  Experiment name        (required — must match a setup.sh run)
#   -N  Number of nodes        (default: 12)
#   -n  Tasks per node         (default: 56)
#   --ntasks <N>               Total tasks — if used alone, Slurm picks layout
#                              If used WITH -N, forces exact node count too
#   --cpus-per-task
#   --mem-per-cpu <MB>           Memory per CPU in MB (default: cluster default)
#                                Use 0 for --mem=0 (all memory on node)
#   -t  Wall time              (default: 01:00:00)
#   -d  Simulation duration    (default: 1h — options: 1h, 10h, 1d, 3d, 7d)
#   -s  Skip preprocessing     (flag, no argument)
#   -p  Only postprocessing      (flag — implies -s)
#   --post                       Also run postprocessing after shel
#   --dry-run                  Print sbatch commands without submitting
#
# Task layout logic:
#   --ntasks alone        → Slurm auto-picks nodes (most flexible)
#   -N + -n               → explicit nodes × tasks/node (predictable, Fahrenheit safe)
#   --ntasks + -N         → fixed node count + fixed total tasks (power-user mode)
#   All three             → --ntasks + -N take precedence over -n
#
# Memory control:
#   --mem-per-cpu 1200   → 1200 MB per CPU (1200 × 56 ≈ 67 GB/node)
#   --mem-per-cpu 0      → --mem=0 (all available memory, recommended on homogeneous clusters)
#   (omit)               → cluster default (usually fine, but not predictable)
#
# Examples:
#   ./run_exp.sh -e exp_v1 -N 12 -n 56 -t 01:00:00 -d 1d
#   ./run_exp.sh -e exp_v1 --ntasks 600 -d 1d
#   ./run_exp.sh -e exp_v1 --ntasks 672 -N 12 -d 1d   # 12 nodes, 56 tasks each
#   ./run_exp.sh -e exp_v1 --ntasks 600 -d 1d --dry-run
# =============================================================================

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
EXP_NAME=""
NODES=""
NTASKS_PER_NODE=56
NTASKS=""
CPUS_PER_TASK=1
MEM_PER_CPU=""
WALL_TIME="01:00:00"
SIM_DURATION="1h"
SKIP_PREP=false
ONLY_POST=false
RUN_POST=false
DRY_RUN=false

# --------------------------------------------------------------------------
# Pre-process long options
# --------------------------------------------------------------------------
ARGS=()
i=1
while [[ $i -le $# ]]; do
    arg="${!i}"
    case "${arg}" in
        --dry-run)
            DRY_RUN=true ;;
        --ntasks)
            i=$(( i + 1 )); NTASKS="${!i}" ;;
        --ntasks=*)
            NTASKS="${arg#*=}" ;;
        --cpus-per-task)
            i=$(( i + 1 )); CPUS_PER_TASK="${!i}" ;;
        --cpus-per-task=*)
            CPUS_PER_TASK="${arg#*=}" ;;
        --mem-per-cpu)
            i=$(( i + 1 )); MEM_PER_CPU="${!i}" ;;
        --mem-per-cpu=*)
            MEM_PER_CPU="${arg#*=}" ;;
        --post)
            RUN_POST=true ;;
        *)
            ARGS+=("${arg}") ;;
    esac
    i=$(( i + 1 ))
done
set -- "${ARGS[@]:-}"

while getopts "e:N:n:t:d:sp" opt; do
    case $opt in
        e) EXP_NAME="$OPTARG" ;;
        N) NODES="$OPTARG" ;;
        n) NTASKS_PER_NODE="$OPTARG" ;;
        t) WALL_TIME="$OPTARG" ;;
        d) SIM_DURATION="$OPTARG" ;;
        s) SKIP_PREP=true ;;
	p) ONLY_POST=true ;;
	*) echo "Unknown option: -$opt"; exit 1 ;;
    esac
done

# --------------------------------------------------------------------------
# Validate experiment name
# --------------------------------------------------------------------------
if [[ -z "${EXP_NAME}" ]]; then
    echo "ERROR: Experiment name required. Use -e <exp_name>"
    echo "       Available experiments:"
    ls "${BENCH_DIR}/experiments/" 2>/dev/null | sed 's/^/         /' \
        || echo "         (none found — run setup.sh first)"
    exit 1
fi

# --------------------------------------------------------------------------
# Load experiment config (single source of truth)
# --------------------------------------------------------------------------
CONFIG_FILE="${BENCH_DIR}/experiments/${EXP_NAME}/exp_config.sh"
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Experiment config not found: ${CONFIG_FILE}"
    echo "       Did you run: ./setup.sh -e ${EXP_NAME}"
    exit 1
fi
source "${CONFIG_FILE}"

# Validate metadata structure created by setup.sh v2.0
RUNTIME_DIR="${META_DIR}/runtime"
SETUP_DIR="${META_DIR}/setup"
if [[ ! -d "${RUNTIME_DIR}" ]]; then
    echo "ERROR: metadata/runtime/ not found in ${META_DIR}"
    echo "       This experiment was created with an older setup.sh — re-run setup.sh"
    exit 1
fi

# --------------------------------------------------------------------------
# Resolve task layout
# Three modes:
#   1. --ntasks + -N  → nodes=N, ntasks=NTASKS (Slurm distributes tasks across N nodes)
#   2. --ntasks alone → Slurm picks nodes freely
#   3. -N + -n        → classic explicit layout
# --------------------------------------------------------------------------
if [[ -n "${NTASKS}" && -n "${NODES}" ]]; then
    # Mode 1: user wants exact node count AND exact total tasks
    # Slurm will pack NTASKS across exactly NODES nodes
    TASK_ARGS="--nodes=${NODES} --ntasks=${NTASKS} --cpus-per-task=${CPUS_PER_TASK} --mem=0"
    TOTAL_TASKS="${NTASKS}"
    LAYOUT_DESC="${NODES} nodes, ${NTASKS} MPI × ${CPUS_PER_TASK} threads = $(( TOTAL_TASKS * CPUS_PER_TASK )) cores"
    NODES_FOR_LOG="${NODES}"
 
elif [[ -n "${NTASKS}" ]]; then
    # Mode 2: total tasks only — Slurm picks node layout freely
    TASK_ARGS="--ntasks=${NTASKS} --cpus-per-task=${CPUS_PER_TASK}"
    TOTAL_TASKS="${NTASKS}"
    # Estimate nodes for logging (ceiling division)
    NODES_FOR_LOG=$(( (NTASKS + NTASKS_PER_NODE - 1) / NTASKS_PER_NODE ))
    LAYOUT_DESC="${NTASKS} MPI × ${CPUS_PER_TASK} threads = $(( TOTAL_TASKS * CPUS_PER_TASK )) cores (~${NODES_FOR_LOG} nodes)"
 
else
    # Mode 3: explicit -N nodes × -n tasks/node
    NODES="${NODES:-12}"   # apply default only here, avoids conflicts with Mode 1/2
    TASK_ARGS="--nodes=${NODES} --ntasks-per-node=${NTASKS_PER_NODE} --cpus-per-task=${CPUS_PER_TASK} --mem=0"
    TOTAL_TASKS=$(( NODES * NTASKS_PER_NODE ))
    NODES_FOR_LOG="${NODES}"
    LAYOUT_DESC="${NODES} nodes × ${NTASKS_PER_NODE} MPI × ${CPUS_PER_TASK} threads = $(( TOTAL_TASKS * CPUS_PER_TASK )) cores"
fi
# --------------------------------------------------------------------------
# Resolve memory argument
# --mem-per-cpu 0  → use --mem=0 (all node memory)
# --mem-per-cpu N  → use --mem-per-cpu=N
# (unset)          → no memory argument (cluster default)
# Note: --mem=0 and --mem-per-cpu are mutually exclusive in Slurm
# If TASK_ARGS already contains --mem=0 (from -N + -n mode), that takes
# precedence over --mem-per-cpu. Override by setting --mem-per-cpu explicitly.
# --------------------------------------------------------------------------
MEM_ARG=""
MEM_DESC="cluster default"
if [[ -n "${MEM_PER_CPU}" ]]; then
    if [[ "${MEM_PER_CPU}" == "0" ]]; then
        # Replace any existing --mem=0 in TASK_ARGS to avoid duplication
        TASK_ARGS="${TASK_ARGS/--mem=0/}"
        MEM_ARG="--mem=0"
        MEM_DESC="all node memory (--mem=0)"
    else
        # Remove --mem=0 from TASK_ARGS if present (can't mix)
        TASK_ARGS="${TASK_ARGS/--mem=0/}"
        MEM_ARG="--mem-per-cpu=${MEM_PER_CPU}"
        MEM_DESC="${MEM_PER_CPU} MB/CPU"
    fi
fi
 
#---------------------------------------------------------------------------
# Resolve only post case
#---------------------------------------------------------------------------
if [[ "${ONLY_POST}" == true ]]; then
	SKIP_PREP=true
fi
 
# --------------------------------------------------------------------------
# Print header
# --------------------------------------------------------------------------
echo "============================================================"
echo " WW3 Experiment Runner  (framework v2.2)"
echo "============================================================"
echo "  Experiment  : ${EXP_NAME}"
echo "  Tags        : ${TAGS:-none}"
echo "  Layout      : ${LAYOUT_DESC}"
echo "  Total tasks : ${TOTAL_TASKS}"
echo "  CPUs/task   : ${CPUS_PER_TASK}"
echo "  Memory      : ${MEM_DESC}"
echo "  Wall time   : ${WALL_TIME}"
echo "  Sim duration: ${SIM_DURATION}"
echo "  Skip prep   : ${SKIP_PREP}"
echo "  Run post    : ${RUN_POST}"
echo "  Only post   : ${ONLY_POST}"
echo "  Dry-run     : ${DRY_RUN}"
echo "  Submitted   : $(date --iso-8601=seconds)"
echo "============================================================"
 
# --------------------------------------------------------------------------
# sbatch wrapper — prints command in dry-run, submits otherwise
# Returns job ID (real or placeholder)
# --------------------------------------------------------------------------
submit_job() {
    local label="$1"; shift
    if [[ "${DRY_RUN}" == true ]]; then
        echo "  [DRY-RUN] sbatch $*"
        echo "99999"   # placeholder job ID
    else
        sbatch --parsable "$@"
    fi
}

# --------------------------------------------------------------------------
# Save run configuration to metadata/runtime
# --------------------------------------------------------------------------
RUN_CONFIG="${RUNTIME_DIR}/run_config_$(date +%Y%m%d_%H%M%S).txt"
if [[ "${DRY_RUN}" == false ]]; then
    cat > "${RUN_CONFIG}" << EOF
============================================================
 Run Configuration  (framework v2.2)
============================================================
Submitted        : $(date --iso-8601=seconds)
Experiment       : ${EXP_NAME}
Tags             : ${TAGS:-none}
Task layout      : ${LAYOUT_DESC}
 
--- Resources ---
Ntasks arg       : ${NTASKS:-not set}
Nodes arg        : ${NODES:-not set}
Tasks/node arg   : ${NTASKS_PER_NODE}
CPUs per task    : ${CPUS_PER_TASK}
Memory           : ${MEM_DESC}
Total MPI tasks  : ${TOTAL_TASKS}
 
--- Run parameters ---
Wall time        : ${WALL_TIME}
Sim duration     : ${SIM_DURATION}
Skip prep        : ${SKIP_PREP}
Run post         : ${RUN_POST}
 
--- Cluster state at submission ---
$(sinfo -o "%20N %8c %10m %6t" 2>/dev/null || echo "sinfo unavailable")
 
--- Queue (your jobs) at submission ---
$(squeue -u "$(whoami)" 2>/dev/null || echo "squeue unavailable")
EOF
    echo "  Run config saved: ${RUN_CONFIG}"
fi

# --------------------------------------------------------------------------
# Step 1 — Preprocessing (sbatch with dependency chain)
# --------------------------------------------------------------------------
PREP_JOB_ID="skipped"
if [[ "${SKIP_PREP}" == false ]]; then
    echo ""
    echo "[1/4] Submitting preprocessing job..."
 
    PREP_JOB_ID=$(submit_job "prep" \
        --account=eu-interchange \
        --job-name="WW3-prep-${EXP_NAME}" \
        --time=01:00:00 \
        --nodes=1 \
        --ntasks-per-node=1 \
        --output="${LOGS_DIR}/prep.%j.LOG" \
        --error="${LOGS_DIR}/prep.%j.ERR" \
        "${BENCH_DIR}/prep.job" \
        "${EXP_DIR}" "${WORK_DIR}" "${META_DIR}")
 
    echo "      Prep job submitted: ${PREP_JOB_ID}"
    PREP_DEP="--dependency=afterok:${PREP_JOB_ID}"
else
    echo "[1/4] Skipping preprocessing"
    PREP_DEP=""
fi

# --------------------------------------------------------------------------
# Step 2 — ww3_shel MPI job
# --------------------------------------------------------------------------
SHEL_JOB_ID="skipped"
echo ""
if [[ "${ONLY_POST}" == false ]]; then
echo "[2/4] Submitting ww3_shel job..."
 
SHEL_JOB_ID=$(submit_job "shel" \
    --account=eu-interchange \
    --job-name="WW3-shel-${EXP_NAME}" \
    --time="${WALL_TIME}" \
    ${TASK_ARGS} \
    ${MEM_ARG} \
    --output="${LOGS_DIR}/shel.%j.LOG" \
    --error="${LOGS_DIR}/shel.%j.ERR" \
    ${PREP_DEP} \
    "${BENCH_DIR}/run_shel.job" \
    "${EXP_DIR}" "${WORK_DIR}" "${SIM_DURATION}" "${META_DIR}" "${CPUS_PER_TASK}")
 
echo "      Shel job: ${SHEL_JOB_ID}"
else
	echo "[2/4] Skipping shel, only postprocessing"
fi
#---------------------------------------------------------------------------
# Step 3 — Performance logging (runs after shel, even on failure)
# --------------------------------------------------------------------------
LOG_JOB_ID="skipped"
echo ""
if [[ "${ONLY_POST}" == false ]]; then
echo "[3/4] Submitting performance logging job..."
 
LOG_JOB_ID=$(submit_job "perf" \
    --account=eu-interchange \
    --job-name="WW3-perf-${EXP_NAME}" \
    --time=00:15:00 \
    --nodes=1 \
    --ntasks-per-node=1 \
    --output="${LOGS_DIR}/perf.%j.LOG" \
    --error="${LOGS_DIR}/perf.%j.ERR" \
    --dependency=afterany:${SHEL_JOB_ID} \
    "${BENCH_DIR}/log_performance.sh" \
    "${EXP_DIR}" "${SHEL_JOB_ID}" \
    "${NODES_FOR_LOG}" "${NTASKS_PER_NODE}" \
    "${SIM_DURATION}" "${META_DIR}" "${TOTAL_TASKS}")
 
echo "      Perf job: ${LOG_JOB_ID}"
else
	echo "[3/4] Skipping log perf, only postprocessing"
fi
# --------------------------------------------------------------------------
# Step 4 — Postprocessing (optional, after shel success)
# --------------------------------------------------------------------------
POST_JOB_ID="skipped"
if [[ "${RUN_POST}" == true || "${ONLY_POST}" == true ]]; then
    echo ""
    echo "[4/4] Submitting postprocessing job..."

    if [[ "${ONLY_POST}" == true ]]; then
        POST_DEP=""
    else
        POST_DEP="--dependency=afterok:${SHEL_JOB_ID}"
    fi

    POST_JOB_ID=$(submit_job "post" \
        --account=eu-interchange \
        --job-name="WW3-post-${EXP_NAME}" \
        --time=02:00:00 \
        --nodes=1 \
        --ntasks-per-node=1 \
	--mem=0\
        --output="${LOGS_DIR}/post.%j.LOG" \
        --error="${LOGS_DIR}/post.%j.ERR" \
        ${POST_DEP} \
        "${BENCH_DIR}/post.job" \
        "${EXP_DIR}" "${WORK_DIR}" "${META_DIR}")

    echo "      Post job: ${POST_JOB_ID}"
else
    echo "[4/4] Postprocessing skipped (use --post to enable)"
fi

# --------------------------------------------------------------------------
# Save job IDs to metadata/runtime/
# --------------------------------------------------------------------------
if [[ "${DRY_RUN}" == false ]]; then
    cat > "${RUNTIME_DIR}/last_jobids.txt" << EOF
shel_job_id=${SHEL_JOB_ID}
perf_job_id=${LOG_JOB_ID}
prep_job_id=${PREP_JOB_ID}
post_job_id=${POST_JOB_ID}
submitted=$(date --iso-8601=seconds)
layout=${LAYOUT_DESC}
total_tasks=${TOTAL_TASKS}
cpus_per_task=${CPUS_PER_TASK}
mem_per_cpu=${MEM_PER_CPU:-default}
sim_duration=${SIM_DURATION}
EOF
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================================"
[[ "${DRY_RUN}" == true ]] && echo " *** DRY-RUN — no jobs submitted ***"
echo " Jobs submitted: ${EXP_NAME}"
echo "============================================================"
[[ "${SKIP_PREP}" == false ]]    && echo "  Prep job  : ${PREP_JOB_ID}"
echo "  Shel job  : ${SHEL_JOB_ID}"
echo "  Perf job  : ${LOG_JOB_ID}"
[[ "${RUN_POST}" == true || "${ONLY_POST}" == true ]] && echo "  Post job  : ${POST_JOB_ID}"
echo ""
echo " Monitor:"
echo "   squeue -u \$(whoami)"
echo "   tail -f ${LOGS_DIR}/shel.${SHEL_JOB_ID}.LOG"
echo "   tail -f ${WORK_DIR}/log.ww3"
echo ""
echo " Results:"
echo "   cat ${RUNTIME_DIR}/performance_*.txt"
echo "   column -t -s, ${BENCH_DIR}/benchmark_summary.csv"
echo "   ./check_exp.sh -e ${EXP_NAME}"
echo "============================================================"
