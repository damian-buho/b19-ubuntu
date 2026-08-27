<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Start containers with entrypoint.d

`entrypoint.d` is the numbered-hook runner that orchestrates every container startup: under `tini -g` it sources `/entrypoint.d/*.sh` in ascending order — signals, secrets, CPU detection, port validation, overlays, template rendering, bootstrap, and finally slot 5000 where your service starts. The pitch: [pluggable startup system](../features.d/entrypoint.d.md).

## When to use

- Building any downstream image: overriding `5000-start.sh` is mandatory, everything else is inherited.
- Adding startup preparation (TLS, registry logins, autotuning) without touching the Dockerfile.

## Quick start

```bash
# .container/user/entrypoint.d/5000-start.sh — the one hook every project writes
#!/usr/bin/env bash

if [ "${ENTRYPOINT_COMMAND_EXECUTED}" = "N" ]; then
  b19-exec -- my-service --config "${B19_HOME}/config.yaml"
fi
```

Do not redeclare `ENTRYPOINT` or `HEALTHCHECK` in the Dockerfile — they are inherited:

```dockerfile
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "entrypoint.d"]
HEALTHCHECK CMD ["healthcheck.d"]
```

## How it works

```text
tini -g (PID 1)
  └─ entrypoint.d (runner: /tools.d/entrypoint.d)
       └─ sources /entrypoint.d/*.sh in numeric order
```

- `tini -g` reaps zombies and forwards signals to the process group.
- The runner finds all `*.sh` in `/entrypoint.d/`, sorts ascending and **sources** each one — shared shell state, no subshells, so variables (`NUMPROCS`, `ENTRYPOINT_COMMAND_EXECUTED`, `PAYLOAD_PID`) are visible to every subsequent hook.
- Two projects’ hooks merge by Docker layer overlay: the runner finds all `*.sh` regardless of which image layer added them.

### Base image hook chain

| Slot | Script                | Purpose                                                                                                                  |
| ---- | --------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| 0000 | `set-signals.sh`      | Trap Unix signals (ALRM, HUP, ILL, INT, QUIT, TERM, USR1, USR2), define `signalHandler()` that forwards to `PAYLOAD_PID` |
| 0050 | `ensure-locale.sh`    | Make the compiled locale available to the shell                                                                          |
| 0100 | `load-secrets.sh`     | Source `b19-load-secrets` → env vars from `/run/secrets/*.*`                                                             |
| 0200 | `set-cpu-count.sh`    | Detect `NUMPROCS`: K8s downward API > cgroups v2 > nproc                                                                 |
| 0300 | `check-ports.sh`      | Validate PORT env vars against WHATWG blocklist + privileged ports (\<1024)                                              |
| 0400 | `print-lineage.sh`    | Log the image lineage chain (base → current)                                                                             |
| 0500 | `copy-overlay.sh`     | Copy files from `$B19_OVERLAYS_PATH/$B19_OVERLAY/` to `/` if `B19_OVERLAY` is set                                        |
| 1000 | `parallel-j2.sh`      | Render all `.j2` templates in `$B19_HOME` via minijinja-cli + `xargs -P`                                                 |
| 2000 | `run-command.sh`      | If first arg is a valid command: execute it, set `ENTRYPOINT_COMMAND_EXECUTED=Y`; if it is not, exit 127                 |
| 2100 | `validate-secrets.sh` | Validate all secrets in `B19_REQUIRED_SECRETS` exist (env or file); exit 1 if missing                                    |
| 3000 | `bootstrap.sh`        | Run `/bootstrap.d/` scripts with lockfile idempotency                                                                    |
| 5000 | `start.sh`            | Default: `sleep infinity` (downstream projects **always** override this)                                                 |
| 9000 | `finalize.sh`         | Log the final `RETURN_CODE`                                                                                              |

### Two execution paths

**Service mode** (`docker run img`, no args):

```text
0000 → 0100 → … → 2000 (ENTRYPOINT_COMMAND_EXECUTED=N) → 2100 (validates secrets) → 3000 (bootstrap) → 5000 (starts service) → 9000
```

