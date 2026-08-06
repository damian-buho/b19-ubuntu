#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  TESTFILE="${B19_TEMP_PATH:-/tmp}/bench-seq-write.tmp"

  echo "=== Disk Sequential Write (1 GiB, dsync) ==="
  dd if=/dev/zero of="${TESTFILE}" bs=1M count=1024 oflag=dsync
