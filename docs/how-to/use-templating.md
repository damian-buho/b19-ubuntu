<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Render templates with minijinja

Every b19 image ships **minijinja-cli** — a standalone Rust binary providing Jinja2-compatible rendering — plus a discovery pipeline: drop `*.j2` files under `${B19_HOME}` and they are discovered at build time and re-rendered at every container start. The pitch: [Jinja2 templating](../features.d/templating.md).

Template files have the `.j2` suffix; the output filename is the template name minus `.j2`.

## When to use

- Configuration that must follow the environment: per-instance ports, hosts, toggles — render at every startup.
- Files resolvable only during build (APT sources, series-dependent package lists) — render in a build hook instead.

## Quick start

```text
.container/user/app/config.yaml.j2
```

```text
# config.yaml.j2 — every container ENV var is available as ENV.NAME
listen: {{ ENV.MY_SERVICE_PORT }}
home: {{ ENV.B19_HOME }}
```

That is the whole integration: the inheritable `820-save-j2.i.sh` hook discovers the template at build time, and the `1000-parallel-j2.sh` entrypoint hook renders it at every start. No hooks of your own.

## How it works

### Engine

| Item         | Value                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------ |
| Binary       | `/usr/local/bin/minijinja-cli`                                                             |
| Source image | `b19/minijinja` (built on `b19/rust-musl`, statically linked)                              |
| Version      | Pinned in `b19/minijinja/.container/compile-rust/deps/cargo.deps`                          |
| Bootstrap    | `ubuntu` COPY’s it from `b19/minijinja`; initial bootstrap: `B19_MINIJINJA_VERSION=latest` |

### The three tools

Three shell tools in `.container/foundation/tools.d/` form the rendering pipeline.
All downstream images inherit them.

#### `j2-render` — render one template

```bash
j2-render <path/to/file.ext.j2>
```

- Strips `.j2` suffix for output: `file.ext.j2` → `file.ext` (same directory)
- Calls `minijinja-cli --autoescape none --env` — all container ENV vars available as `ENV.VAR_NAME`
- Optional companion: `file.ext.data.json` — merged as extra context if present
- Used internally by `parallel-j2` via `xargs -P`

#### `save-j2` — discover templates and render

```bash
save-j2 <directory>
```

- Scans `<directory>` recursively for `*.j2` files via `fd`
- Writes sorted list to `<directory>_.j2.list`
- Respects `B19_J2_EXCLUDE_PATTERNS` (space-separated dir names, e.g. `venv node_modules`)
- Immediately calls `parallel-j2` to render everything found

#### `parallel-j2` — parallel rendering engine

```bash
parallel-j2 [--final] <directory>
```

- Reads `<directory>/.j2.list` and renders each template via `xargs -P "${NUMPROCS:-4}" j2-render`
- Skips entirely if `B19_IMMUTABLE=Y` (production-locked images)
- Skips if `minijinja-cli` is not installed (warns)
- Filters out templates listed in `B19_J2_SKIP_FILES` (comma-separated basenames, e.g. `robots.txt,nginx.conf`)
- `--final`: after rendering, deletes every rendered `.j2` file and its `.data.json` companion, then removes the `.j2.list` itself — skipped templates are not deleted

### Two rendering lifecycles

#### Build-time rendering

For templates that must be resolved during image build (APT sources, package lists,
installers). Variables come from Docker `ARG`/`ENV` and files sourced into the
build hook environment.

**Mechanism**: Build hook calls `minijinja-cli --autoescape none --env` directly or via `save-j2`.

**Examples**:

| Project      | Hook                                       | Template                                 | Why build-time                            |
| ------------ | ------------------------------------------ | ---------------------------------------- | ----------------------------------------- |
| `b19/ubuntu` | `foundation/pre/200-setup-sources.sh`      | `ubuntu.sources.j2`                      | APT sources needed for `apt-get install`  |
| `b19/gcc`    | `base/pre/200-setup-sources.sh`            | `common.apt.deps.j2`                     | Package list depends on `B19_GCC_SERIES`  |
| `b19/llvm`   | `base/pre/200-setup-sources.sh`            | `llvm.sources.j2` + `common.apt.deps.j2` | APT repository + package list             |
| `b19/zig`    | `compile-llvm/pre/200-render-templates.sh` | `common.apt.deps.j2`                     | Package list depends on `B19_LLVM_SERIES` |

**Pattern** (typical build hook):

```bash
. /etc/lsb-release          # provides DISTRIB_CODENAME
minijinja-cli --autoescape none --env "${J2_FILE}" -o "${OUTPUT_FILE}"
rm "${J2_FILE}"             # cleanup template after rendering
```

#### Runtime rendering

