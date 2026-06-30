#!/usr/bin/env bash
# =============================================================================
# run_calibration.sh — Dispatch a WW3 config across multiple named storm periods
# =============================================================================
# Version: 1.4
#
# For each specified period (× each parameter sweep combo):
#   1. Calls setup.sh -c <config_dir> -P <period> -e <exp_name> [-w] [-X ...]
#   2. Optionally patches env.sh for OMPH binary (--omph)
#   3. Calls run_exp.sh -e <exp_name> [...forwarded options...]
#   4. Appends a row to periods/calibration_log.csv
#   5. If -t is not forwarded, auto-sets -t from PERIOD_DURATION_DAYS
#      using a 5:1 ratio (5 sim-days -> 1 wall-clock hour)
#
# Usage:
#   run_calibration.sh -c <config_dir> -P <p1>[,<p2>,...] [options] [run_exp options]
#   run_calibration.sh -c <config_dir> --all-periods [options] [run_exp options]
#
# This script's own options:
#   -c  <config_dir>               Config/namelist directory (required)
#   -D  <data_root>
#   -P  <p1>[,<p2>,...]            Comma-separated period names (or --all-periods)
#   -e  <prefix>                   Experiment name prefix (default: config dir basename)
#                                  Exp dirs named:  <prefix>[__SWEEP_TAG]__<period>
#   -w  <ww3_dir>                  WW3 binary root dir; forwarded to setup.sh
#   -g  <grid_name>                Grid name; forwarded to setup.sh as -g
#   -X  KEY=VALUE                  Namelist override; forwarded to setup.sh (repeatable)
#   --sweep KEY=v1,v2,...          Sweep a parameter over a list of values (repeatable).
#                                  Generates one experiment per value (x per period).
#                                  Multiple --sweep flags produce a Cartesian product.
#                                  Auto-appended to exp name as __KEY_VTAG.
#   --omph                         After each setup, inject WW3_OMP_THREADS=2 and
#                                  I_MPI_ASYNC_PROGRESS=0 into metadata/setup/env.sh.
#                                  Required when using the omph (MPI+OMP) binary.
#   --all-periods                  Use every .period file found in periods/
#   --dry-run                      No submissions or directories created
#   -h|--help                      Show this help
#
# All other flags are forwarded verbatim to run_exp.sh:
#   -N, -n, --ntasks, --cpus-per-task, --mem-per-cpu, -t, --post, -s, -p, etc.
#   If -t is not provided, run_calibration auto-computes it per period.
#
# Examples:
#   # Simple: one config, two periods, fixed params
#   ./run_calibration.sh -c configs/with_sic -P storm_eunice_2022,storm_xaver_2013 \
#       -w /path/to/WW3 -X BETAMAX=1.43 -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \
#       -N 16 -n 60 -t 00:30:00 --post
#
#   # BETAMAX sweep x all periods, omph binary:
#   ./run_calibration.sh -c configs/with_sic --all-periods \
#       -w "${OMPH_WW3}" --omph \
#       --sweep BETAMAX=1.33,1.43,1.50,1.55,1.65,1.75 \
#       -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \
#       -e with_sic__w1_99_w2_00__omph \
#       -N 16 -n 60 --cpus-per-task 2 --post
#
#   # 2-D sweep (Cartesian: 3 BM x 3 W1 = 9 combos x 2 periods = 18 experiments):
#   ./run_calibration.sh -c configs/with_sic -P storm_eunice_2022,storm_xaver_2013 \
#       --sweep BETAMAX=1.43,1.55,1.65 --sweep MISC_WCOR1=99,15.0,25.0 \
#       -X MISC_WCOR2=0.0 -w "${OMPH_WW3}" --omph -N 16 -n 60 --post
# =============================================================================

