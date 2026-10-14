#!/usr/bin/env bash
set -e

# --------------------------------------------------------------------
# Service mode (first positional argument)
# Supported modes:
#   - docservice
#   - converter
#   - adminpanel
# --------------------------------------------------------------------
MODE="${1:-docservice}"
shift || true

case "$MODE" in
  docservice|converter|adminpanel)
    ;;
  *)
    echo "Unknown mode: $MODE (use: docservice|converter|adminpanel)" >&2
    exit 2
    ;;
esac

if [[ -n ${LOG_LEVEL} ]]; then
  sed 's/\(^.\+"level":\s*"\).\+\(".*$\)/\1'$LOG_LEVEL'\2/g' -i /etc/$COMPANY_NAME/documentserver/log4js/production.json
fi

if [[ -n ${LOG_TYPE} ]]; then
  sed 's/\("type"\:\) "pattern"/\1 "'$LOG_TYPE'"/' -i /etc/$COMPANY_NAME/documentserver/log4js/production.json
fi

if [[ -n ${LOG_PATTERN} ]]; then
  sed "s/\(\"pattern\"\:\).*/\1 \"$LOG_PATTERN\"/" -i /etc/$COMPANY_NAME/documentserver/log4js/production.json
fi

ACTIVEMQ_TRANSPORT=""
case $AMQP_PROTO in
  amqps | amqp+ssl)
    ACTIVEMQ_TRANSPORT="tls"
    ;;
  *)
    ACTIVEMQ_TRANSPORT="tcp"
    ;;
esac

if [[ -n "$REDIS_SENTINEL_NODES" ]]; then
  declare -a REDIS_SENTINEL_NODES_ALL=($REDIS_SENTINEL_NODES)
  REDIS_SENTINEL_NODES_ARRAY=()
  for node in "${REDIS_SENTINEL_NODES_ALL[@]}"; do
    host="${node%%:*}"
    port="${node##*:}"
    REDIS_SENTINEL_NODES_ARRAY+=('{ "host": "'$host'", "port": '$port' }')
  done
  OLD_IFS="$IFS"
  IFS=","
  NODES=$(echo "${REDIS_SENTINEL_NODES_ARRAY[*]}")
  IFS="$OLD_IFS"
  REDIS_SENTINEL='[ '$NODES' ],'
else
  REDIS_SENTINEL='[ { "host": "'${REDIS_SERVER_HOST:-localhost}'", "port": '${REDIS_SERVER_PORT:-6379}' } ],'
fi

if [[ -n "$REDIS_CLUSTER_NODES" ]]; then
  declare -a REDIS_CLUSTER_NODES_ALL=($REDIS_CLUSTER_NODES)
  REDIS_CLUSTER_NODES_ARRAY=()
  for node in "${REDIS_CLUSTER_NODES_ALL[@]}"; do
    REDIS_CLUSTER_NODES_ARRAY+=('{ "url": "redis://'$node'" }')
  done
  OLD_IFS="$IFS"
  IFS=","
  NODES=$(echo "${REDIS_CLUSTER_NODES_ARRAY[*]}")
  IFS="$OLD_IFS"
  REDIS_CLUSTER='"rootNodes": [ '$NODES' ], "defaults": { "username": "'${REDIS_SERVER_USER:-default}'", "password": "'$REDIS_SERVER_PWD'" }'
else
  REDIS_CLUSTER=''
fi

# --------------------------------------------------------------------
# Fail closed on insecure default secrets.
#
# The standalone image generates and persists random secrets, but cluster
# pods are ephemeral and run as multiple replicas behind a shared proxy: a
# per-pod generated secret would differ across replicas and break JWT /
# secure-link verification. Secrets must therefore be supplied explicitly
# (e.g. via a Kubernetes Secret). Refuse to start with the known upstream
# placeholder values ("secret" / "verysecretstring") when the corresponding
# feature is enabled, rather than silently accepting forgeable tokens.
# --------------------------------------------------------------------
JWT_ENABLED_EFF="${JWT_ENABLED:-true}"
JWT_ENABLED_INBOX_EFF="${JWT_ENABLED_INBOX:-$JWT_ENABLED_EFF}"
JWT_ENABLED_OUTBOX_EFF="${JWT_ENABLED_OUTBOX:-$JWT_ENABLED_EFF}"

