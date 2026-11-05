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
- Runs `b19-materialize`, which merges the image’s templates and then the chosen overlay into `${B19_RUNTIME_PATH}`. The later layer wins per final path, so a plain overlay file replaces a template at that path.
- The build links every path a shipped overlay touches to `${B19_RUNTIME_PATH}`, so any `B19_OVERLAY` works on a read-only root. A link no chosen layer fills dangles.
- To ship an overlay without a rebuild, mount a volume read-only over `/overlays/<name>`. It may override any path the image knows; it may add a new path only on a writable root, and on a read-only root that file is skipped with a `warn` naming it.

The copy runs as the non-root runtime user, so an overlay can only overwrite files writable by UID 1000 — system paths owned by root are effectively read-only to it. `B19_IMMUTABLE=Y` skips the merge and template rendering; it is deprecated in favour of a read-only root.

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
