<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Write healthchecks

`healthcheck.d` is the Docker-native health monitor every b19 image inherits: each check is a plain shell script, the runner discovers and sorts them, runs them in parallel under one deadline, counts failures and reports the count to Docker. Eight checks ship in the base image — disk space, HTTPS, DNS, TCP reachability, writability, and a generic listen-port probe — and downstream images add service-specific checks in their own slot range. The pitch: [container health monitoring](../features.d/healthcheck.d.md).

Checks that reach the public internet are opt-in: `check-https-connectivity.sh`, `check-dns-resolution.sh` and `check-reachability.sh` stand down unless `B19_HEALTH_EGRESS=true`. Each carries the guard itself, next to the offgrid guard it already had — the runner dispatches on nothing. A container that only serves local traffic carries no check that a third party can fail, and a container whose whole job is egress (proxy, mirror, relay) turns them on and reports unhealthy when the outside is gone. See [Egress checks](#egress-checks) below.

## When to use

- Every downstream image: add checks that probe the actual service, not just the process.
- Any container whose orchestrator (Docker, compose, Swarm) reads `State.Health.Status`.
- Any service that can end up alive but useless, where a restart is the cure — see [Act on unhealthy](#act-on-unhealthy).

## Quick start

```bash
# .container/user/healthcheck.d/1100-check-service-health.sh
#!/usr/bin/env bash

HTTP_PORT="${NS_SERVICE_HTTP_PORT}"

if ! curl --fail --silent --max-time 2 --output /dev/null \
     "http://localhost:${HTTP_PORT}/health"; then
  b19-log bad "HEALTH.D" "$(_p "Service not responding on port %s" "${HTTP_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is healthy on port %s" "${HTTP_PORT}")"
```

Do not redeclare `HEALTHCHECK` in the Dockerfile — `HEALTHCHECK CMD ["healthcheck.d"]` is inherited from b19/Ubuntu; all downstream images get it via layer inheritance.

## Compared with a traditional healthcheck

A traditional healthcheck is one command in the Dockerfile — `HEALTHCHECK CMD curl -f http://localhost/ || exit 1` — and Docker runs it on a timer. `healthcheck.d` keeps that contract with Docker and replaces everything behind it.

| Concern               | Traditional `HEALTHCHECK CMD …`                                                       | `healthcheck.d`                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Definition            | One command per image; a child that adds a check replaces its parent’s                | A directory of scripts merged across every image layer; a child adds a file and keeps the parent’s checks           |
| Composition           | Checks chained with `&&` stop at the first failure                                    | Every check runs, in parallel up to `NUMPROCS`; the exit code is the number of failures                             |
| Diagnosis             | Last 4 KB of mixed output in `docker inspect`                                         | One log line per check, plus the sorted names of failed checks on stdout                                            |
| A hung probe          | Docker kills it at `--timeout`, discards its output, and nothing names the cause      | A shared deadline kills the hung check first, logs it as timed out, and counts it                                   |
| Heavy or rate-limited | Runs on every interval, or needs hand-rolled throttling                               | Lives in a [tier](#interval-tiers): runs detached, at most once per interval; the probe reads its last verdict      |
| Secrets               | Only the container environment; Docker secret files are unread                        | Loads `/run/secrets` itself, the same way the entrypoint does                                                       |
| Internet dependence   | Often probes an outside URL, so a third-party outage marks a local service unhealthy  | Egress checks are opt-in, and stand down in offgrid mode                                                            |
| Deploys               | No way to take a healthy container out of rotation                                    | A [drain file](#egress-checks) reports not ready while in-flight requests finish                                    |
| Acting on unhealthy   | Compose and plain Docker never act; a restart needs a watchdog with the Docker socket | Opt-in `B19_HEALTH_EXIT_AFTER`: the container stops itself after N failed probes and its restart policy restarts it |
| Switching off         | Rebuild, or `--no-healthcheck` for the whole container                                | `B19_HEALTH_ENABLED=false` for all, `B19_HEALTH_SKIP_<NAME>=true` for one, no rebuild                               |
| Tests                 | Nothing waits for it                                                                  | `test.d` waits until it passes before running tests                                                                 |

## How it works

```text
Docker daemon (every --interval)
  └─ healthcheck.d (runner: /tools.d/healthcheck.d)
       ├─ B19_HEALTH_ENABLED=false → pass
       ├─ flock (wait for an overlapping run, bounded)
       ├─ load secrets (runs outside entrypoint context)
       ├─ drain gate ($B19_HEALTH_DRAIN_FILE present → not ready)
       ├─ run /healthcheck.d/*.sh in parallel, capped at NUMPROCS, under one shared deadline
       ├─ answer /healthcheck.d/<tier>/*.sh from their last verdict
       ├─ count consecutive failed probes (B19_HEALTH_EXIT_AFTER set) → TERM to PID 1 at N
       └─ stdout: failed check names · exit code: number of failed checks
```

Runner lifecycle:

1. Checks `B19_HEALTH_ENABLED` — exits 0 immediately if `false`
1. Acquires `flock` on `/tmp/healthcheck.d.lock` — waits up to `B19_HEALTH_LOCK_TIMEOUT` seconds for a run still in progress, then reports unhealthy, so an overlapping caller never reads a pass nobody checked
1. Sets `B19_COLOR=auto` — color only on a TTY; `docker inspect` and file redirects get plain text automatically
1. Sources `b19-i18n` and `b19-load-secrets` — healthchecks run outside entrypoint context, so secrets are loaded explicitly
1. Checks `B19_HEALTH_DRAIN_FILE` — exits 1 unconditionally if present
1. Finds all `*.sh` directly in `$B19_HEALTH_PATH` (not in subdirectories — those are [tiers](#interval-tiers)) and sorts them ascending
1. Runs each surviving check **in the background**, each in a fresh `bash` that loads the same helpers, `</dev/null` so a check reading stdin cannot drain the pipe the outer loop still reads paths from. `NUMPROCS` is unset inside a healthcheck (a fresh daemon-spawned process, not the entrypoint tree that exports it), so the runner sources `detect-cpu-count` itself and reaps with `wait -n -p` once concurrency hits that cap. Failures are isolated per check
1. Bounds the inline checks with one shared deadline — see [Time budget](#time-budget)
1. Answers each tier check from its stored verdict, starting a detached re-run when it is due
1. Logs `N of M checks failed: <names>` or `All N checks passed.`
1. With `B19_HEALTH_EXIT_AFTER` set, updates the consecutive-failure count — see [Act on unhealthy](#act-on-unhealthy)
1. Prints the sorted names of the failed checks on stdout (empty when all passed) and exits with the **count** of failed checks. Docker counts any non-zero exit as a failed probe

The continue-and-count failure mode is the runner’s defining difference from the fail-fast runners — see [use the runner family](use-runner-family.md).

### Docker’s side

The base image declares the schedule once; every child inherits it:

```dockerfile
HEALTHCHECK --start-period=90s --start-interval=1s --interval=10s --timeout=5s --retries=3 \
    CMD ["healthcheck.d"]
```

- `--start-period=90s` with `--start-interval=1s` — during the first 90 s Docker probes every second and a failure does not count, so a container turns healthy as soon as it is ready.
- `--interval=10s` — one probe every 10 s afterwards.
- `--timeout=5s` — Docker kills a probe that runs longer and records it as failed, without its output.
- `--retries=3` — three failed probes in a row turn the status to `unhealthy`.

### Time budget

Every bound sits inside the one around it, so a probe always ends with a verdict the runner wrote itself, never with Docker’s kill:

| Bound                      | Default | Scope                                                                 |
| -------------------------- | ------- | --------------------------------------------------------------------- |
| `HEALTHCHECK --timeout`    | `5` s   | The whole probe; Docker kills it past this and loses its output       |
| `B19_HEALTH_LOCK_TIMEOUT`  | `4` s   | Waiting for an overlapping run; only spent when two probes overlap    |
| `B19_HEALTH_CHECK_TIMEOUT` | `3` s   | All inline checks together, counted from the first launch             |
| A check’s own timeouts     | —       | Must fit in what is left; `--max-time 2` is a safe choice for `curl`  |
| `B19_HEALTH_TIER_TIMEOUT`  | `300` s | One detached tier check; outside the probe, so never against Docker’s |

Each inline check receives the time left until the shared deadline (at least 1 s), so a queue of slow checks on a one-CPU container still ends in time. When time runs out, `timeout(1)` stops the check together with every process it started, the runner logs `Check timed out: <name>`, and the check counts as failed. A check that needs more time belongs in a tier. An image that must run slow inline checks raises `B19_HEALTH_CHECK_TIMEOUT` and its own `HEALTHCHECK --timeout` together.

### Act on unhealthy

Compose and plain Docker only report `unhealthy`; a restart policy acts on an exit, never on a status. `B19_HEALTH_EXIT_AFTER=N` closes that gap from inside the container, with no watchdog and no Docker socket:

- Each probe that fails adds one to a counter stored under `${B19_TEMP_PATH}/healthcheck.d/`; a passing probe resets it.
- At N, the runner sends `TERM` to PID 1. The container stops cleanly, and `restart: unless-stopped` (or `always`, or `on-failure`) starts a fresh one.
- Probes during the first `B19_HEALTH_EXIT_GRACE` seconds after start never count, so a slow start is not a crash loop.
- A draining container never counts: the drain gate exits before the counter.
- The readiness wait inside `test.d` never counts either.

Unset (the default) turns it off. It is a runtime choice, so set it where the restart policy lives — the compose file — rather than in the image. It pays off when the checks probe only the container itself and a fresh start cures the failure: a wedged worker, a stuck process pool, a sub-process that died while PID 1 lives on. Leave it off when:

- A check reaches a dependency (a database, a broker, an upstream API): the outage outside restarts a healthy container in a loop.
- The service holds state that a restart puts through recovery (a database): a slow probe under load then turns into a restart under load.
- The service is the edge every request passes through: a restart drops all traffic.

### Base checks (b19/Ubuntu)

| Slot | Script                           | Check                                                                                      | Skip condition                                         |
| ---- | -------------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------ |
| 0100 | `check-home-directory-space.sh`  | `$B19_HOME` has > `B19_HEALTH_HOME_MIN_SPACE_KB` KB free                                   | Never                                                  |
| 0200 | `check-cache-directory-space.sh` | `$XDG_CACHE_HOME` has > `B19_HEALTH_CACHE_MIN_SPACE_KB`                                    | Never                                                  |
| 0300 | `check-temp-directory-space.sh`  | `$B19_TEMP_PATH` has > `B19_HEALTH_TEMP_MIN_SPACE_KB`                                      | Never                                                  |
| 0400 | `check-https-connectivity.sh`    | At least one `B19_HEALTH_NETWORK_URL` responds to `curl -I`                                | `B19_HEALTH_EGRESS` not `true`, empty URL, or offgrid  |
| 0500 | `check-dns-resolution.sh`        | At least one hostname from `B19_HEALTH_NETWORK_URL` resolves via `getent`                  | Same as 0400                                           |
| 0600 | `check-reachability.sh`          | At least one `B19_HEALTH_PING_TARGETS` answers a TCP probe on `B19_HEALTH_REACH_PORT_SAFE` | `B19_HEALTH_EGRESS` not `true`, no targets, or offgrid |
| 0700 | `check-dummy.sh`                 | Can `touch` + `rm` a file in `B19_HEALTH_PATH`                                             | Never                                                  |
| 0800 | `check-listen.sh`                | TCP-connects `127.0.0.1:B19_READY_PORT`                                                    | `B19_READY_PORT` empty                                 |

Any check — including the space checks — can also be disabled individually at runtime
with `B19_HEALTH_SKIP_<NAME>=true` (see [configure-environment](configure-environment.md)),
which logs a “Skipped” line and counts as neither passed nor failed.

Network checks iterate over multiple targets and pass when **any single target** succeeds — one flaky endpoint must not flag the container unhealthy. The reachability check probes TCP port 443 rather than ICMP: a `ping` needs `CAP_NET_RAW` or a permissive `ping_group_range`, which rootless and hardened containers do not have. The `B19_HEALTH_PING_TARGETS` name predates that switch and is kept for config stability. Under `B19_OFFGRID_MODE=Y` the network checks skip with a “skipped (offgrid mode)” line and exit 0; space checks still run.

### Slot numbering

The leading digit is the image’s **depth in the lineage**, not a category: b19/Ubuntu
owns `0xxx`, an image built on it owns `1xxx`, an image built on that one owns `2xxx`.
A check therefore sorts after every check of the image it inherits from.

| Range     | Purpose                   | Reserved by                  |
| --------- | ------------------------- | ---------------------------- |
| 0100-0300 | System resource checks    | b19/Ubuntu (space)           |
| 0400-0600 | HTTPS, DNS, reachability  | b19/Ubuntu                   |
| 0700      | Writability probe         | b19/Ubuntu                   |
| 0800      | Generic listen-port probe | b19/Ubuntu                   |
| 1xxx      | Service-specific checks   | an image built on b19/Ubuntu |
| 2xxx      | Service-specific checks   | an image built on that one   |

Downstream checks merge via Docker layer overlay — the runner finds all `*.sh` regardless of which layer added them. Permissions are set by the foundation build hook `post/200-permissions.sh`, which creates `$B19_HEALTH_PATH` owned by `$B19_UID:0`.

### Interval tiers

A heavy or rate-limited check — a compliance scan, a probe against a public rate limit — must not run on every 10 s probe. Put it in a tier subdirectory instead of throttling it by hand:

```text
/healthcheck.d/0100-check-listen.sh        every probe
/healthcheck.d/hourly/0900-check-audit.sh  at most once per B19_HEALTH_HOURLY_INTERVAL (3600 s)
```

- The check script stays unaware of its cadence; the runner owns scheduling, locking and logging. A subdirectory merges across image layers like every other `*.d`.
- A tier check runs **detached** from the probe, so a run longer than the `HEALTHCHECK` `--timeout` never fails it. The probe only reads the last verdict — exit code, age and last log line, written atomically under `${B19_TEMP_PATH}/healthcheck.d/`.
- No verdict yet → the probe starts the check and passes. `B19_HEALTH_TIER_TIMEOUT` bounds a run, so a hung check turns into a failing verdict instead of a pass that never ends.
- A passing verdict is reused for the tier interval; a failing one is retried after `B19_HEALTH_RETRY_INTERVAL` (when shorter), so an outage clears fast without re-running a heavy check on every probe. The stale verdict keeps answering while the re-run is in flight.
- `B19_HEALTH_INTERVAL_<NAME>` overrides the interval of one check (`B19_HEALTH_INTERVAL_CHECK_AUDIT=900`); `B19_HEALTH_SKIP_<NAME>` mutes it as usual.
- A tier needs its interval variable: a subdirectory with no `B19_HEALTH_<TIER>_INTERVAL` is ignored with a warning. `hourly` is the only tier the base declares.

### Egress checks

Most containers never talk to the public internet, and a check they cannot fail is a check worth not running.

- **`B19_HEALTH_EGRESS=false`** (default) stands the three egress checks down with a “skipped” line: no `curl`, no `getent`, no TCP probe, nothing to time out.
- **`B19_HEALTH_EGRESS=true`** runs them, and losing the outside marks the container unhealthy. Set it on images that cannot do their job offline — a proxy, a mirror, a relay, a federating service. Their `B19_HEALTH_CURL_TIMEOUT` (8 s) is longer than the shared deadline, so a slow outside answer counts as a failure; raise `B19_HEALTH_CHECK_TIMEOUT` with `HEALTHCHECK --timeout` if that is too strict.
- `check-listen.sh` ships in the base image and is the only check most images need for a working readiness probe: set `B19_READY_PORT` to the port the service listens on and it TCP-connects `127.0.0.1:$B19_READY_PORT`. Empty (the default) skips it — a plain b19/Ubuntu container has nothing to probe.
  Reference the project’s own port variable, never a second literal: declare it in its own `ENV` instruction ahead of the main block, then read it back — Docker resolves an `ENV`-to-`ENV` reference across instructions, but not within the same multi-key instruction. Two independent literals (`B19_READY_PORT=8080` next to `MYPROJECT_PORT=8080`) drift silently the day one changes and the other doesn’t. See `d9t/mcphub`’s Dockerfile for the pattern.
- **`B19_HEALTH_DRAIN_FILE`** (default `/tmp/b19-draining`): when this path exists, the runner reports not ready before anything else runs. A blue-green flip touches it on the outgoing container so Traefik routes around it while it keeps serving in-flight requests — see [blue-green deploy](../../../../blue-green.md).

## Writing a check

Rules:

1. The runner sources the check in a fresh `bash` under `set -euo pipefail`. Test every command that may fail with `if !` or `||`, and read an optional variable as `${VAR:-}` — an unset one otherwise fails the check. Keep the `#!/usr/bin/env bash` line for linters.
1. Exit 0 = pass, non-zero = fail; `exit` and `return` both end the check.
1. Probe the service, not the process: `curl --fail` turns an HTTP error into a failure, while a bare `curl -I` passes on any answer, `500` included.
1. Bound every call well inside [the time budget](#time-budget) — `--max-time 2` for `curl`. A call that needs longer belongs in a tier.
1. Probe only what the container owns. A check that reaches a database or an upstream API marks this container unhealthy for someone else’s outage.
1. Use `b19-log good` / `b19-log bad`, always tagged `"HEALTH.D"`.
1. Wrap user-facing strings in `_()` / `_p()` — i18n is mandatory (en, es, uk).
1. Read config from env vars, never hardcode.
1. Skip gracefully when optional: absent env var → log “skipped” and `exit 0`.
1. Respect `B19_OFFGRID_MODE` — network checks must skip when it is `Y`.
1. Never leak secrets in logs — mask passwords with `****`.

### Patterns by check type

#### HTTP endpoint check (most common)

Used by prometheus, grafana, traefik, keycloak, forgejo, mattermost, verdaccio:

```bash
#!/usr/bin/env bash

HTTP_PORT="${NS_SERVICE_HTTP_PORT}"

if ! curl --fail --silent --max-time 2 --output /dev/null \
     "http://localhost:${HTTP_PORT}/health"; then
  b19-log bad "HEALTH.D" "$(_p "Health endpoint check failed on port %s" "${HTTP_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is responsive on port %s" "${HTTP_PORT}")"
```

#### Database connection check

Used by mariadb, PostgreSQL, MongoDB, valkey:

```bash
#!/usr/bin/env bash

if ! pg_isready --timeout 2 -U "${NS_DB_USER}" -d "${NS_DB_NAME}" -h localhost -q; then
  b19-log bad "HEALTH.D" "$(_p "Database connection failure (%s)" "${NS_DB_USER}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Database is responsive (%s)" "${NS_DB_USER}")"
```

#### Process liveness check

Used by sidekiq, snowflake, webtunnel. `pgrep` comes from `procps`, which the base image does not ship:

```bash
#!/usr/bin/env bash

if ! pgrep -x my-process >/dev/null; then
  b19-log bad "HEALTH.D" "$(_p "%s is not running" "my-process")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "%s is running" "my-process")"
```

#### Exact HTTP status code

Used by stalwart, docker-registry, apt-cache, nginx:

```bash
#!/usr/bin/env bash

HTTP_CODE=$(curl --silent --max-time 2 --output /dev/null --write-out '%{http_code}' \
  "http://localhost:${NS_PORT}/endpoint") || HTTP_CODE="000"

if [ "${HTTP_CODE}" != "200" ]; then
  b19-log bad "HEALTH.D" "$(_p "Service not responding (HTTP %s, port %s)" "${HTTP_CODE}" "${NS_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Service is responding (HTTP %s, port %s)" "${HTTP_CODE}" "${NS_PORT}")"
```

#### Proxy-through check

Used by squid, tor. The verification URL is outside the container, so this is an egress check: keep it behind `B19_HEALTH_EGRESS`, or in a tier when the target is rate-limited:

```bash
#!/usr/bin/env bash

if ! curl --proxy "socks5h://${NS_HOST}:${NS_PORT}" --silent --max-time 2 \
     "${NS_VERIFICATION_URL}" | grep --quiet --max-count 1 "expected string"; then
  b19-log bad "HEALTH.D" "$(_p "Proxy not working (port %s)" "${NS_PORT}")"
  exit 1
fi

b19-log good "HEALTH.D" "$(_p "Proxy is working (port %s)" "${NS_PORT}")"
```

#### Multi-endpoint services

Services exposing separate `/-/healthy`, `/-/ready` and `/metrics` endpoints (prometheus, alertmanager, loki, tempo) get one script per endpoint at its own slot:

```text
1100-check-service-health.sh      # /-/healthy
1200-check-service-ready.sh       # /-/ready
1210-check-service-metrics.sh     # /metrics
```

#### Multi-service variant check

One image serving several roles (weblate: web, celery-beat, celery-worker; mastodon: puma, sidekiq, streaming) switches on the role variable:

```bash
#!/usr/bin/env bash

case "${D9T_WEBLATE_SERVICE}" in
  web)
    curl --fail --silent --max-time 2 --output /dev/null "http://localhost:${D9T_WEBLATE_HTTP_PORT}/healthz/"
    ;;
  celery-beat)
    PIDFILE="${XDG_STATE_HOME}/celery/beat.pid"
    [ -f "${PIDFILE}" ] || exit 1
    PID=$(cat "${PIDFILE}")
    [ -d "/proc/${PID}" ] || exit 1
    ;;
  celery-worker)
    celery -A weblate.utils inspect ping --timeout 2
    ;;
  *)
    exit 1
    ;;
esac
```

## Configuration

| Variable                        | Default                                       | Description                                                        |
| ------------------------------- | --------------------------------------------- | ------------------------------------------------------------------ |
| `B19_HEALTH_ENABLED`            | `true`                                        | Set to `false` to skip all checks                                  |
| `B19_HEALTH_SKIP_<NAME>`        | (unset)                                       | Skip one check by name (`B19_HEALTH_SKIP_CHECK_REACHABILITY=true`) |
| `B19_HEALTH_EGRESS`             | `false`                                       | `true` runs the egress checks (HTTPS, DNS, reachability)           |
| `B19_HEALTH_DRAIN_FILE`         | `/tmp/b19-draining`                           | Present → reports not ready                                        |
| `B19_READY_PORT`                | (unset)                                       | Port `check-listen.sh` TCP-connects on `127.0.0.1`                 |
| `B19_HEALTH_PATH`               | `/healthcheck.d`                              | Directory containing check scripts                                 |
| `B19_HEALTH_HOURLY_INTERVAL`    | `3600`                                        | Seconds a passing verdict of an `hourly/` check is reused          |
| `B19_HEALTH_RETRY_INTERVAL`     | `60`                                          | Seconds before a failing tier verdict is re-run                    |
| `B19_HEALTH_TIER_TIMEOUT`       | `300`                                         | Seconds a detached tier check may run before it counts as failed   |
| `B19_HEALTH_INTERVAL_<NAME>`    | (unset)                                       | Per-check interval override for a tier check                       |
| `B19_HEALTH_HOME_MIN_SPACE_KB`  | `32768`                                       | Min free KB in `$B19_HOME` before failing                          |
| `B19_HEALTH_CACHE_MIN_SPACE_KB` | `32768`                                       | Min free KB in `$XDG_CACHE_HOME` before failing                    |
| `B19_HEALTH_TEMP_MIN_SPACE_KB`  | `32768`                                       | Min free KB in `$B19_TEMP_PATH` before failing                     |
| `B19_HEALTH_CURL_TIMEOUT`       | `8`                                           | Timeout in seconds for the egress `curl` checks                    |
| `B19_HEALTH_LOCK_TIMEOUT`       | `4`                                           | Seconds to wait for an overlapping run before failing              |
| `B19_HEALTH_CHECK_TIMEOUT`      | `3`                                           | Seconds all inline checks of one probe may take together           |
| `B19_HEALTH_EXIT_AFTER`         | (empty)                                       | Consecutive failed probes before PID 1 gets `TERM`; empty is off   |
| `B19_HEALTH_EXIT_GRACE`         | `90`                                          | Seconds after start during which failed probes do not count        |
| `B19_HEALTH_NETWORK_URL`        | `"https://www.w3.org https://www.google.com"` | Space-separated URLs for HTTPS and DNS checks                      |
| `B19_HEALTH_PING_TARGETS`       | `"9.9.9.9 1.1.1.1 8.8.8.8"`                   | Space-separated IPs for the TCP reachability probe                 |
| `B19_HEALTH_REACH_PORT_SAFE`    | `443`                                         | TCP port probed by the reachability check                          |
| `B19_HEALTH_MEMORY_THRESHOLD`   | (unset)                                       | MB threshold for memory consumption test                           |

The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```text
1100-check-service-health.sh.disabled     # rename — the runner only picks up *.sh
```

```bash
docker run -e B19_HEALTH_ENABLED=false ...
```

```yaml
# compose: restart the service after 3 failed probes in a row
restart: unless-stopped
environment:
  B19_HEALTH_EXIT_AFTER: "3"
```

```bash
# Inspect health status
docker inspect --format='{{.State.Health.Status}}' <container>
docker inspect --format='{{json .State.Health}}' <container> | jq

# Run one probe by hand, at full verbosity
docker exec --env B19_VERBOSITY=debug <container> healthcheck.d
```

Typical runner output with egress off — the default (plain text, no TTY):

```text
[INFO]  HEALTH.D  Checks directory found
[INFO]  HEALTH.D  Executing check: 0100-check-home-directory-space.sh
[GOOD]  HEALTH.D  /app (B19_HOME) has sufficient space: 12.50GiB > 32.00MiB
[INFO]  HEALTH.D  Executing check: 0400-check-https-connectivity.sh
[GOOD]  HEALTH.D  HTTPS connectivity check skipped (B19_HEALTH_EGRESS not enabled)
[INFO]  HEALTH.D  Executing check: 0800-check-listen.sh
[GOOD]  HEALTH.D  Listening on 127.0.0.1:8080
[GOOD]  HEALTH.D  All 8 checks passed.
```

The same run under `B19_HEALTH_EGRESS=true` reaches the network instead of standing down:

```text
[INFO]  HEALTH.D  Executing check: 0400-check-https-connectivity.sh
[GOOD]  HEALTH.D  HTTPS connectivity working (B19_HEALTH_NETWORK_URL: https://www.w3.org https://www.google.com)
[INFO]  HEALTH.D  Executing check: 0600-check-reachability.sh
[BAD]   HEALTH.D  Check timed out: 0600-check-reachability.sh (probe deadline 3 s)
[BAD]   HEALTH.D  1 of 8 checks failed: 0600-check-reachability.sh
```

After adding strings, run `make i18n-extract i18n-update` to refresh the `.pot` and merge it into `.container/{stage}/locale/*.po`, then translate the new entries.

## Quick reference

```text
Location:         .container/{stage}/healthcheck.d/
In-image path:    /healthcheck.d (B19_HEALTH_PATH)
Runner:           /tools.d/healthcheck.d
Sort order:       Forward numerical (ascending)
Execution:        Parallel, capped at NUMPROCS, one fresh bash per check
Fail behavior:    Continue (counts failures, exits with count)
Deadline:         B19_HEALTH_CHECK_TIMEOUT for all inline checks (3 s, inside Docker’s 5 s)
Concurrency:      flock on /tmp/healthcheck.d.lock
Colors:           Auto (B19_COLOR=auto — plain text without a TTY)
Secrets:          Loaded explicitly (b19-load-secrets)
Disable all:      B19_HEALTH_ENABLED=false
Disable single:   B19_HEALTH_SKIP_<NAME>=true (or rename to *.disabled)
Tiers:            /healthcheck.d/hourly/ (B19_HEALTH_HOURLY_INTERVAL, detached)
Offgrid:          B19_OFFGRID_MODE=Y (skips egress checks)
Egress:           B19_HEALTH_EGRESS=true (opt in to the egress checks)
Drain:            touch $B19_HEALTH_DRAIN_FILE (default /tmp/b19-draining)
Restart:          B19_HEALTH_EXIT_AFTER=N (TERM to PID 1 after N failed probes)
Dockerfile:       HEALTHCHECK CMD ["healthcheck.d"] (inherited)
```

## See also

- [Use the runner family](use-runner-family.md) — the eight runners and their failure modes
- [Bound every step with timeouts](use-timeouts.md) — the other bounds, retries and the restart in context
- [Run offgrid builds](use-offgrid.md) — why the network checks go quiet
- [Test images with test.d](use-test.d.md) — the suite that waits for these checks to pass
- [Load secrets](use-secrets.md) — what the runner loads before your checks run
