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

# Set ORCHESTRATED_TEST_LOCAL_JSON to a JSON document to provide it as the
# local.json that node-config loads from NODE_CONFIG_DIR.
run_config() {
  local name=$1
  shift
  printf '%s\n' "$name" >"$TMP_DIR/current-case"
  mkdir -p "$TMP_DIR/$name/conf"
  if [[ -n "${ORCHESTRATED_TEST_LOCAL_JSON:-}" ]]; then
    printf '%s\n' "$ORCHESTRATED_TEST_LOCAL_JSON" >"$TMP_DIR/$name/conf/local.json"
  fi
  local status=0
  timeout -k 2s 10s env -i \
    PATH="$PATH" \
    COMPANY_NAME=euro-office \
    NODE_CONFIG_DIR="$TMP_DIR/$name/conf" \
    JWT_ENABLED=false \
    ENTRYPOINT_CONFIG_ONLY=true \
    ENTRYPOINT_CONFIG_ONLY_OUTPUT="$TMP_DIR/$name/config.json" \
    "$@" \
    bash "$ENTRYPOINT" docservice >"$TMP_DIR/$name/output" 2>&1 || status=$?
  if (( status != 0 )); then
    echo "$name: entrypoint exited $status" >>"$TMP_DIR/$name/output"
    return "$status"
  fi
  printf '%s' "$TMP_DIR/$name/config.json"
}

# What the server uses: local.json under the exported NODE_CONFIG.
effective_config() {
  local config=$1
  local saved="${config%/config.json}/conf/local.json"
  if [[ -f "$saved" ]]; then
    jq -s '.[0] * .[1]' "$saved" "$config" >"${config%.json}.effective.json"
  else
    cp "$config" "${config%.json}.effective.json"
  fi
  printf '%s' "${config%.json}.effective.json"
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
    nodeClientOptions: {},
    sentinelClientOptions: {}
  } and
  .services.CoAuthoring.redis.optionsCluster == null and
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
    nodeClientOptions: {username: "redis-user", password: "redis-pass"},
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
      (.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions | has(\"socket\") | not) and
      (.services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.socket.tls // false) == $sentinel_tls
    "
  done
done

cluster_tls_disabled=$(run_config cluster_tls_disabled \
  REDIS_SERVER_TLS=true REDIS_CLUSTER_NODES='cluster-a:7000,cluster-b:7001' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"defaults":{"socket":{"tls":false}}}}}}}')
assert_config "$cluster_tls_disabled" '
  .services.CoAuthoring.redis.optionsCluster == {
    rootNodes: [{url: "redis://cluster-a:7000"}, {url: "redis://cluster-b:7001"}],
    defaults: {socket: {tls: false}}
  }
'

cluster_tls_enabled=$(run_config cluster_tls_enabled \
  REDIS_SERVER_TLS=false REDIS_CLUSTER_NODES='cluster-a:7000' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"defaults":{"socket":{"tls":true}}}}}}}')
assert_config "$cluster_tls_enabled" '
  .services.CoAuthoring.redis.optionsCluster == {
    rootNodes: [{url: "rediss://cluster-a:7000"}],
    defaults: {socket: {tls: true}}
  }
'

cluster_custom_roots=$(run_config cluster_custom_roots \
  REDIS_SERVER_TLS=false REDIS_CLUSTER_NODES='cluster-a:7000' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[{"url":"rediss://custom:7010"}],"defaults":{"socket":{"tls":true}}}}}}}')
assert_config "$cluster_custom_roots" \
  '.services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: "rediss://custom:7010"}]'

empty_tls_config=$(run_config empty_tls REDIS_SERVER_TLS= REDIS_SENTINEL_TLS=)
assert_config "$empty_tls_config" '.services.CoAuthoring.redis.options | has("socket") | not'

for tls_flag in REDIS_SERVER_TLS REDIS_SENTINEL_TLS; do
  expect_failure "invalid_$tls_flag" "$tls_flag='invalid' is not a recognized boolean" "$tls_flag=invalid"
done

