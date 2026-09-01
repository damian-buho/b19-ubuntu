#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Raw-IP reachability (L3/L4) WITHOUT DNS — the middle rung of the connectivity
# diagnostic ladder (HTTPS -> DNS -> reachability). What we are trying to do: when
# the HTTPS rung fails, localize whether the host can reach the network at all,
# independent of name resolution. We use a TCP connect, NOT ICMP: raw ICMP needs
# cap_net_raw / a permissive net.ipv4.ping_group_range, which rootless & hardened
# runtimes (e.g. podman job steps) deny — a capability artifact, not a health
# signal. A TCP connect to a known-open port needs no capability and proves the
# same path, so the check behaves identically under docker and podman.

# Kept the B19_HEALTH_PING_TARGETS env name for config stability; the port is new
# — the default targets are public DNS resolvers, all of which also accept TCP/443
# (DoH). Override B19_HEALTH_REACH_PORT for non-DNS targets.
TARGETS="${B19_HEALTH_PING_TARGETS}"
PORT="${B19_HEALTH_REACH_PORT_SAFE}"
TIMEOUT="${B19_HEALTH_CURL_TIMEOUT}"

# Skip when no targets are configured.
if [ -z "${TARGETS}" ]; then
  b19-log good "HEALTH.D" "$(_ "Reachability check skipped (no B19_HEALTH_PING_TARGETS configured)")"
  exit 0
fi

# Egress checks are opt-in: an image that never reaches the internet must not fail on it.
if [ "${B19_HEALTH_EGRESS:-false}" != "true" ]; then
  b19-log good "HEALTH.D" "$(_ "Reachability check skipped (B19_HEALTH_EGRESS not enabled)")"
  exit 0
fi

if [ "${B19_OFFGRID_MODE:-N}" = "Y" ]; then
  b19-log good "HEALTH.D" "$(_ "Reachability check skipped (offgrid mode)")"
  exit 0
fi

# Success if at least one target's TCP port accepts a connection. bash's /dev/tcp
# pseudo-device performs the connect() with no extra binary or capability;
# `timeout` bounds a target that silently drops packets.
SUCCESS=0
for IP in ${TARGETS}; do
  [ -n "${IP}" ] || continue
  if timeout "${TIMEOUT}" bash -c "exec 3<>/dev/tcp/${IP}/${PORT}" 2>/dev/null; then
    SUCCESS=1
    break
  fi
done

if [ "${SUCCESS}" -eq 0 ]; then
  b19-log bad "HEALTH.D" "$(_p "Reachability failed for all targets on port %s (B19_HEALTH_PING_TARGETS: %s)" "${PORT}" "${B19_HEALTH_PING_TARGETS}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Reachability working on port %s (B19_HEALTH_PING_TARGETS: %s)" "${PORT}" "${B19_HEALTH_PING_TARGETS}")"
exit 0
