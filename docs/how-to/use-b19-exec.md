<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Manage long-running processes with b19-exec

`b19-exec` starts a daemon and keeps its output readable for the container’s lifetime: stdout and stderr are routed through `b19-log` with independent levels and tags, and the payload PID is published so `tini` can forward signals to the right process. The pitch: [service process management with log routing](../features.d/b19-exec.md).

## When to use

- The `5000-start.sh` entrypoint hook starting the image’s service.
- Any long-running child whose output should obey `B19_VERBOSITY` instead of spewing raw to the console.

For one-shot commands, [b19-run](use-b19-run.md) is the right wrapper.

## Quick start

```bash
# Standard daemon startup (inside an entrypoint script)
b19-exec -- php-fpm --fpm-config /etc/php-fpm.conf

# Nginx with stderr elevated to warn
b19-exec --stderr-level warn -- nginx -g "daemon off;"
```

## How it works

```bash
b19-exec [OPTIONS] -- COMMAND [ARGS...]
```

Output is intercepted via process substitution and routed through `b19-log`, which applies level filtering and colors:

```text
stdin:  /proc/1/fd/0     (container stdin)
stdout: b19-log $LEVEL $TAG -> /proc/1/fd/1
stderr: b19-log $LEVEL $TAG -> /proc/1/fd/2
```

### Background mode (default)

Runs the command in the background, waits for it, and exports `PAYLOAD_PID` and `RETURN_CODE`. Because `b19-exec` runs as a subprocess, its `export PAYLOAD_PID` cannot reach the entrypoint shell — so it also publishes the payload PID to `${B19_PAYLOAD_PID_FILE:-${B19_HOME}/.payload.pid}`, which the `0000-set-signals.sh` hook reads when forwarding signals. The file is removed when the command exits; a stale file (e.g. after `SIGKILL`) is harmless — the handler verifies the PID with `kill -0`.

### Foreground mode (`--foreground`)

Uses `exec` to replace the current process: the command becomes PID 1’s direct child, no `PAYLOAD_PID` is exported. Use it when the entrypoint script should not continue after the command starts.

## Configuration

| Option           | Default  | Description                           |
| ---------------- | -------- | ------------------------------------- |
| `--stdout-level` | `info`   | Log level for stdout                  |
| `--stderr-level` | `warn`   | Log level for stderr                  |
| `--stdout-tag`   | `STDOUT` | Tag for stdout messages               |
| `--stderr-tag`   | `STDERR` | Tag for stderr messages               |
| `--foreground`   | (off)    | Run via exec (replaces shell process) |

| Variable                | Default                    | Description                                              |
| ----------------------- | -------------------------- | -------------------------------------------------------- |
| `B19_EXEC_STDOUT_LEVEL` | `info`                     | Override default stdout level                            |
| `B19_EXEC_STDERR_LEVEL` | `warn`                     | Override default stderr level                            |
| `B19_VERBOSITY`         | `warn`                     | Controls which messages are visible                      |
| `B19_PAYLOAD_PID_FILE`  | `${B19_HOME}/.payload.pid` | Where the payload PID is published for signal forwarding |

Valid levels: `error`, `bad`, `warn`, `good`, `info`, `note`. The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```bash
# Custom tags for a worker process
b19-exec --stdout-tag "WORKER" --stderr-tag "WORKER" -- /app/worker.sh

# Foreground mode (exec, no return)
b19-exec --foreground -- /app/server

# Override levels via environment
export B19_EXEC_STDOUT_LEVEL=note
export B19_EXEC_STDERR_LEVEL=error
b19-exec -- my-daemon --config /etc/my-daemon.conf
```

## See also

- [Log with b19-log](use-b19-log.md) — the levels and tags used here
- [Start services in entrypoint.d](use-entrypoint.d.md) — where `5000-start.sh` sits in the startup chain
- [Handle signals gracefully](use-signals.md) — how the PID file is consumed
