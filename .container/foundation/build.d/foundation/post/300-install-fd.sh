#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # shellcheck source=/dev/null
  . b19-i18n

    B19_UPSTREAM_DESTINATION=/usr/bin/fd

    if [ -x "${B19_UPSTREAM_DESTINATION}" ]; then
        b19-log good "FD" "$(_p "Already present at %s, skipping upstream install" "${B19_UPSTREAM_DESTINATION}")"
        fd --version | b19-log good "FD"
        return 0
    fi

    resolved="$(b19-resolve-dep fd "${TARGETARCH}" 2>/dev/null)" || {
        b19-log warn "FD" "$(_p "No binary for %s, skipping" "${TARGETARCH}")"
        return 0
    }
    eval "${resolved}"

    b19-fetch "FD" "${M6E_UPSTREAM__URL}" "${M6E_UPSTREAM__FILE}" "${M6E_UPSTREAM__HASH}"

    b19-run "FD" "$(_p "Install from %s" "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}")" --      \
      dpkg -i "${B19_TEMP_PATH}/${M6E_UPSTREAM__FILE}"
