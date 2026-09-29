#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test healthcheck.d tiers: detached first run, cached verdict, failure reported, no per-probe run.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "HEALTH-TIER-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

mkdir --parents /tmp/b19-test-health-tiers/checks/hourly /tmp/b19-test-health-tiers/state
printf '%s\n' 'echo run >>/tmp/b19-test-health-tiers/runs' >/tmp/b19-test-health-tiers/checks/hourly/0100-check-tier-counted.sh

# Probe an isolated check tree whose verdicts land in an isolated state directory
probe() {
    env "B19_HEALTH_PATH=/tmp/b19-test-health-tiers/checks" "B19_TEMP_PATH=/tmp/b19-test-health-tiers/state" \
        "B19_HEALTH_HOURLY_INTERVAL=3600" healthcheck.d 2>&1
}

# Waits up to 10 s for the background run to write the verdict of check $1
await_verdict() {
    local _i
    for _i in $(seq 1 20); do
        if [ -f "/tmp/b19-test-health-tiers/state/healthcheck.d/$1.verdict" ]; then
            return 0
        fi
        sleep 0.5
    done
    fail "$(_p "No verdict for %s after %s attempts" "$1" "${_i}")"
}

b19-log note "HEALTH-TIER-TEST" "$(_p "Test %s: first probe passes while the verdict is pending" "1")"
if TEST_OUTPUT="$(probe)"; then
    b19-log good "HEALTH-TIER-TEST" "$(_p "Test %s passed" "1")"
else
    fail "$(_ "Pending tier check failed the probe")"
fi
await_verdict 0100-check-tier-counted.sh

b19-log note "HEALTH-TIER-TEST" "$(_p "Test %s: fresh verdict is reused, not re-run" "2")"
TEST_OUTPUT="$(probe)" || fail "$(_ "Cached passing verdict failed the probe")"
RUNS="$(wc --lines </tmp/b19-test-health-tiers/runs)"
if [ "${RUNS}" -eq 1 ]; then
    b19-log good "HEALTH-TIER-TEST" "$(_p "Test %s passed" "2")"
else
    fail "$(_p "Tier check ran %s times in two probes" "${RUNS}")"
fi

b19-log note "HEALTH-TIER-TEST" "$(_p "Test %s: failing verdict fails the probe" "3")"
printf '%s\n' 'exit 3' >/tmp/b19-test-health-tiers/checks/hourly/0200-check-tier-failing.sh
TEST_OUTPUT="$(probe)" || fail "$(_ "Pending tier check failed the probe")"
await_verdict 0200-check-tier-failing.sh
if TEST_OUTPUT="$(probe)"; then
    fail "$(_ "Failing tier verdict passed the probe")"
elif [[ "${TEST_OUTPUT}" == *0200-check-tier-failing.sh* ]]; then
    b19-log good "HEALTH-TIER-TEST" "$(_p "Test %s passed" "3")"
else
    fail "$(_ "Probe failed without naming the tier check")"
fi

rm --recursive --force /tmp/b19-test-health-tiers
b19-log good "HEALTH-TIER-TEST" "$(_ "All healthcheck tier tests passed")"
