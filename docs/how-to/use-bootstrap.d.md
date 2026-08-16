<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Initialize state once with bootstrap.d

`bootstrap.d` is the run-once runner: the first time a container starts on a fresh volume, its numbered scripts initialize databases, create admin users and generate first-run config — and per-script lockfiles guarantee they never run again on restarts. The pitch: [run-once initialization](../features.d/bootstrap.d.md).

## When to use

- First-run state the image cannot bake in: schema migrations, admin user creation, first-run config generation.
- Anything that must happen exactly once per volume lifetime, not on every container start (that is [entrypoint.d](use-entrypoint.d.md) work).

## Quick start

```bash
# .container/user/bootstrap.d/500-init-database.sh
#!/usr/bin/env bash
set -eo pipefail

# shellcheck source=b19-i18n
. b19-i18n

b19-run "BOOTSTRAP" "$(_p "Run schema migrations for %s" "${NS_PROJECT}")" -- \
  my-migrate-tool --host "${NS_DB_HOST}" --port "${NS_DB_PORT}" \
    --user "${NS_DB_USER}" --dbname "${NS_DB_NAME}"
```

## How it works

```text
Container start (tini → entrypoint.d)
  ├─ 2000-run-command.sh        ← detects CMD vs long-run
  ├─ 2100-validate-secrets.sh
  ├─ 3000-bootstrap.sh          ← calls the bootstrap.d runner
  │    └─ /tools.d/bootstrap.d
  │         └─ executes /bootstrap.d/*.sh (ascending, per-script locks)
  ├─ 5000-start.sh
  └─ 9000-finalize.sh
```

The entrypoint hook invokes the runner only when no explicit command was passed — `docker run myimage some-command` executes the command directly and skips bootstrap:

```bash
if [ "${ENTRYPOINT_COMMAND_EXECUTED}" = "N" ]; then
    bootstrap.d
fi
```

### Runner lifecycle

1. Checks `B19_BOOTSTRAP_ENABLED` — exits 0 immediately if `false`
1. Enables `set -eo pipefail`, sources `b19-i18n` for `_()` / `_p()`
1. Resolves `B19_BOOTSTRAP_PATH` (default `/bootstrap.d`) and `B19_BOOTSTRAP_LOCK_PATH` (default `$B19_HOME/.bootstrap`)
1. Finds all `*.sh`, sorts ascending (`sort -zn`)
1. For each script: lockfile `${LOCK_PATH}/.${BASENAME}.bootstrap` exists → skip with “Already done”; otherwise execute via `b19-run`, create the lockfile on success
1. On failure: logs the exit code, **breaks immediately** — no further scripts run, no lockfile is created, so the failed script retries on the next start

The per-script lockfiles make the runner uniquely idempotent among the [runner family](use-runner-family.md): a container restart never re-runs completed scripts; only a volume wipe re-arms them. Where bootstrap.d sits against entrypoint.d, build.d and test.d:

| Aspect      | entrypoint.d              | bootstrap.d                   | build.d                   |
| ----------- | ------------------------- | ----------------------------- | ------------------------- |
| When        | Every container start     | First start only (per volume) | Image build time          |
| Idempotency | Must be self-idempotent   | Tracked by lockfiles          | Hooks deleted after run   |
| Purpose     | Configure the environment | Initialize state/data         | Install packages, compile |
| Writes to   | Runtime env               | Volumes                       | Image layers              |

### Slot numbering

| Range   | Purpose                | Reserved by             |
| ------- | ---------------------- | ----------------------- |
| 100-499 | First-time setup tasks | b19/Ubuntu (smoke test) |
| 500-999 | Service initialization | downstream project      |
| 1000+   | Multi-component setup  | downstream project      |

Use gaps of 100 between scripts to allow future insertions. The base image ships one script — `100-smoke-test.sh` creates a marker file at `$B19_HOME/.bootstrap-smoke`, proving the runner works and the home is writable. Downstream scripts merge via Docker layer overlay:

```text
/bootstrap.d/                        # B19_BOOTSTRAP_PATH
  100-smoke-test.sh                  # from b19/ubuntu
  500-init-database.sh               # from downstream image (layered on top)

/app/.bootstrap/                     # B19_BOOTSTRAP_LOCK_PATH (VOLUME)
  .100-smoke-test.bootstrap          # created after 100 runs
  .500-init-database.bootstrap       # created after 500 runs
```

## Writing a bootstrap script

