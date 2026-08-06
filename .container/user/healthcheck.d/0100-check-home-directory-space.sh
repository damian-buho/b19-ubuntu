#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Check space in the actual working directory (B19_HOME)
# This is a practical check for the directory where applications run
# Uses environment variables for thresholds to maintain single authority principle
HOME_AVAILABLE=$(df --output=avail "${B19_HOME}" | tail -1)
HOME_AVAILABLE_FMT=$(numfmt --from-unit=1024 --to=iec --suffix=B --format="%.2f" <<< "${HOME_AVAILABLE}")
HOME_MIN_SPACE_FMT=$(numfmt --from-unit=1024 --to=iec --suffix=B --format="%.2f" <<< "${B19_HEALTH_HOME_MIN_SPACE_KB}")

if [ "$HOME_AVAILABLE" -le "${B19_HEALTH_HOME_MIN_SPACE_KB}" ]; then
  b19-log bad "HEALTH.D" "$(_p "Low space in %s (B19_HOME): %s < %s" "${B19_HOME}" "${HOME_AVAILABLE_FMT}" "${HOME_MIN_SPACE_FMT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "%s (B19_HOME) has sufficient space: %s > %s" "${B19_HOME}" "${HOME_AVAILABLE_FMT}" "${HOME_MIN_SPACE_FMT}")"
exit 0
