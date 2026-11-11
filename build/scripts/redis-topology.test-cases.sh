#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Sourced by both entrypoint suites, which provide redis_test_config,
# assert_config, and expect_failure. Assertions inspect generated configuration.

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
    config=$(redis_test_config "sentinel_fallback_${nodes_state}_${endpoint_state}_defaults" \
      REDIS_SENTINEL_GROUP_NAME=helm-master "${nodes_env[@]}" "${endpoint_env[@]}")
    assert_config "$config" '
      .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes == [{host: "localhost", port: 6379}]
    '
  done
done

for credential_var in REDIS_SENTINEL_USER REDIS_SENTINEL_USERNAME REDIS_SENTINEL_PASS REDIS_SENTINEL_PWD; do
  case "$credential_var" in
    REDIS_SENTINEL_USER|REDIS_SENTINEL_USERNAME) credential_key=username ;;
    *) credential_key=password ;;
  esac
  config=$(redis_test_config "sentinel_fallback_$credential_var" "$credential_var=sentinel-credential" \
    REDIS_SERVER_HOST=credential-sentinel REDIS_SERVER_PORT=26381)
  assert_config "$config" "
    .services.CoAuthoring.redis.optionsSentinel.sentinelRootNodes ==
      [{host: \"credential-sentinel\", port: 26381}] and
    .services.CoAuthoring.redis.optionsSentinel.sentinelClientOptions.$credential_key == \"sentinel-credential\"
  "
  expect_failure "sentinel_fallback_cluster_$credential_var" \
    'Redis Sentinel and Redis Cluster cannot be configured together' \
    "$credential_var=sentinel-credential" REDIS_CLUSTER_NODES=cluster-a:7000
done

expect_failure sentinel_fallback_invalid_host 'each node must use host:port' \
  REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_HOST=invalid/host
expect_failure sentinel_fallback_invalid_port 'each node must use host:port' \
  REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_SERVER_PORT=invalid
fallback_password='fallback-password-do-not-log'
expect_failure sentinel_fallback_private 'each node must use host:port' \
  "REDIS_SENTINEL_PASS=$fallback_password" "REDIS_SERVER_HOST=user:$fallback_password@host"
if grep -Fq "$fallback_password" "$TMP_DIR/sentinel_fallback_private/output"; then
  echo 'sentinel_fallback_private: credential leaked in diagnostic' >&2
  exit 1
fi
for port in 0 65536; do
  expect_failure "sentinel_fallback_port_$port" 'port must be between 1 and 65535' \
    REDIS_SENTINEL_GROUP_NAME=helm-master "REDIS_SERVER_PORT=$port"
done

config=$(redis_test_config sentinel_explicit_precedence REDIS_SENTINEL_GROUP_NAME=helm-master \
  REDIS_SENTINEL_NODES=explicit-sentinel:26379 REDIS_SERVER_HOST=fallback-host REDIS_SERVER_PORT=6380)
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
expect_failure sentinel_fallback_cluster_group 'Redis Sentinel and Redis Cluster cannot be configured together' \
  REDIS_SENTINEL_GROUP_NAME=helm-master REDIS_CLUSTER_NODES=cluster-a:7000

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
  user_keys=("$REDIS_TEST_USER_KEY")
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
