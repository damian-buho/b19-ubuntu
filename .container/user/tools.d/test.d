#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    # Enable safer bash scripting
    set -o pipefail  # Note: Removed `-e` to ensure all tests run, even if one fails

    # shellcheck source=.container/foundation/tools.d/b19-i18n
    . b19-i18n

    # Skip tests if disabled
    if [ "${B19_TEST_ENABLED:-}" = "false" ]; then
      b19-log warn "TEST.D" "$(_ "Tests disabled") (B19_TEST_ENABLED=false)"
      exit 0
    fi

    # Initialize variables
    FINAL_EXIT_CODE=0
    FAILED_TESTS=0

    b19-log info "TEST.D" "$(_ "Reading from:") ${B19_TEST_PATH}"

    B19_TEST_TIMEOUT="${B19_TEST_TIMEOUT:-60}"
    ELAPSED=0
    # Capture the gate's STDOUT verdict (space-separated names of the still-failing
    # checks) so a timeout can name what stayed unhealthy instead of dying dark:
    # the per-check failures log at `bad`, below the default verbosity, and stderr
    # is dropped here anyway. Reported at `error` so the verdict clears the default
    # threshold and actually prints.
    UNHEALTHY=""
    while ! UNHEALTHY="$(healthcheck.d 2>/dev/null)"; do
      if [ "${ELAPSED}" -ge "${B19_TEST_TIMEOUT}" ]; then
        b19-log error "TEST.D" "$(_p "Healthcheck did not pass within %s seconds" "${B19_TEST_TIMEOUT}")"
        b19-log error "TEST.D" "$(_p "Unhealthy checks: %s" "${UNHEALTHY:-unknown}")"
        exit 1
      fi
      b19-log warn "TEST.D" "$(_p "Waiting for healthcheck... %ss elapsed" "${ELAPSED}")"
      sleep 1
      ELAPSED=$((ELAPSED + 1))
    done
    b19-log good "TEST.D" "$(_ "Healthcheck passed. Starting tests.")"

    # Check if the tests directory exists
    if [ -d "${B19_TEST_PATH}" ]; then
      b19-log info "TEST.D" "$(_ "Directory found:") ${B19_TEST_PATH}"

      # Find and sort test scripts in descending order
      TESTS_COUNT=0
      while IFS= read -r -d '' TEST; do
        TESTS_COUNT=$((TESTS_COUNT + 1))
        BASENAME=$(basename "${TEST}")
        b19-run "TEST.D" "$(_ "Executing:") ${BASENAME}" -- "${TEST}"

        # Capture the exit code of the test
        EXIT_CODE=$?
        if [ "${EXIT_CODE}" -ne 0 ]; then
          FINAL_EXIT_CODE=1
          FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
      done < <(fd --print0 --hidden --type file --extension sh . "${B19_TEST_PATH}" | sort --zero-terminated --numeric-sort --reverse)

      # Handle case where no test scripts are found
      if [ "${TESTS_COUNT}" -eq 0 ]; then
        b19-log warn "TEST.D" "$(_ "No test scripts found in") ${B19_TEST_PATH}"
      fi
    else
      b19-log warn "TEST.D" "$(_ "Directory not found:") ${B19_TEST_PATH}"
    fi

    # Log the final result
    if [ "${FINAL_EXIT_CODE}" -ne 0 ]; then
      b19-log error "TEST.D" "$(_p "%d of %d tests failed. Final exit code: %d" "${FAILED_TESTS}" "${TESTS_COUNT}" "${FINAL_EXIT_CODE}")"
    else
      b19-log good "TEST.D" "$(_p "All %d tests passed." "${TESTS_COUNT}")"
    fi

exit "${FINAL_EXIT_CODE}"