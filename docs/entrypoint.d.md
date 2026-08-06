<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# entrypoint.d — Container Startup System

The numbered-hook runner that orchestrates every container startup in the ecosystem.

## Architecture

Every b19-based container uses the same init chain:

```text
tini -g (PID 1)
  └─ entrypoint.d (runner: /tools.d/entrypoint.d)
       └─ sources /entrypoint.d/*.sh in numeric order
```

- `tini -g` reaps zombies and forwards signals to the process group
- The runner (`/tools.d/entrypoint.d`) finds all `*.sh` in `/entrypoint.d/`, sorts ascending, and **sources** each one (shared shell state — no subshells)
- Scripts are sourced, not executed, so variables (`NUMPROCS`, `ENTRYPOINT_COMMAND_EXECUTED`, `PAYLOAD_PID`) are visible to all subsequent scripts

## Wiring in Dockerfile

```dockerfile
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "entrypoint.d"]
HEALTHCHECK CMD ["healthcheck.d"]
```

The runner lives at `/tools.d/entrypoint.d` (added to `PATH` by the Dockerfile). Both `entrypoint.d` and `healthcheck.d` are bare command names resolved through `PATH`.

## Hook Execution Order

### Base image (b19/Ubuntu)

| Slot | Script                | Purpose                                                                                                                  |
| ---- | --------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| 0000 | `set-signals.sh`      | Trap Unix signals (ALRM, HUP, ILL, INT, QUIT, TERM, USR1, USR2), define `signalHandler()` that forwards to `PAYLOAD_PID` |
| 0100 | `load-secrets.sh`     | Source `b19-load-secrets` → env vars from `/run/secrets/*.*`                                                             |
| 0200 | `set-cpu-count.sh`    | Detect `NUMPROCS`: K8S downward API > cgroups v2 > nproc                                                                 |
| 0300 | `check-ports.sh`      | Validate PORT env vars against WHATWG blocklist + privileged ports (\<1024)                                              |
| 0400 | `print-lineage.sh`    | Log the image lineage chain (base → current)                                                                             |
| 0500 | `copy-overlay.sh`     | Copy files from `$B19_OVERLAYS_PATH/$B19_OVERLAY/` to `/` if `B19_OVERLAY` is set                                        |
| 1000 | `parallel-j2.sh`      | Render all `.j2` templates in `$B19_HOME` via minijinja-cli + `xargs -P`                                                 |
| 2000 | `run-command.sh`      | If first arg is a valid command: execute it, set `ENTRYPOINT_COMMAND_EXECUTED=Y`                                         |
| 2100 | `validate-secrets.sh` | Validate all secrets in `B19_REQUIRED_SECRETS` exist (env or file); exit 1 if missing                                    |
| 3000 | `bootstrap.sh`        | Run `/bootstrap.d/` scripts with lockfile idempotency                                                                    |
| 5000 | `start.sh`            | Default: `sleep infinity` (downstream projects **always** override this)                                                 |
| 9000 | `finalize.sh`         | Log the final `RETURN_CODE`                                                                                              |

### Two Execution Paths

**Service mode** (`docker run img`, no args):

```text
0000 → 0100 → ... → 2000 (ENTRYPOINT_COMMAND_EXECUTED=N) → 2100 (validates secrets) → 3000 (bootstrap) → 5000 (starts service) → 9000
```

**Ad-hoc command** (`docker run img some-command`):

```text
0000 → 0100 → ... → 2000 (executes command, ENTRYPOINT_COMMAND_EXECUTED=Y) → 2100 (skips) → 3000 (skips) → 5000 (skips) → 9000
```

The `ENTRYPOINT_COMMAND_EXECUTED` flag gates secret validation, bootstrap, and service start. This means ad-hoc commands like `docker exec img bash` or `docker run img mysqldump` bypass the full startup sequence.

## Numbering Convention

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

When creating hooks for a downstream project, pick a slot in the appropriate range. Two projects’ hooks merge by Docker layer overlay — the runner finds all `*.sh` regardless of which image layer added them.

## Parallel Runner Family

The same runner pattern (`fd *.sh | sort | source/execute`) is used across all lifecycle hooks:

