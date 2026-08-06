<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# B19 Deps System

Declarative external dependency management for Docker image builds.

Separates dependency metadata (URL, version, hash) from build logic (hook
scripts). The m6e build tool auto-discovers dependencies and generates
Makefile targets -- no manual declarations required.

## The Pipeline (end-to-end)

```text
.deps/ files in repo (version.deps, url.deps, hash.deps)
       |
       v
generate-deps.sh (runs at Makefile parse time)
       |
       v
.makefile/project/10-dependencies.mk  (auto-generated: fetch + hash targets)
       |
       v
make fetch  -->  fetch.sh downloads to .fetch/  -->  stamp files
       |
       v
update-hash.sh  -->  writes {arch}.hash.deps
       |
       v
Docker build: --build-context fetch=.fetch  -->  /fetch/ in container
       |
       v
COPY .container/{stage}/ /  -->  /deps/ in container
       |
       v
b19-resolve-dep reads /deps/{component}/  -->  outputs VERSION, URL, HASH, FILE
       |
       v
b19-fetch (3-tier cache: /fetch/ --> Docker cache --> aria2c + SHA-512)
       |
       v
Build hook extracts / installs the artifact
```

## Directory Layout

All deps live under `.container/{stage}/deps/{component}/`. A component is
any directory containing a `url.deps` or `{arch}.url.deps` file.

### Pattern A: Arch-specific (binaries, tarballs)

Single URL template with `${TARGETARCH}`, per-arch hash files:

```text
.container/{stage}/deps/{component}/
├── version.deps           # "1.26.2"
├── url.deps               # "https://.../go${M6E_UPSTREAM_VERSION}.linux-${TARGETARCH}.tar.gz"
├── amd64.hash.deps        # SHA-512 hex digest (no newline)
└── arm64.hash.deps        # SHA-512 hex digest (no newline)
```

Or separate URL per arch (when the URL structure differs per arch):

```text
.container/{stage}/deps/{component}/
├── version.deps           # "1.95.0"
├── amd64.url.deps         # URL template for amd64
├── arm64.url.deps         # URL template for arm64
├── amd64.hash.deps        # SHA-512 hex digest
└── arm64.hash.deps        # SHA-512 hex digest
```

### Pattern B: Arch-independent (GPG keys, config files)

No arch dimension at all:

```text
.container/{stage}/deps/{component}/
├── version.deps           # Revision marker (e.g. "1")
├── url.deps               # Static URL
└── hash.deps              # SHA-512 hex digest (single file)
```

### Pattern C: Series subdirectories (multi-version)

When a component ships multiple versions selected at build time (e.g. language
runtimes), each series gets its own subdirectory:

```text
.container/{stage}/deps/{component}/
├── url.deps               # Shared URL template (may use ${M6E_SERIES})
├── 3.4/
│   ├── version.deps       # "3.4.9"
│   └── hash.deps          # SHA-512 for 3.4
├── 4.0/
│   ├── version.deps       # "4.0.0"
│   └── hash.deps          # SHA-512 for 4.0
```

Series can also have arch-specific variants:

```text
.container/{stage}/deps/{component}/
├── 21/
│   ├── version.deps
│   ├── amd64.url.deps     # Series + arch specific URL
│   ├── arm64.url.deps
│   ├── amd64.hash.deps
│   └── arm64.hash.deps
├── 25/
│   └── ...
```

### Pattern D: Nested component paths

Component names can contain slashes for grouping:

```text
.container/{stage}/deps/extensions/
├── redis/
│   ├── version.deps
│   ├── url.deps
│   ├── hash.deps
│   └── install-redis.sh
├── xdebug/
│   ├── version.deps
│   ├── url.deps
│   └── hash.deps
```

Used via: `b19-resolve-dep extensions/redis`

## File Reference

| File               | Content                                                                            |
| ------------------ | ---------------------------------------------------------------------------------- |
| `version.deps`     | Plain version string. Bumping triggers re-fetch + hash update.                     |
| `url.deps`         | URL template. May use `${M6E_UPSTREAM_VERSION}`, `${TARGETARCH}`, `${M6E_SERIES}`. |
| `{arch}.url.deps`  | Arch-specific URL template (same variables).                                       |
| `{arch}.hash.deps` | SHA-512 hex digest (no trailing newline). One per architecture.                    |
| `hash.deps`        | SHA-512 hex digest for arch-independent components.                                |

