<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Build images with build.d hooks

`build.d` replaces inline `RUN` logic with modular, ordered, inheritable shell hooks: one `RUN build-stage {name}` per Dockerfile stage runs `pre/` → `on/` → `post/` hook directories, and `.i.sh` hooks survive to run again in every downstream image. The pitch: [modular build hooks](../features.d/build.d.md).

## When to use

- Every stage of every b19 image: `build-stage` is the only `RUN` command a stage needs.
- Base images shipping setup that downstream images should inherit (APT cacher detection, CPU detection, volume preparation).
- Anything you would otherwise write as a 30-line `RUN` chain — a hook gets ordering, logging, i18n and inheritance for free.

## Quick start

```dockerfile
COPY --chown="${B19_UID}:${B19_GID}" .container/foundation/  /

RUN --mount=type=bind,from=fetch,source=.,target=/fetch  \
    --mount=type=cache,target=${B19_DOWNLOAD_PATH}        \
    --mount=type=cache,id=apt-cache-${SERIES},target=/var/cache/apt \
    --mount=type=tmpfs,target=${B19_TEMP_PATH}            \
    build-stage foundation
```

```bash
# .container/{stage}/build.d/{stage}/post/300-install-my-tool.sh
#!/usr/bin/env bash
. b19-i18n
eval "$(b19-resolve-dep my-tool "${TARGETARCH}")"
b19-fetch "TOOL" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
b19-run "TOOL" "$(_p "Install %s" "my-tool")" -- \
  mv "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}" /usr/local/bin/my-tool
```

## How it works

```text
Dockerfile:  RUN build-stage foundation
                  |
                  v
build-stage (tools.d/build-stage)
  |
  ├─ SCOPE=always  ON=pre  . process-hooks -->  /build.d/always/pre/*.sh  (sorted)
  ├─ SCOPE={stage} ON=pre  . process-hooks -->  /build.d/{stage}/pre/*.sh  (sorted)
  ├─ SCOPE={stage} ON=on   . process-hooks -->  /build.d/{stage}/on/*.sh   (sorted)
  ├─ SCOPE={stage} ON=post . process-hooks -->  /build.d/{stage}/post/*.sh (sorted)
  └─ SCOPE=always  ON=post . process-hooks -->  /build.d/always/post/*.sh  (sorted)
```

- Hooks are **sourced** (`. "${HOOK}"`), not executed — they share shell state; numeric sort order (`100-foo.sh` before `200-bar.sh`).
- On error: the failing hook name and exit code are logged and the build aborts (each hook runs under an ERR trap, with `set -eo pipefail` inherited from `build-stage`).
- After execution, `process-hooks` deletes every `*.sh` that is not `*.i.sh` and removes empty directories — hooks from one stage can never leak into the next when `/build.d/` is reused across multi-stage builds.
- `${STAGE}` is the real stage name in every hook (the `always/` ones included); `${SCOPE}` is the directory being run.

### Stage-independent hooks (`always/`)

`always` is a **reserved stage name**. Its hooks bracket every `build-stage` call, whichever stage is named — `base`, `root`, `user`, `compile-go`, or a name a downstream image invents tomorrow. Setup that must hold for *all* stages belongs there once:

```text
/build.d/always/pre/010-trust-ca-certificates.i.sh    <- before {stage}/pre
/build.d/always/post/950-trust-ca-certificates.i.sh   <- after  {stage}/post
```

Because they are `*.i.sh`, they survive the prune and ride the image lineage: `b19/ubuntu` seeds them, `b19/go` inherits them, and a project’s `RUN build-stage compile-go` runs them without either image knowing. Set `B19_BUILD_ALWAYS_ENABLED=false` to skip them for a stage that must not touch, say, the trust store — the stage’s own hooks still run. Use `always/` only for what genuinely applies everywhere: it runs on every stage of every downstream image, including `user` stages that are not root.

### Inheritable hooks (`*.i.sh`)

The `.i.` suffix survives the post-execution cleanup:

```text
100-detect-apt-cacher.i.sh    <- survives, available to downstream stages
100-detect-apt-cacher.sh      <- deleted after execution
```

