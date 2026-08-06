#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Check space in cache directory (XDG_CACHE_HOME)
# Cache directories frequently fill up and cause operational issues
# Uses environment variables for thresholds to maintain single authority principle
CACHE_AVAILABLE=$(df --output=avail "${XDG_CACHE_HOME}" | tail -1)
CACHE_AVAILABLE_FMT=$(numfmt --from-unit=1024 --to=iec --suffix=B --format="%.2f" <<< "${CACHE_AVAILABLE}")
CACHE_MIN_SPACE_FMT=$(numfmt --from-unit=1024 --to=iec --suffix=B --format="%.2f" <<< "${B19_HEALTH_CACHE_MIN_SPACE_KB}")

if [ "$CACHE_AVAILABLE" -le "${B19_HEALTH_CACHE_MIN_SPACE_KB}" ]; then
  b19-log bad "HEALTH.D" "$(_p "Low space in %s (XDG_CACHE_HOME): %s < %s" "${XDG_CACHE_HOME}" "${CACHE_AVAILABLE_FMT}" "${CACHE_MIN_SPACE_FMT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "%s (XDG_CACHE_HOME) has sufficient space: %s > %s" "${XDG_CACHE_HOME}" "${CACHE_AVAILABLE_FMT}" "${CACHE_MIN_SPACE_FMT}")"
exit 0
