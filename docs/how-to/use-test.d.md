<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# test.d — Container Test Framework

## Overview

`test.d` is the numbered-script test runner built into every b19-derived image.
Tests are plain shell scripts (`*.sh`) placed in `/test.d` (mapped from
`.container/{stage}/test.d/` at build time). The runner discovers, sorts, and
executes them, reporting pass/fail counts.

There is no test framework dependency — tests use raw Bash + exit codes.

## How it works

### Runner lifecycle

The runner is the tool script `/tools.d/test.d` (source:
`.container/foundation/tools.d/test.d`). When invoked, it:

1. Checks `B19_TEST_ENABLED` — exits immediately if `false`
1. Waits for `healthcheck.d` to pass (up to `B19_TEST_TIMEOUT` seconds, default 60)
1. Finds all `*.sh` files in `$B19_TEST_PATH` (default `/test.d`)
1. Sorts them in **reverse numerical order** (`sort -znr`)
1. Executes each via `b19-run`, capturing the exit code
1. Continues on failure (does NOT abort after the first failing test)
1. Prints a summary: `N of M tests failed` or `All N tests passed`
1. Exits with code 0 (all passed) or 1 (any failed)

### Key difference from other runners

| Runner        | Fail handling    | Sort order       |
| ------------- | ---------------- | ---------------- |
| test.d        | Continue         | Reverse (`-znr`) |
| healthcheck.d | Continue         | Forward (`-zn`)  |
| entrypoint.d  | Abort (`set -e`) | Forward (`-zn`)  |
| bootstrap.d   | Abort            | Forward (`-zn`)  |

### Environment variables

| Variable                | Default       | Description                                          |
| ----------------------- | ------------- | ---------------------------------------------------- |
| `B19_TEST_PATH`         | `/test.d`     | Directory containing test scripts                    |
| `B19_TEST_ENABLED`      | `true`        | Set to `false` to skip all tests                     |
| `B19_TEST_TIMEOUT`      | `60`          | Seconds to wait for healthcheck before running tests |
| `B19_TEST_RESULTS_PATH` | `/tmp/test.d` | (reserved, not yet used by runner)                   |
| `B19_VERBOSITY`         | `warn`        | Controls log output; `test.d` is invoked with `info` |

Defined in `Dockerfile` (line 88) and `project.yaml` (line 58). Inherited by all
downstream images — no project overrides it.

## How tests get into the image

Tests ride along via the bulk COPY in the Dockerfile:

```dockerfile
COPY --chown="${B19_UID}:${B19_GID}" .container/user/ /
```

The directory tree `.container/user/test.d/` maps directly to `/test.d` inside
the container. This is the same COPY used for `entrypoint.d`, `healthcheck.d`,
`tools.d`, etc.

### Jinja2 templates

Files named `*.sh.j2` in test.d are rendered at build time by an inheritable
hook (`.container/user/build.d/user/post/920-process-j2-tests.i.sh`):

```bash
. parallel-j2 "${B19_TEST_PATH}"
chmod +x "${B19_TEST_PATH}"/*.sh
```

This hook is `.i.` (inheritable), so downstream images automatically process
their own j2 test templates. Example: `0100-check-version.sh.j2` uses
`{{ ENV.B19_UBUNTU_SERIES }}` to assert the correct Ubuntu series at runtime.

## Running tests

### Via make (recommended)

```bash
make test           # Run all registered test targets (includes test.d)
make test.d         # Run only test.d
make       # Full CI: clean → build → up → test → healthcheck → logs
```

The `test.d` make target (`m6e/container/020-runtime.mk:57`) waits for the
container to be running (up to `M6E_CONTAINER_START_TIMEOUT`), then executes
`docker exec ... test.d`.

### Inside a running container

```bash
docker exec -it <container> test.d
```

### Disabling tests

```bash
B19_TEST_ENABLED=false docker exec -e B19_TEST_ENABLED=false <container> test.d
```

## Writing a test

### File naming and numbering

Files follow the pattern `NNNN-descriptive-name.sh` where `NNNN` is a 4-digit
number controlling execution order (reverse — higher numbers run first).

| Range       | Purpose                                           | Examples                                                               |
| ----------- | ------------------------------------------------- | ---------------------------------------------------------------------- |
| `0100-0900` | Base/system checks                                | `0100-dummy.sh`, `0200-nslookup.sh`, `0300-apt-versions.sh`            |
| `1100-1400` | Version checks, tool-specific tests               | `1100-rust-version.sh`, `1200-check-crypto.sh`, `1300-compile-test.sh` |
| `1500-1600` | Writability / filesystem checks                   | `1600-is-data-writable.sh`                                             |
| `2100-2200` | Tool presence checks (downstream tool containers) | `2100-ruff.sh`, `2200-infection.sh`                                    |
| `2600`      | Storage/plugin checks (services)                  | `2600-is-storage-writable.sh`                                          |
| `3100`      | High-level integration                            | `3100-get-kafka-version.sh`                                            |

### Template

```bash
#!/usr/bin/env bash
set -eo pipefail

# shellcheck source=b19-i18n
. b19-i18n

b19-log info "MYTEST" "$(_ "Starting my test")"

# ... test logic ...

exit 0
```

### Rules

