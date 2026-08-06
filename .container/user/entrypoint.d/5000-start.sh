#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  if [ "${ENTRYPOINT_COMMAND_EXECUTED:-N}" = "N" ]
  then
    if [ -z "$*" ]
    then
      b19-log info "UBUNTU" "$(_ "No command provided, will sleep")"
      b19-exec -- sleep infinity
    fi
  fi
