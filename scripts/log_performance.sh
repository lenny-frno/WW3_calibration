#!/bin/bash
# =============================================================================
# log_performance.sh — Collect and save performance metrics after ww3_shel
# =============================================================================
# Version: 2.3
#
# Called by run_exp.sh via sbatch after run_shel.job completes.
# Runs under --dependency=afterany so it always executes, even on failure.
#
# Arguments:
#   $1  EXP_DIR
#   $2  SHEL_JOB_ID
#   $3  NODES           (actual or estimated at submission time)
#   $4  NTASKS_PER_NODE
#   $5  SIM_DURATION
#   $6  META_DIR
#   $7  TOTAL_TASKS
#
# Changes vs v2.2:
#   - Status determined from timing_raw.txt WW3_STATUS (written by run_shel.job)
#     + sacct as authoritative second source — no more file sentinel
#   - CPU efficiency: sacct-based fallback when seff fails/returns garbage
#   - CSV schema frozen at v2.3 — header written with schema version tag
#   - seff retry: smarter "ready" detection, cap at 6 min total wait
#   - mem_per_cpu added to CSV and JSON
# =============================================================================

set -euo pipefail

EXP_DIR="${1}"
SHEL_JOB_ID="${2}"
NODES="${3}"
NTASKS_PER_NODE="${4}"
SIM_DURATION="${5}"
META_DIR="${6}"
TOTAL_TASKS="${7:-N/A}"
 
WORK_DIR="${EXP_DIR}/work"
LOGS_DIR="${EXP_DIR}/logs"
RUNTIME_DIR="${META_DIR}/runtime"
SETUP_DIR="${META_DIR}/setup"
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
# Timestamp for output files
STAMP=$(date +%Y%m%d_%H%M%S)
PERF_TXT="${RUNTIME_DIR}/performance_${STAMP}.txt"
PERF_JSON="${RUNTIME_DIR}/performance_${STAMP}.json"

echo "============================================================"
echo " WW3 Performance Logger  (framework v2.3)"
echo "============================================================"
echo "  Shel job ID  : ${SHEL_JOB_ID}"
echo "  Exp dir      : ${EXP_DIR}"
echo "  Total tasks  : ${TOTAL_TASKS}"
echo "  Start        : $(date --iso-8601=seconds)"
echo "============================================================"

# --------------------------------------------------------------------------
# Load timing written by run_shel.job into metadata/runtime/timing_raw.txt
# --------------------------------------------------------------------------
TIMING_RAW="${RUNTIME_DIR}/timing_raw.txt"
if [[ -f "${TIMING_RAW}" ]]; then
    source "${TIMING_RAW}"
    echo "  Timing loaded: ${TIMING_RAW}"
    echo "    elapsed     : ${ELAPSED_SECONDS:-N/A}s"
    echo "    throughput  : ${THROUGHPUT_DAYS_PER_HOUR:-N/A} sim-days/hour"
    echo "    WW3 status  : ${WW3_STATUS:-UNKNOWN}"
    CPUS_PER_TASK="${CPUS_PER_TASK:-1}"
    TOTAL_CORES="${TOTAL_CORES:-N/A}"
    MEM_PER_CPU="${MEM_PER_CPU:-N/A}"
else
    echo "  WARNING: timing_raw.txt not found at ${TIMING_RAW}"
    echo "           run_shel.job may have failed before writing timing"
    ELAPSED_SECONDS="N/A"
    ELAPSED_MINUTES="N/A"
    THROUGHPUT_DAYS_PER_HOUR="N/A"
    SIM_DAYS="N/A"
    RUN_START_ISO="N/A"
    RUN_END_ISO="N/A"
    CPUS_PER_TASK="N/A"
    TOTAL_CORES="N/A"
    MEM_PER_CPU="N/A"
    WW3_STATUS="UNKNOWN"
    WW3_EXIT_CODE="N/A"
fi

# --------------------------------------------------------------------------
# Determine authoritative run status
# Sources (priority order):
#   1. WW3_STATUS from timing_raw.txt  (set by run_shel.job from log analysis)
#   2. sacct job state                 (Slurm's view — catches OOM kills etc.)
#   3. Fallback: UNKNOWN
# --------------------------------------------------------------------------
echo "  Determining run status..."
 
