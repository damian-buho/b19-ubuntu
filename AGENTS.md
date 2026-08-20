<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# b19/Ubuntu

Root of the entire b19 image tier. This is **two things in one repository**:

1. A concrete Ubuntu base image (digest-pinned, non-root, multi-series).
1. The shared **tool + hook library** that every downstream b19 image runs at build time and at container startup. Most of what lives here never executes for *this* image — it is baked in so children inherit it.

Read this file before editing; it states facts established from the source, not
just what the docs claim. Root conventions live in [../../AGENTS.md](../../AGENTS.md)
(B19\_\* series defaults, namespace layout, make orchestration) — not repeated here.

## What this image actually is

- `Dockerfile` `final` stage = `ubuntu@${B19_UBUNTU_HASH}` (pinned by **digest**, not tag → reproducible). The digest comes from
    `.container/foundation/deps/ubuntu/{series}.sha256.deps`.
- Binaries `fd`, `minijinja-cli` are **copied from sibling b19 images** (`b19/fd`, `b19/minijinja`) via multi-stage `FROM`, not apt. Those images must build first (tier ordering). `mold` comes via a pinned GitHub-release download (`b19-fetch`), not apt — see `deps/mold/`.
- Runs as `ubuntu` UID/GID **1000**, home `/app`. Root is only used during the
    `foundation` build stage.
- PID 1 is `tini -g`; entrypoint is `entrypoint.d`; healthcheck is `healthcheck.d`. These three are **inherited** by every child — children must not redefine them.
- `CMD` is intentionally **absent** (the Dockerfile comment warns against `sleep infinity`). Children set their own `CMD`.

## Build model (the core mechanism)

Two `RUN build-stage <name>` calls drive the whole build:

| Dockerfile call          | User     | Hook dir consumed                           |
| ------------------------ | -------- | ------------------------------------------- |
| `build-stage foundation` | root     | `.container/foundation/build.d/foundation/` |
| `build-stage user`       | uid 1000 | `.container/user/build.d/user/`             |

`build-stage` (`tools.d/build-stage`) sources `process-hooks` once per phase, in
order: **`always/pre` → `pre/` → `on/` → `post/` → `always/post`**. Within a
phase, scripts run in numeric order (`fd … | sort -zn`).

**`always` is a reserved stage name.** `build.d/always/{pre,post}` runs on
*every* `build-stage` call whatever the stage is called — the fleet uses ~20
names (`base`, `root`, `user`, `compile-go`, `fetch`, …), and a downstream image
may invent more. Setup that must hold for all of them (build-host CA trust)
lives there once instead of being copied per stage; `*.i.sh` makes it ride the
whole lineage. `B19_BUILD_ALWAYS_ENABLED=false` opts a stage out. `${STAGE}` is
the real stage inside these hooks, `${SCOPE}` the directory being run.

**The inheritance rule (most important fact in this repository):** after running a
phase, `process-hooks` *deletes* every `*.sh` **except** `*.i.sh`. So:

- `*.sh` hooks = run once for the current image, then gone. Use for one-off setup (install apt, locales, create user, install mold/fd, cleanup).
- `*.i.sh` hooks = **inheritable**; they survive into the image layer. Foundation seeds them into `build.d/base/`, `build.d/root/`, and `build.d/user/` so a downstream image that does `COPY .container/base/ /` + `RUN build-stage base` re-runs them automatically. See `scaffold/Dockerfile.template` for the downstream pattern (it consumes the `base` stage, not `foundation`).

Consequence: `build.d/foundation/` is where *this* image is assembled;
`build.d/{base,root,user}/` is the library *children* execute. Put reusable build
logic in `*.i.sh` under base/root/user; put image-local logic in `*.sh` under
foundation.

## Runtime lifecycle

`tini -g` → `entrypoint.d` runs numbered hooks from `.container/user/entrypoint.d/`:
set-signals → load-secrets → set-cpu-count → check-ports → print-lineage →
copy-overlay → parallel-j2 (render `.j2`) → run-command → validate-secrets →
bootstrap → start → finalize. A bare `docker run img <cmd>` short-circuits to run
the command directly. Every stage and hook is toggleable at runtime via `B19_*`
env (no rebuild) — see [docs/features.d/feature-toggles.md](docs/features.d/feature-toggles.md).

## The runner family (one pattern, eight runners)

All lifecycle subsystems are the *same* numbered-script runner: drop a numbered
`*.sh` into the dir, it is auto-discovered, sorted, and executed; layers merge via
overlay. Runners: `entrypoint.d`, `healthcheck.d`, `test.d`, `bootstrap.d`,
`build.d`, `benchmark.d`, `report.d`, `shell.d`. Overview:
[docs/features.d/runner-family.md](docs/features.d/runner-family.md).

## Directory map

