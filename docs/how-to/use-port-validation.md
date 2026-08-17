<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Validate ports

Every environment variable whose name ends in `PORT` is validated at startup and at build time against the WHATWG blocklist of browser-forbidden ports, and against the privileged range below 1024. A bad port fails loudly at slot 0300 instead of dooming the service to silent connection refusals. The pitch: [port validation](../features.d/port-validation.md).

## When to use

- Automatically: name your port variables with a `PORT` suffix (`HTTP_PORT`, `APP_PORT`) and validation finds them — no registration.
- Debugging a service that mysteriously never receives traffic: check the startup log for a port-validation error first.

## Quick start

```bash
docker run -e HTTPS_PORT=10025 <image>
# entrypoint fails fast:
# PORTS  HTTPS_PORT=10025 is browser-blocked (WHATWG bad port)
```

## How it works

The `check-ports` tool scans `env` for uppercase names matching `*PORT` with purely numeric values, and checks each against:

- `${B19_HOME}/.forbidden-ports.txt` — the WHATWG bad-ports blocklist shipped in the image (comments stripped, one port per line). If the file is missing, the check is skipped with a warning.
- The privileged range: values below 1024 error **only when the container is not root** (`id -u != 0`), because root could legitimately bind them.

Any violation exits 1 and stops the entrypoint chain. The check runs twice — at container startup (entrypoint `0300-check-ports.sh`) and at image build time (inherited `user/post/020-check-ports.i.sh`) — so a bad port fails the build itself.

Scope details that matter:

- Only names **ending** in `PORT` are matched, and only uppercase: `HTTP_PORT` is checked, a bare `PORT` is not.
- `0` is exempt from the privileged check (the conventional “let the OS pick” value).
- 443 is not in the blocklist — `HTTPS_PORT=443` passes.

## Configuration

| Variable                 | Default | Effect                               |
| ------------------------ | ------- | ------------------------------------ |
| `B19_PORT_CHECK_ENABLED` | `true`  | `false` skips validation, no rebuild |

## Recipes

```bash
# Run the check manually against the current environment
docker exec <container> check-ports
```

## See also

- [Start containers with entrypoint.d](use-entrypoint.d.md) — where slot 0300 sits
- [Configure the image environment](configure-environment.md) — the toggle index
