<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# bootstrap.d — Run-Once Initialization System

The numbered-script runner that executes idempotent, one-time setup tasks the first
time a container starts (or after its state is reset). Each bootstrap script runs
exactly once per container volume lifetime, tracked by lockfiles.

## Architecture

```text
Container start (tini → entrypoint.d)
  ├─ 0000-set-signals.sh
  ├─ 0100-load-secrets.sh
  ├─ ...
  ├─ 2000-run-command.sh        ← detects CMD vs long-run
  ├─ 2100-validate-secrets.sh
  ├─ 3000-bootstrap.sh          ← calls bootstrap.d runner
  │    └─ /tools.d/bootstrap.d (runner)
  │         └─ executes /bootstrap.d/*.sh (ascending, with per-script locks)
  ├─ 5000-start.sh              ← sleep infinity if no CMD
  └─ 9000-finalize.sh
```

The runner is invoked by the entrypoint hook
`.container/user/entrypoint.d/3000-bootstrap.sh`:

```bash
if [ "${ENTRYPOINT_COMMAND_EXECUTED}" = "N" ]; then
    bootstrap.d
fi
```

This guard means bootstrap runs only when no explicit command was passed to the
container. If `docker run myimage some-command` is used, the command executes
directly (via `2000-run-command.sh`) and bootstrap is skipped.

## Runner Lifecycle

The runner is `/tools.d/bootstrap.d` (source:
`.container/foundation/tools.d/bootstrap.d`). When invoked:

1. Checks `B19_BOOTSTRAP_ENABLED` — exits 0 immediately if `false`
1. Enables `set -eo pipefail` for strict error handling
1. Sources `b19-i18n` for `_()`, `_p()` translation functions
1. Resolves `BOOTSTRAP_PATH` from `B19_BOOTSTRAP_PATH` (default `/bootstrap.d`)
1. Resolves `LOCK_PATH` from `B19_BOOTSTRAP_LOCK_PATH` (default `$B19_HOME/.bootstrap`)
1. Creates `LOCK_PATH` directory if it doesn’t exist
1. Finds all `*.sh` in `BOOTSTRAP_PATH`, sorts ascending (`sort -zn`)
1. For each script:
    - Computes lockfile: `${LOCK_PATH}/.${BASENAME}.bootstrap`
    - If lockfile exists → logs "Already done: {name}" and **skips**
    - Otherwise: executes the script via `b19-run`
    - On success: creates lockfile (marks as done)
    - On failure: logs error with exit code, **breaks immediately** (no further scripts run)
1. Exits 1 if any script failed, 0 otherwise

### Key difference from other runners

| Runner        | Fail handling               | Sort order | Idempotency             | Concurrency guard   |
| ------------- | --------------------------- | ---------- | ----------------------- | ------------------- |
| bootstrap.d   | Abort on first failure      | Forward    | Per-script locks        | Lockfile per script |
| healthcheck.d | Continue, count failures    | Forward    | None                    | `flock`             |
| test.d        | Continue, count failures    | Reverse    | None                    | None                |
| entrypoint.d  | Abort (`set -e`)            | Forward    | None                    | None                |
| build.d       | Abort (`set -E` + ERR trap) | Forward    | Hooks deleted after run | None                |
| benchmark.d   | Continue, count failures    | Forward    | None                    | None                |

The per-script lockfiles make bootstrap.d uniquely idempotent: a container
restart does not re-run completed bootstrap scripts. Only a volume wipe
(resetting `$B19_BOOTSTRAP_LOCK_PATH`) triggers re-execution.

## Environment Variables

### Feature toggle

| Variable                | Default | Description                                  |
| ----------------------- | ------- | -------------------------------------------- |
| `B19_BOOTSTRAP_ENABLED` | `true`  | Set to `false` to skip all bootstrap scripts |

### Paths

| Variable                  | Default                | Description                            |
| ------------------------- | ---------------------- | -------------------------------------- |
| `B19_BOOTSTRAP_PATH`      | `/bootstrap.d`         | Directory containing bootstrap scripts |
| `B19_BOOTSTRAP_LOCK_PATH` | `$B19_HOME/.bootstrap` | Directory for per-script lockfiles     |

