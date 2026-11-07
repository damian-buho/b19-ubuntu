#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  set -eou pipefail

  # shellcheck source=/dev/null
  . b19-i18n

  FAILED=0

  # Trees a foreign uid reads at run time: every file o+r, every directory o+rx
  for TREE in "${B19_DEPS_PATH}" "${B19_ENTRYPOINT_PATH}" "${B19_HEALTH_PATH}" "${B19_BOOTSTRAP_PATH}" "${B19_COMMAND_PATH}" \
              "${B19_LOG_FORMATS_PATH}" "${B19_OVERLAYS_PATH}" "${B19_TEMPLATES_PATH}" "${B19_TOOLS_PATH}" "${B19_SHELL_PATH}" \
              "${B19_TEST_PATH}" "${B19_BIN_PATH}"; do
    if [ ! -e "${TREE}" ]; then
      b19-log info "POSTURE" "$(_p "Absent, not checked: %s" "${TREE}")"
      continue
    fi
    while IFS= read -r LINE; do
      b19-log error "POSTURE" "$(_p "Unreadable by a foreign uid: %s" "${LINE}")"
      FAILED=$((FAILED + 1))
    done < <(find "${TREE}" -xdev \( \( -type f ! -perm -o=r \) -o \( -type d ! -perm -o=rx \) \) -printf '%m %u:%g %p\n')
  done

  # Directories a foreign uid with --group-add 0 writes at run time: group root, g+wx
  for DIR in "${B19_HOME}" "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_STATE_HOME}" "${B19_RUNTIME_PATH}"; do
    if [ ! -d "${DIR}" ]; then
      b19-log info "POSTURE" "$(_p "Absent, not checked: %s" "${DIR}")"
      continue
    fi
    if [ -z "$(find "${DIR}" -maxdepth 0 -group 0 -perm -g=wx)" ]; then
      b19-log error "POSTURE" "$(_p "Not writable by group root: %s" "$(stat --format '%a %U:%G %n' "${DIR}")")"
      FAILED=$((FAILED + 1))
    fi
  done

  [ "${FAILED}" -eq 0 ] || exit 1
  b19-log good "POSTURE" "$(_ "Runtime paths readable and writable under a foreign uid")"
