#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  if [ -n "${B19_HEALTH_MEMORY_THRESHOLD:-}" ]
  then
    # Rootless runtimes may not delegate the memory controller, so
    # memory.current is absent; we cannot measure, so skip instead of fail
    if [ ! -f /sys/fs/cgroup/memory.current ]; then
        b19-log warn "MEMORY" "$(_ "memory.current unavailable (memory controller not delegated); skipping memory check")"
        exit 0
    fi

    read -r CGROUP_MEMORY_USED_BYTES < /sys/fs/cgroup/memory.current

    CGROUP_MEMORY_USED_MB=$(( CGROUP_MEMORY_USED_BYTES / 1048576 ))

    b19-log info "MEMORY" "$(_p "Total memory used by the container: %s MB" "${CGROUP_MEMORY_USED_MB}")"

    if [ "${CGROUP_MEMORY_USED_MB}" -gt "${B19_HEALTH_MEMORY_THRESHOLD:-}" ]; then
        b19-log bad "MEMORY" "$(_p "Total memory usage (%s MB) exceeds the threshold (%s MB)" "${CGROUP_MEMORY_USED_MB}" "${B19_HEALTH_MEMORY_THRESHOLD:-}")"
        exit 1
    else
        b19-log good "MEMORY" "$(_p "Total memory usage is within the threshold (%s MB)" "${B19_HEALTH_MEMORY_THRESHOLD:-}")"
        exit 0
    fi
  fi
