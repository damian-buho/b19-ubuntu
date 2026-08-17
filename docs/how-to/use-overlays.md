<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Ship files with overlays

An overlay is a directory of files baked into the image but applied only at container startup: set `B19_OVERLAY=<name>` and the contents of `/overlays/<name>/` are recursively copied over the container root. One image, several configurations — no rebuild. The pitch: [runtime overlay injection](../features.d/overlays.md).

## When to use

- Shipping several deployment variants (dev/staging configs, feature data) in one image and choosing per run.
- Anything that must overwrite existing files at startup rather than at build time.

## Quick start

```text
.container/user/overlays/tls-everywhere/etc/my-service/config.yaml
```

```bash
docker run -e B19_OVERLAY=tls-everywhere <image>
```

## How it works

The entrypoint hook `0500-copy-overlay.sh` runs before template rendering and service start:

- Skipped entirely unless `B19_OVERLAY` names an existing directory under `${B19_OVERLAYS_PATH}`.
- Copies with `cp --recursive "${B19_OVERLAYS_PATH}/${B19_OVERLAY}/." --target-directory=/` — overwriting whatever is in the way.
- Wipes the whole `/overlays/` tree afterwards: the choice is per-run and unchosen payloads never linger in the filesystem.

The copy runs as the non-root runtime user, so an overlay can only overwrite files writable by UID 1000 — system paths owned by root are effectively read-only to it. `B19_IMMUTABLE=Y` skips the copy (and template rendering) for production-locked images.

Overlays ship in your payload tree and land in the image via the standard `COPY .container/user/ /`; the base image anchors the directory with an empty `/overlays/` owned by the runtime user.

## Configuration

| Variable            | Default      | Effect                                     |
| ------------------- | ------------ | ------------------------------------------ |
| `B19_OVERLAY`       | (unset)      | Overlay directory name to apply at startup |
| `B19_OVERLAYS_PATH` | `/overlays/` | Where overlay directories live             |
| `B19_IMMUTABLE`     | `N`          | `Y` skips overlay copy and `.j2` rendering |

## Recipes

```yaml
# compose: one image, two configurations
services:
  web:
    environment:
      B19_OVERLAY: web
  worker:
    environment:
      B19_OVERLAY: worker
```

## See also

- [Render templates with minijinja](use-templating.md) — the other startup-time configuration mechanism
- [Start containers with entrypoint.d](use-entrypoint.d.md) — where slot 0500 sits