URL templates are expanded via `envsubst`. Available variables:

- `${M6E_UPSTREAM_VERSION}` -- resolved version string
- `${TARGETARCH}` -- Docker target architecture (amd64, arm64, riscv64)
- `${M6E_SERIES}` -- series selector (when applicable)

Multi-line URL files are supported: each line is tried in order (mirror
fallback). empty lines are ignored.

## 4-Level Resolution Order

Both `b19-resolve-dep` and `fetch.sh` use the same fallback for finding
files (most specific wins):

1. `{component}/{series}/{arch}.file.deps`
1. `{component}/{series}/file.deps`
1. `{component}/{arch}.file.deps`
1. `{component}/file.deps`

Version files only use 2 levels (no arch dimension):

- `{component}/{series}/version.deps`
- `{component}/version.deps`

## Auto-Discovery (generate-deps.sh)

The file `.makefile/project/10-dependencies.mk` is auto-generated at Makefile
parse time by `m6e/common/scripts/generate-deps.sh`. It scans all
`.container/*/deps/*/` directories and emits Makefile rules for each
(component, arch, series) tuple.

**No manual PREREQUISITES declarations are needed.** Add files to the right
directory and the build tool picks them up automatically.

Three targets are generated per tuple:

```makefile
# 1. Fetch stamp -- downloads the file
$(FETCH_PATH)/.{leaf}.{version}.{arch}.stamp: {url_files} {version_file}
 M6E_DEPS_STAGE={stage} TARGETARCH={arch} fetch.sh {component}
 touch $@

# 2. Hash file -- computes SHA-512 from the fetched file
.container/{stage}/deps/{component}/{arch}.hash.deps: $(FETCH_PATH)/.{leaf}.{version}.{arch}.stamp
 M6E_DEPS_STAGE={stage} TARGETARCH={arch} update-hash.sh {component}

# 3. Prerequisite -- gates the Docker build
PREREQUISITES += .container/{stage}/deps/{component}/{arch}.hash.deps
```

The `PREREQUISITES` variable ensures all hashes are fresh before `docker build`
starts.

## b19-resolve-dep

Tool that resolves dependency metadata at build time (inside the container).
Defined at `.container/foundation/tools.d/b19-resolve-dep`.

### Usage

```bash
eval "$(b19-resolve-dep COMPONENT [ARCH])"
```

### Output Variables

| Variable               | Description                                          |
| ---------------------- | ---------------------------------------------------- |
| `M6E_UPSTREAM_VERSION` | Resolved version string                              |
| `M6E_UPSTREAM__URL`    | Resolved URL (envsubst-expanded)                     |
| `M6E_UPSTREAM__HASH`   | Resolved SHA-512 hash                                |
| `M6E_UPSTREAM__FILE`   | Fetch filename (`{leaf}.{version}[.{arch}][.{ext}]`) |

### Resolution

Reads from `B19_DEPS_PATH` (default `/deps`) inside the container. Uses the
4-level resolution order described above.

### Series Selection

Set `M6E_SERIES` before calling `b19-resolve-dep` to select a series
subdirectory:

```bash
M6E_SERIES="${B19_TOR_SERIES}"
eval "$(b19-resolve-dep tor)"
```

## b19-fetch

Downloads files with three-tier caching and SHA-512 verification.
Defined at `.container/foundation/tools.d/b19-fetch`.

### Fetch Usage

```bash
b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
```

### Cache Tiers (checked in order)

1. **Local cache** (`/fetch/`) -- bind-mounted from `.fetch/` build context. Populated by `make fetch`. HIT copies to `B19_TEMP_PATH` and exits.
1. **Docker cache** (`B19_DOWNLOAD_PATH`) -- BuildKit `--mount=type=cache`. Persists across builds on the same host.
1. **Upstream download** via `aria2c` with SHA-512 checksum. Blocked when
    `B19_OFFGRID_MODE=Y`.

