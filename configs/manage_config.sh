#!/bin/bash
# =============================================================================
# manage_config.sh — WW3 namelist config registry and diff tool
# =============================================================================
# Version: 1.0
#
# Manages WW3 namelist configuration folders inside configs/.
# Tracks what changed between configs so folder names don't need to encode
# every detail. Maintains a README.md registry with diffs at creation time.
#
# Usage:
#   ./manage_config.sh <subcommand> [arguments]
#
# Subcommands:
#   init-baseline <folder>
#       Mark an existing config folder as the baseline reference.
#       Registers it in configs/README.md and writes a .baseline marker.
#
#   new <name> [--from <parent>]
#       Create a new config by copying from <parent> (or the baseline if
#       --from is omitted). Runs interactive prompts for description, tags,
#       and modified namelists. Records a diff vs the parent in README.md.
#
#   diff <config_a> [<config_b>]
#       Show file-by-file diff between two configs.
#       If only <config_a> is given, diffs against the baseline.
#
# Namelists tracked:
#   namelist.nml, ww3_prnc_wind.nml, ww3_prnc_sic.nml,
#   ww3_prnc_sithick.nml, ww3_shel.nml,
#   ww3_shel_1h.nml, ww3_shel_10h.nml, ww3_shel_1d.nml, ww3_shel_7d.nml
#
# Files written:
#   configs/<name>/.config_meta   — provenance for each config
#   configs/<folder>/.baseline    — marker for the baseline config
#   configs/README.md             — running registry with diffs
#
# Examples:
#   ./manage_config.sh init-baseline wind_only/
#   ./manage_config.sh new with_ice --from wind_only
#   ./manage_config.sh new with_ice_and_sithick --from with_ice
#   ./manage_config.sh diff with_ice
#   ./manage_config.sh diff with_ice with_ice_and_sithick
# =============================================================================

set -euo pipefail

SCRIPT_VERSION="1.0"
CONFIGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="${CONFIGS_DIR}/README.md"
BASELINE_MARKER=".baseline"
META_FILE=".config_meta"

# Canonical list of namelists this tool tracks
NML_FILES=(
    namelist.nml
    ww3_prnc_wind.nml
    ww3_prnc_sic.nml
    ww3_prnc_sithick.nml
    ww3_shel.nml
    ww3_shel_1h.nml
    ww3_shel_10h.nml
    ww3_shel_1d.nml
    ww3_shel_7d.nml
)

# =============================================================================
# Utility helpers
# =============================================================================

print_header() {
    echo "============================================================"
    echo " WW3 Config Manager  (v${SCRIPT_VERSION})"
    echo "============================================================"
}

err()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "  $*"; }

# Strip trailing slash from a folder argument
strip_slash() { echo "${1%/}"; }

