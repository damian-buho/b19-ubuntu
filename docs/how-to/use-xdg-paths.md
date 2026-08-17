<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Use the XDG paths

The four XDG Base Directory variables point under the app home, pre-created and owned by the runtime user — anything honoring the spec writes where the non-root user already has permission, no sudo, no scattered dotfiles. The pitch: [XDG Base Directory paths](../features.d/xdg-paths.md).

## When to use

- Any tool state, cache or config your service writes: use the variables, never `/root`, never `/var/lib`.
- Volume mounts for caches and data: they anchor cleanly under `/app`.

## Quick start

```text
XDG_CACHE_HOME  = /app/.cache
XDG_CONFIG_HOME = /app/.config
XDG_DATA_HOME   = /app/data
XDG_STATE_HOME  = /app/.state
```

In hooks and scripts, just use the variables: `"${XDG_DATA_HOME}/uploads"`, `"${XDG_CACHE_HOME}/npm"`.

## How it works

Set once in the Dockerfile `ENV` block, anchored at `B19_HOME=/app`. One deliberate divergence from the spec: `XDG_DATA_HOME` is `/app/data`, **not** `.local/share` — the flat, obvious mount point downstream volumes target.

The foundation permissions hook pre-creates all four and chowns them to `${B19_UID}:0`, so the very first write by the runtime user succeeds. Consumers across the image:

- `B19_BOOTSTRAP_LOCK_PATH=${XDG_DATA_HOME}/.bootstrap` — the run-once lockfiles
- The cache-space healthcheck watches `XDG_CACHE_HOME` free space
- The cache-writability test asserts `-w "${XDG_CACHE_HOME}"`
- Host-side cache binds land here: `- ~/.cache/npm:/app/.cache/npm`

Because everything writable sits under `/app`, the whole home can be a volume, and the [non-root](use-non-root.md) user owns it end-to-end.

## Recipes

```yaml
# compose: persistent, user-owned caches
volumes:
  - cache:/app/.cache
  - data:/app/data
```

```bash
# Declare writable dirs at build time (parent-of-mount case)
# .container/user/build.d/volumes.deps
${XDG_DATA_HOME}/uploads
${XDG_CACHE_HOME}/npm
```

## See also

- [Run as a non-root user](use-non-root.md) — the ownership model behind these paths
- [Initialize state once with bootstrap.d](use-bootstrap.d.md) — locks under `XDG_DATA_HOME`