If hash is empty string, no integrity check is performed (logged as warning).

The file lands in `${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}`. Move or install
from there.

See [b19-fetch.md](b19-fetch.md) for full reference.

## Hook Script Patterns

### Standard pattern (arch-dependent)

```bash
#!/usr/bin/env bash
. b19-i18n

eval "$(b19-resolve-dep {component} "${TARGETARCH}")"

b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"

# Extract or install from ${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}
tar --directory /usr/local --extract --strip-components=1 \
    --file "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}"
```

### Graceful skip for unsupported archs

```bash
resolved="$(b19-resolve-dep {component} "${TARGETARCH}" 2>/dev/null)" || {
    b19-log warn "TAG" "$(_p "No binary for %s, skipping" "${TARGETARCH}")"
    return 0
}
eval "${resolved}"
b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
```

### Series-based source download

```bash
M6E_SERIES="${B19_MY_SERIES}"
eval "$(b19-resolve-dep {component})"
b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
tar --extract --file "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}"
```

## Prefetch (make fetch)

```bash
make fetch
```

Scans all deps via the auto-generated `10-dependencies.mk`, downloads every
component into `.fetch/`, and writes stamp files. This populates b19-fetch
Tier 1 so the Docker build can run without network (`B19_OFFGRID_MODE=Y`).

Clean with `make fetch-clean`.

## How It Gets Into the Container

1. **Deps metadata**: `COPY .container/{stage}/ /` copies everything including
    `deps/` into the container. Lands at `/deps/` (set by `B19_DEPS_PATH`).

1. **Prefetched files**: `--build-context fetch=.fetch` makes `.fetch/` available as a build context. The Dockerfile mounts it:

```dockerfile
   RUN --mount=type=bind,from=fetch,source=.,target=/fetch build-stage {stage}
```

1. **Build hooks** in `build.d/{stage}/{pre,post}/` call `b19-resolve-dep` and `b19-fetch` to download/verify/extract artifacts.

## Workflow

### Adding a new dependency

1. Create directory `.container/{stage}/deps/{component}/`
1. Add `version.deps` and `url.deps` (and `{arch}.url.deps` if arch-specific)
1. Run `make fetch` -- downloads the file and computes hash files
1. Commit all files including the generated `{arch}.hash.deps` files
1. Write a build hook in `.container/{stage}/build.d/{stage}/{pre,post}/` using `b19-resolve-dep` + `b19-fetch`

### Updating a dependency version

1. Edit `.container/{stage}/deps/{component}/version.deps` (or `make set/{ns}/{proj}/{component}@{ver}` from repository root)
1. Run `make fetch` -- detects stale hash, re-downloads, updates hash file
1. Commit the updated `version.deps` and `{arch}.hash.deps` files

### Adding a new series to an existing component

1. Create `.container/{stage}/deps/{component}/{series}/`
1. Add `version.deps` (and optionally `url.deps`, `hash.deps` per arch)
1. Run `make fetch`
1. Commit

## Examples

### Binary tool (shared URL, arch-specific hashes)

```text
# .container/foundation/deps/fd/version.deps
10.4.2

# .container/foundation/deps/fd/url.deps
https://github.com/sharkdp/fd/releases/download/v${M6E_UPSTREAM_VERSION}/fd_${M6E_UPSTREAM_VERSION}_${TARGETARCH}.deb

# .container/foundation/deps/fd/amd64.hash.deps
1f6aba715b957335...
```

### Binary tool (arch-specific URLs)

```text
# .container/foundation/deps/mold/version.deps
2.41.0

# .container/foundation/deps/mold/amd64.url.deps
https://github.com/rui314/mold/releases/download/v${M6E_UPSTREAM_VERSION}/mold-${M6E_UPSTREAM_VERSION}-x86_64-linux.tar.gz

# .container/foundation/deps/mold/arm64.url.deps
https://github.com/rui314/mold/releases/download/v${M6E_UPSTREAM_VERSION}/mold-${M6E_UPSTREAM_VERSION}-aarch64-linux.tar.gz

# .container/foundation/deps/mold/amd64.hash.deps
86e838c3a253ee...
```

