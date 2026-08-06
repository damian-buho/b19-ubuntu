<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# b19-i18n — Internationalization

Shell-level GNU gettext integration for all b19-derived images.

## Overview

Provides `_()` and `_p()` translation functions backed by GNU gettext `.mo` catalogs.
All projects share a single `TEXTDOMAIN` (`b19`) — their translations are merged at build
time into a unified `b19.mo` catalog per language. Each project ships its own `.po` files,
and the compile step merges parent+child layers additively.

**Languages**: `en` (source), `es` (`es_ES`), `uk` (`uk_UA`)

## Usage

```bash
# Static string
b19-log good "TAG" "$(_ "Starting server")"

# String with variable substitution — use _p() with %s placeholders
b19-run "TAG" "$(_p "Make %s directory" "${LOCAL_PATH}")" -- mkdir -p "${LOCAL_PATH}"

# Multiple substitutions
b19-log info "TAG" "$(_p "Scanning key of %s port %s to %s" "${HOST}" "${PORT}" "${FILE}")"
```

**Never** concatenate translated atoms with raw variables:

```bash
# WRONG — variables cannot reorder across languages
b19-run "TAG" "$(_ "Make") ${LOCAL_PATH} $(_ "directory")" ...

# CORRECT — translator can place %s anywhere in the string
b19-run "TAG" "$(_p "Make %s directory" "${LOCAL_PATH}")" ...
```

## Functions

### `_()` — static string

```bash
$(_ "String to translate")
```

For strings with no variable parts. Looks up the msgid in `TEXTDOMAIN` (`b19`).

### `_p()` — string with printf-style substitution

```bash
$(_p "String with %s placeholder" "${value}")
$(_p "Two placeholders: %s and %s" "${a}" "${b}")
```

Translators can reorder `%s` within the sentence to match natural phrasing in the
target language. Always use `_p()` instead of concatenating `_()` with variables.

### `_e()` — deprecated

`_e()` (eval_gettext with `${VAR}` expansion) is no longer used. All existing `_e()`
calls have been converted to `_p()`. Do not add new `_e()` calls.

## Sourcing Rules

| Script location                   | How it runs                    | Rule                                        |
| --------------------------------- | ------------------------------ | ------------------------------------------- |
| `entrypoint.d/*.sh`               | sourced by runner              | inherit `_()` — do **not** add `. b19-i18n` |
| `healthcheck.d/*.sh`              | sourced in subshell by runner  | inherit `_()` — do **not** add `. b19-i18n` |
| `report.d/*.sh`                   | sourced by runner              | inherit `_()` — do **not** add `. b19-i18n` |
| `build.d/**/*.sh`                 | sourced by build-stage         | inherit `_()` — do **not** add `. b19-i18n` |
| `test.d/*.sh`                     | subprocess (executed directly) | **must** add `. b19-i18n` at top            |
| `command.d/*`                     | subprocess (executed directly) | **must** add `. b19-i18n` at top            |
| standalone executables (no `.sh`) | subprocess                     | **must** add `. b19-i18n` at top            |

The runner for each directory sources `b19-i18n` once. Sourced scripts inherit both
`TEXTDOMAIN` and the `_()` family automatically. Subprocesses start a new shell and lose
this context — they must re-source explicitly.

## Variables

| Variable           | Default                                         | Description                                                      |
| ------------------ | ----------------------------------------------- | ---------------------------------------------------------------- |
| `TEXTDOMAIN`       | `b19`                                           | Gettext domain — hardcoded in `b19-i18n`. Always `b19`.          |
| `TEXTDOMAINDIR`    | `/usr/share/locale`                             | Where compiled `.mo` catalogs live.                              |
| `B19_I18N_ENABLED` | `true`                                          | Set to `false` to disable translation (passthrough mode).        |
| `LANGUAGE`         | (operator-set, e.g. `es`)                       | Translation language; gettext fallback resolves catalogs.        |
| `B19_LOCALES`      | en_US, uk_UA, es_ES + 20 LATAM Spanish variants | Space-separated locales generated at build time via `localedef`. |
| `_B19_I18N_MODE`   | `gettext`                                       | Tracks current mode: `gettext`, `passthrough`, `disabled`.       |

## Architecture

### Shared TEXTDOMAIN model

