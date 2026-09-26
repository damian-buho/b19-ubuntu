#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

  # Opt-in: remaps B19_USER to B19_PUID/B19_PGID only when started as root.
  if [ -z "${B19_PUID:-}" ]
  then
    b19-log debug "REMAP" "$(_p "B19_PUID unset, keeping uid %s" "$(id --user)")"
    return 0
  fi

  if ! [[ "${B19_PUID}${B19_PGID:-}" =~ ^[0-9]+$ ]]
  then
    b19-log error "REMAP" "$(_p "B19_PUID=%s B19_PGID=%s must be numeric" "${B19_PUID}" "${B19_PGID:-}")"
    exit 1
  fi

  _remap_owner="$(getent passwd "${B19_PUID}" | cut --delimiter=: --fields=1)" || true
  if [ -n "${_remap_owner}" ] && [ "${_remap_owner}" != "${B19_USER}" ]
  then
    b19-log error "REMAP" "$(_p "B19_PUID=%s already belongs to %s" "${B19_PUID}" "${_remap_owner}")"
    exit 1
  fi

  if [ "$(id --user)" = "${B19_PUID}" ]
  then
    b19-log debug "REMAP" "$(_p "Already running as uid %s" "${B19_PUID}")"
    return 0
  fi

  if [ "$(id --user)" -ne 0 ]
  then
    b19-log warn "REMAP" "$(_p "B19_PUID=%s ignored: uid %s is not root, start with --user 0" "${B19_PUID}" "$(id --user)")"
    return 0
  fi

  b19-run "REMAP" "$(_p "Set uid of %s to %s" "${B19_USER}" "${B19_PUID}")" -- \
    usermod --uid "${B19_PUID}" "${B19_USER}"

  if [ -n "${B19_PGID:-}" ]
  then
    _remap_owner="$(getent group "${B19_PGID}" | cut --delimiter=: --fields=1)" || true
    if [ -n "${_remap_owner}" ] && [ "${_remap_owner}" != "${B19_GROUP}" ]
    then
      b19-log error "REMAP" "$(_p "B19_PGID=%s already belongs to %s" "${B19_PGID}" "${_remap_owner}")"
      exit 1
    fi
    b19-run "REMAP" "$(_p "Set gid of %s to %s" "${B19_GROUP}" "${B19_PGID}")" -- \
      groupmod --gid "${B19_PGID}" "${B19_GROUP}"
  fi

  # Group stays 0 so the g+rwX arbitrary-uid posture of the home survives.
  if [ "$(stat --format=%u "${B19_HOME}")" != "${B19_PUID}" ]
  then
    b19-run "REMAP" "$(_p "Set owner of %s to %s" "${B19_HOME}" "${B19_PUID}")" -- \
      chown --recursive "${B19_PUID}" "${B19_HOME}"
  fi
  unset _remap_owner
  export B19_UID="${B19_PUID}" B19_GID="${B19_PGID:-${B19_GID}}"

  b19-log info "REMAP" "$(_p "Dropping root, restarting entrypoint as %s:%s" "${B19_PUID}" "${B19_PGID:-$(id --group "${B19_USER}")}")"
  exec setpriv --reuid="${B19_USER}" --regid="${B19_GROUP}" --init-groups -- entrypoint.d "$@"
