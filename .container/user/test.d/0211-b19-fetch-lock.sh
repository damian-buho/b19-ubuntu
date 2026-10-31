#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  _stub="$(mktemp --directory)"
  trap 'rm -rf "${_stub}"' EXIT
  # Preallocates the cache file, then holds the download open until the gate file appears
  aria2c() {
    local _prev="" _a _out=""
    for _a in "$@"; do
      if [ "${_prev}" = "--out" ]; then _out="${_a}"; fi
      _prev="${_a}"
    done
    : > "${B19_DOWNLOAD_PATH}/${_out}"
    : > "${STUB_DIR}/started"
    until [ -e "${STUB_DIR}/gate" ]; do sleep 0.1; done
    printf 'complete\n' > "${B19_DOWNLOAD_PATH}/${_out}"
  }
  export -f aria2c

  # Polls up to 5 min for COMMAND to succeed
  wait_until() {
    local _try
    for _try in $(seq 3000); do
      "$@" && return 0
      sleep 0.1
    done
    b19-log error "FETCH-LOCK" "$(_p "%s still false after %s tries" "$*" "${_try}")"
    return 1
  }
  # True once the second fetch has exited or reached the lock
  second_parked() {
    ! kill -0 "${_second}" 2>/dev/null || grep -q "Waiting for lock" "${_stub}/second.out"
  }

  export STUB_DIR="${_stub}"
  export B19_FETCH_LOCAL_CACHE=N B19_FETCH_DOCKER_CACHE=Y B19_OFFGRID_MODE=N B19_DOWNLOAD_ATTEMPTS=1
  export B19_DOWNLOAD_DISK_CACHE=64m B19_DOWNLOAD_MAX_TRIES=1 B19_DOWNLOAD_RETRY_WAIT=1
  export B19_DOWNLOAD_PATH="${_stub}/dl"
  mkdir -p "${B19_DOWNLOAD_PATH}" "${_stub}/first" "${_stub}/second"

  B19_TEMP_PATH="${_stub}/first" b19-fetch "TEST" "https://example.com/f.tar.gz" "shared-file" > "${_stub}/first.out" 2>&1 &
  _first=$!
  wait_until test -e "${_stub}/started"
  B19_VERBOSITY=debug NO_COLOR=1 B19_TEMP_PATH="${_stub}/second" b19-fetch "TEST" "https://example.com/f.tar.gz" "shared-file" > "${_stub}/second.out" 2>&1 &
  _second=$!
  wait_until second_parked
  : > "${_stub}/gate"
  wait "${_first}"
  wait "${_second}"

  b19-assert equals "FETCH-LOCK" "complete" "$(cat "${_stub}/second/shared-file")"