# browser/session verify with JWT_SECRET directly; inbox/outbox fall back to it.
if [ "$JWT_ENABLED_EFF" = "true" ] && [ -z "${JWT_SECRET:-}" ]; then
  echo "ERROR: JWT browser verification is enabled (JWT_ENABLED=true) but JWT_SECRET is not set. Provide a strong JWT_SECRET (e.g. via a Kubernetes Secret) or set JWT_ENABLED=false. Refusing to start with an insecure default." >&2
  exit 1
fi
if [ "$JWT_ENABLED_INBOX_EFF" = "true" ] && [ -z "${JWT_SECRET_INBOX:-}" ] && [ -z "${JWT_SECRET:-}" ]; then
  echo "ERROR: inbox JWT is enabled but neither JWT_SECRET_INBOX nor JWT_SECRET is set. Refusing to start with an insecure default." >&2
  exit 1
fi
if [ "$JWT_ENABLED_OUTBOX_EFF" = "true" ] && [ -z "${JWT_SECRET_OUTBOX:-}" ] && [ -z "${JWT_SECRET:-}" ]; then
  echo "ERROR: outbox JWT is enabled but neither JWT_SECRET_OUTBOX nor JWT_SECRET is set. Refusing to start with an insecure default." >&2
  exit 1
fi

if [ -z "${SECURE_LINK_SECRET:-}" ]; then
  echo "ERROR: SECURE_LINK_SECRET is not set. It signs internal cache/file URLs and must be identical across all Docs and proxy replicas. Provide a strong shared value (e.g. via a Kubernetes Secret). Refusing to start with an insecure default." >&2
  exit 1
fi

