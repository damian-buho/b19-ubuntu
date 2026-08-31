<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Jinja2 configuration templates (minijinja-cli)

- Jinja2-compatible template rendering at both build time and container startup.
- Drop a `.j2` file anywhere in the app directory; it is discovered at build time and rendered at every startup with all environment variables available.
- Runtime rendering is parallel and automatic — downstream images get it with zero configuration.
- Skip specific templates at runtime with `B19_J2_SKIP_FILES` (comma-separated basenames).
- Immutable mode (`B19_IMMUTABLE=Y`) locks the filesystem to build-time state, skipping all runtime rendering.
