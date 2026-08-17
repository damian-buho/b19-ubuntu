<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Load secrets

Docker secrets mounted under `/run/secrets` become environment variables automatically: a file named `b19.npm.registry_host` exports `B19_NPM_REGISTRY_HOST` at startup. Required secrets can be declared by name, and the container refuses to start without them. The pitch: [Docker secrets auto-loading](../features.d/secrets.md).

## When to use

- Any credential or token your service reads from the environment — mount it as a file, read it as a var.
- Declaring startup requirements: `B19_REQUIRED_SECRETS` turns a missing credential into a loud, immediate failure.

## Quick start

```yaml
# compose
services:
  my-service:
    secrets:
      - my.db.password
secrets:
  my.db.password:
    file: ../.secrets/my/db/password
```

```yaml
# requirement — the container exits 1 at startup if it is missing
environment:
  B19_REQUIRED_SECRETS: my.db.password
```

The service reads `MY_DB_PASSWORD` from its environment.

## How it works

`b19-load-secrets` (a sourced tool) scans `${B19_SECRETS_PATH}` for `*.*` files and maps dot-notation filenames to uppercase env vars (`-` and `.` → `_`, uppercased). Three rules hold the design:

- **Existing env wins** — a variable already set is never overwritten by a file.
- **Values are newline-stripped** — `cat | tr -d '\n'` — so a trailing newline in the file never corrupts the value.
- **Binary secrets stay files** — non-UTF-8 content is skipped as an env var (Bash truncates at the first NUL, and stray bytes panic any tool that reads the environment as UTF-8, like `minijinja --env`). The file remains at `/run/secrets/<name>` for file-based reads — the only correct way to consume a key or DER blob anyway.

### Where secrets get loaded

| Context              | Mechanism                                                                      |
| -------------------- | ------------------------------------------------------------------------------ |
| Container startup    | entrypoint hook `0100-load-secrets.sh` → `. b19-load-secrets`                  |
| Startup validation   | entrypoint hook `2100-validate-secrets.sh` checks `B19_REQUIRED_SECRETS`       |
| Healthchecks         | the runner sources `b19-load-secrets` itself (runs outside entrypoint context) |
| Interactive shells   | `shell.d/010-load-secrets.sh`                                                  |
| Ad-hoc `docker exec` | `b19-exec-with-secrets <cmd>` — loads, then `exec "$@"`                        |

Validation passes when the env var is non-empty **or** the file exists under `${B19_SECRETS_PATH}`; it is skipped entirely for ad-hoc commands (`ENTRYPOINT_COMMAND_EXECUTED=Y`) and when `B19_SECRETS_ENABLED=false`.

The make wrapper uses the same path for pipeline commands: `M6E_DOCKER_EXEC = docker exec <instance> b19-exec-with-secrets`.

## Configuration

| Variable               | Default        | Effect                                             |
| ---------------------- | -------------- | -------------------------------------------------- |
| `B19_SECRETS_PATH`     | `/run/secrets` | Directory scanned for secret files                 |
| `B19_REQUIRED_SECRETS` | (empty)        | Space-separated dot-notation names that must exist |
| `B19_SECRETS_ENABLED`  | `true`         | `false` skips loading and validation               |

## Recipes

```bash
# Binary SSH keys: consumed as files, exactly as setup-ssh does
cp "/run/secrets/ssh_id_ecdsa" "${HOME}/.ssh/id_ecdsa"
```

## See also

- [Start containers with entrypoint.d](use-entrypoint.d.md) — slots 0100 and 2100
- [Enhance interactive shells](use-shell-hooks.md) — secrets in `docker exec bash`
- [Write healthchecks](use-healthcheck.d.md) — why the runner loads secrets itself
