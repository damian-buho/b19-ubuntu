#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  parallel-j2 --final "${B19_TEST_PATH}"
  chmod +x "${B19_TEST_PATH}"/*.sh
