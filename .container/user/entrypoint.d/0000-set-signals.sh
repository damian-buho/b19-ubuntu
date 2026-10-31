#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Logs a signal; every b19-exec forwards it to its own command
  function signalHandler() {
      b19-log info "SIGNALS" "$(_p "Caught %s, b19-exec forwards it to the commands it runs" "$1")"
  }

  # Clears the b19-exec records an earlier run of this container left behind
  _signals_state="${B19_RUNTIME_PATH:-/run/b19}/b19-exec"
  if [ -d "${_signals_state}" ]; then
    b19-log debug "SIGNALS" "$(_p "Clearing stale records in %s" "${_signals_state}")"
    rm -f -- "${_signals_state}"/*.pid "${_signals_state}"/*.exit "${_signals_state}"/*.stop
  fi
  unset _signals_state

  SIGNALS_FILE="${B19_HOME}/.signals"
  if [ ! -f "${SIGNALS_FILE}" ]; then
    b19-log debug "SIGNALS" "$(_p "%s not found, no signals trapped" "${SIGNALS_FILE}")"
    return 0
  fi

  SIGNALS=$(decomment < "${SIGNALS_FILE}") || true
  for SIGNAL in ${SIGNALS}
  do
    # We in cycle so this warning is irrelevant
    # shellcheck disable=SC2064
    trap "signalHandler SIG${SIGNAL};" "SIG${SIGNAL}"
    b19-log debug "SIGNALS" "$(_p "%s trapped" "${SIGNAL}")"
  done