SCRIPT_NAME=$(basename "$0")
VERSION="1.4.1"
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERIODS_DIR="${BENCH_DIR}/periods"
CAL_LOG="${PERIODS_DIR}/calibration_log.csv"
CAL_LOG_HEADER="timestamp,config,period,exp_name,start_date,end_date,nodes,ntasks,shel_job_id,status"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BOLD="" NC=""
fi

function usage() {
    cat <<EOM

${BOLD}run_calibration.sh${NC} — Dispatch a WW3 config across multiple periods  (v${VERSION})

${BOLD}Usage:${NC}
  ${SCRIPT_NAME} -c <config_dir> -P <period1>[,<period2>,...] [run_exp options]
  ${SCRIPT_NAME} -c <config_dir> --all-periods [run_exp options]

${BOLD}Required:${NC}
  -c  <config_dir>            Config/namelist directory  (e.g. configs/with_sic)
  -P  <p1>[,<p2>,...]         Comma-separated period names  OR  use --all-periods

${BOLD}Optional:${NC}
  -e  <prefix>                Experiment name prefix (default: config dirname)
                              Experiment dirs: <prefix>[__SWEEP_TAG]__<period_name>
  -w  <ww3_dir>               WW3 binary root dir (forwarded to setup.sh as -w)
    -g  <grid_name>             Grid name (forwarded to setup.sh as -g).
                                                            If omitted, setup.sh default is used (CARRA2).
  -X  KEY=VALUE               Namelist override — passed to setup.sh (repeatable)
  --sweep KEY=v1,v2,...       Sweep a parameter over values (repeatable).
                              Multiple --sweep flags produce a Cartesian product.
                              Auto-appends __KEY_VTAG to the exp name per combo.
  --omph                      Inject WW3_OMP_THREADS=2 + I_MPI_ASYNC_PROGRESS=0
                              into env.sh after setup (required for omph binary)
  --rerun                     Skip setup.sh; clean partial outputs and resubmit.
                              Requires the experiment directory to already exist.
                              Deletes output NetCDFs and ww3_shel outputs from
                              work/ (out_grd.ww3, test001.ww3, log.ww3); keeps
                              preprocessing outputs (mod_def.ww3, wind.ww3,
                              ice.ww3) so you can add -s to skip prep.
                              If --omph is set, the patch is checked and applied
                              only if not already present.
  --all-periods               Run every .period file found in ${PERIODS_DIR}/
  --dry-run                   No submissions or directories created
  -h|--help                   Show this help

${BOLD}Forwarded to run_exp.sh:${NC}
  -N <nodes>  -n <tasks/node>  --ntasks <N>  --cpus-per-task <N>
  --mem-per-cpu <MB>  -t <wall_time>  --post  -s  -p
    If -t is omitted, this script auto-sets wall time from PERIOD_DURATION_DAYS
    using: wall_hours = sim_days / 5

${BOLD}Examples:${NC}
  # Fixed params, two periods:
  ${SCRIPT_NAME} -c configs/with_sic -P storm_eunice_2022,storm_xaver_2013 \\
      -w /path/to/WW3 -X BETAMAX=1.43 -X MISC_WCOR1=99 -N 16 -n 60 --post

  # Sweep BETAMAX x all periods, omph binary:
  ${SCRIPT_NAME} -c configs/with_sic --all-periods \\
      -w "\${OMPH_WW3}" --omph \\
      --sweep BETAMAX=1.33,1.43,1.50,1.55,1.65,1.75 \\
      -X MISC_WCOR1=99 -X MISC_WCOR2=0.0 \\
      -e with_sic__w1_99_w2_00__omph -N 16 -n 60 --cpus-per-task 2 --post

  # 2-D sweep (Cartesian: 3 BM x 3 W1 = 9 combos x 2 periods = 18 experiments):
  ${SCRIPT_NAME} -c configs/with_sic -P storm_eunice_2022,storm_xaver_2013 \\
      --sweep BETAMAX=1.43,1.55,1.65 --sweep MISC_WCOR1=99,15.0,25.0 \\
      -X MISC_WCOR2=0.0 -w "\${OMPH_WW3}" --omph -N 16 -n 60 --post

${BOLD}Period management:${NC}
  Register periods first:
    ./manage_periods.sh add storm_eunice_2022 --start 20220218 --end 20220221 --desc "Storm Eunice"
  View log:
    ./manage_periods.sh log --config with_sic

EOM
    exit 1
}

