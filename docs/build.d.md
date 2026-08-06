<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# build.d — Build Hook System

The numbered-hook runner that orchestrates all Docker image construction in the
ecosystem. Replaces inline `RUN` logic in Dockerfiles with modular, ordered,
reusable shell scripts.

## Architecture

Every `RUN build-stage {name}` invocation in a Dockerfile triggers this chain:

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
  └─ SCOPE=always  ON=post . process-hooks -->  /build.d/always/post/*.sh (sorted)
```

- Hooks are **sourced** (`. "${HOOK}"`), not executed -- they share shell state
- Scripts run in numeric sort order (`100-foo.sh` before `200-bar.sh`)
- On error: the failing hook name and exit code are logged, build aborts
- After execution: all `*.sh` hooks are deleted; `*.i.sh` (inheritable) survive
- `${STAGE}` is the real stage name in every hook, `always/` ones included;
    `${SCOPE}` is the directory being run

## Stage-independent hooks (`always/`)

`always` is a **reserved stage name**. Its hooks bracket every `build-stage`
call, whichever stage is named -- `base`, `root`, `user`, `compile-go`, `fetch`,
a name a downstream image invents today. Setup that must hold for *all* stages
belongs there once, instead of being copied into each stage directory in the
fleet:

```text
/build.d/always/pre/010-trust-ca-certificates.i.sh    <- before {stage}/pre
/build.d/always/post/950-trust-ca-certificates.i.sh   <- after  {stage}/post
```

Because they are `*.i.sh`, they survive the prune and ride the image lineage:
`b19/ubuntu` seeds them, `b19/go` inherits them, and a project’s
`RUN build-stage compile-go` runs them without either image knowing.

Set `B19_BUILD_ALWAYS_ENABLED=false` to skip them for a stage -- a stage that
must not touch the trust store, say. The stage’s own hooks still run.

Use `always/` only for what genuinely applies everywhere: it runs on every stage
of every downstream image, including `user` stages that are not root.

## Wiring in Dockerfile

```dockerfile
COPY --chown="${B19_UID}:${B19_GID}" .container/foundation/  /

RUN --mount=type=bind,from=fetch,source=.,target=/fetch  \
    --mount=type=cache,target=${B19_DOWNLOAD_PATH}        \
    --mount=type=cache,id=apt-cache-${SERIES},target=/var/cache/apt \
    --mount=type=tmpfs,target=${B19_TEMP_PATH}            \
    build-stage foundation
```

Key points:

- `COPY .container/{stage}/ /` places `build.d/`, `deps/`, `tools.d/`, `etc/`, and everything else under that stage directory into the container root
- `build-stage {name}` is the only `RUN` command needed per stage
- Mount types provide: fetch cache (`/fetch`), download cache, APT cache, and a tmpfs for temporary files

## Directory Layout

```text
.container/{stage}/build.d/
  always/               <- reserved: runs on every build-stage call
    pre/                <- runs before {stage}/pre
    post/               <- runs after {stage}/post
  {stage}/              <- matches the stage name passed to build-stage
    pre/                <- runs before on/
      050-restore-translations.sh
      100-detect-apt-cacher.sh
      200-setup-sources.sh
    on/                 <- central hooks (cpu detection, apt install)
      100-detect-cpu-count.i.sh
      500-install-apt.i.sh
    post/               <- runs after on/
      050-restore-translations.sh
      150-compile-i18n.sh
      300-install-mold.sh
      900-cleanup.sh
```

The `{stage}` directory name must exactly match the argument to `build-stage`.
Common stage names: `foundation`, `base`, `user`, `root`, `compile-gcc`,
`compile-rust`, `compile-go`, `compile-llvm`, `compile-erlang`.

## Hook Execution: process-hooks

The `process-hooks` tool (at `/tools.d/process-hooks`) handles all hook
execution:

1. Constructs path: `/build.d/${SCOPE}/${ON}/` (`SCOPE` defaults to `STAGE`)
1. Finds all `*.sh` files, sorts by name (zero-delimited for safety)
1. Sources each hook with ERR trap for error reporting
1. After all hooks complete:
    - Deletes all `*.sh` files that are NOT `*.i.sh`
    - Removes empty directories under `/build.d/`

The cleanup step is critical: it prevents hooks from one stage leaking into
the next when the same `/build.d/` directory is reused across multi-stage
builds.

## Inheritable Hooks (\*.i.sh)

Hooks named with `.i.` in the suffix survive the post-execution cleanup:

```text
100-detect-apt-cacher.i.sh    <- survives, available to downstream stages
100-detect-apt-cacher.sh      <- deleted after execution
```

This mechanism allows base images to provide hooks that automatically run in
downstream images. For example:

- `b19/ubuntu` defines `root/pre/100-detect-apt-cacher.i.sh` -- every downstream `root` stage inherits APT cacher detection
- `b19/gcc` defines `compile-gcc/pre/100-setup-build.i.sh` -- every project using a `compile-gcc` stage gets CFLAGS/LDFLAGS probing and MAKEFLAGS setup
- `b19/rust` defines `compile-rust/post/300-install-from-cargo.i.sh` -- any
    `user` stage inheriting from rust can auto-install cargo packages

Inheritable hooks propagate because `COPY .container/{stage}/ /` merges new
files into the existing `/build.d/` tree. The `.i.sh` files from the base
image are still there when the downstream image runs `build-stage`.

## Numbering Convention

Hooks are zero-padded 3-digit numbers. The ranges are conventional, not
enforced:

### Pre-hooks (before on/)

| Range | Purpose                                                              |
| ----- | -------------------------------------------------------------------- |
| 050   | Auxiliary tool setup (e.g., Python for node builds)                  |
| 100   | Detection and setup (apt-cacher, certificates, lineage, build flags) |
| 200   | Source configuration, template rendering                             |

### On-hooks (central phase)

| Range | Purpose                                                         |
| ----- | --------------------------------------------------------------- |
| 100   | Environment detection (CPU count) — typically inheritable       |
| 500   | Package installation (apt) — inheritable, guarded by root check |

### Post-hooks (after on/)

| Range   | Purpose                                                         |
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

## Stages in b19/Ubuntu

The foundation image defines hooks for four stages:

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

### root (intermediate stage, used by images inheriting from non-ubuntu)

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

### base (intermediate stage, used by most language/tool images)

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

## Stages Across the Ecosystem

Different projects use different stage names depending on their purpose:

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

## Tooling Available to Hooks

Hooks run in a shared shell context with these tools on `PATH`:

### build-stage

Entry point. Orchestrates the pre -> on -> post sequence.

### process-hooks

Finds and sources hooks. Handles error trapping and cleanup of non-inheritable
hooks.

### b19-run

```bash
b19-run "TAG" "Human message" -- command [args...]
```

Wraps command execution with timed logging. Commands are executed directly via `"$@"` with proper argument handling. The `--` separator is a convention for readability.

### b19-log

```bash
b19-log {error|warn|bad|good|info|note|debug} "TAG" "message"
b19-log info "FETCH" "Downloading something"
```

Levels: `error` (40) > `warn` (30) > `info`/`good`/`bad` (20) > `note`/`debug` (10).
Controlled by `B19_VERBOSITY` (default: `warn`). In AI mode (`M6E_AI=Y`),
colors are suppressed.

### b19-resolve-dep

```bash
eval "$(b19-resolve-dep component [arch])"
```

Resolves dependency metadata from `/deps/{component}/`. Sets:

- `M6E_UPSTREAM_VERSION` -- version string
- `M6E_UPSTREAM__URL` -- download URL (envsubst-expanded)
- `M6E_UPSTREAM__HASH` -- SHA-512 hash
- `M6E_UPSTREAM__FILE` -- generated filename

Resolution fallback (most specific wins):

1. `{component}/{series}/file.{arch}.txt`
1. `{component}/{series}/file.txt`
1. `{component}/file.{arch}.txt`
1. `{component}/file.txt`

### b19-fetch

```bash
b19-fetch "TAG" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"
```

Three-tier download with SHA-512 verification:

1. **Local cache** (`/fetch`) -- from `make fetch`, checked first
1. **Docker layer cache** (`${B19_DOWNLOAD_PATH}`) -- persisted across builds
1. **Network** via `aria2c` -- multi-connection, checksum-verified

Supports near-cache host rewriting (`M6E_NEAR_CACHE_HOST`) and off-grid mode
(`B19_OFFGRID_MODE=Y` blocks downloads).

### install-apt

Installs packages from declarative dep files under `/deps/`. Resolution priority
(stage-prefixed wins over default):

1. `{stage}.apt.txt`
1. `{stage}.common.apt.deps` + `{stage}.apt.{codename}.txt`
1. `apt.txt`
1. `common.apt.deps` + `apt.{codename}.txt`

Uses `decomment` to strip comments, installs with `--no-install-recommends`,
cleans up consumed files after install.

Called via `on/500-install-apt.i.sh` hook (root-guarded) or
`on/500-install-apt.sh` (foundation, always root). Not called directly by
`build-stage`.

### b19-compile-i18n

Compiles `.po` translation files into `.mo` binaries. Must run before any hook
that uses translatable strings via `_()` or `_p()`.

### Other tools

- `detect-apt-cacher` -- discover local APT caching proxy
- `b19-generate-locales` -- compile locales from B19_LOCALES via localedef
- `b19-ensure-locale` -- runtime guard: validate LANG, fallback to C.UTF-8
- `save-j2` -- discover Jinja2 templates for runtime rendering
- `read-lineage` / `write-lineage` -- track image provenance
- `b19-prepare-volumes` -- pre-create and chown directories declared in a `volumes.deps` file (see [Volume Directories](#volume-directories-volumesdeps) below)
- `check-ports` -- validate PORT env vars against blocked ranges
- `decomment` -- strip comments from text files (stdin filter)
- `apt-cleanup` -- clean APT cache and lists

## Volume Directories (`volumes.deps`)

A `volumes.deps` file declares directories that must exist — and be owned by
`B19_UID:B19_GID` — before a container starts. The inheritable `post/200-prepare-volumes.i.sh` hook reads one per stage and feeds it to `b19-prepare-volumes`, which `mkdir -p`s each path and (as root) `chown`s it to the runtime user. Without this, Docker auto-creates a missing bind-mount parent as `root:root`, which the non-root container user cannot write to.

### File location per stage

Each stage looks for the file at a **different path** — the hook in each stage hardcodes its own:

| Stage         | Hook reads              | Source path in `.container/{stage}/` |
| ------------- | ----------------------- | ------------------------------------ |
| `base`/`root` | `/deps/volumes.deps`    | `deps/volumes.deps`                  |
| `user`        | `/build.d/volumes.deps` | `build.d/volumes.deps`               |

(The `base`/`root` hooks call `b19-prepare-volumes` with no argument, defaulting to `/deps/volumes.deps`; the `user` hook calls `b19-prepare-volumes /build.d/volumes.deps`.)

### Format

One path per line. Empty lines and `#` comments are ignored; `${VAR}` is `envsubst`-expanded against build-time env (`B19_HOME`, `CARGO_HOME`, `XDG_CACHE_HOME`, …):

```text
# SPDX-FileCopyrightText: 2026 …
# SPDX-License-Identifier: MIT

${CARGO_HOME}
${XDG_CACHE_HOME}/npm
${B19_HOME}/.npm/_logs
```

### When to use it

Any directory that is the **parent** of a runtime bind-mount but is not itself mounted. The canonical case: a language tool writes a lock/state file *next to* its cache subdir, so the parent must be writable:

```text
/app/.cargo/                       <- parent: must be writable (cargo-audit writes advisory-db..lock HERE)
├── registry/                      <- mounted (cache)
├── git/                           <- mounted (cache)
└── advisory-db/                   <- mounted (cache)
```

Listing just the parent `${CARGO_HOME}` is enough — the bind-mounts create the children at runtime.

### Gotcha: `--mount=type=cache` shadows the target

A directory created under a BuildKit `--mount=type=cache,target=…` mount is **ephemeral** — it lands in the cache backing store, never the image layer. So a `volumes.deps` entry is only effective in a stage where its path is **not** cache-mounted:

```dockerfile
# base stage: CARGO_HOME is a cache mount — a volumes.deps entry here is EPHEMERAL
RUN --mount=type=cache,id=cargo-home,target=${CARGO_HOME} … build-stage base

# user stage: no cache mount on CARGO_HOME — the mkdir here PERSISTS into the image
RUN … build-stage user
```

This is why `b19/rust` declares `${CARGO_HOME}` in `.container/user/build.d/volumes.deps` (persists) rather than `.container/base/deps/volumes.deps` (shadowed by the base-stage cache mount).

## Hook Script Patterns

### Pattern A: Resolve + Fetch + Extract

The most common pattern for downloading and installing binary dependencies:

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

### Pattern B: Thin Inheritable Wrapper

Most inheritable hooks delegate to a single tool:

```bash
#!/usr/bin/env bash
  read-lineage
```

```bash
#!/usr/bin/env bash
  check-ports
```

### Pattern C: Compile-from-Source

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

### Pattern D: Conditional Downstream (Inheritable user hooks)

Auto-detect and act based on project files:

```bash
#!/usr/bin/env bash
  if [ -f composer.json ]; then
    b19-run "COMPOSER" "$(_ 'Install dependencies')" \
      -- composer install --no-interaction
  fi
```

### Pattern E: Idempotency Guard

Skip if already installed (important for inherited hooks):

```bash
#!/usr/bin/env bash
  command -v php-config >/dev/null 2>&1 && {
      b19-log note "PHP" "$(_ 'Already installed, skipping build')"
      return 0
  }
```

### Pattern F: Module Iteration

Iterate over dynamic dependency directories:

```bash
#!/usr/bin/env bash
  for MODULE_DIR in /deps/modules/*/; do
      [ -f "${MODULE_DIR}/build.sh" ] || continue
      . "${MODULE_DIR}/build.sh"
  done
