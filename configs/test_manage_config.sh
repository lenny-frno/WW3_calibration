#!/bin/bash
# =============================================================================
# test_manage_config.sh — Integration test for manage_config.sh
# =============================================================================
# Version: 1.0
#
# Creates a temporary sandbox under /tmp/ww3_config_test/, exercises all
# three subcommands, and checks expected outputs.
#
# Usage:
#   ./test_manage_config.sh          # run all tests
#   ./test_manage_config.sh --keep   # keep sandbox after run (for inspection)
#
# Tests:
#   1. init-baseline  — marks wind_only/ as baseline
#   2. new            — creates with_ice/ from baseline (non-interactive via heredoc)
#   3. new --from     — creates with_ice_and_sithick/ from with_ice/ explicitly
#   4. diff (1 arg)   — diffs with_ice/ against baseline
#   5. diff (2 args)  — diffs with_ice/ vs with_ice_and_sithick/
#   6. README check   — verifies key content in README.md
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE="${SCRIPT_DIR}/manage_config.sh"

KEEP=false
[[ "${1:-}" == "--keep" ]] && KEEP=true

# =============================================================================
# Test harness
# =============================================================================

PASS=0; FAIL=0

ok()   { echo "  ✓  $*"; (( PASS++ )) || true; }
fail() { echo "  ✗  $*"; (( FAIL++ )) || true; }

check() {
    local label="$1"; shift
    if "$@" &>/dev/null; then ok "${label}"; else fail "${label}"; fi
}

check_contains() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        ok "${label}"
    else
        fail "${label}  (pattern: '${pattern}' not found in ${file})"
    fi
}

section() {
    echo ""
    echo "──────────────────────────────────────────────"
    echo " $*"
    echo "──────────────────────────────────────────────"
}

# =============================================================================
# Sandbox setup
# =============================================================================

SANDBOX=$(mktemp -d /tmp/ww3_config_test_XXXXXX)
echo "============================================================"
echo " WW3 manage_config.sh — Integration Tests"
echo "============================================================"
echo "  Sandbox : ${SANDBOX}"
echo "  Script  : ${MANAGE}"
echo "============================================================"

# Temporarily override CONFIGS_DIR by symlinking manage_config.sh into sandbox
cp "${MANAGE}" "${SANDBOX}/manage_config.sh"
chmod +x "${SANDBOX}/manage_config.sh"
TOOL="${SANDBOX}/manage_config.sh"

# =============================================================================
# Helper: write a minimal but realistic namelist file
# =============================================================================

write_wind_nml() {
    local dir="$1"
    cat > "${dir}/ww3_prnc_wind.nml" << 'EOF'
! ww3_prnc_wind.nml — wind forcing (baseline: ERA5 10m winds)
&FORCING
  TIMESTART = '20210101 000000'
  TIMESTOP  = '20210108 000000'
  FORCING   = T F F F F F F
/
&GRID
  NAME      = 'wind'
  FILENAME  = 'wind.nc'
  X         = 'longitude'
  Y         = 'latitude'
  Z         = ''
  T         = 'time'
  U         = 'u10'
  V         = 'v10'
/
EOF

    cat > "${dir}/ww3_prnc_sic.nml" << 'EOF'
! ww3_prnc_sic.nml — sea ice concentration (baseline: disabled)
&FORCING
  TIMESTART = '20210101 000000'
  TIMESTOP  = '20210108 000000'
  FORCING   = F F F F F F F
/
EOF

    cat > "${dir}/ww3_prnc_sithick.nml" << 'EOF'
! ww3_prnc_sithick.nml — sea ice thickness (baseline: disabled)
&FORCING
  TIMESTART = '20210101 000000'
  TIMESTOP  = '20210108 000000'
  FORCING   = F F F F F F F
/
EOF

    cat > "${dir}/namelist.nml" << 'EOF'
! namelist.nml — WW3 physics and numerics (baseline: unmodified defaults)
&PRO3
  WDTHCG = 0.00
  WDTHTH = 0.00
/
&SIN4
  BETAMAX = 1.55
/
&SDS4
  SDSC2  = -2.2E-5
/
EOF

    cat > "${dir}/ww3_shel.nml" << 'EOF'
! ww3_shel.nml — main shell namelist
&DOMAIN
  STOP = '20210108 000000'
/
&OUTPUT_TYPE
  FIELD%LIST = 'HS WND'
/
EOF

    for dur in 1h 10h 1d 7d; do
        cat > "${dir}/ww3_shel_${dur}.nml" << EOF
! ww3_shel_${dur}.nml — shell namelist for ${dur} simulation
&DOMAIN
  STOP = '20210101 010000'
/
&OUTPUT_TYPE
  FIELD%LIST = 'HS WND'
/
EOF
    done
}

