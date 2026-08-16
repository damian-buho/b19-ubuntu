<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Write healthchecks

`healthcheck.d` is the Docker-native health monitor every b19 image inherits: each check is a plain shell script, the runner discovers and sorts them, counts failures and reports the count to Docker. Seven checks ship in the base image — disk space, HTTPS, DNS, ICMP, writability — and downstream images add service-specific checks at slot 100+. The pitch: [container health monitoring](../features.d/healthcheck.d.md).

## When to use

- Every downstream image: add checks that probe the actual service, not just the process.
- Any container whose orchestrator (Docker, compose, Swarm) reads `State.Health.Status`.

## Quick start

```bash
# .container/user/healthcheck.d/100-check-service-health.sh
#!/usr/bin/env bash
set -o pipefail

HTTP_PORT="${NS_SERVICE_HTTP_PORT}"

if ! curl -I --max-time "${B19_HEALTH_CURL_TIMEOUT}" -s \
     "http://localhost:${HTTP_PORT}/health" >/dev/null 2>&1; then
  b19-log bad "HEALTH.D" "$(_p "Service not responding on port %s" "${HTTP_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is healthy on port %s" "${HTTP_PORT}")"
exit 0
```

Do not redeclare `HEALTHCHECK` in the Dockerfile — `HEALTHCHECK CMD ["healthcheck.d"]` is inherited from b19/Ubuntu; all downstream images get it via layer inheritance.

## How it works

```text
Docker daemon (periodic HEALTHCHECK interval)
  └─ healthcheck.d (runner: /tools.d/healthcheck.d)
       ├─ flock (prevent overlapping runs)
       ├─ load secrets (runs outside entrypoint context)
       └─ execute /healthcheck.d/*.sh in subshells (ascending order)
```

Runner lifecycle:

1. Checks `B19_HEALTH_ENABLED` — exits 0 immediately if `false`
1. Acquires `flock` on `/tmp/healthcheck.d.lock` — exits 0 if another run is still in progress (Docker can invoke HEALTHCHECK while a previous run executes; without the lock, two runs interleave output)
1. Sets `B19_COLOR=0` — output is stored by `docker inspect`, no ANSI escapes
1. Sources `b19-i18n` and `b19-load-secrets` — healthchecks run outside entrypoint context, so secrets are loaded explicitly
1. Finds all `*.sh` in `$B19_HEALTH_PATH`, sorts ascending, executes each in a **subshell** — failures are isolated
1. Exits with the **count** of failed checks (not a boolean): `N of M checks failed.` / `All N checks passed.`

The continue-and-count failure mode is the runner’s defining difference from the fail-fast runners — see [use the runner family](use-runner-family.md).

### Base checks (b19/Ubuntu)

| Slot | Script                           | Check                                                                                      | Skip condition                              |
| ---- | -------------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------- |
| 0100 | `check-home-directory-space.sh`  | `$B19_HOME` has > `B19_HEALTH_HOME_MIN_SPACE_KB` KB free                                   | Never                                       |
| 0200 | `check-cache-directory-space.sh` | `$XDG_CACHE_HOME` has > `B19_HEALTH_CACHE_MIN_SPACE_KB`                                    | Never                                       |
| 0300 | `check-temp-directory-space.sh`  | `$B19_TEMP_PATH` has > `B19_HEALTH_TEMP_MIN_SPACE_KB`                                      | Never                                       |
| 0400 | `check-https-connectivity.sh`    | At least one `B19_HEALTH_NETWORK_URL` responds to `curl -I`                                | `B19_HEALTH_NETWORK_URL` empty, or offgrid  |
| 0500 | `check-dns-resolution.sh`        | At least one hostname from `B19_HEALTH_NETWORK_URL` resolves via `getent`                  | Same as 0400                                |
| 0600 | `check-reachability.sh`          | At least one `B19_HEALTH_PING_TARGETS` answers a TCP probe on `B19_HEALTH_REACH_PORT_SAFE` | `B19_HEALTH_PING_TARGETS` empty, or offgrid |
| 0700 | `check-dummy.sh`                 | Can `touch` + `rm` a file in `B19_HEALTH_PATH`                                             | Never                                       |

Network checks iterate over multiple targets and pass when **any single target** succeeds — one flaky endpoint must not flag the container unhealthy. The reachability check probes TCP port 443 rather than ICMP: a `ping` needs `CAP_NET_RAW` or a permissive `ping_group_range`, which rootless and hardened containers do not have. The `B19_HEALTH_PING_TARGETS` name predates that switch and is kept for config stability. Under `B19_OFFGRID_MODE=Y` the network checks skip with a “skipped (offgrid mode)” line and exit 0; space checks still run.

### Slot numbering

| Range     | Purpose                 | Reserved by                  |
| --------- | ----------------------- | ---------------------------- |
| 0100-0300 | System resource checks  | b19/Ubuntu (space)           |
| 0400-0600 | Network checks          | b19/Ubuntu (HTTPS, DNS, TCP) |
| 0700      | Writability probe       | b19/Ubuntu                   |
| 1000+     | Service-specific checks | downstream project           |

