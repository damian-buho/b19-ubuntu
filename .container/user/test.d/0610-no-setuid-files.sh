#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  ALLOW=" ${B19_SETUID_ALLOW:-} "
  FAILED=0

  # Every setuid/setgid file outside the declared allow-list fails the image
  while IFS= read -r -d '' FILE; do
    [[ "${ALLOW}" == *" ${FILE} "* ]] && continue
    b19-log error "SETUID" "$(_p "Unexpected setuid/setgid file %s" "${FILE}")"
    FAILED=$((FAILED + 1))
  done < <(find / -xdev -type f -perm /6000 -print0 2>/dev/null)

  [ "${FAILED}" -eq 0 ] || exit 1
  b19-log good "SETUID" "$(_ "No setuid/setgid file outside the allow-list")"
