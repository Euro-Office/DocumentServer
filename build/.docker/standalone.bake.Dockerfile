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
        netcat-openbsd xxd openssl tini && \
    rm -rf /var/lib/apt/lists/*

# Create the 'ds' user that is required by OnlyOffice scripts
#RUN useradd -r -s /bin/false ds || true

# --- install ${COMPANY_NAME_LOW} .deb package
# RabbitMQ is started directly rather than via `service rabbitmq-server start`
# for the same reason as in entrypoint.sh: the init script's
# `start-stop-daemon --background` wedges under a huge RLIMIT_NOFILE, which
# would hang the build on hosts that hand containers one (#326). Its mnesia
# database is dropped again afterwards -- the node name follows the container
# hostname, so `rabbit@buildkitsandbox` is never read at runtime.
#
# The readiness wait is a poll for the same reason as start_rabbitmq() in
# entrypoint.sh: `-detached` returns before the node registers with epmd, and
# until it does `rabbitmqctl await_startup` fails outright instead of waiting
# out its timeout. A single call therefore lost the race on three of four CI
# builders, exiting 69 after seven seconds with "epmd reports: node 'rabbit'
# not running at all". On timeout the wait is repeated unsuppressed so
# rabbitmqctl's own diagnostics reach the build log before the build fails.
ARG TARGETARCH
COPY --from=packages / /tmp/
RUN apt-get update && \
    (pg_createcluster 16 main || true) && \
    service postgresql start && \
    runuser -u rabbitmq -- rabbitmq-server -detached && \
    ( timeout 60 runuser -u rabbitmq -- sh -c \
        'until rabbitmqctl -q await_startup --timeout 5 >/dev/null 2>&1; do sleep 1; done' \
      || runuser -u rabbitmq -- rabbitmqctl await_startup --timeout 5 ) && \
    sudo -u postgres psql -c "CREATE USER eurooffice WITH password 'eurooffice';" && \
    sudo -u postgres psql -c "CREATE DATABASE eurooffice OWNER eurooffice;" && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-type string postgres" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-host string localhost" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-port string 5432" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-user string eurooffice" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-pwd password eurooffice" | debconf-set-selections && \
    echo "${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW} ds/db-name string eurooffice" | debconf-set-selections && \
    DS_DOCKER_INSTALLATION=true apt-get install -yq /tmp/${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW}_${PRODUCT_VERSION}-${BUILD_NUMBER}_${TARGETARCH}.deb && \
    (runuser -u rabbitmq -- rabbitmqctl shutdown || true) && \
    rm -rf /var/lib/rabbitmq/mnesia /var/lib/apt/lists/* /tmp/*
# The .deb postinst applies server/schema/postgresql/createdb.sql at build time
# (postinst.m4: install_db is not gated on DS_DOCKER_INSTALLATION), which is why the
# explicit psql call that used to live here was redundant. It does not help when the
# Postgres datadir is a fresh volume or DB_HOST points at an external server, so
# entrypoint.sh re-applies it idempotently at boot (ensure_db_schema).

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