# =============================================================================
# Test 1: init-baseline
# =============================================================================

section "Test 1: init-baseline"

BASELINE_DIR="${SANDBOX}/wind_only"
mkdir -p "${BASELINE_DIR}"
write_wind_nml "${BASELINE_DIR}"

echo "  Running: manage_config.sh init-baseline wind_only"
"${TOOL}" init-baseline wind_only 2>&1 | sed 's/^/    /'

check "  .baseline marker created"    test -f "${BASELINE_DIR}/.baseline"
check "  .config_meta created"        test -f "${BASELINE_DIR}/.config_meta"
check "  README.md created"           test -f "${SANDBOX}/README.md"
check_contains "  README has baseline name" "${SANDBOX}/README.md" "wind_only"
check_contains "  README has schema tag"    "${SANDBOX}/README.md" "schema=v1.0"

# =============================================================================
# Test 2: new (from baseline, non-interactive via heredoc)
# =============================================================================

section "Test 2: new with_ice (from baseline, simulated interactive input)"

echo "  Running: manage_config.sh new with_ice"
"${TOOL}" new with_ice << 'EOF' 2>&1 | sed 's/^/    /'
Enable sea ice concentration forcing (SIC)
ice,sic,physics
ww3_prnc_sic.nml
EOF

check "  with_ice/ folder created"    test -d "${SANDBOX}/with_ice"
check "  .config_meta written"        test -f "${SANDBOX}/with_ice/.config_meta"
check "  namelist.nml copied"         test -f "${SANDBOX}/with_ice/namelist.nml"
check "  ww3_prnc_sic.nml copied"     test -f "${SANDBOX}/with_ice/ww3_prnc_sic.nml"
check "  ww3_shel_1d.nml copied"      test -f "${SANDBOX}/with_ice/ww3_shel_1d.nml"
check_contains "  meta has parent"    "${SANDBOX}/with_ice/.config_meta" "parent=wind_only"
check_contains "  meta has tags"      "${SANDBOX}/with_ice/.config_meta" "tags=ice,sic,physics"
check_contains "  README has with_ice" "${SANDBOX}/README.md" "with_ice"

# Now actually modify the sic namelist so there's a real diff to show
cat > "${SANDBOX}/with_ice/ww3_prnc_sic.nml" << 'EOF'
! ww3_prnc_sic.nml — sea ice concentration (ENABLED)
&FORCING
  TIMESTART = '20210101 000000'
  TIMESTOP  = '20210108 000000'
  FORCING   = F F F T F F F
/
&GRID
  NAME      = 'ice_conc'
  FILENAME  = 'ice.nc'
  X         = 'longitude'
  Y         = 'latitude'
  Z         = ''
  T         = 'time'
  U         = 'sic'
/
EOF

echo "  (Modified ww3_prnc_sic.nml to enable ice forcing)"

# =============================================================================
# Test 3: new --from (branching from with_ice)
# =============================================================================

section "Test 3: new with_ice_and_sithick --from with_ice"

echo "  Running: manage_config.sh new with_ice_and_sithick --from with_ice"
"${TOOL}" new with_ice_and_sithick --from with_ice << 'EOF' 2>&1 | sed 's/^/    /'
Add sea ice thickness forcing on top of SIC
ice,sic,sithick,physics
ww3_prnc_sithick.nml
EOF

check "  with_ice_and_sithick/ created"  test -d "${SANDBOX}/with_ice_and_sithick"
check "  .config_meta written"           test -f "${SANDBOX}/with_ice_and_sithick/.config_meta"
check_contains "  meta: parent=with_ice" \
    "${SANDBOX}/with_ice_and_sithick/.config_meta" "parent=with_ice"
check_contains "  README has new entry"  "${SANDBOX}/README.md" "with_ice_and_sithick"

# Modify sithick in the new config for a real diff
cat > "${SANDBOX}/with_ice_and_sithick/ww3_prnc_sithick.nml" << 'EOF'
! ww3_prnc_sithick.nml — sea ice thickness (ENABLED)
&FORCING
  TIMESTART = '20210101 000000'
  TIMESTOP  = '20210108 000000'
  FORCING   = F F F F F T F
