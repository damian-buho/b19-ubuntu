<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Test images with test.d

`test.d` is the test runner built into every b19 image: plain shell scripts in `/test.d`, discovered and executed by the runner after it waits for the container to become healthy, with a pass/fail summary at the end. No test framework dependency — raw Bash and exit codes. The pitch: [container test framework](../features.d/test.d.md).

## When to use

- Every image: assert the tools you installed actually work — versions compile, binaries respond, directories are writable.
- CI: `make test` runs the suite inside the running container as part of the pipeline.

## Quick start

```bash
# .container/user/test.d/1100-check-version.sh
#!/usr/bin/env bash
set -eo pipefail

EXPECTED_VERSION=$(cat "/deps/rust/version.deps") || exit 1
ACTUAL_VERSION=$(rustc --version | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')

[ "${EXPECTED_VERSION}" != "${ACTUAL_VERSION}" ] && exit 1 || exit 0
```

```bash
make test       # all registered test targets (includes test.d)
make test.d     # only test.d
docker exec -it <container> test.d   # inside a running container
```

## How it works

Runner lifecycle (`/tools.d/test.d`, source `.container/foundation/tools.d/test.d`):

1. Checks `B19_TEST_ENABLED` — exits immediately if `false`
1. Waits for `healthcheck.d` to pass (up to `B19_TEST_TIMEOUT` seconds, default 60) — an unhealthy service skips the suite rather than failing it on a false alarm
1. Finds all `*.sh` in `$B19_TEST_PATH` (default `/test.d`), sorts **reverse numerically** — higher numbers run first
1. Executes each via `b19-run`, capturing the exit code; continues on failure
1. Prints `All N tests passed` / `N of M tests failed`; exits 0 or 1

The wait-for-health entry criterion and continue-on-failure mode distinguish test.d from the fail-fast runners — see [use the runner family](use-runner-family.md).

### Getting tests into the image

Tests ride the standard bulk copy — `.container/user/test.d/` maps to `/test.d`, merging with inherited tests via Docker layer overlay.

Files named `*.sh.j2` are rendered at build time by the inheritable hook `user/post/920-process-j2-tests.i.sh`:

```bash
. parallel-j2 "${B19_TEST_PATH}"
chmod +x "${B19_TEST_PATH}"/*.sh
```

Because the hook is `.i.`, downstream images process their own J2 test templates automatically. Example: this image’s `0100-check-ubuntu-series.sh.j2` asserts the running series against `{{ ENV.B19_UBUNTU_SERIES }}`.

## Writing a test

Rules:

1. `#!/usr/bin/env bash` and `set -eo pipefail` always.
1. Exit 0 = pass, non-zero = fail — no assertion library.
1. Self-contained: no shared helpers beyond `b19-i18n` and `b19-log`.
1. Clean up: `mktemp -d` + `trap 'rm -rf "${WORK_DIR}"' EXIT`.
1. Source `b19-i18n` and wrap user-facing strings in `_()` / `_p()`.
1. Skip gracefully when optional: `command -v` the tool, `b19-log warn` + `exit 0` if absent.
1. Number files `NNNN-name.sh` — reverse order means higher numbers run first.

| Range       | Purpose                                           | Examples                                                               |
| ----------- | ------------------------------------------------- | ---------------------------------------------------------------------- |
| `0100-0900` | Base/system checks                                | `0100-dummy.sh`, `0300-nslookup.sh`, `0600-is-cache-writable.sh`       |
| `1100-1400` | Version checks, tool-specific tests               | `1100-rust-version.sh`, `1200-check-crypto.sh`, `1300-compile-test.sh` |
| `1500-1600` | Writability / filesystem checks                   | `1600-is-data-writable.sh`                                             |
| `2100-2200` | Tool presence checks (downstream tool containers) | `2100-ruff.sh`, `2200-infection.sh`                                    |
| `2600`      | Storage/plugin checks (services)                  | `2600-is-storage-writable.sh`                                          |
| `3100`      | High-level integration                            | `3100-get-kafka-version.sh`                                            |

### Patterns by test type

#### Compile-and-run (compiler images)

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

#### Tool presence (tool containers)

```bash
#!/usr/bin/env bash
set -eo pipefail

golangci-lint version
```

#### Conditional skip (optional tool)

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

#### Service liveness (databases)

```bash
#!/usr/bin/env bash
set -e

mongosh --host "localhost" --port "${O9S_MONGODB_PORT}" \
    --eval "db.runCommand({ ping: 1 })" \
    -u "${O9S_MONGODB_USERNAME}" -p "${O9S_MONGODB_PASSWORD}" \
    --authenticationDatabase admin > /dev/null 2>&1
```

#### Writability

```bash
#!/usr/bin/env bash
set -e

[ ! -w "${XDG_CACHE_HOME}" ] && exit 1
exit 0
```

#### Jinja2 template test (asserts a build arg at build time)

File `0100-check-version.sh.j2` — rendered by the inheritable hook before the runner ever sees it:

```bash
#!/usr/bin/env bash
set -e

if [ "{{ ENV.B19_UBUNTU_SERIES }}" != "$(lsb_release -cs 2> /dev/null)" ]
then
  exit 1
fi
exit 0
```

## Configuration

| Variable                | Default       | Description                                          |
| ----------------------- | ------------- | ---------------------------------------------------- |
| `B19_TEST_PATH`         | `/test.d`     | Directory containing test scripts                    |
| `B19_TEST_ENABLED`      | `true`        | Set to `false` to skip all tests                     |
| `B19_TEST_TIMEOUT`      | `60`          | Seconds to wait for healthcheck before running tests |
| `B19_TEST_RESULTS_PATH` | `/tmp/test.d` | (reserved, not yet used by runner)                   |

The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```text
0900-docker-connect.sh.disabled     # rename — the runner only picks up *.sh
```

```bash
docker exec -e B19_TEST_ENABLED=false <container> test.d   # skip for one run
```

A new scaffolded project ships `1100-check-version.sh`, which calls the project’s `command.d/get-<project>-version` — add more numbered scripts from there. Custom make-level test targets register the same way the b19 runtime does:

```makefile
TEST_TARGETS += my-custom-test
```

The pipeline target runs `clean → build → dc-up-d → test → healthcheck.d → get-history → read-lineage → dc-logs`, with `test` accumulating every registered `TEST_TARGETS` under `--keep-going`.

## Quick reference

```text
Location:        .container/{stage}/test.d/
In-image path:   /test.d
Runner:          /tools.d/test.d
Sort order:      Reverse numerical (higher first)
Fail behavior:   Continue (collects all failures)
Entry criteria:  healthcheck.d passes (B19_TEST_TIMEOUT seconds)
Disable:         B19_TEST_ENABLED=false, or rename one test to *.disabled
Make target:     make test.d
```

## See also

- [Write healthchecks](use-healthcheck.d.md) — the gate test.d waits for
- [Use the runner family](use-runner-family.md) — the eight runners compared
- [Render templates with minijinja](use-templating.md) — the `.sh.j2` lifecycle
