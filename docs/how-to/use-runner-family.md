<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Use the runner family

Eight numbered-hook runners cover the whole container lifecycle, and they all share one pattern: drop a numbered `*.sh` into the right directory and it is auto-discovered, sorted and executed. Scripts from different image layers merge — upstream and downstream hooks coexist without conflict. The pitch: [unified lifecycle runner family](../features.d/runner-family.md).

## When to use

- Deciding which directory a new script belongs in — the runner table below is the map.
- Reasoning about failure semantics: what happens when one hook fails depends entirely on which runner owns it.

## Quick start

```bash
# A downstream service test: numbered script, right directory, done.
# .container/user/test.d/1100-check-version.sh
#!/usr/bin/env bash
set -eo pipefail
my-service --version
```

## How it works

Every runner discovers scripts the same way — `fd --print0 --hidden --type file --extension sh . <dir> | sort --zero-terminated --numeric-sort` — and merges hooks across image layers, because each stage’s `COPY .container/{stage}/ /` overlays into the same directories.

| Runner          | In-container dir | Driver                                   | Sort                   | Failure semantics                                                    |
| --------------- | ---------------- | ---------------------------------------- | ---------------------- | -------------------------------------------------------------------- |
| `entrypoint.d`  | `/entrypoint.d`  | `/tools.d/entrypoint.d`                  | ascending              | abort (`set -euo pipefail`); **sources** each hook                   |
| `healthcheck.d` | `/healthcheck.d` | `/tools.d/healthcheck.d`                 | ascending              | continue, count failures; exit code = count; `flock` against overlap |
| `test.d`        | `/test.d`        | `/tools.d/test.d`                        | descending             | continue, count failures; waits for healthcheck first                |
| `bootstrap.d`   | `/bootstrap.d`   | `/tools.d/bootstrap.d`                   | ascending              | abort; per-script lockfile idempotency                               |
| `build.d`       | `/build.d`       | `/tools.d/build-stage` → `process-hooks` | ascending              | abort via ERR trap; non-`*.i.sh` hooks deleted after run             |
| `benchmark.d`   | `/benchmark.d`   | `/tools.d/benchmark.d`                   | ascending (suite dirs) | continue per suite                                                   |
| `report.d`      | `/report.d`      | `/tools.d/report.d`                      | descending             | always succeeds                                                      |
| `shell.d`       | `/shell.d`       | `/etc/bash.bashrc` block                 | alphabetical glob      | n/a (interactive)                                                    |

Two mechanism differences worth knowing:

- **Sourced vs executed** — `entrypoint.d` sources its hooks into one shell, which is how `ENTRYPOINT_COMMAND_EXECUTED`, `PAYLOAD_PID` and `NUMPROCS` flow between hooks. `healthcheck.d` sources inside a subshell (isolated failures); `test.d` executes each test via `b19-run`.
- **Suites vs scripts** — `benchmark.d` discovers **directories** (each holding `benchmark.sh` plus optional `setup.sh`/`teardown.sh`), not loose scripts.

`build.d` is the one runner with a two-level layout (`{stage}/{pre,on,post}`) and an inheritance mechanism (`*.i.sh` survives the post-run prune to fire again in downstream images) — see [build with hooks](use-build.d.md).

### Skipping individual hooks

Two runners support per-script skip toggles at runtime, no rebuild:

```bash
B19_ENTRYPOINT_SKIP_CHECK_PORTS=true   # skips 0300-check-ports.sh
B19_BOOTSTRAP_SKIP_SMOKE_TEST=true     # skips 100-smoke-test.sh
```

The name is derived from the filename: strip `.sh`, strip through the first digit-dash (`${NAME#*[0-9]-}`), uppercase, `-` → `_`. Whole-subsystem toggles (`B19_ENTRYPOINT_ENABLED`, `B19_HEALTH_ENABLED`, …) are indexed in [configure-environment](configure-environment.md).

## Recipes

```bash
# Where a new script goes, by question:
#   "must run on every container start?"  → .container/user/entrypoint.d/
#   "probes the running service?"         → .container/user/healthcheck.d/
#   "verifies the built image?"           → .container/user/test.d/
#   "must run once per volume?"           → .container/user/bootstrap.d/
#   "prepares an interactive shell?"      → .container/user/shell.d/
#   "runs at image build time?"           → .container/{stage}/build.d/{stage}/
```

## See also

- [Start containers with entrypoint.d](use-entrypoint.d.md) — the sourced, fail-fast startup chain
- [Write healthchecks](use-healthcheck.d.md) — continue-and-count under `flock`
- [Test images with test.d](use-test.d.md) — reverse order, health-gated
- [Initialize state once with bootstrap.d](use-bootstrap.d.md) — lockfile idempotency
- [Build images with build.d hooks](use-build.d.md) — the build-time runner with inheritance
