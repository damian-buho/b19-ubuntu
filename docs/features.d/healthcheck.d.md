<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Built-in health monitoring (healthcheck.d)

- Docker-native healthcheck declared in the base image and inherited by all downstream images with no extra configuration.
- Seven default checks: disk space on home, cache, and temp directories; HTTPS connectivity, DNS resolution, ICMP ping; and filesystem writability.
- Network checks are fault-tolerant — success on any target counts as pass.
- All network checks automatically skip in offgrid mode; all checks can be disabled at runtime.
- Downstream images add service-specific checks (HTTP endpoints, database connections, process liveness) by dropping scripts into a directory.
