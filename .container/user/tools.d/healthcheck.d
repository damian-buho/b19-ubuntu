#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    # Skip all checks if healthcheck is disabled
    if [ "${B19_HEALTH_ENABLED:-}" = "false" ]; then
      exit 0
    fi

    # Prevent overlapping healthcheck executions
    LOCKFILE="/tmp/healthcheck.d.lock"
    exec 9>"${LOCKFILE}"
    if ! flock -n 9; then
      exit 0
    fi

    # Enable safer bash scripting
    set -euo pipefail

    # Color only on an interactive console: b19-log "auto" mode checks [ -t 2 ],
    # so a TTY gets color while docker inspect (captured, no TTY) and file
    # redirects stay plain text automatically.
    export B19_COLOR=auto

    # shellcheck source=.container/foundation/tools.d/b19-i18n
    . b19-i18n

    # Load secrets into environment (healthchecks run outside entrypoint context)
    # shellcheck source=.container/foundation/tools.d/b19-load-secrets
    . b19-load-secrets

    CHECKS_PATH="/healthcheck.d"
    FINAL_EXIT_CODE=0  # Tracks the number of failed checks
    FAILED_NAMES=""    # Space-separated basenames of failed checks, for callers

    if [ -d "${CHECKS_PATH}" ]; then
      b19-log info "HEALTH.D" "$(_ "Checks directory found")"

      # Find and sort scripts in the CHECKS_PATH directory
      CHECKS_COUNT=0
      while IFS= read -r -d '' CHECK; do
        CHECKS_COUNT=$((CHECKS_COUNT + 1))

        SKIP_NAME=$(basename "${CHECK}" .sh)
        SKIP_NAME="${SKIP_NAME#*[0-9]-}"
        SKIP_VAR="B19_HEALTH_SKIP_$(echo "${SKIP_NAME}" | tr '[:lower:]-' '[:upper:]_')"
        if [ "${!SKIP_VAR:-}" = "true" ]; then
          b19-log note "HEALTH.D" "$(_p "Skipped: %s (via %s)" "${SKIP_NAME}" "${SKIP_VAR}")"
          continue
        fi

        b19-log info "HEALTH.D" "$(_ "Executing check:") $(basename "${CHECK}")"

        # Execute the check (subshell inherits _() and other functions).
        # Run it as an `if` condition so a failing check does NOT trip `set -e`
        # in the parent — an unguarded `( . ... )` would abort the whole loop
        # before the "Check failed" line and the final summary could be logged,
        # which is why the last check's result message was silently swallowed.
        # shellcheck disable=SC1090
        if ( . "${CHECK}" ); then
          b19-log good "HEALTH.D" "$(_ "Check passed:") $(basename "${CHECK}")"
        else
          _CHECK_EXIT=$?
          _CHECK_NAME=$(basename "${CHECK}")
          b19-log bad "HEALTH.D" "$(_ "Check failed:") ${_CHECK_NAME} $(_ "with exit code") ${_CHECK_EXIT}"
          FINAL_EXIT_CODE=$((FINAL_EXIT_CODE + 1))  # Increment failed checks counter
          FAILED_NAMES="${FAILED_NAMES:+${FAILED_NAMES} }${_CHECK_NAME}"
        fi
      done < <(fd --print0 --hidden --type file --extension sh . "${CHECKS_PATH}" | sort --zero-terminated --numeric-sort)

      # Handle the case where no scripts are found
      if [ "${CHECKS_COUNT}" -eq 0 ]; then
        b19-log note "HEALTH.D" "$(_ "No health checks found in") ${CHECKS_PATH}"
      fi
    else
      b19-log note "HEALTH.D" "$(_ "Checks directory not found at") ${CHECKS_PATH}"
    fi

    # Final log and exit
    if [ "${FINAL_EXIT_CODE}" -gt 0 ]; then
      b19-log bad "HEALTH.D" "$(_p "%d of %d checks failed: %s" "${FINAL_EXIT_CODE}" "${CHECKS_COUNT}" "${FAILED_NAMES}")"
    else
      b19-log good "HEALTH.D" "$(_p "All %d checks passed." "${CHECKS_COUNT}")"
    fi

    # Compact, unfiltered, locale-independent verdict on STDOUT (b19-log writes to
    # stderr): the space-separated names of the checks that failed. A caller such
    # as test.d can surface *what* is unhealthy even though the per-check "Check
    # failed" lines log at `bad`, below the default verbosity. Empty stdout == all
    # checks passed. An explicit `if` (not `[ ] && ...`) keeps `set -e` happy when
    # nothing failed.
    if [ "${FINAL_EXIT_CODE}" -gt 0 ]; then
      printf '%s\n' "${FAILED_NAMES}"
    fi

    exit "${FINAL_EXIT_CODE}"
