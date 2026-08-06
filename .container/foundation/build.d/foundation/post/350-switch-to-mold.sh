#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT


  # shellcheck source=/dev/null
  . b19-i18n

  if [ -z "${B19_BUILD_DISABLE_MOLD:-}" ]
  then
    command -v mold >/dev/null 2>&1 || {
        b19-log warn "PACKAGES" "$(_ "Mold not installed, skipping link")"
        return 0
    }

    b19-run "PACKAGES" "$(_p "Link mold as %s" "/usr/bin/ld")" --     \
      ln -sf /usr/local/bin/mold /usr/bin/ld

    b19-run "PACKAGES" "$(_p "Link mold as %s" "/bin/ld")" --     \
      ln -sf /usr/local/bin/mold /bin/ld

    LD_OUTPUT=$(ld -v)
    b19-log info "PACKAGES" "$(_p "LD says: %s" "${LD_OUTPUT}")"
  fi
