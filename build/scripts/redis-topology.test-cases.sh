#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Sourced by both entrypoint suites, which provide redis_test_config,
# assert_config, and expect_failure. Assertions inspect generated configuration.
# redis_test_local_config LOCAL_JSON NAME ARGS... runs with LOCAL_JSON merged
# into local.json and prints the effective configuration (local.json under the
# exported NODE_CONFIG); redis_test_local_failure LOCAL_JSON NAME EXPECTED
# ARGS... is the matching expect_failure.
# REDIS_TEST_LOCAL_SENTINEL_FALLBACK is true when Sentinel settings without a
# Sentinel address fall back to localhost (orchestrated) and false when the
# image ignores them to keep its bundled Redis (standalone).

# A Sentinel setting next to REDIS_CLUSTER_NODES conflicts where it would fall
# back to a local Sentinel, and is ignored where the image keeps its bundled Redis.
expect_stray_sentinel_with_cluster() {
  local case_name=$1 config
  shift
  if [[ $REDIS_TEST_LOCAL_SENTINEL_FALLBACK == true ]]; then
    expect_failure "$case_name" 'Redis Sentinel and Redis Cluster cannot be configured together' \
      "$@" REDIS_CLUSTER_NODES=cluster-a:7000
  else
    config=$(redis_test_config "$case_name" "$@" REDIS_CLUSTER_NODES=cluster-a:7000)
    assert_config "$config" '
      .services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: "redis://cluster-a:7000"}] and
      .services.CoAuthoring.redis.optionsSentinel == null
    '
    if ! grep -Fq 'ignoring REDIS_SENTINEL_* settings' "$TMP_DIR/$case_name/output"; then
      echo "$case_name: missing warning about ignored Sentinel settings" >&2
      return 1
    fi
  fi
}

# Sentinel settings with neither REDIS_SENTINEL_NODES nor a REDIS_SERVER_HOST.
assert_local_sentinel_fallback() {
  local case_name=$1 config=$2 expected_nodes=$3
  if [[ $REDIS_TEST_LOCAL_SENTINEL_FALLBACK == true ]]; then
    assert_config "$config" ".services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes == $expected_nodes"
  else
    assert_config "$config" '((.services.CoAuthoring.redis.optionsSentinel // {}) | length) == 0'
    if ! grep -Fq 'ignoring REDIS_SENTINEL_* settings' "$TMP_DIR/$case_name/output"; then
      echo "$case_name: missing warning about ignored Sentinel settings" >&2
      return 1
    fi
  fi
}

for nodes_state in unset empty; do
  nodes_env=()
  [[ $nodes_state == empty ]] && nodes_env=(REDIS_SENTINEL_NODES=)
  config=$(redis_test_config "sentinel_fallback_${nodes_state}" \
    REDIS_SENTINEL_GROUP_NAME=helm-master "${nodes_env[@]}" \
    REDIS_SERVER_HOST=helm-sentinel REDIS_SERVER_PORT=26380 \
    NODE_CONFIG='{"services":{"CoAuthoring":{"server":{"editorDataStorage":"editorDataMemory"}}}}')
  assert_config "$config" '
    .services.CoAuthoring.redis.optionsSentinel.name == "helm-master" and
    .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes == [{host: "helm-sentinel", port: 26380}] and
    .services.CoAuthoring.server.editorDataStorage == "editorDataMemory"
  '

  for endpoint_state in unset empty; do
    endpoint_env=()
    [[ $endpoint_state == empty ]] && endpoint_env=(REDIS_SERVER_HOST= REDIS_SERVER_PORT=)
    case_name="sentinel_fallback_${nodes_state}_${endpoint_state}_defaults"
    config=$(redis_test_config "$case_name" \
      REDIS_SENTINEL_GROUP_NAME=helm-master "${nodes_env[@]}" "${endpoint_env[@]}")
    assert_local_sentinel_fallback "$case_name" "$config" '[{host: "localhost", port: 6379}]'
  done
