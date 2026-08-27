<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Download files with b19-fetch

`b19-fetch` is the build-time downloader: aria2c underneath, a three-tier cache in front, SHA-512 verification on everything it touches. A pinned dependency downloads once per host and never again. The pitch: [cached artifact downloads with integrity verification](../features.d/b19-fetch.md).

## When to use

- Build hooks fetching pinned binaries, tarballs or language toolchains.
- Any download that must be reproducible offline — the cache tiers are what make [offgrid builds](use-offgrid.md) possible.

## Quick start

```bash
b19-fetch "NODE" \
  "https://nodejs.org/dist/v22.0.0/node-v22.0.0-linux-x64.tar.xz" \
  "node-v22.0.0.tar.xz" \
  "abc123...def456"
```

## How it works

```bash
b19-fetch <tag> <url> <filename> [sha512]
```

| Argument   | Required | Description                             |
| ---------- | -------- | --------------------------------------- |
| `tag`      | yes      | Log tag for b19-log/b19-run messages    |
| `url`      | yes      | URL to download                         |
| `filename` | yes      | Output filename                         |
| `sha512`   | no       | SHA-512 hash for integrity verification |

Caches are checked in priority order; the first hit wins.

### Tier 1 — local cache (`.fetch` build context)

Checked when `B19_FETCH_LOCAL_CACHE=Y` (default). The `.fetch/` build context is mounted read-only at `B19_FETCH_LOCAL_PATH` (default `/fetch`). A hit copies the file directly to `B19_TEMP_PATH` and exits — it never writes to the Docker cache tier, which prevents “doubling” a file through both caches. The hash is validated when provided; a mismatch falls through to tier 2 instead of failing.

### Tier 2 — Docker cache (`B19_DOWNLOAD_PATH`)

Checked when `B19_FETCH_DOCKER_CACHE=Y` (default). Files live in a BuildKit `--mount=type=cache` volume, which persists across `docker build` invocations on the same host. A hit sets `DOWNLOAD=N`; a hash mismatch re-downloads.

### Tier 3 — download (aria2c)

Runs when both tiers miss or are disabled. Blocked entirely when `B19_OFFGRID_MODE=Y`: the tool exits 1 with an error instead of touching the network. Downloaded files are stored in `B19_DOWNLOAD_PATH` (populating tier 2 for future builds), then copied to `B19_TEMP_PATH`.

aria2c runs with conditional GET and resume support, up to 16 connections per server (its maximum), gzip acceptance and `fallocate` allocation.

### Near-cache proxy

When `M6E_NEAR_CACHE_HOST` is set, URLs are rewritten to route through the proxy — a caching proxy (e.g. squid) on the LAN that reduces external downloads in CI:

```text
https://example.com/file.tar.gz
-> https://{M6E_NEAR_CACHE_HOST}/example.com/file.tar.gz
```

Before rewriting, `b19-fetch` probes the near cache with `check-reachable` — the same short cURL connect `detect-apt-cacher` uses for the LAN apt proxy. A near cache that is set but unreachable is treated as transient: the rewrite is skipped, the original URLs are used, and aria2c downloads straight from the origin instead of retrying against a proxy that never answers. Set `B19_CACHE_CHECK_ENABLED=false` to skip the probe and always route through the configured host.

#### Trusting a near cache behind private TLS

A near cache fronted by a private root (a self-signed reverse proxy on the build LAN) is not trusted by the image’s stock CA store, and the failure reads as `SSL/TLS handshake failure: not signed by known authorities` on the download — not as a certificate problem at the place you set the proxy.

Set `M6E_CA_CERTIFICATES` on the **build host** to the path of a complete CA bundle, normally `/etc/ssl/certs/ca-certificates.crt`. The m6e build backends stage that bundle into the `fetch` build context, where it arrives as `B19_BUILD_CA_FILE`, and from there:

- the stage-independent hooks `always/pre/010` and `always/post/950` install it through [`trust-ca-certificates`](use-build.d.md) and drop it again before the layer commits, so every root stage of every image is covered and none ships it;
- non-root stages leave the trust store alone (uid 1000 cannot write it), so `b19-fetch` hands the bundle to aria2c directly via `--ca-certificate`.

Because aria2c’s `--ca-certificate` *replaces* the default store rather than adding to it, `M6E_CA_CERTIFICATES` must name a full bundle — a lone extra root would leave the user stage unable to verify anything else. Unset (the CI and published-image default) means nothing is staged and the image trust store is used untouched.

## Configuration

| Variable                  | Default                   | Description                                    |
| ------------------------- | ------------------------- | ---------------------------------------------- |
| `B19_FETCH_LOCAL_CACHE`   | `Y`                       | Enable local cache tier (`.fetch` context)     |
| `B19_FETCH_DOCKER_CACHE`  | `Y`                       | Enable Docker cache tier (`B19_DOWNLOAD_PATH`) |
| `B19_FETCH_LOCAL_PATH`    | `/fetch`                  | Mount path for the local cache context         |
| `B19_OFFGRID_MODE`        | `N`                       | Block downloads; fail if download required     |
| `B19_DOWNLOAD_PATH`       | `/var/cache/b19/download` | Docker cache directory                         |
| `B19_DOWNLOAD_DISK_CACHE` | `64m`                     | aria2c disk cache size                         |
| `B19_DOWNLOAD_MAX_TRIES`  | `4`                       | Maximum retry attempts                         |
| `B19_DOWNLOAD_RETRY_WAIT` | `16`                      | Seconds between retries                        |
| `M6E_NEAR_CACHE_HOST`     | (unset)                   | Near-cache proxy hostname                      |
| `B19_BUILD_CA_FILE`       | (staged)                  | Build-host CA bundle in the fetch context      |
| `B19_TEMP_PATH`           | `/tmp`                    | Destination for the final file copy            |
| `B19_CACHE_CHECK_ENABLED` | `true`                    | Probe the near cache before routing through it |
| `B19_CACHE_CHECK_TIMEOUT` | `2`                       | Seconds to wait for the reachability probe     |

What each switch combination does — and the air-gap scenarios they serve — is the subject of [run offgrid builds](use-offgrid.md). The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```bash
# Download without checksum — ASSUMED HIT on subsequent builds
b19-fetch "TOOL" \
  "https://github.com/example/tool/releases/download/v1.0/tool.tar.gz" \
  "tool-1.0.tar.gz"

# Through a near-cache proxy
M6E_NEAR_CACHE_HOST=cache.local b19-fetch "PKG" \
  "https://registry.npmjs.org/package/-/package-1.0.tgz" \
  "package-1.0.tgz"

# Force re-download, bypassing the Docker cache (suspected corruption)
B19_FETCH_DOCKER_CACHE=N b19-fetch "TOOL" \
  "https://example.com/tool.tar.gz" \
  "tool.tar.gz" \
  "sha512hash..."
```

## See also

- [Run offgrid builds](use-offgrid.md) — the cache switches, air-gap scenarios and the APT layer
- [Declare dependencies](use-dependencies.md) — `*.deps` files generate the fetch calls for you
- [Use build hooks](use-build.d.md) — where `trust-ca-certificates` sits in the hook chain
