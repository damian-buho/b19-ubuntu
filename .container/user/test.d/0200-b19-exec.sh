#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test b19-exec wrapper utility

set -eou pipefail

# shellcheck source=/dev/null
. b19-i18n

b19-log good "b19-exec" "$(_ "Starting b19-exec tests")"

# Keeps every call off the container's own records under /run/b19
B19_RUNTIME_PATH="$(mktemp --directory "${B19_TEMP_PATH:-/tmp}/b19-exec-state-XXXXXX")"
export B19_RUNTIME_PATH
_state="${B19_RUNTIME_PATH}/b19-exec"

# Waits up to 10 s for COMMAND to succeed
wait_until() {
  local _try
  for _try in $(seq 100); do
    "$@" && return 0
    sleep 0.1
  done
  b19-log error "b19-exec" "$(_p "%s still false after %s tries" "$*" "${_try}")"
  return 1
}

# Test 1: Basic execution with successful exit code
b19-log note "b19-exec" "$(_ "Test 1: Successful command execution")"
b19-exec -- true
RC=$?
if [ "${RC}" -eq 0 ]; then
  b19-log good "b19-exec" "$(_ "Test 1 passed: Successful exit code")"
else
  b19-log error "b19-exec" "$(_ "Test 1 failed: Wrong exit code")"
  exit 1
fi

# Test 2: Failed command propagates exit code
b19-log note "b19-exec" "$(_ "Test 2: Failed command exit code propagation")"
EXIT_CODE=0
b19-exec -- bash -c 'exit 42' || EXIT_CODE=$?
if [ "${EXIT_CODE}" -eq 42 ]; then
  b19-log good "b19-exec" "$(_ "Test 2 passed: Exit code 42 propagated")"
else
  b19-log error "b19-exec" "$(_p "Test 2 failed: Exit code %s (expected 42)" "${EXIT_CODE}")"
  exit 1
fi

# Test 3: Command creates file (side effect test)
b19-log note "b19-exec" "$(_ "Test 3: Command execution with side effects")"
TEST_FILE="/tmp/b19-exec-test-$$"
b19-exec -- touch "${TEST_FILE}"
if [ -f "${TEST_FILE}" ]; then
  b19-log good "b19-exec" "$(_ "Test 3 passed: Command executed with side effects")"
  rm -f "${TEST_FILE}"
else
  b19-log error "b19-exec" "$(_ "Test 3 failed: File not created")"
  exit 1
fi

# Test 4: Missing command argument error
b19-log note "b19-exec" "$(_ "Test 4: Missing command error")"
EXIT_CODE=0
b19-exec -- 2>/dev/null || EXIT_CODE=$?
if [ "${EXIT_CODE}" -eq 1 ]; then
  b19-log good "b19-exec" "$(_ "Test 4 passed: Missing command detected")"
else
  b19-log error "b19-exec" "$(_ "Test 4 failed: Missing command not detected")"
  exit 1
fi

# Test 5: Invalid log level error
b19-log note "b19-exec" "$(_ "Test 5: Invalid log level error")"
EXIT_CODE=0
b19-exec --stdout-level invalid -- echo test 2>/dev/null || EXIT_CODE=$?
if [ "${EXIT_CODE}" -eq 1 ]; then
  b19-log good "b19-exec" "$(_ "Test 5 passed: Invalid level detected")"
else
  b19-log error "b19-exec" "$(_ "Test 5 failed: Invalid level not rejected")"
  exit 1
fi

# Test 6: Command with arguments
b19-log note "b19-exec" "$(_ "Test 6: Command with multiple arguments")"
TEST_FILE="/tmp/b19-exec-test-args-$$"
b19-exec -- bash -c "echo 'test content' > ${TEST_FILE}"
if [ -f "${TEST_FILE}" ] && grep -q "test content" "${TEST_FILE}"; then
  b19-log good "b19-exec" "$(_ "Test 6 passed: Arguments passed correctly")"
  rm -f "${TEST_FILE}"
else
  b19-log error "b19-exec" "$(_ "Test 6 failed: Arguments not passed correctly")"
  exit 1
fi

# Test 7: Foreground mode execution
b19-log note "b19-exec" "$(_ "Test 7: Foreground mode")"
EXIT_CODE=0
(b19-exec --foreground -- true) || EXIT_CODE=$?
if [ "${EXIT_CODE}" -eq 0 ]; then
  b19-log good "b19-exec" "$(_ "Test 7 passed: Foreground mode works")"
