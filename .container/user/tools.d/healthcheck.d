#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    # Skip all checks if healthcheck is disabled
    if [ "${B19_HEALTH_ENABLED:-}" = "false" ]; then
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

    # Wait for an overlapping run instead of answering for it
    # shellcheck source=.container/foundation/tools.d/b19-lock
    . b19-lock
    if ! b19_lock "HEALTH.D" "/tmp/healthcheck.d.lock" "${B19_HEALTH_LOCK_TIMEOUT:-4}"; then
      echo "healthcheck.d.lock"
      exit 1
    fi

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

    CHECKS_PATH="${B19_HEALTH_PATH:-/healthcheck.d}"
    FINAL_EXIT_CODE=0  # Tracks the number of failed checks
    FAILED_NAMES=""    # Space-separated basenames of failed checks, for callers

    # NUMPROCS is unset here — a healthcheck is a fresh daemon-spawned process,
    # not the entrypoint tree that exports it — so detect it directly. Caps
    # concurrency: a 0.5-CPU container must not fork one background check per
    # script.
    # shellcheck source=.container/foundation/tools.d/detect-cpu-count
    . detect-cpu-count
    b19-log debug "HEALTH.D" "$(_p "Parallel check cap (NUMPROCS): %s" "${NUMPROCS}")"

    # Upper-snake key of a check name, as used by B19_HEALTH_SKIP_<KEY> and B19_HEALTH_INTERVAL_<KEY>
    check_key() {
      local _name
      _name=$(basename "$1" .sh)
      _name="${_name#*[0-9]-}"
      echo "${_name}" | tr '[:lower:]-' '[:upper:]_'
    }

    # Logs and succeeds when B19_HEALTH_SKIP_<KEY>=true mutes this check
    check_skipped() {
      local _var
      _var="B19_HEALTH_SKIP_$(check_key "$1")"
      if [ "${!_var:-}" = "true" ]; then
        b19-log note "HEALTH.D" "$(_p "Skipped: %s (via %s)" "$(basename "$1")" "${_var}")"
        return 0
      fi
      return 1
    }

    TIER_STATE_PATH="${B19_TEMP_PATH:-/tmp}/healthcheck.d"

    # Runs a tier check detached from the probe, then swaps in its verdict atomically
    refresh_tier_check() {
      local _check="$1" _state="$2" _code=0
      exec 8>"${_state}.lock"
      flock --nonblock 8 || return 0
      # shellcheck disable=SC2016 # the child bash sources the check with its own helpers loaded
      timeout --kill-after=5 "${B19_HEALTH_TIER_TIMEOUT}" \
        bash -c 'set -euo pipefail; . b19-i18n; . b19-load-secrets; . detect-cpu-count; . "$1"' healthcheck.d "${_check}" \
        >"${_state}.log" 2>&1 || _code=$?
      printf '%s %s\n%s\n' "$(date +%s)" "${_code}" "$(tail --lines=1 "${_state}.log")" >"${_state}.verdict.${BASHPID}"
      mv --force "${_state}.verdict.${BASHPID}" "${_state}.verdict"
    }

    # Answers a tier check from its last verdict and refreshes it in the background once due
    report_tier_check() {
      local _check="$1" _interval="$2" _state _at="" _code="" _log="" _age _due
      _state="${TIER_STATE_PATH}/$(basename "${_check}")"
      if [ -f "${_state}.verdict" ]; then
        { read -r _at _code; IFS= read -r _log || true; } <"${_state}.verdict"
      fi
      if ! [[ "${_at}" =~ ^[0-9]+$ && "${_code}" =~ ^[0-9]+$ ]]; then
        b19-log info "HEALTH.D" "$(_p "No verdict yet for %s, running it in the background" "$(basename "${_check}")")"
        ( refresh_tier_check "${_check}" "${_state}" ) </dev/null >/dev/null 2>&1 9>&- &
        disown
        return 0
      fi
      _age=$(( $(date +%s) - _at ))
      _due="${_interval}"
      if [ "${_code}" -ne 0 ] && [ "${B19_HEALTH_RETRY_INTERVAL}" -lt "${_due}" ]; then
        _due="${B19_HEALTH_RETRY_INTERVAL}"
      fi
      if [ "${_age}" -ge "${_due}" ]; then
        b19-log info "HEALTH.D" "$(_p "Stale verdict for %s (%s s old, due every %s s), re-running" "$(basename "${_check}")" "${_age}" "${_due}")"
        ( refresh_tier_check "${_check}" "${_state}" ) </dev/null >/dev/null 2>&1 9>&- &
        disown
      else
        b19-log info "HEALTH.D" "$(_p "Cached verdict for %s (%s s old): %s" "$(basename "${_check}")" "${_age}" "${_log}")"
      fi
      return "${_code}"
    }

    declare -A PID_NAMES=()
    # Stop checks still running when we exit, so none outlives its probe
    trap 'kill "${!PID_NAMES[@]}" 2>/dev/null || true; b19_unlock' EXIT
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

        if check_skipped "${CHECK}"; then
          continue
        fi

        b19-log info "HEALTH.D" "$(_ "Executing check:") ${CHECK_BASENAME}"

        # Launch in the background, </dev/null so a check that reads stdin
        # cannot drain the process-substitution pipe the outer loop still
        # reads its remaining paths from (same trap as process-hooks).
        # shellcheck disable=SC1090
        ( . "${CHECK}" ) </dev/null 9>&- &
        CHECK_PID=$!
        PID_NAMES[${CHECK_PID}]="${CHECK_BASENAME}"
        RUNNING=$((RUNNING + 1))

        if [ "${RUNNING}" -ge "${NUMPROCS}" ]; then
          reap_one_check
        fi
      done < <(fd --print0 --hidden --type file --extension sh --max-depth 1 . "${CHECKS_PATH}" | sort --zero-terminated --numeric-sort)

      while [ "${RUNNING}" -gt 0 ]; do
        reap_one_check
      done

      # Each subdirectory is a tier whose checks run at most once per B19_HEALTH_<TIER>_INTERVAL
      while IFS= read -r -d '' TIER_DIR; do
        TIER_VAR="B19_HEALTH_$(basename "${TIER_DIR}" | tr '[:lower:]-' '[:upper:]_')_INTERVAL"
        if [ -z "${!TIER_VAR:-}" ]; then
          b19-log warn "HEALTH.D" "$(_p "Ignoring tier %s: %s is not set" "${TIER_DIR}" "${TIER_VAR}")"
          continue
        fi
        mkdir --parents "${TIER_STATE_PATH}"
        while IFS= read -r -d '' CHECK; do
          CHECKS_COUNT=$((CHECKS_COUNT + 1))
          if check_skipped "${CHECK}"; then
            continue
          fi
          INTERVAL_VAR="B19_HEALTH_INTERVAL_$(check_key "${CHECK}")"
          if report_tier_check "${CHECK}" "${!INTERVAL_VAR:-${!TIER_VAR}}"; then
            b19-log good "HEALTH.D" "$(_ "Check passed:") $(basename "${CHECK}")"
          else
            b19-log bad "HEALTH.D" "$(_ "Check failed:") $(basename "${CHECK}")"
            FINAL_EXIT_CODE=$((FINAL_EXIT_CODE + 1))
            FAILED_LIST+=("$(basename "${CHECK}")")
          fi
        done < <(fd --print0 --hidden --type file --extension sh --max-depth 1 . "${TIER_DIR}" | sort --zero-terminated --numeric-sort)
      done < <(fd --print0 --hidden --type directory --max-depth 1 . "${CHECKS_PATH}" | sort --zero-terminated)

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
