<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# b19-exec

Execute long-running processes with stdout/stderr routed through b19-log.

## Usage

```bash
b19-exec [OPTIONS] -- COMMAND [ARGS...]
```

## Options

| Option           | Default  | Description                           |
| ---------------- | -------- | ------------------------------------- |
| `--stdout-level` | `info`   | Log level for stdout                  |
| `--stderr-level` | `warn`   | Log level for stderr                  |
| `--stdout-tag`   | `STDOUT` | Tag for stdout messages               |
| `--stderr-tag`   | `STDERR` | Tag for stderr messages               |
| `--foreground`   | (off)    | Run via exec (replaces shell process) |

## Environment

| Variable                | Default                    | Description                                              |
| ----------------------- | -------------------------- | -------------------------------------------------------- |
| `B19_EXEC_STDOUT_LEVEL` | `info`                     | Override default stdout level                            |
| `B19_EXEC_STDERR_LEVEL` | `warn`                     | Override default stderr level                            |
| `B19_VERBOSITY`         | `warn`                     | Controls which messages are visible                      |
| `B19_PAYLOAD_PID_FILE`  | `${B19_HOME}/.payload.pid` | Where the payload PID is published for signal forwarding |

## Modes

### Background (default)

Runs the command in the background, waits for it, and exports `PAYLOAD_PID` and `RETURN_CODE`. This is the standard pattern for entrypoint scripts where tini needs the PID for signal forwarding.

Because `b19-exec` runs as a subprocess, its `export PAYLOAD_PID` cannot reach the entrypoint shell. So it additionally publishes the payload PID to `${B19_PAYLOAD_PID_FILE:-${B19_HOME}/.payload.pid}`, which `0000-set-signals.sh` reads when forwarding signals. The file is removed when the command exits; a stale file (e.g. after `SIGKILL`) is harmless — the handler verifies the PID with `kill -0`.

### Foreground (`--foreground`)

Uses `exec` to replace the current process. The command becomes PID 1's direct child. No `PAYLOAD_PID` is exported. Use this when the entrypoint script should not continue after the command starts.

## Process Routing

```text
stdin:  /proc/1/fd/0     (container stdin)
stdout: b19-log $LEVEL $TAG -> /proc/1/fd/1
stderr: b19-log $LEVEL $TAG -> /proc/1/fd/2
```

Output from the command is intercepted via process substitution and routed through `b19-log`, which applies level filtering and colors.

## Valid Levels

`error`, `bad`, `warn`, `good`, `info`, `note`

## Examples

```bash
# Standard daemon startup (in entrypoint script)
b19-exec -- php-fpm --fpm-config /etc/php-fpm.conf

# Nginx with stderr elevated to warn
b19-exec --stderr-level warn -- nginx -g "daemon off;"

# Custom tags for a worker process
b19-exec --stdout-tag "WORKER" --stderr-tag "WORKER" -- /app/worker.sh

# Foreground mode (exec, no return)
b19-exec --foreground -- /app/server

# Override levels via environment
export B19_EXEC_STDOUT_LEVEL=note
export B19_EXEC_STDERR_LEVEL=error
b19-exec -- my-daemon --config /etc/my-daemon.conf
```
