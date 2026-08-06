#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT


  if [ "${B19_OFFGRID_MODE:-N}" = "Y" ]
  then
    b19-log good "PACKAGES" "$(_ "Offgrid mode, skipping dist-upgrade")"
  else
    b19-run "PACKAGES" "$(_ "Upgrade all packages")" --     \
        flock -w 600 /var/cache/apt/.buildkit-lock          \
          apt-get dist-upgrade -y
  fi
