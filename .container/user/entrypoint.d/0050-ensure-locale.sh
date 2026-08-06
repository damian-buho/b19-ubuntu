#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Validate LANG before any locale-sensitive tooling runs. Runs first (0050,
# before 0100-load-secrets) so every downstream hook and the main process see a
# locale that actually exists in this image.
  # shellcheck source=.container/foundation/tools.d/b19-ensure-locale
  . b19-ensure-locale
