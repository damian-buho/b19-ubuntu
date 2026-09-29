#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Run the command 2000-select-command claimed, now that secrets and bootstrap are in place
  if [ "${ENTRYPOINT_COMMAND_EXECUTED:-N}" = "Y" ];
  then
    b19-log info "ENTRY.D" "$(_p "Running: %s" "$*")"
    "$@" && RETURN_CODE=0 || RETURN_CODE=$?
    export RETURN_CODE
  fi
