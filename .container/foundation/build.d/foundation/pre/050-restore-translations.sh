#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # shellcheck source=.container/foundation/tools.d/b19-i18n
  . b19-i18n

  # The Ubuntu Docker base ships /etc/dpkg/dpkg.cfg.d/excludes that strips ALL
  # .mo translation catalogs (path-exclude=/usr/share/locale/*/LC_MESSAGES/*.mo)
  # to shrink the image. That prevents system tools (apt, dpkg, coreutils) from
  # ever translating, even when the locale is generated and LANGUAGE is set.
  #
  # b19 ships its own 01_strip_docs (docs/man only, NOT .mo), so removing the
  # Ubuntu excludes restores translation catalogs on subsequent apt installs.
  # Runs in the pre stage, before the first install-apt, so .mo files survive.
  EXCLUDES_FILE="/etc/dpkg/dpkg.cfg.d/excludes"
  if [ -f "${EXCLUDES_FILE}" ]; then
      b19-run "LOCALE" "$(_p "Remove Ubuntu .mo-stripping excludes: %s" "${EXCLUDES_FILE}")" --     \
          rm -f "${EXCLUDES_FILE}"
  fi
