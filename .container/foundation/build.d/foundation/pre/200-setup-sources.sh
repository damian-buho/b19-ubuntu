#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT


  # shellcheck source=/dev/null
  . b19-i18n

  if [ -f /etc/apt/sources.list.d/ubuntu.sources ]
  then
    SOURCES_FORMAT="DEB822"
    J2_FILE="/etc/apt/templates/ubuntu.sources.j2"
    OUTPUT_FILE="/etc/apt/sources.list.d/ubuntu.sources"
  else
    SOURCES_FORMAT="classic"
    J2_FILE="/etc/apt/templates/sources.list.j2"
    OUTPUT_FILE="/etc/apt/sources.list"
  fi

  b19-log info "PACKAGES" "$(_p "Format: %s" "${SOURCES_FORMAT}")"

  set -a
  # shellcheck source=/dev/null
  . /etc/lsb-release
  set +a

  MIRRORS_FILE="/etc/apt/mirrors/ubuntu.list"
  mkdir --parents "${MIRRORS_FILE%/*}"
  b19-run "PACKAGES" "$(_p "Render %s" "${MIRRORS_FILE}")" --     \
    minijinja-cli --autoescape none --env /etc/apt/templates/ubuntu.mirrors.j2 -o "${MIRRORS_FILE}"
  b19-log info "PACKAGES" "$(_p "APT mirrors in order: %s" "$(awk '!/^#/ && NF {printf "%s%s", sep, $1; sep=" "}' "${MIRRORS_FILE}")")"

  b19-run "PACKAGES" "$(_p "Render %s" "${OUTPUT_FILE}")" --      \
    minijinja-cli --autoescape none --env "${J2_FILE}" -o "${OUTPUT_FILE}"
