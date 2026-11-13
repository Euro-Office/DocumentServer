#!/bin/sh

# Shared Redis topology parsing, node-redis option construction, and final
# NODE_CONFIG merging used by both image entrypoints. Keep this file
# POSIX-compatible: the standalone image uses /bin/sh while the orchestrated
# image uses Bash. Source bool.sh before calling redis_topology_init.
#
# Credentials and configuration documents never go on a jq command line, where
# /proc/<pid>/cmdline (mode 0444), ps, and argv-recording audit tools expose
# them. They reach jq on stdin or through the environment of the jq process
# itself, which only its owner can read.

parse_redis_nodes() (
  node_list=$1
  node_variable=$2
  tls_variable=$3
  tls_enabled=$4
  # Trailing blanks need no trimming: the split below drops empty entries, and
  # an anchored trailing-blank pattern is quadratic on long input.
  nodes=$(printf '%s' "$node_list" | jq -Rsc --arg tlsVariable "$tls_variable" --arg tlsEnabled "$tls_enabled" '
    "^(?<scheme>rediss?://)?(?:\\[(?<ipv6>[0-9A-Fa-f.]*:[0-9A-Fa-f:.]*)\\]|(?<host>[^\\[\\]:/?#@[:space:]]+)):(?<port>[0-9]+)$" as $pattern |
    sub("^[[:space:]]+"; "") as $trimmed |
    ($trimmed | gsub("[[:space:],]+"; " ") | split(" ") | map(select(length > 0))) as $entries |
    if $trimmed == "" then
      error("must contain at least one node")
    elif ($trimmed | test("(^,|,[[:space:]]*$|,[[:space:]]*,)")) then
      error("must not contain empty node entries")
    elif ($entries | length) == 0 then
      error("must contain at least one node")
    elif any($entries[]; test($pattern) | not) then
      error("each node must use host:port, [IPv6]:port, redis://host:port or rediss://host:port")
    else
      ($entries | map(
        capture($pattern) |
        (.port | tonumber) as $port |
        if $port < 1 or $port > 65535 then
          error("port must be between 1 and 65535")
        else
          {host: (.ipv6 // .host), port: $port, tls: (.scheme == "rediss://")}
        end
      )) as $nodes |
      if any($nodes[]; .tls) and $tlsEnabled != "true" then
        error("rediss:// requires \($tlsVariable)=true; set it or list the nodes as host:port")
      elif (($nodes | map("\(.host | ascii_downcase):\(.port)") | unique | length) != ($nodes | length)) then
        error("must not contain duplicate nodes")
      else
        $nodes | map(del(.tls))
      end
    end
  ') || {
    echo "ERROR: invalid ${node_variable}; see validation error above." >&2
    exit 1
  }
  printf '%s' "$nodes"
)

# Arguments: port value, name of the setting for the error message.
redis_require_port() {
  case "${1:-}" in
    ''|*[!0-9]*) ;;
    *)
      # Strip leading zeros so that the length check and test(1) see the value.
      port_digits=$(printf '%s' "$1" | sed 's/^0*//')
      if [ "${#port_digits}" -le 5 ] && [ "${port_digits:-0}" -ge 1 ] && [ "$port_digits" -le 65535 ]; then
        return 0
      fi
      ;;
  esac
  echo "ERROR: $2 must be an integer between 1 and 65535." >&2
  return 1
}

