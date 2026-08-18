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

# Pin the UIDs/GIDs of every account that ends up owning persisted state.
#
# Debian allocates system UIDs in package-configuration order, which makes them
# a side effect of the package set: adding --no-install-recommends below for
# v9.3.3 dropped dbus's `messagebus` account from this layer and slid postgres
# from 103 to 102, so Postgres volumes written by v9.3.2 suddenly had a datadir
# owned by what is now `rabbitmq` and the server refused to start (#314).
#
# These are the values v9.3.3 shipped, so pinning them changes nothing for
# existing volumes; entrypoint.sh repairs the ones written before that. The
# adduser/useradd calls in the package postinst scripts (and in the .deb's own
# postinst, for `ds`) are no-ops when the account already exists, so the
# packages adopt these accounts as they are.
RUN groupadd -r -g 103 redis    && useradd -r -u 101 -g redis    -d /var/lib/redis      -s /usr/sbin/nologin redis    && \
    groupadd -r -g 104 postgres && useradd -r -u 102 -g postgres -d /var/lib/postgresql -s /bin/bash        postgres && \
    groupadd -r -g 105 rabbitmq && useradd -r -u 103 -g rabbitmq -d /var/lib/rabbitmq   -s /usr/sbin/nologin rabbitmq && \
    groupadd -r -g 107 ds       && useradd -r -u 105 -g ds       -d ${EO_ROOT}          -s /usr/sbin/nologin ds

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