```

## Creating a New Hook

1. Create the file at `.container/{stage}/build.d/{stage}/{pre|on|post}/{NNN}-{name}.sh`
1. Stage name must match the argument passed to `build-stage` in the Dockerfile
1. Choose the phase:
    - `pre/` -- runs before apt (repository setup, certs, detection)
    - `on/` -- central hooks (CPU detection, apt install)
    - `post/` -- runs after apt (tool install, compile, cleanup)
    - `always/{pre,post}` -- only for setup every stage of every downstream image needs
1. Pick an appropriate number from the convention table above
1. Make it inheritable (`.i.sh`) only if downstream images should inherit it
1. Use `b19-run` for all commands, avoid bare `RUN` logic

### Checklist for new hooks

- [ ] Stage directory name matches `build-stage` argument
- [ ] Number doesn’t conflict with existing hooks in same directory
- [ ] Uses `b19-run` for all commands (not raw commands)
- [ ] Sources `b19-i18n` if using `_()` or `_p()` translations
- [ ] Uses `--` separator in `b19-run` calls
- [ ] Named `.i.sh` only if meant to propagate to downstream images
- [ ] Idempotent if inheritable (may run in multiple stages)
- [ ] No hardcoded paths -- uses `B19_*` environment variables
- [ ] Translatable strings wrapped in `_()` or `_p(fmt, args...)`

## Environment Variables

Key variables available during build (set by Dockerfile `ENV` and `ARG`):

| Variable                 | Description                                             |
| ------------------------ | ------------------------------------------------------- |
| `STAGE`                  | Current stage name (set by `build-stage`)               |
| `ON`                     | `pre` or `post` (set by `process-hooks`)                |
| `B19_HOME`               | Application home directory (`/app`)                     |
| `B19_TEMP_PATH`          | Temporary directory (`/tmp`)                            |
| `B19_DEPS_PATH`          | Dependency metadata (`/deps`)                           |
| `B19_BUILD_PATH`         | Build hooks root (`/build.d`)                           |
| `B19_TOOLS_PATH`         | Tool scripts (`/tools.d`)                               |
| `B19_DOWNLOAD_PATH`      | Download cache directory                                |
| `B19_UID` / `B19_GID`    | User/group IDs                                          |
| `B19_USER` / `B19_GROUP` | User/group names                                        |
| `B19_VERBOSITY`          | Log level (default: `warn`, set to `warn` in final ENV) |
| `M6E_AI`                 | Set to `Y` in CI to suppress colors and hints           |
| `M6E_PROJECT`            | Project name (e.g., `ubuntu`)                           |
| `M6E_NAMESPACE`          | Namespace (e.g., `b19`)                                 |
| `TARGETARCH`             | Target architecture (`amd64`, `arm64`)                  |
| `NUMPROCS`               | Number of CPUs (set by `on/100-detect-cpu-count.i.sh`)  |

## Error Handling

- Hooks run with `set -eo pipefail` (inherited from `build-stage`)
- Each hook is wrapped in an ERR trap that logs the hook name and exit code
- A failing hook aborts the entire build
- Use `command -v tool || { return 0 }` for graceful skips
- Use `|| exit 9` as a hard-stop escape hatch (seen in `install-apt`)

## Interactions with Other Hook Runners

build.d is one of several numbered-hook runners in b19. They share the same
pattern (sorted sourcing, numeric prefixes) but serve different lifecycle
phases:

| Runner          | When                | Purpose                     |
| --------------- | ------------------- | --------------------------- |
| `build.d`       | Docker build time   | Install, compile, configure |
| `entrypoint.d`  | Container startup   | Runtime initialization      |
| `test.d`        | `make test`         | Validate the image          |
| `healthcheck.d` | Docker HEALTHCHECK  | Liveness/readiness          |
| `bootstrap.d`   | First container run | One-time initialization     |
| `command.d`     | On demand           | CLI commands                |
| `benchmark.d`   | On demand           | Performance benchmarks      |
| `shell.d`       | Interactive shell   | Bash session setup          |

## Gotchas

- **Stage name must match directory name**: `build-stage foundation` looks for hooks in `/build.d/foundation/`, not `/build.d/base/`
- **`always` is reserved**: `/build.d/always/{pre,post}` runs on *every* `build-stage` call, so a stage may not be named `always`
- **Hooks are sourced, not exec’d**: variables leak between hooks in the same stage -- this is by design but be aware of name collisions
- **Post-cleanup deletes regular hooks**: if you need a hook to survive to a later stage, name it `*.i.sh`
- **`install-apt` only runs for root**: the root guard is inside the
    `on/500-install-apt.i.sh` hook, meaning `user` stages skip APT installation entirely (and have no `on/` directory at all)
- **`b19-run` executes via `"$@"`**: always use `--` separator for commands to ensure proper argument handling
- **Pre-hooks set up state for on-hooks, on-hooks set up state for post-hooks**: e.g., `detect-apt-cacher` (pre) writes `/etc/apt/apt.conf.d/99proxy`,
    `install-apt` (on) uses the proxy, `clean-apt-cacher` (post) removes it
- **Hooks from COPY merge with existing**: downstream images add hooks alongside inherited `.i.sh` hooks -- both run in the same sorted sequence
- **`B19_VERBOSITY=warn` in final ENV**: build-time hooks see `info` by default (from ARG), but the final image sets `warn` -- this means `b19-log info` messages are visible during build but not at runtime