# Sets REDIS_SENTINEL_REQUESTED, REDIS_SENTINEL_NODES_JSON (null keeps the
# Sentinel addresses from local.json or NODE_CONFIG) and
# REDIS_CLUSTER_NODES_JSON.
#
# REDIS_SENTINEL_LOCAL_FALLBACK=false (standalone image): the bundled Redis on
# localhost:6379 is never a Sentinel, so REDIS_SENTINEL_* settings without
# REDIS_SENTINEL_NODES do not fall back to REDIS_SERVER_HOST:REDIS_SERVER_PORT.
# They apply to a Sentinel configured in local.json or NODE_CONFIG when the
# caller sets REDIS_SENTINEL_IN_CONFIG=true. Otherwise, with the bundled Redis,
# they are ignored, as they were before these variables existed.
redis_topology_init() {
  if ! command -v require_bool >/dev/null 2>&1; then
    echo 'ERROR: source bool.sh before redis-topology.sh.' >&2
    return 1
  fi
  require_bool REDIS_SERVER_TLS REDIS_SENTINEL_TLS
  REDIS_SERVER_TLS=${REDIS_SERVER_TLS:-false}
  REDIS_SENTINEL_TLS=${REDIS_SENTINEL_TLS:-false}
  REDIS_SENTINEL_USER="${REDIS_SENTINEL_USER:-${REDIS_SENTINEL_USERNAME:-}}"
  REDIS_SENTINEL_PASS="${REDIS_SENTINEL_PASS:-${REDIS_SENTINEL_PWD:-}}"
  REDIS_SENTINEL_REQUESTED=false
  if [ -n "${REDIS_SENTINEL_NODES:-}" ] || [ -n "${REDIS_SENTINEL_GROUP_NAME:-}" ] \
    || [ -n "$REDIS_SENTINEL_USER" ] || [ -n "$REDIS_SENTINEL_PASS" ]; then
    REDIS_SENTINEL_REQUESTED=true
  fi

  REDIS_SENTINEL_NODES_JSON='[]'
  REDIS_CLUSTER_NODES_JSON='[]'
  redis_keep_config_sentinel_nodes=false
  if [ "$REDIS_SENTINEL_REQUESTED" = true ] && [ "${REDIS_SENTINEL_LOCAL_FALLBACK:-true}" != true ] \
    && [ -z "${REDIS_SENTINEL_NODES:-}" ]; then
    if [ "${REDIS_SENTINEL_IN_CONFIG:-false}" = true ]; then
      redis_keep_config_sentinel_nodes=true
    elif [ "${REDIS_SERVER_HOST:-localhost}" = localhost ]; then
      echo "WARNING: ignoring REDIS_SENTINEL_* settings because no Sentinel address is set;" \
        "set REDIS_SENTINEL_NODES to use Redis Sentinel." >&2
      REDIS_SENTINEL_REQUESTED=false
    fi
  fi

  if [ "$REDIS_SENTINEL_REQUESTED" = true ] && [ -n "${REDIS_CLUSTER_NODES:-}" ]; then
    echo "ERROR: Redis Sentinel and Redis Cluster cannot be configured together." >&2
    return 1
  fi

  if [ "$REDIS_SENTINEL_REQUESTED" = true ]; then
    REDIS_SENTINEL_GROUP_NAME="${REDIS_SENTINEL_GROUP_NAME:-mymaster}"
    case "$REDIS_SENTINEL_GROUP_NAME" in
      *[![:print:]]*|*[[:space:]]*)
        echo "ERROR: REDIS_SENTINEL_GROUP_NAME must not contain whitespace or control characters." >&2
        return 1
        ;;
    esac
    if [ "$redis_keep_config_sentinel_nodes" = true ]; then
      REDIS_SENTINEL_NODES_JSON=null
    else
      if [ -z "${REDIS_SENTINEL_NODES:-}" ]; then
        redis_require_port "${REDIS_SERVER_PORT:-6379}" REDIS_SERVER_PORT || return 1
        case "${REDIS_SERVER_HOST:-localhost}" in
          *:*) REDIS_SENTINEL_NODES="[${REDIS_SERVER_HOST}]:${REDIS_SERVER_PORT:-6379}" ;;
          *) REDIS_SENTINEL_NODES="${REDIS_SERVER_HOST:-localhost}:${REDIS_SERVER_PORT:-6379}" ;;
        esac
      fi
      REDIS_SENTINEL_NODES_JSON=$(parse_redis_nodes "$REDIS_SENTINEL_NODES" REDIS_SENTINEL_NODES \
        REDIS_SENTINEL_TLS "$REDIS_SENTINEL_TLS") || return 1
    fi
  fi
  if [ -n "${REDIS_CLUSTER_NODES:-}" ]; then
    REDIS_CLUSTER_NODES_JSON=$(parse_redis_nodes "$REDIS_CLUSTER_NODES" REDIS_CLUSTER_NODES \
      REDIS_SERVER_TLS "$REDIS_SERVER_TLS") || return 1
  fi
}

redis_require_database() {
  case "${1:-}" in
    *[!0-9]*)
      echo 'ERROR: the Redis database must be a non-negative integer.' >&2
      return 1
      ;;
  esac
}

