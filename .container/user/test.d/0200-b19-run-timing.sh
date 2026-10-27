#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Test b19-run prints B19_RUN_TIMING_PRECISION decimals at every edge of its 0-9 range

set -eou pipefail

# shellcheck source=/dev/null
. b19-i18n

fail() {
  b19-log error "b19-run-timing" "$1"
  exit 1
}

# Elapsed text of a successful run at the given precision setting
elapsed_at() {
  local _out
  _out="$(NO_COLOR=1 B19_VERBOSITY=info B19_LOG_FORMAT=text B19_RUN_TIMING_PRECISION="$1" b19-run TIMING "run" -- true 2>&1)"
  if [[ "${_out}" =~ success\ \[([0-9.]+)s\] ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# Precision to expected decimals: the edges 0 and 9, the documented 3 and 6, and the fallback to 3 outside 0-9
for case in 0:0 1:1 3:3 6:6 9:9 10:3 banana:3 -1:3; do
  precision="${case%%:*}"
  decimals="${case##*:}"
  elapsed="$(elapsed_at "${precision}")"
  if [ "${decimals}" -eq 0 ]; then
    pattern='^[0-9]+$'
  else
    pattern="^[0-9]+\.[0-9]{${decimals}}\$"
  fi
  [[ "${elapsed}" =~ ${pattern} ]] || fail "$(_p "precision %s: expected %s decimals, got [%s]" "${precision}" "${decimals}" "${elapsed}")"
done

b19-log good "b19-run-timing" "$(_ "Timing precision tests passed")"
