#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Compile .po translation files into .mo binaries
  # Must run before any hook that uses translatable b19-* tools
  #
  # Per-project locales (es_ES, uk_UA, …) are generated on-demand in the
  # downstream base stage via b19-generate-locales (localedef); the foundation
  # stage only compiles the b19 gettext catalogs. This hook re-runs
  # idempotently in the base stage (100-compile-i18n.i.sh).

  b19-compile-i18n
