#!/bin/sh
set -e

# --------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------
EO_ROOT="${EO_ROOT:-/var/www/euro-office/documentserver}"
EO_LOG="${EO_LOG:-/var/log/euro-office/documentserver}"
EO_CONF="${EO_CONF:-/etc/euro-office/documentserver}"
DATA_DIR="/var/www/euro-office/Data"
PRIVATE_DIR="${DATA_DIR}/.private"
CONFIG_FILE="${EO_CONF}/local.json"
LOG4JS_CONFIG="${EO_CONF}/log4js/production.json"
EXAMPLE_CONF_DIR="${EO_CONF}-example"
EXAMPLE_LOCAL="${EXAMPLE_CONF_DIR}/local.json"
NGINX_CONFIG_PATH="/etc/nginx/nginx.conf"
NGINX_DS_DIR="${EO_CONF}/nginx"
NGINX_DS_CONF="${NGINX_DS_DIR}/ds.conf"
NGINX_DS_COMMON_CONF="${NGINX_DS_DIR}/includes/ds-common.conf"
NGINX_DS_SSL_TMPL="${NGINX_DS_DIR}/ds-ssl.conf.tmpl"
SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"

# --------------------------------------------------------------------
# Defaults (aligned with upstream run-document-server.sh)
# --------------------------------------------------------------------
JWT_ENABLED="${JWT_ENABLED:-true}"
JWT_HEADER="${JWT_HEADER:-Authorization}"
JWT_IN_BODY="${JWT_IN_BODY:-false}"

DB_TYPE="${DB_TYPE:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-eurooffice}"
DB_USER="${DB_USER:-eurooffice}"

AMQP_HOST="${AMQP_HOST:-localhost}"
AMQP_PORT="${AMQP_PORT:-5672}"
# Seconds to wait for the bundled RabbitMQ to report itself ready (start_rabbitmq).
AMQP_START_TIMEOUT="${AMQP_START_TIMEOUT:-60}"

REDIS_SERVER_HOST="${REDIS_SERVER_HOST:-localhost}"
REDIS_SERVER_PORT="${REDIS_SERVER_PORT:-6379}"

WOPI_ENABLED="${WOPI_ENABLED:-false}"
PLUGINS_ENABLED="${PLUGINS_ENABLED:-true}"
METRICS_ENABLED="${METRICS_ENABLED:-false}"
METRICS_HOST="${METRICS_HOST:-localhost}"
METRICS_PORT="${METRICS_PORT:-8125}"
METRICS_PREFIX="${METRICS_PREFIX:-ds.}"
GENERATE_FONTS="${GENERATE_FONTS:-true}"

MAX_FILE_SIZE="${MAX_FILE_SIZE:-104857600}"

NGINX_WORKER_PROCESSES="${NGINX_WORKER_PROCESSES:-1}"
NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-false}"
NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-100m}"
SSL_VERIFY_CLIENT="${SSL_VERIFY_CLIENT:-off}"
ONLYOFFICE_HTTPS_HSTS_ENABLED="${ONLYOFFICE_HTTPS_HSTS_ENABLED:-true}"
ONLYOFFICE_HTTPS_HSTS_MAXAGE="${ONLYOFFICE_HTTPS_HSTS_MAXAGE:-31536000}"

USE_UNAUTHORIZED_STORAGE="${USE_UNAUTHORIZED_STORAGE:-false}"
ALLOW_PRIVATE_IP_ADDRESS="${ALLOW_PRIVATE_IP_ADDRESS:-false}"
ALLOW_META_IP_ADDRESS="${ALLOW_META_IP_ADDRESS:-false}"

# --------------------------------------------------------------------
# Validate DB type (standalone image only supports postgres)
# --------------------------------------------------------------------
if [ "$DB_TYPE" != "postgres" ]; then
  echo "ERROR: only DB_TYPE=postgres is supported in the standalone image (got '$DB_TYPE'). Use the cluster image for other database types." >&2
  exit 1
fi