# Get sacct state (available within ~60s of job end)
SACCT_STATE="N/A"
for attempt in 1 2 3 4; do
    SACCT_RAW=$(sacct -j "${SHEL_JOB_ID}" --format=State --noheader --parsable2 2>/dev/null \
                | head -1 | tr -d ' ' || echo "")
    if [[ -n "${SACCT_RAW}" && "${SACCT_RAW}" != "N/A" ]]; then
        SACCT_STATE="${SACCT_RAW}"
        echo "    sacct state (attempt ${attempt}): ${SACCT_STATE}"
        break
    fi
    echo "    sacct not ready (attempt ${attempt}/4) — waiting 20s..."
    sleep 20
done
 
# Reconcile: WW3 logic vs Slurm accounting
# Slurm kills (TIMEOUT, OUT_OF_MEMORY, NODE_FAIL) override WW3 log analysis
if echo "${SACCT_STATE}" | grep -qE "TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|CANCELLED"; then
    RUN_STATUS="${SACCT_STATE}"
elif [[ "${WW3_STATUS:-UNKNOWN}" == "SUCCESS" ]]; then
    RUN_STATUS="SUCCESS"
elif [[ "${WW3_STATUS:-UNKNOWN}" == "FATAL_ERROR" ]]; then
    RUN_STATUS="FATAL_ERROR"
elif [[ "${WW3_STATUS:-UNKNOWN}" == "CRASHED" ]]; then
    RUN_STATUS="CRASHED"
elif echo "${SACCT_STATE}" | grep -qE "COMPLETED"; then
    # Slurm says completed but WW3 log didn't confirm — treat as success
    RUN_STATUS="SUCCESS"
elif echo "${SACCT_STATE}" | grep -qE "FAILED"; then
    RUN_STATUS="FAILED"
else
    RUN_STATUS="${WW3_STATUS:-UNKNOWN}"
fi
 
echo "  Final status: ${RUN_STATUS}  (sacct=${SACCT_STATE}, ww3=${WW3_STATUS:-N/A})"

# --------------------------------------------------------------------------
# Count WW3 timesteps completed
# --------------------------------------------------------------------------
TIMESTEPS=$(grep -c "^  [0-9]" "${WORK_DIR}/log.ww3" 2>/dev/null || echo "N/A")

# --------------------------------------------------------------------------
# Collect seff metrics — with retry loop
# Falls back to sacct if seff keeps returning garbage after 6 min
# --------------------------------------------------------------------------
echo "  Collecting efficiency metrics..."

SEFF_OUTPUT=""
CPU_EFF="N/A"
MEM_EFF="N/A"
CPU_UTIL="N/A"
MEM_UTIL="N/A"
SLURM_WALL="N/A"
CPU_EFF_PCT="N/A"
MEM_EFF_PCT="N/A"

MAX_RETRIES=8
RETRY_WAIT=30

for attempt in $(seq 1 ${MAX_RETRIES}); do
    SEFF_OUTPUT=$(seff "${SHEL_JOB_ID}" 2>/dev/null || echo "seff_unavailable")

    if [[ "${SEFF_OUTPUT}" == "seff_unavailable" ]]; then
        echo "    seff not available on this cluster"
        break
    fi

    CPU_EFF_RAW=$(echo "${SEFF_OUTPUT}" | grep -i "CPU Efficiency" | awk -F: '{print $2}' | xargs || echo "")

    # Ready when we see a real denominator (not "00" or "16.00 B")
    if [[ -z "${CPU_EFF_RAW}" ]] || \
       echo "${CPU_EFF_RAW}" | grep -qE "of 00$|of 16\.00 B|of 0 core-seconds"; then
        echo "    Attempt ${attempt}/${MAX_RETRIES}: seff not ready (${CPU_EFF_RAW:-empty}) — waiting ${RETRY_WAIT}s..."
        sleep ${RETRY_WAIT}
    else
        echo "    Attempt ${attempt}/${MAX_RETRIES}: seff ready — ${CPU_EFF_RAW}"
        break
    fi
done

