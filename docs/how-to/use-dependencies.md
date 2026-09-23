<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Declare dependencies

Dependencies are data, not code: a component directory under `deps/` holds its version, URL template and SHA-512 hashes, and the build auto-discovers it, generates the fetch targets and verifies every download. Adding a dependency means adding files — never editing a Makefile. The pitch: [declarative dependency management](../features.d/dependencies.md).

## When to use

- Any external artifact a build hook installs: binary tools, language runtimes, GPG keys.
- APT package lists, which ride the same tree as `common.apt.deps` files.

## Quick start

```text
.container/foundation/deps/fd/version.deps
10.4.2

.container/foundation/deps/fd/url.deps
https://github.com/sharkdp/fd/releases/download/v${M6E_UPSTREAM_VERSION}/fd_${M6E_UPSTREAM_VERSION}_${TARGETARCH}.deb
```

```bash
make fetch        # downloads, writes amd64.hash.deps / arm64.hash.deps
git add .container/foundation/deps/fd
```

Then a build hook consumes it:

```bash
eval "$(b19-resolve-dep fd "${TARGETARCH}")"
b19-fetch "FD" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
```

## How it works

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

All deps live under `.container/{stage}/deps/{component}/`; a component is any directory containing a `url.deps` or `{arch}.url.deps` file. `.makefile/project/10-dependencies.mk` is generated at Makefile parse time by `m6e/common/scripts/generate-deps.sh`, which scans every `.container/*/deps/*/` and emits three targets per (component, arch, series) tuple — a fetch stamp, a hash file, and a `PREREQUISITES` entry that gates `docker build` on fresh hashes. **No manual declarations are needed.**

### File reference

| File               | Content                                                                            |
| ------------------ | ---------------------------------------------------------------------------------- |
| `version.deps`     | Plain version string. Bumping triggers re-fetch + hash update.                     |
| `url.deps`         | URL template. May use `${M6E_UPSTREAM_VERSION}`, `${TARGETARCH}`, `${M6E_SERIES}`. |
| `{arch}.url.deps`  | Arch-specific URL template (same variables).                                       |
| `{arch}.hash.deps` | SHA-512 hex digest (no trailing newline). One per architecture.                    |
| `hash.deps`        | SHA-512 hex digest for arch-independent components.                                |

