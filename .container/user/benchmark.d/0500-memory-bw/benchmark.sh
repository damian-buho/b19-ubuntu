#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  echo "=== Memory Bandwidth (32 GiB null-to-null) ==="
  dd if=/dev/zero of=/dev/null bs=1M count=32768
