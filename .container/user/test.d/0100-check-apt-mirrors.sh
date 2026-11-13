#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  list="/etc/apt/mirrors/ubuntu.list"
  sources="$(cat /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null || true)"

  # Sources name the mirror list, never a bare mirror URI
  b19-assert matches "APTMIRRORS" "mirror[+]file:${list}" "${sources}"
  # The primary mirror is the first entry and the only one with a priority
  b19-assert matches "APTMIRRORS" $'^https?://[^\t ]+\tpriority:1$' "$(awk '!/^#/ && NF' "${list}" | head --lines 1)"
  b19-assert equals "APTMIRRORS" "1" "$(awk '/priority:/ {n++} END {print n + 0}' "${list}")"
  # No mirror is listed twice, trailing slash ignored
  b19-assert equals "APTMIRRORS" "0" "$(awk '!/^#/ && NF {sub(/\/$/, "", $1); print $1}' "${list}" | sort | uniq --repeated | wc --lines)"
