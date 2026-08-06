#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  WORKDIR="${B19_TEMP_PATH:-/tmp}"

  echo "=== Disk Random Read I/O (4K, 256 MiB, 10s) ==="
  fio --name=randread --ioengine=sync --rw=randread --bs=4k     \
      --numjobs=1 --size=256M --runtime=10 --time_based         \
      --directory="${WORKDIR}"
