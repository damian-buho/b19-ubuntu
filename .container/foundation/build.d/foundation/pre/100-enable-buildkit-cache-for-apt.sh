#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT


  # shellcheck source=/dev/null
  . b19-i18n

  DOCKER_CLEAN=/etc/apt/apt.conf.d/docker-clean

  # Conflicts with caching logic
  if [ -f "${DOCKER_CLEAN}" ];
  then
    b19-log info "PACKAGES" "$(_p "%s is detected" "${DOCKER_CLEAN}")"
    b19-run "PACKAGES" "$(_p "Remove %s" "${DOCKER_CLEAN}")" --  rm /etc/apt/apt.conf.d/docker-clean
  else
    b19-log info "PACKAGES" "$(_p "%s is not detected" "${DOCKER_CLEAN}")"
  fi
