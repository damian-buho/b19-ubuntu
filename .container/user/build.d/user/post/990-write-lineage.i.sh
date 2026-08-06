#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # shellcheck source=../../tools.d/b19-i18n

  VERSION_COMMAND="get-${M6E_PROJECT}-version"

  if command -v "${VERSION_COMMAND}" &> /dev/null;
  then
    UPSTREAM_VERSION=$("${VERSION_COMMAND}")
  else
    UPSTREAM_VERSION='?'
  fi

  write-lineage "${M6E_NAMESPACE}/${M6E_PROJECT}" "${UPSTREAM_VERSION}"
