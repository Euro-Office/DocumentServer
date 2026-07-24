# ==============================================================================
# MODULE DOCKERFILE
# This file is not meant to be built standalone. It is consumed by the 
# docker-bake.hcl files in the parent monorepos.
#
# REQUIRED CONTEXTS:
# - packages: final packages of documentserver
# ==============================================================================

#### FINAL UBUNTU ####
FROM ubuntu:24.04 AS finalubuntu
ARG PRODUCT_VERSION
ARG BUILD_NUMBER
ARG BUILD_ROOT=/package

ARG COMPANY_NAME_LOW
ARG PRODUCT_NAME_LOW

ARG EO_ROOT=/var/www/${COMPANY_NAME_LOW}/${PRODUCT_NAME_LOW}
ARG EO_LOG=/var/log/${COMPANY_NAME_LOW}/${PRODUCT_NAME_LOW}
ARG EO_CONF=/etc/${COMPANY_NAME_LOW}/${PRODUCT_NAME_LOW}

# Avoid interactive prompts during package install
ARG DEBIAN_FRONTEND=noninteractive

ENV EO_ROOT=${EO_ROOT}
ENV EO_LOG=${EO_LOG}
ENV EO_CONF=${EO_CONF}
ENV COMPANY_NAME_LOW=${COMPANY_NAME_LOW}
ENV PRODUCT_NAME_LOW=${PRODUCT_NAME_LOW}

RUN apt-get update && \
    ACCEPT_EULA=Y apt-get install -yq --no-install-recommends \
        postgresql postgresql-client redis-server rabbitmq-server \
        nginx sudo gdb nginx-extras supervisor jq util-linux \
        netcat-openbsd xxd openssl && \
    rm -rf /var/lib/apt/lists/*

# Create the 'ds' user that is required by OnlyOffice scripts
#RUN useradd -r -s /bin/false ds || true

# --- install ${COMPANY_NAME_LOW} .deb package
ARG TARGETARCH
COPY --from=packages / /tmp/
RUN apt-get update && \
    (pg_createcluster 16 main || true) && \
    service postgresql start && \
    service rabbitmq-server start && \
    sudo -u postgres psql -c "CREATE USER eurooffice WITH password 'eurooffice';" && \
    sudo -u postgres psql -c "CREATE DATABASE eurooffice OWNER eurooffice;" && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-type string postgres" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-host string localhost" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-port string 5432" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-user string eurooffice" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-pwd password eurooffice" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-name string eurooffice" | debconf-set-selections && \
    DS_DOCKER_INSTALLATION=true apt-get install -yq /tmp/${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW}_${PRODUCT_VERSION}-${BUILD_NUMBER}_${TARGETARCH}.deb && \
    rm -rf /var/lib/apt/lists/* /tmp/*
    #sudo -u postgres bash -c "PGPASSWORD=eurooffice psql -h localhost -U eurooffice -d eurooffice -f ${EO_ROOT}/server/schema/postgresql/createdb.sql"

# --- Final setup ---
COPY build/configs/standalone/supervisor/ /etc/supervisor/conf.d/
COPY --chmod=755 build/scripts/standalone/entrypoint.sh /entrypoint.sh

# Give the 'ds' service user a writable HOME. supervisord runs as root and does
# not reset HOME when dropping to user=ds, so without this the node services
# inherit HOME=/root and fail to write their cache (e.g. sharp/pkg extracting
# native modules to ~/.cache), disabling image processing. HOME is set per
# program in the supervisor confs; this just ensures the directory exists.
RUN mkdir -p /home/ds && chown ds:ds /home/ds

#RUN mkdir -p ${EO_LOG}/docservice ${EO_LOG}/converter \
#             ${EO_LOG}/adminpanel ${EO_LOG}/metrics

#RUN mkdir -p ${EO_ROOT}/documentserver-example/files

#RUN mkdir -p ${EO_ROOT}/server/Common/config && \
#    echo '{}' > ${EO_ROOT}/server/Common/config/runtime.json

#RUN mkdir -p /var/lib/${COMPANY_NAME_LOW} #&& \
#    chown -R ds:ds /var/www/${COMPANY_NAME_LOW} /var/lib/${COMPANY_NAME_LOW} /var/log/${COMPANY_NAME_LOW}

RUN /usr/bin/documentserver-flush-cache.sh -r false

ENTRYPOINT ["/entrypoint.sh"]