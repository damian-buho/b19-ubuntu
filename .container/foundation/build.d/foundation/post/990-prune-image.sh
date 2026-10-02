#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # shellcheck disable=SC2114 # paths the single-layer image leaves out, /home included
  PRUNED="$(rm --recursive --force --verbose            \
    /home                                               \
    /usr/bin/pebble                                     \
    /usr/share/bash-completion/completions/*            \
    /usr/share/doc/*/changelog*                         \
    /usr/share/fish/vendor_completions.d/*              \
    /usr/share/groff/*                                  \
    /usr/share/info/*                                   \
    /usr/share/lintian/*                                \
    /usr/share/man/*                                    \
    /usr/share/zsh/site-functions/*                     \
    /usr/share/zsh/vendor-completions/*                 \
    /var/log/*.log                                      \
    /var/log/apt/*                                      \
    /var/log/btmp                                       \
    /var/log/lastlog                                    \
    /var/log/wtmp                                       \
    | wc --lines)"

  b19-log info "CLEANUP" "$(_p "Pruned %s entries from the image" "${PRUNED}")"