# Find the baseline config folder (the one containing .baseline marker)
find_baseline() {
    local marker
    for dir in "${CONFIGS_DIR}"/*/; do
        marker="${dir}${BASELINE_MARKER}"
        if [[ -f "${marker}" ]]; then
            basename "${dir}"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# README helpers
# =============================================================================

# Initialise README.md from scratch
init_readme() {
    local baseline_name="$1"
    local now="$2"
    cat > "${README}" << EOF
# WW3 Config Registry

Managed by \`manage_config.sh\` v${SCRIPT_VERSION}.
Do not edit the table or diff sections by hand — use the tool.

## Baseline

**\`${baseline_name}/\`** — designated baseline at ${now}

All diffs are recorded relative to the direct parent config at creation time.

---

## Config Summary

<!-- schema=v1.0 -->
| Name | Parent | Date | Tags | Description |
|------|--------|------|------|-------------|
| \`${baseline_name}\` | — | ${now} | baseline | Baseline configuration |

---

## Config Details

EOF
}

# Append a new row to the README summary table
append_table_row() {
    local name="$1" parent="$2" date="$3" tags="$4" desc="$5"
    # Insert before the closing --- after the table
    # We append the row just before the "---\n\n## Config Details" block
    local row="| \`${name}\` | \`${parent}\` | ${date} | ${tags} | ${desc} |"
    # Use a temp file to insert the row before the Details header
    local tmp="${README}.tmp"
    awk -v row="${row}" '
        /^## Config Details/ && !inserted {
            print ""; print row; print ""; inserted=1
        }
        { print }
    ' "${README}" > "${tmp}"
    mv "${tmp}" "${README}"
}

# Append a collapsible diff section for a config
append_diff_section() {
    local name="$1" parent="$2" diff_content="$3" desc="$4"
    cat >> "${README}" << EOF

### \`${name}\`

> **Parent:** \`${parent}\`
> **Description:** ${desc}

<details>
<summary>Diff vs <code>${parent}</code> at creation time</summary>

\`\`\`diff
${diff_content}
\`\`\`

</details>

---
EOF
}

# =============================================================================
# Subcommand: init-baseline
# =============================================================================

cmd_init_baseline() {
    local folder
    folder="$(strip_slash "${1:-}")"

    [[ -z "${folder}" ]] && err "Usage: $0 init-baseline <folder>"

    local folder_path="${CONFIGS_DIR}/${folder}"
    [[ ! -d "${folder_path}" ]] && \
        err "Folder not found: ${folder_path}\n       Create the folder and add namelists first."

    print_header
    echo "  Subcommand   : init-baseline"
    echo "  Folder       : ${folder}"
    echo "  Configs dir  : ${CONFIGS_DIR}"
    echo "============================================================"

    # Check for an existing baseline and warn
    local existing
    if existing=$(find_baseline 2>/dev/null); then
        warn "Existing baseline found: '${existing}' — replacing"
        rm -f "${CONFIGS_DIR}/${existing}/${BASELINE_MARKER}"
    fi

    local now
    now=$(date +"%Y-%m-%dT%H:%M:%S")

    # Write .baseline marker
    cat > "${folder_path}/${BASELINE_MARKER}" << EOF
# WW3 config baseline marker — managed by manage_config.sh
baseline=${folder}
created=${now}
EOF

    echo ""
    info "Baseline marker written: ${folder_path}/${BASELINE_MARKER}"

    # Write .config_meta for the baseline itself
    cat > "${folder_path}/${META_FILE}" << EOF
# WW3 config metadata — managed by manage_config.sh v${SCRIPT_VERSION}
name=${folder}
parent=none
date=${now}
description=Baseline configuration
tags=baseline
modified_namelists=none
is_baseline=true
EOF

    info "Config meta written  : ${folder_path}/${META_FILE}"

    # Initialise or rebuild README
    init_readme "${folder}" "${now}"
    info "README initialised   : ${README}"

    echo ""
    echo "============================================================"
    echo " Baseline set: ${folder}"
    echo "============================================================"
    echo ""
    echo " Next steps:"
    echo "   ./manage_config.sh new <name>              # branch from this baseline"
    echo "   ./manage_config.sh new <name> --from ${folder}  # same, explicit"
}

# =============================================================================
# Subcommand: new
# =============================================================================

cmd_new() {
    local new_name=""
    local parent_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) shift; parent_name="$(strip_slash "${1:-}")" ;;
            --from=*) parent_name="$(strip_slash "${1#*=}")" ;;
            -*) err "Unknown option: $1" ;;
            *)  [[ -z "${new_name}" ]] && new_name="$1" || err "Unexpected argument: $1" ;;
        esac
        shift
    done

    [[ -z "${new_name}" ]] && err "Usage: $0 new <name> [--from <parent>]"

    new_name="$(strip_slash "${new_name}")"
    local new_path="${CONFIGS_DIR}/${new_name}"
    [[ -d "${new_path}" ]] && err "Config already exists: ${new_path}\n       Choose a different name or remove it first."

    # Resolve parent
    if [[ -z "${parent_name}" ]]; then
        parent_name=$(find_baseline 2>/dev/null) || \
            err "No baseline found and --from not specified.\n       Run: $0 init-baseline <folder>"
        info "No --from given — using baseline: ${parent_name}"
    fi

    local parent_path="${CONFIGS_DIR}/${parent_name}"
    [[ ! -d "${parent_path}" ]] && \
        err "Parent config not found: ${parent_path}"

    print_header
    echo "  Subcommand   : new"
    echo "  New config   : ${new_name}"
    echo "  Parent       : ${parent_name}"
    echo "  Configs dir  : ${CONFIGS_DIR}"
    echo "============================================================"
    echo ""

    # Interactive prompts
    echo "--- Configuration details ---"
    echo ""

    local description tags modified_nmls
    printf "  Description (one line — what does this config change?)\n  > "
    read -r description
    [[ -z "${description}" ]] && description="No description provided"

    printf "\n  Tags (comma-separated, e.g. ice,sic,physics — or leave blank)\n  > "
    read -r tags
    [[ -z "${tags}" ]] && tags="none"

    printf "\n  Which namelists did you modify from '${parent_name}'?\n"
    printf "  (space-separated, e.g. ww3_prnc_sic.nml ww3_shel.nml — or leave blank)\n  > "
    read -r modified_nmls
    [[ -z "${modified_nmls}" ]] && modified_nmls="none"

    echo ""
    echo "  Creating config folder and copying namelists..."

    # Create new folder and copy namelists
    mkdir -p "${new_path}"
    local copied=0
    for nml in "${NML_FILES[@]}"; do
        if [[ -f "${parent_path}/${nml}" ]]; then
            cp "${parent_path}/${nml}" "${new_path}/${nml}"
            info "copied: ${nml}"
            (( copied++ )) || true
        fi
    done
    # Also copy any extra *.nml files in parent not in canonical list
    for f in "${parent_path}"/*.nml; do
        [[ -f "${f}" ]] || continue
        local bname; bname=$(basename "${f}")
        if [[ ! -f "${new_path}/${bname}" ]]; then
            cp "${f}" "${new_path}/${bname}"
            info "copied (extra): ${bname}"
            (( copied++ )) || true
        fi
    done
    info "Total namelists copied: ${copied}"

    # Compute diff between parent and new folder (identical at this point — diff at creation)
    # This records the *intent* diff documented by the user; actual diff will show after edits.
    # We record a placeholder diff since files are identical at creation time.
    local diff_content=""
    local files_diffed=0
    for nml in "${NML_FILES[@]}"; do
        local pf="${parent_path}/${nml}"
        local nf="${new_path}/${nml}"
        if [[ -f "${pf}" && -f "${nf}" ]]; then
            local d
            d=$(diff -u "${pf}" "${nf}" || true)
            if [[ -n "${d}" ]]; then
                diff_content+="### ${nml}"$'\n'"${d}"$'\n\n'
            fi
            (( files_diffed++ )) || true
        elif [[ -f "${nf}" && ! -f "${pf}" ]]; then
            diff_content+="### ${nml} (new file in ${new_name})"$'\n\n'
        fi
    done

    if [[ -z "${diff_content}" ]]; then
        diff_content="(No differences at creation time — namelists are identical to parent.
Edit the namelists in ${new_name}/ then re-run:
  ./manage_config.sh diff ${new_name})"
    fi

    local now
    now=$(date +"%Y-%m-%dT%H:%M:%S")

    # Write .config_meta
    cat > "${new_path}/${META_FILE}" << EOF
# WW3 config metadata — managed by manage_config.sh v${SCRIPT_VERSION}
name=${new_name}
parent=${parent_name}
date=${now}
description=${description}
tags=${tags}
modified_namelists=${modified_nmls}
is_baseline=false
EOF
    info "Metadata written: ${new_path}/${META_FILE}"

    # Update README — ensure it exists
    if [[ ! -f "${README}" ]]; then
        warn "README.md not found — creating a minimal one"
        local baseline_name
        baseline_name=$(find_baseline 2>/dev/null) || baseline_name="unknown"
        init_readme "${baseline_name}" "${now}"
    fi

    append_table_row "${new_name}" "${parent_name}" "${now}" "${tags}" "${description}"
    append_diff_section "${new_name}" "${parent_name}" "${diff_content}" "${description}"
    info "README updated  : ${README}"

    echo ""
    echo "============================================================"
    echo " Config created: ${new_name}"
    echo "============================================================"
    echo "  Parent      : ${parent_name}"
    echo "  Description : ${description}"
    echo "  Tags        : ${tags}"
    echo "  Modified    : ${modified_nmls}"
    echo ""
    echo " *** Now edit your namelists in: ***"
    echo "   ${new_path}/"
    echo ""
    echo " After editing, record the actual diff:"
    echo "   ./manage_config.sh diff ${new_name}"
    echo "============================================================"
}

# =============================================================================
# Subcommand: diff
# =============================================================================

cmd_diff() {
    local config_a="" config_b=""

    case $# in
        1) config_a="$(strip_slash "$1")" ;;
        2) config_a="$(strip_slash "$1")"; config_b="$(strip_slash "$2")" ;;
        *) err "Usage: $0 diff <config_a> [<config_b>]" ;;
    esac

    # Resolve config_b — default to baseline if not given
    if [[ -z "${config_b}" ]]; then
        config_b=$(find_baseline 2>/dev/null) || \
            err "No baseline found.\n       Run: $0 init-baseline <folder>"
        echo "  (comparing against baseline: ${config_b})"
        # Swap so A=baseline, B=target for readable diff direction
        local tmp="${config_a}"; config_a="${config_b}"; config_b="${tmp}"
    fi

    local path_a="${CONFIGS_DIR}/${config_a}"
    local path_b="${CONFIGS_DIR}/${config_b}"

    [[ ! -d "${path_a}" ]] && err "Config not found: ${path_a}"
    [[ ! -d "${path_b}" ]] && err "Config not found: ${path_b}"

    print_header
    echo "  Subcommand   : diff"
    echo "  A (base)     : ${config_a}"
    echo "  B (target)   : ${config_b}"
    echo "============================================================"
    echo ""

    local files_same=0 files_differ=0 files_only_a=0 files_only_b=0

    # Collect all nml files across both directories
    local all_nmls=()
    while IFS= read -r f; do
        all_nmls+=("$(basename "${f}")")
    done < <(find "${path_a}" "${path_b}" -maxdepth 1 -name "*.nml" | sort -u)
    # Deduplicate
    mapfile -t all_nmls < <(printf '%s\n' "${all_nmls[@]}" | sort -u)

    for nml in "${all_nmls[@]}"; do
        local fa="${path_a}/${nml}"
        local fb="${path_b}/${nml}"

        echo "──────────────────────────────────────────────"
        echo "  ${nml}"
        echo "──────────────────────────────────────────────"

        if [[ -f "${fa}" && -f "${fb}" ]]; then
            # diff exits 1 when files differ — don't let set -e kill us
            local d
            d=$(diff -u --label "${config_a}/${nml}" --label "${config_b}/${nml}" \
                    "${fa}" "${fb}" 2>/dev/null || true)
            if [[ -z "${d}" ]]; then
                echo "  ✓  identical"
                (( files_same++ )) || true
            else
                # Print with color if terminal supports it
                if [[ -t 1 ]]; then
                    diff -u --color=always \
                        --label "${config_a}/${nml}" --label "${config_b}/${nml}" \
                        "${fa}" "${fb}" || true
                else
                    echo "${d}"
                fi
                (( files_differ++ )) || true
            fi
        elif [[ -f "${fa}" && ! -f "${fb}" ]]; then
            echo "  ✗  only in ${config_a} (not in ${config_b})"
            (( files_only_a++ )) || true
        elif [[ ! -f "${fa}" && -f "${fb}" ]]; then
            echo "  +  only in ${config_b} (not in ${config_a})"
            (( files_only_b++ )) || true
        fi
        echo ""
    done

    echo "============================================================"
    echo " Diff summary: ${config_a}  →  ${config_b}"
    echo "============================================================"
    echo "  Identical    : ${files_same}"
    echo "  Different    : ${files_differ}"
    [[ "${files_only_a}" -gt 0 ]] && echo "  Only in A    : ${files_only_a}"
    [[ "${files_only_b}" -gt 0 ]] && echo "  Only in B    : ${files_only_b}"
    echo "============================================================"
}

# =============================================================================
# Entrypoint
# =============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") <subcommand> [arguments]

Subcommands:
  init-baseline <folder>             Mark a config folder as the baseline
  new <name> [--from <parent>]       Create a new config (interactive)
  diff <config_a> [<config_b>]       Diff two configs (or one vs baseline)

Run with no arguments to see this help.
EOF
}

if [[ $# -eq 0 ]]; then
    print_header
    echo ""
    usage
    exit 0
fi

SUBCOMMAND="$1"; shift

case "${SUBCOMMAND}" in
    init-baseline) cmd_init_baseline "$@" ;;
    new)           cmd_new           "$@" ;;
    diff)          cmd_diff          "$@" ;;
    --help|-h)     print_header; echo ""; usage ;;
    *) err "Unknown subcommand: '${SUBCOMMAND}'\n       Run: $(basename "$0") --help" ;;
esac
