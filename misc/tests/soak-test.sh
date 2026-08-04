#!/bin/bash
# Self-contained check for the self-update soak window (_soak_verdict).
# No root, network or docker needed: the decision function is pure, so every
# branch is driven directly with fabricated state. Run: bash this file.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/update-cs2-centralized.sh"
FAILS=0

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\e[32m'; RED=$'\e[31m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    GREEN=""; RED=""; BOLD=""; RESET=""
fi

echo ""

# run_case <name> <expected> <r_ver> <r_hash> <p_ver> <p_hash> <p_ts> <now> <soak>
run_case() {
    local name="$1" expect="$2"
    shift 2
    local got
    got=$(source "$SCRIPT" >/dev/null 2>&1; _soak_verdict "$@" 2>/dev/null)
    if [ "$got" = "$expect" ]; then
        echo "${GREEN}PASS${RESET}  $name"
    else
        echo "${RED}FAIL${RESET}  $name (got: ${got:-<empty>}, expected: $expect)"
        FAILS=$((FAILS + 1))
    fi
}

H_NEW="aaaa"
H_OLD="bbbb"
NOW=1000000

echo "${BOLD}Soak window decisions${RESET}"
echo ""

run_case "soak disabled installs immediately" \
    install "1.0.62" "$H_NEW" "" "" 0 "$NOW" 0

run_case "first sight of a new version is recorded" \
    record "1.0.62" "$H_NEW" "" "" 0 "$NOW" 3600

run_case "same script still inside the window waits" \
    wait "1.0.62" "$H_NEW" "1.0.62" "$H_NEW" $((NOW - 60)) "$NOW" 3600

run_case "same script past the window installs" \
    install "1.0.62" "$H_NEW" "1.0.62" "$H_NEW" $((NOW - 3600)) "$NOW" 3600

run_case "window boundary counts as elapsed" \
    install "1.0.62" "$H_NEW" "1.0.62" "$H_NEW" $((NOW - 3600)) "$NOW" 3600

run_case "body swapped under the same version restarts the clock" \
    record "1.0.62" "$H_NEW" "1.0.62" "$H_OLD" $((NOW - 3599)) "$NOW" 3600

run_case "a newer version replaces the pending one" \
    record "1.0.63" "$H_NEW" "1.0.62" "$H_OLD" $((NOW - 3599)) "$NOW" 3600

run_case "pending version pulled from the branch is dropped" \
    drop "1.0.61" "$H_NEW" "1.0.62" "$H_OLD" $((NOW - 3599)) "$NOW" 3600

run_case "semver compare is numeric, not lexical (1.0.9 < 1.0.10)" \
    drop "1.0.9" "$H_NEW" "1.0.10" "$H_OLD" $((NOW - 60)) "$NOW" 3600

run_case "--update style bypass installs a still-soaking version" \
    install "1.0.62" "$H_NEW" "1.0.62" "$H_OLD" "$NOW" "$NOW" 0

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "${GREEN}All soak window cases passed${RESET}"
    echo ""
    exit 0
fi
echo "${RED}${FAILS} case(s) failed${RESET}"
echo ""
exit 1