# Parse seff fields
CPU_EFF=$(echo  "${SEFF_OUTPUT}" | grep -i "CPU Efficiency"    | awk -F: '{print $2}' | xargs || echo "N/A")
MEM_EFF=$(echo  "${SEFF_OUTPUT}" | grep -i "Memory Efficiency" | awk -F: '{print $2}' | xargs || echo "N/A")
CPU_UTIL=$(echo "${SEFF_OUTPUT}" | grep -i "CPU Utilized"      | awk -F: '{print $2}' | xargs || echo "N/A")
MEM_UTIL=$(echo "${SEFF_OUTPUT}" | grep -i "Memory Utilized"   | awk -F: '{print $2}' | xargs || echo "N/A")
SLURM_WALL=$(echo "${SEFF_OUTPUT}" | grep -i "Job Wall-clock"  | sed 's/.*: *//' | xargs || echo "N/A")

# Extract clean percentage (e.g. "85.23% of 3-00:00:00" → "85.23%")
CPU_EFF_PCT=$(echo "${CPU_EFF}" | grep -oE '^[0-9]+\.[0-9]+%' || echo "N/A")
MEM_EFF_PCT=$(echo "${MEM_EFF}" | grep -oE '^[0-9]+\.[0-9]+%' || echo "N/A")

# Sacct fallback for CPU efficiency when seff gives nothing useful
if [[ "${CPU_EFF_PCT}" == "N/A" && "${SHEL_JOB_ID}" =~ ^[0-9]+$ ]]; then
    echo "  Trying sacct for CPU efficiency..."
    SACCT_CPU=$(sacct -j "${SHEL_JOB_ID}" \
        --format=CPUTimeRAW,ElapsedRaw,AllocCPUS --noheader --parsable2 2>/dev/null \
        | head -1 || echo "")
    if [[ -n "${SACCT_CPU}" ]]; then
        CPU_TIME_RAW=$(echo "${SACCT_CPU}" | awk -F'|' '{print $1}')
        ELAPSED_RAW=$(echo "${SACCT_CPU}"  | awk -F'|' '{print $2}')
        ALLOC_CPUS=$(echo "${SACCT_CPU}"   | awk -F'|' '{print $3}')
        if [[ "${ELAPSED_RAW}" -gt 0 && "${ALLOC_CPUS}" -gt 0 ]] 2>/dev/null; then
            AVAIL=$(( ELAPSED_RAW * ALLOC_CPUS ))
            CPU_EFF_PCT=$(echo "scale=2; ${CPU_TIME_RAW} * 100 / ${AVAIL}" | bc 2>/dev/null)%
            echo "    sacct CPU eff: ${CPU_EFF_PCT}"
        fi
    fi
fi

# --------------------------------------------------------------------------
# Load experiment identity from setup metadata
# --------------------------------------------------------------------------
EXP_NAME="$(basename "${EXP_DIR}")"
TAGS="N/A"
WW3_GIT="N/A"
SWITCH="N/A"
GRID="N/A"

# Source exp_config for tags and identity (read-only — config is locked)
if [[ -f "${EXP_DIR}/exp_config.sh" ]]; then
    source "${EXP_DIR}/exp_config.sh" || true
    TAGS="${TAGS:-N/A}"
    WW3_GIT="${WW3_GIT_COMMIT:-N/A}"
    SWITCH="${SWITCH:-N/A}"
    GRID="${GRID:-N/A}"
fi
# --------------------------------------------------------------------------
# Get cluster state at time of performance logging
# --------------------------------------------------------------------------
CLUSTER_STATE=$(sinfo -o "%20N %8c %10m %6t" 2>/dev/null || echo "sinfo unavailable")

# --------------------------------------------------------------------------
# Write human-readable performance report
# --------------------------------------------------------------------------
cat > "${PERF_TXT}" << EOF
============================================================
 WW3 Performance Report  (framework v2.3)
============================================================
Experiment       : ${EXP_NAME}
Tags             : ${TAGS}
Report generated : $(date --iso-8601=seconds)
Shel Job ID      : ${SHEL_JOB_ID}
Run status       : ${RUN_STATUS}
Sacct state      : ${SACCT_STATE}
WW3 log status   : ${WW3_STATUS:-N/A}
WW3 exit code    : ${WW3_EXIT_CODE:-N/A}
 
