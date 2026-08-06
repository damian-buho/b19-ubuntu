#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  b19-fetch "TEST"                                    \
    "https://www.rfc-editor.org/rfc/rfc2616.txt"      \
    "test-file"                                       \
    "98492708851aa3b919c618cf9b5832d3b922a9e1097f9812391f3ab37a24466040486774df3587e967c40a45902a4702c44a3447b0ca31daa981cd6cfb5541b3"

  if [ -f "${B19_TEMP_PATH:-}/test-file" ]
  then
    rm "${B19_TEMP_PATH:-}/test-file"
    exit 0
  else
    exit 1
  fi
