<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# healthcheck.d — Container Health Monitoring System

The numbered-script runner that provides Docker-native health monitoring for every
b19-based container. Each check is a plain shell script; the runner discovers,
sorts, and executes them, reporting pass/fail counts to Docker.

## Architecture

```text
Docker daemon (periodic HEALTHCHECK interval)
  └─ healthcheck.d (runner: /tools.d/healthcheck.d)
       ├─ flock (prevent overlapping runs)
       ├─ load secrets (runs outside entrypoint context)
       └─ execute /healthcheck.d/*.sh in subshells (ascending order)
```

Declared once in `b19/ubuntu/Dockerfile:133`:

```dockerfile
HEALTHCHECK CMD ["healthcheck.d"]
```

All ~90 downstream images inherit this via Docker layer inheritance. Their
Dockerfiles contain only a comment:

```dockerfile
# HEALTHCHECK CMD ["healthcheck.d"] is inherited
```

## Runner Lifecycle

The runner is `/tools.d/healthcheck.d` (source:
`.container/foundation/tools.d/healthcheck.d`). When invoked:

1. Checks `B19_HEALTH_ENABLED` — exits 0 immediately if `false`
1. Acquires `flock` on `/tmp/healthcheck.d.lock` — exits 0 if another run is in progress
1. Sets `B19_COLOR=0` — output is stored by `docker inspect`, no ANSI escapes
1. Sources `b19-i18n` for `_()`, `_p()` translation functions
1. Sources `b19-load-secrets` — healthchecks run outside entrypoint context, secrets must be loaded explicitly
1. Finds all `*.sh` in `$B19_HEALTH_PATH` (default `/healthcheck.d`), sorts ascending (`sort -zn`)
1. Executes each in a **subshell** `( . "${CHECK}" )` — failures are isolated
1. Tracks `FINAL_EXIT_CODE` as a **counter of failed checks** (not a boolean)
1. Prints summary: `"N of M checks failed."` or `"All N checks passed."`
1. Exits with the failure count (0 = healthy)

### Key difference from other runners

| Runner        | Fail handling         | Sort order | Concurrency guard   |
| ------------- | --------------------- | ---------- | ------------------- |
| healthcheck.d | Continue, count fails | Forward    | `flock`             |
| test.d        | Continue, count fails | Reverse    | None                |
| entrypoint.d  | Abort (`set -e`)      | Forward    | None                |
| bootstrap.d   | Abort                 | Forward    | Lockfile per script |

The `flock` is critical: Docker can invoke HEALTHCHECK while a previous run is
still executing. Without it, two concurrent runs would interleave output and
produce duplicate log entries.

## Environment Variables

### Feature toggle

| Variable             | Default | Description                       |
| -------------------- | ------- | --------------------------------- |
| `B19_HEALTH_ENABLED` | `true`  | Set to `false` to skip all checks |

### Paths

| Variable          | Default          | Description                        |
| ----------------- | ---------------- | ---------------------------------- |
| `B19_HEALTH_PATH` | `/healthcheck.d` | Directory containing check scripts |

### Thresholds (base image defaults)

| Variable                        | Default                                       | Description                                     |
| ------------------------------- | --------------------------------------------- | ----------------------------------------------- |
| `B19_HEALTH_HOME_MIN_SPACE_KB`  | `32768`                                       | Min free KB in `$B19_HOME` before failing       |
| `B19_HEALTH_CACHE_MIN_SPACE_KB` | `32768`                                       | Min free KB in `$XDG_CACHE_HOME` before failing |
| `B19_HEALTH_TEMP_MIN_SPACE_KB`  | `32768`                                       | Min free KB in `$B19_TEMP_PATH` before failing  |
| `B19_HEALTH_CURL_TIMEOUT`       | `8`                                           | Timeout in seconds for curl-based checks        |
| `B19_HEALTH_NETWORK_URL`        | `"https://www.w3.org https://www.google.com"` | Space-separated URLs for connectivity checks    |
| `B19_HEALTH_PING_TARGETS`       | `"9.9.9.9 1.1.1.1 8.8.8.8"`                   | Space-separated IPs for ICMP checks             |
| `B19_HEALTH_MEMORY_THRESHOLD`   | (unset)                                       | MB threshold for memory consumption test        |

### Offgrid mode

When `B19_OFFGRID_MODE=Y`, all network checks (HTTPS, DNS, ping) are skipped
with a "skipped (offgrid mode)" log message and exit 0. Space checks still run.

