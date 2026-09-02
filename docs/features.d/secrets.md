<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Docker secrets auto-loading

- Docker secrets translate to environment variables automatically at container startup, requiring no code changes.
- Dot-notation filenames map to uppercase env vars, keeping naming consistent and predictable.
- Required secrets can be declared by name; the container refuses to start if any are missing.
- Existing environment variables take precedence over secret-derived values, so overrides are straightforward.
- Binary secrets (keys, DER blobs) stay on disk for file-based reads, avoiding Bash truncation issues.