--- Model Configuration ---
WW3 git commit   : ${WW3_GIT}
Switch           : ${SWITCH}
Grid             : ${GRID}
 
--- Job Configuration ---
Nodes            : ${NODES}
Tasks per node   : ${NTASKS_PER_NODE}
Total MPI tasks  : ${TOTAL_TASKS}
CPUs per task    : ${CPUS_PER_TASK}
Mem per CPU (MB) : ${MEM_PER_CPU}
Total cores      : ${TOTAL_CORES}
Simulation       : ${SIM_DURATION}
 
--- Timing ---
Start time       : ${RUN_START_ISO:-N/A}
End time         : ${RUN_END_ISO:-N/A}
Wall-clock time  : ${ELAPSED_SECONDS:-N/A} seconds (${ELAPSED_MINUTES:-N/A} min)
Slurm wall time  : ${SLURM_WALL}
 
--- Throughput ---
Sim days         : ${SIM_DAYS:-N/A}
Throughput       : ${THROUGHPUT_DAYS_PER_HOUR:-N/A} sim-days/hour
WW3 timesteps    : ${TIMESTEPS}
 
--- Resource Efficiency ---
CPU Utilized     : ${CPU_UTIL}
CPU Efficiency   : ${CPU_EFF} → ${CPU_EFF_PCT}
Memory Utilized  : ${MEM_UTIL}
Memory Efficiency: ${MEM_EFF} → ${MEM_EFF_PCT}
 
--- Raw seff ---
${SEFF_OUTPUT}
 
--- Cluster State at Report Time ---
${CLUSTER_STATE}
 
--- log.ww3 tail (last 20 lines) ---
$(tail -20 "${WORK_DIR}/log.ww3" 2>/dev/null || echo "log.ww3 not found")
 
--- test001.ww3 tail (last 10 lines) ---
$(tail -10 "${WORK_DIR}/test001.ww3" 2>/dev/null || echo "test001.ww3 not found")
============================================================
EOF
 
echo "  Report saved  : ${PERF_TXT}"

# --------------------------------------------------------------------------
# Write structured JSON
# --------------------------------------------------------------------------
NOW=$(date +"%Y-%m-%dT%H:%M:%S")
cat > "${PERF_JSON}" << EOF
{
  "framework_version": "2.3",
  "experiment": {
    "name": "${EXP_NAME}",
    "tags": "${TAGS}",
    "run_status": "${RUN_STATUS}",
    "sacct_state": "${SACCT_STATE}",
    "ww3_log_status": "${WW3_STATUS:-N/A}",
    "ww3_exit_code": "${WW3_EXIT_CODE:-N/A}",
    "report_generated": "${NOW}"
  },
  "model": {
    "ww3_git_commit": "${WW3_GIT}",
    "switch": "${SWITCH}",
    "grid": "${GRID}"
  },
  "job": {
    "slurm_job_id": "${SHEL_JOB_ID}",
    "nodes": "${NODES}",
    "ntasks_per_node": "${NTASKS_PER_NODE}",
    "total_tasks": "${TOTAL_TASKS}",
    "cpus_per_task": "${CPUS_PER_TASK}",
    "mem_per_cpu_mb": "${MEM_PER_CPU}",
    "total_cores": "${TOTAL_CORES}",
    "sim_duration": "${SIM_DURATION}",
    "sim_days": "${SIM_DAYS:-N/A}"
  },
  "timing": {
    "start": "${RUN_START_ISO:-N/A}",
    "end": "${RUN_END_ISO:-N/A}",
    "elapsed_seconds": "${ELAPSED_SECONDS:-N/A}",
    "elapsed_minutes": "${ELAPSED_MINUTES:-N/A}",
    "slurm_wall_clock": "${SLURM_WALL}",
    "throughput_sim_days_per_hour": "${THROUGHPUT_DAYS_PER_HOUR:-N/A}",
    "ww3_timesteps": "${TIMESTEPS}"
  },
  "efficiency": {
    "cpu_utilized": "${CPU_UTIL}",
    "cpu_efficiency_full": "${CPU_EFF}",
    "cpu_efficiency_pct": "${CPU_EFF_PCT}",
    "memory_utilized": "${MEM_UTIL}",
    "memory_efficiency_full": "${MEM_EFF}",
    "memory_efficiency_pct": "${MEM_EFF_PCT}"
  }
}
EOF
 
