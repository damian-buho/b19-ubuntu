#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  ACTUAL="$(lsb_release --codename --short)" || ACTUAL=""

  if [ "${B19_UBUNTU_SERIES:-}" != "${ACTUAL}" ]; then
    b19-log error "TEST" "$(_p "Ubuntu series mismatch: expected %s, found %s" "${B19_UBUNTU_SERIES:-}" "${ACTUAL}")"
    exit 1
  fi

  b19-log info "TEST" "$(_p "Ubuntu series is %s" "${ACTUAL}")"
