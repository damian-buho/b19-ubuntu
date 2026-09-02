<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Cached artifact downloads with integrity verification

- Downloads are cached locally and in BuildKit persistent storage, so repeated fetches are served from cache.
- SHA-512 hash verification runs at every tier; mismatches fall through to the next source rather than failing.
- Offgrid mode blocks all downloads entirely, failing fast with a clear error on cache miss.
- Supports a near-cache proxy for LAN-only builds that route through a caching proxy.
