#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail

# pin-ubuntu-digests.sh — Fetch fresh sha256 digests from Docker Hub for Ubuntu tags

# shellcheck source=/dev/null
. '.makefile/core/scripts/reuse-header.sh'

DEPS_DIR=".container/foundation/deps/ubuntu"
TAGS=(noble resolute)

for tag in "${TAGS[@]}"; do
  digest=$(skopeo inspect --format '{{.Digest}}' "docker://docker.io/library/ubuntu:${tag}")
  {
    reuse_header_print
    printf '\n'
    printf '%s\n' "${digest}"
  } > "${DEPS_DIR}/${tag}.sha256.deps"
  printf 'pinned %s → %s\n' "${tag}" "${digest}"
done
