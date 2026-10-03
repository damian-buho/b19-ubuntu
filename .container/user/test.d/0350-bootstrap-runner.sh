#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test bootstrap.d runs a script once, honours its skip flag, fails on its error and stays idle when empty.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "BOOTSTRAP-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

# Fixtures live in the cache, since /tmp may be mounted noexec
TEST_ROOT="${XDG_CACHE_HOME}/b19-test-bootstrap"
rm --recursive --force "${TEST_ROOT}"
mkdir --parents "${TEST_ROOT}/empty" "${TEST_ROOT}/scripts"
printf '#!/usr/bin/env bash\ntouch "%s/marker"\n' "${TEST_ROOT}" > "${TEST_ROOT}/scripts/100-mark.sh"
chmod +x "${TEST_ROOT}/scripts/100-mark.sh"

# Run the runner against one fixture directory and the shared lock path
run_bootstrap() {
    env "B19_BOOTSTRAP_ENABLED=true" "B19_BOOTSTRAP_PATH=${TEST_ROOT}/$1" \
        "B19_BOOTSTRAP_LOCK_PATH=${TEST_ROOT}/lock" "${@:2}" bootstrap.d 2>&1
}

b19-log note "BOOTSTRAP-TEST" "$(_p "Test %s: empty directory creates no lock" "1")"
TEST_OUTPUT="$(run_bootstrap empty)" || fail "$(_ "Empty bootstrap directory failed")"
[ ! -e "${TEST_ROOT}/lock" ] || fail "$(_ "Empty bootstrap directory created a lock directory")"
b19-log good "BOOTSTRAP-TEST" "$(_p "Test %s passed" "1")"

b19-log note "BOOTSTRAP-TEST" "$(_p "Test %s: skip flag leaves the script unrun" "2")"
TEST_OUTPUT="$(run_bootstrap scripts "B19_BOOTSTRAP_SKIP_MARK=true")" || fail "$(_ "Skipped bootstrap failed")"
[ ! -e "${TEST_ROOT}/marker" ] || fail "$(_ "Skipped bootstrap script ran")"
b19-log good "BOOTSTRAP-TEST" "$(_p "Test %s passed" "2")"

b19-log note "BOOTSTRAP-TEST" "$(_p "Test %s: script runs and is locked" "3")"
TEST_OUTPUT="$(run_bootstrap scripts)" || fail "$(_ "Bootstrap failed")"
[ -f "${TEST_ROOT}/marker" ] || fail "$(_ "Bootstrap script did not run")"
[ -f "${TEST_ROOT}/lock/.100-mark.bootstrap" ] || fail "$(_ "Bootstrap script was not locked")"
b19-log good "BOOTSTRAP-TEST" "$(_p "Test %s passed" "3")"

b19-log note "BOOTSTRAP-TEST" "$(_p "Test %s: locked script does not run again" "4")"
rm --force "${TEST_ROOT}/marker"
TEST_OUTPUT="$(run_bootstrap scripts)" || fail "$(_ "Repeated bootstrap failed")"
[ ! -e "${TEST_ROOT}/marker" ] || fail "$(_ "Locked bootstrap script ran again")"
b19-log good "BOOTSTRAP-TEST" "$(_p "Test %s passed" "4")"

b19-log note "BOOTSTRAP-TEST" "$(_p "Test %s: failing script fails the runner unlocked" "5")"
printf '#!/usr/bin/env bash\nexit 3\n' > "${TEST_ROOT}/scripts/200-broken.sh"
chmod +x "${TEST_ROOT}/scripts/200-broken.sh"
if TEST_OUTPUT="$(run_bootstrap scripts)"; then
    fail "$(_ "Failing bootstrap script passed")"
fi
[ ! -e "${TEST_ROOT}/lock/.200-broken.bootstrap" ] || fail "$(_ "Failing bootstrap script was locked")"
b19-log good "BOOTSTRAP-TEST" "$(_p "Test %s passed" "5")"

rm --recursive --force "${TEST_ROOT}"
b19-log good "BOOTSTRAP-TEST" "$(_ "All bootstrap tests passed")"
