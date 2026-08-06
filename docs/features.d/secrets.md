<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Docker secrets auto-loading (secrets)

- Docker secrets files are automatically discovered and converted to environment variables at startup.
- Dot-notation filenames map to uppercase env vars (`b19.npm.registry_host` becomes `B19_NPM_REGISTRY_HOST`).
- Required secrets can be declared by name; the container refuses to start if any are missing.
- Existing environment variables take precedence over secret-derived values.
- Secrets are also available in interactive shell sessions and healthchecks.
- Non-UTF-8/binary secrets (keys, DER blobs, gzipped tarballs) are **not** exported as env vars: Bash truncates them at the first NUL and the stray bytes panic any tool that reads the environment as UTF-8 (e.g. `minijinja --env`, used to template configs). They remain on disk at `/run/secrets/<name>` for file-based reads — which is the only correct way to consume a binary secret anyway.
