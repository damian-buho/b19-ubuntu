#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Counterpart of always/pre/020: runs after the stage's own post hooks, so
  # the proxy is gone before the layer commits — it never reaches a runtime
  # container either.

  detect-apt-cacher remove