All images — b19/Ubuntu and every child project — share `TEXTDOMAIN="b19"`. There is no
per-project textdomain. Instead, `b19-compile-i18n` merges `.po` files from all image
layers into a single `b19.mo` per language:

```text
/usr/share/locale/{lang}/LC_MESSAGES/b19.mo    ← merged catalog
/usr/share/locale/b19/{PROJECT}/es.po          ← per-project slot (intermediate)
/usr/share/locale/b19/{PROJECT}/uk.po          ← per-project slot (intermediate)
```

This means child images **inherit** all translated strings from parent layers automatically.
When the same msgid appears in both parent and child, the current image wins (`msgcat --use-first`).

### Build-time flow

```text
COPY .container/{stage}/ /    ← puts .po files into /locale/
build-stage {stage}           ← runs inherited 100-compile-i18n.i.sh
  └─ b19-compile-i18n
       ├─ cp /locale/*.po → /usr/share/locale/b19/${M6E_PROJECT}/
       ├─ collect all *.po across all slots
       ├─ msgcat --use-first (current slot wins conflicts)
       └─ msgfmt --check → /usr/share/locale/{lang}/LC_MESSAGES/b19.mo
```

### Runtime flow

```text
entrypoint.d (runner)
  └─ . b19-i18n
       ├─ export TEXTDOMAIN="b19"
       ├─ export TEXTDOMAINDIR=/usr/share/locale
       └─ . /usr/bin/gettext.sh
            └─ _() → gettext "$1"
               _p() → printf "$(gettext "$1")" "${@:2}"
```

`LANGUAGE` is left untouched (operator-controlled). gettext resolves it via its
own fallback chain: `LANGUAGE` > `LC_MESSAGES` > `LANG`.

### Three modes

| Mode          | Trigger                      | Behavior                                              |
| ------------- | ---------------------------- | ----------------------------------------------------- |
| `gettext`     | `/usr/bin/gettext.sh` exists | Full GNU gettext translation                          |
| `passthrough` | `gettext.sh` missing         | Strings pass through untranslated (early build stage) |
| `disabled`    | `B19_I18N_ENABLED=false`     | Strings pass through (opt-out)                        |

## Locale architecture (LANG vs LANGUAGE)

Two independent concerns are deliberately separated:

| Concern       | Variable   | Controls                            | Default                          | Mechanism                         |
| ------------- | ---------- | ----------------------------------- | -------------------------------- | --------------------------------- |
| OS formatting | `LANG`     | dates, numbers, collation, currency | `C.UTF-8` (ENV, always in glibc) | glibc locale data                 |
| Translations  | `LANGUAGE` | which message catalog gettext uses  | (unset → English passthrough)    | `.mo` catalogs + gettext fallback |

**`LANG=C.UTF-8` is the production-safe default** — English formatting, never
fails `setlocale()`. An operator switches to native formatting by setting
`LANG=es_ES.UTF-8`; the runtime guard validates it against generated locales.

**`LANGUAGE` selects translation display** — `LANGUAGE=es` makes b19 scripts,
system tools, and any gettext-aware program display Spanish messages. It works
independently of `LANG` (gettext’s own `LANGUAGE > LC_MESSAGES > LANG` fallback
resolves the catalog).

### Regional variants (es_CL, es_UY, …)

A Chilean and a Uruguayan share the same Spanish translation catalogs
(gettext falls back from `es_CL` to the bare `es` language level). But their
**formatting** differs: Chilean currency is `$` (CLP), Uruguayan is `$` (UYU),
Spanish is `€` (EUR). The curated `B19_LOCALES` set therefore includes **all**
Spanish variants (es_ES + 20 LATAM locales), not just es_ES — each gets correct
local formatting while sharing the single `es.po` translation catalog.

The runtime guard also does **language-level fallback**: if a locale isn’t
generated (e.g. a project trimmed `B19_LOCALES`), the guard resolves to any
available locale of the same language (`es_CL.UTF-8` → `es_ES.UTF-8`).

#### Adding a dialect translation (e.g. es_CL.po)

For dialect-specific wording (e.g. "bencina" vs "gasolina"), add a regional
`.po` file. gettext’s fallback chain merges it with the base language:
`es_CL.mo` (dialect) → `es.mo` (general, fills gaps):

