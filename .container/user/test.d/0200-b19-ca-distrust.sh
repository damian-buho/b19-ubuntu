#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  FAILED=0
  WORK="$(mktemp --directory "${B19_TEMP_PATH:-/tmp}/ca-distrust.XXXXXX")"
  trap 'rm --recursive --force "${WORK}"' EXIT

  # Fails the test when the actual value differs from the expected one
  expect() {
    local _want="$1" _got="$2" _case="$3"
    if [ "${_want}" != "${_got}" ]; then
      b19-log error "CA-DISTRUST" "$(_p "Case %s: expected %s, got %s" "${_case}" "${_want}" "${_got}")"
      FAILED=$((FAILED + 1))
    fi
  }

  # Writes a throwaway self-signed certificate and prints its fingerprint
  make_cert() {
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj "/CN=$1" \
      -keyout "${WORK}/$1.key" -out "${WORK}/$1.pem" 2>/dev/null
    openssl x509 -noout -fingerprint -sha256 -in "${WORK}/$1.pem" | sed --expression 's/.*=//' --expression 's/://g'
  }

  SHIPPED="$(b19-ca-distrust list)"
  expect "1" "$(grep --count --fixed-strings 86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B <<<"${SHIPPED}")" "shipped list"
  awk -v dir="${WORK}" '/BEGIN CERTIFICATE/ { n++ } n { print > (dir "/system-" n ".pem") }' /etc/ssl/certs/ca-certificates.crt
  for CERT in "${WORK}"/system-*.pem; do
    PRINT="$(openssl x509 -noout -fingerprint -sha256 -in "${CERT}" | sed --expression 's/.*=//' --expression 's/://g')"
    if grep --quiet --fixed-strings --line-regexp "${PRINT}" <<<"${SHIPPED}"; then
      b19-log error "CA-DISTRUST" "$(_p "System bundle still trusts %s" "${PRINT}")"
      FAILED=$((FAILED + 1))
    fi
  done

  BAD="$(make_cert bad)"
  GOOD="$(make_cert good)"
  { printf '# bad\n'; cat "${WORK}/bad.pem"; printf '# good\n'; cat "${WORK}/good.pem"; printf '# tail\n'; } > "${WORK}/bundle.pem"
  B19_CA_DISTRUST="$(sed 's/../&:/g; s/:$//' <<<"${BAD,,}")" B19_CA_DISTRUST_DIR="${WORK}/none" b19-ca-distrust bundle "${WORK}/bundle.pem"
  expect "1" "$(grep --count BEGIN "${WORK}/bundle.pem")" "bundle keeps one certificate"
  expect "${GOOD}" "$(openssl x509 -noout -fingerprint -sha256 -in "${WORK}/bundle.pem" | sed --expression 's/.*=//' --expression 's/://g')" "bundle keeps the trusted one"
  expect "0" "$(grep --count '^# bad$' "${WORK}/bundle.pem" || true)" "bundle drops the comment above"
  expect "1" "$(grep --count '^# tail$' "${WORK}/bundle.pem")" "bundle keeps trailing text"

  expect "0" "$(B19_CA_DISTRUST_ENABLED=false b19-ca-distrust list 2>/dev/null | wc --lines)" "disabled list"
  expect "1" "$(B19_CA_DISTRUST="${BAD:0:63}, ${BAD}" B19_CA_DISTRUST_DIR="${WORK}/none" b19-ca-distrust list | wc --lines)" "63-digit entry ignored"

  [ "${FAILED}" -eq 0 ] || exit 1
  b19-log good "CA-DISTRUST" "$(_p "All %s distrusted fingerprints are absent from the system bundle" "$(wc --lines <<<"${SHIPPED}")")"
