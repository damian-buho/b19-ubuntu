#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Stage-independent: any stage may fetch through the TLS near cache, so the
  # build host's root is trusted for the whole stage and dropped again in
  # always/post — inside the same RUN, so no layer ever carries it.

  trust-ca-certificates install
