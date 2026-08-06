#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  TESTFILE="${B19_TEMP_PATH:-/tmp}/bench-compress.tmp"

  echo "=== Generating 256 MiB test data ==="
  dd if=/dev/urandom of="${TESTFILE}" bs=1M count=256 status=none

  echo ""
  echo "=== gzip ==="
  time gzip -c "${TESTFILE}" > /dev/null

  echo ""
  echo "=== bzip2 ==="
  time bzip2 -c "${TESTFILE}" > /dev/null

  echo ""
  echo "=== xz ==="
  time xz -c "${TESTFILE}" > /dev/null
