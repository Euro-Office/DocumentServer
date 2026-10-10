#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/docker-entrypoint.sh"
TRACE=$(mktemp)
trap 'rm -f "$TRACE"' EXIT

run_config() {
  env -i \
    PATH="$PATH" \
    COMPANY_NAME=euro-office \
    JWT_ENABLED=false \
    ENTRYPOINT_CONFIG_ONLY=true \
    "$@" \
    bash "$ENTRYPOINT" docservice
}

assert_config() {
  local config=$1
  local expression=$2
  printf '%s' "$config" | jq -e "$expression" >/dev/null
}

unauthenticated_config=$(run_config \
  EDITOR_DATA_STORAGE=editorDataRedis \
  EDITOR_STAT_STORAGE=editorDataRedis \
  REDIS_SENTINEL_NODES='sentinel-a:26379 sentinel-b:26380')
assert_config "$unauthenticated_config" '
  .services.CoAuthoring.redis.optionsSentinel == {
    name: "mymaster",
    sentinelRootNodes: [
      {host: "sentinel-a", port: 26379},
      {host: "sentinel-b", port: 26380}
    ],
    nodeClientOptions: {database: 0},
    sentinelClientOptions: {}
  } and
  .services.CoAuthoring.redis.optionsCluster == {} and
  .services.CoAuthoring.server.editorDataStorage == "editorDataRedis" and
  .services.CoAuthoring.server.editorStatStorage == "editorDataRedis"
'

omitted_stat_config=$(run_config EDITOR_DATA_STORAGE=editorDataRedis)
assert_config "$omitted_stat_config" '
  .services.CoAuthoring.server.editorDataStorage == "editorDataRedis" and
  .services.CoAuthoring.server.editorStatStorage == "editorDataRedis"
'

authenticated_config=$(run_config \
  REDIS_SERVER_USER=redis-user \
  REDIS_SERVER_PWD=redis-pass \
  REDIS_SENTINEL_USER=sentinel-user \
  REDIS_SENTINEL_PWD=sentinel-pass \
  REDIS_SENTINEL_NODES='sentinel-a:26379')
assert_config "$authenticated_config" '
  .services.CoAuthoring.redis.optionsSentinel == {
    name: "mymaster",
    sentinelRootNodes: [{host: "sentinel-a", port: 26379}],
    nodeClientOptions: {database: 0, username: "redis-user", password: "redis-pass"},
    sentinelClientOptions: {username: "sentinel-user", password: "sentinel-pass"}
  }
'

set +e
env -i \
  PATH="$PATH" \
  COMPANY_NAME=euro-office \
  JWT_ENABLED=false \
  REDIS_SENTINEL_NODES='sentinel-a:26379' \
  REDIS_CLUSTER_NODES='cluster-a:7000' \
  bash "$ENTRYPOINT" docservice >"$TRACE" 2>&1
status=$?
set -e

if [[ $status -eq 0 ]] || ! grep -Fq 'Redis Sentinel and Redis Cluster cannot be configured together' "$TRACE"; then
  echo "conflicting Redis topologies were not rejected" >&2
  cat "$TRACE" >&2
  exit 1
fi

set +e
env -i \
  PATH="$PATH" \
  COMPANY_NAME=euro-office \
  JWT_ENABLED=false \
  REDIS_SENTINEL_NODES='sentinel-a:26379,,sentinel-b:26380' \
  bash "$ENTRYPOINT" docservice >"$TRACE" 2>&1
status=$?
set -e

if [[ $status -eq 0 ]] || ! grep -Fq 'empty node entries' "$TRACE"; then
  echo "malformed Sentinel node list was not rejected" >&2
  cat "$TRACE" >&2
  exit 1
fi

set +e
env -i \
  PATH="$PATH" \
  COMPANY_NAME=euro-office \
  JWT_ENABLED=false \
  EDITOR_DATA_STORAGE='../not-a-module' \
  bash "$ENTRYPOINT" docservice >"$TRACE" 2>&1
status=$?
set -e

if [[ $status -eq 0 ]] || ! grep -Fq 'EDITOR_DATA_STORAGE must be a plain module name' "$TRACE"; then
  echo "invalid editor-data storage name was not rejected" >&2
  cat "$TRACE" >&2
  exit 1
fi

echo "orchestrated entrypoint Redis and editor-data configuration: PASS"
