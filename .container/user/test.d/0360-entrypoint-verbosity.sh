#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test B19_ENTRYPOINT_VERBOSITY quiets the lifecycle hooks and hands the command its own level.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "ENTRY-VERBOSITY-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

# shellcheck disable=SC2016 # hooks sourced in entrypoint.d order, expanded by the child bash
HOOKS='set -euo pipefail; . b19-i18n
for h in 0005-set-verbosity 2000-select-command 2100-validate-secrets 3000-bootstrap 4000-run-command 9000-finalize; do
  . "/entrypoint.d/${h}.sh"
done'

# Run the hooks with no secrets and no bootstrap, so only verbosity varies
run_hooks() {
    env "NO_COLOR=1" "B19_REQUIRED_SECRETS=" "B19_BOOTSTRAP_ENABLED=false" "$@" 2>&1
}

b19-log note "ENTRY-VERBOSITY-TEST" "$(_p "Test %s: lifecycle quiet, command keeps its level" "1")"
TEST_OUTPUT="$(run_hooks "B19_VERBOSITY=info" "B19_ENTRYPOINT_VERBOSITY=warn" \
    bash -c "${HOOKS}" entrypoint.d b19-run "PAYLOAD" "payload step" -- echo b19-payload-output)" \
    || fail "$(_ "Command failed under a lifecycle verbosity")"
printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings 'b19-payload-output' \
    || fail "$(_ "Command output hidden under a lifecycle verbosity")"
if printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings 'ENTRY.D'; then
    fail "$(_ "Lifecycle line shown under a lifecycle verbosity")"
fi
b19-log good "ENTRY-VERBOSITY-TEST" "$(_p "Test %s passed" "1")"

b19-log note "ENTRY-VERBOSITY-TEST" "$(_p "Test %s: unset keeps one level for both" "2")"
TEST_OUTPUT="$(run_hooks "B19_VERBOSITY=info" bash -c "${HOOKS}" entrypoint.d true)" \
    || fail "$(_ "Command failed without a lifecycle verbosity")"
printf '%s\n' "${TEST_OUTPUT}" | grep --quiet --fixed-strings 'ENTRY.D' \
    || fail "$(_ "Lifecycle line hidden without a lifecycle verbosity")"
b19-log good "ENTRY-VERBOSITY-TEST" "$(_p "Test %s passed" "2")"

b19-log note "ENTRY-VERBOSITY-TEST" "$(_p "Test %s: a re-run keeps the first payload level" "3")"
# shellcheck disable=SC2016 # sourced twice like a remap re-exec, expanded by the child bash
TEST_OUTPUT="$(run_hooks "B19_VERBOSITY=info" "B19_ENTRYPOINT_VERBOSITY=warn" bash -c '. b19-i18n
. /entrypoint.d/0005-set-verbosity.sh; . /entrypoint.d/0005-set-verbosity.sh; printf "%s\n" "${ENTRYPOINT_PAYLOAD_VERBOSITY}"')" \
    || fail "$(_ "Repeated verbosity hook failed")"
[ "${TEST_OUTPUT}" = "info" ] || fail "$(_p "Payload level became %s after a re-run" "${TEST_OUTPUT}")"
b19-log good "ENTRY-VERBOSITY-TEST" "$(_p "Test %s passed" "3")"

b19-log good "ENTRY-VERBOSITY-TEST" "$(_ "All entrypoint verbosity tests passed")"