# --------------------------------------------------------------------
# Deprecation aliases — copy old var into upstream-named var if the new
# one is empty, and emit a warning.
# --------------------------------------------------------------------
deprecated_var() {
  old=$1
  new=$2
  old_val=$(eval "printf '%s' \"\${$old:-}\"")
  new_val=$(eval "printf '%s' \"\${$new:-}\"")
  if [ -n "$old_val" ]; then
    echo "WARNING: ${old} is deprecated, use ${new} instead" >&2
    if [ -z "$new_val" ]; then
      eval "$new=\"\$old_val\""
    fi
  fi
}
deprecated_var DB_PASSWORD DB_PWD

# --------------------------------------------------------------------
# Persisted secrets under $DATA_DIR/.private (volume-mountable).
# --------------------------------------------------------------------
mkdir -p "$PRIVATE_DIR"
chmod 700 "$PRIVATE_DIR" 2>/dev/null || true

random_str() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"
}

JWT_MESSAGE=""
JWT_SECRET_FILE="${PRIVATE_DIR}/jwt_secret"
if [ -z "${JWT_SECRET:-}" ]; then
  if [ -s "$JWT_SECRET_FILE" ]; then
    JWT_SECRET=$(cat "$JWT_SECRET_FILE")
  else
    JWT_SECRET=$(random_str 32)
    printf '%s' "$JWT_SECRET" > "$JWT_SECRET_FILE"
    chmod 600 "$JWT_SECRET_FILE"
    JWT_MESSAGE="JWT is enabled by default. A random secret was generated and stored in ${JWT_SECRET_FILE}. Mount ${DATA_DIR} as a volume to persist it across restarts."
  fi
fi
JWT_SECRET_INBOX="${JWT_SECRET_INBOX:-$JWT_SECRET}"
JWT_SECRET_OUTBOX="${JWT_SECRET_OUTBOX:-$JWT_SECRET}"
JWT_ENABLED_INBOX="${JWT_ENABLED_INBOX:-$JWT_ENABLED}"
JWT_ENABLED_OUTBOX="${JWT_ENABLED_OUTBOX:-$JWT_ENABLED}"
JWT_HEADER_INBOX="${JWT_HEADER_INBOX:-$JWT_HEADER}"
JWT_HEADER_OUTBOX="${JWT_HEADER_OUTBOX:-$JWT_HEADER}"

SECURE_LINK_SECRET_FILE="${PRIVATE_DIR}/secure_link_secret"
if [ -z "${SECURE_LINK_SECRET:-}" ]; then
  if [ -s "$SECURE_LINK_SECRET_FILE" ]; then
    SECURE_LINK_SECRET=$(cat "$SECURE_LINK_SECRET_FILE")
  else
    SECURE_LINK_SECRET=$(random_str 20)
    printf '%s' "$SECURE_LINK_SECRET" > "$SECURE_LINK_SECRET_FILE"
    chmod 600 "$SECURE_LINK_SECRET_FILE"
  fi
fi

# --------------------------------------------------------------------
# WOPI keypair (only generate/read when WOPI_ENABLED=true).
# --------------------------------------------------------------------
WOPI_PRIVATE_KEY="${DATA_DIR}/wopi_private.key"
WOPI_PUBLIC_KEY="${DATA_DIR}/wopi_public.key"
WOPI_MODULUS=""
WOPI_EXPONENT=""
WOPI_PRIVATE_KEY_DATA=""
WOPI_PUBLIC_KEY_DATA=""
if [ "$WOPI_ENABLED" = "true" ]; then
  if [ ! -f "$WOPI_PRIVATE_KEY" ]; then
    echo "Generating WOPI private key..."
    openssl genpkey -algorithm RSA -outform PEM -out "$WOPI_PRIVATE_KEY" >/dev/null 2>&1
  fi
  chmod 600 "$WOPI_PRIVATE_KEY" 2>/dev/null || true
  if [ ! -f "$WOPI_PUBLIC_KEY" ]; then
    echo "Generating WOPI public key..."
    openssl rsa -RSAPublicKey_out -in "$WOPI_PRIVATE_KEY" -outform "MS PUBLICKEYBLOB" -out "$WOPI_PUBLIC_KEY" >/dev/null 2>&1
  fi
  WOPI_MODULUS=$(openssl rsa -pubin -inform "MS PUBLICKEYBLOB" -modulus -noout -in "$WOPI_PUBLIC_KEY" | sed 's/Modulus=//' | xxd -r -p | openssl base64 -A)
  WOPI_EXPONENT=$(openssl rsa -pubin -inform "MS PUBLICKEYBLOB" -text -noout -in "$WOPI_PUBLIC_KEY" | grep -oP '(?<=Exponent: )\d+')
  WOPI_PRIVATE_KEY_DATA=$(cat "$WOPI_PRIVATE_KEY")
  WOPI_PUBLIC_KEY_DATA=$(openssl base64 -in "$WOPI_PUBLIC_KEY" -A)
