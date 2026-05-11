# ==============================================================================
# MODULE DOCKERFILE
# This file is not meant to be built standalone. It is consumed by the 
# docker-bake.hcl files in the parent monorepos.
#
# REQUIRED CONTEXTS:
# - server: builds from server repo
# - core: builds from core repo
# - web-apps: builds from web-apps repo
# - sdkjs: builds from sdkjs repo
# - example: builds from example repo
# ==============================================================================

#### FINAL UBUNTU ####
FROM ubuntu:24.04 AS finalubuntu
ARG PRODUCT_VERSION
ARG BUILD_ROOT=/package

ARG EO_ROOT=/var/www/onlyoffice/documentserver
ARG EO_LOG=/var/log/onlyoffice/documentserver
ARG EO_CONF=/etc/onlyoffice/documentserver

ENV EO_ROOT=${EO_ROOT}
ENV EO_LOG=${EO_LOG}
ENV EO_CONF=${EO_CONF}

RUN apt-get -y update && \
    ACCEPT_EULA=Y apt-get -yq install \
        postgresql postgresql-client redis-server rabbitmq-server \
        nginx sudo gdb nginx-extras supervisor jq util-linux && \
    rm -rf /var/lib/apt/lists/*

# Create the 'ds' user that is required by OnlyOffice scripts
RUN useradd -r -s /bin/false ds || true

COPY build/configs/postgres ${EO_ROOT}/server/schema/postgresql

# Create default PostgreSQL cluster (required before starting the service)
RUN pg_createcluster 16 main || true

RUN service postgresql start && \
    sudo -u postgres psql -c "CREATE USER onlyoffice WITH password 'onlyoffice';" && \
    sudo -u postgres psql -c "CREATE DATABASE onlyoffice OWNER onlyoffice;" && \
    sudo -u postgres bash -c "PGPASSWORD=onlyoffice psql -h localhost -U onlyoffice -d onlyoffice -f ${EO_ROOT}/server/schema/postgresql/createdb.sql"

RUN rm -f /etc/nginx/sites-enabled/default && \
    mkdir -p ${EO_LOG}/docservice ${EO_LOG}/converter \
             ${EO_LOG}/adminpanel ${EO_LOG}/metrics \
             ${EO_ROOT}/sdkjs-plugins ${EO_ROOT}/fonts \
             ${EO_ROOT}/server/FileConverter/lib ${EO_ROOT}/server/tools && \
    touch ${EO_LOG}/nginx.error.log

# --- Static content from build context (rarely changes) ---
COPY dictionaries ${EO_ROOT}/dictionaries
COPY document-templates ${EO_ROOT}/document-templates
COPY core-fonts ${EO_ROOT}/core-fonts

# --- Config files and scripts (rarely change) ---
COPY build/configs/onlyoffice/default.json            ${EO_CONF}/default.json
COPY build/configs/onlyoffice/development-linux.json  ${EO_CONF}/development-linux.json
COPY build/configs/onlyoffice/local.json              ${EO_CONF}/local.json
COPY build/configs/onlyoffice/log4js/development.json ${EO_CONF}/log4js/development.json

RUN mkdir -p /var/www/onlyoffice/documentserver && \
    cp ${EO_CONF}/log4js/development.json /var/www/onlyoffice/documentserver/log4js.json

COPY build/configs/metrics/config/config.js ${EO_ROOT}/server/Metrics/config/config.js
COPY build/configs/nginx/conf.d /etc/nginx/conf.d/
COPY build/configs/nginx/includes /etc/nginx/includes/
RUN sed -i "s/__PRODUCT_VERSION__/${PRODUCT_VERSION}/g" /etc/nginx/includes/ds-docservice.conf

COPY build/configs/core/DoctRenderer.config ${EO_ROOT}/server/FileConverter/bin/DoctRenderer.config
COPY build/configs/supervisor/ /etc/supervisor/conf.d/
COPY --chmod=755 build/scripts/documentserver-flush-cache.sh /usr/bin/documentserver-flush-cache.sh
COPY --chmod=755 build/scripts/documentserver-generate-allfonts.sh /usr/bin/documentserver-generate-allfonts.sh
COPY --chmod=755 build/scripts/entrypoint.sh /entrypoint.sh

# --- Build stage outputs (change with code) ---
COPY --from=sdkjs ${BUILD_ROOT} ${EO_ROOT}/
COPY --from=web-apps ${BUILD_ROOT} ${EO_ROOT}/

COPY --from=core ${BUILD_ROOT}/bin/ ${EO_ROOT}/server/FileConverter/bin/
COPY --from=core ${BUILD_ROOT}/tools/ ${EO_ROOT}/server/tools/
COPY --from=core ${BUILD_ROOT}/*.so* ${EO_ROOT}/server/FileConverter/lib/
COPY --from=core ${BUILD_ROOT}/tools/*.so* ${EO_ROOT}/server/tools/

COPY --from=server ${BUILD_ROOT}/docservice    ${EO_ROOT}/server/DocService/docservice
COPY --from=server ${BUILD_ROOT}/fileconverter ${EO_ROOT}/server/FileConverter/converter
COPY --from=server ${BUILD_ROOT}/metrics       ${EO_ROOT}/server/Metrics/metrics
COPY --from=server ${BUILD_ROOT}/adminpanel    ${EO_ROOT}/server/AdminPanel/server/adminpanel
COPY --from=server ${BUILD_ROOT}/build         ${EO_ROOT}/server/AdminPanel/client/build

COPY --from=example /example/example /var/www/onlyoffice/documentserver-example/example
RUN mkdir -p /var/www/onlyoffice/documentserver-example/files
COPY --from=example /example/config/* /etc/onlyoffice/documentserver-example/

COPY document-server-package/common/documentserver-example/welcome /var/www/onlyoffice/documentserver-example/welcome
RUN YEAR=$(date +"%Y") && \
    sed -i "s|{{OFFICIAL_PRODUCT_NAME}}|Community Edition|g" /var/www/onlyoffice/documentserver-example/welcome/*.html && \
    find /var/www/onlyoffice/documentserver-example/welcome -depth -type f \
         -exec sed -i "s_{{year}}_${YEAR}_g" {} \; && \
    sed -i "s|{{EXAMPLE_DISABLED_COMMANDS}}|sudo systemctl start ds-example|g" \
           /var/www/onlyoffice/documentserver-example/welcome/example-disabled.html && \
    rm -f /var/www/onlyoffice/documentserver-example/welcome/admin-disabled.html && \
    sed -i '/<!-- BEGIN ADMIN PANEL SECTION -->/,/<!-- END ADMIN PANEL SECTION -->/d' \
           /var/www/onlyoffice/documentserver-example/welcome/docker.html \
           /var/www/onlyoffice/documentserver-example/welcome/linux.html \
           /var/www/onlyoffice/documentserver-example/welcome/linux-rpm.html \
           /var/www/onlyoffice/documentserver-example/welcome/win.html

# --- Final setup ---
RUN mkdir -p ${EO_ROOT}/server/Common/config && \
    echo '{}' > ${EO_ROOT}/server/Common/config/runtime.json

RUN mkdir -p /var/lib/onlyoffice && \
    chown -R ds:ds /var/www/onlyoffice /var/lib/onlyoffice /var/log/onlyoffice

RUN /usr/bin/documentserver-flush-cache.sh -r false

ENTRYPOINT ["/entrypoint.sh"]
