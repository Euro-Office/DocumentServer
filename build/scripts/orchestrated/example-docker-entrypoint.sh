#!/usr/bin/env bash
set -e

# Normalize boolean env vars: accept True/TRUE/yes/on/1 (as written by e.g.
# Ansible or compose files) and canonicalize to lowercase true/false. The
# values end up raw inside JSON, where anything else is invalid. Empty values
# are left untouched so the ${VAR:-default} fallbacks still apply.
#
# normalize_bool: an unrecognized value warns and becomes false.
# require_bool:   an unrecognized value aborts startup. Use it for
#                 security-relevant flags (JWT), where silently falling back
#                 to false would disable authentication.
_normalize_bool() {
  local mode="$1" var val
  shift
  for var in "$@"; do
    val="${!var:-}"
    case "${val,,}" in
      "") ;;
      true|yes|y|on|1)  printf -v "$var" '%s' true ;;
      false|no|n|off|0) printf -v "$var" '%s' false ;;
      *)
        if [[ "$mode" == "strict" ]]; then
          echo "ERROR: ${var}='${val}' is not a recognized boolean (use true or false). Refusing to start rather than guess." >&2
          exit 1
        fi
        echo "WARNING: ${var}='${val}' is not a recognized boolean (use true/false); treating it as false" >&2
        printf -v "$var" '%s' false
        ;;
    esac
  done
}
normalize_bool() { _normalize_bool lenient "$@"; }
require_bool()   { _normalize_bool strict "$@"; }

require_bool JWT_ENABLED

export NODE_CONFIG='{
      "server": {
        "siteUrl": "'${DS_URL:-"/"}'",
        "token": {
          "enable": '${JWT_ENABLED:-false}',
          "secret": "'${JWT_SECRET:-euro-office-dev-jwt-secret-key-2026}'",
          "authorizationHeader": "'${JWT_HEADER:-Authorization}'"
        }
      }
    }'

exec "$@"