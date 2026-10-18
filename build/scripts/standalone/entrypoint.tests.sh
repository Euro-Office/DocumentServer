#!/usr/bin/env bash
# Run from the repository root:
#   bash build/scripts/standalone/entrypoint.tests.sh
#   bash build/scripts/standalone/entrypoint.tests.sh --services [existing-image]
#
# The default suite runs without root and requires Bash, jq, GNU timeout, and
# standard GNU utilities. No initialized submodules are needed. It checks
# generated config, DATA_DIR secret
# isolation, and Redis topology connection decisions using a recording nc stub.
#
# --services also requires Docker and checks the bundled Redis startup decision
# beyond ENTRYPOINT_CONFIG_ONLY, using the current scripts in a disposable
# container. Services and the final process handoff are intercepted; this does
# not test live Redis connectivity. The default image is the locally available
# ghcr.io/euro-office/documentserver:latest-dev; no image is pulled or built.
# Only scripts and the config fixture are mounted, read-only, with no network.
# Invoke the supporting harness and --container-services only through --services.
#
# Each entrypoint run has a timeout. Generated config and secrets use temporary
# test directories; failures print captured output and calls before cleanup.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/entrypoint.sh"
DEFAULT_CONFIG="$SCRIPT_DIR/fixtures/local.json"
TMP_DIR=$(mktemp -d)
CONTAINER_NAME=""
cleanup() {
  local status=$?
  if (( status != 0 )); then
    echo "Standalone entrypoint tests failed (exit $status). Captured diagnostics:" >&2
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
    done < <(find "$diagnostic_dir" -type f \( -name output -o -name calls \) | sort)
  fi
  if [[ -n "$CONTAINER_NAME" ]]; then
    timeout -k 2s 10s docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SERVICE_START=false
CONFIG_ONLY=true
case "${1:-}" in
  --services)
    image=${2:-ghcr.io/euro-office/documentserver:latest-dev}
    CONTAINER_NAME="eo-entrypoint-tests-$(id -u)-$$"
    printf '%s\n' container_services >"$TMP_DIR/current-case"
    mkdir -p "$TMP_DIR/container_services"
    # Only the scripts and input fixture are mounted, both read-only. All writes
    # and service interception happen in the disposable container's filesystem.
    timeout -k 5s 120s docker run --rm --pull never --network none \
      --name "$CONTAINER_NAME" --user 0 --entrypoint bash \
      --mount "type=bind,src=$SCRIPT_DIR/..,dst=/tests/build/scripts,readonly" \
      "$image" /tests/build/scripts/standalone/entrypoint.service-start-harness.sh \
      >"$TMP_DIR/container_services/output" 2>&1
    cat "$TMP_DIR/container_services/output"
    exit 0
    ;;
  --container-services)
    [[ -f /.dockerenv ]] || { echo 'Service-start tests require a disposable Docker container.' >&2; exit 1; }
    SERVICE_START=true
    CONFIG_ONLY=false
    ;;
  "") ;;
  *) echo "Usage: $0 [--services [existing-image]]" >&2; exit 1 ;;
esac

mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/nc" <<'EOF'
#!/bin/sh
printf 'nc %s\n' "$*" >>"$ENTRYPOINT_CALLS"
exit 0
EOF
chmod +x "$TMP_DIR/bin/nc"

assert_secrets() {
  local case_dir=$1
  [[ $(wc -c <"$case_dir/data/.private/jwt_secret") -eq 32 ]] || return 1
  [[ $(wc -c <"$case_dir/data/.private/secure_link_secret") -eq 20 ]] || return 1
  [[ $(stat -c %a "$case_dir/data/.private") == 700 ]] || return 1
  [[ $(stat -c %a "$case_dir/data/.private/jwt_secret") == 600 ]] || return 1
  [[ $(stat -c %a "$case_dir/data/.private/secure_link_secret") == 600 ]] || return 1
  jq -e --rawfile secret "$case_dir/data/.private/jwt_secret" \
    '.services.CoAuthoring.secret.session.string == $secret' "$case_dir/conf/local.json" >/dev/null || return $?
  [[ ! -e "$case_dir/conf/local.json.tmp" ]]
}

