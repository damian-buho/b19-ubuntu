#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  # Test with -- separator
  b19-run "TEST" "$(_ "Touch /tmp/test")" -- touch /tmp/test

  if [ ! -f /tmp/test ]; then
    exit 1
  fi
