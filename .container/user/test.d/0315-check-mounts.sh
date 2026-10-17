#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test check-mounts: mounted vs unmounted volume paths.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "MOUNT-CHECK-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

VOLFILE="${XDG_CACHE_HOME}/b19-mount-check-test.volumes"
UNMOUNTED="/opt/b19-mount-check-unmounted"

b19-log note "MOUNT-CHECK-TEST" "$(_p "Test %s: mounted path produces no warning" "1")"
printf '/dev/shm\n' > "${VOLFILE}"
TEST_OUTPUT="$(B19_MOUNT_CHECK_FILE="${VOLFILE}" check-mounts 2>&1)" || fail "$(_ "Mounted path check failed")"
if printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings "${UNMOUNTED}"; then
    fail "$(_ "Unexpected unmounted warning")"
fi
b19-log good "MOUNT-CHECK-TEST" "$(_p "Test %s passed" "1")"

b19-log note "MOUNT-CHECK-TEST" "$(_p "Test %s: unmounted path is logged" "2")"
printf '/dev/shm\n%s required\n' "${UNMOUNTED}" > "${VOLFILE}"
TEST_OUTPUT="$(B19_MOUNT_CHECK_FILE="${VOLFILE}" check-mounts 2>&1)" || fail "$(_ "Unmounted path check failed unexpectedly")"
printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings "${UNMOUNTED}" \
    || fail "$(_ "Unmounted path was not logged")"
b19-log good "MOUNT-CHECK-TEST" "$(_p "Test %s passed" "2")"

b19-log note "MOUNT-CHECK-TEST" "$(_p "Test %s: B19_REQUIRE_MOUNTS fails on required path" "3")"
if TEST_OUTPUT="$(B19_MOUNT_CHECK_FILE="${VOLFILE}" B19_REQUIRE_MOUNTS=Y check-mounts 2>&1)"; then
    fail "$(_ "Required mount check did not fail")"
else
    printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings "${UNMOUNTED}" \
        || fail "$(_ "Unmounted path was not logged")"
fi
b19-log good "MOUNT-CHECK-TEST" "$(_p "Test %s passed" "3")"

b19-log note "MOUNT-CHECK-TEST" "$(_p "Test %s: B19_SKIP_MOUNT_CHECK disables the hook" "4")"
TEST_OUTPUT="$(B19_MOUNT_CHECK_FILE="${VOLFILE}" B19_SKIP_MOUNT_CHECK=Y check-mounts 2>&1)" || fail "$(_ "Disabled check failed")"
if printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings "${UNMOUNTED}"; then
    fail "$(_ "Disabled check still logged the path")"
fi
b19-log good "MOUNT-CHECK-TEST" "$(_p "Test %s passed" "4")"

rm -f "${VOLFILE}"
b19-log good "MOUNT-CHECK-TEST" "$(_ "All mount-check tests passed")"
