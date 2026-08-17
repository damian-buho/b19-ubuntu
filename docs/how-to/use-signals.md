<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Handle signals gracefully

PID 1 is `tini -g`: it reaps zombies and forwards every signal to the whole process group. On top of that, a startup hook traps a configurable signal list and forwards each signal to your service by PID — so `docker stop` reaches the daemon cleanly even where process-group signalling is absent. The pitch: [graceful signal handling](../features.d/signals.md).

## When to use

- Every image: start your service with [b19-exec](use-b19-exec.md) from slot 5000 and signal handling is wired — nothing else to do.
- Custom payloads or special shutdown choreography: edit the trapped-signal list or add your own trap behavior.

## Quick start

```bash
# .container/user/entrypoint.d/5000-start.sh
b19-exec -- my-daemon --config "${B19_HOME}/config.yaml"
```

```bash
docker stop <container>   # SIGTERM reaches my-daemon; exit code propagates
```

## How it works

```text
docker stop / kill
  → tini -g (PID 1)                    reaps zombies, signals the process group
    → signalHandler()                  trap set by 0000-set-signals.sh
      → kill -s $SIGNAL $payload_pid   forwarded to the service
```

Two layers, deliberately redundant:

- **`tini -g`** is the base mechanism — `ENTRYPOINT ["/usr/bin/tini", "-g", "--", "entrypoint.d"]` is inherited, never redeclared. There is no `STOPSIGNAL` directive in the image: `docker stop` sends the default SIGTERM, which tini forwards.
- **The trap chain** matters where the process group is not signalled (some Kubernetes runtimes drop `tini`’s group semantics): `0000-set-signals.sh` reads `${B19_HOME}/.signals` (shipped listing `ALRM HUP ILL INT QUIT TERM USR1 USR2`, comments stripped by `decomment`), traps each one, and the handler resolves the payload PID from `${B19_PAYLOAD_PID_FILE:-${B19_HOME}/.payload.pid}` — published by `b19-exec`, because its subprocess `export PAYLOAD_PID` cannot reach the entrypoint shell — falling back to a shell-set `PAYLOAD_PID`. The handler verifies the PID is alive with `kill -0` before forwarding, so a stale file after `SIGKILL` is harmless.

When the service exits, `b19-exec` exports `RETURN_CODE`, removes the PID file, and `9000-finalize.sh` exits the container with it.

## Configuration

| Variable               | Default                    | Effect                                   |
| ---------------------- | -------------------------- | ---------------------------------------- |
| `B19_PAYLOAD_PID_FILE` | `${B19_HOME}/.payload.pid` | Where b19-exec publishes the service PID |

The trapped list is the file `.container/user/app/.signals` — edit it in your payload tree to change what the handler catches; a missing file disables the traps cleanly.

## Recipes

```bash
# Watch the forwarding happen
B19_VERBOSITY=debug docker stop <container>
```

The contract is regression-tested by `test.d/0200-b19-exec.sh`: a backgrounded `b19-exec` publishes a live PID during the run and removes the file after exit.

## See also

- [Manage long-running processes with b19-exec](use-b19-exec.md) — the PID publisher
- [Start containers with entrypoint.d](use-entrypoint.d.md) — slots 0000 and 9000
