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

merged_config=$(run_config \
  REDIS_SERVER_HOST=generated-host \
  REDIS_SERVER_PWD=redis-pass \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"host":"override-host","options":{"socket":{"tls":true}}}}}}')
assert_config "$merged_config" '
  .services.CoAuthoring.redis.host == "override-host" and
  .services.CoAuthoring.redis.options.socket.tls == true and
  .services.CoAuthoring.redis.options.password == "redis-pass" and
  .services.CoAuthoring.redis.port == 6379 and
  .services.CoAuthoring.sql.type == "postgres"
'

for invalid_config in '{' '[]' 'null' 'true' '"text"'; do
  if run_config NODE_CONFIG="$invalid_config" >"$TRACE" 2>&1; then
    echo "invalid NODE_CONFIG was accepted" >&2
    exit 1
  fi
  grep -Fq 'must be valid JSON objects' "$TRACE"
done

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

for tls in false true; do
  standalone_tls_config=$(run_config REDIS_SERVER_TLS="$tls")
  assert_config "$standalone_tls_config" "
    (.services.CoAuthoring.redis.options.socket.tls // false) == $tls
  "
  cluster_tls_config=$(run_config REDIS_SERVER_TLS="$tls" REDIS_CLUSTER_NODES='cluster-a:7000')
  scheme=redis
  [[ "$tls" == true ]] && scheme=rediss
  assert_config "$cluster_tls_config" "
    (.services.CoAuthoring.redis.optionsCluster.defaults.socket.tls // false) == $tls and
    .services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: \"$scheme://cluster-a:7000\"}]
  "
  for sentinel_tls in false true; do
    sentinel_tls_config=$(run_config REDIS_SERVER_TLS="$tls" REDIS_SENTINEL_TLS="$sentinel_tls" \
      REDIS_SENTINEL_NODES='sentinel-a:26379')
    assert_config "$sentinel_tls_config" "
      (.services.CoAuthoring.redis.options.socket.tls // false) == $tls and
      (.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.socket.tls // false) == $tls and
      (.services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.socket.tls // false) == $sentinel_tls
    "
  done
done

empty_tls_config=$(run_config REDIS_SERVER_TLS= REDIS_SENTINEL_TLS=)
assert_config "$empty_tls_config" '.services.CoAuthoring.redis.options | has("socket") | not'

for tls_flag in REDIS_SERVER_TLS REDIS_SENTINEL_TLS; do
  if run_config "$tls_flag=invalid" >"$TRACE" 2>&1; then
    echo "$tls_flag accepted an invalid boolean" >&2
    exit 1
  fi
  grep -Fq "$tls_flag must be true or false" "$TRACE"
done

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
