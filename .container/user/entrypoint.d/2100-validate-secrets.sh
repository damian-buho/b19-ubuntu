#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# Validate required secrets are present
# Secrets can be provided via:
#   1. Environment variables (B19_* format)
#   2. Docker secrets files (/run/secrets/b19.*)
#
# Required secrets are defined in B19_REQUIRED_SECRETS (space-separated list)
# Format: b19.{category}.{service}.{key}
# Example: b19.storage.mariadb.password

# Skip if secrets are disabled
if [[ "${B19_SECRETS_ENABLED:-}" == "false" ]]; then
  b19-log info "SECRETS" "$(_ "Secrets validation disabled (B19_SECRETS_ENABLED=false)")"
  return 0
fi

if [ "${ENTRYPOINT_COMMAND_EXECUTED:-N}" = "Y" ]
then
    return 0
fi

MISSING_SECRETS=""
LOADED_SECRETS=""
SECRET_COUNT=0

# Skip validation if no secrets are required
if [[ -z "${B19_REQUIRED_SECRETS:-}" ]]; then
  b19-log info "SECRETS" "$(_ "No required secrets defined, skipping validation")"
  return 0
fi

b19-log info "SECRETS" "$(_ "Validating required secrets...")"

for secret_name in ${B19_REQUIRED_SECRETS}; do
  SECRET_COUNT=$((SECRET_COUNT + 1))
  # Convert dot notation to env var format
  # d9t.mariadb.password -> D9T_MARIADB_PASSWORD
  env_var_name=$(echo "${secret_name}" | tr '-' '_' | tr '.' '_' | tr '[:lower:]' '[:upper:]')

  secret_file="${B19_SECRETS_PATH}/${secret_name}"

  # Check if env var is set (non-empty)
  if [[ -n "${!env_var_name:-}" ]]; then
    LOADED_SECRETS="${LOADED_SECRETS} ${secret_name}(env)"
    continue
  fi

  # Check if secret file exists
  if [[ -f "${secret_file}" ]]; then
    LOADED_SECRETS="${LOADED_SECRETS} ${secret_name}(file)"
    continue
  fi

  # Secret is missing
  MISSING_SECRETS="${MISSING_SECRETS} ${secret_name}"
done

# Report loaded secrets
if [[ -n "${LOADED_SECRETS}" ]]; then
  b19-log good "SECRETS" "$(_p "Loaded:%s" "${LOADED_SECRETS}")"
fi

# Fail-fast if secrets are missing
if [[ -n "${MISSING_SECRETS}" ]]; then
  b19-log error "SECRETS" "$(_p "Missing required secrets:%s" "${MISSING_SECRETS}")"
  b19-log error "SECRETS" "$(_ "Provide secrets via:")"
  b19-log error "SECRETS" "$(_p "  - Environment variables (%s format)" "${env_var_name}")"
  b19-log error "SECRETS" "$(_p "  - Docker secrets files (%s/b19.* format)" "${B19_SECRETS_PATH}")"
  exit 1
fi

b19-log good "SECRETS" "$(_p "All %d required secrets validated" "${SECRET_COUNT}")"