expect_failure conflicting_topologies 'Redis Sentinel and Redis Cluster cannot be configured together' \
  REDIS_SENTINEL_NODES='sentinel-a:26379' REDIS_CLUSTER_NODES='cluster-a:7000'
expect_failure cluster_with_sentinel_override 'Redis Sentinel and Redis Cluster cannot be configured together' \
  REDIS_CLUSTER_NODES='cluster-a:7000' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{"name":"mymaster","sentinelRootNodes":[{"host":"sentinel-a","port":26379}]}}}}}'
expect_failure sentinel_with_cluster_override 'Redis Sentinel and Redis Cluster cannot be configured together' \
  REDIS_SENTINEL_NODES='sentinel-a:26379' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[{"url":"redis://cluster-a:7000"}]}}}}}'
empty_sentinel_override=$(run_config empty_sentinel_override REDIS_CLUSTER_NODES='cluster-a:7000' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{}}}}}')
assert_config "$empty_sentinel_override" \
  '.services.CoAuthoring.redis.optionsCluster.rootNodes | length == 1'
expect_failure invalid_storage 'EDITOR_DATA_STORAGE must be a plain module name' \
  EDITOR_DATA_STORAGE='../not-a-module'

redis_test_config() { run_config "$@"; }
redis_test_local_config() {
  local local_json=$1 config
  shift
  config=$(ORCHESTRATED_TEST_LOCAL_JSON="$local_json" run_config "$@") || return $?
  effective_config "$config"
}
redis_test_local_failure() {
  local local_json=$1
  shift
  ORCHESTRATED_TEST_LOCAL_JSON="$local_json" expect_failure "$@"
}
REDIS_TEST_PASSWORD_VAR=REDIS_SERVER_PWD
REDIS_TEST_LOCAL_SENTINEL_FALLBACK=true
. "$SCRIPT_DIR/../redis-topology.test-cases.sh"

sentinel_db_config=$(run_config sentinel_database REDIS_SERVER_DB_NUM=4 REDIS_SENTINEL_NODES='sentinel-a:26379')
assert_config "$sentinel_db_config" '.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.database == 4'
expect_failure invalid_sentinel_database 'the Redis database must be a non-negative integer' \
  REDIS_SERVER_DB_NUM=oops REDIS_SENTINEL_NODES='sentinel-a:26379'

sentinel_base_db_config=$(run_config sentinel_base_database \
  REDIS_SENTINEL_NODES='sentinel-a:26379' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"options":{"db":4}}}}}')
assert_config "$sentinel_base_db_config" \
  '(.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.database // .services.CoAuthoring.redis.options.db) == 4'

standalone_db_config=$(run_config standalone_database REDIS_SERVER_DB_NUM=4)
assert_config "$standalone_db_config" '.services.CoAuthoring.redis.options.database == 4'
expect_failure invalid_database 'the Redis database must be a non-negative integer' REDIS_SERVER_DB_NUM=oops

# --------------------------------------------------------------------
# local.json from NODE_CONFIG_DIR (Helm extraConf)
# --------------------------------------------------------------------

# Credentials in local.json survive the Helm chart's REDIS_SERVER_USER=default
# with an empty REDIS_SERVER_PWD, for the base options and for Sentinel node
# clients. The configured username applies, not `default`.
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"options":{"username":"app","password":"file-pass"}}}}}' \
  run_config local_password REDIS_SERVER_USER=default REDIS_SERVER_PWD= REDIS_SERVER_DB_NUM=0 \
  REDIS_SENTINEL_NODES=sentinel-a:26379)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.options == {username: "app", password: "file-pass", database: 0} and
  (.services.CoAuthoring.redis.options + .services.CoAuthoring.redis.optionsSentinel.nodeClientOptions) ==
    {username: "app", password: "file-pass", database: 0}
'