fi

# --------------------------------------------------------------------
# Wait for remote services if not localhost.
# --------------------------------------------------------------------
waiting_for_connection() {
  host=$1; port=$2
  until nc -z -w 3 "$host" "$port" 2>/dev/null; do
    >&2 echo "Waiting for $host:$port..."
    sleep 1
  done
}

[ "$DB_HOST" != "localhost" ] && waiting_for_connection "$DB_HOST" "$DB_PORT"
[ "$REDIS_SERVER_HOST" != "localhost" ] && waiting_for_connection "$REDIS_SERVER_HOST" "$REDIS_SERVER_PORT"
if [ -n "${AMQP_URI:-}" ]; then
  : # caller picks their host; we don't parse the URI here
elif [ "$AMQP_HOST" != "localhost" ]; then
  waiting_for_connection "$AMQP_HOST" "$AMQP_PORT"
fi

# --------------------------------------------------------------------
# Build jq filter to update ${CONFIG_FILE}.
#
# Booleans are coerced via string comparison ($var == "true") so malformed
# input degrades to false rather than crashing jq.
# --------------------------------------------------------------------
jq_filter='.'

jq_set() { jq_filter="$jq_filter | $*"; }

# JWT enable
jq_set '.services.CoAuthoring.token.enable.browser         = ($jwtEnabled       == "true")'
jq_set '.services.CoAuthoring.token.enable.request.inbox   = ($jwtEnabledInbox  == "true")'
jq_set '.services.CoAuthoring.token.enable.request.outbox  = ($jwtEnabledOutbox == "true")'
jq_set '.services.CoAuthoring.token.inbox.inBody           = ($jwtInBody        == "true")'
jq_set '.services.CoAuthoring.token.outbox.inBody          = ($jwtInBody        == "true")'

# JWT secrets / headers
jq_set '.services.CoAuthoring.secret.browser.string = $jwtSecret'
jq_set '.services.CoAuthoring.secret.session.string = $jwtSecret'
jq_set '.services.CoAuthoring.secret.inbox.string   = $jwtSecretInbox'
jq_set '.services.CoAuthoring.secret.outbox.string  = $jwtSecretOutbox'
jq_set '.services.CoAuthoring.token.inbox.header    = $jwtHeaderInbox'
jq_set '.services.CoAuthoring.token.outbox.header   = $jwtHeaderOutbox'

# DB
jq_set '.services.CoAuthoring.sql.type   = $dbType'
jq_set '.services.CoAuthoring.sql.dbHost = $dbHost'
jq_set '.services.CoAuthoring.sql.dbPort = ($dbPort | tonumber? // $dbPort)'
jq_set '.services.CoAuthoring.sql.dbName = $dbName'
jq_set '.services.CoAuthoring.sql.dbUser = $dbUser'
[ -n "${DB_PWD:-}" ] && jq_set '.services.CoAuthoring.sql.dbPass = $dbPass'

# Redis
jq_set '.services.CoAuthoring.redis.host = $redisHost'
jq_set '.services.CoAuthoring.redis.port = ($redisPort | tonumber? // $redisPort)'
[ -n "${REDIS_SERVER_USER:-}" ] && jq_set '.services.CoAuthoring.redis.options.username = $redisUser'
[ -n "${REDIS_SERVER_PASS:-}" ] && jq_set '.services.CoAuthoring.redis.options.password = $redisPass'
[ -n "${REDIS_SERVER_DB:-}"   ] && jq_set '.services.CoAuthoring.redis.options.database = ($redisDb | tonumber? // $redisDb)'

# AMQP / RabbitMQ
if [ -n "${AMQP_URI:-}" ]; then
  jq_set '.rabbitmq.url = $amqpUri'