```sh
make i18n-init LOCALE=es_CL    # creates es_CL.po from .pot template
# edit es_CL.po — translate only the dialect-specific entries
make build                      # b19-compile-i18n auto-discovers es_CL.po
```

No `B19_LOCALES` change needed — `es_CL.UTF-8` is already in the curated set.

## Project locale layout

### b19/Ubuntu (foundation stage)

```text
b19/ubuntu/.container/foundation/
├── locale/
│   ├── ubuntu.pot           ← msgid template (238 msgids)
│   ├── b19.pot              ← legacy template (pre-refactor, do not use)
│   ├── es.po                ← Spanish translations (232 msgids)
│   ├── uk.po                ← Ukrainian translations (232 msgids)
│   ├── es/                  ← compiled .mo (gitignored)
│   └── uk/                  ← compiled .mo (gitignored)
├── build.d/foundation/post/
│   └── 150-compile-i18n.sh  ← ubuntu's own compile hook
└── build.d/base/
    └── 100-compile-i18n.i.sh ← inheritable hook for "base" stage children
```

Note: b19/ubuntu’s locale directory is missing the standard `.gitignore` (`*.mo`)
that child projects have via scaffold. The `es/` and `uk/` subdirectories are
local compile artifacts.

### Child project (e.g. b19/node)

```text
b19/node/.container/base/
├── locale/
│   ├── .gitignore            ← *.mo
│   ├── node.pot              ← msgid template
│   ├── es.po                 ← Spanish translations
│   └── uk.po                 ← Ukrainian translations
└── build.d/                  ← no own compile hook needed
```

Child projects do **not** create their own compile hook — they inherit
`100-compile-i18n.i.sh` from b19/ubuntu’s foundation stage. The `.i.sh` suffix
marks it as "inheritable" (`process-hooks` does not delete it after execution).

When `COPY .container/base/ /` places the locale files into the image, and
`build-stage base` runs, the inherited hook fires and calls `b19-compile-i18n`.

### Stage mapping

| Project stage type | Compile hook source                                |
| ------------------ | -------------------------------------------------- |
| `foundation`       | b19/ubuntu’s own `150-compile-i18n.sh` (post)      |
| `base`             | Inherited `100-compile-i18n.i.sh` (pre)            |
| `root`             | Inherited `100-compile-i18n.i.sh` (pre)            |
| `compile-*`        | Inherited (if the compile stage uses `base` hooks) |

## Tools

### b19-i18n (sourced library)

**Path**: `.container/foundation/tools.d/b19-i18n` (57 lines)

Defines `_()`, `_p()`, `_e()` using GNU gettext. Must be sourced, not executed.

```bash
. b19-i18n
```

- Re-source guard: checks if `_` function already exists (shell functions don’t survive `exec` boundaries, so re-sourcing is safe and sometimes necessary).
- Never calls `b19-log` (would cause infinite recursion — `b19-log` sources `b19-i18n`).
- Falls back to passthrough mode when `gettext.sh` is not yet installed.

### b19-compile-i18n (executable)

**Path**: `.container/foundation/tools.d/b19-compile-i18n` (59 lines)

Compiles all `.po` files into merged `.mo` catalogs.

```bash
b19-compile-i18n [locale-dir]
# Default locale-dir: /locale
```

Uses `M6E_PROJECT` as the catalog slot name. The merge algorithm:

1. Copy current project’s `.po` files into `/usr/share/locale/b19/${M6E_PROJECT}/`
1. Discover all languages across all catalog slots
1. For each language: `msgcat --use-first` (current project first, then sorted others)
1. `msgfmt --check` → `/usr/share/locale/{lang}/LC_MESSAGES/b19.mo`
1. Exits with error if any compilation fails

### b19-generate-locales (sourced by build hook)

**Path**: `.container/foundation/tools.d/b19-generate-locales`

Compiles locales from `B19_LOCALES` via `localedef --no-archive` during the
downstream `base` stage (inherited `0600-generate-locales.i.sh`). Each locale
lands in `/usr/lib/locale/<locale>/` (~2.5MB each). No-op when `B19_LOCALES` is
empty. The `locales` apt package (source data) is installed in the foundation
stage, so `localedef` can compile any locale without re-downloading.

