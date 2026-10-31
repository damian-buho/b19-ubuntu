#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

set -euo pipefail
# shellcheck source=b19-i18n

# Bytes of an IEC size (512Mi, 4Gi, 1024), or fails on any other shape
to_bytes() {
  local _num _unit _exp
  [[ "$1" =~ ^([0-9]+)(Ki|Mi|Gi|Ti|Pi)?$ ]] || return 1
  _num="${BASH_REMATCH[1]}"
  _unit="${BASH_REMATCH[2]}"
  case "${_unit}" in
    Ki) _exp=1 ;; Mi) _exp=2 ;; Gi) _exp=3 ;; Ti) _exp=4 ;; Pi) _exp=5 ;; *) _exp=0 ;;
  esac
  echo $(( 10#${_num} * (1 << (10 * _exp)) ))
}

# Human form of a byte count for log lines
human() {
  numfmt --to=iec-i --suffix=B --format="%.2f" "$1"
}

WARN_PERCENT="${B19_HEALTH_DISK_WARN_PERCENT}"
NEAR_FILE="${B19_TEMP_PATH}/healthcheck.d/disk-budget.near"
DECLARED=0
OVER=()
NEAR=()

if ! [[ "${WARN_PERCENT}" =~ ^[1-9][0-9]?$|^100$ ]]; then
  b19-log error "HEALTH.D" "$(_p "B19_HEALTH_DISK_WARN_PERCENT=%s is not a percentage from 1 to 100" "${WARN_PERCENT}")"
  exit 1
fi

for BUDGET_VAR in $(compgen -v B19_DISK_BUDGET_ || true); do
  BUDGET="${!BUDGET_VAR}"
  PATH_VAR="${BUDGET_VAR#B19_DISK_BUDGET_}"
  if [ -z "${BUDGET}" ]; then
    b19-log debug "HEALTH.D" "$(_p "%s is empty, no budget" "${BUDGET_VAR}")"
    continue
  fi
  DECLARED=$((DECLARED + 1))
  # The suffix names the variable that holds the path
  TARGET=""
  [ -z "${PATH_VAR}" ] || TARGET="${!PATH_VAR:-}"
  if ! BUDGET_BYTES=$(to_bytes "${BUDGET}") || [[ "${TARGET}" != /* ]]; then
    b19-log error "HEALTH.D" "$(_p "%s=%s: needs an IEC size and %s holding an absolute path, found '%s'" "${BUDGET_VAR}" "${BUDGET}" "${PATH_VAR}" "${TARGET}")"
    OVER+=("${BUDGET_VAR}")
    continue
  fi
  if [ ! -e "${TARGET}" ]; then
    b19-log warn "HEALTH.D" "$(_p "%s (%s) does not exist, not checked" "${TARGET}" "${PATH_VAR}")"
    continue
  fi
  DU_OUT=$(nice --adjustment=19 ionice --class=2 --classdata=7 \
    du --summarize --one-file-system --block-size=1 -- "${TARGET}" 2>/dev/null) \
    || b19-log warn "HEALTH.D" "$(_p "Some entries under %s are unreadable, its usage is a lower bound" "${TARGET}")"
  USED="${DU_OUT%%[[:space:]]*}"
  if ! [[ "${USED}" =~ ^[0-9]+$ ]]; then
    b19-log warn "HEALTH.D" "$(_p "Cannot measure %s" "${TARGET}")"
    OVER+=("${TARGET}")
  elif [ "${USED}" -gt "${BUDGET_BYTES}" ]; then
    b19-log warn "HEALTH.D" "$(_p "%s uses %s, over its budget of %s" "${TARGET}" "$(human "${USED}")" "$(human "${BUDGET_BYTES}")")"
    OVER+=("${TARGET}($(human "${USED}")>$(human "${BUDGET_BYTES}"))")
  elif [ $(( USED * 100 )) -ge $(( BUDGET_BYTES * WARN_PERCENT )) ]; then
    b19-log warn "HEALTH.D" "$(_p "%s uses %s, %s%% or more of its budget of %s" "${TARGET}" "$(human "${USED}")" "${WARN_PERCENT}" "$(human "${BUDGET_BYTES}")")"
    NEAR+=("${TARGET}")
  else
    b19-log good "HEALTH.D" "$(_p "%s uses %s of its %s budget" "${TARGET}" "$(human "${USED}")" "$(human "${BUDGET_BYTES}")")"
  fi
done

# Paths near their budget go to the container log once, when that set changes
WAS_NEAR=""
[ ! -f "${NEAR_FILE}" ] || WAS_NEAR=$(<"${NEAR_FILE}")
if [ "${NEAR[*]}" != "${WAS_NEAR}" ]; then
  mkdir --parents "${NEAR_FILE%/*}"
  printf '%s\n' "${NEAR[*]}" >"${NEAR_FILE}.$$"
  mv --force "${NEAR_FILE}.$$" "${NEAR_FILE}"
  if [ "${#NEAR[@]}" -gt 0 ]; then
    { b19-log warn "HEALTH.D" "$(_p "Near the disk budget (%s%%): %s" "${WARN_PERCENT}" "${NEAR[*]}")" 2>>"${B19_HEALTH_LOG_TARGET:-/proc/1/fd/2}"; } 2>/dev/null \
      || b19-log debug "HEALTH.D" "$(_p "Cannot write to %s" "${B19_HEALTH_LOG_TARGET:-/proc/1/fd/2}")"
  fi
fi

if [ "${#OVER[@]}" -gt 0 ]; then
  b19-log error "HEALTH.D" "$(_p "%s of %s disk budgets failed: %s" "${#OVER[@]}" "${DECLARED}" "${OVER[*]}")"
  exit 1
fi
b19-log good "HEALTH.D" "$(_p "All %s disk budgets hold" "${DECLARED}")"
exit 0