Inheritance works because `COPY .container/{stage}/ /` merges new files into the existing `/build.d/` tree — the base image’s `.i.sh` files are still there when the downstream image runs `build-stage`. Real lineage examples:

- `b19/ubuntu` defines `root/pre/100-detect-apt-cacher.i.sh` — every downstream `root` stage inherits APT cacher detection.
- `b19/gcc` defines `compile-gcc/pre/100-setup-build.i.sh` — every project using a `compile-gcc` stage gets CFLAGS/LDFLAGS probing and MAKEFLAGS setup.
- `b19/rust` defines `compile-rust/post/300-install-from-cargo.i.sh` — any `user` stage inheriting from rust can auto-install cargo packages.

### Directory layout

```text
.container/{stage}/build.d/
  always/               <- reserved: runs on every build-stage call
    pre/                <- runs before {stage}/pre
    post/               <- runs after {stage}/post
  {stage}/              <- must match the argument passed to build-stage
    pre/                <- runs before on/ (repository setup, certs, detection)
    on/                 <- central hooks (CPU detection, apt install)
    post/               <- runs after on/ (tool install, compile, cleanup)
```

Common stage names across the fleet:

| Stage Name       | Used By                                         | Purpose                                               |
| ---------------- | ----------------------------------------------- | ----------------------------------------------------- |
| `foundation`     | Ubuntu                                          | Root-level OS setup                                   |
| `base`           | gcc, llvm, node, go, Java, crystal, php, rust   | Language/tool install from apt or tarball             |
| `root`           | scala, node                                     | Alternative to `base` when inheriting from non-ubuntu |
| `user`           | all projects                                    | Non-root final stage, runtime setup                   |
| `compile-gcc`    | node, python, ruby, php, erlang, haskell, nginx | Compile-from-source using GCC                         |
| `compile-rust`   | rust, gleam, nginx (ACME)                       | Compile-from-source using Rust/Cargo                  |
| `compile-go`     | go                                              | Compile Go programs                                   |
| `compile-llvm`   | zig                                             | Compile using LLVM toolchain                          |
| `compile-erlang` | elixir                                          | Compile Erlang bytecode                               |

### Numbering convention

Zero-padded 3-digit numbers; ranges are conventional, not enforced:

| Pre | Purpose                                                              |
| --- | -------------------------------------------------------------------- |
| 050 | Auxiliary tool setup (e.g., Python for node builds)                  |
| 100 | Detection and setup (apt-cacher, certificates, lineage, build flags) |
| 200 | Source configuration, template rendering                             |

| On  | Purpose                                                         |
| --- | --------------------------------------------------------------- |
| 100 | Environment detection (CPU count) — typically inheritable       |
| 500 | Package installation (apt) — inheritable, guarded by root check |

| Post    | Purpose                                                         |
| ------- | --------------------------------------------------------------- |
| 020     | Port validation                                                 |
| 050     | Compile cache setup (sccache)                                   |
| 100     | Install tools, download sources, cleanup, certificates, locales |
| 150     | Secondary setup (i18n compilation)                              |
| 200     | Permissions, volumes, tokens                                    |
| 250-270 | Secondary configuration (log dirs, global npm)                  |
| 300     | Install binary tools (fd, mold, go, crystal, configure)         |
| 350     | Feature switching (mold linker, corepack)                       |
| 400     | System upgrades, dhparams                                       |
| 500     | Main compile/build step (the heavy one)                         |
| 600     | Post-build (cabal, user/group, check-outdated)                  |
| 700     | Secondary build steps (PHP extensions, nginx modules)           |
| 800     | Template save, composer-install                                 |
| 820     | J2 template save                                                |
| 900     | Final cleanup, cache stats display                              |
| 920     | J2 test processing                                              |
| 990     | Write lineage (always last)                                     |

## The hooks this image ships

### foundation (root, primary install)