elif [ "$AMQP_HOST" != "localhost" ]; then
  jq_set '.rabbitmq.url = $amqpUri'
fi

# WOPI
jq_set '.wopi.enable = ($wopiEnabled == "true")'
if [ "$WOPI_ENABLED" = "true" ]; then
  jq_set '.wopi.privateKey    = $wopiPriv'
  jq_set '.wopi.privateKeyOld = $wopiPriv'
  jq_set '.wopi.publicKey     = $wopiPub'
  jq_set '.wopi.publicKeyOld  = $wopiPub'
  jq_set '.wopi.modulus       = $wopiMod'
  jq_set '.wopi.modulusOld    = $wopiMod'
  jq_set '.wopi.exponent      = ($wopiExp | tonumber? // $wopiExp)'
  jq_set '.wopi.exponentOld   = ($wopiExp | tonumber? // $wopiExp)'
fi

# Request filtering
[ "$USE_UNAUTHORIZED_STORAGE" = "true" ] && \
  jq_set '.services.CoAuthoring.requestDefaults.rejectUnauthorized = false'
[ "$ALLOW_PRIVATE_IP_ADDRESS" = "true" ] && \
  jq_set '.services.CoAuthoring["request-filtering-agent"].allowPrivateIPAddress = true'
[ "$ALLOW_META_IP_ADDRESS" = "true" ] && \
  jq_set '.services.CoAuthoring["request-filtering-agent"].allowMetaIPAddress = true'

# Upload size limit
jq_set '.services.CoAuthoring.server.limits_tempfile_upload = ($maxFileSize | tonumber? // $maxFileSize)'

# Metrics (statsd)
if [ "$METRICS_ENABLED" = "true" ]; then
  jq_set '.statsd.useMetrics = true'
  jq_set '.statsd.host       = $metricsHost'
  jq_set '.statsd.port       = ($metricsPort | tonumber? // $metricsPort)'
  jq_set '.statsd.prefix     = $metricsPrefix'
fi

# FileConverter limits (max upload/conversion size).
# Both are optional overrides; when unset the built-in default.json values apply.
# maxDownloadBytes: max size in bytes of the file the converter will download.
if [ -n "${FILECONVERTER_MAX_DOWNLOAD_BYTES:-}" ]; then
  case "$FILECONVERTER_MAX_DOWNLOAD_BYTES" in
    ''|*[!0-9]*) >&2 echo "WARN: FILECONVERTER_MAX_DOWNLOAD_BYTES is not a plain byte count, ignoring" ;;
    *) jq_set '.FileConverter.converter.maxDownloadBytes = ($maxDownloadBytes | tonumber)' ;;
  esac
fi
# inputLimits: max *uncompressed* size of the office file's zip (e.g. "500MB").
# Replaces the whole inputLimits array (node-config replaces arrays, not merges).
if [ -n "${FILECONVERTER_INPUT_LIMIT_UNCOMPRESSED:-}" ]; then
  jq_set '.FileConverter.converter.inputLimits = [
    { "type": "docx;dotx;docm;dotm",           "zip": { "uncompressed": $inputLimitUncompressed, "template": "*.xml" } },
    { "type": "xlsx;xltx;xlsm;xltm",           "zip": { "uncompressed": $inputLimitUncompressed, "template": "*.xml" } },
    { "type": "pptx;ppsx;potx;pptm;ppsm;potm", "zip": { "uncompressed": $inputLimitUncompressed, "template": "*.xml" } },
    { "type": "vsdx;vstx;vssx;vsdm;vstm;vssm", "zip": { "uncompressed": $inputLimitUncompressed, "template": "*.xml" } }
  ]'
fi

