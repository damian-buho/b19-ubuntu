#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test healthcheck.d consecutive-failure counting without reaching the PID 1 threshold.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

mkdir --parents /tmp/b19-test-health-exit/checks /tmp/b19-test-health-exit/state
printf '%s\n' 'exit 3' >/tmp/b19-test-health-exit/checks/0100-check-failing.sh

# Probes an isolated check tree with a threshold no test run reaches
probe() {
    env "B19_HEALTH_PATH=/tmp/b19-test-health-exit/checks" "B19_TEMP_PATH=/tmp/b19-test-health-exit/state" \
        "B19_HEALTH_EXIT_AFTER=1000" "B19_HEALTH_EXIT_GRACE=0" healthcheck.d >/dev/null 2>&1 || true
}

# Prints the stored consecutive-failure count
count() {
    cat /tmp/b19-test-health-exit/state/healthcheck.d/consecutive-failures
}

probe
probe
[ "$(count)" -eq 2 ] || { b19-log error "HEALTH-EXIT-TEST" "$(_p "Expected 2 failures, counted %s" "$(count)")"; exit 1; }

rm --force /tmp/b19-test-health-exit/checks/0100-check-failing.sh
probe
[ "$(count)" -eq 0 ] || { b19-log error "HEALTH-EXIT-TEST" "$(_p "A passing probe left %s failures" "$(count)")"; exit 1; }

rm --recursive --force /tmp/b19-test-health-exit
b19-log good "HEALTH-EXIT-TEST" "$(_ "Consecutive failures counted and reset")"
