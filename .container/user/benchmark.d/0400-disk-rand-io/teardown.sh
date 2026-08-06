#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# shellcheck source=/dev/null
. b19-i18n

b19-log info "BENCH.D" "$(_p "Removing: %s" "fio")"
apt-get remove -y -qq fio 2>/dev/null || true
rm -f "${B19_TEMP_PATH:-/tmp}"/randread.* 2>/dev/null || true
