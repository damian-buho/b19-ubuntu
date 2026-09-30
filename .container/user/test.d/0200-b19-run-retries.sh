#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  # Fails twice, then passes on the third attempt
  : >/tmp/b19-run-retries.count
  # shellcheck disable=SC2016 # expanded by the child bash
  b19-run --retries 2 --backoff 1 "TEST" "$(_ "Retry a flaky command")" -- \
    bash -c 'echo x >>/tmp/b19-run-retries.count; [ "$(wc --lines </tmp/b19-run-retries.count)" -ge 3 ]'
  ATTEMPTS="$(wc --lines </tmp/b19-run-retries.count)"
  rm --force /tmp/b19-run-retries.count
  [ "${ATTEMPTS}" -eq 3 ] || { b19-log error "TEST" "$(_p "Expected 3 attempts, got %s" "${ATTEMPTS}")"; exit 1; }

  # A hung command dies with timeout(1)'s 124
  RC=0
  b19-run --timeout 1 "TEST" "$(_ "Time out a hung command")" -- sleep 30 || RC=$?
  [ "${RC}" -eq 124 ] || { b19-log error "TEST" "$(_p "Expected exit code 124, got %s" "${RC}")"; exit 1; }
