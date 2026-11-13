#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test healthcheck.d reports not ready while the pid in bootstrap.d.pid runs.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

ROOT="/tmp/b19-test-health-bootstrap.$$"
mkdir --parents "${ROOT}/checks" "${ROOT}/state" "${ROOT}/runtime"

# Probes an isolated, check-free tree and prints "<exit code> <gated|ran>"
probe() {
    local _code=0 _log
    _log=$(env "B19_HEALTH_PATH=${ROOT}/checks" "B19_TEMP_PATH=${ROOT}/state" "B19_RUNTIME_PATH=${ROOT}/runtime" \
        "B19_VERBOSITY=info" healthcheck.d 2>&1) || _code=$?
    if [[ ${_log} == *"still running: reporting not ready"* ]]; then echo "${_code} gated"; else echo "${_code} ran"; fi
}

# Fails naming the case when the probe answers anything but EXPECTED
expect() {
    local _actual
    _actual=$(probe)
    b19-log info "HEALTH-BOOTSTRAP-TEST" "$(_p "Case %s: expected %s, got %s" "$1" "$2" "${_actual}")"
    b19-assert equals "HEALTH-BOOTSTRAP-TEST" "$2" "${_actual}"
}

expect "no marker" "0 ran"

printf '%s\n' "$$" >"${ROOT}/runtime/bootstrap.d.pid"
expect "live pid $$" "1 gated"

true &
DEAD_PID=$!
wait "${DEAD_PID}"
printf '%s\n' "${DEAD_PID}" >"${ROOT}/runtime/bootstrap.d.pid"
expect "dead pid ${DEAD_PID}" "0 ran"

printf '%s\n' "not-a-pid" >"${ROOT}/runtime/bootstrap.d.pid"
expect "garbage" "0 ran"

: >"${ROOT}/runtime/bootstrap.d.pid"
expect "empty" "0 ran"

rm --recursive --force "${ROOT}"
b19-log good "HEALTH-BOOTSTRAP-TEST" "$(_ "Bootstrap gate holds while bootstrap runs and only then")"
