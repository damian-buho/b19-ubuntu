#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT


  if [[ -n "${B19_UID:-}" && -n "${B19_GROUP:-}" ]]; then
    DIRS=(
      "${B19_BIN_PATH}"
      "${B19_BOOTSTRAP_LOCK_PATH}"
      "${B19_BUILD_PATH}"
      "${B19_COMMAND_PATH}"
      "${B19_DEPS_PATH}"
      "${B19_ENTRYPOINT_PATH}"
      "${B19_HEALTH_PATH}"
      "${B19_HOME}"
      "${B19_OVERLAYS_PATH}"
      "${B19_SHELL_PATH}"
      "${B19_TEMP_PATH}"
      "${B19_TEST_PATH}"
      "${B19_TOOLS_PATH}"
      "${XDG_CACHE_HOME}"
      "${XDG_CONFIG_HOME}"
      "${XDG_DATA_HOME}"
      "${XDG_STATE_HOME}"
    )

    for DIR in "${DIRS[@]}"; do
      b19-run "SECURITY" "$(_p "Ensure exists %s" "${DIR}")"  --      \
        mkdir -p "${DIR}"
      b19-run "SECURITY" "$(_p "Set owner %s:0 %s" "${B19_UID}" "${DIR}")"  --      \
        chown -R "${B19_UID}:0" "${DIR}"
    done

    b19-run "SECURITY" "$(_p "Set permissions of %s" "${B19_HOME}")" --  chmod -R g+rwX "${B19_HOME}"

    # ${B19_CACHE_PATH} is the parent of the build-time download cache mount.
    # b19-fetch creates ${B19_DOWNLOAD_PATH} below it, so uid ${B19_UID} needs
    # write access here. The chown and the chmod stay NON-recursive on purpose:
    # the cache mounted below is shared with every other build on the host, and
    # a recursive call rewrites its content.
    b19-run "SECURITY" "$(_p "Ensure exists %s" "${B19_CACHE_PATH}")"  --      \
      mkdir -p "${B19_CACHE_PATH}"
    b19-run "SECURITY" "$(_p "Set owner %s:0 %s" "${B19_UID}" "${B19_CACHE_PATH}")"  --      \
      chown "${B19_UID}:0" "${B19_CACHE_PATH}"
    b19-run "SECURITY" "$(_p "Set permissions of %s" "${B19_CACHE_PATH}")" --  chmod g+rwX "${B19_CACHE_PATH}"
  fi
