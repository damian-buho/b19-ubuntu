#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # Rewrite assertion via function doubles (exported into the b19-fetch
  # child shell): no network, the doubles record probe URL and aria2c args.
  _stub="$(mktemp -d)"
  trap 'rm -rf "${_stub}"' EXIT
  check-reachable() {
    printf '%s' "$2" > "${STUB_DIR}/probe"
    return 0
  }
  aria2c() {
    printf '%s\n' "$@" > "${STUB_DIR}/args"
    printf '%s\n' "${@: -1}" >> "${STUB_DIR}/calls"
    if [ "${NEAR_CODE:-0}" -ne 0 ] && [[ "${*: -1}" == http*://*kiota-http-cache* ]]; then return "${NEAR_CODE}"; fi
    _prev=""
    for _a in "$@"; do
      if [ "${_prev}" = "--out" ]; then touch "${B19_DOWNLOAD_PATH}/${_a}"; fi
      _prev="${_a}"
    done
    return 0
  }
  export -f check-reachable aria2c

  export STUB_DIR="${_stub}"
  export B19_FETCH_LOCAL_CACHE=N B19_FETCH_DOCKER_CACHE=N B19_OFFGRID_MODE=N B19_DOWNLOAD_ATTEMPTS=1
  export B19_DOWNLOAD_DISK_CACHE=64m B19_DOWNLOAD_MAX_TRIES=1 B19_DOWNLOAD_RETRY_WAIT=1
  export B19_DOWNLOAD_PATH="${_stub}/dl" B19_TEMP_PATH="${_stub}/tmp"
  mkdir -p "${B19_DOWNLOAD_PATH}" "${B19_TEMP_PATH}"

  M6E_NEAR_CACHE_HOST=kiota-http-cache M6E_NEAR_CACHE_PORT=8080 M6E_NEAR_CACHE_SCHEME=http \
    b19-fetch "TEST" "https://example.com/file.tar.gz" "http-file" "dummyhash"
  grep -qx "http://kiota-http-cache:8080/" "${_stub}/probe"
  grep -qx "http://kiota-http-cache:8080/example.com/file.tar.gz" "${_stub}/args"

  M6E_NEAR_CACHE_HOST=cache.local \
    b19-fetch "TEST" "https://example.com/other.tar.gz" "https-file" "dummyhash"
  grep -qx "https://cache.local/" "${_stub}/probe"
  grep -qx "https://cache.local/example.com/other.tar.gz" "${_stub}/args"

  # cache refuses with 403 (aria2c exit 22): origin fetched once, both URLs logged
  : > "${_stub}/calls"
  NEAR_CODE=22 M6E_NEAR_CACHE_HOST=kiota-http-cache M6E_NEAR_CACHE_PORT=8080 M6E_NEAR_CACHE_SCHEME=http \
    b19-fetch "TEST" "https://example.com/a.tar.gz" "fb-file" "dummyhash" > "${_stub}/out" 2>&1
  [ "$(grep -c '^https://example.com/a.tar.gz$' "${_stub}/calls")" -eq 1 ]
  [ "$(grep -c '^http://kiota-http-cache' "${_stub}/calls")" -eq 1 ]
  grep -q "falling back to origin" "${_stub}/out"
  grep -q "http://kiota-http-cache:8080/example.com/a.tar.gz" "${_stub}/out"
  grep -q "https://example.com/a.tar.gz" "${_stub}/out"

  # cache fails on every attempt: origin runs only after the last one
  : > "${_stub}/calls"
  B19_DOWNLOAD_ATTEMPTS=2 NEAR_CODE=22 M6E_NEAR_CACHE_HOST=kiota-http-cache M6E_NEAR_CACHE_PORT=8080 M6E_NEAR_CACHE_SCHEME=http \
    b19-fetch "TEST" "https://example.com/b.tar.gz" "fb-file2" "dummyhash" > /dev/null 2>&1
  [ "$(grep -c '^http://kiota-http-cache' "${_stub}/calls")" -eq 2 ]
  [ "$(tail -n 1 "${_stub}/calls")" = "https://example.com/b.tar.gz" ]

  # offgrid with a failing cache: no request at all, build fails
  : > "${_stub}/calls"
  if B19_OFFGRID_MODE=Y NEAR_CODE=22 M6E_NEAR_CACHE_HOST=kiota-http-cache \
    b19-fetch "TEST" "https://example.com/c.tar.gz" "fb-file3" "dummyhash" > /dev/null 2>&1
  then exit 1; fi
  [ ! -s "${_stub}/calls" ]

  # healthy cache: origin never touched
  : > "${_stub}/calls"
  M6E_NEAR_CACHE_HOST=kiota-http-cache M6E_NEAR_CACHE_PORT=8080 M6E_NEAR_CACHE_SCHEME=http \
    b19-fetch "TEST" "https://example.com/d.tar.gz" "fb-file4" "dummyhash"
  ! grep -q '^https://example.com/' "${_stub}/calls"
