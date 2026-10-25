<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Manage long-running processes with b19-exec

`b19-exec` starts a daemon and keeps its output readable for the container’s lifetime: stdout and stderr are routed through `b19-log` with independent levels and tags, every signal reaches the command once, and several daemons in one container start, stop and fail together. The pitch: [service process management with log routing](../features.d/b19-exec.md).

## When to use

- The `5000-start.sh` entrypoint hook starting the image’s service.
- Any long-running child whose output should obey `B19_VERBOSITY` instead of spewing raw to the console.
- A second daemon beside the service (sshd next to a web server), started with `--background` from an earlier hook.

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

Output is intercepted via process substitution and routed through `b19-log`. The stream is piped, and `b19-log` never level-filters piped input, so `--stdout-level`/`--stderr-level` only pick the tag color — payload output always reaches the console:

```text
stdin:  /proc/1/fd/0     (container stdin)
stdout: b19-log $LEVEL $TAG -> /proc/1/fd/1
stderr: b19-log $LEVEL $TAG -> /proc/1/fd/2
```

### Passthrough (`--passthrough`)

The payload’s stdout and stderr go straight to the container’s, with no `b19-log` in between: every byte the daemon writes is what the log collector reads, and no logger process runs per line. Use it for a daemon whose own output is the log a parser expects verbatim — a JSON access log, nginx error lines, sshd. `B19_VERBOSITY`, levels and tags no longer apply to that output; the daemon’s own log level does. `B19_EXEC_PASSTHROUGH=true` sets it from the environment, so an operator can switch without an image change.

### Supervision (default)

`b19-exec` stays alive as the command’s supervisor. The command runs in its own session, so `tini -g` cannot signal it directly: the supervisor traps every signal in `${B19_HOME}/.signals` and forwards it to the command’s whole process group, exactly once. It then waits for the command, drains both loggers and exits with the command’s code.

Each supervised command is recorded as `${B19_RUNTIME_PATH}/b19-exec/<name>.pid`, holding `PID ROLE` (`payload`, `required` or `optional`). The record is written under a lock and removed when the command exits; `0000-set-signals.sh` clears what an earlier run of the container left behind. Without `--name` the record is `payload.pid`; a second unnamed call while one runs is not recorded and logs a warning.

### Several daemons (`--background --name NAME`)

```bash
# 4500-start-sshd.sh
b19-exec --background --name sshd -- /usr/sbin/sshd -D -e
# 5000-start.sh
b19-exec --name forgejo -- forgejo web
```

`--background` starts the command under its own supervisor and returns as soon as it is recorded, so the hooks go on; a command that exits before that makes the call fail with its exit code. `--name` names the record and tags both streams, so under `B19_LOG_FORMAT=json` every line says `"tag":"sshd"`. The last call without `--background` is the payload. A background command reads `/dev/null`, never the container’s stdin.

- **Stop order.** A stop signal (`INT`, `QUIT`, `TERM`) is held until every command started later is gone, so the payload stops first and background daemons follow, last started first. Other signals (`HUP`, `USR1`, …) are forwarded at once. A repeated stop signal is logged and not forwarded again, so a double delivery is harmless. `B19_EXEC_STOP_TIMEOUT` bounds each wait; past it the stop goes ahead and a warning names what still runs.
- **Payload exit.** When the payload exits for any reason, its `b19-exec` stops every background daemon in that order and waits for each daemon and its supervisor before exiting, so the container never ends with a daemon still writing or a record left behind.
- **Fail-fast.** The payload’s `b19-exec` watches every required daemon. When one exits, it logs the name, PID and exit code, stops the payload, and exits with that daemon’s code (`1` if the daemon exited `0`), so the restart policy acts. A payload started after a required daemon already died refuses to start. `--optional` (a file watcher) only logs a warning. The `0900-check-daemons` health check fails while a required daemon is gone.

### Foreground mode (`--foreground`)

Runs the command inline, with the same log routing and drain, but neither supervises nor records it. Signals reach it straight from `tini -g`, as part of the entrypoint’s process group.

## Configuration

| Option           | Default   | Description                             |
| ---------------- | --------- | --------------------------------------- |
| `--stdout-level` | `info`    | Log level for stdout                    |
| `--stderr-level` | `warn`    | Log level for stderr                    |
| `--stdout-tag`   | `STDOUT`  | Tag for stdout messages                 |
| `--stderr-tag`   | `STDERR`  | Tag for stderr messages                 |
| `--foreground`   | (off)     | Run inline, unsupervised and unrecorded |
| `--background`   | (off)     | Supervise in the background and return  |
| `--name`         | `payload` | Record name, and tag of both streams    |
| `--optional`     | (off)     | A background exit only logs             |
| `--passthrough`  | (off)     | Payload output bypasses `b19-log`       |

| Variable                | Default    | Description                                             |
| ----------------------- | ---------- | ------------------------------------------------------- |
| `B19_EXEC_STDOUT_LEVEL` | `info`     | Override default stdout level                           |
| `B19_EXEC_STDERR_LEVEL` | `warn`     | Override default stderr level                           |
| `B19_EXEC_PASSTHROUGH`  | `false`    | `true` defaults to `--passthrough`; another value fails |
| `B19_VERBOSITY`         | `warn`     | Controls which messages are visible                     |
| `B19_EXEC_STOP_TIMEOUT` | `30`       | Seconds each stop waits for the commands started later  |
| `B19_RUNTIME_PATH`      | `/run/b19` | Holds the `b19-exec/<name>.pid` records                 |

Valid levels: `error`, `bad`, `warn`, `good`, `info`, `note`. The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```bash
# Custom tags for a worker process
b19-exec --stdout-tag "WORKER" --stderr-tag "WORKER" -- /app/worker.sh

# Foreground mode (inline, unsupervised)
b19-exec --foreground -- /app/server

# A daemon whose JSON access log must reach the collector byte for byte
b19-exec --passthrough -- traefik --configfile /app/traefik.yaml

# Override levels via environment
export B19_EXEC_STDOUT_LEVEL=note
export B19_EXEC_STDERR_LEVEL=error
b19-exec -- my-daemon --config /etc/my-daemon.conf
```

## See also

- [Log with b19-log](use-b19-log.md) — the levels and tags used here
- [Start services in entrypoint.d](use-entrypoint.d.md) — where `5000-start.sh` sits in the startup chain
- [Handle signals gracefully](use-signals.md) — how a stop reaches every daemon