### b19-ensure-locale (sourced by entrypoint)

**Path**: `.container/foundation/tools.d/b19-ensure-locale`

Runtime guard (entrypoint `0050-ensure-locale.sh`) that validates `LANG`
against generated locales and falls back gracefully:

1. `LANG` is valid as-is → keep it
1. Same language, any region → fall back (`es_CL.UTF-8` → `es_ES.UTF-8`)
1. No match → `C.UTF-8` (always present in glibc)

This protects every derived image against invalid/empty `LANG` (the CI
`initdb: invalid locale settings` bug) and lets regional variants work from
the curated set without generating every country-specific locale.

## Makefile Targets (m6e)

The targets do **not** run gettext on the host: they dispatch to the
containerized `auto-i18n` wrapper shipped in `d9t/misc-tools`, which is
bind-mounted onto the project and reads/writes `.pot` / `.po` through the mount.
No host gettext install is required.

`i18n-extract` / `-update` / `-stats` / `-check` are **manifest tools** (defined
in `.makefile/container/ci.yaml`); the generic executor generates their
`make <target>` recipes — so, like `hadolint` / `reuse-lint`, they do **not**
appear in `make help` (this page is their reference). `i18n-init` is a hand
recipe in `.makefile/container/tools/i18n.mk` (it has a required `LOCALE=` arg).
Project/keyword/version knobs reach the container via exported `M6E_I18N_*`
(`--env` passthrough).

### Configuration variables

| Variable               | Default                                  | Description                                       |
| ---------------------- | ---------------------------------------- | ------------------------------------------------- |
| `M6E_I18N_DOMAIN`      | `$(PROJECT)`                             | `.pot` / `.po` stem                               |
| `M6E_I18N_KEYWORDS`    | `_:1 _e:1 _p:1` (set by the b19 bolt-on) | `xgettext --keyword` specs                        |
| `M6E_I18N_DIR`         | auto-discovered `.container/*/locale`    | Restrict to one locale directory                  |
| `M6E_I18N_SOURCE_DIRS` | hook dirs (see below)                    | Hook directories scanned for translatable strings |
| `TOOLS_I18N_IMAGE`     | `…/d9t/misc-tools:<ver>`                 | Image carrying the `auto-i18n` wrapper            |

The default `M6E_I18N_SOURCE_DIRS` mirrors the runtime sourcing-rules table:
`tools.d build.d entrypoint.d healthcheck.d command.d bootstrap.d benchmark.d report.d shell.d test.d`. Projects with a single locale directory scan the whole
`.container/` tree; multi-stage projects scan each owning stage separately.

### Targets

| Target                     | Description                                                                        |
| -------------------------- | ---------------------------------------------------------------------------------- |
| `make i18n-extract`        | Run `xgettext` (keywords from `M6E_I18N_KEYWORDS`) over all sources, writes `.pot` |
| `make i18n-init LOCALE=uk` | Create a new `.po` from `.pot` via `msginit`                                       |
| `make i18n-update`         | Merge `.pot` changes into existing `.po` files via `msgmerge`                      |
| `make i18n-stats`          | Show translation statistics per `.po` file                                         |
| `make i18n-check`          | Warn on fuzzy / untranslated `.po` entries; runs in CI (source-is-compliant)       |

There is no host-side compile target: `.po` → `.mo` is done inside the image by
`b19-compile-i18n` during `make build` (which also runs `msgfmt --check`).

### Host locale detection

m6e auto-detects the developer’s host `LANG` and passes it as a `B19_LOCALES`
build-arg when the matching `.po` file exists. This means `make build` on a
Spanish developer’s machine adds `es_ES.UTF-8` to the locale set generated
inside the container. `LANG` itself is fixed to `C.UTF-8` in the base image
(always present in glibc, never fails `setlocale`).

### Linting

- `msgfmt --check` runs automatically during `b19-compile-i18n` (build time). Catches syntax errors in `.po` files.
- `make i18n-check` warns on fuzzy / untranslated entries; it is also a CI node on the b19 publish gate (`source-is-compliant`), where it is **non-blocking** (warns, never fails). `make i18n-stats` shows per-language coverage.
- `shellcheck` SC1091 warnings about sourcing `b19-i18n` are expected — it is a runtime dependency from the base image, not a local file.

