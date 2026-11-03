#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Lock the stream formatter: parsed fields, the native line in raw, untrusted content, and every way it degrades.

set -eou pipefail

# shellcheck source=/dev/null
. b19-i18n

unset STAGE
export B19_LOG_FORMAT=json B19_VERBOSITY=warn NO_COLOR=1

WORK="$(mktemp --directory)"
# shellcheck disable=SC2329 # cleanup invoked via EXIT trap
cleanup() { rm --recursive --force "${WORK}"; }
trap cleanup EXIT

export B19_LOG_FORMATS_PATH="${WORK}/rules"
mkdir "${B19_LOG_FORMATS_PATH}"
cat > "${B19_LOG_FORMATS_PATH}/1000-nginx" <<'RULE'
# A comment, then a rule whose # must survive

^(?<upstream_time>[0-9/]+ [0-9:]+) \[(?<level>[a-z]+)\] [0-9]+#[0-9]+: (?<msg>.*)$
RULE
printf '%s\n' '(unclosed' '^plain rule (?<word>[a-z]+)$' > "${B19_LOG_FORMATS_PATH}/2000-more"

# Strip the time field, the only value that changes between runs
untimed() {
  sed --regexp-extended 's/,"time":"[0-9T:.-]+Z"//'
}

# Formats one line at the warn stream level
format() {
  printf '%s\n' "$1" | b19-log-format "${2:-warn}" TAG 2>&1 | untimed
}

OUT="$(printf '%s\n' 'x' | b19-log-format warn TAG 2>&1)"
b19-assert matches "LOG-FORMAT" '"time":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z"' "${OUT}"

LINE='2026/11/03 10:00:00 [crit] 12#12: *3 failed, client: 192.0.2.1'
b19-assert equals "LOG-FORMAT" '{"level":"error","msg":"*3 failed, client: 192.0.2.1","raw":"'"${LINE}"'","tag":"TAG","upstream_time":"2026/11/03 10:00:00"}' "$(format "${LINE}")"

LINE='2026/11/03 10:00:00 [nonsense] 1#1: x'
b19-assert equals "LOG-FORMAT" '{"level":"warn","msg":"x","raw":"'"${LINE}"'","tag":"TAG","upstream_time":"2026/11/03 10:00:00"}' "$(format "${LINE}")"

b19-assert equals "LOG-FORMAT" '{"level":"warn","msg":"plain rule abc","tag":"TAG","word":"abc"}' "$(format 'plain rule abc')"

OUT="$(format 'a=1 b="two words" c="q\"r"')"
b19-assert equals "LOG-FORMAT" '{"a":"1","b":"two words","c":"q\"r","level":"warn","raw":"a=1 b=\"two words\" c=\"q\\\"r\"","tag":"TAG"}' "${OUT}"

# Log content is untrusted: the first level wins, and the engine’s own keys hold
OUT="$(format 'level=error level=info tag=sshd stage=forged raw=forged')"
b19-assert equals "LOG-FORMAT" '{"level":"error","raw":"level=error level=info tag=sshd stage=forged raw=forged","tag":"TAG"}' "${OUT}"

for LINE in 'prose holding a=b inside' '[1,2]' '{not closed' 'a="never closed' ''
do
  b19-assert equals "LOG-FORMAT" "{\"level\":\"warn\",\"msg\":\"${LINE//\"/\\\"}\",\"tag\":\"TAG\"}" "$(format "${LINE}")"
done

b19-assert equals "LOG-FORMAT" '{"level":"info","msg":"x","tag":"TAG"}' "$(format 'x' good)"
b19-assert equals "LOG-FORMAT" '{"level":"debug","msg":"x","tag":"TAG"}' "$(format 'x' note)"

OUT="$(printf 'bad\xffbyte\n' | b19-log-format warn TAG 2>&1 | untimed)"
b19-assert equals "LOG-FORMAT" '{"level":"warn","msg":"bad\ufffdbyte","tag":"TAG"}' "${OUT}"

OUT="$(STAGE=ENTRY format 'x')"
b19-assert equals "LOG-FORMAT" '{"level":"warn","msg":"x","stage":"ENTRY","tag":"TAG"}' "${OUT}"

# A complete object stays byte-identical; a partial one gains what it lacks and never a tag
LINE='{"time":"t", "level":"INFO", "n":1.10}'
b19-assert equals "LOG-FORMAT" "${LINE}" "$(format "${LINE}")"
b19-assert equals "LOG-FORMAT" '{"DownstreamStatus":502,"level":"warn"}' "$(format '{"DownstreamStatus":502}')"

# text stays the plain logger, and no rule runs
OUT="$(printf '%s\n' 'a=1' | B19_LOG_FORMAT=text b19-log-format warn TAG 2>&1)"
b19-assert matches "LOG-FORMAT" '^ TAG +a=1$' "${OUT}"

# A missing gojq or filter leaves the stream on b19-log, with no line lost
OUT="$(printf '%s\n' 'a=1' | PATH="/tools.d:/usr/bin:/bin" b19-log-format warn TAG 2>&1)"
b19-assert matches "LOG-FORMAT" '"tag":"b19-log-format"' "${OUT}"
b19-assert matches "LOG-FORMAT" '"tag":"TAG","msg":"a=1"' "${OUT}"

# b19-exec routes both streams through the formatter
OUT="$(b19-exec -- bash -c 'echo "level=error a=1"; echo "plain rule abc" >&2' 2>&1 | untimed)"
b19-assert matches "LOG-FORMAT" '"a":"1","level":"error"' "${OUT}"
b19-assert matches "LOG-FORMAT" '"word":"abc"' "${OUT}"

# A signal to the logger’s group leaves gojq running, so the last lines are still parsed
mkfifo "${WORK}/in"
# shellcheck disable=SC2016 # expanded by the logger shell
setsid bash -c 'trap "" TERM USR1; echo "$$" > "$0"; exec b19-log-format warn TAG' "${WORK}/group" \
  < "${WORK}/in" 2> "${WORK}/out" &
LOGGER_PID=$!
exec {FEED}> "${WORK}/in"
printf '%s\n' 'before=1' >&"${FEED}"
for _ in {1..600}
do
  grep --quiet 'before' "${WORK}/out" && break
  sleep 0.1
done
grep --quiet 'before' "${WORK}/out" || { b19-log error "LOG-FORMAT" "$(_p "No record reached %s" "${WORK}/out")"; exit 1; }
kill -TERM -- "-$(< "${WORK}/group")"
kill -USR1 -- "-$(< "${WORK}/group")"
printf '%s\n' 'after=1' >&"${FEED}"
exec {FEED}>&-
wait "${LOGGER_PID}"
b19-assert matches "LOG-FORMAT" '"after":"1"' "$(< "${WORK}/out")"