```text
pre/
  100-detect-apt-cacher.sh              discover local APT caching proxy
  100-enable-buildkit-cache-for-apt.sh  remove docker-clean config (unblocks BuildKit APT cache)
  200-setup-sources.sh                  render APT sources via minijinja

on/
  100-detect-cpu-count.i.sh             detect NUMPROCS (inheritable)
  500-install-apt.sh                    install APT packages (non-inheritable, foundation-only)

post/
  100-clean-apt-cacher.i.sh             remove proxy config (inheritable)
  100-update-certificates.sh            update CA certificates
  150-compile-i18n.sh                   compile .po -> .mo translations
  200-permissions.sh                    create dirs, set ownership
  300-install-fd.sh                     install fd binary (b19-resolve-dep + b19-fetch)
  300-install-mold.sh                   install mold linker (b19-resolve-dep + b19-fetch)
  350-switch-to-mold.sh                 symlink /usr/bin/ld -> mold
  400-upgrade.sh                        apt-get dist-upgrade (guarded by B19_OFFGRID_MODE)
  600-create-user-group.sh              create ubuntu user (UID 1000)
  650-setup-shell-hooks.sh              append shell.d sourcing to /etc/bash.bashrc
  820-save-j2.sh                        discover and save Jinja2 templates
  900-cleanup.sh                        remove /home, /var/log/*
```

### root and base (intermediate stages)

```text
pre/
  100-compile-i18n.i.sh          compile translations (inheritable)
  100-detect-apt-cacher.i.sh     detect proxy (inheritable)
  200-read-lineage.i.sh          read lineage metadata (inheritable)

on/
  100-detect-cpu-count.i.sh      detect NUMPROCS (inheritable)
  500-install-apt.i.sh           install APT packages (inheritable, root-guarded)

post/
  100-clean-apt-cacher.i.sh      cleanup proxy (inheritable)
  200-prepare-volumes.i.sh       setup volume directories (inheritable)
```

### user (non-root final stage)

```text
pre/
  200-read-lineage.i.sh          read lineage (inheritable)

post/
  020-check-ports.i.sh           validate PORT variables (inheritable)
  200-prepare-volumes.i.sh       setup volumes (inheritable)
  820-save-j2.i.sh               save J2 templates + test templates (inheritable)
  920-process-j2-tests.i.sh      render test J2 templates (inheritable)
  990-write-lineage.i.sh         write image lineage metadata (inheritable)
```

## Tools available to hooks

Hooks run in a shared shell with `/tools.d` on `PATH` — the full library is catalogued in [use the tools](use-tools.md); the ones hooks call most:

