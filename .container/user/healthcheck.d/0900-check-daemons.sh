#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Fails when a required b19-exec daemon exited or its recorded process is gone
_daemons_state="${B19_RUNTIME_PATH:-/run/b19}/b19-exec"
_daemons_failed=0
_daemons_count=0

for _daemons_file in "${_daemons_state}"/*.exit; do
  [ -e "${_daemons_file}" ] || continue
  _daemons_name="${_daemons_file##*/}"
  b19-log bad "HEALTH.D" "$(_p "Required daemon %s exited with %s" "${_daemons_name%.exit}" "$(<"${_daemons_file}")")"
  _daemons_failed=1
done

for _daemons_file in "${_daemons_state}"/*.pid; do
  [ -e "${_daemons_file}" ] || continue
  _daemons_name="${_daemons_file##*/}"
  _daemons_pid="" _daemons_role=""
  read -r _daemons_pid _daemons_role < "${_daemons_file}" || true
  if [ "${_daemons_role}" = optional ]; then
    b19-log debug "HEALTH.D" "$(_p "Skipping optional daemon %s (pid %s)" "${_daemons_name%.pid}" "${_daemons_pid}")"
  elif [[ "${_daemons_pid}" =~ ^[0-9]+$ ]] && [ -e "/proc/${_daemons_pid}" ]; then
    _daemons_count=$((_daemons_count + 1))
  else
    b19-log bad "HEALTH.D" "$(_p "Daemon %s (pid %s) is gone" "${_daemons_name%.pid}" "${_daemons_pid}")"
    _daemons_failed=1
  fi
done

if [ "${_daemons_failed}" -eq 1 ]; then
  exit 1
fi
b19-log good "HEALTH.D" "$(_p "%s required daemons running in %s" "${_daemons_count}" "${_daemons_state}")"
exit 0
