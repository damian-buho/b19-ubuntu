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

    # shellcheck source=/dev/null
    . b19-i18n

    # shellcheck source=/dev/null
    . b19-skip

    # A filtered log line costs no process
    # shellcheck source=/dev/null
    . b19-log-filter

    TIER_STATE_PATH="${B19_TEMP_PATH:-/tmp}/healthcheck.d"
    OUTPUT_LIMIT="${B19_HEALTH_OUTPUT_LIMIT:-4096}"
    RUN_DIR="${TIER_STATE_PATH}/run.$$"
    mkdir --parents "${RUN_DIR}"
    # A probe Docker killed leaves its run dir behind, so each probe sweeps the ones whose probe is gone
    for _stale in "${TIER_STATE_PATH}"/run.*; do
      if ! [ -d "${_stale}" ] || [ "${_stale}" = "${RUN_DIR}" ] || [ -e "/proc/${_stale##*.}" ]; then continue; fi
      rm --force -- "${_stale}"/*.out "${_stale}"/log.*
      rmdir -- "${_stale}" 2>/dev/null || b19-log debug "HEALTH.D" "$(_p "Cannot remove %s yet" "${_stale}")"
    done

    # Docker keeps only the first B19_HEALTH_OUTPUT_LIMIT bytes of a probe's output, so the log waits in an unlinked file and follows the verdict
    exec 3>&2
    if ! [ -t 2 ]; then
      LOG_FILE=$(mktemp "${RUN_DIR}/log.XXXXXX")
      exec 4<"${LOG_FILE}"
      exec 2>"${LOG_FILE}"
      unlink "${LOG_FILE}"
    fi

    # Writes the buffered log to the real stderr, cut so $1 verdict bytes and the log fit the output limit
    flush_log() {
      local _room=$(( OUTPUT_LIMIT - $1 ))
      [ "${_room}" -gt 0 ] || _room=0
      { head --bytes="${_room}" <&4 >&3; } 2>/dev/null || true
    }

    # Writes FILE atomically with CONTENT, so a probe killed mid-write never leaves it empty
    write_atomic() {
      printf '%s\n' "$2" >"$1.$$"
      mv --force "$1.$$" "$1"
    }

    # Wait for an overlapping run, and answer with the last finished verdict when it outlasts the wait
    LAST_VERDICT="${TIER_STATE_PATH}/last-verdict"
    # shellcheck source=/dev/null
    . b19-lock
    if ! b19_lock "HEALTH.D" "${B19_TEMP_PATH:-/tmp}/healthcheck.d.lock" "${B19_HEALTH_LOCK_TIMEOUT:-4}"; then
      _last_code="" _last_names=""
      { read -r _last_code; IFS= read -r _last_names || true; } 2>/dev/null <"${LAST_VERDICT}" || true
      if [[ "${_last_code}" =~ ^[0-9]+$ ]]; then
        b19-log info "HEALTH.D" "$(_p "Another probe holds the lock, repeating the last verdict %s" "${_last_code}")"
        [ -z "${_last_names}" ] || printf '%s\n' "${_last_names}"
        flush_log "$(( ${#_last_names} + 1 ))"
        rmdir -- "${RUN_DIR}" 2>/dev/null || true
        exit "${_last_code}"
      fi
      echo "healthcheck.d.lock"
      flush_log 19
      rmdir -- "${RUN_DIR}" 2>/dev/null || true
      exit 1
    fi

    # The entrypoint already warned about each binary secret, so this run and its checks stay quiet
    export B19_SECRETS_QUIET=true

    # Load secrets into environment (healthchecks run outside entrypoint context)
    # shellcheck source=/dev/null
    . b19-load-secrets

    # Drain gate: a deploy touches this file on the OUTGOING container so it
    # reports not-ready and Traefik's health filter routes around it, while the
    # container keeps serving requests already in flight. Checked before any
    # check runs — draining must win over every check result.
    if [ -f "${B19_HEALTH_DRAIN_FILE}" ]; then
      b19-log warn "HEALTH.D" "$(_p "Draining via %s: reporting not ready" "${B19_HEALTH_DRAIN_FILE}")"
      flush_log 0
      exit 1
    fi

    CHECKS_PATH="${B19_HEALTH_PATH:-/healthcheck.d}"
    FINAL_EXIT_CODE=0  # Tracks the number of failed checks
    FAILED_NAMES=""    # Space-separated basenames of failed checks, for callers

    # NUMPROCS is unset here — a healthcheck is a fresh daemon-spawned process,
    # not the entrypoint tree that exports it — so detect it directly. Caps
    # concurrency: a 0.5-CPU container must not fork one background check per
    # script.
    # shellcheck source=/dev/null
    . detect-cpu-count
    b19-log debug "HEALTH.D" "$(_p "Parallel check cap (NUMPROCS): %s" "${NUMPROCS}")"

    TIER_STATE_PATH="${B19_TEMP_PATH:-/tmp}/healthcheck.d"
    # A check's functions cross into its fresh bash, so it sources nothing twice
    export -f _ _e _p b19-log
    B19_HEALTH_LOG_TARGET="${B19_HEALTH_LOG_TARGET:-/proc/1/fd/2}"

    # Writes one warn line to PID 1's stderr (docker logs) when a check's state changes: $1 name, $2 pass|fail, $3 reason
    report_state() {
      local _name="$1" _now="$2" _why="$3" _file="${TIER_STATE_PATH}/reported.${1}" _was=""
      [ -f "${_file}" ] && _was=$(<"${_file}")
      [ "${_was}" = "${_now} ${_why}" ] && return 0
      write_atomic "${_file}" "${_now} ${_why}"
      if [ "${_now}" = "pass" ] && [ -z "${_was}" ]; then
        return 0
      fi
      if [ ! -w "${B19_HEALTH_LOG_TARGET}" ]; then
        b19-log debug "HEALTH.D" "$(_p "%s is not writable, not reporting %s" "${B19_HEALTH_LOG_TARGET}" "${_name}")"
        return 0
      fi
      if [ "${_now}" = "pass" ]; then
        b19-log warn "HEALTH.D" "$(_p "Check recovered: %s" "${_name}")" 2>>"${B19_HEALTH_LOG_TARGET}"
      else
        b19-log warn "HEALTH.D" "$(_p "Check failed: %s: %s" "${_name}" "${_why}")" 2>>"${B19_HEALTH_LOG_TARGET}"
      fi
    }

    # Runs one check in a fresh bash that timeout(1) kills, with its process group, after $2 seconds
    run_check() {
      # shellcheck disable=SC2016 # the child bash sources the check with its own helpers loaded
      timeout --kill-after=1 "$2" \
        bash -c 'set -euo pipefail; . b19-i18n; . "$1"' healthcheck.d "$1"
    }

    # Runs a tier check detached from the probe, then swaps in its verdict atomically
    refresh_tier_check() {
      local _check="$1" _state="$2" _code=0
      exec 8>"${_state}.lock"
      flock --nonblock 8 || return 0
      run_check "${_check}" "${B19_HEALTH_TIER_TIMEOUT}" >"${_state}.log" 2>&1 || _code=$?
      printf '%s %s\n%s\n' "${EPOCHSECONDS}" "${_code}" "$(tail --lines=1 "${_state}.log")" >"${_state}.verdict.${BASHPID}"
      mv --force "${_state}.verdict.${BASHPID}" "${_state}.verdict"
    }

    # Answers a tier check from its last verdict and refreshes it in the background once due
    report_tier_check() {
      local _check="$1" _interval="$2" _state _at="" _code="" _log="" _age _due
      TIER_REASON=""
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
      TIER_REASON="${_log}"
      _age=$(( EPOCHSECONDS - _at ))
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

    # Fills SCRIPTS with the *.sh files of $1, ordered by leading number then name, with no process
    list_scripts() {
      local _f _i _j _tmp
      SCRIPTS=()
      shopt -s nullglob dotglob
      for _f in "$1"/*.sh; do
        if [ -f "${_f}" ]; then SCRIPTS+=("${_f}"); fi
      done
      shopt -u nullglob dotglob
      for (( _i = 1; _i < ${#SCRIPTS[@]}; _i++ )); do
        _tmp="${SCRIPTS[_i]}"
        for (( _j = _i - 1; _j >= 0; _j-- )); do
          script_before "${_tmp}" "${SCRIPTS[_j]}" || break
          SCRIPTS[_j + 1]="${SCRIPTS[_j]}"
        done
        SCRIPTS[_j + 1]="${_tmp}"
      done
      b19-log debug "HEALTH.D" "$(_p "Listed %s scripts in %s" "${#SCRIPTS[@]}" "$1")"
    }

    # Succeeds when script $1 sorts before $2: leading number first, then name
    script_before() {
      local _a="${1##*/}" _b="${2##*/}" _na _nb
      _na="${_a%%[!0-9]*}"
      _nb="${_b%%[!0-9]*}"
      if [ $(( 10#${_na:-0} )) -ne $(( 10#${_nb:-0} )) ]; then
        [ $(( 10#${_na:-0} )) -lt $(( 10#${_nb:-0} )) ]
      else
        [[ "${_a}" < "${_b}" ]]
      fi
    }

    declare -A PID_NAMES=()
    # Stop checks still running when we exit, so none outlives its probe
    trap 'kill "${!PID_NAMES[@]}" 2>/dev/null || true; rmdir -- "${RUN_DIR}" 2>/dev/null || true; b19_unlock' EXIT
    declare -a FAILED_LIST=()
    RUNNING=0

    # Waits for the next background check to finish. Run as an `if` condition
    # so a failing check's non-zero `wait` does not trip `set -e` before the
    # summary can be logged — same reasoning as the check execution below.
    reap_one_check() {
      local FINISHED_PID CHECK_EXIT CHECK_NAME CHECK_WHY
      if wait -n -p FINISHED_PID "${!PID_NAMES[@]}"; then
        CHECK_EXIT=0
      else
        CHECK_EXIT=$?
      fi
      CHECK_NAME="${PID_NAMES[${FINISHED_PID}]}"
      unset "PID_NAMES[${FINISHED_PID}]"
      RUNNING=$((RUNNING - 1))
      [ ! -s "${RUN_DIR}/${CHECK_NAME}.out" ] || cat "${RUN_DIR}/${CHECK_NAME}.out" >&2
      CHECK_WHY=$(tail --lines=1 "${RUN_DIR}/${CHECK_NAME}.out")
      rm --force -- "${RUN_DIR}/${CHECK_NAME}.out"
      if [ "${CHECK_EXIT}" -eq 0 ]; then
        b19-log good "HEALTH.D" "$(_ "Check passed:") ${CHECK_NAME}"
        report_state "${CHECK_NAME}" pass ""
      elif [ "${CHECK_EXIT}" -eq 124 ]; then
        b19-log bad "HEALTH.D" "$(_p "Check timed out: %s (probe deadline %s s)" "${CHECK_NAME}" "${B19_HEALTH_CHECK_TIMEOUT}")"
        FINAL_EXIT_CODE=$((FINAL_EXIT_CODE + 1))
        FAILED_LIST+=("${CHECK_NAME}")
        report_state "${CHECK_NAME}" fail "$(_p "timed out after %s s" "${B19_HEALTH_CHECK_TIMEOUT}")"
      else
        b19-log bad "HEALTH.D" "$(_ "Check failed:") ${CHECK_NAME} $(_ "with exit code") ${CHECK_EXIT}"
        FINAL_EXIT_CODE=$((FINAL_EXIT_CODE + 1))  # Increment failed checks counter
        FAILED_LIST+=("${CHECK_NAME}")
        report_state "${CHECK_NAME}" fail "${CHECK_WHY:-exit code ${CHECK_EXIT}}"
      fi
    }

    if [ -d "${CHECKS_PATH}" ]; then
      b19-log info "HEALTH.D" "$(_ "Checks directory found")"

      # Find and sort scripts in the CHECKS_PATH directory
      CHECKS_COUNT=0
      # All inline checks share one deadline, so a queue of slow checks still ends inside Docker's probe timeout
      CHECKS_DEADLINE=$(( EPOCHSECONDS + B19_HEALTH_CHECK_TIMEOUT ))
      list_scripts "${CHECKS_PATH}"
      for CHECK in "${SCRIPTS[@]}"; do
        CHECK_BASENAME="${CHECK##*/}"
        CHECKS_COUNT=$((CHECKS_COUNT + 1))

        if b19_skipped note "HEALTH.D" B19_HEALTH_SKIP_ "${CHECK}"; then
          continue
        fi

        b19-log info "HEALTH.D" "$(_ "Executing check:") ${CHECK_BASENAME}"

        # Launch in the background, </dev/null so a check that reads stdin
        # cannot drain the process-substitution pipe the outer loop still
        # reads its remaining paths from (same trap as process-hooks).
        CHECK_BUDGET=$(( CHECKS_DEADLINE - EPOCHSECONDS ))
        [ "${CHECK_BUDGET}" -ge 1 ] || CHECK_BUDGET=1
        b19-log debug "HEALTH.D" "$(_p "Time budget for %s: %s s" "${CHECK_BASENAME}" "${CHECK_BUDGET}")"
        run_check "${CHECK}" "${CHECK_BUDGET}" </dev/null >"${RUN_DIR}/${CHECK_BASENAME}.out" 2>&1 9>&- &
        CHECK_PID=$!
        PID_NAMES[${CHECK_PID}]="${CHECK_BASENAME}"
        RUNNING=$((RUNNING + 1))

        if [ "${RUNNING}" -ge "${NUMPROCS}" ]; then
          reap_one_check
        fi
      done

      while [ "${RUNNING}" -gt 0 ]; do
        reap_one_check
      done

      # Each subdirectory is a tier whose checks run at most once per B19_HEALTH_<TIER>_INTERVAL
      shopt -s nullglob dotglob
      TIER_DIRS=("${CHECKS_PATH}"/*/)
      shopt -u nullglob dotglob
      for TIER_DIR in "${TIER_DIRS[@]%/}"; do
        TIER_VAR="B19_HEALTH_$(basename "${TIER_DIR}" | tr '[:lower:]-' '[:upper:]_')_INTERVAL"
        if [ -z "${!TIER_VAR:-}" ]; then
          b19-log warn "HEALTH.D" "$(_p "Ignoring tier %s: %s is not set" "${TIER_DIR}" "${TIER_VAR}")"
          continue
        fi
        mkdir --parents "${TIER_STATE_PATH}"
        list_scripts "${TIER_DIR}"
        for CHECK in "${SCRIPTS[@]}"; do
          CHECKS_COUNT=$((CHECKS_COUNT + 1))
          if b19_skipped note "HEALTH.D" B19_HEALTH_SKIP_ "${CHECK}"; then
            continue
          fi
          INTERVAL_VAR="B19_HEALTH_INTERVAL_$(b19_skip_key "${CHECK}")"
          if report_tier_check "${CHECK}" "${!INTERVAL_VAR:-${!TIER_VAR}}"; then
            b19-log good "HEALTH.D" "$(_ "Check passed:") $(basename "${CHECK}")"
            report_state "$(basename "${CHECK}")" pass ""
          else
            b19-log bad "HEALTH.D" "$(_ "Check failed:") $(basename "${CHECK}")"
            report_state "$(basename "${CHECK}")" fail "${TIER_REASON:-no verdict line}"
            FINAL_EXIT_CODE=$((FINAL_EXIT_CODE + 1))
            FAILED_LIST+=("$(basename "${CHECK}")")
          fi
        done
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

    # Seconds since PID 1 started, read from /proc since procps is absent
    pid1_age() {
      local _up _stat _fields
      read -r _up _ </proc/uptime
      _stat=$(</proc/1/stat)
      read -ra _fields <<<"${_stat##*) }"
      echo $(( ${_up%.*} - _fields[19] / $(getconf CLK_TCK) ))
    }

    # Stops PID 1 after B19_HEALTH_EXIT_AFTER consecutive failed probes, so the restart policy acts
    if [ -n "${B19_HEALTH_EXIT_AFTER:-}" ] && ! [[ "${B19_HEALTH_EXIT_AFTER}" =~ ^[1-9][0-9]*$ ]]; then
      b19-log warn "HEALTH.D" "$(_p "Ignoring B19_HEALTH_EXIT_AFTER=%s: not a positive integer" "${B19_HEALTH_EXIT_AFTER}")"
    elif [ -n "${B19_HEALTH_EXIT_AFTER:-}" ]; then
      FAILURES_FILE="${TIER_STATE_PATH}/consecutive-failures"
      mkdir --parents "${TIER_STATE_PATH}"
      FAILURES=$(cat "${FAILURES_FILE}" 2>/dev/null || true)
      [[ "${FAILURES}" =~ ^[0-9]+$ ]] || FAILURES=0
      PID1_AGE=$(pid1_age)
      if [ "${FINAL_EXIT_CODE}" -eq 0 ] || [ "${PID1_AGE}" -lt "${B19_HEALTH_EXIT_GRACE:-90}" ]; then
        FAILURES=0
      else
        FAILURES=$((FAILURES + 1))
      fi
      write_atomic "${FAILURES_FILE}" "${FAILURES}"
      b19-log debug "HEALTH.D" "$(_p "Consecutive failed probes: %s of %s (PID 1 age %s s)" "${FAILURES}" "${B19_HEALTH_EXIT_AFTER}" "${PID1_AGE}")"
      if [ "${FAILURES}" -ge "${B19_HEALTH_EXIT_AFTER}" ]; then
        b19-log error "HEALTH.D" "$(_p "%s consecutive failed probes, sending TERM to PID 1" "${FAILURES}")"
        kill -TERM 1 || b19-log warn "HEALTH.D" "$(_p "Cannot signal PID 1 as UID %s" "$(id --user)")"
      fi
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
    write_atomic "${LAST_VERDICT}" "${FINAL_EXIT_CODE}"$'\n'"${FAILED_NAMES}" 2>/dev/null \
      || b19-log debug "HEALTH.D" "$(_p "Cannot write %s" "${LAST_VERDICT}")"

    # The buffered log follows the verdict, cut so both fit the output limit
    flush_log "$(( ${#FAILED_NAMES} + 1 ))"

    exit "${FINAL_EXIT_CODE}"
