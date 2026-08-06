<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Automatic CPU count detection (NUMPROCS)

- Available CPUs are detected automatically with Kubernetes downward API, cgroups v2, or `nproc` fallback.
- The detected count is available as `NUMPROCS` throughout the build and runtime, used for parallel compilation, template rendering, and test execution.
- Eliminates hardcoded job counts and ensures consistent parallelism across Docker, Kubernetes, and CI.
