<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Use the tools

`/tools.d` is the shared CLI library baked into this image and inherited by every downstream image — logging, downloads, process management, secrets, i18n, port checks — on `PATH` ahead of raw shell so the whole fleet gets uniform behavior. Prefer these over hand-rolled shell: logging, i18n, caching and offgrid guards come along for free. The pitch: [pre-installed utility tools](../features.d/tools.md).

## When to use

- Writing any hook, test, healthcheck or script that ships in a b19 image: reach for a tool first, shell second.

## Quick start

```bash
b19-log good "SETUP" "Ready"                  # leveled, colored, NO_COLOR-aware
b19-run "BUILD" "Compile" -- make -j"${NUMPROCS}"
b19-fetch "TOOL" "$URL" file.tar.gz "$SHA512"
```

## How it works

The `PATH` includes `/tools.d` and `/command.d`; the tree is assembled from `.container/foundation/tools.d/` (installed as root) and `.container/user/tools.d/` (the runner drivers), overlaid by downstream `COPY .container/{stage}/ /`.

### The tools with their own how-tos

| Tool                                                           | One-liner                                     |
| -------------------------------------------------------------- | --------------------------------------------- |
| [`b19-log`](use-b19-log.md)                                    | Leveled, tag-prefixed logger on stderr        |
| [`b19-run`](use-b19-run.md)                                    | Timed command wrapper with failure reporting  |
| [`b19-exec`](use-b19-exec.md)                                  | Long-running process manager with log routing |
| [`b19-fetch`](use-b19-fetch.md)                                | Three-tier cached download, SHA-512 verified  |
| [`build-stage` / `process-hooks`](use-build.d.md)              | The build hook engine                         |
| [`install-apt` / `update-apt`](use-apt-cache.md)               | Deps-driven package install with caching      |
| [`b19-resolve-dep`](use-dependencies.md)                       | Pinned dependency metadata for hooks          |
| [`check-ports`](use-port-validation.md)                        | WHATWG + privileged port validation           |
| [`b19-i18n` / `b19-compile-i18n`](use-i18n.md)                 | gettext helpers and catalog compilation       |
| [`j2-render` / `save-j2` / `parallel-j2`](use-templating.md)   | minijinja template pipeline                   |
| [`read-lineage` / `write-lineage`](use-lineage.md)             | Provenance chain append/print                 |
| [`detect-cpu-count`](use-cpu-detection.md)                     | `NUMPROCS` from quota/cgroups/nproc           |
| [`b19-load-secrets` / `b19-exec-with-secrets`](use-secrets.md) | Secret files → env vars                       |
| [`b19-prepare-volumes`](use-build.d.md)                        | `volumes.deps` mkdir + chown                  |
| [`trust-ca-certificates`](use-b19-fetch.md)                    | Trust the build host CA for exactly one stage |
| \[`setup-ssh` / `keyscan`\]                                    | SSH keys from secrets; pre-seed `known_hosts` |

### The smaller helpers

- `detect-apt-cacher install|remove` — write/remove the LAN APT proxy config from `M6E_APT_CACHE_HOST`; root-only, no-ops otherwise
- `check-reachable <tag> <url> [timeout]` — cURL connect probe used by `detect-apt-cacher` and `b19-fetch` to skip a stuck LAN cache instead of failing
- `b19-generate-locales` / `b19-ensure-locale` — compile/validate locales
- `decomment` — strip `#` comments from a stream
- `ansi`, `hr` — ANSI escapes and horizontal rules for pretty output
- `setup-docker-sources`, `setup-pass-with-docker`, `add-user-to-docker` — Docker-in-Docker conveniences
- `/command.d` mini-commands: `get-ubuntu-version`, `list-commands`, `dummy`

### Preinstalled binaries

Not in `tools.d` but shipped by install hooks and always available: `mold` (default linker, opt-out via `B19_BUILD_DISABLE_MOLD`), `fd`, `minijinja-cli`, `aria2c`, `tini`, `pbzip2` / `pigz` / `pixz`, gettext, cURL.

## See also

- [Use the runner family](use-runner-family.md) — the drivers that consume these tools
- [Configure the image environment](configure-environment.md) — the knobs they honor