```text
.container/
  foundation/            # root-stage payload, COPYed to / then `build-stage foundation`
    tools.d/             # the b19 CLI library (on PATH in every image) — see below
    build.d/
      foundation/        # *.sh: assemble THIS image (apt, locales, user, mold…)
      base/ root/        # *.i.sh: inheritable build hooks for downstream stages
    command.d/ etc/ locale/ overlays/ deps/
  user/                  # uid-1000 payload, COPYed to / then `build-stage user`
    entrypoint.d/ healthcheck.d/ bootstrap.d/ test.d/
    benchmark.d/ report.d/ shell.d/
    build.d/user/        # *.i.sh: inheritable user-stage build hooks
    app/                 # .signals, .forbidden-ports.txt
docs/                    # deep references (see index below)
docs/features.d/         # one capability per file, user-facing framing
scaffold/                # Dockerfile.template + deps skeleton for new downstream images
reports/                 # lint/scan/bridge outputs (generated; do not hand-edit)
.makefile/               # m6e submodules: core, b19, container (build framework)
```

## tools.d — the b19 CLI library

These are on `PATH` (`/tools.d`) in this and every downstream image. Prefer them
over raw shell so logging, i18n, caching, and offgrid guards apply uniformly:

- `b19-log <level> <tag> [msg]` — leveled (error/warn/info/debug), color-aware, honors `NO_COLOR`. [docs](docs/how-to/use-b19-log.md)
- `b19-run <tag> <msg> -- <cmd>` — timed wrapper; success output hidden unless verbose, failure always shown. [docs](docs/how-to/use-b19-run.md)
- `b19-exec [opts] -- <cmd>` — long-running services; routes stdout/stderr through the logger, tracks PID for signal forwarding. [docs](docs/how-to/use-b19-exec.md)
- `b19-fetch <tag> <url> <file> [sha512]` — three-tier cached download (`.fetch/` → BuildKit cache → aria2c), SHA-512 verified, offgrid-aware. [docs](docs/how-to/use-b19-fetch.md)
- `b19-i18n` — sourced to get `_()` / `_p()` gettext helpers (TEXTDOMAIN `b19`).
- `build-stage`, `process-hooks` — the build hook engine described above.
- `trust-ca-certificates install|remove` — trusts the build host’s CA bundle for one build stage. [docs](docs/how-to/use-b19-fetch.md)
- `b19-load-secrets` / `b19-exec-with-secrets`, `b19-resolve-dep`,
    `read-lineage`/`write-lineage`, `detect-cpu-count`, `check-ports`,
    `install-apt`, `j2-render`/`parallel-j2`/`save-j2`, `keyscan`, `setup-ssh`.

## Non-obvious facts / gotchas

- **CLAUDE.md → AGENTS.md.** `CLAUDE.md` is just `@AGENTS.md`; edit this file.
- **Multi-series matrix.** Builds across `B19_UBUNTU_SERIES` ∈ {`resolute`, `noble`} (`projectfile.yaml` → `org.projectfile.ci.matrix`). Image name is series-qualified: `b19/ubuntu/<series>`. Anything series-specific belongs in
    `deps/ubuntu/<series>.*` or `.j2` templates, never hardcoded.
- **deps are declarative.** Add a `*.deps` file under the right `deps/` path and the m6e build auto-discovers it (URL/version/SHA-512, arch-aware) — no Makefile edit. [docs/how-to/use-dependencies.md](docs/how-to/use-dependencies.md).
- **`b19-resolve-dep` clobbers.** It always writes the same `M6E_UPSTREAM_VERSION` / `M6E_UPSTREAM__*` names, and hooks are SOURCED in one shell, so the last `eval` in the stage wins. A hook that reads those values MUST `eval "$(b19-resolve-dep <name>)"` itself — an earlier hook’s resolve is not yours. Silent when the value only feeds a `-X` ldflag: the linker drops an unknown target and the binary keeps its default.
- **A hook child that reads stdin starves the hook list.** `process-hooks` feeds its `while read` loop from a process-substitution pipe on fd 0, and `b19-run` passes stdin through — a child like `npm` that drains stdin (r8e/shields: `npm run build`/`npm prune`) consumes the queued hook paths, so every hook after it silently never runs and the stage still exits 0. Guard such calls with `< /dev/null` in the hook.
- **i18n is mandatory.** User-facing strings go through `_()`/`_p()`; update
    `.container/{stage}/locale/*.pot|*.po` (es, uk). Don’t add English-only output.
