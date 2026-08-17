<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Track image lineage

Every image appends one line of build identity — who built it, when, at what version, on which upstream — to a lineage file that rides the image layers. A downstream image inherits its parent’s entries and adds its own, so the file is a base-to-current provenance chain you can read from any running container. The pitch: [image lineage tracking](../features.d/lineage.md).

## When to use

- Debugging “what is this container actually built from?” — one file answers the whole chain.
- Any downstream image: the writer hook is inherited, so lineage works with zero configuration.

## Quick start

```bash
docker exec <container> cat /app/.lineage
```

```text
[amd64] b19/ubuntu 250612.1042 1.2.3 [Upstream: 25.10]
[amd64] b19/node 250614.0912 3.2.0 [Upstream: 22.16.0]
```

## How it works

During the `user` build stage, the inherited `post/990-write-lineage.i.sh` hook calls:

```bash
write-lineage "${M6E_NAMESPACE}/${M6E_PROJECT}" "${UPSTREAM_VERSION}"
```

appending one line to `${B19_LINEAGE_FILE}` (default `${B19_HOME}/.lineage`):

```text
[<TARGETARCH>] <namespace/project> <yymmdd.HHMM> <M6E_VERSION> [Upstream: <version>]
```

Because the file lives in an image layer, a downstream image built `FROM` this one keeps the parent’s entries and appends its own — the chain grows one hop per image, no ancestry walk needed. At build start, the inherited `pre/200-read-lineage.i.sh` hooks log the parent chain; at startup the `0400-print-lineage.sh` entrypoint hook logs it again — at `debug` level, so raise `B19_VERBOSITY` to see it.

### The upstream version command

`[Upstream: …]` comes from a version command named `get-<project>-version` on `PATH` (i.e. `.container/user/command.d/get-<project>-version`); without one, the hook records `?`. This image ships `get-ubuntu-version`, echoing `${DISTRIB_RELEASE}` from `/etc/lsb-release`. The scaffold generates the conventional implementation:

```bash
# .container/user/command.d/get-<project>-version
<project> --version 2>&1 | awk '{print $NF}' || echo "unknown"
```

## Configuration

| Variable           | Default                | Effect                      |
| ------------------ | ---------------------- | --------------------------- |
| `B19_LINEAGE_FILE` | `${B19_HOME}/.lineage` | Where the chain is appended |

Ensure `M6E_NAMESPACE`, `M6E_PROJECT`, `M6E_VERSION` and `TARGETARCH` reach your Dockerfile as build args — CI passes them on every build.

## Recipes

```bash
# Log the chain from inside the container at startup verbosity
B19_VERBOSITY=debug docker run --rm <image>   # watch the LINEAGE lines
```

## See also

- [Build images with build.d hooks](use-build.d.md) — the 990 writer hook
- [Run commands with b19-run](use-b19-run.md) — how hooks report
