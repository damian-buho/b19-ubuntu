<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Service process management with log routing (b19-exec)

- Long-running processes (daemons, servers) have stdout and stderr automatically routed through the structured logger.
- Every signal reaches the service exactly once, so `docker stop` ends it gracefully and its last log lines are kept.
- Log levels for stdout and stderr streams are independently configurable.
- Several daemons share one container: each line is tagged with its daemon, they stop in reverse start order, and a crashed required daemon stops the container so the restart policy acts.
- Passthrough mode hands a service’s own log to the collector byte for byte, so parsers built for that daemon still match.