- **offgrid is real.** `B19_OFFGRID_MODE=Y` must stay honored: any new network access needs a guard + cache path. Reference: [use-offgrid](docs/how-to/use-offgrid.md).
- **No certificate lives in this repository.** Trust for a privately fronted near cache comes from the build host via `M6E_CA_CERTIFICATES`, rides the `fetch` build context, and is dropped again inside the same `RUN` — see [docs/how-to/use-b19-fetch.md](docs/how-to/use-b19-fetch.md). Never commit a `.crt` here or bake one into a layer: it is environment data, it reaches only one image lineage, and it silently expires with the issuing proxy.
- **`setup-docker-sources` arms a test.** Adding the Docker apt repository also renames `/test.d/0900-docker-connect.sh.disabled` to `.sh`, so every downstream image that ships the Docker CLI asserts `docker system info` at `make container-test` time. In CI there is no host socket: such a project MUST give `.compose/pipeline.yaml` a `d9t/dind` sidecar, or that test fails.
- **Defaults live in the Dockerfile** `ENV`/`ARG` block — not in templates (root rule: no duplicate defaults). The Dockerfile `ENV` is the source of truth for every `B19_*` runtime default; [docs/how-to/configure-environment.md](docs/how-to/configure-environment.md) documents them.
- **`reports/` is generated.** Treat as build output.
- Defaults you’ll rely on: home `/app`, prefix `/usr/local`, temp `/tmp` (tmpfs during build), parallelism via `NUMPROCS`, XDG paths under `/app`, build download cache under `/var/cache/b19`.
- **Keep `--mount=type=cache` targets out of `${B19_HOME}`, and never `chown -R` / `chmod -R` the home from a build hook.** buildah `--layers` ≤1.42 ([#6747](https://github.com/containers/buildah/issues/6747), fix PR [#6981](https://github.com/containers/buildah/pull/6981) unmerged) restores the mtime of the directory that holds a cache mount when it removes that mount. The differ then reads the directory as unchanged and omits its tar entry, but it still writes the changed children. Extraction gives the orphaned parent `root:root 755`, and the next stage cannot write its own home. Measured on 1.42.1, with a cache mounted below the home: a new **file** directly in the home is safe; a change to a **pre-existing** file in the home triggers it; a new **directory** inside a pre-existing subdirectory triggers it as well. `b19-prepare-volumes` does the last one, so a plain `mkdir -p` is enough to trigger it — a recursive `chown` is not necessary. `${B19_DOWNLOAD_PATH}` sits under `${B19_CACHE_PATH}` to keep the home clear of cache mounts.
- **A posture heal inside that RUN is a no-op** (measured, 1.42.1): the values already match, buildah restores the directory mtime on mount cleanup, and its tar filter drops the pulled-up parent regardless. A separate `RUN` step re-asserts it, and so does a commit outside the build — the latter is what the post-build `M6E_BUILDAH_HEAL` in the buildah backends does, so shipped images and `test.d` stay correct.

## Docs index

How-to articles live in `docs/how-to/`, one per `docs/features.d/` fragment —
the fragment is the pitch, the article is the guide (fragment stem `x.md` pairs
with `docs/how-to/use-x.md`). Read the matching one before touching a subsystem:

- Build time: [use-build.d](docs/how-to/use-build.d.md) · [use-dependencies](docs/how-to/use-dependencies.md) · [use-apt-cache](docs/how-to/use-apt-cache.md) · [use-pinned-base](docs/how-to/use-pinned-base.md)
- Runtime: [use-entrypoint.d](docs/how-to/use-entrypoint.d.md) · [use-bootstrap.d](docs/how-to/use-bootstrap.d.md) · [use-healthcheck.d](docs/how-to/use-healthcheck.d.md) · [use-test.d](docs/how-to/use-test.d.md)
- Command-line tools: [use-b19-log](docs/how-to/use-b19-log.md) · [use-b19-run](docs/how-to/use-b19-run.md) · [use-b19-exec](docs/how-to/use-b19-exec.md) · [use-b19-fetch](docs/how-to/use-b19-fetch.md) · [use-tools](docs/how-to/use-tools.md)
- Platform: [configure-environment](docs/how-to/configure-environment.md) — every `B19_*` var, start here · [use-runner-family](docs/how-to/use-runner-family.md) · [use-signals](docs/how-to/use-signals.md) · [use-secrets](docs/how-to/use-secrets.md) · [use-cpu-detection](docs/how-to/use-cpu-detection.md) · [use-lineage](docs/how-to/use-lineage.md) · [use-xdg-paths](docs/how-to/use-xdg-paths.md) · [use-non-root](docs/how-to/use-non-root.md)
- Configuration: [use-templating](docs/how-to/use-templating.md) · [use-overlays](docs/how-to/use-overlays.md) · [use-i18n](docs/how-to/use-i18n.md) · [use-offgrid](docs/how-to/use-offgrid.md) · [use-port-validation](docs/how-to/use-port-validation.md) · [use-shell-hooks](docs/how-to/use-shell-hooks.md)
- [MAKEFILE.md](docs/how-to/MAKEFILE.md) — available make targets (or run `make help`).

Per-capability summaries (the "what does this give me" view) live in
[docs/features.d/](docs/features.d/): one short fragment per feature, assembled
into `FEATURES.md`, each pairing with its how-to article above.
