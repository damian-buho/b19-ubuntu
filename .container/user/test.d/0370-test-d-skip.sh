#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test test.d mutes one script with B19_TEST_SKIP_<NAME>=true, runs it otherwise and counts the skip.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "TEST-SKIP-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

# Fixtures live in the cache, since /tmp may be mounted noexec
TEST_ROOT="${XDG_CACHE_HOME}/b19-test-test-d-skip"
rm --recursive --force "${TEST_ROOT}"
mkdir --parents "${TEST_ROOT}/health" "${TEST_ROOT}/tests"
printf '#!/usr/bin/env bash\ntouch "%s/marker"\n' "${TEST_ROOT}" > "${TEST_ROOT}/tests/0100-some-check.sh"
chmod +x "${TEST_ROOT}/tests/0100-some-check.sh"

# Run the runner on the fixture suite with an empty healthcheck tree, so the gate passes at once
run_tests() {
    rm --force "${TEST_ROOT}/marker"
    env "B19_TEST_PATH=${TEST_ROOT}/tests" "B19_HEALTH_PATH=${TEST_ROOT}/health" "B19_TEMP_PATH=${TEST_ROOT}" \
        "B19_VERBOSITY=info" "$@" test.d 2>&1
}

b19-log note "TEST-SKIP-TEST" "$(_p "Test %s: muted script is not run and is counted" "1")"
TEST_OUTPUT="$(run_tests "B19_TEST_SKIP_SOME_CHECK=true")" || fail "$(_ "Muted suite failed")"
[ ! -e "${TEST_ROOT}/marker" ] || fail "$(_ "Muted test script ran")"
[[ "${TEST_OUTPUT}" == *"B19_TEST_SKIP_SOME_CHECK"* ]] || fail "$(_ "Skip did not name its variable")"
[[ "${TEST_OUTPUT}" == *"0 passed, 1 skipped"* ]] || fail "$(_ "Skip was not counted")"
b19-log good "TEST-SKIP-TEST" "$(_p "Test %s passed" "1")"

b19-log note "TEST-SKIP-TEST" "$(_p "Test %s: unset variable runs the script" "2")"
TEST_OUTPUT="$(run_tests)" || fail "$(_ "Unmuted suite failed")"
[ -f "${TEST_ROOT}/marker" ] || fail "$(_ "Unmuted test script did not run")"
[[ "${TEST_OUTPUT}" == *"1 passed, 0 skipped"* ]] || fail "$(_ "Pass was not counted")"
b19-log good "TEST-SKIP-TEST" "$(_p "Test %s passed" "2")"

b19-log note "TEST-SKIP-TEST" "$(_p "Test %s: false runs the script" "3")"
TEST_OUTPUT="$(run_tests "B19_TEST_SKIP_SOME_CHECK=false")" || fail "$(_ "Suite with false mute failed")"
[ -f "${TEST_ROOT}/marker" ] || fail "$(_ "Script with a false mute did not run")"
b19-log good "TEST-SKIP-TEST" "$(_p "Test %s passed" "3")"

b19-log note "TEST-SKIP-TEST" "$(_p "Test %s: unknown name is a no-op" "4")"
TEST_OUTPUT="$(run_tests "B19_TEST_SKIP_NO_SUCH_SCRIPT=true")" || fail "$(_ "Suite with unknown mute failed")"
[ -f "${TEST_ROOT}/marker" ] || fail "$(_ "Unknown mute stopped a script")"
b19-log good "TEST-SKIP-TEST" "$(_p "Test %s passed" "4")"

rm --recursive --force "${TEST_ROOT}"