| Runner          | Location                 | Sort           | Failure mode                                            |
| --------------- | ------------------------ | -------------- | ------------------------------------------------------- |
| `entrypoint.d`  | `/tools.d/entrypoint.d`  | ascending      | fail fast (`set -e`)                                    |
| `healthcheck.d` | `/tools.d/healthcheck.d` | ascending      | continues, counts failures                              |
| `test.d`        | `/tools.d/test.d`        | **descending** | continues, counts failures; waits for healthcheck first |
| `bootstrap.d`   | `/tools.d/bootstrap.d`   | ascending      | fail fast; lockfile idempotency                         |
| `benchmark.d`   | `/tools.d/benchmark.d`   | ascending      | continues per suite                                     |
| `report.d`      | `/tools.d/report.d`      | descending     | always succeeds                                         |
| `build-stage`   | `/tools.d/build-stage`   | ascending      | fail fast with ERR trap                                 |

Key differences:

- `entrypoint.d` sources scripts (shared state). Other runners execute in subshells.
- `test.d` sorts descending so higher-numbered tests run first.
- `healthcheck.d` uses `flock` to prevent overlapping runs and forces `B19_COLOR=0` (output stored by Docker).
- `bootstrap.d` creates a lockfile per script (`$B19_BOOTSTRAP_LOCK_PATH/.{name}.bootstrap`) to ensure idempotency across container restarts.

## Starting a Service (5000-start.sh)

Every downstream project overrides slot 5000 to launch its payload via `b19-exec`:

```bash
#!/usr/bin/env bash

if [ "${ENTRYPOINT_COMMAND_EXECUTED}" = "N" ]; then
  b19-exec -- my-daemon --config "${B19_HOME}/config.yaml"
fi
```

`b19-exec` backgrounds the process, routes stdout/stderr through `b19-log`, sets `PAYLOAD_PID` for signal forwarding, and waits. When the process exits, `RETURN_CODE` is exported.

The base image’s `5000-start.sh` does `sleep infinity` — it is always replaced by the downstream Dockerfile’s `COPY .container/user/ /`.

## Signal Flow

```text
docker stop / kill
  → tini (PID 1)
    → signalHandler() (defined in 0000-set-signals.sh)
      → kill -s $SIGNAL $payload_pid
        → your service process
```

`0000-set-signals.sh` reads `/app/.signals` (ALRM, HUP, ILL, INT, QUIT, TERM, USR1, USR2) and traps each one. The handler resolves the payload PID from `${B19_HOME}/.payload.pid` (written by `b19-exec`), falling back to a `PAYLOAD_PID` set directly in the shell, verifies it is alive with `kill -0`, then forwards the signal.

`b19-exec` runs as a subprocess, so its `export PAYLOAD_PID` does not reach the entrypoint shell — the PID file is what bridges that boundary. (Under `tini -g` signals also reach the whole process group directly, so forwarding is belt-and-suspenders; it matters when `tini -g` is absent, e.g. some Kubernetes runtimes.)

## Bootstrap System

`3000-bootstrap.sh` invokes the `bootstrap.d` runner, which:

1. Finds all `*.sh` in `/bootstrap.d/`, sorted ascending
1. For each script: checks for a lockfile at `$B19_BOOTSTRAP_LOCK_PATH/.{name}.bootstrap`
1. If lock exists → skip (already ran)
1. If not → execute the script, create lockfile on success
1. On failure → stop and exit 1

Bootstrap scripts run **once per container lifecycle**. They persist across `docker restart` (lockfiles survive if volumes are used). Example:

```bash
# bootstrap.d/100-init-db.sh
if [ ! -d "${O9S_MARIADB_DATA_PATH}/mysql" ]; then
  mariadb-install-db --datadir="${O9S_MARIADB_DATA_PATH}"
fi
```

## Downstream Extension Patterns

### Pattern 1: Override 5000-start.sh

The most common pattern. Every service project replaces the start hook:

```bash
# database example
b19-exec -- mariadbd --defaults-file="${B19_HOME}/my.cnf"

# daemon example
b19-exec -- /usr/bin/dockerd --config-file /app/daemon.json

# proxy example
b19-exec -- tor --defaults-torrc "${B19_HOME}/torrc-defaults"
```