## .pot filename convention

Default: `{project}.pot` (e.g., `forgejo.pot`, `kafka.pot`, `node.pot`).

The scaffold creates `TEXTDOMAIN.pot` and renames it to `{PROJECT}.pot` during
project initialization. Some older projects have a secondary `{ns}-{project}.pot`
leftover from scaffold v1 — these are header-only and can be removed.

## Coverage (Apr 2026)

87 `.pot` files across 80+ projects. Every `.pot` has matching `es.po` and `uk.po`
with no gaps.

| Namespace | Projects                 | Translations |
| --------- | ------------------------ | ------------ |
| b19       | Ubuntu + 19 child images | es, uk       |

## Adding a New Project

Use the scaffold (creates locale directory automatically):

```bash
make scaffold
```

Or manually:

1. Create `.container/{stage}/locale/`:
    - `{project}.pot` — msgid template (can be empty initially)
    - `es.po` — Spanish translations
    - `uk.po` — Ukrainian translations
    - `.gitignore` — `*.mo`
1. No compile hook needed — the inherited `100-compile-i18n.i.sh` handles it
1. Wrap user-visible strings: `$(_ "...")` for static, `$(_p "... %s" "${var}")` for dynamic

## Adding Strings to an Existing Project

1. Wrap the string: `$(_ "My new message")` or `$(_p "My %s message" "${var}")`
1. Extract: `make i18n-extract` — updates the `.pot` with the new msgid
1. Update translations: `make i18n-update` — merges new msgids into `.po` files
1. Edit `.po` files — add translations for the new msgids
1. Verify: `make i18n-stats` — check coverage
1. Rebuild: `make build` — `b19-compile-i18n` compiles `.po` → `.mo` during build

The `.po` files are compiled to `.mo` at build time — no runtime overhead.

## Adding a New Language

1. `make i18n-init LOCALE=fr` — creates `fr.po` from `.pot` template

1. Add the locale to `B19_LOCALES` in the project’s `projectfile.yaml`:

    ```yaml
    org:
      projectfile:
        build:
          args:
            B19_LOCALES: "en_US.UTF-8 uk_UA.UTF-8 es_ES.UTF-8 es_CL.UTF-8 fr_FR.UTF-8"
    ```

    (extend the curated set — don’t replace it unless the project is locale-lean)

1. Edit `fr.po` — translate all msgid entries

1. Verify: `make i18n-stats`

1. Rebuild: `make build`

Note: `B19_LOCALES` controls which locales `localedef` generates at build time.
For translations to display, set `LANGUAGE=fr` at runtime (gettext catalog
selection is independent of the generated locale). Adding a regional variant
of an existing language (e.g. `fr_CA`) only needs the locale in `B19_LOCALES` —
no new `.po` file required (gettext falls back `fr_CA → fr`).

## Common Bugs

### Strings not translating at runtime

- Check `LANGUAGE` is set to the translation language (e.g., `LANGUAGE=es` → `es.po`)
- Check the locale is generated: `locale -a | grep es` (needs `B19_LOCALES` to include it)
- Check `B19_I18N_ENABLED` is not `false`
- Check `TEXTDOMAIN` is `b19` (`echo $TEXTDOMAIN` inside container)
- Check `msgfmt --check es.po` passes without errors

### Missing compile hook

Child projects should NOT have their own compile hook. The inherited `.i.sh` hook
from b19/Ubuntu handles compilation. If translations aren’t compiling, check that
the project’s Dockerfile runs `build-stage {stage}` after `COPY .container/{stage}/ /`.

### Outdated .pot / .po files

Run `make i18n-extract` to regenerate the `.pot` from source, then `make i18n-update`
to merge changes into `.po` files. New msgids appear as `msgstr ""` (untranslated).

### msgfmt compilation errors

`msgfmt --check` is strict about `.po` syntax. Common issues:

- Mismatched `%s` count between `msgid` and `msgstr`
- Missing or extra `msgstr` lines
- UTF-8 encoding issues

Run `msgfmt --check --statistics {lang}.po` locally to diagnose.

### Legacy b19.pot in b19/Ubuntu

`b19.pot` is a pre-refactor artifact with old `.docker/` path references. The
current template is `ubuntu.pot`. Do not use or update `b19.pot`.
