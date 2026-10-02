#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  b19-assert equals "SERIES" "${B19_UBUNTU_SERIES:-}" "$(lsb_release --codename --short || true)"
