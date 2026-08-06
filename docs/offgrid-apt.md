<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Offgrid APT Audit

Inventory of all network-connected operations in b19/Ubuntu, with their current
offgrid status and recommended bypass solutions.

## TL;DR — Gaps (Fixed)

Two build-time operations had **no `B19_OFFGRID_MODE` guard** — both are now fixed:

| File                                                           | Operation              | Status          |
| -------------------------------------------------------------- | ---------------------- | --------------- |
| `.container/foundation/tools.d/install-apt`                    | `apt-get update`       | Fixed — guarded |
| `.container/foundation/build.d/foundation/post/400-upgrade.sh` | `apt-get dist-upgrade` | Fixed — guarded |

All other network operations are either already guarded or delegate to `b19-fetch`
(which has a correct offgrid guard).

______________________________________________________________________

## Full Inventory

Execution follows two `build-stage` calls (Dockerfile lines 94–106):

1. `build-stage ubuntu` — root user, processes pre-hooks → `install-apt` → post-hooks
1. `build-stage user` — non-root user, processes pre/post hooks only

### Stage 1: Ubuntu / pre-hooks

| Hook                                              | Tool                                     | Network?                                                                           | Offgrid status |
| ------------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------- | -------------- |
| `ubuntu/pre/100-detect-apt-cacher.sh`             | `detect-apt-cacher`                      | Config only; writes `/etc/apt/apt.conf.d/99proxy` when `M6E_APT_CACHE_HOST` is set | N/A — no call  |
| `ubuntu/pre/100-enable-buildkit-cache-for-apt.sh` | removes `docker-clean`                   | No                                                                                 | N/A            |
| `ubuntu/pre/200-setup-sources.sh`                 | `sed` substitution into sources template | No — writes config only                                                            | N/A            |

### Stage 1: `install-apt` (root only)

Called unconditionally by `build-stage` when running as root.

| Operation         | Line  | Network?                                           | Offgrid status                                                  |
| ----------------- | ----- | -------------------------------------------------- | --------------------------------------------------------------- |
| `apt-get update`  | 42–44 | Yes — fetches package index from configured mirror | **Fixed — guarded**                                             |
| `apt-get install` | 48–54 | Yes — downloads packages                           | Fails anyway if `update` is skipped or lists absent; acceptable |

### Stage 1: Ubuntu / post-hooks

| Hook                                     | Tool                     | Network?                     | Offgrid status       |
| ---------------------------------------- | ------------------------ | ---------------------------- | -------------------- |
| `ubuntu/pre/050-restore-translations.sh` | `rm` (excludes file)     | No                           | N/A                  |
| `ubuntu/post/100-update-certificates.sh` | `update-ca-certificates` | No -- reads local filesystem | N/A                  |
| `ubuntu/post/150-compile-i18n.sh`        | `b19-compile-i18n`       | No                           | N/A                  |
| `ubuntu/post/200-permissions.sh`         | `chown`/`chmod`          | No                           | N/A                  |
| `ubuntu/post/300-install-fd.sh`          | `b19-fetch`              | Yes                          | **Handled**          |
| `ubuntu/post/300-install-mold.sh`        | `b19-fetch`              | Yes                          | **Handled**          |
| `ubuntu/post/350-switch-to-mold.sh`      | `ln`                     | No                           | N/A                  |
| `ubuntu/post/400-upgrade.sh`             | `apt-get dist-upgrade`   | Yes                          | **Fixed -- guarded** |
| `ubuntu/post/600-create-user-group.sh`   | `useradd`/`groupadd`     | No                           | N/A                  |
| `ubuntu/post/650-setup-shell-hooks.sh`   | `bashrc` append          | No                           | N/A                  |
| `ubuntu/post/820-save-j2.sh`             | `save-j2`                | No                           | N/A                  |
| `ubuntu/post/900-cleanup.sh`             | `rm`                     | No                           | N/A                  |

### Stage 2: user / pre-hooks

| Hook                             | Tool           | Network? | Offgrid status |
| -------------------------------- | -------------- | -------- | -------------- |
| `user/pre/200-read-lineage.i.sh` | `read-lineage` | No       | N/A            |

### Shared hooks (used by derived images, not Ubuntu itself)

| Hook                                  | Tool                | Offgrid status     |
| ------------------------------------- | ------------------- | ------------------ |
| `base/pre/100-detect-apt-cacher.i.sh` | `detect-apt-cacher` | N/A -- config only |
| `root/pre/100-detect-apt-cacher.i.sh` | `detect-apt-cacher` | N/A -- config only |

### Opt-in scripts (called by downstream images)

| Script                    | Operation                                                                    | Offgrid status                             |
| ------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------ |
| `setup-docker-repository` | `b19-fetch` for Docker GPG key                                               | **Handled** by `b19-fetch`                 |
| `setup-docker-repository` | adds `docker.sources` — triggers `apt-get update` on next `install-apt` call | **Fixed** — covered by `install-apt` guard |
| `add-user-to-docker`      | `groupadd`, `adduser`                                                        | N/A — local                                |
| `setup-pass-with-docker`  | `gpg2 --gen-key`, `pass init`                                                | N/A — local                                |

