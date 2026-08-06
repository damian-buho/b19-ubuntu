#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Append shell.d sourcing to /etc/bash.bashrc
# This makes shell.d hooks run for interactive shells (e.g. docker exec bash)

  if [ "${B19_SHELL_ENABLED:-}" = "false" ]; then
    b19-log info "SHELL" "$(_ "Shell hooks disabled")"
    return 0
  fi

  b19-log info "SHELL" "$(_p "Setting up shell hooks at %s" "${B19_SHELL_PATH}")"

  cat >> /etc/bash.bashrc <<'BASHRC'

# b19: source shell.d hooks for interactive shells
if [ "${B19_SHELL_ENABLED}" != "false" ] && [ -d "${B19_SHELL_PATH}" ]; then
  for _b19_sh in "${B19_SHELL_PATH}"/*.sh; do
    [ -e "${_b19_sh}" ] || continue
    # shellcheck disable=SC1090
    . "${_b19_sh}"
  done
  unset _b19_sh
fi
BASHRC

  b19-log good "SHELL" "$(_ "Shell hooks configured in /etc/bash.bashrc")"
