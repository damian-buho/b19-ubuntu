#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Stage-independent: any stage may run apt, not just base/root/foundation.
  # Counterpart removed in always/post/900, inside the same RUN.

  detect-apt-cacher install
