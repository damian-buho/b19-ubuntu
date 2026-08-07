<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Environment Variables

Every `B19_*` variable available in b19/Ubuntu — defaults, accepted values, scope,
and what each one controls. This is the single comprehensive reference;
topic-specific docs (ENTRYPOINT, HEALTHCHECK, OFFGRID, etc.) link here for details.

## Conventions

- **Scope** column: `build` = set via `ARG`/`--build-arg`; `runtime` = set via
    `docker run -e` or compose `environment:`; `build + runtime` = both
- All boolean toggles default to **enabled**; set to `false` to disable
- Variables marked `Y`/`N` follow the pattern: `Y` = active, `N` = inactive
- Unless noted, all variables are declared in `b19/ubuntu/Dockerfile` and inherited by every downstream image

## Feature Toggles

All default-enabled. Set to `false` to disable the corresponding subsystem.

| Variable                   | Default | Scope           | Controls                                           |
| -------------------------- | ------- | --------------- | -------------------------------------------------- |
| `B19_ENTRYPOINT_ENABLED`   | `true`  | runtime         | Skip all entrypoint scripts; exec CMD directly     |
| `B19_BUILD_ALWAYS_ENABLED` | `true`  | build           | Skip stage-independent `build.d/always/` hooks     |
| `B19_BOOTSTRAP_ENABLED`    | `true`  | runtime         | Skip all bootstrap scripts                         |
| `B19_HEALTH_ENABLED`       | `true`  | runtime         | Skip all healthchecks (container always healthy)   |
| `B19_TEST_ENABLED`         | `true`  | runtime         | Skip test suite                                    |
| `B19_BENCHMARK_ENABLED`    | `true`  | runtime         | Skip benchmark suite                               |
| `B19_SECRETS_ENABLED`      | `true`  | runtime         | Skip Docker secrets loading and validation         |
| `B19_PORT_CHECK_ENABLED`   | `true`  | runtime         | Skip WHATWG port blocklist validation              |
| `B19_I18N_ENABLED`         | `true`  | build + runtime | Disable gettext translations (English passthrough) |
| `B19_SHELL_ENABLED`        | `true`  | build + runtime | Disable shell.d hooks in interactive sessions      |

### Per-script skip

Skip individual hooks without disabling the entire subsystem.

**Entrypoint**: `B19_ENTRYPOINT_SKIP_<NAME>=true`

**Bootstrap**: `B19_BOOTSTRAP_SKIP_<NAME>=true`

Name derivation: take the script filename, strip `.sh`, strip leading digits and
first dash, convert `-` to `_`, uppercase.

| Script file            | Derived name   | ENV variable                            |
| ---------------------- | -------------- | --------------------------------------- |
| `0100-load-secrets.sh` | `load-secrets` | `B19_ENTRYPOINT_SKIP_LOAD_SECRETS=true` |
| `0300-check-ports.sh`  | `check-ports`  | `B19_ENTRYPOINT_SKIP_CHECK_PORTS=true`  |
| `1000-parallel-j2.sh`  | `parallel-j2`  | `B19_ENTRYPOINT_SKIP_PARALLEL_J2=true`  |
| `100-smoke-test.sh`    | `smoke-test`   | `B19_BOOTSTRAP_SKIP_SMOKE_TEST=true`    |

Skipped scripts log `"Skipped: <name> (via B19_*_SKIP_<NAME>)"` and continue to
the next hook.

## Logging and Output

