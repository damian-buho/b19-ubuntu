#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # shellcheck source=/dev/null
  . b19-i18n

    B19_UPSTREAM_DESTINATION=/usr/local/bin/minijinja-cli

    if [ -x "${B19_UPSTREAM_DESTINATION}" ]; then
        b19-log good "MINIJINJA" "$(_p "Already present at %s, skipping upstream install" "${B19_UPSTREAM_DESTINATION}")"
        minijinja-cli --version | b19-log good "MINIJINJA"
        return 0
    fi

    b19-log warn "MINIJINJA" "$(_p "Not found at %s" "${B19_UPSTREAM_DESTINATION}")"