### Pattern 2: Add preparatory hooks

Insert hooks at appropriate number slots to prepare state before service start:

| Slot | Script                   | What it does                                       |
| ---- | ------------------------ | -------------------------------------------------- |
| 0200 | `map-log-level.sh`       | Maps `B19_VERBOSITY` to service log level          |
| 0300 | `autotune.sh`            | Calculates pool size, max connections from RAM/CPU |
| 1400 | `login-to-registry.sh`   | Docker registry login                              |
| 1500 | `tls-ca.sh`              | Generate self-signed CA                            |
| 1600 | `tls-certs.sh`           | Generate mTLS server + client certs                |
| 0250 | `extorport-docker-ip.sh` | Discover Docker-assigned IP                        |
| 0300 | `tune-cpu.sh`            | Set `NumCPUs` from `NUMPROCS`                      |
| 1250 | `keyscan.sh`             | SSH keyscan for remote hosts                       |
| 1500 | `build-registry.sh`      | Build package registry                             |

### Pattern 3: Override finalize (9000)

Some projects replace `9000-finalize.sh` for cleanup:

```bash
# clean up stale PID file
rm -f /var/run/service/service.pid
```

### Pattern 4: Stage-specific entrypoint hooks

Projects with a `base` stage (root operations) can place entrypoint hooks in `.container/base/entrypoint.d/` instead of `.container/user/entrypoint.d/`. For example, placing `1400-login-to-registry.sh` in `base/` because Docker login requires root.

### Pattern 5: Add bootstrap scripts

```bash
# .container/user/bootstrap.d/100-init-db.sh
# Runs once; lock file prevents re-runs across container restarts
```

## Healthcheck System

`HEALTHCHECK CMD ["healthcheck.d"]` is inherited from b19/Ubuntu. The runner:

1. Acquires a `flock` to prevent overlapping executions
1. Forces `B19_COLOR=0` (output stored by `docker inspect`)
1. Loads secrets (healthchecks run outside entrypoint context)
1. Sources each `/healthcheck.d/*.sh` in a **subshell** (failures don’t abort the container)
1. Counts failures and exits with the failure count

Base healthchecks (b19/Ubuntu):

| Slot | Script                           | Check                                                 |
| ---- | -------------------------------- | ----------------------------------------------------- |
| 050  | `check-home-directory-space.sh`  | `$B19_HOME` has >32MB free                            |
| 060  | `check-cache-directory-space.sh` | `$XDG_CACHE_HOME` has >32MB free                      |
| 070  | `check-temp-directory-space.sh`  | `$B19_TEMP_PATH` has >32MB free                       |
| 080  | `check-https-connectivity.sh`    | At least one URL in `B19_HEALTH_NETWORK_URL` responds |
| 085  | `check-dns-resolution.sh`        | At least one hostname resolves                        |
| 090  | `check-ping-connectivity.sh`     | At least one IP in `B19_HEALTH_PING_TARGETS` responds |
| 100  | `check-dummy.sh`                 | Can write/delete a file in `B19_HEALTH_PATH`          |

Downstream projects add service-specific checks at slot 100+.

## Test System

`make test` invokes `test.d` (the runner). It:

1. Waits for `healthcheck.d` to pass (up to `B19_TEST_TIMEOUT` seconds)
1. Runs `/test.d/*.sh` in **descending** order
1. Continues on failure; reports total failures at end

## Shell Hooks (`shell.d/`)

Scripts in `/shell.d/` are sourced on interactive shell login (`docker exec bash`). The base image provides `010-load-secrets.sh` so secrets are available in interactive sessions.

## Environment Variables

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

### Paths