Both are declared as `ENV` in `b19/ubuntu/Dockerfile:47-48` and inherited by all
downstream images.

### Volume declaration

The Dockerfile declares `VOLUME ${B19_BOOTSTRAP_LOCK_PATH}` (line 129). This
means the lock directory persists across container restarts by default. To
force re-bootstrap, delete the volume or remove the lockfiles:

```bash
docker compose down -v                    # removes all volumes
# or
docker exec <container> rm /app/.bootstrap/.100-smoke-test.bootstrap
```

## Base Scripts (b19/Ubuntu)

One script ships in `.container/user/bootstrap.d/`:

| Slot | Script              | Action                                                |
| ---- | ------------------- | ----------------------------------------------------- |
| 100  | `100-smoke-test.sh` | Creates a marker file at `$B19_HOME/.bootstrap-smoke` |

The smoke test verifies that the bootstrap runner itself is functional and that
the home directory is writable.

### Slot numbering convention

| Range   | Purpose                | Reserved by             |
| ------- | ---------------------- | ----------------------- |
| 100-499 | First-time setup tasks | b19/Ubuntu (smoke test) |
| 500-999 | Service initialization | downstream project      |
| 1000+   | Multi-component setup  | downstream project      |

## How Scripts Get Into the Image

The Dockerfile bulk-copies two directory trees to `/`:

```dockerfile
COPY .container/foundation/  /     # tools.d (runner), build hooks, locale
COPY .container/user/        /     # bootstrap.d (scripts), entrypoint.d, healthcheck.d
```

Inside the container:

```text
/bootstrap.d/                        # B19_BOOTSTRAP_PATH
  100-smoke-test.sh                  # from b19/ubuntu
  500-init-database.sh               # from downstream image (layered on top)
  600-create-admin.sh                # from downstream image (layered on top)

/app/.bootstrap/                     # B19_BOOTSTRAP_LOCK_PATH (volume)
  .100-smoke-test.bootstrap          # created after 100 runs
  .500-init-database.bootstrap       # created after 500 runs
```

Downstream projects’ scripts merge via Docker layer overlay. The runner finds
all `*.sh` regardless of which image layer added them.

The scaffold template (`.makefile/m6e/scaffold/shared/container/user/bootstrap.d/`)
creates an empty directory with a `.gitkeep` for new projects.

## Writing a Bootstrap Script

### Template

```bash
#!/usr/bin/env bash

    set -eo pipefail

    # shellcheck source=b19-i18n
    . b19-i18n

    b19-run "BOOTSTRAP" "$(_p "Initialize %s" "my-resource")" \
      touch "${XDG_DATA_HOME}/.initialized"
```

### Rules

1. **`#!/usr/bin/env bash`** — always
1. **`set -eo pipefail`** — strict mode; a failed bootstrap aborts the entire chain
1. **Source `b19-i18n`** if using `_()` or `_p()` for translatable strings
1. **Use `b19-run`** for all actions — provides timing, progress display, and error reporting
1. **Tag all `b19-log` calls as `"BOOTSTRAP"`** — consistent prefix for filtering
1. **Wrap user-facing strings in `_()` or `_p()`** — i18n is mandatory (en, es, uk)
1. **Be idempotent** — the runner’s lock prevents re-execution, but design for safety in case locks are cleared
1. **Read config from env vars** — never hardcode paths, ports, or URLs
1. **Exit 0 = success** (lockfile is created), **non-zero = failure** (chain breaks, no lockfile)
1. **Do NOT assume network** — bootstrap runs early; services may not be up yet
1. **Do NOT leak secrets in logs** — mask passwords with `****`

### Common Patterns

#### Database schema migration

```bash
#!/usr/bin/env bash

    set -eo pipefail

    # shellcheck source=b19-i18n
    . b19-i18n

    b19-run "BOOTSTRAP" "$(_p "Run schema migrations for %s" "${NS_PROJECT}")" -- \
      my-migrate-tool --host "${NS_DB_HOST}" --port "${NS_DB_PORT}" \
        --user "${NS_DB_USER}" --dbname "${NS_DB_NAME}"
```

#### First-run config generation

