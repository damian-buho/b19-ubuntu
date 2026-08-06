#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    # Skip all bootstrapping if disabled
    if [ "${B19_BOOTSTRAP_ENABLED:-}" = "false" ]; then
      exit 0
    fi

    # Enable safer bash scripting
    set -euo pipefail

    # shellcheck source=.container/foundation/tools.d/b19-i18n
    . b19-i18n

    BOOTSTRAP_PATH="${B19_BOOTSTRAP_PATH:-/bootstrap.d}"
    LOCK_PATH="${B19_BOOTSTRAP_LOCK_PATH:-${B19_HOME}/.bootstrap}"

    if [ ! -d "${BOOTSTRAP_PATH}" ]; then
      b19-log note "BOOTSTRAP" "$(_p "Directory not found: %s" "${BOOTSTRAP_PATH}")"
      exit 0
    fi

    # Ensure lock directory exists
    b19-run "BOOTSTRAP" "$(_p "Create lock directory %s" "${LOCK_PATH}")" --  mkdir -p "${LOCK_PATH}"

    SCRIPT_COUNT=0

    while IFS= read -r -d '' SCRIPT; do
      SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
      BASENAME=$(basename "${SCRIPT}" .sh)
      SKIP_NAME="${BASENAME#*[0-9]-}"
      SKIP_VAR="B19_BOOTSTRAP_SKIP_$(echo "${SKIP_NAME}" | tr '[:lower:]-' '[:upper:]_')"
      if [ "${!SKIP_VAR:-}" = "true" ]; then
        b19-log note "BOOTSTRAP" "$(_p "Skipped: %s (via %s)" "${SKIP_NAME}" "${SKIP_VAR}")"
        continue
      fi

      LOCK_FILE="${LOCK_PATH}/.${BASENAME}.bootstrap"

      if [ -f "${LOCK_FILE}" ]; then
        b19-log note "BOOTSTRAP" "$(_p "Already done: %s" "${BASENAME}")"
        continue
      fi

      b19-log info "BOOTSTRAP" "$(_p "Running: %s" "${BASENAME}")"
      b19-run "BOOTSTRAP" "$(_p "Execute: %s" "${BASENAME}")" --  "${SCRIPT}"
      b19-run "BOOTSTRAP" "$(_p "Lock: %s" "${BASENAME}")" --    touch "${LOCK_FILE}"
      b19-log good "BOOTSTRAP" "$(_p "Completed: %s" "${BASENAME}")"
    done < <(fd --print0 --hidden --type file --extension sh . "${BOOTSTRAP_PATH}" | sort --zero-terminated --numeric-sort)

    if [ "${SCRIPT_COUNT}" -eq 0 ]; then
      b19-log note "BOOTSTRAP" "$(_p "No scripts found in %s" "${BOOTSTRAP_PATH}")"
    fi

    exit 0
