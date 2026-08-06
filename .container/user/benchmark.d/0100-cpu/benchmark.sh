#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  echo "=== CPU: SHA-256 (1s) ==="
  openssl speed -seconds 1 sha256

  echo ""
  echo "=== CPU: AES-256-CBC (1s) ==="
  openssl speed -seconds 1 aes-256-cbc
