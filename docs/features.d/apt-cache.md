<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Persistent APT cache across builds

- Package downloads and index caches persist across builds, so repeated builds skip redundant downloads.
- Cache is keyed by Ubuntu series and architecture, avoiding cross-contamination.
- Optional LAN APT cacher proxy can be enabled for faster local builds.
