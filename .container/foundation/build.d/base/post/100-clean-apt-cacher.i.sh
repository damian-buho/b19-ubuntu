#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  if [ -f /etc/apt/apt.conf.d/99proxy ]
  then
    rm /etc/apt/apt.conf.d/99proxy
  fi
