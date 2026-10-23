#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Lock B19_LOG_FORMAT=json: one escaped object per line, payload objects untouched, text stays the default.

set -eou pipefail

# shellcheck source=/dev/null
. b19-i18n

unset STAGE
export B19_VERBOSITY=warn NO_COLOR=1

# Strip the time field, the only value that changes between runs
untimed() {
  sed --regexp-extended 's/^\{"time":"[^"]*",/{/'
}

OUT="$(B19_LOG_FORMAT=text b19-log warn TAG "plain" 2>&1)"
b19-assert matches "LOG-JSON" '^ WARN +TAG +plain$' "${OUT}"

OUT="$(B19_LOG_FORMAT=bogus b19-log warn TAG "plain" 2>&1)"
b19-assert matches "LOG-JSON" '^ WARN +TAG +plain$' "${OUT}"

export B19_LOG_FORMAT=json

OUT="$(b19-log warn TAG "plain" 2>&1)"
b19-assert matches "LOG-JSON" '^\{"time":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z","level":"warn","tag":"TAG","msg":"plain"\}$' "${OUT}"

# A decimal-comma locale must not leak into the timestamp
COMMA_LOCALE="$(locale --all-locales | grep --max-count=1 --extended-regexp '^(uk_UA|es_ES)\.utf-?8$' || true)"
if [ -n "${COMMA_LOCALE}" ]
then
  OUT="$(LC_ALL="${COMMA_LOCALE}" b19-log warn TAG "plain" 2>&1)"
  b19-assert matches "LOG-JSON" '^\{"time":"[^",]*\.[0-9]{3}Z"' "${OUT}"
else
  b19-log warn "LOG-JSON" "$(_p "Skipping the decimal-comma case: no such locale among %s" "$(locale --all-locales | tr '\n' ' ')")"
fi

OUT="$(printf '%s\n' $'q"b\\t\tr\rc\x01e\x1b[0m' | b19-log error TAG 2>&1 | untimed)"
b19-assert equals "LOG-JSON" '{"level":"error","tag":"TAG","msg":"q\"b\\t\tr\rc\u0001e\u001b[0m"}' "${OUT}"

OUT="$(b19-log warn "ТЕГ" "Привіт, ñandú «…»" 2>&1 | untimed)"
b19-assert equals "LOG-JSON" '{"level":"warn","tag":"ТЕГ","msg":"Привіт, ñandú «…»"}' "${OUT}"

OUT="$(B19_VERBOSITY=debug b19-log good TAG "g" 2>&1 | untimed)"
b19-assert equals "LOG-JSON" '{"level":"info","tag":"TAG","msg":"g"}' "${OUT}"

OUT="$(B19_VERBOSITY=debug b19-log note TAG "n" 2>&1 | untimed)"
b19-assert equals "LOG-JSON" '{"level":"debug","tag":"TAG","msg":"n"}' "${OUT}"

OUT="$(b19-log info TAG "below threshold" 2>&1)"
b19-assert equals "LOG-JSON" "" "${OUT}"

OUT="$(STAGE=ENTRY b19-log warn TAG "s" 2>&1 | untimed)"
b19-assert equals "LOG-JSON" '{"level":"warn","stage":"ENTRY","tag":"TAG","msg":"s"}' "${OUT}"

OUT="$(b19-log warn TAG 'one\ntwo' 2>&1 | untimed)"
b19-assert equals "LOG-JSON" $'{"level":"warn","tag":"TAG","msg":"one"}\n{"level":"warn","tag":"TAG","msg":"two"}' "${OUT}"

OUT="$(printf '%s\n' '{"ClientHost":"192.0.2.1","DownstreamStatus":404}' 'plain line' '{not closed' | b19-log info STDOUT 2>&1 | untimed)"
b19-assert equals "LOG-JSON" $'{"ClientHost":"192.0.2.1","DownstreamStatus":404}\n{"level":"info","tag":"STDOUT","msg":"plain line"}\n{"level":"info","tag":"STDOUT","msg":"{not closed"}' "${OUT}"

OUT="$(printf 'no newline at end' | b19-log info STDOUT 2>&1 | untimed)"
b19-assert equals "LOG-JSON" '{"level":"info","tag":"STDOUT","msg":"no newline at end"}' "${OUT}"

b19-log good "LOG-JSON" "$(_p "%s escapes, maps levels, filters and passes payload objects through" "B19_LOG_FORMAT=json")"
