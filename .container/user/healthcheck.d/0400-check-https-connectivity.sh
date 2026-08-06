#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Check HTTPS connectivity
# Tests actual HTTPS connectivity that can fail during operation
# Supports multiple URLs (comma-separated) - success if at least one works
# Uses environment variables from the b19 system

# Skip check if no health URL is configured
if [ -z "${B19_HEALTH_NETWORK_URL}" ]; then
  b19-log good "HEALTH.D" "$(_ "HTTPS connectivity check skipped (no B19_HEALTH_NETWORK_URL configured)")"
  exit 0
fi

if [ "${B19_OFFGRID_MODE:-N}" = "Y" ]; then
  b19-log good "HEALTH.D" "$(_ "HTTPS connectivity check skipped (offgrid mode)")"
  exit 0
fi

# Split multiple URLs by space and test each one
# Success if at least one URL is reachable
SUCCESS=0
for URL in ${B19_HEALTH_NETWORK_URL}; do
  if [ -n "${URL}" ] && curl -I -s --connect-timeout "${B19_HEALTH_CURL_TIMEOUT}" --max-time $((B19_HEALTH_CURL_TIMEOUT * 2)) "${URL}" >/dev/null 2>&1; then
    SUCCESS=1
    break
  fi
done

if [ "${SUCCESS}" -eq 0 ]; then
  b19-log bad "HEALTH.D" "$(_p "HTTPS connectivity failed (B19_HEALTH_NETWORK_URL: %s)" "${B19_HEALTH_NETWORK_URL}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "HTTPS connectivity working (B19_HEALTH_NETWORK_URL: %s)" "${B19_HEALTH_NETWORK_URL}")"
exit 0