## Base Checks (b19/Ubuntu)

Seven scripts ship in `.container/user/healthcheck.d/`:

| Slot | Script                           | Check                                                                           | Skip condition                              |
| ---- | -------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------- |
| 050  | `check-home-directory-space.sh`  | `$B19_HOME` has > `B19_HEALTH_HOME_MIN_SPACE_KB` KB free                        | Never                                       |
| 060  | `check-cache-directory-space.sh` | `$XDG_CACHE_HOME` has > `B19_HEALTH_CACHE_MIN_SPACE_KB`                         | Never                                       |
| 070  | `check-temp-directory-space.sh`  | `$B19_TEMP_PATH` has > `B19_HEALTH_TEMP_MIN_SPACE_KB`                           | Never                                       |
| 080  | `check-https-connectivity.sh`    | At least one `B19_HEALTH_NETWORK_URL` responds to `curl -I`                     | `B19_HEALTH_NETWORK_URL` empty, or offgrid  |
| 085  | `check-dns-resolution.sh`        | At least one hostname from `B19_HEALTH_NETWORK_URL` resolves via `getent hosts` | Same as 080                                 |
| 090  | `check-ping-connectivity.sh`     | At least one `B19_HEALTH_PING_TARGETS` responds to `ping -c 1 -W 2`             | `B19_HEALTH_PING_TARGETS` empty, or offgrid |
| 100  | `check-dummy.sh`                 | Can `touch` + `rm` a file in `B19_HEALTH_PATH`                                  | Never                                       |

### Check pattern: "at least one succeeds"

Network checks (080, 085, 090) iterate over multiple targets. Success of any
single target counts as pass. This avoids false positives from one flaky endpoint.

### Slot numbering convention

| Range   | Purpose                     | Reserved by                  |
| ------- | --------------------------- | ---------------------------- |
| 050-099 | System resource checks      | b19/Ubuntu (space, disk)     |
| 080-099 | Network connectivity checks | b19/Ubuntu (HTTP, DNS, ICMP) |
| 100-499 | Service-specific checks     | downstream project           |
| 500-999 | Advanced/integration checks | downstream project           |
| 1000+   | Multi-component checks      | downstream project           |

## How Checks Get Into the Image

The Dockerfile bulk-copies two directory trees to `/`:

```dockerfile
COPY .container/foundation/  /     # tools.d (runner), build hooks, locale
COPY .container/user/        /     # healthcheck.d (checks), entrypoint.d, test.d
```

Inside the container:

```text
/healthcheck.d/                     # B19_HEALTH_PATH
  050-check-home-directory-space.sh # from b19/ubuntu
  060-check-cache-directory-space.sh
  ...
  100-custom-health.sh              # from downstream image (layered on top)
```

Downstream projects’ checks merge via Docker layer overlay. The runner finds
all `*.sh` regardless of which image layer added them.

Permissions are set by the foundation build hook
`.container/foundation/build.d/foundation/post/200-permissions.sh`
which creates `$B19_HEALTH_PATH` and sets ownership to `$B19_UID:0`.

## Writing a Check

### Template

```bash
#!/usr/bin/env bash
set -o pipefail
# shellcheck source=b19-i18n

HTTP_PORT="${MY_PROJECT_HTTP_PORT}"

if ! curl -I --max-time "${B19_HEALTH_CURL_TIMEOUT}" -s \
     "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; then
  b19-log bad "HEALTH.D" "$(_p "Service not responding on port %s" "${HTTP_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is healthy on port %s" "${HTTP_PORT}")"
exit 0
```

### Rules

1. **`#!/usr/bin/env bash`** — always, for consistency
1. **`set -o pipefail`** — catch pipe failures (do NOT use `set -e` — the subshell runner does not need it, and it can cause unexpected aborts)
1. **Exit 0 = pass, non-zero = fail** — the runner captures `$?` after each subshell
1. **Source `b19-i18n`** if using `_()` or `_p()` for translatable strings (the runner sources it before checks, but subshells inherit it)
1. **Use `b19-log`** for all output — `b19-log good` for pass, `b19-log bad` for fail
1. **Tag all logs as `"HEALTH.D"`** — consistent prefix for filtering
1. **Wrap user-facing strings in `_()` or `_p()`** — i18n is mandatory (en, es, uk)
1. **Use `B19_HEALTH_CURL_TIMEOUT`** for cURL calls — respects the configured timeout
1. **Read config from env vars** — never hardcode ports, paths, or URLs
1. **Skip gracefully when optional** — check for the relevant env var and `exit 0` with a "skipped" log if absent
1. **Respect `B19_OFFGRID_MODE`** — network checks must skip when `B19_OFFGRID_MODE=Y`
1. **Do NOT leak secrets in logs** — mask passwords with `****`

