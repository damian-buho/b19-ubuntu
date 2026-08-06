#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  if [ "${B19_IMMUTABLE:-}" != "Y" ]
  then
    if [ -n "${B19_OVERLAY:-}" ] && [ -d "${B19_OVERLAYS_PATH}/${B19_OVERLAY}/" ]
    then
      b19-log note "OVERLAY" "$(_p "%s is active" "${B19_OVERLAY}")"

      cp    --recursive "${B19_OVERLAYS_PATH}/${B19_OVERLAY}/."     \
            --verbose                                               \
            --target-directory="/"
    fi
    if [ -d "${B19_OVERLAYS_PATH}" ]
    then
      if [ "${B19_VERBOSITY:-warn}" = "debug" ]; then
        b19-run "OVERLAY" "$(_ "Remove overlays directory")" --     \
          rm -rf "${B19_OVERLAYS_PATH:?}"/*
      else
        rm -rf "${B19_OVERLAYS_PATH:?}"/*
      fi
    fi
  else
    b19-log warn "OVERLAY" "$(_ "B19_IMMUTABLE=Y, skipping overlays")"
  fi

