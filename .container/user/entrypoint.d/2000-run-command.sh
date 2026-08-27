#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  if [ $# -gt 0 ] && command -v "$1" >/dev/null 2>&1;
  then
    b19-log note "ENTRY.D" "$(_p "Treating %s as command" "$*")"
    "$@" && RETURN_CODE=0 || RETURN_CODE=$?
    ENTRYPOINT_COMMAND_EXECUTED=Y
  elif [ $# -eq 0 ] || [ -z "${1:-}" ];
  then
    b19-log info "ENTRY.D" "$(_ "Empty command, continue")"
    ENTRYPOINT_COMMAND_EXECUTED=N
  elif [ "${B19_SINGLE_COMMAND_IMAGE:-N}" = "Y" ];
  then
    # An image wrapping ONE program takes the SUBCOMMAND as argv (`docker run
    # img validate`, not `docker run img pf-cli validate`), so a first arg that
    # is not a command is the normal path: leave it for the image's own start
    # hook, which knows the program. 9000-finalize fails the run if none did.
    b19-log info "ENTRY.D" "$(_p "Single-command image: %s left for the start hook" "$*")"
    ENTRYPOINT_COMMAND_EXECUTED=N
  else
    # A command WAS requested and the image does not carry it: fail closed with
    # the shell's 127 rather than falling through to bootstrap/start, which
    # reported success for a run that executed nothing.
    b19-log error "ENTRY.D" "$(_p "%s is not a command" "$1")"
    ENTRYPOINT_COMMAND_EXECUTED=N
    RETURN_CODE=127
    export ENTRYPOINT_COMMAND_EXECUTED RETURN_CODE
    exit "${RETURN_CODE}"
  fi

  export ENTRYPOINT_COMMAND_EXECUTED RETURN_CODE