# Prints the local.json that node-config also loads as one JSON object, or {}
# when there is none. Argument: the file path.
#
# node-config reads .json files as JSON5. Comments and trailing commas, the
# usual hand-edits, are removed before parsing. A file that still does not
# parse is reported and treated as {}: the server then reads it with its own
# parser, and only the checks below do not see its Redis settings.
redis_config_file_json() (
  config_file=${1:-}
  if [ -z "$config_file" ] || [ ! -e "$config_file" ]; then
    echo '{}'
    exit 0
  fi
  jq -Rsc '
    "(?<s>\"(?:[^\"\\\\]|\\\\.)*\")" as $string |
    if test("^[[:space:]]*$") then {}
    else
      . as $text |
      (try fromjson catch ($text |
        gsub($string + "|//[^\\n]*|/\\*(?:[^*]|\\*+[^*/])*\\*+/"; .s // "") |
        gsub($string + "|,(?=[[:space:]]*[}\\]])"; .s // "") |
        fromjson
      )) | objects
    end
  ' <"$config_file" 2>/dev/null | grep . || {
    echo "WARNING: could not parse $config_file as JSON; its Redis settings are not" \
      "checked or combined with the REDIS_* variables." >&2
    echo '{}'
  }
)

# jq definitions shared by the option builders. Credentials are read from the
# jq process environment ($ENV), never from arguments.
#
# A `default` user with an empty password is written as
# {username: "default", password: ""}. The server treats that pair as
# unauthenticated, which keeps a `default` username left in local.json by older
# entrypoints working. redis_merge_node_config drops the pair again when the
# configuration supplies a real password.
REDIS_TOPOLOGY_JQ_DEFS='
  def credentials($user; $pass):
    if $user != "" then .username = $user else . end |
    if $pass != "" or $user == "default" then .password = $pass else . end;
  def database($db): if $db != "" then .database = ($db | tonumber) else . end;
  def tls($enabled): if $enabled then .socket.tls = true else . end;
'

# Base (non-topology) client options: user, password, database.
redis_build_base_options() (
  redis_require_database "${3:-}" || exit 1
  REDIS_TOPOLOGY_USER=${1:-} REDIS_TOPOLOGY_PASS=${2:-} jq -cn \
    --arg redisDb "${3:-}" \
    --argjson redisTLS "${REDIS_SERVER_TLS:-false}" \
    "$REDIS_TOPOLOGY_JQ_DEFS"'
      {} | database($redisDb) | tls($redisTLS) |
      credentials($ENV.REDIS_TOPOLOGY_USER; $ENV.REDIS_TOPOLOGY_PASS)
    '
)

# Arguments: name, nodes JSON (null keeps the configured nodes), user,
# password, database, Sentinel user, Sentinel password.
#
# nodeClientOptions gets no socket: the server builds the data-node options
# with a shallow {...options, ...nodeClientOptions}, so a socket here would
# replace options.socket (ca, servername, ...) instead of adding to it.
# REDIS_SERVER_TLS reaches the data nodes through options.socket.tls.
redis_build_sentinel_options() (
  redis_require_database "${5:-}" || exit 1
  REDIS_TOPOLOGY_USER=${3:-} REDIS_TOPOLOGY_PASS=${4:-} \
  REDIS_TOPOLOGY_SENTINEL_USER=${6:-} REDIS_TOPOLOGY_SENTINEL_PASS=${7:-} jq -cn \
    --arg name "${1:-mymaster}" \
    --argjson nodes "${2:-[]}" \
    --arg redisDb "${5:-}" \
    --argjson sentinelTLS "${REDIS_SENTINEL_TLS:-false}" \
    "$REDIS_TOPOLOGY_JQ_DEFS"'
    {name: $name} +
    (if $nodes != null then {sentinelRootNodes: $nodes} else {} end) +
    {
      nodeClientOptions: ({} | database($redisDb) |
        credentials($ENV.REDIS_TOPOLOGY_USER; $ENV.REDIS_TOPOLOGY_PASS)),
      sentinelClientOptions: ({} | tls($sentinelTLS) |
        credentials($ENV.REDIS_TOPOLOGY_SENTINEL_USER; $ENV.REDIS_TOPOLOGY_SENTINEL_PASS))
    }'
)

# Arguments: nodes JSON, user, password.
redis_build_cluster_options() (
  REDIS_TOPOLOGY_USER=${2:-} REDIS_TOPOLOGY_PASS=${3:-} jq -cn \
    --argjson nodes "${1:-[]}" \
    --argjson redisTLS "${REDIS_SERVER_TLS:-false}" \
    "$REDIS_TOPOLOGY_JQ_DEFS"'{
      rootNodes: ($nodes | map({url: (
        (if $redisTLS then "rediss://" else "redis://" end) +
        (if (.host | contains(":")) then "[\(.host)]" else .host end) + ":" + (.port | tostring)
      )})),
      defaults: ({} | tls($redisTLS) |
        credentials($ENV.REDIS_TOPOLOGY_USER; $ENV.REDIS_TOPOLOGY_PASS))
    }'
)

