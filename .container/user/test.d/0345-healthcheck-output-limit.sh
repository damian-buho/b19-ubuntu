#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test healthcheck.d output: the verdict survives noise past the output limit, and a failure leaves its reason in the state file.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "HEALTH-LIMIT-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

mkdir --parents /tmp/b19-test-health-limit/checks /tmp/b19-test-health-limit/state
touch /tmp/b19-test-health-limit/container.log
cat >/tmp/b19-test-health-limit/checks/0100-check-noisy.sh <<'CHECK'
for i in $(seq 1 300); do echo "noise line number ${i} with some padding to fill the buffer" >&2; done
echo boom >&2
exit 3
CHECK

# Probe an isolated check tree, stdout and stderr merged as Docker stores them
probe() {
    env "B19_HEALTH_PATH=/tmp/b19-test-health-limit/checks" "B19_TEMP_PATH=/tmp/b19-test-health-limit/state" \
        "B19_HEALTH_OUTPUT_LIMIT=${1}" "B19_HEALTH_LOG_TARGET=/tmp/b19-test-health-limit/container.log" "B19_VERBOSITY=debug" healthcheck.d 2>&1
}

b19-log note "HEALTH-LIMIT-TEST" "$(_p "Test %s: noise past the limit keeps the failed name first" "1")"
TEST_OUTPUT="$(probe 4096)" && fail "$(_ "Failing check passed the probe")"
if [ "${#TEST_OUTPUT}" -le 4096 ] && [ "${TEST_OUTPUT%%$'\n'*}" = "0100-check-noisy.sh" ]; then
    b19-log good "HEALTH-LIMIT-TEST" "$(_p "Test %s passed" "1")"
else
    fail "$(_p "Output of %s bytes does not open with the failed name" "${#TEST_OUTPUT}")"
fi

b19-log note "HEALTH-LIMIT-TEST" "$(_p "Test %s: a limit smaller than the verdict still opens with it" "2")"
TEST_OUTPUT="$(probe 20)" && fail "$(_ "Failing check passed the probe")"
if [ "${TEST_OUTPUT%%$'\n'*}" = "0100-check-noisy.sh" ]; then
    b19-log good "HEALTH-LIMIT-TEST" "$(_p "Test %s passed" "2")"
else
    fail "$(_ "Verdict lost under a tiny limit")"
fi

b19-log note "HEALTH-LIMIT-TEST" "$(_p "Test %s: the failure reason is stored for the state change" "3")"
STATE="$(</tmp/b19-test-health-limit/state/healthcheck.d/reported.0100-check-noisy.sh)"
if [ "${STATE}" = "fail boom" ]; then
    b19-log good "HEALTH-LIMIT-TEST" "$(_p "Test %s passed" "3")"
else
    fail "$(_p "Unexpected stored state: %s" "${STATE}")"
fi

b19-log note "HEALTH-LIMIT-TEST" "$(_p "Test %s: a repeated failure reaches the container log once" "4")"
LINES="$(grep --count --fixed-strings 'Check failed: 0100-check-noisy.sh: boom' /tmp/b19-test-health-limit/container.log)"
if [ "${LINES}" = "1" ]; then
    b19-log good "HEALTH-LIMIT-TEST" "$(_p "Test %s passed" "4")"
else
    fail "$(_p "Container log holds the failure %s times" "${LINES}")"
fi

b19-log note "HEALTH-LIMIT-TEST" "$(_p "Test %s: checks run in numeric order, not text order" "5")"
mkdir --parents /tmp/b19-test-health-limit/ordered
printf '%s\n' 'exit 0' >/tmp/b19-test-health-limit/ordered/10-check-second.sh
printf '%s\n' 'exit 0' >/tmp/b19-test-health-limit/ordered/9-check-first.sh
ORDER="$(env "B19_HEALTH_PATH=/tmp/b19-test-health-limit/ordered" "B19_TEMP_PATH=/tmp/b19-test-health-limit/state" "B19_VERBOSITY=info" healthcheck.d 2>&1 | grep --only-matching 'Executing check: .*' | tr '\n' ' ')"
if [ "${ORDER}" = "Executing check: 9-check-first.sh Executing check: 10-check-second.sh " ]; then
    b19-log good "HEALTH-LIMIT-TEST" "$(_p "Test %s passed" "5")"
else
    fail "$(_p "Unexpected check order: %s" "${ORDER}")"
fi

rm --recursive --force /tmp/b19-test-health-limit
b19-log good "HEALTH-LIMIT-TEST" "$(_ "All healthcheck output tests passed")"
