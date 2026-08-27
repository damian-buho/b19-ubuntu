<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Use the APT cache

APT state survives across builds: downloaded `.deb` archives and package indices live in BuildKit cache mounts, so the second build of an image installs from warm caches instead of re-downloading the internet. An optional LAN cacher proxy rides the same path. The pitch: [persistent APT cache](../features.d/apt-cache.md).

## When to use

- Every build: the cache mounts come with the inherited `build-stage` pattern — carrying them into your own `RUN` lines is the whole integration.
- CI or LAN fleets: add `M6E_APT_CACHE_HOST` to route apt through a caching proxy.

## Quick start

```dockerfile
# Your stage’s RUN line carries the two cache mounts (scaffold pattern):
RUN --mount=type=cache,id=apt-cache-${B19_UBUNTU_SERIES}-${TARGETARCH},target=/var/cache/apt,sharing=shared \
    --mount=type=cache,id=apt-lists-${B19_UBUNTU_SERIES}-${TARGETARCH},target=/var/lib/apt,sharing=shared \
    build-stage base
```

## How it works

Two BuildKit `--mount=type=cache` mounts persist APT state: `/var/cache/apt` (archives) and `/var/lib/apt` (lists). The base image keys both cache IDs by Ubuntu series and architecture (`apt-cache-${B19_UBUNTU_SERIES}-${TARGETARCH}`), so parallel builds of different series never poison each other’s caches. `/etc/apt/apt.conf.d/docker-clean` — which normally deletes archives after every apt run — is removed during the foundation stage so packages persist.

Concurrent builds coordinate through lockfiles inside the shared mounts: `update-apt` wraps `apt-get update` in `flock -w 600 /var/lib/apt/.buildkit-lock`, and `install-apt` wraps `apt-get install` in `flock -w 600 /var/cache/apt/.buildkit-lock`.

The lists mount is shared by every project of a series, so `update-apt` passes `--option APT::Get::List-Cleanup=false`: by default `apt-get update` deletes list files no source of *this* build declares, which is every list a concurrently building project fetched from its own repository. A project that adds a repository whose suite name varies per build (`b19/llvm`, one apt suite per LLVM series) MUST also carry that variable in its lists cache ID, so its key describes its content.

Performance tuning (parallel queues, 30s timeouts) ships in `.container/foundation/etc/apt/apt.conf.d/90optimizations.conf`.

### The LAN cacher proxy

Setting `M6E_APT_CACHE_HOST` (build arg) enables the proxy path: `always/pre/020-detect-apt-cacher.i.sh` writes `/etc/apt/apt.conf.d/99proxy` pointing at `http://${M6E_APT_CACHE_HOST}:${M6E_APT_CACHE_PORT:-3142}` (the apt-cacher-ng default port), and `always/post/900-clean-apt-cacher.i.sh` removes it again — both run on every `build-stage` call whatever the stage is called (see [use-build.d](use-build.d.md)), so the proxy config never ships in a layer, and never reaches a runtime container either. “Detection” is exactly this: set the host, the hook acts; unset, it does nothing. `detect-apt-cacher` checks `id --user` itself and no-ops for the uid-1000 user stage, since `/etc/apt/apt.conf.d` is root-owned.

Before writing the proxy config, `detect-apt-cacher` probes the cache host with `check-reachable` (a short cURL connect, `B19_CACHE_CHECK_TIMEOUT` seconds, one retry). A host that is set but unreachable — a stuck cacher-ng, a LAN outage — is treated as a transient condition: the proxy is skipped, apt falls through to a direct connection, and the build keeps going instead of failing deep inside `apt-get` once it can’t reach a proxy that was never there. Set `B19_CACHE_CHECK_ENABLED=false` to skip the probe and always trust the configured host.

## Configuration

| Variable                  | Default | Effect                                        |
| ------------------------- | ------- | --------------------------------------------- |
| `M6E_APT_CACHE_HOST`      | (unset) | LAN cacher hostname; empty disables the proxy |
| `M6E_APT_CACHE_PORT`      | `3142`  | LAN cacher port                               |
| `B19_CACHE_CHECK_ENABLED` | `true`  | Probe the cache host before trusting it       |
| `B19_CACHE_CHECK_TIMEOUT` | `2`     | Seconds to wait for the reachability probe    |

Packages themselves are declared in `common.apt.deps` files — see [declare dependencies](use-dependencies.md).

## Recipes

```yaml
# CI / compose wiring
env:
  M6E_APT_CACHE_HOST: apt-cacher.internal
```

```bash
# Offgrid: snapshot host APT lists into .fetch/apt-lists before the build
make copy-apt-lists        # consumed by update-apt in tier-1 fashion
make copy-apt-lists-clean  # drop the snapshot
```

The offgrid snapshot path is covered in [run offgrid builds](use-offgrid.md).

## See also

- [Declare dependencies](use-dependencies.md) — `common.apt.deps` and version pinning
- [Run offgrid builds](use-offgrid.md) — the APT tier model
- [Build images with build.d hooks](use-build.d.md) — where the cache mounts ride