| Variable                   | Default | Accepted values                                | Controls                                                                                                                                                                             |
| -------------------------- | ------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `B19_VERBOSITY`            | `warn`  | `error`, `warn`, `info`, `debug`               | Log level threshold (error=40, warn=30, info=20, debug=10). Messages below threshold are discarded. `debug` streams `b19-run` command output live.                                   |
| `B19_COLOR`                | `1`     | `1`, `0`, `auto`                               | ANSI color in `b19-log` output. `auto` checks if stderr is a TTY. Forced `0` in healthchecks and when `M6E_AI=Y`. Overridden by `NO_COLOR=1` ([no-color.org](https://no-color.org)). |
| `B19_RUN_TIMING_PRECISION` | `3`     | integer (decimal places)                       | Precision of elapsed time in `b19-run` output. `0` = seconds, `3` = milliseconds, `6` = microseconds.                                                                                |
| `B19_EXEC_STDOUT_LEVEL`    | `info`  | `error`, `bad`, `warn`, `good`, `info`, `note` | Default `b19-log` level for stdout lines in `b19-exec`.                                                                                                                              |
| `B19_EXEC_STDERR_LEVEL`    | `warn`  | (same as above)                                | Default `b19-log` level for stderr lines in `b19-exec`.                                                                                                                              |

## Behavior

| Variable                  | Default          | Accepted values            | Controls                                                                                                                                                                                                   |
| ------------------------- | ---------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `B19_J2_EXCLUDE_PATTERNS` | (unset)          | space-separated names      | Directory names to exclude from j2 template discovery (e.g., `venv node_modules`). Used by `save-j2`.                                                                                                      |
| `B19_IMMUTABLE`           | `N`              | `N`, `Y`                   | `Y` skips overlay copy and j2 template rendering at startup. Locks the filesystem to its build-time state.                                                                                                 |
| `B19_OFFGRID_MODE`        | `N`              | `N`, `Y`                   | `Y` blocks all internet access. At build time: prevents downloads (cache miss = fail), skips SSH keyscan and APT upgrade. At runtime: network healthchecks skip with exit 0. See [OFFGRID.md](OFFGRID.md). |
| `B19_RUNTIME_MODE`        | `docker-compose` | any string                 | Informational runtime environment identifier. Available for downstream images to adjust behavior.                                                                                                          |
| `B19_TEST_TIMEOUT`        | `60`             | positive integer (seconds) | Seconds `test.d` waits for healthcheck to pass before running tests.                                                                                                                                       |
| `B19_OVERLAY`             | (unset)          | directory name             | Name of an overlay directory under `B19_OVERLAYS_PATH/` to apply at startup. Contents are recursively copied to `/`.                                                                                       |
| `B19_REQUIRED_SECRETS`    | (empty)          | space-separated names      | Dot-notation secret names that must exist (env var or file). Container exits 1 if any are missing. Skipped when `B19_SECRETS_ENABLED=false` or ad-hoc command mode.                                        |

## Secrets

| Variable           | Default        | Controls                                                                                                                                                                                                        |
| ------------------ | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `B19_SECRETS_PATH` | `/run/secrets` | Directory scanned for Docker secrets files. Files matching `*.*` are converted from dot-notation to env vars (e.g. `b19.npm.registry_host` becomes `B19_NPM_REGISTRY_HOST`). Existing env vars take precedence. |

See [ENTRYPOINT.md](ENTRYPOINT.md) for secrets loading and validation flow.

## Health Thresholds

All thresholds apply at runtime. Space checks compare free kilobytes; network
checks test connectivity. Network checks respect `B19_OFFGRID_MODE`.

| Variable                        | Default                                       | Controls                                                                                         |
| ------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `B19_HEALTH_HOME_MIN_SPACE_KB`  | `32768` (32 MB)                               | Min free KB in `$B19_HOME`                                                                       |
| `B19_HEALTH_CACHE_MIN_SPACE_KB` | `32768` (32 MB)                               | Min free KB in `$XDG_CACHE_HOME`                                                                 |
| `B19_HEALTH_TEMP_MIN_SPACE_KB`  | `32768` (32 MB)                               | Min free KB in `$B19_TEMP_PATH`                                                                  |
| `B19_HEALTH_CURL_TIMEOUT`       | `8`                                           | Connection timeout in seconds for cURL checks (max-time = 2x)                                    |
| `B19_HEALTH_NETWORK_URL`        | `"https://www.w3.org https://www.google.com"` | Space-separated HTTPS URLs for connectivity checks                                               |
| `B19_HEALTH_PING_TARGETS`       | `"9.9.9.9 1.1.1.1 8.8.8.8"`                   | Space-separated IPs for ICMP ping checks                                                         |
| `B19_HEALTH_MEMORY_THRESHOLD`   | (unset)                                       | MB threshold for memory consumption test. Only runs when set. Reads cgroups v2 `memory.current`. |

## Download and Fetch (build-time)

Three-tier fetch model: local cache → Docker BuildKit cache → aria2c download.

| Variable                  | Default                      | Accepted values    | Controls                                                       |
| ------------------------- | ----------------------- -----| ------------------ | -------------------------------------------------------------- |
| `B19_FETCH_LOCAL_CACHE`   | `Y`                          | `Y`, `N`           | Enable Tier 1: check `.fetch` build context before network     |
| `B19_FETCH_DOCKER_CACHE`  | `Y`                          | `Y`, `N`           | Enable Tier 2: check BuildKit persistent cache before download |
| `B19_FETCH_LOCAL_PATH`    | `/fetch`                     | absolute path      | Mount point for `.fetch` context (set by Dockerfile `--mount`) |
| `B19_CACHE_PATH`          | `/var/cache/b19`             | absolute path      | Parent of the download cache mount, writable by `B19_UID`      |
| `B19_DOWNLOAD_PATH`       | `${B19_CACHE_PATH}/download` | absolute path      | BuildKit cache mount target for aria2c downloads               |
| `B19_DOWNLOAD_DISK_CACHE` | `64m`                        | aria2c size string | aria2c in-memory disk cache size                               |
| `B19_DOWNLOAD_MAX_TRIES`  | `4`                          | positive integer   | Max aria2c retry attempts per download                         |
| `B19_DOWNLOAD_RETRY_WAIT` | `16`                         | positive integer   | Seconds between aria2c retries                                 |
| `B19_BUILD_CA_FILE`       | (staged)                     | absolute path      | Build-host CA bundle staged from `M6E_CA_CERTIFICATES`         |
| `B19_BUILD_CA_ANCHOR`     | (transient)                  | absolute path      | Where a root stage installs it, then drops it pre-commit       |

Both CA variables are inert unless the build host sets `M6E_CA_CERTIFICATES` —
see [b19-fetch.md](b19-fetch.md) for why a privately fronted near cache needs
them and why the anchor never survives the `RUN` that creates it.

See [OFFGRID.md](OFFGRID.md) for the full three-tier model and interaction with offgrid mode.

## Report

| Variable                       | Default | Controls                                                                                                        |
| ------------------------------ | ------- | --------------------------------------------------------------------------------------------------------------- |
| `B19_REPORTD_FAT_FILES_AMOUNT` | `64`    | Number of largest files to report when running `report.d`. Scans root filesystem, sorts by size, outputs top N. |

## SSH

| Variable             | Default                                              | Controls                                                                                                          |
| -------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `B19_SSH_SCAN_HOSTS` | `"codeberg.org github.com gitlab.com bitbucket.org"` | Space-separated `hostname` or `hostname:port` for `ssh-keyscan` at build time. Skipped when `B19_OFFGRID_MODE=Y`. |

## Build-time Only (ARG)

These are `ARG` in the Dockerfile — set via `--build-arg`, not at runtime.

| Variable                    | Default                                         | Controls                                                                                                              |
| --------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `B19_BUILD_DISABLE_MOLD`    | (unset)                                         | Any non-empty value skips symlinking `mold` as default linker. Used by images where mold is incompatible (e.g. Ruby). |
| `B19_UBUNTU_SERIES`         | (axis)                                          | Ubuntu series for the FROM image (noble, resolute, etc.)                                                              |
| `B19_UBUNTU_HASH`           | `sha256:4a92…`                                  | Pinned digest for the `ubuntu` base image                                                                             |
| `B19_UBUNTU_MIRROR_AMD64`   | `http://archive.ubuntu.com/ubuntu/`             | APT mirror for amd64                                                                                                  |
| `B19_UBUNTU_MIRROR_ARM64`   | `http://ports.ubuntu.com/ubuntu-ports`          | APT mirror for arm64                                                                                                  |
| `B19_UBUNTU_MIRROR_RISCV64` | `http://ports.ubuntu.com/ubuntu-ports`          | APT mirror for riscv64                                                                                                |
| `B19_LOCALES`               | en_US, uk_UA, es_ES + 20 LATAM Spanish variants | Locales to generate at build time via `localedef`                                                                     |

## Identity and Paths

Core paths and user identity. Set at build time via `ARG`, baked into image via
`ENV`. Changing these at runtime is not recommended — they affect the entire
hook system.

### User identity

| Variable    | Default  | Controls                    |
| ----------- | -------- | --------------------------- |
| `B19_HOME`  | `/app`   | Working directory (WORKDIR) |
| `B19_USER`  | `ubuntu` | Non-root username           |
| `B19_UID`   | `1000`   | User UID                    |
| `B19_GROUP` | `ubuntu` | Group name                  |
| `B19_GID`   | `1000`   | Group GID                   |

### System paths

| Variable           | Default                | Controls                                |
| ------------------ | ---------------------- | --------------------------------------- |
| `B19_PREFIX`       | `/usr/local`           | System installation prefix              |
| `B19_BIN_PATH`     | `${B19_HOME}/bin`      | User binaries (on PATH)                 |
| `B19_TEMP_PATH`    | `/tmp`                 | Temporary files, tmpfs mount            |
| `B19_DOCKER_GID`   | `995`                  | Docker group GID (for Docker-in-Docker) |
| `B19_LINEAGE_FILE` | `${B19_HOME}/.lineage` | Image build lineage tracking file       |

### Hook directories

All runners discover scripts in these directories.

| Variable                     | Default                       | Runner               |
| ---------------------------- | ----------------------------- | -------------------- |
| `B19_ENTRYPOINT_PATH`        | `/entrypoint.d`               | entrypoint.d         |
| `B19_HEALTH_PATH`            | `/healthcheck.d`              | healthcheck.d        |
| `B19_TEST_PATH`              | `/test.d`                     | test.d               |
| `B19_TEST_RESULTS_PATH`      | `${B19_TEMP_PATH}/test.d`     | test.d               |
| `B19_BOOTSTRAP_PATH`         | `/bootstrap.d`                | bootstrap.d          |
| `B19_BOOTSTRAP_LOCK_PATH`    | `${XDG_DATA_HOME}/.bootstrap` | bootstrap.d          |
| `B19_BENCHMARK_PATH`         | `/benchmark.d`                | benchmark.d          |
| `B19_BENCHMARK_RESULTS_PATH` | `/tmp/benchmark.d`            | benchmark.d          |
| `B19_BUILD_PATH`             | `/build.d`                    | build-stage          |
| `B19_COMMAND_PATH`           | `/command.d`                  | (on PATH)            |
| `B19_TOOLS_PATH`             | `/tools.d`                    | (on PATH)            |
| `B19_SHELL_PATH`             | `/shell.d`                    | bash.bashrc          |
| `B19_DEPS_PATH`              | `/deps`                       | build-stage          |
| `B19_OVERLAYS_PATH`          | `/overlays/`                  | 0500-copy-overlay.sh |

## System-set Variables

Set automatically at runtime by the entrypoint system. Not intended for user
configuration, but useful in downstream scripts.

| Variable                      | Set by                  | Purpose                                                                                                                                                    |
| ----------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ENTRYPOINT_COMMAND_EXECUTED` | `2000-run-command.sh`   | `Y`/`N` — gates secret validation, bootstrap, and service start                                                                                            |
| `PAYLOAD_PID`                 | `b19-exec`              | PID of the main service process — published to `${B19_HOME}/.payload.pid` for signal forwarding (the subprocess `export` can’t reach the entrypoint shell) |
| `RETURN_CODE`                 | `b19-exec`              | Exit code of the main service                                                                                                                              |
| `NUMPROCS`                    | `0200-set-cpu-count.sh` | Detected CPU count (K8S > cgroups v2 > nproc)                                                                                                              |
| `STAGE`                       | `build-stage`           | Current build stage name (foundation, user, etc.)                                                                                                          |
| `_B19_I18N_MODE`              | `b19-i18n`              | Current i18n mode: `gettext`, `passthrough`, `disabled`                                                                                                    |

## Telemetry opt-out

Base-image default. Inherited by every downstream image; honored by tools that respect the standard.

| Variable       | Default | Controls                                                                                                                                                                   |
| -------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DO_NOT_TRACK` | `1`     | The [donottrack.sh](https://donottrack.sh/) standard opt-out. Set in the Dockerfile `ENV` block; downstream tools (e.g. grype, syft) honor it to skip anonymous analytics. |

## XDG Paths

Set in the Dockerfile for consistency with XDG Base Directory Specification.

| Variable          | Default               |
| ----------------- | --------------------- |
| `XDG_CACHE_HOME`  | `${B19_HOME}/.cache`  |
| `XDG_CONFIG_HOME` | `${B19_HOME}/.config` |
| `XDG_DATA_HOME`   | `${B19_HOME}/data`    |
| `XDG_STATE_HOME`  | `${B19_HOME}/.state`  |

## Complete Variable Index

Alphabetical list of every `B19_*` variable with its scope.

| Variable                        | Scope           | Section          |
| ------------------------------- | --------------- | ---------------- |
| ------------------------------- | --------------- | ---------------- |
| `B19_BENCHMARK_PATH`            | runtime         | Hook Directories |
| `B19_BENCHMARK_RESULTS_PATH`    | runtime         | Hook Directories |
| `B19_BIN_PATH`                  | build + runtime | System Paths     |
| `B19_BOOTSTRAP_ENABLED`         | runtime         | Feature Toggles  |
| `B19_BOOTSTRAP_LOCK_PATH`       | runtime         | Hook Directories |
| `B19_BOOTSTRAP_PATH`            | runtime         | Hook Directories |
| `B19_BOOTSTRAP_SKIP_*`          | runtime         | Per-script Skip  |
| `B19_BUILD_ALWAYS_ENABLED`      | build           | Feature Toggles  |
| `B19_BUILD_DISABLE_MOLD`        | build           | Build-time Only  |
| `B19_BUILD_PATH`                | runtime         | Hook Directories |
| `B19_COLOR`                     | build + runtime | Logging          |
| `B19_COMMAND_PATH`              | runtime         | Hook Directories |
| `B19_DEPS_PATH`                 | runtime         | Hook Directories |
| `B19_BUILD_CA_ANCHOR`           | build           | Download         |
| `B19_BUILD_CA_FILE`             | build           | Download         |
| `B19_CACHE_PATH`                | build + runtime | Download         |
| `B19_DOCKER_GID`                | build + runtime | System Paths     |
| `B19_DOWNLOAD_DISK_CACHE`       | build           | Download         |
| `B19_DOWNLOAD_MAX_TRIES`        | build           | Download         |
| `B19_DOWNLOAD_PATH`             | build           | Download         |
| `B19_DOWNLOAD_RETRY_WAIT`       | build           | Download         |
| `B19_ENTRYPOINT_ENABLED`        | runtime         | Feature Toggles  |
| `B19_ENTRYPOINT_PATH`           | runtime         | Hook Directories |
| `B19_ENTRYPOINT_SKIP_*`         | runtime         | Per-script Skip  |
| `B19_EXEC_STDERR_LEVEL`         | runtime         | Logging          |
| `B19_EXEC_STDOUT_LEVEL`         | runtime         | Logging          |
| `B19_FETCH_DOCKER_CACHE`        | build           | Download         |
| `B19_FETCH_LOCAL_CACHE`         | build           | Download         |
| `B19_FETCH_LOCAL_PATH`          | build           | Download         |
| `B19_GID`                       | build + runtime | User Identity    |
| `B19_GROUP`                     | build + runtime | User Identity    |
| `B19_HEALTH_CACHE_MIN_SPACE_KB` | runtime         | Health           |
| `B19_HEALTH_CURL_TIMEOUT`       | runtime         | Health           |
| `B19_HEALTH_ENABLED`            | runtime         | Feature Toggles  |
| `B19_HEALTH_HOME_MIN_SPACE_KB`  | runtime         | Health           |
| `B19_HEALTH_MEMORY_THRESHOLD`   | runtime         | Health           |
| `B19_HEALTH_NETWORK_URL`        | runtime         | Health           |
| `B19_HEALTH_PATH`               | runtime         | Hook Directories |
| `B19_HEALTH_PING_TARGETS`       | runtime         | Health           |
| `B19_HEALTH_TEMP_MIN_SPACE_KB`  | runtime         | Health           |
| `B19_HOME`                      | build + runtime | User Identity    |
| `B19_I18N_ENABLED`              | build + runtime | Feature Toggles  |
| `B19_IMMUTABLE`                 | runtime         | Behavior         |
| `B19_J2_EXCLUDE_PATTERNS`       | runtime         | Behavior         |
| `B19_LINEAGE_FILE`              | build + runtime | System Paths     |
| `B19_LOCALES`                   | build           | Build-time Only  |
| `B19_OFFGRID_MODE`              | build + runtime | Behavior         |
| `B19_OVERLAY`                   | runtime         | Behavior         |
| `B19_OVERLAYS_PATH`             | runtime         | Hook Directories |
| `B19_PORT_CHECK_ENABLED`        | runtime         | Feature Toggles  |
| `B19_PREFIX`                    | build + runtime | System Paths     |
| `B19_REPORTD_FAT_FILES_AMOUNT`  | runtime         | Report           |
| `B19_REQUIRED_SECRETS`          | runtime         | Behavior         |
| `B19_RUN_TIMING_PRECISION`      | runtime         | Logging          |
| `B19_SECRETS_ENABLED`           | runtime         | Feature Toggles  |
| `B19_SECRETS_PATH`              | runtime         | Secrets          |
| `B19_SHELL_ENABLED`             | build + runtime | Feature Toggles  |
| `B19_SHELL_PATH`                | runtime         | Hook Directories |
| `B19_SSH_SCAN_HOSTS`            | build           | SSH              |
| `B19_TEMP_PATH`                 | build + runtime | System Paths     |
| `B19_TEST_ENABLED`              | runtime         | Feature Toggles  |
| `B19_TEST_PATH`                 | runtime         | Hook Directories |
| `B19_TEST_RESULTS_PATH`         | runtime         | Hook Directories |
| `B19_TEST_TIMEOUT`              | runtime         | Behavior         |
| `B19_TOOLS_PATH`                | runtime         | Hook Directories |
| `B19_UBUNTU_HASH`               | build           | Build-time Only  |
| `B19_UBUNTU_MIRROR_AMD64`       | build           | Build-time Only  |
| `B19_UBUNTU_MIRROR_ARM64`       | build           | Build-time Only  |
| `B19_UBUNTU_MIRROR_RISCV64`     | build           | Build-time Only  |
| `B19_UBUNTU_SERIES`             | build           | Build-time Only  |
| `B19_UID`                       | build + runtime | User Identity    |
| `B19_USER`                      | build + runtime | User Identity    |
| `B19_VERBOSITY`                 | build + runtime | Logging          |
