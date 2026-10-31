#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Drop setuid/setgid bits a root stage installed, except the image-declared B19_SETUID_ALLOW
  if [ "${EUID}" -eq 0 ]; then
    b19-strip-setuid
  else
    b19-log debug "SETUID" "$(_p "Stage %s runs as uid %s, nothing to strip" "${STAGE}" "${EUID}")"
  fi
