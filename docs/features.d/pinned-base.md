<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Reproducible base image (pinned by digest)

- The Ubuntu base image is pinned by SHA-256 digest, not by tag, ensuring deterministic builds.
- Supports multiple Ubuntu series (resolute, noble, jammy) selectable at build time.
- APT mirrors are configurable per architecture for LAN mirrors or air-gapped environments.
