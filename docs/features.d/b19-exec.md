<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Service process management with log routing (b19-exec)

- Long-running processes (daemons, servers) have stdout and stderr automatically routed through the structured logger.
- The service PID is tracked for signal forwarding — Docker stop gracefully terminates the main process.
- Log levels for stdout and stderr streams are independently configurable.
- Exit code of the service is captured and available to downstream hooks.