# Construct the AMQP URI value (may be unused if AMQP_HOST=localhost and AMQP_URI unset).
# AMQP_VHOST is a vhost name (e.g. "myvhost"); normalize to a leading slash before
# appending to the URI so values without it still produce a valid amqp:// URI.
AMQP_VHOST_PATH="${AMQP_VHOST:-/}"
case "$AMQP_VHOST_PATH" in
  /*) ;;
  *) AMQP_VHOST_PATH="/${AMQP_VHOST_PATH}" ;;
esac
AMQP_URI_VALUE="${AMQP_URI:-amqp://${AMQP_USER:-guest}:${AMQP_PWD:-guest}@${AMQP_HOST}:${AMQP_PORT}${AMQP_VHOST_PATH}}"

jq \
  --arg jwtEnabled       "$JWT_ENABLED" \
  --arg jwtEnabledInbox  "$JWT_ENABLED_INBOX" \
  --arg jwtEnabledOutbox "$JWT_ENABLED_OUTBOX" \
  --arg jwtInBody        "$JWT_IN_BODY" \
  --arg jwtSecret        "$JWT_SECRET" \
  --arg jwtSecretInbox   "$JWT_SECRET_INBOX" \
  --arg jwtSecretOutbox  "$JWT_SECRET_OUTBOX" \
  --arg jwtHeaderInbox   "$JWT_HEADER_INBOX" \
  --arg jwtHeaderOutbox  "$JWT_HEADER_OUTBOX" \
  --arg dbType           "$DB_TYPE" \
  --arg dbHost           "$DB_HOST" \
  --arg dbPort           "$DB_PORT" \
  --arg dbName           "$DB_NAME" \
  --arg dbUser           "$DB_USER" \
  --arg dbPass           "${DB_PWD:-}" \
  --arg redisHost        "$REDIS_SERVER_HOST" \
  --arg redisPort        "$REDIS_SERVER_PORT" \
  --arg redisUser        "${REDIS_SERVER_USER:-}" \
  --arg redisPass        "${REDIS_SERVER_PASS:-}" \
  --arg redisDb          "${REDIS_SERVER_DB:-}" \
  --arg amqpUri          "$AMQP_URI_VALUE" \
  --arg wopiEnabled      "$WOPI_ENABLED" \
  --arg wopiPriv         "$WOPI_PRIVATE_KEY_DATA" \
  --arg wopiPub          "$WOPI_PUBLIC_KEY_DATA" \
  --arg wopiMod          "$WOPI_MODULUS" \
  --arg wopiExp          "${WOPI_EXPONENT:-65537}" \
  --arg metricsHost      "$METRICS_HOST" \
  --arg metricsPort      "$METRICS_PORT" \
  --arg metricsPrefix    "$METRICS_PREFIX" \
  --arg maxFileSize      "$MAX_FILE_SIZE" \
  --arg maxDownloadBytes       "${FILECONVERTER_MAX_DOWNLOAD_BYTES:-}" \
  --arg inputLimitUncompressed "${FILECONVERTER_INPUT_LIMIT_UNCOMPRESSED:-}" \
  "$jq_filter" \
  "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

# --------------------------------------------------------------------
# log4js level
# --------------------------------------------------------------------
if [ -n "${DS_LOG_LEVEL:-}" ] && [ -f "$LOG4JS_CONFIG" ]; then
  jq --arg lvl "$DS_LOG_LEVEL" '.categories.default.level = $lvl' \
    "$LOG4JS_CONFIG" > "${LOG4JS_CONFIG}.tmp"
  mv "${LOG4JS_CONFIG}.tmp" "$LOG4JS_CONFIG"
fi

# --------------------------------------------------------------------
# nginx tuning + SSL
# --------------------------------------------------------------------
if [ -f "$NGINX_CONFIG_PATH" ]; then
  sed -i "s/^worker_processes.*/worker_processes ${NGINX_WORKER_PROCESSES};/" "$NGINX_CONFIG_PATH"
  if [ -n "${NGINX_WORKER_CONNECTIONS:-}" ]; then
    sed -i "s/worker_connections[[:space:]]\+[0-9]\+;/worker_connections ${NGINX_WORKER_CONNECTIONS};/" "$NGINX_CONFIG_PATH"
  fi
  if [ "$NGINX_ACCESS_LOG" = "true" ]; then
    mkdir -p "$EO_LOG"
    touch "${EO_LOG}/nginx.access.log"
    sed -ri "s|^\s*access_log\b.*;|access_log ${EO_LOG}/nginx.access.log;|" "$NGINX_CONFIG_PATH"
  else
    sed -ri "s|^\s*access_log\b.*;|access_log off;|" "$NGINX_CONFIG_PATH"
  fi
fi