# node-config reads local.json as JSON5: comments and trailing commas work.
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{
  // Helm extraConf
  "services": {"CoAuthoring": {
    "sql": {"dbHost": "db", /* not a comment: "//" */ "dbName": "a//b/*c*/",},
    "redis": {"options": {"username": "app", "password": "file-pass",},},
  },},
}' run_config local_json5 REDIS_SERVER_USER=default REDIS_SERVER_PWD=)
assert_config "$config" '.services.CoAuthoring.redis.options == {}'
if grep -Fq 'could not parse' "$TMP_DIR/local_json5/output"; then
  echo 'local_json5: comments and trailing commas were not accepted' >&2
  exit 1
fi

# Environment credentials and database replace those in local.json together.
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"options":{"username":"app","password":"old","database":5}}}}}' \
  run_config local_credentials REDIS_SERVER_USER=default REDIS_SERVER_PWD=pw REDIS_SERVER_DB_NUM=2)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.options == {username: "default", password: "pw", database: 2}
'

# Seeds follow TLS enabled in local.json.
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"defaults":{"socket":{"tls":true,"ca":"file-ca"}}}}}}}' \
  run_config local_cluster_tls REDIS_CLUSTER_NODES=cluster-a:7000)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: "rediss://cluster-a:7000"}] and
  .services.CoAuthoring.redis.optionsCluster.defaults.socket == {tls: true, ca: "file-ca"}
'

# The TLS flags also apply to a topology configured in local.json.
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{
    "rootNodes":[{"url":"redis://file-cluster:7000"}],"defaults":{"socket":{"ca":"file-ca"}}}}}}}' \
  run_config local_cluster_env_tls REDIS_SERVER_TLS=yes)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.optionsCluster == {
    rootNodes: [{url: "rediss://file-cluster:7000"}],
    defaults: {socket: {ca: "file-ca", tls: true}}
  }
'
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{
    "name":"file-master","sentinelRootNodes":[{"host":"file-sentinel","port":26379}],
    "nodeClientOptions":{"socket":{"ca":"node-ca"}},"sentinelClientOptions":{"socket":{"ca":"sentinel-ca"}}}}}}}' \
  run_config local_sentinel_env_tls REDIS_SERVER_TLS=1 REDIS_SENTINEL_TLS=On)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.optionsSentinel.nodeClientOptions.socket == {ca: "node-ca", tls: true} and
  .services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.socket == {ca: "sentinel-ca", tls: true}
'
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{
    "name":"file-master","sentinelRootNodes":[{"host":"file-sentinel","port":26379}]}}}}}' \
  run_config local_sentinel_no_tls)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.optionsSentinel ==
    {name: "file-master", sentinelRootNodes: [{host: "file-sentinel", port: 26379}]}
'

# An environment topology replaces the other one in local.json (null, not {}).
config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{
    "name":"file-master","sentinelRootNodes":[{"host":"file-sentinel","port":26379}]}}}}}' \
  run_config local_sentinel_env_cluster REDIS_CLUSTER_NODES=cluster-a:7000)
effective=$(effective_config "$config")
assert_config "$effective" '
  .services.CoAuthoring.redis.optionsSentinel == null and
  .services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: "redis://cluster-a:7000"}]
'
ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[{"url":"redis://file-cluster:7000"}]}}}}}' \
  expect_failure local_cluster_override_sentinel 'Redis Sentinel and Redis Cluster cannot be configured together' \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{"name":"mymaster","sentinelRootNodes":[{"host":"sentinel-a","port":26379}]}}}}}'

# A local.json that still does not parse is left to the server, which reports
# it; the entrypoint warns without quoting it.
config=$(ORCHESTRATED_TEST_LOCAL_JSON="{\"services\":{\"CoAuthoring\":{\"redis\":{\"options\":{\"password\":\"$diagnostic_password\"" \
  run_config local_invalid DB_PWD="$diagnostic_password")
grep -Fq 'could not parse' "$TMP_DIR/local_invalid/output" || {
  echo 'local_invalid: missing warning' >&2
  exit 1
}
assert_private_diagnostic local_invalid

# --------------------------------------------------------------------
# Mistyped overrides are rejected (see redis-topology.test-cases.sh).
# --------------------------------------------------------------------
expect_failure cluster_defaults_string \
  'services.CoAuthoring.redis.optionsCluster.defaults in NODE_CONFIG must be a JSON object' \
  REDIS_CLUSTER_NODES=cluster-a:7000 \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"defaults":"x"}}}}}'