run_entrypoint() {
  local name=$1
  shift
  printf '%s\n' "$name" >"$TMP_DIR/current-case"
  local case_dir="$TMP_DIR/$name"
  mkdir -p "$case_dir/conf" "$case_dir/data"
  cp "${ENTRYPOINT_TEST_CONFIG:-$DEFAULT_CONFIG}" "$case_dir/conf/local.json"
  : >"$case_dir/calls"

  local status=0
  timeout -k 2s 10s env -i \
    PATH="$TMP_DIR/bin:$PATH" \
    ENTRYPOINT_CALLS="$case_dir/calls" \
    EO_ROOT="$case_dir/root" \
    EO_LOG="$case_dir/log" \
    EO_LIB="$case_dir/lib" \
    EO_CONF="$case_dir/conf" \
    DATA_DIR="$case_dir/data" \
    ENTRYPOINT_CONFIG_ONLY="$CONFIG_ONLY" \
    JWT_ENABLED=false \
    GENERATE_FONTS=false \
    PLUGINS_ENABLED=false \
    AMQP_URI=amqp://unused \
    "$@" \
    sh "$ENTRYPOINT" >"$case_dir/output" 2>&1 || status=$?
  if (( status != 0 )); then
    echo "$name: entrypoint exited $status" >&2
    return "$status"
  fi

  assert_secrets "$case_dir" || { echo "$name: secret isolation assertion failed" >&2; return 1; }
  assert_config "$case_dir/conf/local.json" \
    '.services.CoAuthoring.server.port == 8123 and .FileConverter.converter.maxprocesscount == 2' || return $?

  printf '%s' "$case_dir/conf/local.json"
}

assert_config() {
  local config=$1
  local expression=$2
  if ! jq -e "$expression" "$config" >/dev/null; then
    echo "${config#"$TMP_DIR/"}: failed assertion: $expression" >&2
    cat "$config" >&2
    return 1
  fi
}

assert_call_count() {
  local calls=$1 expected=$2 call=$3
  local actual
  actual=$(grep -Fxc -- "$call" "$calls" || true)
  if [[ $actual != "$expected" ]]; then
    echo "$calls: expected $expected calls to '$call', got $actual" >&2
    return 1
  fi
}

# Each case checks observable connection attempts, and in the container also
# checks service startup and successful handoff past the Redis startup guard.
check_topology() {
  local name=$1 topology=$2
  shift 2
  local host config calls wait_count redis_count
  for host in remote localhost; do
    local host_env=()
    [[ $host == remote ]] && host_env=(REDIS_SERVER_HOST=remote-redis)
    config=$(run_entrypoint "${name}_$host" "${host_env[@]}" "$@")
    calls="${config%/conf/local.json}/calls"
    wait_count=0
    redis_count=0
    if [[ $topology == standalone ]]; then
      [[ $host == remote ]] && wait_count=1
      [[ $host == localhost ]] && redis_count=1
    fi
    assert_call_count "$calls" "$wait_count" 'nc -z -w 3 remote-redis 6379'
    [[ $(grep -c '^nc ' "$calls" || true) == "$wait_count" ]] || {
      echo "$calls: unexpected connection check" >&2
      return 1
    }
    if [[ $SERVICE_START == true ]]; then
      assert_call_count "$calls" "$redis_count" 'service redis-server start'
      assert_call_count "$calls" 1 'service nginx start'
      assert_call_count "$calls" 1 'handoff -- /usr/bin/supervisord'
    fi
  done
}

node_config_sentinel='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{"name":"mymaster","sentinelRootNodes":[{"host":"sentinel-a","port":26379}]}}}}}'
node_config_cluster='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[{"url":"redis://cluster-a:7000"}]}}}}}'

