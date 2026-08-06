#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  TESTFILE="${B19_TEMP_PATH:-/tmp}/bench-seq-read.tmp"

  echo "=== Preparing read test file (1 GiB) ==="
  dd if=/dev/zero of="${TESTFILE}" bs=1M count=1024 status=none

  echo "=== Disk Sequential Read (1 GiB) ==="
  dd if="${TESTFILE}" of=/dev/null bs=1M