### GPG key (arch-independent)

```text
# .container/base/deps/llvm-key/version.deps
1

# .container/base/deps/llvm-key/url.deps
https://apt.llvm.org/llvm-snapshot.gpg.key

# .container/base/deps/llvm-key/hash.deps
66630ad43bb77a3b...
```

### Language runtime (series subdirectories)

```text
# .container/compile-gcc/deps/ruby/url.deps
https://cache.ruby-lang.org/pub/ruby/${M6E_SERIES}/ruby-${M6E_UPSTREAM_VERSION}.tar.xz

# .container/compile-gcc/deps/ruby/3.4/version.deps
3.4.9

# .container/compile-gcc/deps/ruby/3.4/hash.deps
356fb47cc56f...

# .container/compile-gcc/deps/ruby/4.0/version.deps
4.0.0

# .container/compile-gcc/deps/ruby/4.0/hash.deps
a1b2c3...
```

### Nested component (PHP extensions)

```text
# .container/compile-gcc/deps/extensions/redis/version.deps
6.2.0

# .container/compile-gcc/deps/extensions/redis/url.deps
https://pecl.php.net/get/redis-${M6E_UPSTREAM_VERSION}.tgz

# .container/compile-gcc/deps/extensions/redis/hash.deps
d4e5f6...
```

Access via: `b19-resolve-dep extensions/redis`

## Ancillary Deps Files

These live in `.container/{stage}/deps/` but are NOT processed by the
auto-discovery pipeline. They are read directly by build hooks:

| File              | Purpose                                                                            |
| ----------------- | ---------------------------------------------------------------------------------- |
| `common.apt.deps` | APT packages installed by `install-apt`. One per line, `name[=version] # comment`. |
| `volumes.deps`    | Dirs pre-created + chowned by `b19-prepare-volumes` (see [build.d](build.d.md)).   |
| `*.j2`            | Jinja2 templates for APT sources etc.                                              |
| `install-*.sh`    | Extension-specific install hooks (PHP extensions).                                 |
| `*.ini.j2`        | PHP extension config templates.                                                    |

## APT version pinning

Unlike fetched binaries (which pin via `version.deps`) APT packages float by
default: `install-apt` runs `apt-get install <name>` and `400-upgrade.sh`
dist-upgrades. To pin, write the version inline in the first token:

```text
curl=8.12.1-1ubuntu1           # transfer tool | deps: libcurl4t64
```

`install-apt` passes the `name=version` token straight to `apt-get`, so no
build change is needed. Avoid listing the same package both bare and pinned
(e.g. `curl` in `common.apt.deps` and `curl=...` in a release file) — apt would
be asked for it twice.

Pins are harvested from a built image rather than hand-written. The harvester
asks the image’s OWN apt — so extra repositories (Docker, llvm.org, ...) and apt
preferences are honored — for the candidate version of each listed package and
rewrites it in place, preserving the comment column:

- `make apt-pin` — resolve candidates and update `common.apt.deps`
- `make apt-pin-check` — fail (non-zero) if a pin drifted; no writes (lefthook/CI)

Overrides: `APT_PIN_IMAGE` (default `$(M6E_IMAGE_FULLNAME)`) and
`APT_PIN_SOURCE_FILE` (default: the `common.apt.deps` under any build stage).
The mechanism lives in m6e/container (`.makefile/container/workflow/apt-pin.mk` + `.makefile/container/scripts/apt-pin.sh`) so every container consumer gets
`make apt-pin` — the APT analogue of `npm-user-upgrade`.

## See Also

- [b19-fetch.md](b19-fetch.md) -- three-tier caching and SHA-512 verification
- [OFFGRID.md](OFFGRID.md) -- offline build support
- `m6e/common/scripts/generate-deps.sh` -- auto-discovery logic
- `m6e/common/scripts/fetch.sh` -- download logic
- `m6e/common/scripts/update-hash.sh` -- hash computation
- `.container/foundation/tools.d/b19-resolve-dep` -- in-container resolution
- `.container/foundation/tools.d/b19-fetch` -- in-container download
