<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Modular build hooks (build.d)

- Build logic lives in composable hook scripts instead of inline Dockerfile commands, making it easy to read, test, and reuse.
- Cross-cutting setup (CA trust, locale, shared installs) is written once and runs on every stage automatically.
- Downstream images inherit parent build logic through the layer overlay — no duplication needed.
- Non-inheritable one-off setup is cleaned up after execution to avoid leaking into later stages.
