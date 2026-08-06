#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Self-check: Test healthcheck directory operations
# Test writing to healthcheck directory (can fail if permission/space issues)
if ! touch "${B19_HEALTH_PATH}/.healthcheck_test" 2>/dev/null || ! rm "${B19_HEALTH_PATH}/.healthcheck_test" 2>/dev/null; then
  b19-log bad "HEALTH.D" "$(_p "Healthcheck directory operations failed (B19_HEALTH_PATH: %s)" "${B19_HEALTH_PATH}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Healthcheck directory operations working (B19_HEALTH_PATH: %s)" "${B19_HEALTH_PATH}")"
exit 0
