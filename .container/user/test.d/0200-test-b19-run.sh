#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  # Test non-existent command returns exit code 127
  RC=0
  b19-run "TEST" "$(_ "Try to call non-existent-command")" -- non-existent-command || RC=$?
  [ "${RC}" -eq 127 ] || exit 1
