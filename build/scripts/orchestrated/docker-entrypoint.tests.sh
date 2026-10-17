#!/usr/bin/env bash
# Run from the repository root:
#   bash build/scripts/orchestrated/docker-entrypoint.tests.sh
# Requires Bash, jq, GNU timeout, and standard Linux utilities. Runs without
# root, initialized submodules, or live services; checks generated JSON and
# validation failures. Each entrypoint invocation is bounded, with captured
# diagnostics printed before temporary files are removed on failure.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/docker-entrypoint.sh"
TMP_DIR=$(mktemp -d)
cleanup() {
  local status=$?
  if (( status != 0 )); then
    echo "Orchestrated entrypoint tests failed (exit $status). Captured diagnostics:" >&2
    local diagnostic_dir="$TMP_DIR"
    if [[ -f "$TMP_DIR/current-case" ]]; then
      local case_name
      case_name=$(cat "$TMP_DIR/current-case")
      echo "Case: $case_name" >&2
      diagnostic_dir="$TMP_DIR/$case_name"
    fi
    while IFS= read -r file; do
      echo "--- ${file#"$TMP_DIR/"} ---" >&2
      cat "$file" >&2
    done < <(find "$diagnostic_dir" -name output -type f | sort)
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_config() {
  local name=$1
  shift
  printf '%s\n' "$name" >"$TMP_DIR/current-case"
  mkdir -p "$TMP_DIR/$name"
  local status=0
  timeout -k 2s 10s env -i \
    PATH="$PATH" \
    COMPANY_NAME=euro-office \
    JWT_ENABLED=false \
    ENTRYPOINT_CONFIG_ONLY=true \
    "$@" \
    bash "$ENTRYPOINT" docservice >"$TMP_DIR/$name/output" 2>&1 || status=$?
  if (( status != 0 )); then
    echo "$name: entrypoint exited $status" >>"$TMP_DIR/$name/output"
    return "$status"
  fi
  printf '%s' "$TMP_DIR/$name/output"
}

assert_config() {
  local config=$1 expression=$2
  if ! jq -e "$expression" "$config" >/dev/null; then
    echo "${config#"$TMP_DIR/"}: failed assertion: $expression" >&2
    cat "$config" >&2
    return 1
  fi
}

expect_failure() {
  local name=$1 expected=$2
  shift 2
  local status=0
  run_config "$name" "$@" >/dev/null || status=$?
  if (( status == 0 || status == 124 || status == 137 )); then
    echo "$name: expected a validation failure, got exit $status" >&2
    return 1
  fi
  if ! grep -Fq "$expected" "$TMP_DIR/$name/output"; then
    echo "$name: missing diagnostic: $expected" >&2
    return 1
  fi
}

merged_config=$(run_config merged \
  REDIS_SERVER_HOST=generated-host \
  REDIS_SERVER_PWD=redis-pass \
  REDIS_SERVER_TLS=true \
  NODE_CONFIG='{
    "services":{"CoAuthoring":{"redis":{
      "host":"override-host","options":{"socket":{"ca":"test-ca"}}
    }}},
    "FileConverter":{"converter":{"inputLimits":[{"type":"docx"}]}}
  }')
assert_config "$merged_config" '
  .services.CoAuthoring.redis.host == "override-host" and
  .services.CoAuthoring.redis.options.socket.tls == true and
  .services.CoAuthoring.redis.options.socket.ca == "test-ca" and
  .services.CoAuthoring.redis.options.password == "redis-pass" and
  .services.CoAuthoring.redis.port == 6379 and
  .services.CoAuthoring.sql.type == "postgres" and
  .FileConverter.converter.inputLimits == [{type: "docx"}]
'

custom_tls_config=$(run_config custom_tls \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"options":{"socket":{"tls":true}}}}}}')
assert_config "$custom_tls_config" '.services.CoAuthoring.redis.options.socket.tls == true'

empty_override_config=$(run_config empty_override NODE_CONFIG=)
assert_config "$empty_override_config" '.services.CoAuthoring.sql.type == "postgres"'

diagnostic_password='diagnostic-password-do-not-log'
assert_private_diagnostic() {
  local name=$1
  if grep -Fq "$diagnostic_password" "$TMP_DIR/$name/output"; then
    echo "$name: configuration password leaked in diagnostics" >&2
    return 1
  fi
}

