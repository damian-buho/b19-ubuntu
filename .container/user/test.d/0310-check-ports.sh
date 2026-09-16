#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test check-ports: WHATWG blocklist, privileged range, and NET_BIND_SERVICE.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "PORT-CHECK-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

# Run check-ports with only the given assignments visible, capturing output.
run_check() {
    env -i "PATH=${PATH}" "B19_HOME=${B19_HOME}" "$@" check-ports 2>&1
}

# Kernel truth: root or CAP_NET_BIND_SERVICE (CapEff bit 10) binds <1024.
can_bind_privileged() {
    if [ "$(id -u)" = "0" ]; then
        return 0
    fi
    local _cap
    _cap="$(awk '/^CapEff:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    case "${_cap:-}" in
        ''|*[!0-9a-fA-F]*) return 1 ;;
    esac
    if (( 16#"${_cap}" & 16#400 )); then
        return 0
    fi
    return 1
}

# A skipped check would pass everything, so refuse a vacuous run.
if [ ! -f "${B19_HOME}/.forbidden-ports.txt" ]; then
    fail "$(_ "Forbidden ports list missing, cannot test")"
fi

b19-log note "PORT-CHECK-TEST" "$(_p "Test %s: safe high port passes" "1")"
if TEST_OUTPUT="$(run_check "B19_TEST_APP_PORT=8080")"; then
    b19-log good "PORT-CHECK-TEST" "$(_p "Test %s passed" "1")"
else
    fail "$(_ "Safe high port was rejected")"
fi

b19-log note "PORT-CHECK-TEST" "$(_p "Test %s: WHATWG-blocked port fails" "2")"
if TEST_OUTPUT="$(run_check "B19_TEST_APP_PORT=6000")"; then
    fail "$(_ "WHATWG-blocked port was allowed")"
else
    b19-log good "PORT-CHECK-TEST" "$(_p "Test %s passed" "2")"
fi

b19-log note "PORT-CHECK-TEST" "$(_p "Test %s: port 0 passes" "3")"
if TEST_OUTPUT="$(run_check "B19_TEST_APP_PORT=0")"; then
    b19-log good "PORT-CHECK-TEST" "$(_p "Test %s passed" "3")"
else
    fail "$(_ "Port 0 was rejected")"
fi

b19-log note "PORT-CHECK-TEST" "$(_p "Test %s: privileged port follows the kernel" "4")"
if can_bind_privileged; then
    if TEST_OUTPUT="$(run_check "B19_TEST_HTTPS_PORT=443")"; then
        b19-log good "PORT-CHECK-TEST" "$(_p "Test %s passed" "4")"
    else
        fail "$(_ "Privileged port verdict disagrees with the kernel")"
    fi
else
    if TEST_OUTPUT="$(run_check "B19_TEST_HTTPS_PORT=443")"; then
        fail "$(_ "Privileged port verdict disagrees with the kernel")"
    else
        b19-log good "PORT-CHECK-TEST" "$(_p "Test %s passed" "4")"
    fi
fi

b19-log note "PORT-CHECK-TEST" "$(_p "Test %s: disabled check passes" "5")"
if TEST_OUTPUT="$(run_check "B19_PORT_CHECK_ENABLED=false" "B19_TEST_APP_PORT=6000")"; then
    b19-log good "PORT-CHECK-TEST" "$(_p "Test %s passed" "5")"
else
    fail "$(_ "Disabled check still rejected the port")"
fi

b19-log good "PORT-CHECK-TEST" "$(_ "All check-ports tests passed")"
