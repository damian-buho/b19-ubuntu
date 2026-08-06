#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # b19-exec publishes the payload PID to ${B19_HOME}/.payload.pid because it
  # runs as a subprocess whose `export PAYLOAD_PID` cannot reach this shell.
  # Fall back to a PAYLOAD_PID set directly in this shell (if any caller does).
  function signalHandler() {
      _signals_pid=""
      if [ -f "${B19_HOME}/.payload.pid" ]; then
        _signals_pid=$(tr -dc '0-9' < "${B19_HOME}/.payload.pid" 2>/dev/null)
      fi
      _signals_pid="${_signals_pid:-${PAYLOAD_PID:-}}"
      if [ -n "${_signals_pid}" ] && kill -0 "${_signals_pid}" 2>/dev/null; then
        b19-log info "SIGNALS" "$(_p "Caught %s, transferring to %s" "$1" "${_signals_pid}")"
        kill -s "${1}" "${_signals_pid}"
      else
        b19-log warn "SIGNALS" "$(_p "Caught %s, no active payload process to signal" "$1")"
      fi
  }

  SIGNALS_FILE="${B19_HOME}/.signals"
  if [ ! -f "${SIGNALS_FILE}" ]; then
    exit 0
  fi

  SIGNALS=$(decomment < "${SIGNALS_FILE}") || true
  for SIGNAL in ${SIGNALS}
  do
    # We in cycle so this warning is irrelevant
    # shellcheck disable=SC2064
    trap "signalHandler SIG${SIGNAL};" "SIG${SIGNAL}"
    b19-log debug "SIGNALS" "$(_p "%s trapped" "${SIGNAL}")"
  done
