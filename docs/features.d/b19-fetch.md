<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Cached artifact downloads with integrity verification (b19-fetch)

- All external downloads go through a three-tier cache: local `.fetch/` directory, BuildKit persistent cache, then upstream via aria2c with up to 16 connections.
- Optional SHA-512 verification at every tier; hash mismatch causes fallthrough to the next tier rather than failure.
- Offgrid mode blocks all downloads entirely, failing fast with a clear error if a cache miss occurs.
- Supports a near-cache proxy for LAN-only builds that route through a caching proxy.