**Ad-hoc command** (`docker run img some-command`):

```text
0000 → 0100 → … → 2000 (executes command, ENTRYPOINT_COMMAND_EXECUTED=Y) → 2100 (skips) → 3000 (skips) → 5000 (skips) → 9000
```

**Unknown command** (`docker run img typo`):

```text
0000 → 0100 → … → 2000 (exit 127)
```

A command was asked for and the image does not carry it, so the run fails closed
with the shell’s `127` — it does **not** fall through to bootstrap and start. The
old fall-through logged a warning and finished green, so a stale image reported
success for a run that executed nothing. `B19_ENTRYPOINT_SKIP_RUN_COMMAND=true`
skips the hook entirely if a lineage really needs the argv ignored.

The `ENTRYPOINT_COMMAND_EXECUTED` flag gates secret validation, bootstrap and service start — ad-hoc commands like `docker run img mysqldump` bypass the full startup sequence.

### Numbering convention

| Range     | Purpose                       | Reserved by                                |
| --------- | ----------------------------- | ------------------------------------------ |
| 0000-0099 | System fundamentals           | b19/Ubuntu (signals)                       |
| 0100-0199 | Environment setup             | b19/Ubuntu (secrets, CPU)                  |
| 0200-0499 | Validation and checks         | shared (ports, lineage, autotune)          |
| 0500-0999 | File/overlay operations       | b19/Ubuntu (overlay)                       |
| 1000-1999 | Rendering and preparation     | shared (TLS, SSH, j2)                      |
| 2000-2999 | Command execution and secrets | b19/Ubuntu (run-command, validate-secrets) |
| 3000-4999 | Bootstrap and post-init       | b19/Ubuntu (bootstrap.d), downstream       |
| 5000-8999 | Start the main service        | downstream project                         |
| 9000-9999 | Finalization                  | b19/Ubuntu                                 |

When creating hooks for a downstream project, pick a slot in the appropriate range. The same numbered-hook pattern powers seven more lifecycle runners — see [use the runner family](use-runner-family.md) for the full family and how entrypoint.d differs (sourced hooks, fail-fast).

### Signal flow

```text
docker stop / kill
  → tini (PID 1)
    → signalHandler() (defined in 0000-set-signals.sh)
      → kill -s $SIGNAL $payload_pid
        → your service process
```

`0000-set-signals.sh` reads `/app/.signals` and traps each signal listed there. The handler resolves the payload PID from `${B19_HOME}/.payload.pid` (written by `b19-exec`), falling back to a `PAYLOAD_PID` set directly in the shell, verifies it is alive with `kill -0`, then forwards the signal. Under `tini -g` signals also reach the whole process group directly, so forwarding is belt-and-suspenders — it matters when `tini -g` is absent, e.g. some Kubernetes runtimes. Detail: [handle signals gracefully](use-signals.md).

### Delegated runners

Slot 3000 hands off to [bootstrap.d](use-bootstrap.d.md) (run-once-per-volume initialization with lockfiles). After the chain completes, [healthcheck.d](use-healthcheck.d.md) keeps watching the container on Docker’s schedule, [shell.d](use-shell-hooks.md) enhances interactive shells, and [test.d](use-test.d.md) runs the in-container test suite on `make test`. Each has its own article.

## Configuration

### Feature toggles (all default-enabled)

| Variable                 | Default | Set to disable                  |
| ------------------------ | ------- | ------------------------------- |
| `B19_HEALTH_ENABLED`     | `true`  | `false` — skip all healthchecks |
| `B19_BOOTSTRAP_ENABLED`  | `true`  | `false` — skip bootstrap        |
| `B19_TEST_ENABLED`       | `true`  | `false` — skip tests            |
| `B19_SECRETS_ENABLED`    | `true`  | `false` — skip secrets loading  |
| `B19_PORT_CHECK_ENABLED` | `true`  | `false` — skip port validation  |
| `B19_I18N_ENABLED`       | `true`  | `false` — disable translations  |
| `B19_SHELL_ENABLED`      | `true`  | `false` — disable shell.d hooks |