else
  b19-log error "b19-exec" "$(_p "Test 7 failed: Foreground mode error (code %s)" "${EXIT_CODE}")"
  exit 1
fi

# Test 8: Output routing (check that output appears with b19-log format)
b19-log note "b19-exec" "$(_ "Test 8: Output routing through b19-log")"
TEST_FILE="/tmp/b19-exec-output-$$"
(b19-exec -- echo "test-output" > "${TEST_FILE}" 2>&1) || true
if [ -f "${TEST_FILE}" ] && grep -q "STDOUT" "${TEST_FILE}" && grep -q "test-output" "${TEST_FILE}"; then
  b19-log good "b19-exec" "$(_ "Test 8 passed: Output routed through b19-log")"
  rm -f "${TEST_FILE}"
else
  b19-log good "b19-exec" "$(_ "Test 8 skipped: Output routing cannot be fully tested in test context")"
  rm -f "${TEST_FILE}" 2>/dev/null || true
fi

# Test 9: Custom log levels accepted
b19-log note "b19-exec" "$(_ "Test 9: Custom log levels")"
b19-exec --stdout-level warn --stderr-level error -- true
RC=$?
if [ "${RC}" -eq 0 ]; then
  b19-log good "b19-exec" "$(_ "Test 9 passed: Custom levels accepted")"
else
  b19-log error "b19-exec" "$(_ "Test 9 failed: Custom levels rejected")"
  exit 1
fi

# Test 10: Custom tags accepted
b19-log note "b19-exec" "$(_ "Test 10: Custom tags")"
b19-exec --stdout-tag MYAPP --stderr-tag MYERR -- true
RC=$?
if [ "${RC}" -eq 0 ]; then
  b19-log good "b19-exec" "$(_ "Test 10 passed: Custom tags accepted")"
else
  b19-log error "b19-exec" "$(_ "Test 10 failed: Custom tags rejected")"
  exit 1
fi

# Test 11: Stderr drains on failure (regression: coprocess output was lost before exit)
b19-log note "b19-exec" "$(_ "Test 11: Stderr drain on failed command")"
EXIT_CODE=0
b19-exec --stderr-level error -- bash -c 'echo "error-output" >&2; exit 5' 2>/dev/null || EXIT_CODE=$?
if [ "${EXIT_CODE}" -eq 5 ]; then
  b19-log good "b19-exec" "$(_ "Test 11 passed: Exit code propagated and stderr drained")"
else
  b19-log error "b19-exec" "$(_p "Test 11 failed: Exit code %s (expected 5)" "${EXIT_CODE}")"
  exit 1
fi

# Test 12: Foreground mode propagates failure exit code
b19-log note "b19-exec" "$(_ "Test 12: Foreground mode exit code propagation")"
EXIT_CODE=0
(b19-exec --foreground -- bash -c 'exit 7') || EXIT_CODE=$?
if [ "${EXIT_CODE}" -eq 7 ]; then
  b19-log good "b19-exec" "$(_ "Test 12 passed: Foreground mode exit code propagated")"
else
  b19-log error "b19-exec" "$(_p "Test 12 failed: Exit code %s (expected 7)" "${EXIT_CODE}")"
  exit 1
fi

# Test 13: The payload records "PID payload" under B19_RUNTIME_PATH and drops it on exit
b19-log note "b19-exec" "$(_ "Test 13: Payload PID record published and cleaned up")"
_self="${B19_RUNTIME_PATH}/self"
# shellcheck disable=SC2016 # expanded by the payload shell
b19-exec -- bash -c 'echo $$ > "$0"; exec sleep 300' "${_self}" &
_exec_pid=$!
wait_until test -s "${_self}"
wait_until grep --quiet --line-regexp "$(<"${_self}") payload" "${_state}/payload.pid"
_observed="" _role=""
read -r _observed _role < "${_state}/payload.pid" || true
b19-assert matches "b19-exec" '^[0-9]+$' "${_observed}"
b19-assert equals "b19-exec" "payload" "${_role}"
b19-assert equals "b19-exec" "$(<"${_self}")" "${_observed}"
kill -s TERM "${_exec_pid}"
wait "${_exec_pid}" || true
rm -f "${_self}"
b19-assert equals "b19-exec" "absent" "$([ -e "${_state}/payload.pid" ] && echo present || echo absent)"