# Build the Cartesian product of all --sweep dimensions.
# sweep_keys and sweep_values must be declared in the calling scope.
# Populates the caller's combos array (passed by name).
# Each element is a space-separated list of "KEY=VALUE" pairs.
function build_combos() {
    local -n _result_combos=$1
    _result_combos=("")   # start with one empty combo
    local ki
    for ki in "${!sweep_keys[@]}"; do
        local key="${sweep_keys[$ki]}"
        local -a vals
        IFS=',' read -r -a vals <<< "${sweep_values[$ki]}"
        local new_combos=()
        local combo v
        for combo in "${_result_combos[@]}"; do
            for v in "${vals[@]}"; do
                v="${v// /}"  # strip stray spaces
                new_combos+=("${combo:+${combo} }${key}=${v}")
            done
        done
        _result_combos=("${new_combos[@]}")
    done
}

function ensure_log() {
    mkdir -p "${PERIODS_DIR}"
    if [[ ! -f "${CAL_LOG}" ]]; then
        echo "${CAL_LOG_HEADER}" > "${CAL_LOG}"
    fi
}

function append_log() {
    local config="$1" period="$2" exp_name="$3"
    local start_date="$4" end_date="$5"
    local nodes="$6" ntasks="$7"
    local shel_job_id="$8" status="$9"
    local ts
    ts=$(date --iso-8601=seconds)
    echo "${ts},${config},${period},${exp_name},${start_date},${end_date},${nodes},${ntasks},${shel_job_id},${status}" \
        >> "${CAL_LOG}"
}

# Convert simulation days to Slurm wall time using a fixed ratio:
#   5 simulation days : 1 wall-clock hour
# Wall time (seconds) = ceil(days * 3600 / 5) = ceil(days * 720)
function days_to_wall_hms() {
    local days="$1"
    local total_seconds

    total_seconds=$(awk -v d="${days}" 'BEGIN {
        s = d * 900
        if (s < 60) s = 60
        if (s == int(s)) printf "%d", s
        else printf "%d", int(s) + 1
    }')

    local hh=$(( total_seconds / 3600 ))
    local mm=$(( (total_seconds % 3600) / 60 ))
    local ss=$(( total_seconds % 60 ))
    printf "%02d:%02d:%02d" "${hh}" "${mm}" "${ss}"
}

