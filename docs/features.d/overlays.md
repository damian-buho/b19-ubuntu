<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Runtime overlay injection

- Configuration or data files can be injected at container startup by setting `B19_OVERLAY` to a directory name.
- Overlay contents are recursively copied to the container root, overwriting existing files — no image rebuild needed.
- Skipped in immutable mode, preventing runtime modification of production-locked images.
