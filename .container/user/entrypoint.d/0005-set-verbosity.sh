#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Run the lifecycle hooks at B19_ENTRYPOINT_VERBOSITY; 4000-run-command restores B19_VERBOSITY for the payload
  if [ -n "${B19_ENTRYPOINT_VERBOSITY:-}" ];
  then
    # Keep the first stash, so a re-exec from 0010-remap-user does not lose the payload level
    ENTRYPOINT_PAYLOAD_VERBOSITY="${ENTRYPOINT_PAYLOAD_VERBOSITY:-${B19_VERBOSITY:-warn}}"
    B19_VERBOSITY="${B19_ENTRYPOINT_VERBOSITY}"
    export ENTRYPOINT_PAYLOAD_VERBOSITY B19_VERBOSITY
    b19-log debug "ENTRY.D" "$(_p "Lifecycle verbosity %s, payload verbosity %s" "${B19_VERBOSITY}" "${ENTRYPOINT_PAYLOAD_VERBOSITY}")"
  fi