sentinel_options='{
  "name": "saved-master",
  "sentinelRootNodes": [{"host": "saved-sentinel", "port": 26380}],
  "nodeClientOptions": {
    "username": "saved-user", "password": "saved-password", "database": 4,
    "socket": {"tls": true, "ca": "node-ca", "cert": "node-cert", "key": "node-key"}
  },
  "sentinelClientOptions": {
    "username": "saved-sentinel-user", "password": "saved-sentinel-password",
    "socket": {"tls": true, "ca": "sentinel-ca", "cert": "sentinel-cert", "key": "sentinel-key"}
  }
}'
cluster_options='{
  "rootNodes": [{"url": "rediss://saved-cluster:7000"}],
  "defaults": {
    "username": "saved-user", "password": "saved-password",
    "socket": {"tls": true, "ca": "cluster-ca", "cert": "cluster-cert", "key": "cluster-key"}
  },
  "maxCommandRedirections": 20
}'
sentinel_fixture="$TMP_DIR/sentinel.json"
cluster_fixture="$TMP_DIR/cluster.json"
jq --argjson options "$sentinel_options" '.services.CoAuthoring.redis.optionsSentinel = $options' \
  "$DEFAULT_CONFIG" >"$sentinel_fixture"
jq --argjson options "$cluster_options" '.services.CoAuthoring.redis.optionsCluster = $options' \
  "$DEFAULT_CONFIG" >"$cluster_fixture"

for kind in sentinel cluster; do
  fixture_var="${kind}_fixture"
  options_var="${kind}_options"
  config=$(ENTRYPOINT_TEST_CONFIG="${!fixture_var}" run_entrypoint "preserve_$kind")
  assert_config "$config" ".services.CoAuthoring.redis.options${kind^} == ${!options_var}"
  ENTRYPOINT_TEST_CONFIG="${!fixture_var}" check_topology "local_config_$kind" "$kind"
done

check_topology no_topology standalone
check_topology empty_sentinel standalone \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{}}}}}'
check_topology empty_cluster standalone \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{}}}}}'
check_topology cluster_defaults standalone \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"defaults":{"socket":{"tls":true}}}}}}}'
check_topology cluster_empty_roots standalone \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[]}}}}}'
check_topology node_config_sentinel sentinel NODE_CONFIG="$node_config_sentinel"
check_topology node_config_cluster cluster NODE_CONFIG="$node_config_cluster"
check_topology env_sentinel sentinel REDIS_SENTINEL_GROUP_NAME=mymaster REDIS_SENTINEL_NODES=sentinel-a:26379
check_topology env_cluster cluster REDIS_CLUSTER_NODES=cluster-a:7000

if [[ $SERVICE_START == true ]]; then
  echo 'standalone entrypoint Redis service startup: PASS (22 cases)'
  exit 0
fi

sentinel_nodes_config=$(ENTRYPOINT_TEST_CONFIG="$sentinel_fixture" run_entrypoint sentinel_nodes_override \
  REDIS_SENTINEL_NODES=new-sentinel:26379)