```bash
#!/usr/bin/env bash
set -eo pipefail

# shellcheck source=b19-i18n
. b19-i18n

b19-run "BOOTSTRAP" "$(_p "Initialize %s" "my-resource")" -- \
  touch "${XDG_DATA_HOME}/.initialized"
```

Rules:

1. `#!/usr/bin/env bash` and `set -eo pipefail` always — a failed bootstrap aborts the chain.
1. Source `b19-i18n` and wrap every user-facing string in `_()` / `_p()` — translations are mandatory (en, es, uk).
1. Use `b19-run` for actions and tag `b19-log` calls `"BOOTSTRAP"` — one prefix to filter on.
1. Be idempotent anyway: the lock prevents re-execution, but design for cleared locks.
1. Read config from env vars, never hardcode paths or ports.
1. Do not assume network — bootstrap runs early; services may not be up yet.
1. Never leak secrets in logs — mask passwords with `****`.

After adding strings, run `make build` so `b19-compile-i18n` extracts the `.pot` and compiles `.po` → `.mo`, then update `.container/{stage}/locale/*.po`.

## Configuration

| Variable                  | Default                | Description                                  |
| ------------------------- | ---------------------- | -------------------------------------------- |
| `B19_BOOTSTRAP_ENABLED`   | `true`                 | Set to `false` to skip all bootstrap scripts |
| `B19_BOOTSTRAP_PATH`      | `/bootstrap.d`         | Directory containing bootstrap scripts       |
| `B19_BOOTSTRAP_LOCK_PATH` | `$B19_HOME/.bootstrap` | Directory for per-script lockfiles           |

The Dockerfile declares `VOLUME ${B19_BOOTSTRAP_LOCK_PATH}`, so locks persist across restarts by default. The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

### First-run config generation

```bash
CONFIG_FILE="${B19_HOME}/config/app.conf"
if [ ! -f "${CONFIG_FILE}" ]; then
    b19-run "BOOTSTRAP" "$(_p "Generate default config at %s" "${CONFIG_FILE}")" -- \
      envsubst < "${B19_HOME}/templates/app.conf.j2" > "${CONFIG_FILE}"
fi
```

### Skip one script, disable all, reset state

```text
500-init-database.sh.disabled     # rename — the runner only picks up *.sh
```

```bash
docker run -e B19_BOOTSTRAP_ENABLED=false ...
```

```bash
# Re-run everything: wipe the lock volume
docker compose down -v

# Re-run one script: delete its lock only
docker exec <container> rm /app/.bootstrap/.500-init-database.bootstrap
docker compose restart <service>

# Or sweep every lock
docker exec <container> fd --hidden --extension bootstrap . /app/.bootstrap --exec-batch rm --force
```

### Inspect status

```bash
docker exec <container> ls -la /app/.bootstrap/
```

Each `.NNN-name.bootstrap` is a completed script; an absent file has not run (or failed before locking). Successful startup logs:

```text
 NOTE  BOOTSTRAP  Already done: 100-smoke-test
 INFO  BOOTSTRAP  Running: 500-init-database
 BOOTSTRAP  Initialize database… success [0.342s]
  GOOD  BOOTSTRAP  Completed: 500-init-database
```

## Troubleshooting

### Script never runs

- `B19_BOOTSTRAP_ENABLED` not `false`; extension is `.sh` (not `.sh.disabled`); file copied by the Dockerfile `COPY`.
- Logs show “Directory not found: /bootstrap.d” → the tree never landed in the image.

### Script runs on every restart

- `$B19_BOOTSTRAP_LOCK_PATH` must be a volume, not tmpfs.
- `docker compose down` keeps volumes; only `down -v` wipes them.

### Script always fails

- Read the runner output — `b19-run` prints the exit code — then reproduce inside the container:

    ```bash
    docker exec -it <container> bash
    . b19-i18n
    bash -x /bootstrap.d/500-my-script.sh
    ```

- Common causes: missing env vars, network not ready, file permissions.

### Scripts after a failure don’t execute

- By design: the runner breaks on first failure; only the failed script’s lockfile is missing. Fix it, restart.

### Lockfile exists but state is wrong

- The script succeeded but left bad state (e.g. partial migration). Delete that one lockfile and restart — see Recipes.

## Quick reference

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
i18n:              Use _() and _p(), tag "BOOTSTRAP"
```

## See also

- [Use the runner family](use-runner-family.md) — how all eight numbered-hook runners compare
- [Start containers with entrypoint.d](use-entrypoint.d.md) — the chain that triggers slot 3000
- [Run commands with b19-run](use-b19-run.md) — the wrapper your scripts should call
