#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Tests for b19-is-immutable, the save-j2 harvest and the b19-materialize layers.

  set -euo pipefail

  T="$(mktemp --directory "${B19_TEMP_PATH:-/tmp}/layers-XXXXXX")"
  trap 'chmod --recursive u+rwx "${T}"; rm --recursive --force "${T}"' EXIT

  # Exit code of b19-is-immutable against the fake mount table.
  answer() {
    local code=0
    env --unset=B19_IMMUTABLE B19_MOUNTINFO_PATH="${T}/mountinfo" b19-is-immutable "$@" 2>/dev/null || code=$?
    printf '%s' "${code}"
  }

  # Exit code of b19-materialize under the given mount table.
  materialize() {
    local code=0
    B19_MOUNTINFO_PATH="$1" b19-materialize 2>/dev/null || code=$?
    printf '%s' "${code}"
  }

  cat > "${T}/mountinfo" <<'EOF'
1 0 0:1 / / ro,relatime - overlay overlay rw
2 1 0:2 / /run/b19 rw,nosuid - tmpfs tmpfs rw
3 1 0:3 / /mnt/rw rw - tmpfs tmpfs rw
4 3 0:4 / /mnt/rw/ro ro - tmpfs tmpfs rw
5 1 0:5 / /mnt/a\040b rw - tmpfs tmpfs rw
6 1 0:6 / /mnt/shadow ro - tmpfs tmpfs rw
7 1 0:7 / /mnt/shadow rw - tmpfs tmpfs rw
8 1 0:8 / /mnt/opt rw,ro_like - tmpfs tmpfs rw
EOF

  b19-assert equals "LAYERS" "0" "$(answer)"
  b19-assert equals "LAYERS" "0" "$(answer /)"
  b19-assert equals "LAYERS" "1" "$(answer /run/b19)"
  b19-assert equals "LAYERS" "1" "$(answer /run/b19/deep/missing)"
  b19-assert equals "LAYERS" "0" "$(answer /run/b19x)"
  b19-assert equals "LAYERS" "0" "$(answer /mnt/rw/ro/file)"
  b19-assert equals "LAYERS" "1" "$(answer /mnt/rw/rox)"
  b19-assert equals "LAYERS" "1" "$(answer '/mnt/a b/file')"
  b19-assert equals "LAYERS" "1" "$(answer /mnt/shadow)"
  b19-assert equals "LAYERS" "1" "$(answer /mnt/opt)"
  b19-assert equals "LAYERS" "2" "$(answer one two)"
  b19-assert equals "LAYERS" "0" "$(B19_IMMUTABLE=Y b19-is-immutable /run/b19 && echo 0)"

  sed 's/ ro,relatime / rw,relatime /' "${T}/mountinfo" > "${T}/mountinfo.rw"
  printf '1 0 0:1 / / ro - overlay overlay rw\n' > "${T}/mountinfo.ro"

  export B19_HOME="${T}/home" B19_RUNTIME_PATH="${T}/run" B19_TEMPLATES_PATH="${T}/layer" B19_OVERLAYS_PATH="${T}/overlays/"
  mkdir --parents "${B19_HOME}/sub" "${B19_RUNTIME_PATH}" "${B19_TEMPLATES_PATH}" "${B19_OVERLAYS_PATH}/alt${B19_HOME}"

  # Harvest moves the template and its companion, then links the final path.
  printf 'a={{ ENV.LAYER_A }}\n' > "${B19_HOME}/sub/a.conf.j2"
  printf 'b={{ B }}\n' > "${B19_HOME}/b.conf.j2"
  printf '{"B": 2}\n' > "${B19_HOME}/b.conf.data.json"
  LAYER_A=build save-j2 "${B19_HOME}" 2>/dev/null

  b19-assert equals "LAYERS" "${B19_RUNTIME_PATH}${B19_HOME}/sub/a.conf" "$(readlink "${B19_HOME}/sub/a.conf")"
  b19-assert equals "LAYERS" "${B19_TEMPLATES_PATH}${B19_HOME}/sub/a.conf.j2" "$(readlink "${B19_HOME}/sub/a.conf.j2")"
  b19-assert equals "LAYERS" "a={{ ENV.LAYER_A }}" "$(<"${B19_HOME}/sub/a.conf.j2")"
  b19-assert equals "LAYERS" "absent" "$([ -e "${B19_HOME}/b.conf.data.json" ] && echo present || echo absent)"
  b19-assert equals "LAYERS" "absent" "$([ -e "${B19_HOME}/.j2.list" ] && echo present || echo absent)"
  b19-assert equals "LAYERS" "a=build" "$(<"${B19_HOME}/sub/a.conf")"
  b19-assert equals "LAYERS" "b=2" "$(<"${B19_HOME}/b.conf")"

  # The start renders from env through the same link, as does a call by the original path.
  export LAYER_A=start
  b19-assert equals "LAYERS" "0" "$(materialize "${T}/mountinfo.rw")"
  parallel-j2 "${B19_HOME}" 2>/dev/null
  b19-assert equals "LAYERS" "a=start" "$(<"${B19_HOME}/sub/a.conf")"
  LAYER_A=direct j2-render "${B19_HOME}/sub/a.conf.j2"
  b19-assert equals "LAYERS" "a=direct" "$(<"${B19_HOME}/sub/a.conf")"

  # A child image’s template replaces the link and the harvested one.
  rm --force "${B19_HOME}/sub/a.conf.j2"
  printf 'a2={{ ENV.LAYER_A }}\n' > "${B19_HOME}/sub/a.conf.j2"
  save-j2 "${B19_HOME}" 2>/dev/null
  b19-assert equals "LAYERS" "a2=start" "$(<"${B19_HOME}/sub/a.conf")"

  # A plain overlay file beats a template at the same final path.
  printf 'overlay\n' > "${B19_OVERLAYS_PATH}alt${B19_HOME}/b.conf"
  B19_OVERLAY=alt materialize "${T}/mountinfo.rw" > /dev/null
  parallel-j2 "${B19_HOME}" 2>/dev/null
  b19-assert equals "LAYERS" "overlay" "$(<"${B19_HOME}/b.conf")"

  # An overlay adds a new path only on a writable root.
  printf 'added\n' > "${B19_OVERLAYS_PATH}alt${B19_HOME}/added.conf"
  B19_OVERLAY=alt materialize "${T}/mountinfo.ro" > /dev/null
  b19-assert equals "LAYERS" "absent" "$([ -e "${B19_HOME}/added.conf" ] && echo present || echo absent)"
  B19_OVERLAY=alt materialize "${T}/mountinfo.rw" > /dev/null
  b19-assert equals "LAYERS" "added" "$(<"${B19_HOME}/added.conf")"

  # A shipped overlay moves the file it shadows to the layer, so an unchosen overlay keeps it.
  printf 'image\n' > "${B19_HOME}/plain.conf"
  printf 'variant\n' > "${B19_OVERLAYS_PATH}alt${B19_HOME}/plain.conf"
  save-j2 "${B19_HOME}" 2>/dev/null
  b19-assert equals "LAYERS" "image" "$(<"${B19_HOME}/plain.conf")"

  # An unwritable runtime fails closed on a read-only root and degrades on a writable one.
  chmod 0555 "${B19_RUNTIME_PATH}"
  if [ ! -w "${B19_RUNTIME_PATH}" ]; then
    b19-assert equals "LAYERS" "1" "$(materialize "${T}/mountinfo.ro")"
    b19-assert equals "LAYERS" "0" "$(materialize "${T}/mountinfo.rw")"
  fi
  chmod 0755 "${B19_RUNTIME_PATH}"

  # A writable runtime with an unwritable entry below it degrades the same way.
  chmod 0555 "${B19_RUNTIME_PATH}${B19_HOME}"
  if [ ! -w "${B19_RUNTIME_PATH}${B19_HOME}" ]; then
    b19-assert equals "LAYERS" "1" "$(materialize "${T}/mountinfo.ro")"
    b19-assert equals "LAYERS" "0" "$(materialize "${T}/mountinfo.rw")"
  fi
  chmod 0755 "${B19_RUNTIME_PATH}${B19_HOME}"

  # An image with no templates has nothing to fail on.
  chmod 0555 "${B19_RUNTIME_PATH}"
  b19-assert equals "LAYERS" "0" "$(B19_TEMPLATES_PATH="${T}/empty" materialize "${T}/mountinfo.ro")"
  chmod 0755 "${B19_RUNTIME_PATH}"

  b19-log info "LAYERS" "Read-only layers passed under ${T}"
