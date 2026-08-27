#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test b19-log verbosity filtering via B19_VERBOSITY

set -eou pipefail

# shellcheck source=/dev/null
. b19-i18n

# On assertion failure, surface the captured output (always, at error level) so a
# CI flake is diagnosable in one glance instead of a bare "filtering incorrect".
fail() {
  b19-log error "b19-verbosity" "$1"
  b19-log error "b19-verbosity" "$(_ "Captured output was:")"
  printf '%s\n' "${TEST_OUTPUT:-}" >&2
  exit 1
}

b19-log good "b19-verbosity" "$(_ "Starting verbosity tests")"

# Test 1: error level (only error visible)
b19-log note "b19-verbosity" "$(_ "Test 1: error level filtering")"
TEST_OUTPUT=$(B19_VERBOSITY=error bash -c '
  b19-log error TEST "error message" 2>&1
  b19-log bad TEST "bad message" 2>&1
  b19-log warn TEST "warn message" 2>&1
  b19-log good TEST "good message" 2>&1
  b19-log info TEST "info message" 2>&1
  b19-log note TEST "note message" 2>&1
')

if echo "${TEST_OUTPUT}" | grep -q "error message" &&       \
   ! echo "${TEST_OUTPUT}" | grep -q "bad message" &&       \
   ! echo "${TEST_OUTPUT}" | grep -q "warn message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "good message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "info message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "note message"; then
  b19-log good "b19-verbosity" "$(_ "Test 1 passed: error level shows only error")"
else
  fail "$(_ "Test 1 failed: error level filtering incorrect")"
fi

# Test 2: warn level (error/warn visible, bad/good/info/note hidden)
b19-log note "b19-verbosity" "$(_ "Test 2: warn level filtering")"
TEST_OUTPUT=$(B19_VERBOSITY=warn bash -c '
  b19-log error TEST "error message" 2>&1
  b19-log bad TEST "bad message" 2>&1
  b19-log warn TEST "warn message" 2>&1
  b19-log good TEST "good message" 2>&1
  b19-log info TEST "info message" 2>&1
  b19-log note TEST "note message" 2>&1
')

if echo "${TEST_OUTPUT}" | grep -q "error message" &&       \
   ! echo "${TEST_OUTPUT}" | grep -q "bad message" &&       \
   echo "${TEST_OUTPUT}" | grep -q "warn message" &&        \
   ! echo "${TEST_OUTPUT}" | grep -q "good message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "info message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "note message"; then
  b19-log good "b19-verbosity" "$(_ "Test 2 passed: warn level shows error/warn only")"
else
  fail "$(_ "Test 2 failed: warn level filtering incorrect")"
fi

# Test 3: info level (error/bad/warn/good/info visible, note hidden)
b19-log note "b19-verbosity" "$(_ "Test 3: info level filtering")"
TEST_OUTPUT=$(B19_VERBOSITY=info bash -c '
  b19-log error TEST "error message" 2>&1
  b19-log bad TEST "bad message" 2>&1
  b19-log warn TEST "warn message" 2>&1
  b19-log good TEST "good message" 2>&1
  b19-log info TEST "info message" 2>&1
  b19-log note TEST "note message" 2>&1
')

if echo "${TEST_OUTPUT}" | grep -q "error message" &&     \
   echo "${TEST_OUTPUT}" | grep -q "bad message" &&       \
   echo "${TEST_OUTPUT}" | grep -q "warn message" &&      \
   echo "${TEST_OUTPUT}" | grep -q "good message" &&      \
   echo "${TEST_OUTPUT}" | grep -q "info message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "note message"; then
  b19-log good "b19-verbosity" "$(_ "Test 3 passed: info level shows all except note")"
else
  fail "$(_ "Test 3 failed: info level filtering incorrect")"
fi

# Test 4: debug level (all messages visible)
b19-log note "b19-verbosity" "$(_ "Test 4: debug level filtering")"
TEST_OUTPUT=$(B19_VERBOSITY=debug bash -c '
  b19-log error TEST "error message" 2>&1
  b19-log bad TEST "bad message" 2>&1
  b19-log warn TEST "warn message" 2>&1
  b19-log good TEST "good message" 2>&1
  b19-log info TEST "info message" 2>&1
  b19-log note TEST "note message" 2>&1
')

if echo "${TEST_OUTPUT}" | grep -q "error message" &&     \
   echo "${TEST_OUTPUT}" | grep -q "bad message" &&       \
   echo "${TEST_OUTPUT}" | grep -q "warn message" &&      \
   echo "${TEST_OUTPUT}" | grep -q "good message" &&      \
   echo "${TEST_OUTPUT}" | grep -q "info message" &&      \
   echo "${TEST_OUTPUT}" | grep -q "note message"; then
  b19-log good "b19-verbosity" "$(_ "Test 4 passed: debug level shows all messages")"
else
  fail "$(_ "Test 4 failed: debug level filtering incorrect")"
fi

# Test 5: Invalid level (defaults to warn)
b19-log note "b19-verbosity" "$(_ "Test 5: Invalid level defaults to warn")"
TEST_OUTPUT=$(B19_VERBOSITY=INVALID bash -c '
  b19-log warn TEST "warn message" 2>&1
  b19-log good TEST "good message" 2>&1
')

if echo "${TEST_OUTPUT}" | grep -q "warn message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "good message"; then
  b19-log good "b19-verbosity" "$(_ "Test 5 passed: Invalid level defaults to warn")"
else
  fail "$(_ "Test 5 failed: Invalid level did not default to warn")"
fi

# Test 6: Default behavior (unset B19_VERBOSITY should be warn)
b19-log note "b19-verbosity" "$(_ "Test 6: Default behavior")"
TEST_OUTPUT=$(bash -c 'unset B19_VERBOSITY; b19-log warn TEST "warn message" 2>&1; b19-log good TEST "good message" 2>&1')

if echo "${TEST_OUTPUT}" | grep -q "warn message" &&      \
   ! echo "${TEST_OUTPUT}" | grep -q "good message"; then
  b19-log good "b19-verbosity" "$(_ "Test 6 passed: Default level is warn")"
else
  fail "$(_ "Test 6 failed: Default level incorrect")"
fi

# Test 7: a captured (NO_COLOR) line names its own level — without it a warn and
# an info are byte-identical in reports/*.log and no grep can tell them apart.
b19-log note "b19-verbosity" "$(_ "Test 7: plain output carries the level")"
TEST_OUTPUT=$(NO_COLOR=1 B19_VERBOSITY=debug bash -c '
  b19-log warn TEST "warn message" 2>&1
  b19-log info TEST "info message" 2>&1
  echo "payload line" | b19-log info TEST 2>&1
')

if echo "${TEST_OUTPUT}" | grep -q "^ WARN .*warn message" &&       \
   echo "${TEST_OUTPUT}" | grep -q "^ INFO .*info message" &&       \
   ! echo "${TEST_OUTPUT}" | grep -q "INFO.*payload line"; then
  b19-log good "b19-verbosity" "$(_ "Test 7 passed: plain output carries the level")"
else
  fail "$(_ "Test 7 failed: plain output lost the level")"
fi

b19-log good "b19-verbosity" "$(_ "All verbosity tests passed")"