A `url.deps` whose line starts with `git+` declares a repository instead of a
file — see [Git sources](#git-sources).

URL templates are `envsubst`-expanded; `${TARGETARCH}` is `amd64`, `arm64` or `riscv64`. Multi-line URL files are supported — each line is tried in order (mirror fallback), empty lines ignored.

### Directory patterns

**Arch-specific** (binaries, tarballs) — one URL template plus per-arch hashes, or per-arch URLs when the naming differs:

```text
deps/{component}/            deps/{component}/
├── version.deps             ├──── version.deps
├── url.deps    (${TARGETARCH} in the template)
├── amd64.hash.deps          ├──── amd64.url.deps
└── arm64.hash.deps          ├──── arm64.url.deps
                             ├──── amd64.hash.deps
                             └── arm64.hash.deps
```

**Arch-independent** (GPG keys, config files): `version.deps` + `url.deps` + `hash.deps`, no arch dimension.

**Series subdirectories** (multi-version components, e.g. language runtimes selected at build time):

```text
deps/{component}/
├── url.deps               # shared template, may use ${M6E_SERIES}
├── 3.4/
│   ├── version.deps       # "3.4.9"
│   └── hash.deps
└── 4.0/
    ├── version.deps       # "4.0.0"
    └── hash.deps
```

Series directories can carry their own arch-specific `url`/`hash` files.

**Nested component paths** for grouping (PHP extensions): `deps/extensions/redis/`, resolved as `b19-resolve-dep extensions/redis`.

### Git sources

Some upstreams publish no artifact at all — the release is a tag in a
repository. Declare the transport in `url.deps` as `git+<url>#<ref>`, where the
ref is the tag the build clones:

```text
deps/radicle/version.deps
1.10.1

deps/radicle/url.deps
git+https://seed.radicle.garden/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git#releases/${M6E_UPSTREAM_VERSION}
```

There is no file to download, so such a component carries **no `hash.deps`** —
the ref is the pin. `make fetch` still runs: it resolves the ref to a commit and
caches it, so a version nobody published fails within the second rather than
after a full compile. The hook clones what was declared:

```bash
eval "$(b19-resolve-dep radicle "${TARGETARCH}")"
git clone --depth 1 --branch "${M6E_UPSTREAM__REF}" "${M6E_UPSTREAM__URL}" src/heartwood
```

`M6E_UPSTREAM__URL` is the URL with the `git+` prefix and the fragment removed,
`M6E_UPSTREAM__REF` the fragment, `M6E_UPSTREAM__HASH` empty. Reach for this
only when there is genuinely nothing to fetch: a tarball keeps its SHA-512
verification, a clone trusts the remote.

### Resolution order

Both `b19-resolve-dep` and `fetch.sh` fall back most-specific-wins:

1. `{component}/{series}/{arch}.file.deps`
1. `{component}/{series}/file.deps`
1. `{component}/{arch}.file.deps`
1. `{component}/file.deps`

Version files use two levels only (no arch dimension): `{component}/{series}/version.deps`, then `{component}/version.deps`.

### b19-resolve-dep

```bash
eval "$(b19-resolve-dep COMPONENT [ARCH])"
```

Sets `M6E_UPSTREAM_VERSION`, `M6E_UPSTREAM__URL` (envsubst-expanded), `M6E_UPSTREAM__HASH`, `M6E_UPSTREAM__FILE` (`{leaf}.{version}[.{arch}][.{ext}]`) and `M6E_UPSTREAM__REF` (Git sources only), reading from `B19_DEPS_PATH` (default `/deps`). Set `M6E_SERIES` first to select a series subdirectory:

```bash
M6E_SERIES="${B19_TOR_SERIES}"
eval "$(b19-resolve-dep tor)"
```

> `b19-resolve-dep` always writes the same variable names and hooks are sourced in one shell — a hook that reads these values MUST run its own `eval "$(b19-resolve-dep …)"`; an earlier hook’s resolve is not yours.

The download itself is [b19-fetch](use-b19-fetch.md) — three-tier cache, SHA-512 verification, offgrid-aware.

## Workflow

### Adding a dependency

1. Create `.container/{stage}/deps/{component}/` with `version.deps` and `url.deps` (plus `{arch}.url.deps` if arch-specific)
1. `make fetch` — downloads and computes the hash files
1. Commit everything including the generated `{arch}.hash.deps`
1. Write the build hook that calls `b19-resolve-dep` + `b19-fetch` (patterns in [build with hooks](use-build.d.md))

### Updating a version

1. Edit `version.deps` (or `make set/{ns}/{proj}/{component}@{ver}` from the workspace root)
1. `make fetch` — detects the stale hash, re-downloads, rewrites it
1. Commit the updated `version.deps` + hash files

### Prefetch and offline builds

`make fetch` populates `.fetch/` — tier 1 of the fetch cache — which is exactly what an [offgrid build](use-offgrid.md) consumes (`make fetch-clean` clears it).

## Hook patterns

```bash
# Graceful skip for unsupported archs
resolved="$(b19-resolve-dep {component} "${TARGETARCH}" 2>/dev/null)" || {
    b19-log warn "TAG" "$(_p "No binary for %s, skipping" "${TARGETARCH}")"
    return 0
}
eval "${resolved}"
b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
```

```bash
# Series-based source download
M6E_SERIES="${B19_MY_SERIES}"
eval "$(b19-resolve-dep {component})"
b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
tar --extract --file "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}"
```

## APT packages

APT deps ride the same tree but are read directly by `install-apt`, not by the fetch pipeline. Resolution is stage-prefixed first (most specific wins):

1. `{stage}.apt.deps`
1. `{stage}.common.apt.deps` + `{stage}.{codename}.apt.deps` + `{stage}.{arch}.apt.deps`
1. `apt.deps`
1. `common.apt.deps` + `{codename}.apt.deps` + `{arch}.apt.deps`

`{arch}` is `dpkg --print-architecture` (`amd64`, `arm64`, `riscv64`), so a package that exists on some architectures only goes in that architecture’s list.

One package per line, `name[=version] # comment`; `install-apt` installs with `--no-install-recommends`, honors the [APT cache](use-apt-cache.md) and proxy, and cleans up consumed files.

### Version pinning

Fetched binaries pin via `version.deps`; APT packages float by default (`install-apt` installs bare names, `400-upgrade.sh` dist-upgrades). To pin, write the version inline as the first token — `install-apt` passes `name=version` straight to `apt-get`:

```text
curl=8.12.1-1ubuntu1           # transfer tool | deps: libcurl4t64
```

Never list the same package both bare and pinned — apt would be asked for it twice.

Pins are harvested from a built image, not hand-written: the harvester asks the image’s own apt — so extra repositories (Docker, llvm.org, …) and apt preferences are honored — for the candidate version of each listed package and rewrites it in place, preserving the comment column:

- `make apt-pin` — resolve candidates and update `common.apt.deps`
- `make apt-pin-check` — exit non-zero if a pin drifted; no writes (lefthook/CI)

The mechanism lives in m6e/container (`workflow/apt-pin.mk` + `scripts/apt-pin.sh`), so every container consumer gets it — the APT analogue of `npm-user-upgrade`.

## Ancillary deps files

Files in `.container/{stage}/deps/` outside the fetch pipeline:

| File              | Purpose                                                                                      |
| ----------------- | -------------------------------------------------------------------------------------------- |
| `common.apt.deps` | APT packages for `install-apt`; `{codename}` and `{arch}` lists add to it                    |
| `volumes.deps`    | Dirs pre-created + chowned by `b19-prepare-volumes` (see [build with hooks](use-build.d.md)) |
| `*.j2`            | Jinja2 templates for APT sources etc.                                                        |
| `install-*.sh`    | Extension-specific install hooks (PHP extensions)                                            |
| `*.ini.j2`        | PHP extension config templates                                                               |

## See also

- [Download files with b19-fetch](use-b19-fetch.md) — the three-tier cache these files feed
- [Build images with build.d hooks](use-build.d.md) — where resolve+fetch patterns live
- [Use the APT cache](use-apt-cache.md) — how package installs stay fast
