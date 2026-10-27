#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test b19-log-filter drops exactly what b19-log would, at every threshold edge

set -eou pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
  b19-log error "b19-log-filter" "$1"
  exit 1
}

# Output of one call through the filter, then through the real tool, must match
same_output() {
  local _verbosity="$1" _level="$2" _filtered _real
  _filtered=$(B19_VERBOSITY="${_verbosity}" bash -c '. b19-log-filter; b19-log "$1" TEST "msg" 2>&1' _ "${_level}")
  _real=$(B19_VERBOSITY="${_verbosity}" b19-log "${_level}" TEST "msg" 2>&1)
  [ "${_filtered}" = "${_real}" ] || fail "$(_p "verbosity %s level %s: filter printed [%s], b19-log printed [%s]" "${_verbosity}" "${_level}" "${_filtered}" "${_real}")"
}

b19-log good "b19-log-filter" "$(_ "Starting log filter tests")"

# Every verbosity, every level, including the unknown verbosity that falls back to warn
for verbosity in error warn info debug bogus; do
  for level in error warn bad good info debug note; do
    same_output "${verbosity}" "${level}"
  done
done

# The filter is a function, so a dropped line costs no process
[ "$(bash -c '. b19-log-filter; type -t b19-log')" = "function" ] || fail "$(_ "b19-log is not a function after sourcing")"

# A verbosity change between calls takes effect on the next call
OUTPUT=$(bash -c '. b19-log-filter; B19_VERBOSITY=warn; b19-log info TEST "first"; B19_VERBOSITY=info; b19-log info TEST "second"' 2>&1)
grep -q "second" <<<"${OUTPUT}" || fail "$(_ "verbosity change was not honored")"
! grep -q "first" <<<"${OUTPUT}" || fail "$(_ "line below the old threshold was printed")"

# An unknown level still fails the way the real tool does
if bash -c '. b19-log-filter; b19-log bogus TEST "msg"' >/dev/null 2>&1; then
  fail "$(_ "unknown level was accepted")"
fi

# A piped call (no message) reaches the real tool unfiltered
OUTPUT=$(printf 'piped line\n' | B19_VERBOSITY=error bash -c '. b19-log-filter; b19-log debug TEST' 2>&1)
grep -q "piped line" <<<"${OUTPUT}" || fail "$(_ "piped line was dropped")"

b19-log good "b19-log-filter" "$(_ "Log filter tests passed")"
