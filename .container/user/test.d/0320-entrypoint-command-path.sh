#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test both command spellings pass secret validation and bootstrap before anything runs.

set -euo pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
    b19-log error "COMMAND-PATH-TEST" "$1"
    printf '%s\n' "${TEST_OUTPUT:-}" >&2
    exit 1
}

# An empty bootstrap.d whose runner proves it ran by creating the lock directory
mkdir --parents /tmp/b19-test-command-path/bootstrap

# Source the base command-path hooks only, so a downstream start hook never runs here
run_path() {
    rm --recursive --force /tmp/b19-test-command-path/lock
    env "B19_REQUIRED_SECRETS=" "B19_BOOTSTRAP_ENABLED=true" \
        "B19_BOOTSTRAP_PATH=/tmp/b19-test-command-path/bootstrap" \
        "B19_BOOTSTRAP_LOCK_PATH=/tmp/b19-test-command-path/lock" \
        "$@" 2>&1
}

# shellcheck disable=SC2016 # hooks sourced in entrypoint.d order, expanded by the child bash
HOOKS='set -euo pipefail; . b19-i18n
for h in 2000-select-command 2100-validate-secrets 3000-bootstrap 4000-run-command 9000-finalize; do
  . "/entrypoint.d/${h}.sh"
done'

b19-log note "COMMAND-PATH-TEST" "$(_p "Test %s: explicit command runs after bootstrap" "1")"
if TEST_OUTPUT="$(run_path bash -c "${HOOKS}" entrypoint.d test -d /tmp/b19-test-command-path/lock)"; then
    b19-log good "COMMAND-PATH-TEST" "$(_p "Test %s passed" "1")"
else
    fail "$(_ "Explicit command ran before bootstrap")"
fi

b19-log note "COMMAND-PATH-TEST" "$(_p "Test %s: single-command subcommand reaches bootstrap" "2")"
TEST_OUTPUT="$(run_path "B19_SINGLE_COMMAND_IMAGE=Y" bash -c "${HOOKS}" entrypoint.d b19-not-a-command)" || true
if [ -d /tmp/b19-test-command-path/lock ]; then
    b19-log good "COMMAND-PATH-TEST" "$(_p "Test %s passed" "2")"
else
    fail "$(_ "Single-command subcommand skipped bootstrap")"
fi

b19-log note "COMMAND-PATH-TEST" "$(_p "Test %s: missing secret fails the explicit command" "3")"
if TEST_OUTPUT="$(run_path "B19_SECRETS_ENABLED=true" "B19_REQUIRED_SECRETS=b19.test.command.path" bash -c "${HOOKS}" entrypoint.d true)"; then
    fail "$(_ "Explicit command ran without a required secret")"
else
    b19-log good "COMMAND-PATH-TEST" "$(_p "Test %s passed" "3")"
fi

b19-log note "COMMAND-PATH-TEST" "$(_p "Test %s: missing secret fails the single-command subcommand" "4")"
if TEST_OUTPUT="$(run_path "B19_SECRETS_ENABLED=true" "B19_REQUIRED_SECRETS=b19.test.command.path" "B19_SINGLE_COMMAND_IMAGE=Y" bash -c "${HOOKS}" entrypoint.d b19-not-a-command)" \
    || [ -d /tmp/b19-test-command-path/lock ]; then
    fail "$(_ "Single-command subcommand reached bootstrap without a required secret")"
else
    b19-log good "COMMAND-PATH-TEST" "$(_p "Test %s passed" "4")"
fi

b19-log note "COMMAND-PATH-TEST" "$(_p "Test %s: unknown command fails before bootstrap" "5")"
TEST_OUTPUT="$(run_path bash -c "${HOOKS}" entrypoint.d b19-not-a-command)" && TEST_CODE=0 || TEST_CODE=$?
if [ "${TEST_CODE}" = 127 ] && [ ! -d /tmp/b19-test-command-path/lock ]; then
    b19-log good "COMMAND-PATH-TEST" "$(_p "Test %s passed" "5")"
else
    fail "$(_p "Unknown command exited %s or reached bootstrap" "${TEST_CODE}")"
fi

rm --recursive --force /tmp/b19-test-command-path
b19-log good "COMMAND-PATH-TEST" "$(_ "All command-path tests passed")"
