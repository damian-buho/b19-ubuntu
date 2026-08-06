<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Timed command execution with failure reporting (b19-run)

- Any command can be wrapped to get automatic elapsed-time measurement and success/failure reporting.
- Success output is visible only at higher verbosity levels; failure output is always shown.
- In debug mode, command output streams live instead of being buffered.
