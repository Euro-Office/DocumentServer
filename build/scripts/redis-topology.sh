#!/bin/sh

# Shared Redis topology parsing and node-redis option construction used by
# both image entrypoints. Keep this file POSIX-compatible: the standalone
# image uses /bin/sh while the orchestrated image uses Bash.

parse_redis_nodes() (
  node_list=$1
  node_kind=$2
  nodes=$(jq -cn --arg value "$node_list" '
    ($value | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $trimmed |
    ($trimmed | gsub("[[:space:],]+"; " ") | split(" ") | map(select(length > 0))) as $entries |
    if $trimmed == "" then
      error("must contain at least one node")
    elif ($trimmed | test("(^,|,$|,,|,[[:space:]]*,)")) then
      error("must not contain empty node entries")
    elif ($entries | length) == 0 then
      error("must contain at least one node")
    elif any($entries[]; test("^(redis://)?[^:/?#@[:space:]]+:[0-9]+$") | not) then
      error("each node must use host:port or redis://host:port")
    else
      ($entries | map(
        capture("^(redis://)?(?<host>[^:/?#@[:space:]]+):(?<port>[0-9]+)$") |
        (.port | tonumber) as $port |
        if $port < 1 or $port > 65535 then
          error("port must be between 1 and 65535")
        else
          {host: .host, port: $port}
        end
      )) as $nodes |
      if (($nodes | map("\(.host):\(.port)") | unique | length) != ($nodes | length)) then
        error("must not contain duplicate nodes")
      else
        $nodes
      end
    end
  ') || {
    echo "ERROR: invalid ${node_kind} Redis node list: ${node_list}" >&2
    exit 1
  }
  printf '%s' "$nodes"
)

redis_topology_init() {
  REDIS_SENTINEL_USER="${REDIS_SENTINEL_USER:-${REDIS_SENTINEL_USERNAME:-}}"
  REDIS_SENTINEL_PASS="${REDIS_SENTINEL_PASS:-${REDIS_SENTINEL_PWD:-}}"
  REDIS_SENTINEL_REQUESTED=false
  if [ -n "${REDIS_SENTINEL_NODES:-}" ] || [ -n "${REDIS_SENTINEL_GROUP_NAME:-}" ] \
    || [ -n "$REDIS_SENTINEL_USER" ] || [ -n "$REDIS_SENTINEL_PASS" ]; then
    REDIS_SENTINEL_REQUESTED=true
  fi

  if [ "$REDIS_SENTINEL_REQUESTED" = true ] && [ -n "${REDIS_CLUSTER_NODES:-}" ]; then
    echo "ERROR: Redis Sentinel and Redis Cluster cannot be configured together." >&2
    return 1
  fi

  REDIS_SENTINEL_NODES_JSON='[]'
  REDIS_CLUSTER_NODES_JSON='[]'
  if [ "$REDIS_SENTINEL_REQUESTED" = true ]; then
    REDIS_SENTINEL_GROUP_NAME="${REDIS_SENTINEL_GROUP_NAME:-mymaster}"
    case "$REDIS_SENTINEL_GROUP_NAME" in
      *[![:print:]]*|*[[:space:]]*)
        echo "ERROR: REDIS_SENTINEL_GROUP_NAME must not contain whitespace or control characters." >&2
        return 1
        ;;
    esac
    if [ -z "${REDIS_SENTINEL_NODES:-}" ]; then
      echo "ERROR: Redis Sentinel was requested but REDIS_SENTINEL_NODES is not set." >&2
      return 1
    fi
    REDIS_SENTINEL_NODES_JSON=$(parse_redis_nodes "$REDIS_SENTINEL_NODES" Sentinel) || return 1
  fi
  if [ -n "${REDIS_CLUSTER_NODES:-}" ]; then
    REDIS_CLUSTER_NODES_JSON=$(parse_redis_nodes "$REDIS_CLUSTER_NODES" Cluster) || return 1
  fi
}

redis_build_sentinel_options() {
  jq -cn \
    --arg name "${1:-mymaster}" \
    --argjson nodes "${2:-[]}" \
    --arg redisUser "${3:-}" \
    --arg redisPass "${4:-}" \
    --arg redisDb "${5:-0}" \
    --arg sentinelUser "${6:-}" \
    --arg sentinelPass "${7:-}" \
    '{
      name: $name,
      sentinelRootNodes: $nodes,
      nodeClientOptions: (
        {database: ($redisDb | tonumber? // 0)} |
        if $redisUser != "" then .username = $redisUser else . end |
        if $redisPass != "" then .password = $redisPass else . end
      ),
      sentinelClientOptions: (
        {} |
        if $sentinelUser != "" then .username = $sentinelUser else . end |
        if $sentinelPass != "" then .password = $sentinelPass else . end
      )
    }'
}

redis_build_cluster_options() {
  jq -cn \
    --argjson nodes "${1:-[]}" \
    --arg redisUser "${2:-}" \
    --arg redisPass "${3:-}" \
    '{
      rootNodes: ($nodes | map({url: ("redis://" + .host + ":" + (.port | tostring))})),
      defaults: (
        {} |
        if $redisUser != "" then .username = $redisUser else . end |
        if $redisPass != "" then .password = $redisPass else . end
      )
    }'
}