# Builds services.CoAuthoring.redis from the base, Sentinel and Cluster option
# documents read from stdin, one JSON value per line. Pass `null` for a
# topology that is not requested. The unused topology is set to null rather
# than {}: node-config replaces null but deep-merges {}, which would keep a
# topology from local.json alongside the requested one.
# Arguments: host, port, optional connector name.
redis_build_section() (
  redis_require_port "$2" REDIS_SERVER_PORT || exit 1
  jq -cs --arg host "$1" --argjson port "$(printf '%s' "$2" | sed 's/^0*//')" --arg name "${3:-}" '
    .[0] as $options | .[1] as $sentinel | .[2] as $cluster |
    (if $name != "" then {name: $name} else {} end) +
    {host: $host, port: $port, options: $options} |
    if $sentinel != null then .optionsSentinel = $sentinel | .optionsCluster = null
    elif $cluster != null then .optionsCluster = $cluster | .optionsSentinel = null
    else . end
  '
)

# jq definitions describing the effective Redis configuration.
REDIS_EFFECTIVE_JQ_DEFS='
  def obj: if type == "object" then . else {} end;
  def redis_of: (.services?.CoAuthoring?.redis? | objects) // {};
  def sentinel_active:
    (.optionsSentinel // {}) |
    if type == "object" or type == "array" or type == "string" then length > 0 else false end;
  def cluster_active: [.optionsCluster | objects | .rootNodes | arrays | length > 0] | any;
  def placeholder: type == "object" and .username == "default" and .password == "";
  def has_password: (obj | .password) != null;
  # Settings the entrypoint reads or writes into; each must be an object
  # (or null) wherever it is set.
  def invalid_settings:
    (try .services.CoAuthoring.redis catch null) as $redis |
    if $redis == null then []
    elif ($redis | type) != "object" then ["services.CoAuthoring.redis"]
    else [
      [["options"], ["options", "socket"],
       ["optionsSentinel"], ["optionsSentinel", "nodeClientOptions"],
       ["optionsSentinel", "nodeClientOptions", "socket"],
       ["optionsSentinel", "sentinelClientOptions"],
       ["optionsSentinel", "sentinelClientOptions", "socket"],
       ["optionsCluster"], ["optionsCluster", "defaults"],
       ["optionsCluster", "defaults", "socket"]][] as $path |
      select(($redis | try getpath($path) catch "") | . != null and type != "object") |
      "services.CoAuthoring.redis." + ($path | join("."))
    ] | .[:1]
    end;
'

# Combines the generated configuration with an operator NODE_CONFIG and prints
# the NODE_CONFIG to export. Reads two JSON objects from stdin: the generated
# configuration, then the operator override. Argument: the local.json that
# node-config also loads, if any.
#
# - The generated `default` + "" placeholder yields to a password supplied in
#   local.json or NODE_CONFIG: the username goes too, so the configured user
#   applies with its password.
# - REDIS_SERVER_TLS and REDIS_SENTINEL_TLS also apply to a Sentinel or Cluster
#   topology configured in local.json or NODE_CONFIG.
# - Cluster seed URL schemes follow an explicit effective defaults.socket.tls,
#   since node-redis refuses a mismatch. Without one, the scheme decides.
# - Sentinel together with Cluster, and a Sentinel username from the
#   environment without any Sentinel password, stop startup.
redis_merge_node_config() (
  sentinel_user_set=false
  [ "${REDIS_SENTINEL_REQUESTED:-false}" = true ] && [ -n "${REDIS_SENTINEL_USER:-}" ] &&
    sentinel_user_set=true
  result=$({ cat; redis_config_file_json "${1:-}"; } | jq -cs \
    --argjson serverTLS "${REDIS_SERVER_TLS:-false}" \
    --argjson sentinelTLS "${REDIS_SENTINEL_TLS:-false}" \
    --argjson sentinelUserSet "$sentinel_user_set" \
    "$REDIS_EFFECTIVE_JQ_DEFS"'
    .[0] as $generated | .[1] as $override | .[2] as $file |
    def without_placeholder($path; $configured):
      if (getpath($path) | placeholder) and $configured then
        delpaths([$path + ["username"], $path + ["password"]])
      else . end;
    if ($file | invalid_settings | length) > 0 then
      ["\($file | invalid_settings[0]) in local.json must be a JSON object.", null]
    elif ($override | invalid_settings | length) > 0 then
      ["\($override | invalid_settings[0]) in NODE_CONFIG must be a JSON object.", null]
    else
      ($file * $override | redis_of) as $external |
      ($generated | redis_of) as $section |

      # Keep the placeholder only where no real password is configured.
      ($section |
        without_placeholder(["options"]; $external.options | has_password) |
        without_placeholder(["optionsSentinel", "nodeClientOptions"];
          ($external.optionsSentinel | obj | .nodeClientOptions | has_password) or
          ($external.options | has_password)) |
        without_placeholder(["optionsSentinel", "sentinelClientOptions"];
          $external.optionsSentinel | obj | .sentinelClientOptions | has_password) |
        without_placeholder(["optionsCluster", "defaults"];
          $external.optionsCluster | obj | .defaults | has_password)
      ) as $section |

      # Apply the TLS flags to topologies that come from configuration too.
      # The data nodes of a Sentinel inherit options.socket.tls (see
      # redis_build_sentinel_options); a configured nodeClientOptions.socket
      # replaces that socket, so it gets the flag itself.
      ($file * ($generated | .services.CoAuthoring.redis = $section) * $override | redis_of) as $effective |
      ($section |
        if ($effective | sentinel_active) and ($effective.optionsSentinel | type) == "object" then
          (if $serverTLS and ($effective.optionsSentinel.nodeClientOptions | obj | .socket | type) == "object" then
            .optionsSentinel.nodeClientOptions.socket.tls = true else . end) |
          (if $sentinelTLS then .optionsSentinel.sentinelClientOptions.socket.tls = true else . end)
        else . end |
        if ($effective | cluster_active) and $serverTLS then
          .optionsCluster.defaults.socket.tls = true
        else . end
      ) as $section |

      ($generated | .services.CoAuthoring.redis = $section) * $override |
      . as $config |
      ($file * $config | redis_of) as $effective |
      (if ($effective | cluster_active) and
          ($effective.optionsCluster.defaults | obj | .socket | obj | .tls | type) == "boolean" then
        $effective.optionsCluster.defaults.socket.tls as $clusterTLS |
        ($effective.optionsCluster.rootNodes | map(
          if type == "object" and (.url | type) == "string" then
            .url |= sub("^rediss?://"; if $clusterTLS then "rediss://" else "redis://" end; "i")
          else . end
        )) as $aligned |
        if $aligned != $effective.optionsCluster.rootNodes or ($section.optionsCluster | obj | has("rootNodes")) then
          .services.CoAuthoring.redis.optionsCluster.rootNodes = $aligned
        else . end
      else . end) as $config |

      ($file * $config | redis_of) as $effective |
      if ($effective | sentinel_active) and ($effective | cluster_active) then
        ["Redis Sentinel and Redis Cluster cannot be configured together.", null]
      elif $sentinelUserSet and ($effective | sentinel_active) and
           ($effective.optionsSentinel | obj | .sentinelClientOptions | obj |
             .username != null and .password == null) then
        ["REDIS_SENTINEL_USER is set without a Sentinel password. Set REDIS_SENTINEL_PASS, or use REDIS_SENTINEL_USER=default for Sentinels without authentication.", null]
      else
        [null, $config]
      end
    end
  ' 2>/dev/null) || {
    # jq diagnostics can quote configuration values, so they are not shown.
    echo 'ERROR: could not merge the Redis configuration. Check that NODE_CONFIG is valid JSON' \
      'and that services.CoAuthoring.redis and its option settings are objects.' >&2
    exit 1
  }
  problem=$(printf '%s' "$result" | jq -r '.[0] // empty')
  if [ -n "$problem" ]; then
    echo "ERROR: $problem" >&2
    exit 1
  fi
  printf '%s' "$result" | jq -c '.[1]'
)

# Prints "sentinel", "cluster" or "standalone" for the effective configuration.
# Reads the NODE_CONFIG to export on stdin. Argument: local.json, if any.
redis_effective_topology() (
  { cat; redis_config_file_json "${1:-}"; } | jq -rs "$REDIS_EFFECTIVE_JQ_DEFS"'
    (.[1] * .[0] | redis_of) |
    if sentinel_active then "sentinel" elif cluster_active then "cluster" else "standalone" end
  '
)
