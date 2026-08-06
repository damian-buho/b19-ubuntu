#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT


    # shellcheck source=/dev/null
    . b19-i18n

    b19-run "BOOTSTRAP" "$(_ "Create smoke-test marker")" --      \
      touch "${B19_HOME}/.bootstrap-smoke"