function main() {
    local config_dir=""
    local data_dir=""
    local periods_arg=""
    local exp_prefix=""
    local ww3_dir=""
    local grid_name=""
    local all_periods=false
    local dry_run=false
    local omph=false
    local rerun=false
    local use_groups=false
    local fwd_args=()
    local extra_x_args=()
    local -a sweep_keys=()
    local -a sweep_values=()

    # Manual argument parsing — collect our flags, forward everything else
    local i=0
    local args=("$@")

    while [[ ${i} -lt ${#args[@]} ]]; do
        local arg="${args[${i}]}"
        case "${arg}" in
            -c)
                i=$(( i + 1 )); config_dir="${args[${i}]}" ;;
            -c*)
                config_dir="${arg#-c}" ;;
	    -D)
                i=$(( i + 1 )); data_dir="${args[${i}]}" ;;
            -D*)
                data_dir="${arg#-D}" ;;
            -P)
                i=$(( i + 1 )); periods_arg="${args[${i}]}" ;;
            -P*)
                periods_arg="${arg#-P}" ;;
            -e)
                i=$(( i + 1 )); exp_prefix="${args[${i}]}" ;;
            -e*)
                exp_prefix="${arg#-e}" ;;
            -w)
                i=$(( i + 1 )); ww3_dir="${args[${i}]}" ;;
            -w*)
                ww3_dir="${arg#-w}" ;;
            -g)
                i=$(( i + 1 )); grid_name="${args[${i}]}" ;;
            -g*)
                grid_name="${arg#-g}" ;;
            -X)
                i=$(( i + 1 )); extra_x_args+=(-X "${args[${i}]}") ;;
            -X*)
                extra_x_args+=(-X "${arg#-X}") ;;
            --sweep)
                i=$(( i + 1 ))
                local _sw="${args[${i}]}"
                local _sk="${_sw%%=*}" _sv="${_sw#*=}"
                if [[ -z "${_sk}" || "${_sk}" == "${_sw}" ]]; then
                    echo -e "${RED}Error:${NC} --sweep requires KEY=v1,v2,... format." >&2; usage
                fi
                sweep_keys+=("${_sk}")
                sweep_values+=("${_sv}") ;;
            --omph)
                omph=true ;;
            --rerun)
                rerun=true ;;
            --all-periods)
                all_periods=true ;;
            --use-groups)
                use_groups=true ;;
            --dry-run)
                dry_run=true
                fwd_args+=("--dry-run") ;;
            -h|--help)
                usage ;;
            # Forward everything else to run_exp.sh
            *)
                fwd_args+=("${arg}") ;;
        esac
        i=$(( i + 1 ))
    done

    # Validate required arguments
    if [[ -z "${config_dir}" ]]; then
        echo -e "${RED}Error:${NC} -c <config_dir> is required." >&2; usage
    fi
    if [[ -z "${periods_arg}" && "${all_periods}" == false ]]; then
        echo -e "${RED}Error:${NC} -P <periods> or --all-periods is required." >&2; usage
    fi

    # Resolve config directory (try relative to BENCH_DIR if not found directly)
    if [[ ! -d "${config_dir}" ]]; then
        if [[ -d "${BENCH_DIR}/${config_dir}" ]]; then
            config_dir="${BENCH_DIR}/${config_dir}"
        else
            echo -e "${RED}Error:${NC} Config directory not found: ${config_dir}" >&2
            exit 1
        fi
    fi
    config_dir="$(cd "${config_dir}" && pwd)"
    local config_name
    config_name="$(basename "${config_dir}")"

    # Default experiment prefix = config name
    if [[ -z "${exp_prefix}" ]]; then
        exp_prefix="${config_name}"
    fi

    # Build period list
    local period_list=()
    if [[ "${all_periods}" == true ]]; then
        local -a files=( "${PERIODS_DIR}"/*.period )
        if [[ ! -e "${files[0]}" ]]; then
            echo -e "${RED}Error:${NC} No .period files found in ${PERIODS_DIR}" >&2
            exit 1
        fi
        for f in "${files[@]}"; do
            [[ -f "$f" ]] && period_list+=("$(basename "${f}" .period)")
        done
    else
        IFS=',' read -r -a period_list <<< "${periods_arg}"
    fi

    # Validate all period files exist before submitting anything
    for period in "${period_list[@]}"; do
        local pf="${PERIODS_DIR}/${period}.period"
        if [[ ! -f "${pf}" ]]; then
            echo -e "${RED}Error:${NC} Period not found: '${period}'" >&2
            echo "  Expected: ${pf}" >&2
            echo "  Register it with:  ${BENCH_DIR}/scripts/manage_periods.sh add ${period} --start YYYYMMDD --end YYYYMMDD" >&2
            exit 1
        fi
    done

    ensure_log

    # Build sweep Cartesian product (empty string = "no sweep" = one iteration)
    local -a sweep_combos=()
    build_combos sweep_combos
    local total_experiments=$(( ${#period_list[@]} * ${#sweep_combos[@]} ))

    echo "============================================================"
    echo " WW3 Calibration Run Dispatcher  (v${VERSION})"
    echo "============================================================"
    echo "  Config dir  : ${config_dir}"
    echo "  Config name : ${config_name}"
    echo "  DATA dir    : ${data_dir}"
    echo "  Exp prefix  : ${exp_prefix}"
    echo "  Periods     : ${#period_list[@]}  (${period_list[*]})"
    [[ -n "${ww3_dir}" ]]               && echo "  WW3 binary  : ${ww3_dir}"
    [[ -n "${grid_name}" ]]             && echo "  Grid        : ${grid_name}"
    [[ ${#extra_x_args[@]} -gt 0 ]]    && echo "  -X overrides: ${extra_x_args[*]}"
    [[ ${#sweep_combos[@]} -gt 1 ]]    && echo "  Sweep combos: ${#sweep_combos[@]}  (${sweep_combos[*]})"
    echo "  OMPH patch  : ${omph}"
    echo "  Rerun mode  : ${rerun}"
    echo "  Use groups  : ${use_groups}"
    echo "  Dry-run     : ${dry_run}"
    [[ ${#fwd_args[@]} -gt 0 ]]        && echo "  Fwd to run_exp: ${fwd_args[*]}"
    echo "  Total exps  : ${total_experiments}"
    echo "============================================================"
    echo ""

    local n_success=0
    local n_failed=0

    local sweep_combo
    for sweep_combo in "${sweep_combos[@]}"; do
        # Parse this sweep combo into per-experiment -X args and a name suffix.
        # sweep_combo format: "KEY1=val1 KEY2=val2 ..."
        local combo_x_args=()
        local combo_suffix=""
        if [[ -n "${sweep_combo}" ]]; then
            local kv
            for kv in ${sweep_combo}; do
                local sk="${kv%%=*}"
                local sv="${kv#*=}"
                combo_x_args+=(-X "${sk}=${sv}")
                local sv_tag="${sv//./}"   # strip dots: 1.43 → 143, 15.0 → 150
                combo_suffix+="__${sk}_${sv_tag}"
            done
        fi

        local period
        for period in "${period_list[@]}"; do
            local pf="${PERIODS_DIR}/${period}.period"

            # --use-groups: group = physics fingerprint, exp = period
            # Default: flat  exp_name = prefix + combo_suffix + __ + period
            local exp_name exp_group
            if [[ "${use_groups}" == true ]]; then
                exp_group="${exp_prefix}${combo_suffix}"
                exp_name="${period}"
            else
                exp_group=""
                exp_name="${exp_prefix}${combo_suffix}__${period}"
            fi
            local log_name="${exp_group:+${exp_group}/}${exp_name}"

            # Extract period dates for logging (without sourcing into current shell)
            local start_date end_date period_duration_days
            start_date=$(grep '^START_DATE=' "${pf}" | cut -d'"' -f2 | awk '{print $1}')
            end_date=$(grep   '^END_DATE='   "${pf}" | cut -d'"' -f2 | awk '{print $1}')
            period_duration_days=$(grep '^PERIOD_DURATION_DAYS=' "${pf}" | cut -d'"' -f2)

            echo "------------------------------------------------------------"
            [[ -n "${combo_suffix}" ]] && echo "  Sweep     : ${sweep_combo}"
            echo "  Period    : ${period}"
            if [[ -n "${exp_group}" ]]; then
            echo "  Group     : ${exp_group}"
            fi
            echo "  Exp name  : ${exp_name}"
            echo "  Path      : experiments/${exp_group:+${exp_group}/}${exp_name}"
            echo "  Dates     : ${start_date} → ${end_date}"
            [[ -n "${period_duration_days}" ]] && echo "  Duration  : ${period_duration_days} days"
            echo "------------------------------------------------------------"

            # Resolve experiment directory path (shared by rerun cleanup and OMPH patch)
            local exp_dir_path
            if [[ -n "${exp_group}" ]]; then
                exp_dir_path="${BENCH_DIR}/experiments/${exp_group}/${exp_name}"
            else
                exp_dir_path="${BENCH_DIR}/experiments/${exp_name}"
            fi

            # ----------------------------------------------------------------
            # Step 1 — setup.sh  (skipped in --rerun mode)
            # ----------------------------------------------------------------
            if [[ "${rerun}" == false ]]; then
                echo "[1/3] Setting up experiment: ${exp_name}"
                local setup_cmd=(
                    "${BENCH_DIR}/scripts/setup.sh"
                    -e "${exp_name}"
                    -c "${config_dir}"
                    -P "${period}"
		    -D "${data_dir}"
                )
                [[ -n "${ww3_dir}" ]]            && setup_cmd+=(-w "${ww3_dir}")
                [[ -n "${grid_name}" ]]          && setup_cmd+=(-g "${grid_name}")
                [[ -n "${exp_group}" ]]           && setup_cmd+=(--exp-group "${exp_group}")
                [[ ${#extra_x_args[@]} -gt 0 ]]  && setup_cmd+=("${extra_x_args[@]}")
                [[ ${#combo_x_args[@]} -gt 0 ]]  && setup_cmd+=("${combo_x_args[@]}")
                [[ "${dry_run}" == true ]]        && setup_cmd+=("--dry-run")

                if ! "${setup_cmd[@]}"; then
                    echo -e "${RED}ERROR:${NC} setup.sh failed for '${exp_name}' — skipping." >&2
                    append_log "${config_name}" "${period}" "${log_name}" \
                        "${start_date}" "${end_date}" "?" "?" "FAILED_SETUP" "SETUP_FAILED"
                    (( n_failed++ )) || true
                    echo ""
                    continue
                fi
            else
                # -- Rerun: verify directory exists, then clean partial outputs --
                echo "[1/3] Rerun — cleaning partial outputs: ${exp_dir_path}"
                if [[ ! -d "${exp_dir_path}" ]]; then
                    echo -e "${RED}ERROR:${NC} Experiment directory not found for rerun:" >&2
                    echo "         ${exp_dir_path}" >&2
                    append_log "${config_name}" "${period}" "${log_name}" \
                        "${start_date}" "${end_date}" "?" "?" "NO_DIR" "RERUN_FAILED"
                    (( n_failed++ )) || true
                    echo ""
                    continue
                fi
                local work_dir_rerun="${exp_dir_path}/work"
                if [[ "${dry_run}" == true ]]; then
                    echo "  [DRY-RUN] Would delete non-symlink *.nc in ${work_dir_rerun}"
                    echo "  [DRY-RUN] Would delete out_grd.ww3 test001.ww3 log.ww3"
                else
                    # Delete output NetCDFs — skip symlinks (wind.nc, ice.nc)
                    find "${work_dir_rerun}" -maxdepth 1 -name "*.nc" ! -type l -delete 2>/dev/null || true
                    # Delete ww3_shel binary outputs; keep prep outputs (mod_def, wind, ice .ww3)
                    rm -f "${work_dir_rerun}/out_grd.ww3" \
                          "${work_dir_rerun}/test001.ww3" \
                          "${work_dir_rerun}/log.ww3"
                    echo "      Cleaned: output *.nc, out_grd.ww3, test001.ww3, log.ww3"
                fi
            fi

            # ----------------------------------------------------------------
            # Step 2 — OMPH env.sh patch (if --omph)
            # ----------------------------------------------------------------
            if [[ "${omph}" == true ]]; then
                local env_file="${exp_dir_path}/metadata/setup/env.sh"
                if [[ "${dry_run}" == true ]]; then
                    echo "[DRY-RUN] Would check/apply OMPH patch to ${env_file}"
                elif [[ -f "${env_file}" ]]; then
                    if grep -q "WW3_OMP_THREADS=2" "${env_file}"; then
                        echo "[2/3] OMPH patch already present — skipping"
                    else
                        chmod u+w "${env_file}"
                        echo "export WW3_OMP_THREADS=2"      >> "${env_file}"
                        echo "export I_MPI_ASYNC_PROGRESS=0" >> "${env_file}"
                        chmod a-w "${env_file}"
                        echo "[2/3] OMPH env patch applied: ${env_file}"
                    fi
                else
                    echo -e "${YELLOW}WARNING:${NC} env.sh not found for OMPH patch: ${env_file}" >&2
                fi
            fi

            # Build -d and -t flags from stored duration if not already in fwd_args.
            # -d gets period duration in days; -t uses 5:1 sim-days-to-wall-hours.
            local extra_d_flag=()
            local extra_t_flag=()
            if [[ -n "${period_duration_days}" ]]; then
                local already_has_d=false
                local already_has_t=false
                local a
                for a in "${fwd_args[@]}"; do
                    [[ "$a" == "-d" ]] && { already_has_d=true; break; }
                done
                for a in "${fwd_args[@]}"; do
                    if [[ "$a" == "-t" || "$a" == -t* ]]; then
                        already_has_t=true
                        break
                    fi
                done
                [[ "${already_has_d}" == false ]] && extra_d_flag=(-d "${period_duration_days}")

                if [[ "${already_has_t}" == false ]]; then
                    local auto_wall_time
                    auto_wall_time="$(days_to_wall_hms "${period_duration_days}")"
                    extra_t_flag=(-t "${auto_wall_time}")
                    echo "  Auto -t   : ${auto_wall_time} (from ${period_duration_days} days at 5:1)"
                fi
            fi

            # ----------------------------------------------------------------
            # Step 3 — run_exp.sh
            # ----------------------------------------------------------------
            echo ""
            echo "[3/3] Submitting jobs: ${exp_name}"
            local run_cmd=(
                "${BENCH_DIR}/scripts/run_exp.sh"
                -e "${exp_name}"
                "${extra_d_flag[@]}"
                "${extra_t_flag[@]}"
                "${fwd_args[@]}"
            )

            local run_output
            if ! run_output=$("${run_cmd[@]}" 2>&1); then
                echo -e "${RED}ERROR:${NC} run_exp.sh failed for '${exp_name}'." >&2
                echo "${run_output}" >&2
                append_log "${config_name}" "${period}" "${log_name}" \
                    "${start_date}" "${end_date}" "?" "?" "FAILED_SUBMIT" "SUBMIT_FAILED"
                (( n_failed++ )) || true
                echo ""
                continue
            fi
            echo "${run_output}"

            # Parse shel job ID and task count from run_exp.sh output
            local shel_job_id ntasks_logged
            shel_job_id=$(echo "${run_output}" | grep -E 'Shel job\s*:' | grep -oE '[0-9]+' | tail -1)
            shel_job_id="${shel_job_id:-unknown}"
            ntasks_logged=$(echo "${run_output}" | grep -E 'Total tasks\s*:' | grep -oE '[0-9]+' | head -1)
            ntasks_logged="${ntasks_logged:-?}"

            append_log "${config_name}" "${period}" "${log_name}" \
                "${start_date}" "${end_date}" "?" "${ntasks_logged}" \
                "${shel_job_id}" "SUBMITTED"

            echo -e "${GREEN}Logged:${NC} ${log_name} (shel job: ${shel_job_id})"
            (( n_success++ )) || true
            echo ""
        done  # period loop
    done  # sweep_combo loop

    echo "============================================================"
    echo " Calibration dispatch complete"
    echo "  Submitted : ${n_success}/${total_experiments}"
    echo "  Failed    : ${n_failed}/${total_experiments}"
    echo "  Log       : ${CAL_LOG}"
    echo "============================================================"
    echo ""
    echo " Review log:"
    echo "   ${BENCH_DIR}/scripts/manage_periods.sh log --config ${config_name}"
    echo ""

    if [[ "${n_failed}" -gt 0 ]]; then
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
