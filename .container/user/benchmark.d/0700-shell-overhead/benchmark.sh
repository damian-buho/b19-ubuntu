#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  echo "=== Shell Loop Overhead (1M iterations) ==="
  time bash -c 'for i in $(seq 1 1000000); do :; done'
