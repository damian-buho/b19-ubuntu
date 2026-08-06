#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  FAILED=0

  # grep must exist, or every check below short-circuits to a silent pass
  command -v grep >/dev/null || {
    b19-log error "TEST" "$(_p "%s is required but not available" "grep")"
    exit 1
  }

  for script in /tools.d/*; do
    [ -f "${script}" ] || continue

    USES_CODENAME=false
    SOURCES_LSB=false

    grep -qE 'DISTRIB_CODENAME' "${script}"         && USES_CODENAME=true
    grep -qE '/etc/lsb-release'  "${script}"         && SOURCES_LSB=true

    if "${USES_CODENAME}" && ! "${SOURCES_LSB}"; then
      b19-log error "TEST" "$(_p "%s uses DISTRIB_CODENAME without sourcing /etc/lsb-release" "${script}")"
      FAILED=$((FAILED + 1))
    fi
  done

  [ "${FAILED}" -eq 0 ] || exit 1
