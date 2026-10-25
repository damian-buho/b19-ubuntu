<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Handle signals gracefully

PID 1 is `tini -g`: it reaps zombies and forwards every signal to the whole process group. Every daemon started with `b19-exec` gets the signal once, from its own supervisor, and several daemons stop in reverse start order — so `docker stop` ends the service first, then its sidecars, each cleanly. The pitch: [graceful signal handling](../features.d/signals.md).

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
  → tini -g (PID 1)                    reaps zombies, signals the entrypoint’s process group
    → b19-exec (one per command)       traps the signal, holds a stop for newer commands
      → kill -s $SIGNAL -- -$pid       forwarded once to the command’s own process group
```

- **`tini -g`** is the base mechanism — `ENTRYPOINT ["/usr/bin/tini", "-g", "--", "entrypoint.d"]` is inherited, never redeclared. There is no `STOPSIGNAL` directive in the image: `docker stop` sends the default SIGTERM, which tini forwards to its process group.
- **`b19-exec` is the only forwarder.** Each command it supervises runs in its own session, outside that group, so the signal reaches it exactly once, through its `b19-exec`. A stop signal (`INT`, `QUIT`, `TERM`) waits until every command started later is gone, so the payload stops first and background daemons follow, last started first; [b19-exec](use-b19-exec.md#several-daemons---background---name-name) has the whole contract. `b19-exec` and its loggers outlive the stop, so a daemon’s last lines before it exits are drained, not cut off.
- **The entrypoint trap only logs.** `0000-set-signals.sh` reads `${B19_HOME}/.signals` (shipped listing `ALRM HUP ILL INT QUIT TERM USR1 USR2`, comments stripped by `decomment`) and traps each one, so the entrypoint shell survives a signal and reports the payload’s exit code. Bash runs a trap only after the foreground command ends, so this shell could never forward to a running payload. The hook also clears the `${B19_RUNTIME_PATH}/b19-exec/` records an earlier run of the container left behind.
- **`--foreground` and `docker run img <cmd>`** run inside tini’s process group, unsupervised, and get the signal straight from `tini -g`.

When the payload exits, `b19-exec` stops the background daemons, exits with the payload’s code, and `9000-finalize.sh` exits the container with it.

## Configuration

| Variable                | Default    | Effect                                                   |
| ----------------------- | ---------- | -------------------------------------------------------- |
| `B19_EXEC_STOP_TIMEOUT` | `30`       | Seconds each stop waits for the commands started later   |
| `B19_RUNTIME_PATH`      | `/run/b19` | Holds the `b19-exec/<name>.pid` records of every command |

The trapped list is the file `.container/user/app/.signals` — edit it in your payload tree to change what `b19-exec` forwards; without the file it forwards `HUP INT QUIT TERM USR1 USR2`. Keep `B19_EXEC_STOP_TIMEOUT` times the number of daemons under the orchestrator’s stop grace period (`docker stop --time`, compose `stop_grace_period`), or the last daemon is killed before its turn.

## Recipes

```bash
# Watch the forwarding happen
B19_VERBOSITY=debug docker stop <container>
```

The contract is regression-tested by `test.d/0200-b19-exec.sh`: two background daemons and a payload stop in reverse start order on SIGTERM, a required daemon’s exit stops the payload, and an optional one’s does not.

## See also

- [Manage long-running processes with b19-exec](use-b19-exec.md) — the PID publisher
- [Start containers with entrypoint.d](use-entrypoint.d.md) — slots 0000 and 9000
