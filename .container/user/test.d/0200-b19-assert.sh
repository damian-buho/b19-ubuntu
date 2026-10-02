#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  FAILED=0

  # Runs one case and fails the test when the exit code or the logged text differs
  check() {
    local _want_rc="$1" _want_text="$2" _rc=0 _out
    shift 2
    _out="$(NO_COLOR=1 B19_VERBOSITY=info b19-assert "$@" 2>&1)" || _rc=$?
    if [ "${_rc}" -ne "${_want_rc}" ] || [[ "${_out}" != *"${_want_text}"* ]]; then
      b19-log error "b19-assert" "$(_p "Case %s: expected exit %s with %s, got exit %s with %s" "$*" "${_want_rc}" "${_want_text}" "${_rc}" "${_out}")"
      FAILED=$((FAILED + 1))
    fi
  }

  check 0 "noble"     equals  SERIES noble noble
  check 1 "resolute"  equals  SERIES noble resolute
  check 0 "1.2.3"     matches VERSION '^1\.2\.' 1.2.3
  check 1 "2.0.0"     matches VERSION '^1\.2\.' 2.0.0
  check 1 "SERIES"    equals  SERIES noble ""
  check 2 "between"   between SERIES noble noble
  check 2 "3"         equals  SERIES noble

  [ "${FAILED}" -eq 0 ] || exit 1
  b19-log good "b19-assert" "$(_ "All b19-assert cases passed")"
