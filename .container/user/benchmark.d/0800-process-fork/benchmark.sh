#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  echo "=== Process Fork Overhead (/bin/true, 500 runs) ==="
  hyperfine --runs 500 '/bin/true'
