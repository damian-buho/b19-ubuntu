#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    # Skip entire entrypoint if disabled
    if [ "${B19_ENTRYPOINT_ENABLED:-true}" = "false" ]; then
      if [ $# -gt 0 ]; then
        exec "$@"
      fi
      exec sleep infinity
    fi

    # Enable safer bash scripting
    set -euo pipefail

    # shellcheck source=.container/foundation/tools.d/b19-i18n
    . b19-i18n
    b19-log debug "I18N" "mode=${_B19_I18N_MODE} lang=${LANG:-}"

    ENTRYPOINTS_PATH="/entrypoint.d"

    # Check if the entrypoints directory exists
    if [ -d "${ENTRYPOINTS_PATH}" ]; then
      b19-log debug "ENTRY.D" "$(_ "Directory found:") ${ENTRYPOINTS_PATH}" >&2
      b19-log debug "ENTRY.D" "$(_ "Found:") $(ls -m "${ENTRYPOINTS_PATH}")" >&2

      # Find and sort entrypoint scripts
      ENTRYPOINTS_COUNT=0
      while IFS= read -r -d '' ENTRYPOINT <&3; do
        ENTRYPOINTS_COUNT=$((ENTRYPOINTS_COUNT + 1))

        SKIP_NAME=$(basename "${ENTRYPOINT}" .sh)
        SKIP_NAME="${SKIP_NAME#*[0-9]-}"
        SKIP_NAME="${SKIP_NAME%.i}"
        SKIP_VAR="B19_ENTRYPOINT_SKIP_$(echo "${SKIP_NAME}" | tr '[:lower:]-' '[:upper:]_')"
        if [ "${!SKIP_VAR:-}" = "true" ]; then
          b19-log note "ENTRY.D" "$(_p "Skipped: %s (via %s)" "${SKIP_NAME}" "${SKIP_VAR}")" >&2
          continue
        fi

        b19-log debug "ENTRY.D" "$(_ "Will run") ${ENTRYPOINT}" >&2

        # Execute the entrypoint script
        # shellcheck disable=SC1090
        . "${ENTRYPOINT}"
      done 3< <(fd --print0 --hidden --type file --extension sh . "${ENTRYPOINTS_PATH}" | sort --zero-terminated --numeric-sort)

      # Handle case where no scripts are found
      if [ "${ENTRYPOINTS_COUNT}" -eq 0 ]; then
        b19-log warn "ENTRY.D" "$(_ "No entrypoint scripts found in") ${ENTRYPOINTS_PATH}" >&2
      fi
    else
      b19-log warn "ENTRY.D" "$(_ "Directory not found:") ${ENTRYPOINTS_PATH}" >&2
    fi
