#!/usr/bin/env bash
set -e
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