### Common Patterns by Check Type

#### HTTP endpoint check (most common)

Used by: prometheus, grafana, traefik, keycloak, forgejo, mattermost, verdaccio, etc.

```bash
#!/usr/bin/env bash
set -o pipefail

HTTP_PORT="${NS_SERVICE_HTTP_PORT}"

if ! curl -I --max-time "${B19_HEALTH_CURL_TIMEOUT}" -s \
     "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; then
  b19-log bad "HEALTH.D" "$(_p "Health endpoint check failed on port %s" "${HTTP_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is responsive on port %s" "${HTTP_PORT}")"
exit 0
```

#### Database connection check

Used by: mariadb, PostgreSQL, MongoDB, valkey.

```bash
#!/usr/bin/env bash
set -o pipefail

if ! pg_isready -U "${NS_DB_USER}" -d "${NS_DB_NAME}" -h localhost -q; then
  b19-log bad "HEALTH.D" "$(_p "Database connection failure (%s)" "${NS_DB_USER}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Database is responsive (%s)" "${NS_DB_USER}")"
exit 0
```

#### Process liveness check

Used by: sidekiq, snowflake, webtunnel.

```bash
#!/usr/bin/env bash
set -o pipefail

if ! pgrep -x my-process >/dev/null 2>&1; then
  b19-log bad "HEALTH.D" "$(_p "%s is not running" "my-process")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "%s is running" "my-process")"
exit 0
```

#### HTTP status code check (exact code)

Used by: stalwart, docker-registry, apt-cache, nginx.

```bash
#!/usr/bin/env bash
set -o pipefail

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  "http://localhost:${NS_PORT}/endpoint" 2>/dev/null) || HTTP_CODE="000"

if [ "${HTTP_CODE}" != "200" ]; then
  b19-log bad "HEALTH.D" "$(_p "Service not responding (HTTP %s, port %s)" "${HTTP_CODE}" "${NS_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is responding (HTTP %s, port %s)" "${HTTP_CODE}" "${NS_PORT}")"
exit 0
```

#### Proxy-through check

Used by: squid, tor.

```bash
#!/usr/bin/env bash
set -o pipefail

if ! curl --proxy "socks5h://${NS_HOST}:${NS_PORT}" \
     --silent "${NS_VERIFICATION_URL}" | grep -q -m1 "expected string"; then
  b19-log bad "HEALTH.D" "$(_p "Proxy not working (port %s)" "${NS_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Proxy is working (port %s)" "${NS_PORT}")"
exit 0
```

#### Multi-endpoint check (healthy + ready + metrics)

Used by: prometheus, alertmanager, loki, tempo, blackbox-exporter.

Some services expose separate `/-/healthy`, `/-/ready`, and `/metrics` endpoints.
Each gets its own script at a different slot:

```text
100-check-service-health.sh      # /-/healthy
200-check-service-ready.sh       # /-/ready
210-check-service-metrics.sh     # /metrics
```

#### Multi-service variant check

Used by: weblate (web, celery-beat, celery-worker), mastodon (puma, sidekiq, streaming).

```bash
#!/usr/bin/env bash
set -eo pipefail

case "${D9T_WEBLATE_SERVICE}" in
  web)
    curl -sf "http://localhost:${D9T_WEBLATE_HTTP_PORT}/healthz/" >/dev/null
    ;;
  celery-beat)
    PIDFILE="${XDG_STATE_HOME}/celery/beat.pid"
    [ -f "${PIDFILE}" ] || exit 1
    PID=$(cat "${PIDFILE}")
    [ -d "/proc/${PID}" ] || exit 1
    ;;
  celery-worker)
    celery -A weblate.utils inspect ping --timeout 10
    ;;
  *)
    exit 1
    ;;
esac
```

## Adding Checks to a Downstream Project