1. **Always start with `#!/usr/bin/env bash`** and `set -e` (or `set -eo pipefail`)
1. **Exit 0 = pass, non-zero = fail** — no assertion library needed
1. **Self-contained** — no shared test helpers beyond `b19-i18n` and `b19-log`
1. **Clean up after yourself** — use `mktemp -d` + `trap 'rm -rf "$WORK_DIR"' EXIT`
1. **Use `b19-run` for wrapped execution** — provides timing and formatted output
1. **i18n for user-facing strings** — source `b19-i18n`, use `$(_ "...")` and `$(_p "... %s" "$var")`
1. **Skip gracefully when optional** — check `command -v` and `b19-log warn` + `exit 0` if absent
1. **Place in the correct stage directory** — `.container/user/test.d/` for user-stage, `.container/foundation/test.d/` for foundation-stage (rare)

### Disabling a test

Rename the file to `*.disabled`:

```text
0900-docker-connect.sh.disabled
```

The runner only picks up `*.sh` files.

## Test categories by example

### Version assertion (most common across projects)

```bash
#!/usr/bin/env bash
set -eo pipefail

EXPECTED_VERSION=$(cat "/deps/rust/version.deps") || exit 1
ACTUAL_VERSION=$(rustc --version | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')

[ "${EXPECTED_VERSION}" != "${ACTUAL_VERSION}" ] && exit 1 || exit 0
```

### Compile-and-run test (compiler images)

```bash
#!/usr/bin/env bash
set -eo pipefail

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

cat > "${WORK_DIR}/hello.hs" <<'EOF'
main :: IO ()
main = putStrLn "Hello, Haskell!"
EOF

ghc -outputdir "${WORK_DIR}" -o "${WORK_DIR}/hello" "${WORK_DIR}/hello.hs"
OUTPUT=$("${WORK_DIR}/hello")
[ "${OUTPUT}" = "Hello, Haskell!" ]
```

### Tool presence check (tool containers)

```bash
#!/usr/bin/env bash
set -eo pipefail

golangci-lint version
```

### Conditional skip (optional tool)

```bash
#!/usr/bin/env bash
set -eo pipefail

. b19-i18n

command -v fd > /dev/null 2>&1 || {
    b19-log warn "FD" "$(_ "Not installed, skipping test")"
    exit 0
}

fd --version
```

### Service liveness (databases)

```bash
#!/usr/bin/env bash
set -e

mongosh --host "localhost" --port "${O9S_MONGODB_PORT}" \
    --eval "db.runCommand({ ping: 1 })" \
    -u "${O9S_MONGODB_USERNAME}" -p "${O9S_MONGODB_PASSWORD}" \
    --authenticationDatabase admin > /dev/null 2>&1
```

### Writability check

```bash
#!/usr/bin/env bash
set -e

[ ! -w "${XDG_CACHE_HOME}" ] && exit 1
exit 0
```

### Jinja2 template test (asserts build-arg at build time)

File: `0100-check-version.sh.j2`

```bash
#!/usr/bin/env bash
set -e

if [ "{{ ENV.B19_UBUNTU_SERIES }}" != "$(lsb_release -cs 2> /dev/null)" ]
then
  exit 1
fi
exit 0
```

## Adding tests to a new project

When scaffolding a new project, the template at
`.makefile/m6e/scaffold/shared/container/user/test.d/1100-check-version.sh`
is copied with `@@PROJECT@@` replaced:

```bash
#!/usr/bin/env bash
set -eo pipefail

  get-myproject-version
```

This calls the version command from `command.d/`. Add more tests as numbered
scripts in `.container/user/test.d/`.

## Pipeline integration

The `pipeline` target (`m6e/workflow/pipeline.mk`) runs:

```text
clean → build → dc-up-d → test → healthcheck.d → get-history → read-lineage → dc-logs
```

`test` is an accumulator target (`m6e/workflow/test.mk`) that runs all
registered `TEST_TARGETS` with `--keep-going`. The `test.d` target is registered
by `m6e/container/020-runtime.mk` via:

```makefile
TEST_TARGETS += test.d
```

Projects can add custom test targets:

```makefile
TEST_TARGETS += my-custom-test
```

## Relation to other `.d` runners

All numbered-script runners share the same pattern (fd + sort + execute):

| Runner          | Location                       | Purpose                | When                        |
| --------------- | ------------------------------ | ---------------------- | --------------------------- |
| `entrypoint.d`  | `/entrypoint.d`                | Container startup      | Every start                 |
| `healthcheck.d` | `/healthcheck.d`               | Docker HEALTHCHECK     | Periodic                    |
| `test.d`        | `/test.d`                      | CI testing             | `make test` / `make`        |
| `bootstrap.d`   | `/bootstrap.d`                 | First-run setup        | Once per volume             |
| `report.d`      | `/report.d`                    | Diagnostic reports     | On demand                   |
| `benchmark.d`   | `/benchmark.d`                 | Performance benchmarks | On demand                   |
| `build.d`       | `/build.d/{stage}/{pre,post}/` | Build hooks            | Build time (Dockerfile RUN) |

## Quick reference

```text
Location:        .container/{stage}/test.d/
In-image path:   /test.d
Runner:          /tools.d/test.d
Sort order:      Reverse numerical (higher first)
Fail behavior:   Continue (collects all failures)
Entry criteria:  healthcheck.d passes
```

```text
Disable:         B19_TEST_ENABLED=false
Disable file:    Rename to *.disabled
Make target:     make test.d
Pipeline:        make (includes test.d)
Scaffold:        .makefile/m6e/scaffold/shared/container/user/test.d/
```
