<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Build on the pinned base

The `FROM` line is `ubuntu@sha256:…` — a digest, never a mutable tag. Rebuilding this image a year from now produces the same base layer, and the whole fleet’s reproducibility hangs off that one pin. The digests are data files, versioned and updatable like any dependency. The pitch: [reproducible base image](../features.d/pinned-base.md).

## When to use

- Updating the fleet base: bump a digest file, rebuild, everything downstream rebuilds on top.
- Selecting an Ubuntu series (`resolute`, `noble`, `jammy`) or a per-arch APT mirror for LAN/air-gapped environments.

## Quick start

```bash
# Update the resolute pin: write the new digest, rebuild
echo "sha256:<new-digest>" > .container/foundation/deps/ubuntu/resolute.sha256.deps
M6E_AI=Y make build
```

## How it works

```text
.container/foundation/deps/ubuntu/
├── jammy.sha256.deps      # one-line digest per series
├── noble.sha256.deps
└── resolute.sha256.deps
```

The projectfile maps the file to the `B19_UBUNTU_HASH` build arg (`file:` key), CI injects it via file-args, and the Dockerfile consumes `FROM ubuntu@${B19_UBUNTU_HASH}`. The deps files are the source of truth; the `ARG` inline default in the Dockerfile is a stale fallback that real builds always override.

The series axis (`B19_UBUNTU_SERIES`, default `resolute`; CI builds `resolute` + `noble`) fans out to series-qualified images `b19/ubuntu/<series>` — anything series-specific belongs in `deps/ubuntu/<series>.*` or `.j2` templates, never hardcoded.

Downstream images do not pin by digest themselves: they `FROM` the published series tag of this image, so the fleet pins exactly once, here.

### Mirrors per architecture

APT mirrors are build args rendered into the sources lists by `foundation/pre/200-setup-sources.sh` (DEB822 `ubuntu.sources` or classic `sources.list`, via `.j2` templates):

| Variable                    | Default                                |
| --------------------------- | -------------------------------------- |
| `B19_UBUNTU_MIRROR_AMD64`   | `http://archive.ubuntu.com/ubuntu/`    |
| `B19_UBUNTU_MIRROR_ARM64`   | `http://ports.ubuntu.com/ubuntu-ports` |
| `B19_UBUNTU_MIRROR_RISCV64` | `http://ports.ubuntu.com/ubuntu-ports` |

## Recipes

```bash
# Verify the running series matches the pin
docker run --rm <image> get-ubuntu-version
```

```bash
# Build a specific series locally
M6E_AI=Y make build B19_UBUNTU_SERIES=noble
```

## See also

- [Declare dependencies](use-dependencies.md) — the `*.deps` system this pin rides on
- [Use the APT cache](use-apt-cache.md) — series-keyed cache mounts
