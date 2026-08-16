<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Offgrid Mode and Cache Switches

Three ENV switches for controlling network access and caching tiers during builds and runtime.

## Variables

| Variable                 | Default  | Scope           | Description                                                          |
| ------------------------ | -------- | --------------- | -------------------------------------------------------------------- |
| `B19_OFFGRID_MODE`       | `N`      | build + runtime | Block all internet access; fail if a download would be required      |
| `B19_FETCH_LOCAL_CACHE`  | `Y`      | build           | Enable checking the `.fetch` build context before any network access |
| `B19_FETCH_DOCKER_CACHE` | `Y`      | build           | Enable checking the BuildKit disk cache before downloading           |
| `B19_FETCH_LOCAL_PATH`   | `/fetch` | build           | Mount path for the `.fetch` context (set by Dockerfile `--mount`)    |

All four have `ARG` defaults so they can also be overridden via `--build-arg` at build time.

## Three-Tier Fetch Model

`b19-fetch` checks caches in priority order and stops at the first hit:

```text
1. Local Cache  (B19_FETCH_LOCAL_PATH — bind-mount from .fetch/ build context)
2. Docker Cache (B19_DOWNLOAD_PATH   — BuildKit --mount=type=cache, persists across builds)
3. Download     (aria2c from internet — blocked when B19_OFFGRID_MODE=Y)
```

**Local cache HIT** copies the file directly to `B19_TEMP_PATH` and exits — it never writes to
the Docker Cache. This prevents "doubling" where the same file was previously promoted
from local cache → Docker Cache → temp.

**Hash validation** applies at both tiers: if `sha512` is provided, a mismatch on the local
cache file causes fallthrough to the next tier rather than a hard failure.

### Flow diagram

```text
b19-fetch TAG URL FILE [SHA512]
│
├─ B19_FETCH_LOCAL_CACHE=Y ?
│   └─ FILE in /fetch/ ?
│       ├─ hash match (or no hash) → copy to /tmp → EXIT 0
│       └─ hash mismatch           → log bad, fall through
│
├─ B19_FETCH_DOCKER_CACHE=Y ?
│   └─ FILE in B19_DOWNLOAD_PATH ?
│       ├─ hash match (or no hash) → DOWNLOAD=N
│       └─ hash mismatch           → DOWNLOAD=Y (re-download)
│
├─ B19_OFFGRID_MODE=Y && DOWNLOAD=Y → log error, EXIT 1
│
├─ DOWNLOAD=Y → aria2c ...
│
└─ copy B19_DOWNLOAD_PATH/FILE → B19_TEMP_PATH/FILE
```

## Offgrid Mode

`B19_OFFGRID_MODE=Y` cuts internet access at three points:

| Component           | Behavior                                                                             |
| ------------------- | ------------------------------------------------------------------------------------ |
| `b19-fetch`         | Exits 1 if a download would be required (caches must cover all files)                |
| `keyscan`           | Skips `ssh-keyscan`; relies on `.container/{stage}/app/.ssh/` pre-populated via COPY |
| `healthcheck.d/080` | Skips HTTPS connectivity check                                                       |
| `healthcheck.d/085` | Skips DNS resolution check                                                           |
| `healthcheck.d/090` | Skips ping connectivity check                                                        |

"Offgrid" is intentionally distinct from "offline" — it cuts internet, not all network
connections. LAN services (registry, APT cache proxy, near-cache) remain reachable.

## Use Cases

### Air-gapped rebuild

Pre-populate `.fetch/` with all expected binaries, then build with internet blocked:

```bash
# Ensure all files are in .fetch/ first
M6E_AI=Y make build B19_OFFGRID_MODE=Y
```

If any file is missing from cache, `b19-fetch` fails fast with a clear error.

### Force re-download (bypass Docker Cache)

```bash
B19_FETCH_DOCKER_CACHE=N M6E_AI=Y make build
```

aria2c still runs for every file. Useful when you suspect a corrupted Docker Cache.

### Force re-download (bypass both caches)

```bash
B19_FETCH_LOCAL_CACHE=N B19_FETCH_DOCKER_CACHE=N M6E_AI=Y make build
```

### Test offgrid healthchecks

```bash
docker run --rm -e B19_OFFGRID_MODE=Y <image> healthcheck.d
# All three network checks report "good" immediately
```

### Offgrid runtime container

```yaml
# docker-compose
environment:
  - B19_OFFGRID_MODE=Y
```

All three network healthchecks pass silently, keeping the container healthy on isolated networks.

## Populating the Local Cache

The local cache is a standard Docker build context stage named `fetch`. Files placed there
are available at build time via `--mount=type=bind,from=fetch,source=.,target=/fetch`.

The `.fetch/` directory in a project is gitignored. Populate it manually or via a CI
artifact step before running an offgrid build.

## APT Layer

`apt-get update` is wrapped by `update-apt` (`.container/foundation/tools.d/update-apt`), which
applies the same three-tier logic as `b19-fetch`:

1. **Local snapshot** — if `.fetch/apt-lists/` is non-empty, lists are copied into
    `/var/lib/apt/lists/` and `apt-get update` is skipped
1. **BuildKit cache** — if offgrid and no snapshot, existing cached lists are used (populated by a prior online build); `apt-get install` fails cleanly if cold
1. **Online** — `apt-get update --allow-releaseinfo-change` runs normally

Populate the local snapshot with `make copy-apt-lists` before an air-gapped build.
Remove with `make copy-apt-lists-clean`.

## Interaction with Near-Cache

`M6E_NEAR_CACHE_HOST` and `B19_OFFGRID_MODE` serve different purposes and can coexist:

- Near-cache rewrites URLs to a LAN proxy (still a network call)
- Offgrid mode blocks all downloads regardless of URL

For LAN-only builds that use a caching proxy, use `M6E_NEAR_CACHE_HOST` without
`B19_OFFGRID_MODE`. For true air-gapped builds, use `B19_OFFGRID_MODE=Y` with a
pre-populated `.fetch/` local cache.
