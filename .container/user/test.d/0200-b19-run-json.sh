#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Lock b19-run under JSON logs: revealed and failure output leave as one object per line, each with time and level.

set -eou pipefail

unset STAGE
export B19_LOG_FORMAT=json B19_VERBOSITY=warn NO_COLOR=1

# Prints plain text, foreign JSON without time/level, and a non-JSON brace line
payload() {
  printf '%s\n' 'plain text line' '{"ok":1}' '{ ok: 1 }'
  return "${1:-0}"
}
export -f payload

# Fails unless every line of $2 is a JSON object holding time and level
assert_records() {
  local _count
  _count="$(gojq --raw-input 'try fromjson catch null | select(type == "object" and has("time") and has("level"))' <<<"$2" | gojq --slurp 'length')"
  b19-assert equals "B19-RUN-JSON" "$(wc --lines <<<"$2" | tr --delete ' ')" "${_count}"
  b19-assert matches "B19-RUN-JSON" "$1" "$2"
}

OUT="$(b19-run --reveal Y JSON "Reveal" -- bash -c payload 2>&1)"
assert_records '"msg":"\{ ok: 1 \}"' "${OUT}"
b19-assert matches "B19-RUN-JSON" '"level":"info","ok":1' "${OUT}"

OUT="$(b19-run JSON "Fail" -- bash -c 'payload 3' 2>&1)" && exit 1
assert_records '"level":"error","msg":"plain text line"' "${OUT}"

OUT="$(B19_VERBOSITY=debug b19-run JSON "Stream" -- bash -c payload 2>&1)"
assert_records '"level":"debug","msg":"plain text line"' "${OUT}"