For configuration files that should be configurable per container instance.
Templates are discovered at build time (`.j2.list` saved), then re-rendered
at every container start.

**Mechanism**: Entrypoint hook calls `parallel-j2 ${B19_HOME}`.

**Flow**:

```text
BUILD TIME                              RUN TIME (every start)
─────────                              ──────────────────────
820-save-j2.sh (foundation)             1000-parallel-j2.sh (entrypoint)
820-save-j2.i.sh (user, inheritable)        |
    |                                       v
    v                                   parallel-j2 ${B19_HOME}
save-j2 ${B19_HOME}                        |
save-j2 ${B19_TEST_PATH}                   v
    |                                   Reads .j2.list
    v                                   Renders all templates
.j2.list files written
```

**Entrypoint hook** (`.container/user/entrypoint.d/1000-parallel-j2.sh`):

```bash
. parallel-j2 "${B19_HOME}"
```

**Inheritable build hooks**:

| File                                                | Scope                                      |
| --------------------------------------------------- | ------------------------------------------ |
| `foundation/build.d/foundation/post/820-save-j2.sh` | foundation stage only                      |
| `user/build.d/user/post/820-save-j2.i.sh`           | inheritable — all downstream `user` stages |

This means **any image inheriting from b19/Ubuntu automatically gets**:

- Template discovery at build time
- Template rendering at every container startup
- No extra configuration needed — just drop `.j2` files into `${B19_HOME}`

## Template syntax

minijinja is Jinja2-compatible. With `--env`, all environment variables are
accessible through the `ENV` object.

### Variable access

```text
{{ ENV.VARIABLE_NAME }}                              # dot notation
{{ ENV["PREFIX_" ~ ENV.TARGETARCH | upper] }}        # dynamic key + concat
{{ ENV.B19_HOME ~ "/dynamic" }}                      # string concatenation with ~
```

### Auto-escaping is disabled

All `minijinja-cli` invocations use `--autoescape none`. Quoting and escaping
are the template author’s responsibility — no implicit HTML/JSON encoding.

This avoids subtle bugs where minijinja’s `auto` mode (which strips `.j2` and
checks the base extension) would silently JSON-quote values in `.json.j2`
templates or HTML-encode values in `.html.j2` templates.

### JSON templates: explicit quoting

For `.json.j2` templates, string values must be explicitly quoted:

```text
"name": "{{ ENV.MY_SERVICE_NAME }}",                 # string — quoted
"port": {{ ENV.MY_PORT | int }},                     # number — unquoted
"enabled": {{ ENV.MY_FLAG | bool }},                 # boolean — unquoted
"url": "{{ "https://" ~ ENV.HOST ~ ":" ~ ENV.PORT }}",  # concatenation — quoted
```

Do **not** use `| safe` — it is a no-op with auto-escaping disabled.

### String concatenation with `~`

The `~` operator concatenates strings inline:

```text
{{ ENV.B19_HOME ~ "/config/app.yaml" }}              # simple path join
{{ "prefix-" ~ ENV.MY_VAR ~ "-suffix" }}              # multi-part concat
{{ ENV["PREFIX_" ~ (ENV.TARGETARCH | upper)] }}        # dynamic key lookup
{%- set _url = ENV.O9S_HOST ~ ":" ~ ENV.O9S_PORT ~ "/api" -%}
{{ _url }}                                             # capture in variable
```

### Filters

```text
{{ ENV.KAFKA_BROKER_ID | int }}                      # cast to integer
{{ ENV.O9S_ALERTMANAGER_WEBHOOK_SEND_RESOLVED | bool }}  # cast to boolean
{{ ENV.TARGETARCH | upper }}                         # uppercase
{{ ENV.O9S_NGINX_ROBOTS_TXT_DEFAULT_POLICY | default("disallow") }}  # fallback
```

### Conditionals

```text
{% if ENV.O9S_TRAEFIK_MODE == "SELF-SIGNED" %}
  tls: true
{% else %}
  tls:
    certresolver: acme
{% endif %}
```

### Defined check

```text
{% if ENV.VAR is defined and ENV.VAR != "" %}...{% endif %}
```

### Set blocks (variables)

```text
{%- set _log_levels = {
    "error": "error",
    "warn":  "warn",
    "info":  "info",
    "debug": "debug"
} %}
error_log /dev/stderr {{ _log_levels[ENV.B19_VERBOSITY] | default("warn") }};
```

### Ternary

```text
{{ "reuseport" if ENV.O9S_NGINX_LISTEN_REUSEPORT == "Y" else "" }}
```

### List construction + join