Downstream checks merge via Docker layer overlay — the runner finds all `*.sh` regardless of which layer added them. Permissions are set by the foundation build hook `post/200-permissions.sh`, which creates `$B19_HEALTH_PATH` owned by `$B19_UID:0`.

## Writing a check

Rules:

1. `#!/usr/bin/env bash` and `set -o pipefail` — but **not** `set -e`; the subshell runner doesn’t need it and it causes unexpected aborts.
1. Exit 0 = pass, non-zero = fail — the runner captures `$?` after each subshell.
1. Use `b19-log good` / `b19-log bad`, always tagged `"HEALTH.D"`.
1. Wrap user-facing strings in `_()` / `_p()` — i18n is mandatory (en, es, uk).
1. Use `B19_HEALTH_CURL_TIMEOUT` for cURL calls; read config from env vars, never hardcode.
1. Skip gracefully when optional: absent env var → log “skipped” and `exit 0`.
1. Respect `B19_OFFGRID_MODE` — network checks must skip when it is `Y`.
1. Never leak secrets in logs — mask passwords with `****`.

### Patterns by check type

#### HTTP endpoint check (most common)

Used by prometheus, grafana, traefik, keycloak, forgejo, mattermost, verdaccio:

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

Used by mariadb, PostgreSQL, MongoDB, valkey:

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

Used by sidekiq, snowflake, webtunnel:

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

#### Exact HTTP status code

Used by stalwart, docker-registry, apt-cache, nginx:

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

Used by squid, tor:

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

#### Multi-endpoint services

Services exposing separate `/-/healthy`, `/-/ready` and `/metrics` endpoints (prometheus, alertmanager, loki, tempo) get one script per endpoint at its own slot:

```text
100-check-service-health.sh      # /-/healthy
200-check-service-ready.sh       # /-/ready
210-check-service-metrics.sh     # /metrics
```

#### Multi-service variant check

One image serving several roles (weblate: web, celery-beat, celery-worker; mastodon: puma, sidekiq, streaming) switches on the role variable:

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

## Configuration

| Variable                        | Default                                       | Description                                        |
| ------------------------------- | --------------------------------------------- | -------------------------------------------------- |
| `B19_HEALTH_ENABLED`            | `true`                                        | Set to `false` to skip all checks                  |
| `B19_HEALTH_PATH`               | `/healthcheck.d`                              | Directory containing check scripts                 |
| `B19_HEALTH_HOME_MIN_SPACE_KB`  | `32768`                                       | Min free KB in `$B19_HOME` before failing          |
| `B19_HEALTH_CACHE_MIN_SPACE_KB` | `32768`                                       | Min free KB in `$XDG_CACHE_HOME` before failing    |
| `B19_HEALTH_TEMP_MIN_SPACE_KB`  | `32768`                                       | Min free KB in `$B19_TEMP_PATH` before failing     |
| `B19_HEALTH_CURL_TIMEOUT`       | `8`                                           | Timeout in seconds for curl-based checks           |
| `B19_HEALTH_NETWORK_URL`        | `"https://www.w3.org https://www.google.com"` | Space-separated URLs for HTTPS and DNS checks      |
| `B19_HEALTH_PING_TARGETS`       | `"9.9.9.9 1.1.1.1 8.8.8.8"`                   | Space-separated IPs for the TCP reachability probe |
| `B19_HEALTH_REACH_PORT_SAFE`    | `443`                                         | TCP port probed by the reachability check          |
| `B19_HEALTH_MEMORY_THRESHOLD`   | (unset)                                       | MB threshold for memory consumption test           |

The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```text
100-check-service-health.sh.disabled     # rename — the runner only picks up *.sh
```

```bash
docker run -e B19_HEALTH_ENABLED=false ...
```

```yaml
# compose
environment:
  B19_HEALTH_ENABLED: "false"
```

```bash
# Inspect health status
docker inspect --format='{{.State.Health.Status}}' <container>
docker inspect --format='{{json .State.Health}}' <container> | jq
```

Typical runner output (plain text, colors forced off):

```text
[INFO]  HEALTH.D  Executing check: 0100-check-home-directory-space.sh
[GOOD]  HEALTH.D  /app (B19_HOME) has sufficient space: 12.50GiB > 32.00MiB
[INFO]  HEALTH.D  Executing check: 0400-check-https-connectivity.sh
[GOOD]  HEALTH.D  HTTPS connectivity working (B19_HEALTH_NETWORK_URL: https://www.w3.org https://www.google.com)
[GOOD]  HEALTH.D  All 7 checks passed.
```

After adding strings, run `make build` so `b19-compile-i18n` refreshes the `.pot` and compiles `.po` → `.mo`, then update `.container/{stage}/locale/*.po`.

## Quick reference

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
```

## See also

- [Use the runner family](use-runner-family.md) — the eight runners and their failure modes
- [Run offgrid builds](use-offgrid.md) — why the network checks go quiet
- [Test images with test.d](use-test.d.md) — the suite that waits for these checks to pass
- [Load secrets](use-secrets.md) — what the runner loads before your checks run
