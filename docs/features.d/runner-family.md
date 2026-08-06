<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Unified lifecycle runner family

- Eight numbered-hook runners cover the full container lifecycle: startup, healthchecks, tests, bootstrap, build hooks, benchmarks, reports, and shell sessions.
- All runners share the same pattern: drop a numbered script into a directory, it is auto-discovered and executed.
- Scripts from different image layers merge seamlessly — upstream and downstream hooks coexist without conflict.
- Each runner has tailored failure semantics: abort on error (entrypoint, bootstrap), continue and count failures (healthchecks, tests), always succeed (reports).