```bash
#!/usr/bin/env bash

    set -eo pipefail

    # shellcheck source=b19-i18n
    . b19-i18n

    CONFIG_FILE="${B19_HOME}/config/app.conf"

    if [ ! -f "${CONFIG_FILE}" ]; then
        b19-run "BOOTSTRAP" "$(_p "Generate default config at %s" "${CONFIG_FILE}")" -- \
          envsubst < "${B19_HOME}/templates/app.conf.j2" > "${CONFIG_FILE}"
    fi
```

#### Admin user creation

```bash
#!/usr/bin/env bash

    set -eo pipefail

    # shellcheck source=b19-i18n
    . b19-i18n

    b19-run "BOOTSTRAP" "$(_p "Create admin user %s" "${NS_ADMIN_USER}")" -- \
      my-app-cli admin create \
        --username "${NS_ADMIN_USER}" \
        --password "${NS_ADMIN_PASSWORD}" \
        --email "${NS_ADMIN_EMAIL}"
```

#### Directory structure initialization

```bash
#!/usr/bin/env bash

    set -eo pipefail

    # shellcheck source=b19-i18n
    . b19-i18n

    b19-run "BOOTSTRAP" "$(_p "Create data directories")" -- \
      mkdir -p "${XDG_DATA_HOME}/uploads" \
               "${XDG_DATA_HOME}/cache" \
               "${XDG_DATA_HOME}/logs"
```

## Adding Scripts to a Downstream Project

1. Create `.container/user/bootstrap.d/NNN-task-name.sh`
1. Pick a slot in the appropriate range (500+ for service-specific setup)
1. Ensure the Dockerfile copies `.container/user/` to `/` (standard pattern: `COPY .container/user/ /`)
1. Add i18n strings to `.container/{stage}/locale/*.po` files
1. Test: `make dc-up`, wait for container to start, check logs for bootstrap output

### Numbering convention

Use gaps of 100 between scripts to allow future insertions:

```text
100-smoke-test.sh              # from b19/ubuntu
500-init-database.sh           # downstream project
600-create-default-config.sh   # downstream project
700-register-service.sh        # downstream project
```

### Skipping a script

Rename the file to `*.disabled`:

```text
500-init-database.sh.disabled
```

The runner only picks up `*.sh` files.

### Disabling all bootstrap at runtime

```bash
docker run -e B19_BOOTSTRAP_ENABLED=false ...
```

Or in compose:

```yaml
environment:
  B19_BOOTSTRAP_ENABLED: "false"
```

## Resetting Bootstrap State

To re-run all bootstrap scripts (e.g., after a database wipe):

```bash
# Remove the lock volume
docker compose down -v

# Or remove individual lock files
docker exec <container> fd --hidden --extension bootstrap . /app/.bootstrap --exec-batch rm --force

# Then restart
docker compose up -d
```

## Inspecting Bootstrap Status

### Check which scripts have completed

```bash
docker exec <container> ls -la /app/.bootstrap/
```

Each `.NNN-name.bootstrap` file corresponds to a completed script. Absent files
indicate scripts that haven’t run (or failed before creating the lock).

### Logs

Bootstrap output appears in container logs during startup:

```text
 NOTE  BOOTSTRAP  Already done: 100-smoke-test
 INFO  BOOTSTRAP  Running: 500-init-database
 BOOTSTRAP  Initialize database… success [0.342s]
  GOOD  BOOTSTRAP  Completed: 500-init-database
```

If a script fails:

```text
 INFO  BOOTSTRAP  Running: 600-create-admin
 BOOTSTRAP  Create admin user… failure (exit code 1) [0.012s]
   BAD  BOOTSTRAP  Failed: 600-create-admin (exit code 1)
   BAD  BOOTSTRAP  Failed scripts: 1
```

Scripts after the failure are not attempted. The lockfile for the failed
script is **not** created, so it will be retried on the next container start.

## Relation to Other Systems

### bootstrap.d vs entrypoint.d

| Aspect      | entrypoint.d              | bootstrap.d                     |
| ----------- | ------------------------- | ------------------------------- |
| When        | Every container start     | First start only (per volume)   |
| Idempotency | Must be self-idempotent   | Tracked by lockfiles            |
| Purpose     | Configure the environment | Initialize state/data           |
| Examples    | Load secrets, render j2   | DB migration, create admin user |
| Ordering    | Runs at slot 3000         | Triggered by slot 3000          |