if [ -f "$NGINX_DS_COMMON_CONF" ]; then
  sed -i "s/client_max_body_size[[:space:]]\+[^;]\+;/client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};/" "$NGINX_DS_COMMON_CONF"
fi

if [ -n "${SSL_CERTIFICATE_PATH:-}" ] && [ -n "${SSL_KEY_PATH:-}" ] \
   && [ -f "$SSL_CERTIFICATE_PATH" ] && [ -f "$SSL_KEY_PATH" ] \
   && [ -f "$NGINX_DS_SSL_TMPL" ]; then
  cp -f "$NGINX_DS_SSL_TMPL" "$NGINX_DS_CONF"
  sed -i "s,{{SSL_CERTIFICATE_PATH}},${SSL_CERTIFICATE_PATH}," "$NGINX_DS_CONF"
  sed -i "s,{{SSL_KEY_PATH}},${SSL_KEY_PATH}," "$NGINX_DS_CONF"
  sed -i "s,ssl_verify_client [^;]*;,ssl_verify_client ${SSL_VERIFY_CLIENT};," "$NGINX_DS_CONF"
  if [ -n "${SSL_DHPARAM_PATH:-}" ] && [ -r "$SSL_DHPARAM_PATH" ]; then
    sed -i "s,\(#* *\)\?\(ssl_dhparam \).*\(;\)$,\2${SSL_DHPARAM_PATH}\3," "$NGINX_DS_CONF"
  else
    sed -i "/ssl_dhparam/d" "$NGINX_DS_CONF"
  fi
  if [ "$ONLYOFFICE_HTTPS_HSTS_ENABLED" = "true" ]; then
    sed -i "s,\(max-age=\)[0-9]*\(;\)$,\1${ONLYOFFICE_HTTPS_HSTS_MAXAGE}\2," "$NGINX_DS_CONF"
  else
    sed -i "/max-age=/d" "$NGINX_DS_CONF"
  fi
  echo "SSL enabled with cert=${SSL_CERTIFICATE_PATH}"
fi

# Strip IPv6 listen directives if the kernel has no IPv6 support
if [ ! -f /proc/net/if_inet6 ] && [ -f "$NGINX_DS_CONF" ]; then
  sed -i '/listen[[:space:]]\+\[::[0-9]*\].\+/d' "$NGINX_DS_CONF"
fi

# Apply SECURE_LINK_SECRET via the bundled helper (also patches nginx ds.conf)
if command -v documentserver-update-securelink.sh >/dev/null 2>&1; then
  documentserver-update-securelink.sh -s "$SECURE_LINK_SECRET" -r false || true
fi

# --------------------------------------------------------------------
# Supervisor program toggles
# --------------------------------------------------------------------
enable_supervisor_program() {
  conf="${SUPERVISOR_CONF_DIR}/$1.conf"
  [ -f "$conf" ] && sed -i 's/^autostart=false$/autostart=true/' "$conf"
}

[ "${ADMINPANEL_ENABLED:-false}" = "true" ] && enable_supervisor_program ds-adminpanel
[ "${EXAMPLE_ENABLED:-false}"    = "true" ] && enable_supervisor_program ds-example
[ "$METRICS_ENABLED" = "true" ]              && enable_supervisor_program ds-metrics

# --------------------------------------------------------------------
# Example app local.json (kept from previous entrypoint).
# --------------------------------------------------------------------
if [ "${EXAMPLE_ENABLED:-false}" = "true" ] && [ -d "$EXAMPLE_CONF_DIR" ]; then
  jq -n \
    --arg secret      "$JWT_SECRET" \
    --arg header      "$JWT_HEADER" \
    --arg maxFileSize "$MAX_FILE_SIZE" \
    '{
      "server": {
        "siteUrl": "/",
        "exampleUrl": "http://localhost/example/",
        "maxFileSize": ($maxFileSize | tonumber? // $maxFileSize),
        "token": {
          "enable": true,
          "secret": $secret,
          "authorizationHeader": $header
        }
      }
    }' > "$EXAMPLE_LOCAL"
fi

