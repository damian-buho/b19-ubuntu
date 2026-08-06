#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  timeout 5 nslookup google.com 8.8.8.8 || {
    b19-log warn "NSLOOKUP" "$(_ "nslookup google.com 8.8.8.8 failed (network may be isolated)")"
  }
  timeout 5 nslookup google.com 1.1.1.1 || {
    b19-log warn "NSLOOKUP" "$(_ "nslookup google.com 1.1.1.1 failed (network may be isolated)")"
  }
