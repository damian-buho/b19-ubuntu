#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  if [ "$(id -u)" -eq 0 ]; then
      # shellcheck source=.container/foundation/tools.d/install-apt
      . install-apt
  fi