# --------------------------------------------------------------------
# Welcome page rewrite (preserved from previous entrypoint).
# --------------------------------------------------------------------
update_welcome_page() {
  WELCOME_PAGE="${EO_ROOT}-example/welcome/docker.html"
  EXAMPLE_DISABLED_PAGE="${EO_ROOT}-example/welcome/example-disabled.html"

  sed 's/linux/docker/' -i /etc/nginx/includes/ds-example.conf

  [ -f "$EXAMPLE_DISABLED_PAGE" ] && \
    sed -i 's|sudo systemctl start ds-example|sudo docker exec $(sudo docker ps -q) supervisorctl start ds:example|g' \
        "$EXAMPLE_DISABLED_PAGE"

  if [ -e "$WELCOME_PAGE" ]; then
    DOCKER_CONTAINER_ID=$(basename "$(cat /proc/1/cpuset 2>/dev/null)")
    if [ "${#DOCKER_CONTAINER_ID}" -lt 12 ]; then
      DOCKER_CONTAINER_ID=$(hostname)
    fi
    if [ "${#DOCKER_CONTAINER_ID}" -ge 12 ]; then
      if command -v docker > /dev/null 2>&1; then
        DOCKER_CONTAINER_NAME=$(docker inspect --format="{{.Name}}" "$DOCKER_CONTAINER_ID" | sed 's|^/||')
        sed -i "s|\$(sudo docker ps -q)|${DOCKER_CONTAINER_NAME}|g" \
            "$WELCOME_PAGE" "$EXAMPLE_DISABLED_PAGE"
      else
        DOCKER_CONTAINER_SHORT=$(echo "$DOCKER_CONTAINER_ID" | cut -c1-12)
        sed -i "s|\$(sudo docker ps -q)|${DOCKER_CONTAINER_SHORT}|g" \
            "$WELCOME_PAGE" "$EXAMPLE_DISABLED_PAGE"
      fi
    fi
  fi
}
update_welcome_page

# Symlink /config -> ${EO_CONF} for tools that expect it
ln -sf ${EO_CONF} /config 2>/dev/null || true

# Ensure api.js template (required by documentserver-flush-cache.sh)
API_TPL="${EO_ROOT}/web-apps/apps/api/documents/api.js.tpl"
if [ ! -f "$API_TPL" ] && [ -f "${EO_ROOT}/web-apps/apps/api/documents/api.js" ]; then
  cp "${EO_ROOT}/web-apps/apps/api/documents/api.js" "$API_TPL"
fi

# --------------------------------------------------------------------
# Start bundled services only when the corresponding host points at
# localhost. When an external host is configured, we already waited
# for it above.
# --------------------------------------------------------------------
[ "$DB_HOST"            = "localhost" ] && service postgresql start

# --------------------------------------------------------------------
# Apply Postgres schema on first boot (idempotent).
#
# The .deb postinst applies createdb.sql at *image build* time, so the
# bundled cluster already has the schema. This step exists for the cases
# build-time application can't cover: an external DB_HOST, or a fresh
# volume mounted over the Postgres datadir — either leaves docservice
# failing with `DB table "task_result" does not exist` and never binding
# to :8000, so nginx serves 502 on /healthcheck.
#
# Runs here, right after Postgres starts and before nginx, so the 502
# window is as small as possible.
#
# A failure here is not fatal to boot (see the `||` at the call site
# below) — the container still starts, just possibly 502ing until the
# schema is applied out of band, rather than being taken down by set -e.
# --------------------------------------------------------------------
ensure_db_schema() {
  schema_file="${EO_ROOT}/server/schema/postgresql/createdb.sql"
  [ -f "$schema_file" ] || return 0

  # DB_PWD is usually unset: the jq rewrite above only touches
  # sql.dbPass when DB_PWD is non-empty (see :200), so in the default
  # (stock-image) configuration the real password is whatever postinst
  # baked into $CONFIG_FILE at build time. Fall back to reading it from
  # there rather than authenticating with an empty password.
  db_pwd="${DB_PWD:-$(jq -r '.services.CoAuthoring.sql.dbPass // empty' "$CONFIG_FILE" 2>/dev/null || true)}"

  db_psql() {
    PGPASSWORD="$db_pwd" psql -w \
      -v ON_ERROR_STOP=1 \
      -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$@"
  }

  tries=0
  until db_psql -tAc 'SELECT 1' >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 60 ]; then
      echo "ERROR: could not connect to Postgres at ${DB_HOST}:${DB_PORT} as ${DB_USER}/${DB_NAME} after 60s" >&2
      # Re-run once unsuppressed so psql's own message (auth failure vs.
      # unreachable host) reaches the log instead of our generic one.
      db_psql -tAc 'SELECT 1' >&2 || true
      unset -f db_psql
      return 1
    fi
    sleep 1
  done

  # Probe a table that createdb.sql creates. Skip if already populated.
  if [ "$(db_psql -tAc "SELECT to_regclass('public.task_result') IS NOT NULL" 2>/dev/null)" = "t" ]; then
    echo "Postgres schema already present, skipping."
    unset -f db_psql
    return 0
  fi

  echo "Applying Postgres schema from ${schema_file}..."
  db_psql -f "$schema_file"
  rc=$?
  unset -f db_psql
  return "$rc"
}
ensure_db_schema || echo "WARNING: Postgres schema bootstrap failed; docservice may 502 until it is applied." >&2

