#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  b19-log note "ENTRY.D" "$(_p "Done: %s" "${RETURN_CODE:-0}")"

  # Propagate the executed command's exit code as the CONTAINER's exit code.
  # The orchestrator (tools.d/entrypoint.d) SOURCES this hook last and never
  # exits itself, so without this the command.d path always reported success:
  # 2000-run-command captures RETURN_CODE via `… || RETURN_CODE=$?` (so set -e
  # does not abort the remaining hooks), but only the b19-exec/test.d path ever
  # re-asserted it. A failing tool (e.g. yamllint) must fail the run.
  # RETURN_CODE is unset only on the no/invalid-command path (the service path
  # exits earlier via b19-exec), so :-0 is the benign default there.
  exit "${RETURN_CODE:-0}"

