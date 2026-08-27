#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  b19-log note "ENTRY.D" "$(_p "Done: %s" "${RETURN_CODE:-0}")"

  # An argv that reached the last hook with NO exit code was never executed by
  # anyone: B19_SINGLE_COMMAND_IMAGE let it through at 2000 and no start hook
  # claimed it. Reporting 0 would be exactly the green-over-nothing this hook
  # exists to prevent, so the single-command mode cannot reintroduce it.
  if [ -z "${RETURN_CODE:-}" ] && [ $# -gt 0 ];
  then
    b19-log error "ENTRY.D" "$(_p "Nothing consumed %s — the image declares no start hook for it" "$*")"
    exit 127
  fi

  # Propagate the executed command's exit code as the CONTAINER's exit code.
  # The orchestrator (tools.d/entrypoint.d) SOURCES this hook last and never
  # exits itself, so without this the command.d path always reported success:
  # 2000-run-command captures RETURN_CODE via `… || RETURN_CODE=$?` (so set -e
  # does not abort the remaining hooks), but only the b19-exec/test.d path ever
  # re-asserted it. A failing tool (e.g. yamllint) must fail the run.
  # RETURN_CODE is unset only on the empty-argv path (the service path exits
  # earlier via b19-exec), so :-0 is the benign default there.
  exit "${RETURN_CODE:-0}"