# --------------------------------------------------------------------
# NODE_CONFIG (exported for Docs services)
# --------------------------------------------------------------------
export NODE_CONFIG='{
  "statsd": {
    "useMetrics": '${METRICS_ENABLED:-false}',
    "host": "'${METRICS_HOST:-localhost}'",
    "port": '${METRICS_PORT:-8125}',
    "prefix": "'${METRICS_PREFIX:-ds.}'"
  },
  "runtimeConfig": {
    "filePath": "/var/www/'${COMPANY_NAME}'/config/runtime.json"
  },
  "services": {
    "CoAuthoring": {
      "sql": {
        "type": "'${DB_TYPE:-postgres}'",
        "dbHost": "'${DB_HOST:-localhost}'",
        "dbPort": '${DB_PORT:-5432}',
        "dbUser": "'${DB_USER:=onlyoffice}'",
        "dbName": "'${DB_NAME:-${DB_USER}}'",
        "dbPass": "'${DB_PWD:-onlyoffice}'"
      },
      "redis": {
        "name": "'${REDIS_CONNECTOR_NAME:-redis}'",
        "host": "'${REDIS_SERVER_HOST:-${REDIST_SERVER_HOST:-localhost}}'",
        "port": '${REDIS_SERVER_PORT:-${REDIST_SERVER_PORT:-6379}}',
        "options": {
          "user": "'${REDIS_SERVER_USER:-default}'",
          "password": "'${REDIS_SERVER_PWD}'",
          "db": "'${REDIS_SERVER_DB_NUM:-0}'"
        },
        "optionsCluster": { '${REDIS_CLUSTER}' },
        "iooptions": {
          "sentinels": '${REDIS_SENTINEL}'
          "name": "'${REDIS_SENTINEL_GROUP_NAME:-mymaster}'",
          "sentinelPassword": "'${REDIS_SENTINEL_PWD}'",
          "username": "'${REDIS_SERVER_USER:-default}'",
          "password": "'${REDIS_SERVER_PWD}'",
          "db": "'${REDIS_SERVER_DB_NUM:-0}'"
        }
      },
      "token": {
        "enable": {
          "browser": '${JWT_ENABLED:=true}',
          "request": {
            "inbox": '${JWT_ENABLED_INBOX:-${JWT_ENABLED}}',
            "outbox": '${JWT_ENABLED_OUTBOX:-${JWT_ENABLED}}'
          }
        },
        "inbox": {
          "header": "'${JWT_HEADER_INBOX:-${JWT_HEADER:=Authorization}}'",
          "inBody": '${JWT_IN_BODY:=false}'
        },
        "outbox": {
          "header": "'${JWT_HEADER_OUTBOX:-${JWT_HEADER}}'",
          "inBody": '${JWT_IN_BODY}'
        }
      },
      "secret": {
        "inbox": {
          "string": "'${JWT_SECRET_INBOX:-${JWT_SECRET}}'"
        },
        "outbox": {
          "string": "'${JWT_SECRET_OUTBOX:-${JWT_SECRET}}'"
        },
        "browser": {
          "string": "'${JWT_SECRET}'"
        },
        "session": {
          "string": "'${JWT_SECRET}'"
        }
      },
      "request-filtering-agent" : {
        "allowPrivateIPAddress": '${ALLOW_PRIVATE_IP_ADDRESS:-false}',
        "allowMetaIPAddress": '${ALLOW_META_IP_ADDRESS:-false}',
        "allowIPAddressList": '${ALLOW_IP_ADDRESS_LIST:-[]}',
        "denyIPAddressList": '${DENY_IP_ADDRESS_LIST:-[]}'
      }
    }
  },
  "queue": {
    "type": "'${AMQP_TYPE:=rabbitmq}'"
  },
  "activemq": {
    "connectOptions": {
      "port": "'${AMQP_PORT:=5672}'",
      "host": "'${AMQP_HOST:=localhost}'",
      "username": "'${AMQP_USER:=guest}'",
      "password": "'${AMQP_PWD:=guest}'",
      "transport": "'${ACTIVEMQ_TRANSPORT}'"
    }
  },
  "rabbitmq": {
    "url": "'${AMQP_URI:-${AMQP_PROTO:-amqp}://${AMQP_USER}:${AMQP_PWD}@${AMQP_HOST}:${AMQP_PORT}${AMQP_VHOST:-/}}'"
  },
  "wopi": {
    "enable": '${WOPI_ENABLED:-false}',
    "privateKey": "'${WOPI_PRIVATE_KEY}'",
    "privateKeyOld": "'${WOPI_PRIVATE_KEY_OLD}'",
    "publicKey": "'${WOPI_PUBLIC_KEY}'",
    "publicKeyOld": "'${WOPI_PUBLIC_KEY_OLD}'",
    "modulus": "'${WOPI_MODULUS_KEY}'",
    "modulusOld": "'${WOPI_MODULUS_KEY_OLD}'",
    "exponent": '${WOPI_EXPONENT_KEY:=65537}',
    "exponentOld": '${WOPI_EXPONENT_KEY_OLD:-${WOPI_EXPONENT_KEY}}'
  },
  "FileConverter": {
    "converter": {
        "maxprocesscount": 0.001,
        "maxDownloadBytes": '${FILECONVERTER_MAX_DOWNLOAD_BYTES:-524288000}',
        "inputLimits": [
          { "type": "docx;dotx;docm;dotm", "zip": { "uncompressed": "'${FILECONVERTER_INPUT_LIMIT_UNCOMPRESSED:-500MB}'", "template": "*.xml" } },
          { "type": "xlsx;xltx;xlsm;xltm", "zip": { "uncompressed": "'${FILECONVERTER_INPUT_LIMIT_UNCOMPRESSED:-500MB}'", "template": "*.xml" } },
          { "type": "pptx;ppsx;potx;pptm;ppsm;potm", "zip": { "uncompressed": "'${FILECONVERTER_INPUT_LIMIT_UNCOMPRESSED:-500MB}'", "template": "*.xml" } },
          { "type": "vsdx;vstx;vssx;vsdm;vstm;vssm", "zip": { "uncompressed": "'${FILECONVERTER_INPUT_LIMIT_UNCOMPRESSED:-500MB}'", "template": "*.xml" } }
        ],
        "signingKeyStorePath": "/var/www/'${COMPANY_NAME}'/config/signing-keystore.p12"
    }
  },
  "storage": {
    "fs": {
      "folderPath": "/var/lib/'${COMPANY_NAME}'/documentserver/App_Data/cache/files/'${STORAGE_SUBDIRECTORY_NAME:-latest}'",
      "secretString": "'${SECURE_LINK_SECRET}'"
    },
    "storageFolderName": "files/'${STORAGE_SUBDIRECTORY_NAME:-latest}'"
  },
  "persistentStorage": {
    "fs": {
      "folderPath": "/var/lib/'${COMPANY_NAME}'/documentserver/App_Data/cache/files",
      "secretString": "'${SECURE_LINK_SECRET}'"
    },
    "storageFolderName": "files"
  }
}'

WORK_DIR="/var/www/$COMPANY_NAME/documentserver"
BUILD_FONTS=false
BUILD_PLUGINS=false
BUILD_DICTIONARIES=false

