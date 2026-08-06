#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# localedef generation needs root (writes to /usr/lib/locale/). build-stage base
# runs as root, so this runs in every downstream image. No-op when B19_LOCALES
# is empty (the default). Inheritable (.i.sh): survives into downstream stages.
  if [ "$(id -u)" -eq 0 ]; then
      # shellcheck source=.container/foundation/tools.d/b19-generate-locales
      . b19-generate-locales
  fi
