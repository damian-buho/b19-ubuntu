#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Counterpart of always/pre/010: runs after the stage's own post hooks, so the
  # anchor is gone before the layer commits whatever the stage did.

  trust-ca-certificates remove
