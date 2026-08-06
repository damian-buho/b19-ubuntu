<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Pluggable startup system (entrypoint.d)

- Every container startup runs through a sequence of numbered hooks: signal setup, secrets loading, CPU detection, port validation, template rendering, bootstrap, service start.
- Ad-hoc commands (`docker run img command`) automatically bypass part of the startup chain and execute directly.
- Individual hooks or the entire entrypoint can be skipped at runtime via environment variables, no image rebuild needed.
- Downstream images override a single hook (slot 5000) to launch their service; everything else is inherited.
