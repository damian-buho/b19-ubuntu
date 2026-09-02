<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Automatic CPU count detection

- CPU count is detected automatically across Docker, Kubernetes, and CI environments without manual configuration.
- Eliminates hardcoded job counts — parallel compilation, template rendering, and tests use the right parallelism everywhere.
- The detected count is available throughout build and runtime for any tool that needs it.