```text
{%- set _parts = [
    "key1=" ~ ("yes" if ENV.FLAG_A | default("N") == "Y" else "no"),
    "key2=" ~ ("yes" if ENV.FLAG_B | default("N") == "Y" else "no"),
] -%}
{{ _parts | join(", ") }}
```

### Comments

```jinja2
{#- This is a comment -#}
```

### Loops

```jinja2
{% for item in list %}...{% endfor %}
```

## Directory layout

Templates live alongside their intended output, with `.j2` appended:

```text
.container/{stage}/
├── app/
│   ├── config.yaml.j2 → config.yaml
│   ├── nginx.conf.j2 → nginx.conf
│   └── etc/
│       ├── includes/**/*.nginx.j2
│       └── php/conf.d/*.ini.j2
├── deps/
│   ├── common.apt.deps.j2 → common.apt.deps
│   └── extensions/{name}/50-{name}.ini.j2
└── test.d/
    ├── 0100-check-version.sh.j2 → 0100-check-version.sh
    └── 2100-phar-version.j2 → 2100-phar-version
```

## Adding templates to a project

### Runtime templates (most common)

1. Place `*.j2` files anywhere under `${B19_HOME}` (typically `.container/user/app/`)
1. The inheritable `820-save-j2.i.sh` hook discovers them at build time
1. The `1000-parallel-j2.sh` entrypoint hook renders them at startup
1. No extra hooks needed — it just works

### Build-time templates

1. Place the `.j2` template in the appropriate location
1. Create a build hook at `.container/{stage}/build.d/{stage}/{pre,post}/NNN-name.sh`
1. Call `minijinja-cli --env` or `save-j2` from that hook
1. Clean up `.j2` files after rendering if not needed at runtime

### Excluding directories

Set `B19_J2_EXCLUDE_PATTERNS` in the Dockerfile or Makefile:

```bash
ENV B19_J2_EXCLUDE_PATTERNS="venv node_modules .cache"
```

### Skipping specific files at runtime

Set `B19_J2_SKIP_FILES` to prevent specific templates from being rendered at startup. The value is a comma-separated list of basenames (without `.j2`):

```bash
ENV B19_J2_SKIP_FILES="robots.txt,nginx.conf"
```

This is useful when a downstream image ships its own version of a file that the base image also templates. For example, `o9s/nginx` ships `robots.txt.j2` as a fallback, but a project that builds its own `robots.txt` via Astro can set `B19_J2_SKIP_FILES=robots.txt` to keep the build-time version.

## Companion data files (optional)

`j2-render` checks for `<template>.data.json` alongside each `.j2` file.
If present, it is passed as additional context to minijinja-cli.

Currently unused across the ecosystem but available for complex templates
that need structured data beyond flat ENV vars.

## Immutable mode

When `B19_IMMUTABLE=Y`, `parallel-j2` skips rendering entirely.
Use this for production images where all config should be baked in at build time.

## Quick reference

```bash
# Render a single template manually
minijinja-cli --autoescape none --env template.j2 -o output.conf

# Render all templates in a directory
save-j2 /path/to/dir

# Check what templates will be rendered
cat /path/to/dir/.j2.list

# Test rendering with a specific variable
B19_VERBOSITY=debug minijinja-cli --autoescape none --env template.j2
```

## Troubleshooting

| Symptom                                  | Cause             | Fix                                                                            |
| ---------------------------------------- | ----------------- | ------------------------------------------------------------------------------ |
| Template not rendered at startup         | Not in `.j2.list` | Check `820-save-j2` hook ran at build time; ensure file is under `${B19_HOME}` |
| Template rendered but should be skipped  | Not configured    | Set `B19_J2_SKIP_FILES` (see below)                                            |
| `minijinja-cli not installed, skipping`  | Binary missing    | Image must inherit from `b19/ubuntu` (or copy binary from `b19/minijinja`)     |
| `B19_IMMUTABLE=Y, skipping j2 templates` | Intentional lock  | Remove `B19_IMMUTABLE=Y` or pre-render at build time                           |
| Variable renders empty                   | ENV var not set   | Check Dockerfile `ENV` or runtime env; use `\| default("fallback")`            |
| Dynamic key `ENV["PREFIX_" ~ VAR]` fails | Filter precedence | Use parentheses: `ENV["PREFIX_" ~ (ENV.TARGETARCH \| upper)]`                  |
| ALL templates silently keep build-time   | A binary (non-    | `b19-load-secrets` must skip it; a binary secret exported as an env var makes  |
| defaults; `thread 'main' panicked` in    | UTF-8) Docker     | `minijinja --env` panic while iterating the env, aborting every render. Read   |
| logs (`std::env`)                        | secret in the env | binary secrets from `/run/secrets/<name>` instead — never from an env var.     |