| Variable                  | Default                  | What it points to              |
| ------------------------- | ------------------------ | ------------------------------ |
| `B19_HOME`                | `/app`                   | Working directory              |
| `B19_ENTRYPOINT_PATH`     | `/entrypoint.d`          | Entrypoint scripts directory   |
| `B19_HEALTH_PATH`         | `/healthcheck.d`         | Healthcheck scripts directory  |
| `B19_TEST_PATH`           | `/test.d`                | Test scripts directory         |
| `B19_BOOTSTRAP_PATH`      | `/bootstrap.d`           | Bootstrap scripts directory    |
| `B19_SECRETS_PATH`        | `/run/secrets`           | Docker secrets mount point     |
| `B19_BOOTSTRAP_LOCK_PATH` | `${B19_HOME}/.bootstrap` | Lock directory for idempotency |
| `B19_OVERLAYS_PATH`       | `/overlays/`             | Overlay base path              |

### Behavior

| Variable               | Default          | Effect                                                      |
| ---------------------- | ---------------- | ----------------------------------------------------------- |
| `B19_VERBOSITY`        | `warn`           | Log threshold: error (40), warn (30), info (20), debug (10) |
| `B19_COLOR`            | `1`              | `1`, `0`, `auto` (auto = TTY check; `NO_COLOR=1` overrides) |
| `B19_IMMUTABLE`        | `N`              | `Y` skips overlays and j2 rendering                         |
| `B19_OFFGRID_MODE`     | `N`              | `Y` for air-gapped (no downloads, no network checks)        |
| `B19_OVERLAY`          | (unset)          | Name of overlay to apply at startup                         |
| `B19_REQUIRED_SECRETS` | (empty)          | Space-separated secret names to validate                    |
| `B19_RUNTIME_MODE`     | `docker-compose` | Runtime environment identifier                              |
| `B19_TEST_TIMEOUT`     | `60`             | Seconds to wait for healthcheck before tests                |
| `M6E_AI`               | `N`              | `Y` suppresses colors/hints for CI                          |

### Set at runtime by the system

| Variable                      | Set by                  | Purpose                                     |
| ----------------------------- | ----------------------- | ------------------------------------------- |
| `ENTRYPOINT_COMMAND_EXECUTED` | `2000-run-command.sh`   | `Y`/`N` — gates bootstrap and service start |
| `PAYLOAD_PID`                 | `b19-exec`              | PID of the main service process             |
| `RETURN_CODE`                 | `b19-exec`              | Exit code of the main service               |
| `NUMPROCS`                    | `0200-set-cpu-count.sh` | Detected CPU count                          |

## i18n Integration

All entrypoint scripts use the `_()`, `_e()`, `_p()` functions from `b19-i18n` for translatable strings:

- `_ "string"` — translate a static string
- `_e "string with $var"` — translate with variable interpolation
- `_p "format %s" "$arg"` — translate with printf-style arguments

The runner sources `b19-i18n` before any hooks run. Languages: `en_US.UTF-8` (default), `es_CL.UTF-8`, `uk_UA.UTF-8`. See `docs/I18N.md` for details.

## Creating a New Downstream Project

1. Create `.container/user/entrypoint.d/5000-start.sh` — this is mandatory
1. Optionally add hooks at other slots for preparation, validation, or cleanup
1. Do NOT redeclare `ENTRYPOINT` or `HEALTHCHECK` in the Dockerfile — they are inherited
1. Use `b19-exec --` to start the service process
1. Use `b19-log` for all logging; respect `B19_VERBOSITY`
1. Wrap all user-facing strings in `_()` or `_p()` for i18n
1. Use `ENTRYPOINT_COMMAND_EXECUTED` to gate service-only logic

### Minimal 5000-start.sh

```bash
#!/usr/bin/env bash

if [ "${ENTRYPOINT_COMMAND_EXECUTED}" = "N" ]; then
  b19-exec -- my-service --config "${B19_HOME}/config.yaml"
fi
```

### Adding a preparatory hook

```bash
#!/usr/bin/env bash
# .container/user/entrypoint.d/1500-setup-tls.sh

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

## Filesystem Layout Inside Container

The Dockerfile copies two directories to `/`:

```dockerfile
COPY .container/foundation/ /    # root-owned: tools.d, command.d, locale, build.d
USER ${B19_UID}
COPY .container/user/       /    # user-owned: entrypoint.d, healthcheck.d, test.d, bootstrap.d, shell.d, overlays, app
```

Resulting runtime structure:

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
/app/.signals        # List of trapped UNIX signals
```
