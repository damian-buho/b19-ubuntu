#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Check space in temp directory (B19_TEMP_PATH)
# Temp space is critical for build operations and can fill up quickly
# Uses environment variables for thresholds to maintain single authority principle
TEMP_AVAILABLE=$(df --output=avail "${B19_TEMP_PATH}" | tail -1)
TEMP_AVAILABLE_FMT=$(numfmt --from-unit=1024 --to=iec --suffix=B --format="%.2f" <<< "${TEMP_AVAILABLE}")
TEMP_MIN_SPACE_FMT=$(numfmt --from-unit=1024 --to=iec --suffix=B --format="%.2f" <<< "${B19_HEALTH_TEMP_MIN_SPACE_KB}")

if [ "$TEMP_AVAILABLE" -le "${B19_HEALTH_TEMP_MIN_SPACE_KB}" ]; then
  b19-log bad "HEALTH.D" "$(_p "Low space in %s (B19_TEMP_PATH): %s < %s" "${B19_TEMP_PATH}" "${TEMP_AVAILABLE_FMT}" "${TEMP_MIN_SPACE_FMT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "%s (B19_TEMP_PATH) has sufficient space: %s > %s" "${B19_TEMP_PATH}" "${TEMP_AVAILABLE_FMT}" "${TEMP_MIN_SPACE_FMT}")"
exit 0