### bootstrap.d vs build.d (build-stage hooks)

| Aspect      | build.d (build hooks)     | bootstrap.d                      |
| ----------- | ------------------------- | -------------------------------- |
| When        | Image build time          | Container first-run time         |
| Persistence | Baked into image layers   | Writes to volumes                |
| Access to   | Build-time context only   | Full runtime env + secrets       |
| Network     | Limited (build kit)       | Full container network           |
| Purpose     | Install packages, compile | Initialize state, run migrations |

### bootstrap.d vs test.d

| Aspect        | test.d                        | bootstrap.d                     |
| ------------- | ----------------------------- | ------------------------------- |
| When          | `make test` / pipeline        | Container first-run             |
| Prerequisites | Waits for healthcheck to pass | None (runs early in entrypoint) |
| Purpose       | Verify the image works        | Initialize state                |
| Fail handling | Continue (count failures)     | Abort on first failure          |

## i18n Integration

All bootstrap strings use `_()` (static) and `_p()` (printf-style) from
`b19-i18n`. Translation files live in `.container/{stage}/locale/`:

- `TEXTDOMAIN.pot` — template (extracted by `b19-compile-i18n`)
- `es.po` — Spanish (es_CL)
- `uk.po` — Ukrainian (uk_UA)

After adding or modifying translatable strings:

1. Run `make build` — `b19-compile-i18n` extracts strings to `.pot` and compiles
    `.po` -> `.mo`
1. Update `.po` files with translations for new/changed `msgid` entries

## Bug Fixing Guide

### Script never runs

- Check `B19_BOOTSTRAP_ENABLED` is not `false`
- Check the file extension is `.sh` (not `.sh.disabled` or `.bak`)
- Check the script is executable and readable
- Check the file was actually copied into the image (Dockerfile `COPY`)
- Check logs for "Directory not found: /bootstrap.d"

### Script runs on every restart

- Check that `$B19_BOOTSTRAP_LOCK_PATH` is a volume (not tmpfs)
- Check that the lockfile was created: `ls /app/.bootstrap/.*.bootstrap`
- Check `docker compose down` vs `docker compose down -v` (the latter wipes volumes)

### Script always fails

- Read the runner output — `b19-run` shows the exit code and command

- Run the script manually inside the container to debug:

    ```bash
    docker exec -it <container> bash
    . b19-i18n
    bash -x /bootstrap.d/500-my-script.sh
    ```

- Common causes: missing env vars, network not ready, file permissions

### Script runs but downstream scripts don’t execute

- The runner **breaks** on first failure — check the log for the failed script
- Only the failed script’s lockfile will be missing
- Fix the failing script, then restart the container

### Lockfile exists but state is corrupt

This happens when a script succeeds (creating the lock) but the resulting state
is wrong (e.g., partial data migration). Fix:

```bash
# Delete the specific lock file to re-run just that script
docker exec <container> rm /app/.bootstrap/.500-init-database.bootstrap
docker compose restart <service>
```

## Quick Reference

```text
Location:          .container/{stage}/bootstrap.d/
In-image path:     /bootstrap.d (B19_BOOTSTRAP_PATH)
Lock directory:    $B19_HOME/.bootstrap (B19_BOOTSTRAP_LOCK_PATH, VOLUME)
Runner:            /tools.d/bootstrap.d
Triggered by:      entrypoint.d/3000-bootstrap.sh
Condition:         ENTRYPOINT_COMMAND_EXECUTED=N (no explicit CMD)
Sort order:        Forward numerical (ascending)
Fail behavior:     Abort on first failure (stop chain)
Idempotency:       Per-script lock files in B19_BOOTSTRAP_LOCK_PATH
Disable all:       B19_BOOTSTRAP_ENABLED=false
Disable single:    Rename to *.disabled
Reset state:       Delete files in B19_BOOTSTRAP_LOCK_PATH or remove volume
Dockerfile:        VOLUME ${B19_BOOTSTRAP_LOCK_PATH} (inherited)
Scaffold:          .makefile/m6e/scaffold/shared/container/user/bootstrap.d/
i18n:              Use _() and _p(), tag "BOOTSTRAP"
```