/
&GRID
  NAME      = 'ice_thick'
  FILENAME  = 'ice.nc'
  X         = 'longitude'
  Y         = 'latitude'
  Z         = ''
  T         = 'time'
  U         = 'sithick'
/
EOF

echo "  (Modified ww3_prnc_sithick.nml to enable ice thickness)"

# =============================================================================
# Test 4: diff (single arg — vs baseline)
# =============================================================================

section "Test 4: diff with_ice (vs baseline)"

echo "  Running: manage_config.sh diff with_ice"
DIFF_OUT=$("${TOOL}" diff with_ice 2>&1)
echo "${DIFF_OUT}" | sed 's/^/    /'

if echo "${DIFF_OUT}" | grep -q "ww3_prnc_sic.nml"; then
    ok "  diff output mentions ww3_prnc_sic.nml"
else
    fail "  diff output should mention ww3_prnc_sic.nml"
fi

if echo "${DIFF_OUT}" | grep -qE "Different\s*:\s*[1-9]"; then
    ok "  diff reports at least 1 differing file"
else
    fail "  diff should report ≥1 different file"
fi

if echo "${DIFF_OUT}" | grep -qE "Identical\s*:"; then
    ok "  diff reports identical count"
else
    fail "  diff should report identical count"
fi

# =============================================================================
# Test 5: diff (two args)
# =============================================================================

section "Test 5: diff with_ice with_ice_and_sithick"

echo "  Running: manage_config.sh diff with_ice with_ice_and_sithick"
DIFF2_OUT=$("${TOOL}" diff with_ice with_ice_and_sithick 2>&1)
echo "${DIFF2_OUT}" | sed 's/^/    /'

if echo "${DIFF2_OUT}" | grep -q "ww3_prnc_sithick.nml"; then
    ok "  diff2 mentions ww3_prnc_sithick.nml"
else
    fail "  diff2 should mention ww3_prnc_sithick.nml"
fi

if echo "${DIFF2_OUT}" | grep -qE "Different\s*:\s*[1-9]"; then
    ok "  diff2 reports at least 1 differing file"
else
    fail "  diff2 should report ≥1 different file"
fi

# =============================================================================
# Test 6: README integrity
# =============================================================================

section "Test 6: README.md content integrity"

check_contains "  Has summary table header" "${SANDBOX}/README.md" "| Name | Parent | Date | Tags | Description |"
check_contains "  Has wind_only row"         "${SANDBOX}/README.md" "wind_only"
check_contains "  Has with_ice row"          "${SANDBOX}/README.md" "with_ice"
check_contains "  Has with_ice_and_sithick"  "${SANDBOX}/README.md" "with_ice_and_sithick"
check_contains "  Has <details> block"       "${SANDBOX}/README.md" "<details>"
check_contains "  Has diff fences"           "${SANDBOX}/README.md" '```diff'

# =============================================================================
# Error handling tests
# =============================================================================

section "Test 7: Error handling"

echo "  Testing: new with existing name should fail"
OUT=$(bash "${TOOL}" new with_ice <<< $'test\nnone\nnone' 2>&1 || true)
if echo "${OUT}" | grep -q "ERROR"; then
    ok "  Duplicate name rejected"
else
    fail "  Duplicate name should be rejected"
fi

echo "  Testing: diff with nonexistent config should fail"
OUT=$(bash "${TOOL}" diff nonexistent_config_xyz 2>&1 || true)
if echo "${OUT}" | grep -q "ERROR"; then
    ok "  Missing config rejected in diff"
else
    fail "  Missing config should fail in diff"
fi

echo "  Testing: unknown subcommand should fail"
OUT=$(bash "${TOOL}" frobnicate 2>&1 || true)
if echo "${OUT}" | grep -q "ERROR"; then
    ok "  Unknown subcommand rejected"
else
    fail "  Unknown subcommand should be rejected"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================"
echo " Test Results"
echo "============================================================"
echo "  Passed : ${PASS}"
echo "  Failed : ${FAIL}"
echo "  Total  : $(( PASS + FAIL ))"
echo ""

if [[ "${KEEP}" == true ]]; then
    echo "  Sandbox kept at: ${SANDBOX}"
    echo ""
    echo "  Explore:"
    echo "    ls ${SANDBOX}/"
    echo "    cat ${SANDBOX}/README.md"
    echo "    cat ${SANDBOX}/with_ice/.config_meta"
else
    rm -rf "${SANDBOX}"
    echo "  Sandbox cleaned up (use --keep to retain)"
fi

echo "============================================================"

[[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