assert_config "$sentinel_nodes_config" "
  .services.CoAuthoring.redis.optionsSentinel == ($sentinel_options |
    .sentinelRootNodes = [{host: \"new-sentinel\", port: 26379}])
"

sentinel_overrides_config=$(ENTRYPOINT_TEST_CONFIG="$sentinel_fixture" run_entrypoint sentinel_overrides \
  REDIS_SENTINEL_NODES=new-sentinel:26379 REDIS_SENTINEL_GROUP_NAME=new-master \
  REDIS_SERVER_USER=new-user REDIS_SERVER_PASS=new-password REDIS_SERVER_DB=0 \
  REDIS_SENTINEL_USER=new-sentinel-user REDIS_SENTINEL_PASS=new-sentinel-password \
  REDIS_SERVER_TLS=true REDIS_SENTINEL_TLS=true)
assert_config "$sentinel_overrides_config" "
  .services.CoAuthoring.redis.optionsSentinel == ($sentinel_options |
    .name = \"new-master\" |
    .sentinelRootNodes = [{host: \"new-sentinel\", port: 26379}] |
    .nodeClientOptions.username = \"new-user\" |
    .nodeClientOptions.password = \"new-password\" |
    .nodeClientOptions.database = 0 |
    .sentinelClientOptions.username = \"new-sentinel-user\" |
    .sentinelClientOptions.password = \"new-sentinel-password\")
"

cluster_nodes_config=$(ENTRYPOINT_TEST_CONFIG="$cluster_fixture" run_entrypoint cluster_nodes_override \
  REDIS_CLUSTER_NODES='new-cluster:7001,new-cluster-b:7002')
assert_config "$cluster_nodes_config" "
  .services.CoAuthoring.redis.optionsCluster == ($cluster_options |
    .rootNodes = [{url: \"rediss://new-cluster:7001\"}, {url: \"rediss://new-cluster-b:7002\"}])
"

# Enabling TLS must add the flag without dropping the existing socket options.
cluster_ca_fixture="$TMP_DIR/cluster-ca.json"
jq 'del(.services.CoAuthoring.redis.optionsCluster.defaults.socket.tls)' \
  "$cluster_fixture" >"$cluster_ca_fixture"
cluster_overrides_config=$(ENTRYPOINT_TEST_CONFIG="$cluster_ca_fixture" run_entrypoint cluster_overrides \
  REDIS_CLUSTER_NODES=new-cluster:7001 REDIS_SERVER_TLS=true \
  REDIS_SERVER_USER=new-user REDIS_SERVER_PASS=new-password)
assert_config "$cluster_overrides_config" "
  .services.CoAuthoring.redis.optionsCluster == ($cluster_options |
    .rootNodes = [{url: \"rediss://new-cluster:7001\"}] |
    .defaults.username = \"new-user\" | .defaults.password = \"new-password\")
"

for kind in sentinel cluster; do
  previous_config_var="${kind}_overrides_config"
  restarted_config=$(ENTRYPOINT_TEST_CONFIG="${!previous_config_var}" run_entrypoint "restart_$kind")
  previous_options=$(jq '.services.CoAuthoring.redis | {optionsSentinel, optionsCluster}' "${!previous_config_var}")
  assert_config "$restarted_config" ".services.CoAuthoring.redis | {optionsSentinel, optionsCluster} == $previous_options"
done

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

expect_failure() {
  local name=$1
  local expected=$2
  shift 2
  printf '%s\n' "$name" >"$TMP_DIR/current-case"
  local case_dir="$TMP_DIR/$name"
  mkdir -p "$case_dir/conf" "$case_dir/data"
  cp "$DEFAULT_CONFIG" "$case_dir/conf/local.json"

  local status=0
  timeout -k 2s 10s env -i \
    PATH="$TMP_DIR/bin:$PATH" \
    ENTRYPOINT_CALLS="$case_dir/calls" \
    EO_ROOT="$case_dir/root" \
    EO_LOG="$case_dir/log" \
    EO_LIB="$case_dir/lib" \
    EO_CONF="$case_dir/conf" \
    DATA_DIR="$case_dir/data" \
    ENTRYPOINT_CONFIG_ONLY=true \
    JWT_ENABLED=false \
    AMQP_URI=amqp://unused \
    "$@" \
    sh "$ENTRYPOINT" >"$case_dir/output" 2>&1 || status=$?
  if (( status == 0 || status == 124 || status == 137 )); then
    echo "$name: expected a validation failure, got exit $status" >&2
    return 1
  fi
  if ! grep -Fq "$expected" "$case_dir/output"; then
    echo "$name: missing diagnostic: $expected" >&2
    return 1
  fi
}

expect_failure incomplete_sentinel 'REDIS_SENTINEL_NODES is not set' \
  REDIS_SENTINEL_GROUP_NAME=mymaster
expect_failure invalid_redis_tls 'REDIS_SERVER_TLS must be true or false' REDIS_SERVER_TLS=invalid
expect_failure invalid_sentinel_tls 'REDIS_SENTINEL_TLS must be true or false' REDIS_SENTINEL_TLS=invalid

redis_test_config() { run_entrypoint "$@"; }
. "$SCRIPT_DIR/../redis-topology.test-cases.sh"

echo 'standalone entrypoint Redis configuration: PASS'