| Tool                                         | One-liner                                                           | Article                                               |
| -------------------------------------------- | ------------------------------------------------------------------- | ----------------------------------------------------- |
| `b19-run`                                    | Timed command wrapper with failure reporting                        | [b19-run](use-b19-run.md)                             |
| `b19-log`                                    | Level-filtered logger                                               | [b19-log](use-b19-log.md)                             |
| `b19-fetch`                                  | Three-tier cached download, SHA-512 verified                        | [b19-fetch](use-b19-fetch.md)                         |
| `b19-resolve-dep`                            | Resolve pinned dependency metadata from `/deps/{component}/`        | [dependencies](use-dependencies.md)                   |
| `install-apt`                                | Install packages from declarative `.apt.deps` files                 | [dependencies](use-dependencies.md)                   |
| `b19-compile-i18n`                           | Compile `.po` → `.mo`; must run before any hook uses `_()` / `_p()` | [i18n](use-i18n.md)                                   |
| `save-j2`                                    | Discover Jinja2 templates for runtime rendering                     | [templating](use-templating.md)                       |
| `b19-prepare-volumes`                        | Pre-create and chown `volumes.deps` directories                     | [Volume directories](#volume-directories-volumesdeps) |
| `read-lineage` / `write-lineage`             | Track image provenance                                              | [lineage](use-lineage.md)                             |
| `check-ports`                                | Validate PORT env vars against blocked ranges                       | [port validation](use-port-validation.md)             |
| `detect-apt-cacher`                          | Discover local APT caching proxy                                    | [APT cache](use-apt-cache.md)                         |
| `b19-generate-locales` / `b19-ensure-locale` | Compile/validate locales                                            | [i18n](use-i18n.md)                                   |
| `decomment`                                  | Strip comments from text files (stdin filter)                       |                                                       |
| `apt-cleanup`                                | Clean APT cache and lists                                           |                                                       |

## Volume directories (`volumes.deps`)

A `volumes.deps` file declares directories that must exist — and be owned by `B19_UID:B19_GID` — before a container starts. The inheritable `post/200-prepare-volumes.i.sh` hook reads one per stage and feeds it to `b19-prepare-volumes`, which `mkdir -p`s each path and (as root) `chown`s it to the runtime user. Without this, Docker auto-creates a missing bind-mount parent as `root:root`, which the non-root container user cannot write to.

Each stage looks for the file at a **different path** — the hook in each stage hardcodes its own:

| Stage         | Hook reads              | Source path in `.container/{stage}/` |
| ------------- | ----------------------- | ------------------------------------ |
| `base`/`root` | `/deps/volumes.deps`    | `deps/volumes.deps`                  |
| `user`        | `/build.d/volumes.deps` | `build.d/volumes.deps`               |

One path per line; empty lines and `#` comments ignored; `${VAR}` is `envsubst`-expanded against build-time env (`B19_HOME`, `CARGO_HOME`, `XDG_CACHE_HOME`, …):

```text
# SPDX-FileCopyrightText: 2026 …
# SPDX-License-Identifier: MIT

${CARGO_HOME}
${XDG_CACHE_HOME}/npm
${B19_HOME}/.npm/_logs
```

Use it for any directory that is the **parent** of a runtime bind-mount but is not itself mounted. The canonical case: a language tool writes a lock/state file *next to* its cache subdir, so the parent must be writable:

```text
/app/.cargo/                       <- parent: must be writable (cargo-audit writes advisory-db..lock HERE)
├── registry/                      <- mounted (cache)
├── git/                           <- mounted (cache)
└── advisory-db/                   <- mounted (cache)
```

Listing just the parent `${CARGO_HOME}` is enough — the bind-mounts create the children at runtime.

### Gotcha: `--mount=type=cache` shadows the target

A directory created under a BuildKit `--mount=type=cache,target=…` mount is **ephemeral** — it lands in the cache backing store, never the image layer. A `volumes.deps` entry is only effective in a stage where its path is **not** cache-mounted:

```dockerfile
# base stage: CARGO_HOME is a cache mount — a volumes.deps entry here is EPHEMERAL
RUN --mount=type=cache,id=cargo-home,target=${CARGO_HOME} … build-stage base

# user stage: no cache mount on CARGO_HOME — the mkdir here PERSISTS into the image
RUN … build-stage user
```

This is why `b19/rust` declares `${CARGO_HOME}` in `.container/user/build.d/volumes.deps` (persists) rather than `.container/base/deps/volumes.deps` (shadowed by the base-stage cache mount).

## Recipes

### Pattern A: resolve + fetch + extract

The most common pattern for installing binary dependencies:

```bash
#!/usr/bin/env bash
. b19-i18n

eval "$(b19-resolve-dep fd "${TARGETARCH}")"

b19-fetch "FD" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"

b19-run "FD" "$(_p "Move %s to %s" "${M6E_UPSTREAM__FILE}" "/usr/local/bin/fd")" \
  -- mv "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}" /usr/local/bin/fd

b19-run "FD" "$(_p "Set executable %s" "/usr/local/bin/fd")" \
  -- chmod +x /usr/local/bin/fd
```

### Pattern B: thin inheritable wrapper

Most inheritable hooks delegate to a single tool:

```bash
#!/usr/bin/env bash
b19-log info "LINEAGE" "$(read-lineage)"
```

```bash
#!/usr/bin/env bash
check-ports
```

### Pattern C: compile from source

Standard configure/build/install cycle:

```bash
#!/usr/bin/env bash
. b19-i18n
eval "$(b19-resolve-dep ruby)"

cd "${B19_TEMP_PATH}" || exit
b19-fetch "RUBY" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"

b19-run "RUBY" "$(_p "Extract %s" "${M6E_UPSTREAM__FILE}")" \
  -- tar --extract --strip-components=1 --file "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}"

b19-run "RUBY" "$(_ 'Configure')" \
  -- ./configure --prefix=/usr --enable-shared

b19-run "RUBY" "$(_p 'Build with %s jobs' "${NUMPROCS}")" \
  -- make -j"${NUMPROCS}"
```

### Pattern D: conditional downstream hook

Auto-detect and act based on project files:

```bash
#!/usr/bin/env bash
if [ -f composer.json ]; then
    b19-run "COMPOSER" "$(_ 'Install dependencies')" \
      -- composer install --no-interaction
fi
```

### Pattern E: idempotency guard

Skip if already installed — important for inherited hooks, which may run in several stages:

```bash
#!/usr/bin/env bash
command -v php-config >/dev/null 2>&1 && {
    b19-log note "PHP" "$(_ 'Already installed, skipping build')"
    return 0
}
```

### Pattern F: module iteration

Iterate over dynamic dependency directories:

```bash
#!/usr/bin/env bash
for MODULE_DIR in /deps/modules/*/; do
    [ -f "${MODULE_DIR}/build.sh" ] || continue
    . "${MODULE_DIR}/build.sh"
done
```

## Configuration

Key variables available during build (set by Dockerfile `ENV` and `ARG`):

| Variable              | Description                                            |
| --------------------- | ------------------------------------------------------ |
| `STAGE`               | Current stage name (set by `build-stage`)              |
| `ON`                  | `pre` or `post` (set by `process-hooks`)               |
| `B19_BUILD_PATH`      | Build hooks root (`/build.d`)                          |
| `B19_DEPS_PATH`       | Dependency metadata (`/deps`)                          |
| `B19_TEMP_PATH`       | Temporary directory (`/tmp`)                           |
| `B19_DOWNLOAD_PATH`   | Download cache directory                               |
| `B19_UID` / `B19_GID` | User/group IDs                                         |
| `TARGETARCH`          | Target architecture (`amd64`, `arm64`)                 |
| `NUMPROCS`            | Number of CPUs (set by `on/100-detect-cpu-count.i.sh`) |

The full variable index lives in [configure-environment](configure-environment.md).

## Gotchas

- **Stage name must match directory name**: `build-stage foundation` looks for hooks in `/build.d/foundation/`, not `/build.d/base/`.
- **`always` is reserved**: `/build.d/always/{pre,post}` runs on *every* `build-stage` call, so a stage may not be named `always`.
- **Hooks are sourced, not exec’d**: variables leak between hooks in the same stage — by design, but watch for name collisions.
- **Post-cleanup deletes regular hooks**: if a hook must survive to a later stage, name it `*.i.sh`.
- **`install-apt` only runs for root**: the root guard is inside `on/500-install-apt.i.sh`, so `user` stages skip APT installation entirely (and have no `on/` directory at all).
- **`b19-run` executes via `"$@"`**: always use the `--` separator for commands.
- **Pre-hooks set up state for on-hooks, on-hooks for post-hooks**: `detect-apt-cacher` (pre) writes `/etc/apt/apt.conf.d/99proxy`, `install-apt` (on) uses the proxy, `clean-apt-cacher` (post) removes it.
- **Hooks from COPY merge with existing**: downstream images add hooks alongside inherited `.i.sh` hooks — both run in the same sorted sequence.
- **`B19_VERBOSITY=warn` in final ENV**: build-time hooks see `info` by default (from ARG), but the final image sets `warn` — `b19-log info` messages are visible during build, not at runtime.
- For graceful skips use `command -v tool || { return 0 }`; `|| exit 9` is the hard-stop escape hatch (seen in `install-apt`).

## See also

- [Declare dependencies](use-dependencies.md) — the `*.deps` files `b19-resolve-dep` reads
- [Use the runner family](use-runner-family.md) — how build.d differs from the runtime runners
- [Render templates with minijinja](use-templating.md) — `save-j2` and the template lifecycle
- [Track image lineage](use-lineage.md) — what the 990 hook writes
