<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Run offgrid builds

Four `ENV`/`ARG` switches decide whether a build or a running container may touch the internet at all, and which cache tiers it may read on the way. This is the air-gap story of the image — `b19-fetch` is the machinery, this article is the policy. The pitch: [offgrid mode](../features.d/offgrid.md).

## When to use

- Air-gapped rebuilds: everything needed sits in `.fetch/`, the network stays cut.
- Suspected cache corruption: bypass one or both tiers and re-download.
- Deploying to isolated networks: the runtime healthchecks must not fail just because the internet is unreachable.

## Quick start

```bash
# Air-gapped rebuild — .fetch/ must cover every file
M6E_AI=Y make build B19_OFFGRID_MODE=Y

# Runtime container on an isolated network
docker run --rm -e B19_OFFGRID_MODE=Y <image>
```

## How it works

### The switches

| Variable                 | Default  | Scope           | Description                                                          |
| ------------------------ | -------- | --------------- | -------------------------------------------------------------------- |
| `B19_OFFGRID_MODE`       | `N`      | build + runtime | Block all internet access; fail if a download would be required      |
| `B19_FETCH_LOCAL_CACHE`  | `Y`      | build           | Enable checking the `.fetch` build context before any network access |
| `B19_FETCH_DOCKER_CACHE` | `Y`      | build           | Enable checking the BuildKit disk cache before downloading           |
| `B19_FETCH_LOCAL_PATH`   | `/fetch` | build           | Mount path for the `.fetch` context (set by Dockerfile `--mount`)    |

All four have `ARG` defaults, so they can also be overridden via `--build-arg`.

### The three-tier model

`b19-fetch` checks caches in priority order and stops at the first hit:

```text
1. Local cache  (B19_FETCH_LOCAL_PATH — bind-mount from .fetch/ build context)
2. Docker cache (B19_DOWNLOAD_PATH   — BuildKit --mount=type=cache, persists across builds)
3. Download     (aria2c from internet — blocked when B19_OFFGRID_MODE=Y)
```

Tier mechanics, hash validation and the aria2c details live in [download files with b19-fetch](use-b19-fetch.md).

### Switch combinations

| Scenario                   | Tier 1       | Tier 2  | Download   |
| -------------------------- | ------------ | ------- | ---------- |
| Default (online)           | checked      | checked | if miss    |
| `.fetch` miss, Docker hit  | miss         | HIT     | skipped    |
| `.fetch` hit               | HIT (exit 0) | skipped | skipped    |
| `B19_FETCH_LOCAL_CACHE=N`  | skipped      | checked | if miss    |
| `B19_FETCH_DOCKER_CACHE=N` | checked      | skipped | if T1 miss |
| `B19_OFFGRID_MODE=Y`       | checked      | checked | blocked    |

### What offgrid actually cuts

`B19_OFFGRID_MODE=Y` cuts internet access at five points:

| Component           | Behavior                                                                             |
| ------------------- | ------------------------------------------------------------------------------------ |
| `b19-fetch`         | Exits 1 if a download would be required (caches must cover all files)                |
| `keyscan`           | Skips `ssh-keyscan`; relies on `.container/{stage}/app/.ssh/` pre-populated via COPY |
| `healthcheck.d/080` | Skips HTTPS connectivity check                                                       |
| `healthcheck.d/085` | Skips DNS resolution check                                                           |
| `healthcheck.d/090` | Skips ping connectivity check                                                        |

“Offgrid” is intentionally distinct from “offline” — it cuts internet, not all network connections. LAN services (registry, APT cache proxy, near-cache) remain reachable.

## Populating the local cache

The local cache is a standard Docker build-context stage named `fetch`. Files placed there are available at build time via `--mount=type=bind,from=fetch,source=.,target=/fetch`. The `.fetch/` directory in a project is gitignored — populate it manually or via a CI artifact step before running an offgrid build.

## The APT layer

`apt-get update` is wrapped by `update-apt` (`.container/foundation/tools.d/update-apt`), which applies the same three-tier logic as `b19-fetch`:

1. **Local snapshot** — if `.fetch/apt-lists/` is non-empty, lists are copied into `/var/lib/apt/lists/` and `apt-get update` is skipped
1. **BuildKit cache** — if offgrid and no snapshot, existing cached lists are used (populated by a prior online build); `apt-get install` fails cleanly if cold
1. **Online** — `apt-get update --allow-releaseinfo-change` runs normally

Populate the local snapshot with `make copy-apt-lists` before an air-gapped build; remove it with `make copy-apt-lists-clean`.

## Recipes

```bash
# Force re-download, bypassing the Docker cache
B19_FETCH_DOCKER_CACHE=N M6E_AI=Y make build

# Force re-download, bypassing both caches
B19_FETCH_LOCAL_CACHE=N B19_FETCH_DOCKER_CACHE=N M6E_AI=Y make build

# Exercise the offgrid healthcheck path
docker run --rm -e B19_OFFGRID_MODE=Y <image> healthcheck.d
# All three network checks report "good" immediately
```

```yaml
# docker-compose service on an isolated network
environment:
  - B19_OFFGRID_MODE=Y
```

### Near-cache and offgrid coexist

`M6E_NEAR_CACHE_HOST` and `B19_OFFGRID_MODE` serve different purposes:

- Near-cache rewrites URLs to a LAN proxy (still a network call).
- Offgrid mode blocks all downloads regardless of URL.

For LAN-only builds that use a caching proxy, use `M6E_NEAR_CACHE_HOST` without `B19_OFFGRID_MODE`. For true air-gapped builds, use `B19_OFFGRID_MODE=Y` with a pre-populated `.fetch/` local cache.

## See also

- [Download files with b19-fetch](use-b19-fetch.md) — the machinery these switches control
- [Write healthchecks](use-healthcheck.d.md) — the network checks that go quiet in offgrid mode
- [Configure the image environment](configure-environment.md) — every `B19_*` variable
