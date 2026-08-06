<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Persistent APT cache across builds

- APT package and index caches survive across builds via BuildKit cache mounts, keyed by Ubuntu series and architecture.
- Repeated builds reuse downloaded packages instead of re-downloading.
- Optional LAN APT cacher proxy auto-detection for environments with a caching proxy.
