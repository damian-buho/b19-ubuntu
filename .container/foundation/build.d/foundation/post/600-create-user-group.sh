#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Create the fixed ubuntu user (UID 1000)

if ! getent passwd ubuntu > /dev/null 2>&1; then
  b19-log good "SECURITY" "$(_p "User %s does not exist" "ubuntu")"
else
  b19-log info "SECURITY" "$(_p "User %s already exists, removing for recreation" "ubuntu")"
  b19-run "SECURITY" "$(_p "Remove user %s" "ubuntu")" --     \
    deluser ubuntu
fi

b19-run "SECURITY" "$(_p "Create user %s" "ubuntu")" --     \
        useradd                                             \
          --home "${B19_HOME}"                              \
          --shell /bin/bash                                 \
          --uid "${B19_UID}"                                \
          ubuntu
