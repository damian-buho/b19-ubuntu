#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  command -v b19-run > /dev/null 2>&1 || { echo "Not in build context, refusing to run destructive cleanup"; exit 1; }

  b19-run "CLEANUP" "$(_ "Remove /home")" --            rm -rf /home
  b19-run "CLEANUP" "$(_ "Remove /var/log files")" --   fd --hidden --no-ignore --type file . /var/log --exec-batch rm --force
  b19-run "CLEANUP" "$(_ "Remove shell completions")" -- rm --recursive --force /usr/share/bash-completion/completions /usr/share/fish/vendor_completions.d /usr/share/zsh/site-functions /usr/share/zsh/vendor-completions