echo "  JSON saved    : ${PERF_JSON}"

# --------------------------------------------------------------------------
# Append to master benchmark_summary.csv
# Schema v2.3 — fixed column order, schema version in header comment
# --------------------------------------------------------------------------
MASTER_CSV="${BENCH_DIR}/benchmark_summary.csv"
 
# v2.3 schema — DO NOT change column order without bumping schema version
CSV_HEADER="# schema=v2.3
exp_name,tags,job_id,status,sacct_state,nodes,tasks_per_node,total_tasks,cpus_per_task,mem_per_cpu_mb,total_cores,sim_duration,elapsed_seconds,elapsed_minutes,throughput_days_per_hour,cpu_efficiency_pct,mem_efficiency_pct,switch,grid,ww3_commit,date"
 
if [[ ! -f "${MASTER_CSV}" ]]; then
    echo "${CSV_HEADER}" > "${MASTER_CSV}"
    echo "  Created CSV   : ${MASTER_CSV}"
else
    # Check if schema version matches — warn if stale
    EXISTING_SCHEMA=$(head -1 "${MASTER_CSV}" | grep -o 'schema=v[0-9.]*' || echo "schema=unknown")
    if [[ "${EXISTING_SCHEMA}" != "schema=v2.3" ]]; then
        echo "  WARNING: CSV schema mismatch (${EXISTING_SCHEMA} vs schema=v2.3)"
        echo "           Old CSV archived to ${MASTER_CSV}.pre-v2.3"
        cp "${MASTER_CSV}" "${MASTER_CSV}.pre-v2.3"
        echo "${CSV_HEADER}" > "${MASTER_CSV}"
    fi
fi
 
# Sanitise fields that might contain commas
safe() { echo "${1//,/;}"; }
 
printf '%s\n' \
    "$(safe "${EXP_NAME}"),$(safe "${TAGS}"),${SHEL_JOB_ID},${RUN_STATUS},${SACCT_STATE},\
${NODES},${NTASKS_PER_NODE},${TOTAL_TASKS},${CPUS_PER_TASK},${MEM_PER_CPU},${TOTAL_CORES},${SIM_DURATION},\
${ELAPSED_SECONDS:-N/A},${ELAPSED_MINUTES:-N/A},${THROUGHPUT_DAYS_PER_HOUR:-N/A},\
${CPU_EFF_PCT},${MEM_EFF_PCT},\
$(safe "${SWITCH}"),$(safe "${GRID}"),${WW3_GIT},$(date --iso-8601=seconds)" \
    >> "${MASTER_CSV}"
 
echo "  CSV updated   : ${MASTER_CSV}"

# --------------------------------------------------------------------------
# Print summary
# --------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " PERFORMANCE SUMMARY — ${EXP_NAME}"
echo "============================================================"
echo "  Status       : ${RUN_STATUS}  (Slurm: ${SACCT_STATE})"
echo "  Layout       : ${NODES} nodes × ${NTASKS_PER_NODE} tasks × ${CPUS_PER_TASK} CPUs"
echo "  Mem/CPU      : ${MEM_PER_CPU} MB"
echo "  Total cores  : ${TOTAL_CORES}"
echo "  Elapsed      : ${ELAPSED_SECONDS:-N/A}s (${ELAPSED_MINUTES:-N/A} min)"
echo "  Throughput   : ${THROUGHPUT_DAYS_PER_HOUR:-N/A} sim-days/hour"
echo "  CPU eff      : ${CPU_EFF_PCT}"
echo "  Mem eff      : ${MEM_EFF_PCT}"
echo "  Switch       : ${SWITCH}"
echo "  Grid         : ${GRID}"
echo "============================================================"
echo ""
echo " Compare all experiments:"
echo "   column -t -s, ${MASTER_CSV}"
