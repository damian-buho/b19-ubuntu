<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Modular build hooks (build.d)

- All image build logic lives in numbered shell scripts instead of inline Dockerfile `RUN` commands.
- Hooks are organized in `pre/on/post` phases and auto-discovered by the stage name passed to `build-stage`.
- The reserved `always/{pre,post}` scope brackets every stage, whatever it is named, so cross-cutting setup is written once instead of per stage.
- Inheritable hooks propagate to downstream images automatically via Docker layer overlay — downstream gets parent’s build logic for free.
- Non-inheritable hooks are cleaned up after execution to prevent leaking into later stages.
