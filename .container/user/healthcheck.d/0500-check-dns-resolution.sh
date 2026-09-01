#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Check DNS resolution
# Tests DNS resolution functionality that can fail during operation
# Supports multiple URLs (comma-separated) - success if at least one resolves
# Uses environment variables from the b19 system

# Use the same health URLs as HTTPS connectivity check for consistency
HEALTH_URLS="${B19_HEALTH_NETWORK_URL}"

# Skip check if no health URL is configured
if [ -z "${HEALTH_URLS}" ]; then
  b19-log good "HEALTH.D" "$(_ "DNS resolution check skipped (no B19_HEALTH_NETWORK_URL configured)")"
  exit 0
fi

# Egress checks are opt-in: an image that never reaches the internet must not fail on it.
if [ "${B19_HEALTH_EGRESS:-false}" != "true" ]; then
  b19-log good "HEALTH.D" "$(_ "DNS resolution check skipped (B19_HEALTH_EGRESS not enabled)")"
  exit 0
fi

if [ "${B19_OFFGRID_MODE:-N}" = "Y" ]; then
  b19-log good "HEALTH.D" "$(_ "DNS resolution check skipped (offgrid mode)")"
  exit 0
fi

# Split multiple URLs by space and test DNS resolution for each one
# Success if at least one hostname resolves
SUCCESS=0
for URL in ${HEALTH_URLS}; do
  if [ -z "${URL}" ]; then
    continue
  fi
  
  # Extract hostname from URL for DNS resolution test
  HOSTNAME="${URL#*://}"; HOSTNAME="${HOSTNAME%%/*}"; HOSTNAME="${HOSTNAME%%:*}"
  
  if [ -z "${HOSTNAME}" ]; then
    b19-log bad "HEALTH.D" "$(_p "DNS resolution failed - could not extract hostname from URL: %s" "${URL}")"
    continue
  fi
  
  # Test DNS resolution using getent (more reliable than ping for DNS-only check)
  if getent hosts "${HOSTNAME}" >/dev/null 2>&1; then
    SUCCESS=1
    break
  fi
done

if [ "${SUCCESS}" -eq 0 ]; then
  b19-log bad "HEALTH.D" "$(_p "DNS resolution failed for all URLs (B19_HEALTH_NETWORK_URL: %s)" "${B19_HEALTH_NETWORK_URL}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "DNS resolution working (B19_HEALTH_NETWORK_URL: %s)" "${B19_HEALTH_NETWORK_URL}")"
exit 0