OPTIND=1
while getopts ":fpd" opt; do
  case "$opt" in
    f) BUILD_FONTS=true ;;
    p) BUILD_PLUGINS=true ;;
    d) BUILD_DICTIONARIES=true ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      exit 2
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ "${BUILD_FONTS}" == "true" ]]; then
  if [[ "$MODE" == "converter" ]]; then
    if [ "$(find "$WORK_DIR/fonts" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      echo -e "\e[0;32m Fonts have already been added, preparatory steps, please wait... \e[0m"
      if [[ -n "$DOCS_SHARDS" ]]; then
        until [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/index.html || true)" = "200" ]
        do
          sleep 5
        done
      fi
      cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/AllFonts.js $WORK_DIR/sdkjs/common/
      cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/bin/* $WORK_DIR/server/FileConverter/bin/
      echo -e "\e[0;32m Completed \e[0m"
    else
      if [[ -n "$DOCS_SHARDS" ]]; then
        echo -e "\e[0;32m Waiting for Fonts to be added, please wait... \e[0m"
        until [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/index.html || true)" = "200" ]
        do
          sleep 5
        done
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/AllFonts.js $WORK_DIR/sdkjs/common/
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/bin/* $WORK_DIR/server/FileConverter/bin/
      else
        echo -e "\e[0;32m Run Fonts adding, please wait... \e[0m"
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/Images/* $WORK_DIR/sdkjs/common/Images/
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/themes/* $WORK_DIR/sdkjs/slide/themes/
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/fonts/* $WORK_DIR/fonts/
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/custom-k8s/* $WORK_DIR/core-fonts/custom-k8s/
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/AllFonts.js $WORK_DIR/sdkjs/common/
        cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/bin/* $WORK_DIR/server/FileConverter/bin/
      fi
      echo -e "\e[0;32m Fonts have been added successfully \e[0m"
    fi
  fi
fi

if [[ "${BUILD_PLUGINS}" == "true" ]]; then
  if [[ "$MODE" != "converter" ]]; then
    echo -e "\e[0;32m Waiting for Plugins to be added, please wait... \e[0m"
    until [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/ 2>/dev/null || true)" != "000" ]
    do
      sleep 5
    done
    if [ "$(find "$WORK_DIR/sdkjs-plugins" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      echo -e "\e[0;32m Plugins have been added successfully \e[0m"
    else
      echo -e "\e[0;31m No plugins added \e[0m"
    fi
  fi
fi

if [[ "${BUILD_DICTIONARIES}" == "true" ]]; then
  if [[ "$MODE" == "converter" ]]; then
    echo -e "\e[0;32m Run Dictionaries adding, please wait... \e[0m"
    ( find $WORK_DIR/sdkjs/cell $WORK_DIR/sdkjs/word $WORK_DIR/sdkjs/slide $WORK_DIR/sdkjs/visio -maxdepth 1 -type f \( -name '*.js' -o -name '*.bin' \)
      echo "$WORK_DIR/sdkjs/common/spell/spell/spell.js" ) | while read -r file; do
        chmod 740 "$file"
        dir=$(basename "$(dirname "$file")")
        base_file=$(basename "$file")
        if [[ "${base_file}" == "spell.js" ]]; then
          target_dir="$WORK_DIR/sdkjs/common/spell/$dir"
        else
          target_dir="$WORK_DIR/sdkjs/$dir"
        fi
        cp -a "/var/lib/$COMPANY_NAME/documentserver/buffer/dictionaries/$dir/$base_file" "$target_dir/"
        chmod 440 "$target_dir/$base_file"
    done
    if [ "$(find "$WORK_DIR/dictionaries" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      if [[ -n "$DOCS_SHARDS" ]]; then
        until [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/index.html || true)" = "200" ]
        do
          sleep 5
        done
      fi
      echo -e "\e[0;32m Completed \e[0m"
    else
      if [[ -n "$DOCS_SHARDS" ]]; then
        echo -e "\e[0;32m Waiting for Dictionaries to be added, please wait... \e[0m"
        until [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/index.html || true)" = "200" ]
        do
          sleep 5
        done
      else
        cp -ra /var/lib/$COMPANY_NAME/documentserver/buffer/dictionaries/dictionaries/* $WORK_DIR/dictionaries/
      fi
      echo -e "\e[0;32m Dictionaries have been added successfully \e[0m"
    fi
  fi
fi

# --------------------------------------------------------------------
# Exec docs service
# --------------------------------------------------------------------
case "$MODE" in
  docservice)
    exec "/var/www/${COMPANY_NAME}/documentserver/server/DocService/docservice" "$@"
    ;;
  converter)
    exec "/var/www/${COMPANY_NAME}/documentserver/server/FileConverter/converter" "$@"
    ;;
  adminpanel)
    exec "/var/www/${COMPANY_NAME}/documentserver/server/AdminPanel/server/adminpanel" "$@"
    ;;
esac