# --------------------------------------------------------------------
# Start the bundled RabbitMQ.
#
# Deliberately not `service rabbitmq-server start`: that init script goes
# through `start-stop-daemon --background`, which wedges for many minutes on
# hosts whose Docker daemon hands containers a huge RLIMIT_NOFILE (some
# distro-packaged daemons default it to 1073741816). The entrypoint then never
# reaches nginx/supervisord and the container looks hung with no diagnostic
# (#326). A direct detached start is unaffected, and pairing it with an
# explicit readiness wait means a real startup failure is reported here
# instead of surfacing later as unexplained 502s from docservice.
#
# Not fatal to boot, like the schema bootstrap above: the container stays up
# and inspectable, and /healthcheck fails until AMQP is reachable.
# --------------------------------------------------------------------
start_rabbitmq() {
  echo "Starting RabbitMQ Messaging Server rabbitmq-server"
  runuser -u rabbitmq -- rabbitmq-server -detached || return 1

  # `-detached` returns before the node registers with epmd, and until it does
  # await_startup fails outright instead of waiting, so poll it.
  deadline=$(( $(date +%s) + AMQP_START_TIMEOUT ))
  until runuser -u rabbitmq -- rabbitmqctl -q await_startup --timeout 5 >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      # Re-run unsuppressed so rabbitmqctl's own diagnostics reach the log.
      runuser -u rabbitmq -- rabbitmqctl await_startup --timeout 5 >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "   ...done."
}

if [ "$AMQP_HOST" = "localhost" ] && [ -z "${AMQP_URI:-}" ]; then
  start_rabbitmq \
    || echo "ERROR: RabbitMQ did not become ready within ${AMQP_START_TIMEOUT}s; docservice will fail to connect." >&2
fi
[ "$REDIS_SERVER_HOST"  = "localhost" ] && service redis-server start
service nginx start

# --------------------------------------------------------------------
# Fonts + plugins (background where appropriate).
# --------------------------------------------------------------------
if [ "$GENERATE_FONTS" = "true" ] && command -v /usr/bin/documentserver-generate-allfonts.sh >/dev/null 2>&1; then
  /usr/bin/documentserver-generate-allfonts.sh
fi

if [ "$PLUGINS_ENABLED" = "true" ] && command -v documentserver-pluginsmanager.sh >/dev/null 2>&1 \
   && [ -f "${EO_ROOT}/sdkjs-plugins/plugin-list-default.json" ]; then
  (
    documentserver-pluginsmanager.sh -r false \
      --update="${EO_ROOT}/sdkjs-plugins/plugin-list-default.json" >/dev/null
    echo "[pluginsmanager] Plugins initialization finished"
  ) &
fi

# --------------------------------------------------------------------
# Final messages and hand-off to supervisord.
# --------------------------------------------------------------------
[ -n "$JWT_MESSAGE" ] && echo "$JWT_MESSAGE"

# Hand off to supervisord under tini. tini becomes PID 1 and acts as the init
# zombie-reaper: it silently reaps orphaned children of the bundled daemons
# (postgres, redis, nginx, rabbitmq) and of the node services. Without it,
# supervisord would run as PID 1 and log every reaped orphan as a noisy
# "reaped unknown pid" INFO message.
exec /usr/bin/tini -- /usr/bin/supervisord
