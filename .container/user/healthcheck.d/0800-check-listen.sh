#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Readiness probe: TCP-connect 127.0.0.1:${B19_READY_PORT}. Gives every
# downstream image a working readiness check for one ENV line, with no
# service-specific script required. Loopback-only, so a refused connection
# returns immediately — no timeout wrapper needed, unlike the diagnostic
# checks that reach the network.

PORT="${B19_READY_PORT:-}"

if [ -z "${PORT}" ]; then
  b19-log good "HEALTH.D" "$(_ "Listen check skipped (no B19_READY_PORT configured)")"
  exit 0
fi

if { exec 3<>"/dev/tcp/127.0.0.1/${PORT}"; } 2>/dev/null; then
  exec 3<&-
  b19-log good "HEALTH.D" "$(_p "Listening on 127.0.0.1:%s" "${PORT}")"
  exit 0
fi

b19-log bad "HEALTH.D" "$(_p "Not listening on 127.0.0.1:%s" "${PORT}")"
exit 1