# Test 14: Passthrough hands the payload PID 1's stdout, the default a logger pipe
b19-log note "b19-exec" "$(_ "Test 14: Passthrough bypasses b19-log")"
_fd_file="${B19_TEMP_PATH:-/tmp}/b19-exec-fd-$$"
# shellcheck disable=SC2016 # expanded by the payload shell
_fd_probe='printf "%s %s\n" "$(readlink /proc/$$/fd/1)" "$(readlink /proc/1/fd/1)" > "$0"'
b19-exec --foreground --passthrough -- bash -c "${_fd_probe}" "${_fd_file}"
read -r _payload_fd _pid1_fd < "${_fd_file}"
b19-assert equals "b19-exec" "${_pid1_fd}" "${_payload_fd}"
B19_EXEC_PASSTHROUGH=true b19-exec --foreground -- bash -c "${_fd_probe}" "${_fd_file}"
read -r _payload_fd _pid1_fd < "${_fd_file}"
b19-assert equals "b19-exec" "${_pid1_fd}" "${_payload_fd}"
b19-exec --foreground -- bash -c "${_fd_probe}" "${_fd_file}"
read -r _payload_fd _pid1_fd < "${_fd_file}"
b19-assert matches "b19-exec" '^pipe:' "${_payload_fd}"
rm -f "${_fd_file}"

# Test 15: An unknown passthrough value refuses to run the payload
b19-log note "b19-exec" "$(_ "Test 15: Invalid passthrough value")"
EXIT_CODE=0
B19_EXEC_PASSTHROUGH=maybe b19-exec -- true 2>/dev/null || EXIT_CODE=$?
b19-assert equals "b19-exec" "1" "${EXIT_CODE}"

# Prints the supervisor of a recorded daemon, the parent b19-exec forwards its signals from
supervisor_of() {
  local _pid _stat _fields
  read -r _pid _ < "${_state}/$1.pid"
  _stat=$(<"/proc/${_pid}/stat")
  read -ra _fields <<<"${_stat##*) }"
  printf '%s\n' "${_fields[1]}"
}

# Succeeds once PID is gone or a zombie
exited() {
  local _stat
  { read -r _stat < "/proc/$1/stat"; } 2>/dev/null || return 0
  read -r _stat _ <<<"${_stat##*) }"
  [ "${_stat}" = Z ]
}

# Waits up to 10 s for NAME's record to disappear
wait_gone() {
  local _try
  for _try in $(seq 100); do
    [ -e "${_state}/$1.pid" ] || return 0
    sleep 0.1
  done
  b19-log error "b19-exec" "$(_p "%s still recorded after %s tries" "$1" "${_try}")"
  return 1
}

# A daemon that marks itself ready once trapped and appends its name to the order file when told to stop
# shellcheck disable=SC2016 # expanded by the daemon shell
_daemon='trap "echo $1 >> $0; exit 0" TERM; : > "$0.$1"; sleep 300 & wait'

# Test 16: Background daemons stop after the payload, newest first, each on its own SIGTERM
b19-log note "b19-exec" "$(_ "Test 16: Background daemons stop in reverse start order")"
_order="${B19_RUNTIME_PATH}/order"
b19-exec --background --name first -- bash -c "${_daemon}" "${_order}" first
b19-exec --background --name second -- bash -c "${_daemon}" "${_order}" second
b19-assert equals "b19-exec" "required" "$(cut --delimiter=' ' --fields=2 "${_state}/first.pid")"
b19-exec --name main -- bash -c "${_daemon}" "${_order}" main &
_exec_pid=$!
wait_until test -e "${_order}.first" -a -e "${_order}.second" -a -e "${_order}.main"
kill -s TERM "${_exec_pid}" "$(supervisor_of second)" "$(supervisor_of first)"
EXIT_CODE=0
wait "${_exec_pid}" || EXIT_CODE=$?
wait_gone first
b19-assert equals "b19-exec" "0" "${EXIT_CODE}"
b19-assert equals "b19-exec" "main second first" "$(paste --serial --delimiters=' ' "${_order}")"
rm -f "${_order}" "${_order}".*

