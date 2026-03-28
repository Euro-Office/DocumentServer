#!/bin/sh

update_welcome_page() {
    WELCOME_PAGE="/var/www/onlyoffice/documentserver-example/welcome/docker.html"
    EXAMPLE_DISABLED_PAGE="/var/www/onlyoffice/documentserver-example/welcome/example-disabled.html"

    # Replace systemctl placeholder (set at build time) with docker+supervisorctl equivalent
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

# Create symlink for /config -> /etc/onlyoffice/documentserver so tools can find config
ln -sf /etc/onlyoffice/documentserver /config 2>/dev/null || true

service postgresql start
runuser -u rabbitmq -- rabbitmq-server -detached
service redis-server start
service nginx start

# Ensure the api.js.tpl template exists (required by documentserver-flush-cache.sh)
API_TPL="/var/www/onlyoffice/documentserver/web-apps/apps/api/documents/api.js.tpl"
if [ ! -f "$API_TPL" ] && [ -f "/var/www/onlyoffice/documentserver/web-apps/apps/api/documents/api.js" ]; then
    cp /var/www/onlyoffice/documentserver/web-apps/apps/api/documents/api.js "$API_TPL"
fi

# Generate all fonts (AllFonts.js, font_selection.bin, presentation themes)
/usr/bin/documentserver-generate-allfonts.sh



CONFIG_FILE="$EO_CONF/local.json"

jq_filter='.'

if [ -n "$JWT_SECRET" ]; then
  jq_filter="$jq_filter | .services.CoAuthoring.secret.browser.string = \$jwtSecret"
  jq_filter="$jq_filter | .services.CoAuthoring.secret.inbox.string   = \$jwtSecret"
  jq_filter="$jq_filter | .services.CoAuthoring.secret.outbox.string  = \$jwtSecret"
  jq_filter="$jq_filter | .services.CoAuthoring.secret.session.string = \$jwtSecret"
fi

[ -n "$DB_PASSWORD" ] && \
  jq_filter="$jq_filter | .services.CoAuthoring.sql.dbPass = \$dbPassword"

[ -n "$USE_UNAUTHORIZED_STORAGE" ] && \
  jq_filter="$jq_filter | .services.CoAuthoring.requestDefaults.rejectUnauthorized = false"

[ -n "$ALLOW_PRIVATE_IP_ADDRESS" ] && \
  jq_filter="$jq_filter | .services.CoAuthoring[\"request-filtering-agent\"].allowPrivateIPAddress = true"

[ -n "$ALLOW_META_IP_ADDRESS" ] && \
  jq_filter="$jq_filter | .services.CoAuthoring[\"request-filtering-agent\"].allowMetaIPAddress = true"

if [ "$jq_filter" != "." ]; then
  jq \
    --arg jwtSecret "$JWT_SECRET" \
    --arg dbPassword "$DB_PASSWORD" \
    "$jq_filter" \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"

  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
fi

update_welcome_page

enable_supervisor_program() {
    sed -i 's/^autostart=false$/autostart=true/' "/etc/supervisor/conf.d/$1.conf"
}

[ "${ADMINPANEL_ENABLED:-false}" = "true" ] && enable_supervisor_program ds-adminpanel
[ "${EXAMPLE_ENABLED:-false}" = "true" ]    && enable_supervisor_program ds-example

/usr/bin/supervisord