### Runtime healthchecks

| Script                            | Operation                           | Offgrid status |
| --------------------------------- | ----------------------------------- | -------------- |
| `080-check-https-connectivity.sh` | `curl` to `B19_HEALTH_NETWORK_URL`  | **Handled**    |
| `085-check-dns-resolution.sh`     | `getent hosts`                      | **Handled**    |
| `090-check-ping-connectivity.sh`  | `ping` to `B19_HEALTH_PING_TARGETS` | **Handled**    |

______________________________________________________________________

## APT Layer — How It Works

The build uses two BuildKit caches for APT (Dockerfile lines 96–97):

```text
--mount=type=cache,id=apt-cache-${B19_UBUNTU_SERIES},target=/var/cache/apt,sharing=shared   # .deb package files
--mount=type=cache,id=apt-lists-${B19_UBUNTU_SERIES},target=/var/lib/apt,sharing=shared                                                  # package index lists
```

`sharing=locked` prevents concurrent build access but **does** persist state across
sequential builds. A warm cache from a previous online build leaves package lists in
`/var/lib/apt/lists/` and debs in `/var/cache/apt/archives/`.

This is the foundation for all APT bypass strategies.

______________________________________________________________________

## Bypass Solutions

### 1. Guard `apt-get update` in `install-apt`

**Where**: `.container/foundation/tools.d/install-apt`, around line 42

**Change**: Wrap the `apt-get update` call:

```sh
if [ "${B19_OFFGRID_MODE:-N}" = "Y" ]; then
  b19-log good "PACKAGES" "$(_ "Offgrid mode, skipping apt-get update")"
else
  b19-run "PACKAGES" "$(_ "Update lists")"  \
    apt-get update --allow-releaseinfo-change
fi
```

**Requirement**: The BuildKit apt cache must have been warmed by a prior online build.
If the lists are missing, `apt-get install` will fail with a clear error.

### 2. Guard `apt-get dist-upgrade` in `400-upgrade.sh`

**Where**: `.container/foundation/build.d/foundation/post/400-upgrade.sh`

**Change**:

```sh
if [ "${B19_OFFGRID_MODE:-N}" = "Y" ]; then
  b19-log good "PACKAGES" "$(_ "Offgrid mode, skipping dist-upgrade")"
else
  b19-run "PACKAGES" "$(_ "Upgrade all packages")" apt-get dist-upgrade -y
fi
```

**Rationale**: In true offgrid mode, upgrading to network-fetched packages is
impossible anyway. The base image is pinned by hash in the Dockerfile `FROM` line,
so the starting point is already deterministic.

### 3. APT lists snapshot via Makefile target + `update-apt` script

`update-apt` (`.container/foundation/tools.d/update-apt`) is the single entry point for all APT
index operations. It replaces the direct `apt-get update` call in `install-apt`.

**Priority order** (mirrors `b19-fetch` three-tier model):

1. `${B19_FETCH_LOCAL_PATH}/apt-lists/` exists and non-empty → copy into `/var/lib/apt/lists/`, skip update
1. `B19_OFFGRID_MODE=Y` (no local lists) → skip (BuildKit cache lists remain; `apt-get install` uses them or fails)
1. Online → `apt-get update --allow-releaseinfo-change`

**Makefile target** (`.makefile/project/20-offgrid.mk`):

```bash
make copy-apt-lists        # copy /var/lib/apt/lists/ → .fetch/apt-lists/
make copy-apt-lists-clean  # rm -rf .fetch/apt-lists/
```

**Constraint**: The snapshot must be taken from a host running the same Ubuntu release
and mirror as `B19_UBUNTU_MIRROR_*`. List filenames embed the codename
(e.g., `archive.ubuntu.com_ubuntu_dists_noble_Release`), so mismatches are visible at
`apt-get install` time.

______________________________________________________________________

## Implementation Status

| Item                             | Status |
| -------------------------------- | ------ |
| Guard `400-upgrade.sh`           | Done   |
| Introduce `update-apt` script    | Done   |
| `install-apt` calls `update-apt` | Done   |
| `copy-apt-lists` Makefile target | Done   |

______________________________________________________________________

## Interaction Matrix

| Scenario                      | `B19_OFFGRID_MODE` | `M6E_APT_CACHE_HOST` | BuildKit cache warm | Result after fix                     |
| ----------------------------- | ------------------ | -------------------- | ------------------- | ------------------------------------ |
| Normal online build           | N                  | —                    | —                   | Full update + upgrade ✓              |
| LAN build with apt-cacher     | N                  | set                  | —                   | Proxy handles apt traffic ✓          |
| Repeat build (warm cache)     | Y                  | —                    | Yes                 | Skips update, installs from cache ✓  |
| Air-gapped + snapshot         | Y                  | —                    | —                   | Injects snapshot, installs from it ✓ |
| Cold air-gapped (no snapshot) | Y                  | —                    | No                  | `apt-get install` fails — expected ✓ |