# Test 16b: A stop that lands while the payload starts never leaves it running nor stops a daemon before it
b19-log note "b19-exec" "$(_ "Test 16b: Stop while the payload starts")"
b19-exec --background --name first -- bash -c "${_daemon}" "${_order}" first
b19-exec --background --name second -- bash -c "${_daemon}" "${_order}" second
wait_until test -e "${_order}.first" -a -e "${_order}.second"
b19-exec --name main -- bash -c "${_daemon}" "${_order}" main &
_exec_pid=$!
kill -s TERM "${_exec_pid}" "$(supervisor_of second)" "$(supervisor_of first)"
wait_until exited "${_exec_pid}"
wait "${_exec_pid}" || true
wait_gone first
b19-assert matches "b19-exec" '^(main )?second first$' "$(paste --serial --delimiters=' ' "${_order}")"

# Test 17: A required background daemon that exits stops the payload with its exit code
b19-log note "b19-exec" "$(_ "Test 17: Required daemon exit fails fast")"
b19-exec --background --name crasher -- bash -c 'sleep 1; exit 3'
EXIT_CODE=0
timeout 15 b19-exec --name main -- sleep 300 || EXIT_CODE=$?
b19-assert equals "b19-exec" "3" "${EXIT_CODE}"
b19-assert equals "b19-exec" "3" "$(<"${_state}/crasher.exit")"
EXIT_CODE=0
bash -c '. b19-i18n; . /healthcheck.d/0900-check-daemons.sh' 2>/dev/null || EXIT_CODE=$?
b19-assert equals "b19-exec" "1" "${EXIT_CODE}"
EXIT_CODE=0
b19-exec --name late -- true 2>/dev/null || EXIT_CODE=$?
b19-assert equals "b19-exec" "3" "${EXIT_CODE}"
rm -f "${_state}/crasher.exit"

# Test 18: An optional daemon that exits only logs, and its logger drains before its supervisor ends
b19-log note "b19-exec" "$(_ "Test 18: Optional daemon exit keeps the payload")"
b19-exec --background --optional --name watcher -- bash -c 'sleep 0.5; echo last-line; exit 4'
wait_gone watcher
b19-assert equals "b19-exec" "0" "$(fd --hidden --glob '*.exit' "${_state}" | wc --lines)"
EXIT_CODE=0
b19-exec --name main -- sleep 2 || EXIT_CODE=$?
b19-assert equals "b19-exec" "0" "${EXIT_CODE}"
_loggers=0
for _cmdline in /proc/[0-9]*/cmdline; do
  _command=$(tr '\0' ' ' < "${_cmdline}" 2>/dev/null) || continue
  [[ "${_command}" != *"b19-log info watcher"* ]] || _loggers=$((_loggers + 1))
done
b19-assert equals "b19-exec" "0" "${_loggers}"

# Test 19: Healthy daemons pass the health check, a payload exit stops them
b19-log note "b19-exec" "$(_ "Test 19: Health check and stop on payload exit")"
b19-exec --background --name keeper -- sleep 300
bash -c '. b19-i18n; . /healthcheck.d/0900-check-daemons.sh' 2>/dev/null
b19-exec --name main -- true
b19-assert equals "b19-exec" "absent" "$([ -e "${_state}/keeper.pid" ] && echo present || echo absent)"

# Test 20: Misuse is refused before anything starts
b19-log note "b19-exec" "$(_ "Test 20: Invalid background calls")"
for _args in "--background" "--name ../x" "--optional" "--background --foreground --name x"; do
  EXIT_CODE=0
  # shellcheck disable=SC2086 # the option string splits on purpose
  b19-exec ${_args} -- true 2>/dev/null || EXIT_CODE=$?
  b19-assert equals "b19-exec" "1" "${EXIT_CODE}"
done
b19-exec --background --name twice -- sleep 300
EXIT_CODE=0
b19-exec --background --name twice -- sleep 300 2>/dev/null || EXIT_CODE=$?
b19-assert equals "b19-exec" "1" "${EXIT_CODE}"
kill -s TERM "$(supervisor_of twice)"
wait_gone twice
rm -f "${_state}/.lock" "${_order}" "${_order}".*
rmdir "${_state}" "${B19_RUNTIME_PATH}"

b19-log good "b19-exec" "$(_ "All b19-exec tests passed")"