### Set at runtime by the system

| Variable                      | Set by                  | Purpose                                     |
| ----------------------------- | ----------------------- | ------------------------------------------- |
| `ENTRYPOINT_COMMAND_EXECUTED` | `2000-run-command.sh`   | `Y`/`N` — gates bootstrap and service start |
| `PAYLOAD_PID`                 | `b19-exec`              | PID of the main service process             |
| `RETURN_CODE`                 | `b19-exec`              | Exit code of the main service               |
| `NUMPROCS`                    | `0200-set-cpu-count.sh` | Detected CPU count                          |

Path and behavior variables (`B19_HOME`, `B19_VERBOSITY`, `B19_OVERLAY`, `B19_REQUIRED_SECRETS`, …) are indexed in [configure-environment](configure-environment.md).

## Recipes

Every hook that must not run for ad-hoc commands checks the gate first. Common slot choices from real projects:

| Slot | Script                 | What it does                                       |
| ---- | ---------------------- | -------------------------------------------------- |
| 0200 | `map-log-level.sh`     | Maps `B19_VERBOSITY` to service log level          |
| 0300 | `autotune.sh`          | Calculates pool size, max connections from RAM/CPU |
| 1250 | `keyscan.sh`           | SSH keyscan for remote hosts                       |
| 1400 | `login-to-registry.sh` | Docker registry login                              |
| 1500 | `tls-ca.sh`            | Generate self-signed CA                            |
| 1600 | `tls-certs.sh`         | Generate mTLS server + client certs                |

```bash
# .container/user/entrypoint.d/1500-setup-tls.sh
#!/usr/bin/env bash

if [ "${ENTRYPOINT_COMMAND_EXECUTED}" = "N" ]; then
  if [ ! -f "${B19_HOME}/tls/cert.pem" ]; then
    openssl req -x509 -newkey rsa:4096 \
      -keyout "${B19_HOME}/tls/key.pem" \
      -out "${B19_HOME}/tls/cert.pem" \
      -days 365 -nodes -subj "/CN=my-service"
    b19-log info "TLS" "$(_p "Generated certificate for %s" "my-service")"
  fi
fi
```

```bash
# Pattern: override 9000-finalize.sh for cleanup
rm -f /var/run/service/service.pid
```

Root-only operations belong in the `base` stage: a hook placed in `.container/base/entrypoint.d/` runs as root before the user-stage hooks merge in (e.g. `1400-login-to-registry.sh`, because Docker login requires root).

All user-facing strings in hooks go through `_()` / `_p()` from [b19-i18n](use-i18n.md) — the runner sources it before any hook runs.

## Filesystem layout inside the container

The Dockerfile copies two trees to `/`:

```dockerfile
COPY .container/foundation/ /    # root-owned: tools.d, command.d, locale, build.d
USER ${B19_UID}
COPY .container/user/       /    # user-owned: entrypoint.d, healthcheck.d, test.d, bootstrap.d, shell.d, overlays, app
```

```text
/entrypoint.d/       # Numbered startup hooks (0000-9999)
/healthcheck.d/      # Numbered health checks
/test.d/             # Test scripts (descending order)
/bootstrap.d/        # One-time init scripts (lock-file guarded)
/command.d/          # Executable commands (e.g., get-ubuntu-version)
/tools.d/            # Runner scripts and tools (on PATH)
/shell.d/            # Shell login hooks (docker exec)
/overlays/           # Overlay directories (applied at startup)
/locale/             # Translation files (.po → .mo at build time)
/app/                # B19_HOME, working directory
```

## See also

- [Use the runner family](use-runner-family.md) — the eight numbered-hook runners compared
- [Manage long-running processes with b19-exec](use-b19-exec.md) — what slot 5000 should call
- [Handle signals gracefully](use-signals.md) — the PID file and trap chain in depth
- [Ship files with overlays](use-overlays.md) — what the 0500 hook copies
- [Render templates with minijinja](use-templating.md) — what the 1000 hook renders
