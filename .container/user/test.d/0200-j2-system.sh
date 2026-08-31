#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Tests for the J2 template system: j2-render, save-j2, parallel-j2

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  PASS=0
  FAIL=0

  assert_exists() {
    if [ ! -f "$1" ]; then
      b19-log error "TEST" "$(_p "Expected %s to exist" "$1")"
      FAIL=$((FAIL + 1))
      return 1
    fi
    PASS=$((PASS + 1))
  }

  assert_not_exists() {
    if [ -f "$1" ]; then
      b19-log error "TEST" "$(_p "Expected %s to NOT exist" "$1")"
      FAIL=$((FAIL + 1))
      return 1
    fi
    PASS=$((PASS + 1))
  }

  assert_content() {
    local file="$1" expected="$2"
    local actual
    actual=$(cat "${file}")
    if [ "${actual}" != "${expected}" ]; then
      b19-log error "TEST" "$(_p "Content mismatch in %s: expected '%s', got '%s'" "${file}" "${expected}" "${actual}")"
      FAIL=$((FAIL + 1))
      return 1
    fi
    PASS=$((PASS + 1))
  }

  # ═══════════════════════════════════════════════════════════════════
  # j2-render
  # ═══════════════════════════════════════════════════════════════════
  T=$(mktemp -d)
  trap 'rm -rf "${T}"' EXIT

  # Basic rendering — ENV variable expansion
  echo 'Hello {{ ENV.WORLD }}' > "${T}/greeting.txt.j2"
  WORLD=world j2-render "${T}/greeting.txt.j2"
  assert_exists "${T}/greeting.txt"
  assert_content "${T}/greeting.txt" "Hello world"

  # Output strips .j2 suffix, same directory
  assert_not_exists "${T}/greeting.txt.j2.rendered"

  # Nested directory
  mkdir -p "${T}/sub/deep"
  echo '{{ ENV.VAL }}' > "${T}/sub/deep/nested.j2"
  VAL=ok j2-render "${T}/sub/deep/nested.j2"
  assert_content "${T}/sub/deep/nested" "ok"

  # Companion data file (.data.json) — provides root-level vars, not ENV.*
  echo 'port={{ PORT }}' > "${T}/svc.conf.j2"
  echo '{"PORT": 8080}' > "${T}/svc.conf.data.json"
  unset PORT
  j2-render "${T}/svc.conf.j2"
  assert_content "${T}/svc.conf" "port=8080"

  # ═══════════════════════════════════════════════════════════════════
  # save-j2
  # ═══════════════════════════════════════════════════════════════════
  D=$(mktemp -d)

  echo '{{ ENV.A }}' > "${D}/a.j2"
  echo '{{ ENV.B }}' > "${D}/b.j2"
  mkdir -p "${D}/sub"
  echo '{{ ENV.C }}' > "${D}/sub/c.j2"

  A=1 B=2 C=3 save-j2 "${D}"

  # .j2.list should exist and contain all three templates
  assert_exists "${D}/.j2.list"
  LIST_COUNT=$(wc -l < "${D}/.j2.list")
  if [ "${LIST_COUNT}" -ne 3 ]; then
    b19-log error "TEST" "$(_p "Expected 3 templates in .j2.list, got %s" "${LIST_COUNT}")"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi

  # All templates should be rendered
  assert_content "${D}/a" "1"
  assert_content "${D}/b" "2"
  assert_content "${D}/sub/c" "3"

  # B19_J2_EXCLUDE_PATTERNS — skip a directory
  E=$(mktemp -d)
  echo '{{ ENV.X }}' > "${E}/keep.j2"
  mkdir -p "${E}/node_modules"
  echo '{{ ENV.Y }}' > "${E}/node_modules/skip.j2"

  B19_J2_EXCLUDE_PATTERNS="node_modules" X=ok Y=no save-j2 "${E}"
  assert_exists "${E}/keep"
  assert_content "${E}/keep" "ok"
  assert_not_exists "${E}/node_modules/skip"

  # ═══════════════════════════════════════════════════════════════════
  # parallel-j2
  # ═══════════════════════════════════════════════════════════════════

  # Basic rendering from .j2.list
  P=$(mktemp -d)
  echo '{{ ENV.P1 }}' > "${P}/x.j2"
  echo '{{ ENV.P2 }}' > "${P}/y.j2"
  printf '%s\n' "${P}/x.j2" "${P}/y.j2" > "${P}/.j2.list"

  P1=alpha P2=beta NUMPROCS=1 parallel-j2 "${P}"
  assert_content "${P}/x" "alpha"
  assert_content "${P}/y" "beta"

  # B19_IMMUTABLE=Y — skip rendering
  Q=$(mktemp -d)
  echo '{{ ENV.Q }}' > "${Q}/immutable.j2"
  printf '%s\n' "${Q}/immutable.j2" > "${Q}/.j2.list"

  # shellcheck disable=SC2097,SC2098 # prefix vars set ENV for minijinja-cli --env
  B19_IMMUTABLE=Y Q=nope NUMPROCS=1 parallel-j2 "${Q}"
  assert_not_exists "${Q}/immutable"

  # B19_J2_SKIP_FILES — skip matching basenames, render the rest
  S=$(mktemp -d)
  echo '{{ ENV.S1 }}' > "${S}/keep.j2"
  echo '{{ ENV.S2 }}' > "${S}/robots.txt.j2"
  echo '{{ ENV.S3 }}' > "${S}/also.j2"
  printf '%s\n' "${S}/also.j2" "${S}/keep.j2" "${S}/robots.txt.j2" > "${S}/.j2.list"

  B19_J2_SKIP_FILES="robots.txt" S1=a S2=b S3=c NUMPROCS=1 parallel-j2 "${S}"
  assert_content "${S}/keep" "a"
  assert_content "${S}/also" "c"
  assert_not_exists "${S}/robots.txt"
  # Verify skip actually filtered: rendered count must be 2, not 3
  RENDERED=0
  for f in "${S}"/*; do
    case "${f}" in *.j2|*.j2.list) continue;; esac
    RENDERED=$((RENDERED + 1))
  done
  if [ "${RENDERED}" -ne 2 ]; then
    b19-log error "TEST" "$(_p "Expected 2 rendered files, got %s (skip filter broken?)" "${RENDERED}")"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi

  # Multiple comma-separated skips
  R=$(mktemp -d)
  echo '{{ ENV.R1 }}' > "${R}/only.j2"
  echo '{{ ENV.R2 }}' > "${R}/skip1.j2"
  echo '{{ ENV.R3 }}' > "${R}/skip2.j2"
  printf '%s\n' "${R}/only.j2" "${R}/skip1.j2" "${R}/skip2.j2" > "${R}/.j2.list"

  B19_J2_SKIP_FILES="skip1,skip2" R1=ok NUMPROCS=1 parallel-j2 "${R}"
  assert_content "${R}/only" "ok"
  assert_not_exists "${R}/skip1"
  assert_not_exists "${R}/skip2"
  RENDERED=0
  for f in "${R}"/*; do
    case "${f}" in *.j2|*.j2.list) continue;; esac
    RENDERED=$((RENDERED + 1))
  done
  if [ "${RENDERED}" -ne 1 ]; then
    b19-log error "TEST" "$(_p "Expected 1 rendered file, got %s (skip filter broken?)" "${RENDERED}")"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi

  # --final: renders then deletes source templates, preserves skipped ones
  F=$(mktemp -d)
  echo '{{ ENV.F }}' > "${F}/doomed.j2"
  echo '{{ ENV.G }}' > "${F}/survivor.j2"
  printf '%s\n' "${F}/doomed.j2" "${F}/survivor.j2" > "${F}/.j2.list"

  # shellcheck disable=SC2097,SC2098 # prefix vars set ENV for minijinja-cli --env
  B19_J2_SKIP_FILES="survivor.j2" F=yes G=yes NUMPROCS=1 parallel-j2 --final "${F}"
  assert_content "${F}/doomed" "yes"
  assert_not_exists "${F}/doomed.j2"
  assert_exists "${F}/survivor.j2"
  assert_not_exists "${F}/.j2.list"
  # Verify --final actually deleted: source count must be 1 (survivor only)
  SOURCE_COUNT=0
  for f in "${F}"/*.j2; do
    [ -f "${f}" ] && SOURCE_COUNT=$((SOURCE_COUNT + 1))
  done
  if [ "${SOURCE_COUNT}" -ne 1 ]; then
    b19-log error "TEST" "$(_p "Expected 1 source .j2 remaining, got %s (--final delete broken?)" "${SOURCE_COUNT}")"
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi

  # ═══════════════════════════════════════════════════════════════════
  # Summary
  # ═══════════════════════════════════════════════════════════════════
  if [ "${FAIL}" -gt 0 ]; then
    b19-log error "TEST" "$(_p "%s failed, %s passed" "${FAIL}" "${PASS}")"
    exit 1
  fi

  b19-log info "TEST" "$(_p "J2 system: %s assertions passed" "${PASS}")"
