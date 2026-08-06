#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    # Enable safer bash scripting
    set -euo pipefail

    # shellcheck source=.container/foundation/tools.d/b19-i18n
    . b19-i18n

    REPORTS_PATH="/report.d"
    REPORTS_RESULTS_PATH="/tmp/report.txt"

    # Log the paths being used
    b19-log info "REPORT.D" "$(_ "Reading from:") ${REPORTS_PATH}"
    b19-log info "REPORT.D" "$(_ "Writing to:") ${REPORTS_RESULTS_PATH}"

    # Clear or create the results file
    echo > "${REPORTS_RESULTS_PATH}"

    # Check if the reports directory exists
    if [ -d "${REPORTS_PATH}" ]; then
      b19-log info "REPORT.D" "$(_ "Directory found:") ${REPORTS_PATH}"

      # Find and sort report scripts in descending order
      REPORTS_COUNT=0
      while IFS= read -r -d '' REPORT; do
        REPORTS_COUNT=$((REPORTS_COUNT + 1))
        BASENAME="$(basename "${REPORT}" .sh)"
        b19-log info "REPORT.D" "$(_ "Processing report:") ${BASENAME}"

        {
          echo
          echo "--------[START ${BASENAME}]--------"
          # shellcheck disable=SC1090
          . "${REPORT}"
          echo "--------[END ${BASENAME}]--------"
        } | tee -a "${REPORTS_RESULTS_PATH}"
      done < <(fd --print0 --hidden --type file --extension sh . "${REPORTS_PATH}" | sort --zero-terminated --numeric-sort --reverse)

      # Handle case where no scripts are found
      if [ "${REPORTS_COUNT}" -eq 0 ]; then
        b19-log note "REPORT.D" "$(_ "No report scripts found in") ${REPORTS_PATH}"
      else
        # Output the final report
        cat "${REPORTS_RESULTS_PATH}"
      fi
    else
      b19-log note "REPORT.D" "$(_ "Directory not found:") ${REPORTS_PATH}"
    fi

    # Exit with success
    exit 0