1. Create `.container/user/healthcheck.d/NNN-check-name.sh`
1. Pick a slot in the appropriate range (100+ for service checks)
1. Ensure the Dockerfile copies `.container/user/` to `/` (standard pattern: `COPY .container/user/ /`)
1. Do NOT redeclare `HEALTHCHECK` in the Dockerfile — it is inherited from b19/Ubuntu
1. Add i18n strings to `.container/{stage}/locale/*.po` files

### Numbering collision avoidance

Base checks occupy slots 050-100. Downstream projects should start at 100+.
Within a project, use gaps of 10 between checks to allow future insertions:

```text
100-check-service-health.sh
200-check-service-ready.sh
500-check-advanced-feature.sh
```

### Disabling a check

Rename the file to `*.disabled`:

```text
100-check-service-health.sh.disabled
```

The runner only picks up `*.sh` files.

### Disabling all healthchecks at runtime

```bash
docker run -e B19_HEALTH_ENABLED=false ...
```

Or in compose:

```yaml
environment:
  B19_HEALTH_ENABLED: "false"
```

## Inspecting Health Status

### Docker CLI

```bash
docker inspect --format='{{.State.Health.Status}}' <container>
docker inspect --format='{{json .State.Health}}' <container> | jq
```

### Logs

Healthcheck output appears in `docker inspect` and `docker logs`. The runner
uses `b19-log` with forced `B19_COLOR=0` so output is plain text.

Typical output:

```text
[INFO]  HEALTH.D  Checks directory found
[INFO]  HEALTH.D  Executing check: 050-check-home-directory-space.sh
[GOOD]  HEALTH.D  /app (B19_HOME) has sufficient space: 12.50GiB > 32.00MiB
[INFO]  HEALTH.D  Executing check: 080-check-https-connectivity.sh
[GOOD]  HEALTH.D  HTTPS connectivity working (B19_HEALTH_NETWORK_URL: https://www.w3.org https://www.google.com)
[GOOD]  HEALTH.D  All 7 checks passed.
```

## i18n Integration

All check strings use `_()` (static) and `_p()` (printf-style) from `b19-i18n`.
Translation files live in `.container/{stage}/locale/`:

- `TEXTDOMAIN.pot` — template (extracted by `b19-compile-i18n`)
- `es.po` — Spanish (es_CL)
- `uk.po` — Ukrainian (uk_UA)

After adding or modifying translatable strings:

1. Run `make build` — `b19-compile-i18n` extracts strings to `.pot` and compiles `.po` → `.mo`
1. Update `.po` files with translations for new/changed `msgid` entries

## Downstream Checks Reference

55 custom healthcheck scripts across the ecosystem (as of 2026-04):

### b19 (2 checks, nginx only)

| Project | Script                                | Method                    |
| ------- | ------------------------------------- | ------------------------- |
| nginx   | `1100-check-ping-status.sh`           | HTTP status on status URL |
| nginx   | `1200-check-nginx-actual-response.sh` | `curl -I` on status URL   |

## Relation to Other Runners

| Runner        | When            | Fail mode | Secrets loaded | Concurrency     |
| ------------- | --------------- | --------- | -------------- | --------------- |
| healthcheck.d | Docker periodic | Continue  | Explicitly     | `flock`         |
| entrypoint.d  | Container start | Abort     | By 0100 hook   | None            |
| test.d        | `make test`     | Continue  | Via entrypoint | None            |
| bootstrap.d   | Container start | Abort     | Via entrypoint | Per-script lock |

`test.d` waits for `healthcheck.d` to pass before running (up to
`B19_TEST_TIMEOUT` seconds). This means service-specific healthchecks gate the
test suite — if the service is unhealthy, tests are skipped.

## Quick Reference

```text
Location:         .container/{stage}/healthcheck.d/
In-image path:    /healthcheck.d (B19_HEALTH_PATH)
Runner:           /tools.d/healthcheck.d
Sort order:       Forward numerical (ascending)
Fail behavior:    Continue (counts failures, exits with count)
Concurrency:      flock on /tmp/healthcheck.d.lock
Colors:           Forced off (B19_COLOR=0)
Secrets:          Loaded explicitly (b19-load-secrets)
Disable all:      B19_HEALTH_ENABLED=false
Disable single:   Rename to *.disabled
Offgrid:          B19_OFFGRID_MODE=Y (skips network checks)
Dockerfile:       HEALTHCHECK CMD ["healthcheck.d"] (inherited)
Scaffold:         .makefile/m6e/scaffold/shared/container/user/healthcheck.d/
```
