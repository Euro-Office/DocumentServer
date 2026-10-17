#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
# Sourced by both entrypoint suites, which provide redis_test_config,
# assert_config, and expect_failure. Assertions inspect generated configuration.

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
done

group_names=('my master' $'my\tmaster' $'my\nmaster' $'my\rmaster' $'my\001master' $'my\177master')
for index in "${!group_names[@]}"; do
  expect_failure "sentinel_invalid_group_$index" \
    'REDIS_SENTINEL_GROUP_NAME must not contain whitespace or control characters' \
    REDIS_SENTINEL_NODES=node-a:26379 "REDIS_SENTINEL_GROUP_NAME=${group_names[$index]}"
done
