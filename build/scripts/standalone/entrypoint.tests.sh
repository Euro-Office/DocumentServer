#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
ENTRYPOINT="$SCRIPT_DIR/entrypoint.sh"
DEFAULT_CONFIG="$ROOT_DIR/server/Common/config/default.json"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

run_entrypoint() {
  local name=$1
  shift
  local case_dir="$TMP_DIR/$name"
  mkdir -p "$case_dir/conf" "$case_dir/data"
  cp "$DEFAULT_CONFIG" "$case_dir/conf/local.json"

  env -i \
    PATH="$PATH" \
    EO_CONF="$case_dir/conf" \
    DATA_DIR="$case_dir/data" \
    ENTRYPOINT_CONFIG_ONLY=true \
    JWT_ENABLED=false \
    GENERATE_FONTS=false \
    PLUGINS_ENABLED=false \
    AMQP_URI=amqp://unused \
    "$@" \
    sh "$ENTRYPOINT" >"$case_dir/output" 2>&1

  printf '%s' "$case_dir/conf/local.json"
}

assert_config() {
  local config=$1
  local expression=$2
  jq -e "$expression" "$config" >/dev/null
}

standalone_config=$(run_entrypoint standalone REDIS_SERVER_USER=redis-user REDIS_SERVER_PASS=redis-pass REDIS_SERVER_DB=2)
assert_config "$standalone_config" '
  .services.CoAuthoring.redis.options == {
    username: "redis-user",
    password: "redis-pass",
    database: 2
  } and
  .services.CoAuthoring.redis.optionsCluster == {} and
  .services.CoAuthoring.redis.optionsSentinel == {}
'

cluster_config=$(run_entrypoint cluster \
  REDIS_SERVER_USER=redis-user \
  REDIS_SERVER_PASS=redis-pass \
  REDIS_CLUSTER_NODES="cluster-a:7000 redis://cluster-b:7001")
assert_config "$cluster_config" '
  .services.CoAuthoring.redis.optionsCluster == {
    rootNodes: [
      {url: "redis://cluster-a:7000"},
      {url: "redis://cluster-b:7001"}
    ],
    defaults: {username: "redis-user", password: "redis-pass"}
  } and
  .services.CoAuthoring.redis.optionsSentinel == {}
'

sentinel_config=$(run_entrypoint sentinel \
  REDIS_SERVER_USER=redis-user \
  REDIS_SERVER_PASS=redis-pass \
  REDIS_SERVER_DB=2 \
  REDIS_SENTINEL_GROUP_NAME=mymaster \
  REDIS_SENTINEL_NODES="sentinel-a:26379, sentinel-b:26380" \
  REDIS_SENTINEL_USER=sentinel-user \
  REDIS_SENTINEL_PASS=sentinel-pass)
assert_config "$sentinel_config" '
  .services.CoAuthoring.redis.optionsCluster == {} and
  .services.CoAuthoring.redis.optionsSentinel == {
    name: "mymaster",
    sentinelRootNodes: [
      {host: "sentinel-a", port: 26379},
      {host: "sentinel-b", port: 26380}
    ],
    nodeClientOptions: {
      database: 2,
      username: "redis-user",
      password: "redis-pass"
    },
    sentinelClientOptions: {
      username: "sentinel-user",
      password: "sentinel-pass"
    }
  }
'

for tls in false true; do
  standalone_tls_config=$(run_entrypoint "standalone_tls_$tls" REDIS_SERVER_TLS="$tls")
  assert_config "$standalone_tls_config" "
    (.services.CoAuthoring.redis.options.socket.tls // false) == $tls
  "
  cluster_tls_config=$(run_entrypoint "cluster_tls_$tls" \
    REDIS_SERVER_TLS="$tls" REDIS_CLUSTER_NODES='cluster-a:7000')
  scheme=redis
  [[ "$tls" == true ]] && scheme=rediss
  assert_config "$cluster_tls_config" "
    (.services.CoAuthoring.redis.optionsCluster.defaults.socket.tls // false) == $tls and
    .services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: \"$scheme://cluster-a:7000\"}]
  "
  for sentinel_tls in false true; do
    sentinel_tls_config=$(run_entrypoint "sentinel_tls_${tls}_$sentinel_tls" \
      REDIS_SERVER_TLS="$tls" REDIS_SENTINEL_TLS="$sentinel_tls" REDIS_SENTINEL_NODES='sentinel-a:26379')
    assert_config "$sentinel_tls_config" "
      (.services.CoAuthoring.redis.options.socket.tls // false) == $tls and
      (.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.socket.tls // false) == $tls and
      (.services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.socket.tls // false) == $sentinel_tls
    "
  done
done

empty_tls_config=$(run_entrypoint empty_tls REDIS_SERVER_TLS= REDIS_SENTINEL_TLS=)
assert_config "$empty_tls_config" '.services.CoAuthoring.redis.options | has("socket") | not'

# NODE_CONFIG topology settings must suppress the legacy single-node wait even
# when the REDIS_SENTINEL_* environment API is not used.
node_config_sentinel='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{"name":"mymaster","sentinelRootNodes":[{"host":"sentinel-a","port":26379}]}}}}}'
node_config_result=$(run_entrypoint node_config_sentinel \
  REDIS_SERVER_HOST=unavailable-redis \
  NODE_CONFIG="$node_config_sentinel")
assert_config "$node_config_result" '.services.CoAuthoring.redis.optionsSentinel == {}'

node_config_cluster='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[{"url":"redis://cluster-a:7000"}]}}}}}'
node_config_result=$(run_entrypoint node_config_cluster \
  REDIS_SERVER_HOST=unavailable-redis \
  NODE_CONFIG="$node_config_cluster")
assert_config "$node_config_result" '.services.CoAuthoring.redis.optionsCluster == {}'

expect_failure() {
  local name=$1
  local expected=$2
  shift 2
  local case_dir="$TMP_DIR/$name"
  mkdir -p "$case_dir/conf" "$case_dir/data"
  cp "$DEFAULT_CONFIG" "$case_dir/conf/local.json"

  if env -i \
    PATH="$PATH" \
    EO_CONF="$case_dir/conf" \
    DATA_DIR="$case_dir/data" \
    ENTRYPOINT_CONFIG_ONLY=true \
    JWT_ENABLED=false \
    AMQP_URI=amqp://unused \
    "$@" \
    sh "$ENTRYPOINT" >"$case_dir/output" 2>&1; then
    echo "$name unexpectedly succeeded" >&2
    return 1
  fi
  grep -Fq "$expected" "$case_dir/output"
}

expect_failure malformed_separator 'empty node entries' \
  REDIS_SENTINEL_NODES='sentinel-a:26379,,sentinel-b:26380'
expect_failure malformed_host 'each node must use host:port' \
  REDIS_SENTINEL_NODES='sentinel/a:26379'
expect_failure incomplete_sentinel 'REDIS_SENTINEL_NODES is not set' \
  REDIS_SENTINEL_GROUP_NAME=mymaster
expect_failure invalid_redis_tls 'REDIS_SERVER_TLS must be true or false' REDIS_SERVER_TLS=invalid
expect_failure invalid_sentinel_tls 'REDIS_SENTINEL_TLS must be true or false' REDIS_SENTINEL_TLS=invalid

echo 'standalone entrypoint Redis configuration: PASS'