expect_failure invalid_generated 'Generated configuration must be a valid JSON object' \
  DB_PWD="$diagnostic_password\"" ENTRYPOINT_CONFIG_ONLY=false
assert_private_diagnostic invalid_generated
expect_failure invalid_generated_with_override 'Generated configuration must be a valid JSON object' \
  DB_PWD="$diagnostic_password\"" NODE_CONFIG='{}'
assert_private_diagnostic invalid_generated_with_override

invalid_index=0
for invalid_config in \
    "{\"password\":\"$diagnostic_password\"" '[]' 'null' 'true' 'false' '"text"' '{} {}' ' '; do
  name="invalid_node_config_$((invalid_index++))"
  expect_failure "$name" 'Supplied NODE_CONFIG must be a valid JSON object' \
    DB_PWD="$diagnostic_password" NODE_CONFIG="$invalid_config"
  assert_private_diagnostic "$name"
done

unauthenticated_config=$(run_config unauthenticated \
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

omitted_stat_config=$(run_config omitted_stat EDITOR_DATA_STORAGE=editorDataRedis)
assert_config "$omitted_stat_config" '
  .services.CoAuthoring.server.editorDataStorage == "editorDataRedis" and
  .services.CoAuthoring.server.editorStatStorage == "editorDataRedis"
'

authenticated_config=$(run_config authenticated \
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
  standalone_tls_config=$(run_config "standalone_tls_$tls" REDIS_SERVER_TLS="$tls")
  assert_config "$standalone_tls_config" "
    (.services.CoAuthoring.redis.options.socket.tls // false) == $tls
  "
  cluster_tls_config=$(run_config "cluster_tls_$tls" REDIS_SERVER_TLS="$tls" REDIS_CLUSTER_NODES='cluster-a:7000')
  scheme=redis
  [[ "$tls" == true ]] && scheme=rediss
  assert_config "$cluster_tls_config" "
    (.services.CoAuthoring.redis.optionsCluster.defaults.socket.tls // false) == $tls and
    .services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: \"$scheme://cluster-a:7000\"}]
  "
  for sentinel_tls in false true; do
    sentinel_tls_config=$(run_config "sentinel_tls_${tls}_$sentinel_tls" \
      REDIS_SERVER_TLS="$tls" REDIS_SENTINEL_TLS="$sentinel_tls" \
      REDIS_SENTINEL_NODES='sentinel-a:26379')
    assert_config "$sentinel_tls_config" "
      (.services.CoAuthoring.redis.options.socket.tls // false) == $tls and
      (.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.socket.tls // false) == $tls and
      (.services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.socket.tls // false) == $sentinel_tls
    "
  done
done

empty_tls_config=$(run_config empty_tls REDIS_SERVER_TLS= REDIS_SENTINEL_TLS=)
assert_config "$empty_tls_config" '.services.CoAuthoring.redis.options | has("socket") | not'

for tls_flag in REDIS_SERVER_TLS REDIS_SENTINEL_TLS; do
  expect_failure "invalid_$tls_flag" "$tls_flag must be true or false" "$tls_flag=invalid"
done

expect_failure conflicting_topologies 'Redis Sentinel and Redis Cluster cannot be configured together' \
  REDIS_SENTINEL_NODES='sentinel-a:26379' REDIS_CLUSTER_NODES='cluster-a:7000'
expect_failure invalid_storage 'EDITOR_DATA_STORAGE must be a plain module name' \
  EDITOR_DATA_STORAGE='../not-a-module'

redis_test_config() { run_config "$@"; }
. "$SCRIPT_DIR/../redis-topology.test-cases.sh"

sentinel_db_config=$(run_config sentinel_database REDIS_SERVER_DB_NUM=4 REDIS_SENTINEL_NODES='sentinel-a:26379')
assert_config "$sentinel_db_config" '.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.database == 4'

standalone_db_config=$(run_config standalone_database REDIS_SERVER_DB_NUM=4)
assert_config "$standalone_db_config" '.services.CoAuthoring.redis.options.db == "4"'

echo "orchestrated entrypoint Redis and editor-data configuration: PASS"
