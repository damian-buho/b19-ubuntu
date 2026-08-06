#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# shellcheck source=/dev/null
. b19-i18n

b19-log info "BENCH.D" "$(_p "Installing: %s" "hyperfine")"
apt-get install -y --no-install-recommends -qq hyperfine
