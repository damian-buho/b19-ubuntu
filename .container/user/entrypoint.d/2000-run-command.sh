#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  if [ $# -gt 0 ] && command -v "$1" >/dev/null 2>&1;
  then
    b19-log note "ENTRY.D" "$(_p "Treating %s as command" "$*")"
    "$@" && RETURN_CODE=0 || RETURN_CODE=$?
    ENTRYPOINT_COMMAND_EXECUTED=Y
  else
    if [ $# -eq 0 ] || [ -z "${1:-}" ];
    then
      b19-log info "ENTRY.D" "$(_ "Empty command, continue")"
    else
      b19-log warn "ENTRY.D" "$(_p "%s is not a command, continue" "$1")"
    fi
    ENTRYPOINT_COMMAND_EXECUTED=N
  fi

  export ENTRYPOINT_COMMAND_EXECUTED RETURN_CODE