# --------------------------------------------------------------------
# Configuration-only mode without an output file says so.
# --------------------------------------------------------------------
mkdir -p "$TMP_DIR/config_only_no_output"
timeout -k 2s 10s env -i PATH="$PATH" COMPANY_NAME=euro-office \
  NODE_CONFIG_DIR="$TMP_DIR/config_only_no_output" JWT_ENABLED=false ENTRYPOINT_CONFIG_ONLY=true \
  bash "$ENTRYPOINT" docservice >"$TMP_DIR/config_only_no_output/output" 2>&1
grep -Fq 'set ENTRYPOINT_CONFIG_ONLY_OUTPUT' "$TMP_DIR/config_only_no_output/output" || {
  echo 'config_only_no_output: missing note' >&2
  exit 1
}

# --------------------------------------------------------------------
# Secrets stay off jq command lines and out of the container log.
# --------------------------------------------------------------------
real_jq=$(command -v jq)
mkdir -p "$TMP_DIR/argv-bin"
cat >"$TMP_DIR/argv-bin/jq" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"\$JQ_ARGV_LOG"
exec "$real_jq" "\$@"
EOF
chmod +x "$TMP_DIR/argv-bin/jq"
argv_secrets=(jwt-secret-on-argv-0123456789abcdef db-pass-on-argv amqp-pass-on-argv
  redis-pass-on-argv sentinel-pass-on-argv wopi-key-on-argv link-secret-on-argv override-secret-on-argv
  sentinel-user-on-argv)
for topology in sentinel cluster; do
  topology_env=(REDIS_SENTINEL_NODES=sentinel-a:26379 REDIS_SENTINEL_USER="${argv_secrets[8]}"
    REDIS_SENTINEL_PWD="${argv_secrets[4]}")
  [[ $topology == cluster ]] && topology_env=(REDIS_CLUSTER_NODES=cluster-a:7000)
  case_name="argv_$topology"
  : >"$TMP_DIR/argv-$topology.log"
  config=$(ORCHESTRATED_TEST_LOCAL_JSON='{"services":{"CoAuthoring":{"redis":{"options":{"username":"app"}}}}}' \
    run_config "$case_name" \
    PATH="$TMP_DIR/argv-bin:$PATH" JQ_ARGV_LOG="$TMP_DIR/argv-$topology.log" \
    JWT_ENABLED=true JWT_SECRET="${argv_secrets[0]}" DB_PWD="${argv_secrets[1]}" AMQP_PWD="${argv_secrets[2]}" \
    REDIS_SERVER_USER=app REDIS_SERVER_PWD="${argv_secrets[3]}" \
    WOPI_PRIVATE_KEY="${argv_secrets[5]}" SECURE_LINK_SECRET="${argv_secrets[6]}" \
    NODE_CONFIG="{\"services\":{\"CoAuthoring\":{\"secret\":{\"session\":{\"string\":\"${argv_secrets[7]}\"}}}}}" \
    "${topology_env[@]}")
  [[ -s "$TMP_DIR/argv-$topology.log" ]] || { echo "$case_name: jq wrapper was not used" >&2; exit 1; }
  for secret in "${argv_secrets[@]}"; do
    [[ $topology == cluster && $secret == sentinel-* ]] && continue
    if grep -Fq -- "$secret" "$TMP_DIR/argv-$topology.log"; then
      echo "$case_name: $secret appeared on a jq command line" >&2
      exit 1
    fi
    if grep -Fq -- "$secret" "$TMP_DIR/$case_name/output"; then
      echo "$case_name: $secret appeared in the entrypoint output" >&2
      exit 1
    fi
    grep -Fq -- "$secret" "$config" || { echo "$case_name: $secret missing from the configuration" >&2; exit 1; }
  done
  [[ $(stat -c %a "$config") == 600 ]] || { echo "$case_name: configuration file is not private" >&2; exit 1; }
done

echo "orchestrated entrypoint Redis and editor-data configuration: PASS"
