<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Unified lifecycle runner family

- Every lifecycle concern — startup, healthchecks, tests, bootstrap, build, benchmarks, reports, and shell — follows the same discoverable hook pattern.
- Drop a numbered script into a directory and it is auto-discovered and executed, no wiring required.
- Scripts from different image layers merge, so upstream and downstream hooks coexist without conflict.
- Each runner has tailored failure semantics: abort on error, continue and count failures, or always succeed as appropriate.