done

for endpoint_state in unset empty; do
  endpoint_env=()
  [[ $endpoint_state == empty ]] && endpoint_env=(REDIS_SERVER_HOST=)
  case_name="sentinel_fallback_host_${endpoint_state}"
  config=$(redis_test_config "$case_name" \
    REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_PORT=26380 "${endpoint_env[@]}")
  assert_local_sentinel_fallback "$case_name" "$config" '[{host: "localhost", port: 26380}]'

  endpoint_env=()
  [[ $endpoint_state == empty ]] && endpoint_env=(REDIS_SERVER_PORT=)
  config=$(redis_test_config "sentinel_fallback_port_${endpoint_state}" \
    REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_HOST=helm-sentinel "${endpoint_env[@]}")
  assert_config "$config" '
    .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes == [{host: "helm-sentinel", port: 6379}]
  '
done

for credential_var in REDIS_SENTINEL_USER REDIS_SENTINEL_USERNAME REDIS_SENTINEL_PASS REDIS_SENTINEL_PWD; do
  case "$credential_var" in
    REDIS_SENTINEL_USER|REDIS_SENTINEL_USERNAME) credential_key=username ;;
    *) credential_key=password ;;
  esac
  for nodes_state in unset empty; do
    nodes_env=()
    [[ $nodes_state == empty ]] && nodes_env=(REDIS_SENTINEL_NODES=)
    case_name="sentinel_fallback_${credential_var}_$nodes_state"
    if [[ $credential_key == username ]]; then
      # The server rejects a Sentinel username without a password.
      expect_failure "$case_name" 'REDIS_SENTINEL_USER is set without a Sentinel password' \
        "$credential_var=sentinel-credential" "${nodes_env[@]}" \
        REDIS_SERVER_HOST=credential-sentinel REDIS_SERVER_PORT=26381
      continue
    fi
    config=$(redis_test_config "$case_name" \
      "$credential_var=sentinel-credential" "${nodes_env[@]}" \
      REDIS_SERVER_HOST=credential-sentinel REDIS_SERVER_PORT=26381)
    assert_config "$config" "
      .services.CoAuthoring.redis.optionsSentinel.name == \"mymaster\" and
      .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes ==
        [{host: \"credential-sentinel\", port: 26381}] and
      .services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.$credential_key == \"sentinel-credential\"
    "
  done
  expect_stray_sentinel_with_cluster "sentinel_fallback_cluster_$credential_var" \
    "$credential_var=sentinel-credential"
done

# `default` without a password is unauthenticated, as for the Redis user.
for credential_var in REDIS_SENTINEL_USER REDIS_SENTINEL_USERNAME; do
  config=$(redis_test_config "sentinel_default_${credential_var}" "$credential_var=default" \
    REDIS_SENTINEL_NODES=sentinel-a:26379)
  assert_config "$config" '
    .services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions == {username: "default", password: ""}
  '
done
# A Sentinel password supplied in NODE_CONFIG satisfies a username from the environment.
config=$(redis_test_config sentinel_user_config_password REDIS_SENTINEL_USER=sentinel-user \
  REDIS_SENTINEL_NODES=sentinel-a:26379 \
  NODE_CONFIG='{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{"sentinelClientOptions":{"password":"configured"}}}}}}')
assert_config "$config" '
  .services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions == {username: "sentinel-user", password: "configured"}
'

expect_failure sentinel_fallback_invalid_host 'each node must use host:port' \
  REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_HOST=invalid/host
expect_failure sentinel_fallback_invalid_port 'REDIS_SERVER_PORT must be an integer between 1 and 65535' \
  REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_HOST=helm-sentinel REDIS_SERVER_PORT=invalid
fallback_password='fallback-password-do-not-log'
expect_failure sentinel_fallback_private 'each node must use host:port' \
  "REDIS_SENTINEL_PASS=$fallback_password" "REDIS_SERVER_HOST=user:$fallback_password@host"
if grep -Fq "$fallback_password" "$TMP_DIR/sentinel_fallback_private/output"; then
  echo 'sentinel_fallback_private: credential leaked in diagnostic' >&2
  exit 1
fi
for port in 0 65536; do
  expect_failure "sentinel_fallback_port_$port" 'REDIS_SERVER_PORT must be an integer between 1 and 65535' \
    REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_HOST=helm-sentinel "REDIS_SERVER_PORT=$port"
done
# An IPv6 REDIS_SERVER_HOST is bracketed for the fallback Sentinel address.
config=$(redis_test_config sentinel_fallback_ipv6 REDIS_SENTINEL_GROUP_NAME=helm-master \
  REDIS_SERVER_HOST=fd00::5 REDIS_SERVER_PORT=26380)
assert_config "$config" '
  .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes == [{host: "fd00::5", port: 26380}]
'

# REDIS_SERVER_PORT is a port number in every topology.
port_values=(abc 0 65536 99999999999999999999 -1 '6379 ')
for index in "${!port_values[@]}"; do
  expect_failure "server_port_invalid_$index" 'REDIS_SERVER_PORT must be an integer between 1 and 65535' \
    "REDIS_SERVER_PORT=${port_values[$index]}"
done
config=$(redis_test_config server_port_leading_zero REDIS_SERVER_PORT=06380)
assert_config "$config" '.services.CoAuthoring.redis.port == 6380'

config=$(redis_test_config sentinel_explicit_precedence REDIS_SENTINEL_GROUP_NAME=helm-master \
  REDIS_SENTINEL_NODES=explicit-sentinel:26379 REDIS_SERVER_HOST=invalid/host REDIS_SERVER_PORT=6380)
assert_config "$config" '
  .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes == [{host: "explicit-sentinel", port: 26379}]
'

config=$(redis_test_config no_sentinel_settings REDIS_SERVER_HOST=standalone-host REDIS_SERVER_PORT=6380)
assert_config "$config" '
  .services.CoAuthoring.redis.host == "standalone-host" and
  .services.CoAuthoring.redis.port == 6380 and
  ((.services.CoAuthoring.redis.optionsSentinel // {}) | length) == 0 and
  ((.services.CoAuthoring.redis.optionsCluster // {}) | length) == 0
'
expect_stray_sentinel_with_cluster sentinel_fallback_cluster_group REDIS_SENTINEL_GROUP_NAME=helm-master

separators=(' ' ',' ', ' $'\t' $'\n')
format_names=(space comma comma_space tab newline)
for kind in sentinel cluster; do
  if [[ $kind == sentinel ]]; then
    nodes_var=REDIS_SENTINEL_NODES
    nodes_expression='.services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes'
    expected_nodes='[{"host":"node-a","port":1},{"host":"node-b","port":65535},{"host":"node-c","port":7001}]'
  else
    nodes_var=REDIS_CLUSTER_NODES
    nodes_expression='.services.CoAuthoring.redis.optionsCluster.rootNodes'
    expected_nodes='[{"url":"redis://node-a:1"},{"url":"redis://node-b:65535"},{"url":"redis://node-c:7001"}]'
  fi

  for index in "${!separators[@]}"; do
    separator=${separators[$index]}
    config=$(redis_test_config "${kind}_format_${format_names[$index]}" \
      "$nodes_var=node-a:1${separator}redis://node-b:65535${separator}node-c:7001")
    assert_config "$config" "$nodes_expression == $expected_nodes"
  done

  expect_failure "${kind}_duplicate" 'duplicate nodes' "$nodes_var=node-a:7000,node-a:7000"
  expect_failure "${kind}_duplicate_uri" 'duplicate nodes' "$nodes_var=node-a:7000 redis://node-a:7000"
  for port in 0 65536; do
    expect_failure "${kind}_port_$port" 'port must be between 1 and 65535' "$nodes_var=node-a:$port"
  done
  for nodes in ',node-a:7000' 'node-a:7000,' 'node-a:7000,,node-b:7001' 'node-a:7000, ,node-b:7001'; do
    expect_failure "${kind}_empty_$((index++))" 'empty node entries' "$nodes_var=$nodes"
  done
  expect_failure "${kind}_malformed_host" 'each node must use host:port' "$nodes_var=node/a:7000"
  expect_failure "${kind}_missing_port" 'each node must use host:port' "$nodes_var=node-a"
  expect_failure "${kind}_unbracketed_ipv6" 'each node must use host:port' "$nodes_var=fd00::1:7000"
  expect_failure "${kind}_duplicate_case" 'duplicate nodes' "$nodes_var=Node-A:7000,node-a:7000"

  if [[ $kind == sentinel ]]; then
    tls_var=REDIS_SENTINEL_TLS
    ipv6_expected='[{"host":"fd00::1","port":26379},{"host":"10.0.0.2","port":26380}]'
  else
    tls_var=REDIS_SERVER_TLS
    ipv6_expected='[{"url":"redis://[fd00::1]:26379"},{"url":"redis://10.0.0.2:26380"}]'
  fi
  config=$(redis_test_config "${kind}_ipv6" "$nodes_var=[fd00::1]:26379 redis://10.0.0.2:26380")
  assert_config "$config" "$nodes_expression == $ipv6_expected"

  config=$(redis_test_config "${kind}_rediss" "$tls_var=true" \
    "$nodes_var=rediss://node-a:7000,rediss://[fd00::1]:7001")
  if [[ $kind == sentinel ]]; then
    assert_config "$config" "$nodes_expression == [{host: \"node-a\", port: 7000}, {host: \"fd00::1\", port: 7001}]"
  else
    assert_config "$config" "$nodes_expression == [{url: \"rediss://node-a:7000\"}, {url: \"rediss://[fd00::1]:7001\"}]"
  fi
  expect_failure "${kind}_rediss_without_tls" "rediss:// requires $tls_var=true" \
    "$nodes_var=rediss://node-a:7000"

  embedded_password='embedded-password-do-not-log'
  case_name="${kind}_embedded_credentials"
  expect_failure "$case_name" 'each node must use host:port' \
    "$nodes_var=redis://user:$embedded_password@node-a:7000"
  if ! grep -Fq "$nodes_var" "$TMP_DIR/$case_name/output"; then
    echo "$case_name: missing variable name in diagnostic" >&2
    exit 1
  fi
  if grep -Fq "$embedded_password" "$TMP_DIR/$case_name/output"; then
    echo "$case_name: node-list credential leaked in diagnostic" >&2
    exit 1
  fi
done

group_names=('my master' $'my\tmaster' $'my\nmaster' $'my\rmaster' $'my\001master' $'my\177master')
for index in "${!group_names[@]}"; do
  expect_failure "sentinel_invalid_group_$index" \
    'REDIS_SENTINEL_GROUP_NAME must not contain whitespace or control characters' \
    REDIS_SENTINEL_NODES=node-a:26379 "REDIS_SENTINEL_GROUP_NAME=${group_names[$index]}"
done

# The server normalizes default + password: "" to unauthenticated, but rejects
# any username with an omitted password. These are configuration assertions,
# not live connection or server normalization tests.
for kind in standalone sentinel cluster; do
  topology_env=()
  option_paths=(.services.CoAuthoring.redis.options)
  user_keys=(username)
  case "$kind" in
    sentinel)
      topology_env=(REDIS_SENTINEL_NODES=node-a:26379)
      option_paths+=(.services.CoAuthoring.redis.optionsSentinel.nodeClientOptions)
      user_keys+=(username)
      ;;
    cluster)
      topology_env=(REDIS_CLUSTER_NODES=node-a:7000)
      option_paths+=(.services.CoAuthoring.redis.optionsCluster.defaults)
      user_keys+=(username)
      ;;
  esac
  for user in default redis-user; do
    for password_state in unset empty authenticated; do
      password_env=()
      expected_password='{}'
      case "$password_state" in
        unset|empty)
          [[ $password_state == empty ]] && password_env=("$REDIS_TEST_PASSWORD_VAR=")
          [[ $user == default ]] && expected_password='{"password":""}'
          ;;
        authenticated)
          password_env=("$REDIS_TEST_PASSWORD_VAR=redis-pass")
          expected_password='{"password":"redis-pass"}'
          ;;
      esac
      config=$(redis_test_config "${kind}_${user}_${password_state}" \
        "${topology_env[@]}" "REDIS_SERVER_USER=$user" "${password_env[@]}")
      for index in "${!option_paths[@]}"; do
        # For redis-user without a password, keep the username and omit the
        # password so the server still rejects the invalid credentials.
        assert_config "$config" "
          (${option_paths[$index]} |
            with_entries(select(.key == \"user\" or .key == \"username\" or .key == \"password\"))) ==
          ({${user_keys[$index]}: \"$user\"} + $expected_password)
        "
      done
    done
  done

  operator_options='{"username":"operator-user","password":"operator-pass"}'
  operator_config=$(jq -cn --argjson options "$operator_options" '
    {services: {CoAuthoring: {redis: {
      options: $options,
      optionsSentinel: {nodeClientOptions: $options},
      optionsCluster: {defaults: $options}
    }}}}')
  # Only override options for the active topology; avoid requesting both.
  case "$kind" in
    standalone) operator_config=$(jq 'del(.services.CoAuthoring.redis.optionsSentinel,
      .services.CoAuthoring.redis.optionsCluster)' <<<"$operator_config") ;;
    sentinel) operator_config=$(jq 'del(.services.CoAuthoring.redis.optionsCluster)' <<<"$operator_config") ;;
    cluster) operator_config=$(jq 'del(.services.CoAuthoring.redis.optionsSentinel)' <<<"$operator_config") ;;
  esac
  config=$(redis_test_config "${kind}_operator_auth" "${topology_env[@]}" \
    REDIS_SERVER_USER=default "NODE_CONFIG=$operator_config")
  for path in "${option_paths[@]}"; do
    assert_config "$config" "
      $path.username == \"operator-user\" and $path.password == \"operator-pass\"
    "
  done
done

# The `default` + "" placeholder must not replace a password configured in
# local.json or NODE_CONFIG. The whole placeholder yields, so a configured
# username applies with its password, and without one the server uses its
# `default` user. Sentinel node clients inherit the base options, as in the
# server ({...options, ...nodeClientOptions}); Cluster defaults do not.
configured_password='configured-pass'
for kind in standalone sentinel cluster; do
  case "$kind" in
    standalone)
      topology_env=()
      config_path='options'
      client='.services.CoAuthoring.redis.options'
      ;;
    sentinel)
      topology_env=(REDIS_SENTINEL_NODES=node-a:26379)
      config_path='options'
      client='(.services.CoAuthoring.redis.options + .services.CoAuthoring.redis.optionsSentinel.nodeClientOptions)'
      ;;
    cluster)
      topology_env=(REDIS_CLUSTER_NODES=node-a:7000)
      config_path='optionsCluster.defaults'
      client='.services.CoAuthoring.redis.optionsCluster.defaults'
      ;;
  esac
  for credentials in password user_password; do
    configured='{"password":"configured-pass"}'
    expected_user=null
    if [[ $credentials == user_password ]]; then
      configured='{"username":"app","password":"configured-pass"}'
      expected_user='"app"'
    fi
    redis_settings=$(jq -cn --arg path "$config_path" --argjson configured "$configured" '
      {services: {CoAuthoring: {redis: ({} | setpath($path | split("."); $configured))}}}')
    expected="$client | {username, password} == {username: $expected_user, password: \"$configured_password\"}"

    config=$(redis_test_local_config "$redis_settings" "${kind}_default_local_${credentials}" \
      "${topology_env[@]}" REDIS_SERVER_USER=default "$REDIS_TEST_PASSWORD_VAR=")
    assert_config "$config" "$expected"
    config=$(redis_test_config "${kind}_default_override_${credentials}" "${topology_env[@]}" \
      REDIS_SERVER_USER=default "$REDIS_TEST_PASSWORD_VAR=" "NODE_CONFIG=$redis_settings")
    assert_config "$config" "$expected"
  done
done

# The same for Sentinel authentication: REDIS_SENTINEL_USER=default yields to a
# configured Sentinel password, and a Sentinel username from the environment is
# accepted with a password from local.json.
for sentinel_user in default sentinel-user; do
  expected_user=null
  [[ $sentinel_user != default ]] && expected_user="\"$sentinel_user\""
  config=$(redis_test_local_config \
    '{"services":{"CoAuthoring":{"redis":{"optionsSentinel":{"sentinelClientOptions":{"password":"sentinel-file-pass"}}}}}}' \
    "sentinel_user_${sentinel_user}_local_password" \
    REDIS_SENTINEL_NODES=node-a:26379 "REDIS_SENTINEL_USER=$sentinel_user")
  assert_config "$config" "
    .services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions | {username, password} ==
      {username: $expected_user, password: \"sentinel-file-pass\"}
  "
done

# REDIS_SERVER_TLS reaches Sentinel data nodes through options.socket, without
# replacing the CA and server name configured there.
for sentinel_source in local env; do
  redis_settings='{"services":{"CoAuthoring":{"redis":{"options":{"socket":{"ca":"node-ca","servername":"redis.internal"}}}}}}'
  sentinel_env=(REDIS_SENTINEL_NODES=node-a:26379)
  if [[ $sentinel_source == local ]]; then
    redis_settings=$(jq -c '.services.CoAuthoring.redis.optionsSentinel =
      {name: "file-master", sentinelRootNodes: [{host: "file-sentinel", port: 26379}]}' <<<"$redis_settings")
    sentinel_env=()
  fi
  config=$(redis_test_local_config "$redis_settings" "sentinel_${sentinel_source}_tls_keeps_socket" \
    REDIS_SERVER_TLS=true "${sentinel_env[@]}")
  assert_config "$config" '
    (.services.CoAuthoring.redis.options + .services.CoAuthoring.redis.optionsSentinel.nodeClientOptions).socket ==
      {ca: "node-ca", servername: "redis.internal", tls: true}
  '
done

# Configured seed URL schemes are matched without regard to case.
config=$(redis_test_local_config \
  '{"services":{"CoAuthoring":{"redis":{"optionsCluster":{"rootNodes":[{"url":"REDIS://file-cluster:7000"}]}}}}}' \
  cluster_seed_scheme_case REDIS_SERVER_TLS=true)
assert_config "$config" '.services.CoAuthoring.redis.optionsCluster.rootNodes == [{url: "rediss://file-cluster:7000"}]'

# Redis settings that must be objects are rejected, wherever they are set.
redis_test_local_failure '{"services":{"CoAuthoring":{"redis":"redis://host:6379"}}}' local_redis_string \
  'services.CoAuthoring.redis in local.json must be a JSON object'
for setting in options optionsSentinel optionsCluster optionsCluster.defaults optionsSentinel.nodeClientOptions; do
  override=$(jq -cn --arg path "$setting" '{services: {CoAuthoring: {redis: ({} | setpath($path | split("."); "x"))}}}')
  expect_failure "override_${setting//./_}_string" \
    "services.CoAuthoring.redis.$setting in NODE_CONFIG must be a JSON object" "NODE_CONFIG=$override"
done
