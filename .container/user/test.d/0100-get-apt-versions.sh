#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  adduser   --version
  aria2c    --version
  catatonit --version
  curl      --version
  gettext   --version
  gpg       --version
  killall   --version
  pbzip2    --version
  pigz      --version
  tree      --version

  nslookup  -version
  dig       -v

  /usr/bin/time --version

  # pixz -h exits 2 even on success; verify binary presence only
  command -v pixz
