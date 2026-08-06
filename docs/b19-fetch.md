<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# b19-fetch

Download files with aria2c, three-tier caching, and SHA-512 verification.

## Usage

```bash
b19-fetch <tag> <url> <filename> [sha512]
```

## Arguments

| Argument   | Required | Description                             |
| ---------- | -------- | --------------------------------------- |
| `tag`      | yes      | Log tag for b19-log/b19-run messages    |
| `url`      | yes      | URL to download                         |
| `filename` | yes      | Output filename                         |
| `sha512`   | no       | SHA-512 hash for integrity verification |

## Cache Tiers

Caches are checked in priority order. The first hit wins.

### Tier 1: Local Cache (`.fetch` build context)

Checked when `B19_FETCH_LOCAL_CACHE=Y` (default). The `.fetch/` build context is mounted
read-only at `B19_FETCH_LOCAL_PATH` (default `/fetch`).

A local cache HIT copies the file directly to `B19_TEMP_PATH` and exits. It never writes
to the Docker Cache tier. Hash is validated if provided; mismatch falls through to tier 2.

### Tier 2: Docker Cache (`B19_DOWNLOAD_PATH`)

Checked when `B19_FETCH_DOCKER_CACHE=Y` (default). Files are stored in the BuildKit
`--mount=type=cache` volume, which persists across `docker build` invocations on the same
host.

A Docker Cache HIT sets `DOWNLOAD=N`. Hash is validated if provided; mismatch re-downloads.

### Tier 3: Download (aria2c)

Runs when both tiers miss or are disabled. Blocked entirely when `B19_OFFGRID_MODE=Y`
(exits 1 with an error if a download would be required).

Downloaded files are stored in `B19_DOWNLOAD_PATH` (populates Tier 2 for future builds)
then copied to `B19_TEMP_PATH`.

## Cache Switch Summary

| Scenario                   | Tier 1       | Tier 2  | Download   |
| -------------------------- | ------------ | ------- | ---------- |
| Default (online)           | checked      | checked | if miss    |
| `.fetch` miss, Docker hit  | miss         | HIT     | skipped    |
| `.fetch` hit               | HIT (exit 0) | skipped | skipped    |
| `B19_FETCH_LOCAL_CACHE=N`  | skipped      | checked | if miss    |
| `B19_FETCH_DOCKER_CACHE=N` | checked      | skipped | if T1 miss |
| `B19_OFFGRID_MODE=Y`       | checked      | checked | blocked    |

## Near-Cache Proxy

When `M6E_NEAR_CACHE_HOST` is set, URLs are rewritten to route through the proxy:

```text
https://example.com/file.tar.gz
-> https://{M6E_NEAR_CACHE_HOST}/example.com/file.tar.gz
```

Used with caching proxies (e.g., squid) to reduce external downloads in CI.

### Trusting a near cache behind private TLS

A near cache fronted by a private root (a self-signed reverse proxy on the build
LAN) is not trusted by the image’s stock CA store, and the failure reads as
`SSL/TLS handshake failure: not signed by known authorities` on the download —
not as a certificate problem at the place you set the proxy.

Set `M6E_CA_CERTIFICATES` on the **build host** to the path of a complete CA
bundle, normally `/etc/ssl/certs/ca-certificates.crt`. The m6e build backends
stage that bundle into the `fetch` build context, where it arrives as
`B19_BUILD_CA_FILE`, and from there:

- the stage-independent hooks `always/pre/010` and `always/post/950` install it
    through [`trust-ca-certificates`](build.d.md) and drop it again before the
    layer commits, so every root stage of every image is covered and none ships
    it;
- non-root stages leave the trust store alone (uid 1000 cannot write it), so
    `b19-fetch` hands the bundle to aria2c directly via `--ca-certificate`.

Because aria2c’s `--ca-certificate` *replaces* the default store rather than
adding to it, `M6E_CA_CERTIFICATES` must name a full bundle — a lone extra root
would leave the user stage unable to verify anything else.

Unset (the CI and published-image default) means nothing is staged and the image
trust store is used untouched.

## aria2c Options

- Conditional GET and resume support
- Up to 16 connections per server (aria2c’s maximum)
- gzip acceptance
- File allocation via fallocate

## Environment

| Variable                  | Default          | Description                                    |
| ------------------------- | ---------------- | ---------------------------------------------- |
| `B19_FETCH_LOCAL_CACHE`   | `Y`              | Enable local cache tier (`.fetch` context)     |
| `B19_FETCH_DOCKER_CACHE`  | `Y`              | Enable Docker Cache tier (`B19_DOWNLOAD_PATH`) |
| `B19_FETCH_LOCAL_PATH`    | `/fetch`         | Mount path for the local cache context         |
| `B19_OFFGRID_MODE`        | `N`              | Block downloads; fail if download required     |
| `B19_DOWNLOAD_PATH`       | `/app/.download` | Docker Cache directory                         |
| `B19_DOWNLOAD_DISK_CACHE` | `64m`            | aria2c disk cache size                         |
| `B19_DOWNLOAD_MAX_TRIES`  | `4`              | Maximum retry attempts                         |
| `B19_DOWNLOAD_RETRY_WAIT` | `16`             | Seconds between retries                        |
| `M6E_NEAR_CACHE_HOST`     | (unset)          | Near-cache proxy hostname                      |
| `B19_BUILD_CA_FILE`       | (staged)         | Build-host CA bundle in the fetch context      |
| `B19_TEMP_PATH`           | `/tmp`           | Destination for the final file copy            |

See [OFFGRID.md](OFFGRID.md) for the full offgrid/cache-switch reference.

## Examples

```bash
# Download with checksum verification
b19-fetch "NODE" \
  "https://nodejs.org/dist/v22.0.0/node-v22.0.0-linux-x64.tar.xz" \
  "node-v22.0.0.tar.xz" \
  "abc123...def456"

# Download without checksum (ASSUMED HIT on subsequent builds)
b19-fetch "TOOL" \
  "https://github.com/example/tool/releases/download/v1.0/tool.tar.gz" \
  "tool-1.0.tar.gz"

# With near-cache proxy
M6E_NEAR_CACHE_HOST=cache.local b19-fetch "PKG" \
  "https://registry.npmjs.org/package/-/package-1.0.tgz" \
  "package-1.0.tgz"

# Force re-download, bypass Docker Cache
B19_FETCH_DOCKER_CACHE=N b19-fetch "TOOL" \
  "https://example.com/tool.tar.gz" \
  "tool.tar.gz" \
  "sha512hash..."
```
