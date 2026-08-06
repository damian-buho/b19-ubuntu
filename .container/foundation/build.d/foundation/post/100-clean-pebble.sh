#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Unmaintained piece of shit that nobody asked for.
  # Primary purpose: fail security audits every week
  if [ -f /usr/bin/pebble ]
  then
    rm /usr/bin/pebble
  fi
