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

    # Drain gate: a deploy touches this file on the OUTGOING container so it
    # reports not-ready and Traefik's health filter routes around it, while the
    # container keeps serving requests already in flight. Checked before any
    # check runs — draining must win over every check result.
    if [ -f "${B19_HEALTH_DRAIN_FILE}" ]; then
      b19-log warn "HEALTH.D" "$(_p "Draining via %s: reporting not ready" "${B19_HEALTH_DRAIN_FILE}")"
      exit 1
    fi

    CHECKS_PATH="/healthcheck.d"
    FINAL_EXIT_CODE=0  # Tracks the number of failed checks
    FAILED_NAMES=""    # Space-separated basenames of failed checks, for callers

    # NUMPROCS is unset here — a healthcheck is a fresh daemon-spawned process,
    # not the entrypoint tree that exports it — so detect it directly. Caps
    # concurrency: a 0.5-CPU container must not fork one background check per
    # script.
    # shellcheck source=.container/foundation/tools.d/detect-cpu-count
    . detect-cpu-count
    b19-log debug "HEALTH.D" "$(_p "Parallel check cap (NUMPROCS): %s" "${NUMPROCS}")"

    declare -A PID_NAMES=()
    declare -a FAILED_LIST=()
    RUNNING=0

    # Waits for the next background check to finish. Run as an `if` condition
    # so a failing check's non-zero `wait` does not trip `set -e` before the
    # summary can be logged — same reasoning as the check execution below.
    reap_one_check() {
      local FINISHED_PID CHECK_EXIT CHECK_NAME
      if wait -n -p FINISHED_PID; then
        CHECK_EXIT=0
      else
        CHECK_EXIT=$?
      fi
      CHECK_NAME="${PID_NAMES[${FINISHED_PID}]}"
      unset "PID_NAMES[${FINISHED_PID}]"
      RUNNING=$((RUNNING - 1))
      if [ "${CHECK_EXIT}" -eq 0 ]; then
        b19-log good "HEALTH.D" "$(_ "Check passed:") ${CHECK_NAME}"
      else
        b19-log bad "HEALTH.D" "$(_ "Check failed:") ${CHECK_NAME} $(_ "with exit code") ${CHECK_EXIT}"
        FINAL_EXIT_CODE=$((FINAL_EXIT_CODE + 1))  # Increment failed checks counter
        FAILED_LIST+=("${CHECK_NAME}")
      fi
    }

    if [ -d "${CHECKS_PATH}" ]; then
      b19-log info "HEALTH.D" "$(_ "Checks directory found")"

      # Find and sort scripts in the CHECKS_PATH directory
      CHECKS_COUNT=0
      while IFS= read -r -d '' CHECK; do
        CHECK_BASENAME=$(basename "${CHECK}")
        CHECKS_COUNT=$((CHECKS_COUNT + 1))

        SKIP_NAME=$(basename "${CHECK}" .sh)
        SKIP_NAME="${SKIP_NAME#*[0-9]-}"
        SKIP_VAR="B19_HEALTH_SKIP_$(echo "${SKIP_NAME}" | tr '[:lower:]-' '[:upper:]_')"
        if [ "${!SKIP_VAR:-}" = "true" ]; then
          b19-log note "HEALTH.D" "$(_p "Skipped: %s (via %s)" "${SKIP_NAME}" "${SKIP_VAR}")"
          continue
        fi

        b19-log info "HEALTH.D" "$(_ "Executing check:") ${CHECK_BASENAME}"

        # Launch in the background, </dev/null so a check that reads stdin
        # cannot drain the process-substitution pipe the outer loop still
        # reads its remaining paths from (same trap as process-hooks).
        # shellcheck disable=SC1090
        ( . "${CHECK}" ) </dev/null &
        CHECK_PID=$!
        PID_NAMES[${CHECK_PID}]="${CHECK_BASENAME}"
        RUNNING=$((RUNNING + 1))

        if [ "${RUNNING}" -ge "${NUMPROCS}" ]; then
          reap_one_check
        fi
      done < <(fd --print0 --hidden --type file --extension sh . "${CHECKS_PATH}" | sort --zero-terminated --numeric-sort)

      while [ "${RUNNING}" -gt 0 ]; do
        reap_one_check
      done

      # Handle the case where no scripts are found
      if [ "${CHECKS_COUNT}" -eq 0 ]; then
        b19-log note "HEALTH.D" "$(_ "No health checks found in") ${CHECKS_PATH}"
      fi
    else
      b19-log note "HEALTH.D" "$(_ "Checks directory not found at") ${CHECKS_PATH}"
    fi

    # Sort — parallel checks finish in a non-deterministic order, but the
    # stdout contract callers rely on (test.d) must stay deterministic.
    if [ "${#FAILED_LIST[@]}" -gt 0 ]; then
      readarray -t FAILED_LIST < <(printf '%s\n' "${FAILED_LIST[@]}" | sort)
      FAILED_NAMES="${FAILED_LIST[*]}"
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
