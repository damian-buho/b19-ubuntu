<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Run as a non-root user

The image runs as `ubuntu`, UID/GID 1000 — not root. A two-stage build separates root-level system installation from user-level runtime setup, and every writable path the runtime needs is pre-owned by that user. The pitch: [non-root container by default](../features.d/non-root.md).

## When to use

- Every downstream image: the pattern is inherited — mirror it in your own Dockerfile stages.
- Hardened deployments where a compromised service process must not be root.

## Quick start

```dockerfile
# The two-stage pattern (scaffold shape):
USER root
COPY .container/foundation/ /
RUN --mount=... build-stage base      # root-level install
USER ${B19_UID}
COPY .container/user/ /
RUN --mount=... build-stage user      # user-level runtime setup
# ENTRYPOINT and HEALTHCHECK are inherited — never redeclare them
```

## How it works

The foundation stage runs as root and creates the account:

```bash
useradd --home "${B19_HOME}" --shell /bin/bash --uid "${B19_UID}" ubuntu
```

The account name is fixed (`ubuntu`); `B19_USER` only changes the `USER` env var. Home is `/app`, not `/home/ubuntu` — `/home` is deleted in cleanup. The final `USER` directive is the numeric UID (`USER ${B19_UID}`), which survives even where the name is not in `/etc/passwd` of the runtime namespace.

A permissions pass (`foundation/post/200-permissions.sh`) creates and chowns the hook directories, the overlay root, the [XDG paths](use-xdg-paths.md) and `${B19_HOME}` itself to `${B19_UID}:0` with `g+rwX` on the home — so group 0 (the pattern hardened runtimes use for volumes) can also write. `${B19_CACHE_PATH}` is chowned non-recursively on purpose: rewriting the shared build cache would defeat it.

Runtime behavior adapts to the non-root reality: privileged-port validation errors only when `id -u` is not 0, and the APT install hook is root-guarded inside itself.

## Configuration

| Variable    | Default  | Effect                                             |
| ----------- | -------- | -------------------------------------------------- |
| `B19_USER`  | `ubuntu` | Runtime username env (account name stays `ubuntu`) |
| `B19_UID`   | `1000`   | User UID — also the final `USER`                   |
| `B19_GROUP` | `ubuntu` | Group name env                                     |
| `B19_GID`   | `1000`   | Group GID                                          |
| `B19_HOME`  | `/app`   | Working directory and user home                    |
| `B19_PUID`  | (empty)  | Opt-in: remap the UID when started as root         |
| `B19_PGID`  | (empty)  | Opt-in: remap the GID, together with `B19_PUID`    |

Directories your service needs on mounted volumes at build time belong in a `volumes.deps` file — see [build with hooks](use-build.d.md) for the mount-shadowing gotcha.

## Run as the host user

A bind mount keeps the host’s ownership, so UID 1000 inside may not match the host user that owns `./data`. Two ways out, neither of them the default:

```bash
# No root at all: any UID in group 0 can write the home (g+rwX posture)
docker run --user "$(id -u):0" --volume ./data:/app/data image

# Opt-in remap: start as root, remap, then drop to the host UID/GID for good
docker run --user 0 --env B19_PUID="$(id -u)" --env B19_PGID="$(id -g)" --volume ./data:/app/data:z image
```

The remap (`entrypoint.d/0010-remap-user.sh`) acts only when `B19_PUID` is set AND the container starts as root; set but not root, it warns and carries on as 1000. It moves `ubuntu` to the requested IDs, chowns `${B19_HOME}` to the new UID (group 0 stays), and restarts the entrypoint through `setpriv`, so no hook after it and no service ever runs as root. It refuses a non-numeric ID and one owned by another account, root included. It needs a writable `/etc/passwd`, so it does not combine with `--read-only`, and it needs `CHOWN`, `SETUID` and `SETGID`, so it does not combine with `--cap-drop ALL`. `B19_ENTRYPOINT_SKIP_REMAP_USER=true` switches it off. The `:z` suffix relabels the mount on SELinux hosts. Rootless Podman gets the same result with `--userns=keep-id` and no remap.

## Recipes

```bash
# Docker-in-Docker opt-in: join the socket group (GID B19_DOCKER_GID=995)
add-user-to-docker
```

## See also

- [Use the XDG paths](use-xdg-paths.md) — the writable-path layout this depends on
- [Build images with build.d hooks](use-build.d.md) — the two stages in detail
- [Validate ports](use-port-validation.md) — a check that depends on `id -u`
