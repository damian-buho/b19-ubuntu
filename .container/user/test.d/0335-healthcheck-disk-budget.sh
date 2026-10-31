#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test the disk budget check at its edges: used = budget, budget + 1, the warn threshold and malformed budgets.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

ROOT="/tmp/b19-test-disk-budget.$$"
CHECK="${B19_HEALTH_PATH}/hourly/0100-check-disk-budget.sh"

fail() {
    b19-log error "DISK-BUDGET-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

# Runs the check with only the budget variables given as NAME=VALUE arguments
budget() {
    local _unset=() _var
    for _var in $(compgen -v B19_DISK_BUDGET_ || true); do _unset+=("--unset=${_var}"); done
    # shellcheck disable=SC2016 # the child bash sources the check with its own helpers loaded
    env "${_unset[@]}" \
        "B19_TEMP_PATH=${ROOT}/state" "B19_HEALTH_LOG_TARGET=${ROOT}/container.log" B19_VERBOSITY=info \
        TEST_DATA="${ROOT}/data" TEST_ABSENT="${ROOT}/absent" TEST_RELATIVE=relative/path "$@" \
        bash -c 'set -euo pipefail; . b19-i18n; . "$1"' disk-budget "${CHECK}" 2>&1
}

# Asserts test $1 passes ($2=pass) or fails ($2=fail) with budget variables $3…
expect() {
    local _n="$1" _want="$2" _got=pass
    shift 2
    b19-log note "DISK-BUDGET-TEST" "$(_p "Test %s: expecting %s for %s" "${_n}" "${_want}" "$*")"
    TEST_OUTPUT="$(budget "$@")" || _got=fail
    [ "${_got}" = "${_want}" ] || fail "$(_p "Test %s: expected %s, got %s" "${_n}" "${_want}" "${_got}")"
    b19-log good "DISK-BUDGET-TEST" "$(_p "Test %s passed" "${_n}")"
}

# Counts the near-budget lines written to the container log
near_lines() {
    local _n=0 _line
    if [ -f "${ROOT}/container.log" ]; then
        while IFS= read -r _line; do
            if [[ "${_line}" == *"${ROOT}/data"* ]]; then _n=$((_n + 1)); fi
        done <"${ROOT}/container.log"
    fi
    echo "${_n}"
}

mkdir --parents "${ROOT}/data" "${ROOT}/state"
head --bytes=65536 /dev/zero >"${ROOT}/data/payload"
USED=$(du --summarize --one-file-system --block-size=1 -- "${ROOT}/data")
USED="${USED%%[[:space:]]*}"
b19-log note "DISK-BUDGET-TEST" "$(_p "Fixture %s uses %s bytes" "${ROOT}/data" "${USED}")"

expect 1 pass "B19_DISK_BUDGET_TEST_DATA=${USED}" B19_HEALTH_DISK_WARN_PERCENT=100
[ "$(near_lines)" -eq 1 ] || fail "$(_ "Used equal to the budget at 100 % was not reported as near")"

expect 2 pass "B19_DISK_BUDGET_TEST_DATA=${USED}" B19_HEALTH_DISK_WARN_PERCENT=100
[ "$(near_lines)" -eq 1 ] || fail "$(_ "An unchanged near-budget set was reported again")"

expect 3 pass "B19_DISK_BUDGET_TEST_DATA=$(( USED + 1 ))" B19_HEALTH_DISK_WARN_PERCENT=100
expect 4 pass "B19_DISK_BUDGET_TEST_DATA=${USED}" B19_HEALTH_DISK_WARN_PERCENT=100
[ "$(near_lines)" -eq 2 ] || fail "$(_ "A path crossing the threshold again was not reported")"

expect 5 fail "B19_DISK_BUDGET_TEST_DATA=$(( USED - 1 ))" B19_HEALTH_DISK_WARN_PERCENT=90
[[ "${TEST_OUTPUT##*$'\n'}" == *"${ROOT}/data("* ]] || fail "$(_ "The last line does not name the path over budget")"

expect 6 pass "B19_DISK_BUDGET_TEST_DATA=1Pi" "B19_DISK_BUDGET_TEST_ABSENT=1Ki" "B19_DISK_BUDGET_TEST_EMPTY=" B19_HEALTH_DISK_WARN_PERCENT=90
[[ "${TEST_OUTPUT}" == *"${ROOT}/absent"* ]] || fail "$(_ "Missing budget path was not logged")"

expect 7 fail "B19_DISK_BUDGET_TEST_DATA=4G" B19_HEALTH_DISK_WARN_PERCENT=90
[[ "${TEST_OUTPUT}" == *B19_DISK_BUDGET_TEST_DATA=4G* ]] || fail "$(_ "Malformed budget was not named by its variable")"
expect 8 fail "B19_DISK_BUDGET_TEST_RELATIVE=1Gi" B19_HEALTH_DISK_WARN_PERCENT=90
expect 9 fail "B19_DISK_BUDGET_TEST_UNDEFINED=1Gi" B19_HEALTH_DISK_WARN_PERCENT=90
expect 10 fail "B19_DISK_BUDGET_=1Gi" B19_HEALTH_DISK_WARN_PERCENT=90
expect 11 fail B19_HEALTH_DISK_WARN_PERCENT=0
expect 12 fail B19_HEALTH_DISK_WARN_PERCENT=101
expect 13 pass B19_HEALTH_DISK_WARN_PERCENT=1

rm --recursive --force -- "${ROOT}"
b19-log good "DISK-BUDGET-TEST" "$(_ "All disk budget tests passed")"
