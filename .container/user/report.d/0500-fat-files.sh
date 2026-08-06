#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -euo pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  # Temporary file to store intermediate results
  UNSORTED=$(mktemp)
  SORTED=$(mktemp)
  trap 'rm -f "${UNSORTED}" "${SORTED}"' EXIT

  # Check if the B19_REPORTD_FAT_FILES_AMOUNT variable is set
  if [[ -z "${B19_REPORTD_FAT_FILES_AMOUNT}" ]]; then
    b19-log error "FATFILES" "$(_ "B19_REPORTD_FAT_FILES_AMOUNT environment variable is not set")"
    exit 1
  fi

  b19-log info "FATFILES" "$(_ "Generating file list from root filesystem")"
  # --exclude proc prunes /proc (pseudo-files); --no-ignore makes traversal exhaustive
  # like find. || true keeps the report going past per-file du/stat errors.
  fd --hidden --no-ignore --type file --exclude proc . / --exec-batch du --human-readable 2>/dev/null > "${UNSORTED}" || true

  b19-log info "FATFILES" "$(_ "Sorting file list by size...")"
  sort -hr -k1 "${UNSORTED}" > "${SORTED}"

  b19-log good "FATFILES" "$(_p "The top %s largest files have been saved to: %s" "${B19_REPORTD_FAT_FILES_AMOUNT}" "${SORTED}")"

  head -n "${B19_REPORTD_FAT_FILES_AMOUNT}" "${SORTED}"
