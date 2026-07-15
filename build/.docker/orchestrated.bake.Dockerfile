ARG POSTGRES_VERSION="15"
ARG MYSQL_VERSION="latest"
ARG MARIADB_VERSION="latest"

FROM fedora:43 AS ds-base

    LABEL maintainer Euro-Office

    ARG COMPANY_NAME_LOW=euro-office
    ARG DS_VERSION_HASH
    ENV COMPANY_NAME_LOW=$COMPANY_NAME_LOW \
        APPLICATION_NAME=$COMPANY_NAME_LOW \
        DS_VERSION_HASH=$DS_VERSION_HASH \
        NODE_ENV=production-linux \
        NODE_CONFIG_DIR=/etc/$COMPANY_NAME_LOW/documentserver \
        PKG_NATIVE_CACHE_PATH=/tmp/.cache

    RUN dnf -y updateinfo list --security && \
        dnf update --security -y && \
        dnf install sudo \
                    python3-pip \
                    findutils \
                    shadow-utils \
                    procps-ng \
                    tar \
                    unzip \
                    libaio \
                    libnsl \
                    nano \
                    gettext \
                    nginx \
                    httpd-tools \
                    wget -y && \
        pip3 install --no-cache-dir redis && \
        wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_$(uname -m) && \
        chmod +x /usr/local/bin/dumb-init && \
        mkdir -p /oracle/instantclient /opt/oracle /home/ds /etc/nginx/includes && \
        wget -O /oracle/basic.zip https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip && \
        unzip /oracle/basic.zip -d /oracle/instantclient && \
        mv /oracle/instantclient/instantclient_23_7 /opt/oracle/instantclient_23_7 && \
        rm -rf /oracle && \
        groupadd --system --gid 101 ds && \
        useradd --system -g ds --no-create-home --shell /sbin/nologin --uid 101 ds && \
        chown -R ds:ds /home/ds && \
        dnf clean all && \
        rm -rf /var/cache/dnf && \
        rm -f /var/log/*log

FROM ds-base AS ds-service
    ARG TARGETARCH
    ARG DS_VERSION_HASH
    ARG PRODUCT_EDITION=
    ARG RELEASE_VERSION
    ARG PRODUCT_VERSION
    ARG PRODUCT_NAME_LOW
    ARG BUILD_NUMBER
    ENV TARGETARCH=$TARGETARCH \
        DS_VERSION_HASH=$DS_VERSION_HASH \
        COMPANY_NAME_LOW=$COMPANY_NAME_LOW \
        PRODUCT_NAME_LOW=$PRODUCT_NAME_LOW \
        BUILD_NUMBER=$BUILD_NUMBER
    WORKDIR /ds

    COPY --from=packages / /tmp/

    RUN dnf -y install cabextract xorg-x11-font-utils fontconfig && \
        rpm -ivh --nodigest \
        https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm && \
        TARGETARCH=$(echo $TARGETARCH | sed "s/"$TARGETARCH"/"$(uname -m)"/g") && \
        rpm -ivh /tmp/${COMPANY_NAME_LOW}-${PRODUCT_NAME_LOW}-${PRODUCT_VERSION}-${BUILD_NUMBER}.${TARGETARCH}.rpm --noscripts --nodeps && \
        mkdir -p /var/www/$COMPANY_NAME_LOW/documentserver/core-fonts/msttcore && \
        cp -vt \
            /var/www/$COMPANY_NAME_LOW/documentserver/core-fonts/msttcore \
            /usr/share/fonts/msttcore/*.ttf && \
        chmod a+r /etc/$COMPANY_NAME_LOW/documentserver*/*.json && \
        chmod a+r /etc/$COMPANY_NAME_LOW/documentserver/log4js/*.json
    COPY --chown=ds:ds \
        build/configs/orchestrated/nginx/includes/http-common.conf \
        build/configs/orchestrated/nginx/includes/http-upstream.conf \
        /etc/$COMPANY_NAME_LOW/documentserver/nginx/includes/
    #COPY --chown=ds:ds \
    #    fonts/ \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/core-fonts/custom/
    #COPY --chown=ds:ds \
    #    plugins/ \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs-plugins/
    #COPY --chown=ds:ds \
    #    dictionaries/ \
    #    /var/www/onlyoffice/documentserver/dictionaries/
    RUN documentserver-generate-allfonts.sh true && \
        #python3 /var/www/onlyoffice/documentserver/server/dictionaries/update.py && \
        documentserver-flush-cache.sh -h $DS_VERSION_HASH -r false
    #    documentserver-pluginsmanager.sh -r false \
    #    --update=\"/var/www/$COMPANY_NAME_LOW/documentserver/sdkjs-plugins/plugin-list-default.json\"

# --------------------------------------------------------------------------------
# This image contains ALL runtime components (DocService, Converter, Adminpanel and
# Proxy) and is intended to be reused by
# multiple Kubernetes Deployments
#
# Model:
#   - Select the Docs service via container args (docservice|converter|adminpanel)
#   - For the Proxy Deployment, override ONLY `command` in the
#     PodSpec to run proxy-docker-entrypoint.sh directly
# --------------------------------------------------------------------------------

FROM ds-base AS docs
    ENV DOCSERVICE_HOST_PORT=localhost:8000 \
        ADMINPANEL_HOST_PORT=localhost:9000 \
        EXAMPLE_HOST_PORT=localhost:3000 \
        NGINX_ACCESS_LOG=off \
        NGINX_GZIP_PROXIED=off \
        NGINX_CLIENT_MAX_BODY_SIZE=100m \
        NGINX_WORKER_CONNECTIONS=4096 \
        NGINX_WORKER_PROCESSES=1
    COPY --chown=ds:ds build/configs/orchestrated/nginx/nginx.conf /etc/nginx/nginx.conf
    COPY --chown=ds:ds --from=ds-service \
        /usr/bin/documentserver-generate-allfonts.sh \
        #/usr/bin/documentserver-pluginsmanager.sh \
        /usr/local/bin/
    #COPY --from=ds-service \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/server/dictionaries/update.py \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/server/dictionaries/update.py
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/tools/allfontsgen \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/tools/allfontsgen
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/tools/allthemesgen \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/tools/allthemesgen
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/tools/pluginsmanager \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/tools/pluginsmanager
    COPY --chown=ds:ds --chmod=644 --from=ds-service \
        /etc/$COMPANY_NAME_LOW/documentserver/nginx/ds.conf \
        /etc/nginx/conf.d/
    COPY --chown=ds:ds --chmod=644 --from=ds-service \
        /etc/$COMPANY_NAME_LOW/documentserver*/nginx/includes/*.conf \
        /etc/nginx/includes/ds-cache.conf \
        /etc/nginx/includes/
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/dictionaries \
        /var/www/$COMPANY_NAME_LOW/documentserver/dictionaries
    COPY --from=ds-service \
        /etc/$COMPANY_NAME_LOW/documentserver/default.json \
        /etc/$COMPANY_NAME_LOW/documentserver/production-linux.json \
        /etc/$COMPANY_NAME_LOW/documentserver/
    COPY --from=ds-service --chown=ds:ds \
        /etc/$COMPANY_NAME_LOW/documentserver/log4js/production.json \
        /etc/$COMPANY_NAME_LOW/documentserver/log4js/
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs-plugins \
        /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs-plugins
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/core-fonts \
        /var/www/$COMPANY_NAME_LOW/documentserver/core-fonts
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/fonts \
        /var/www/$COMPANY_NAME_LOW/documentserver/fonts
    COPY --from=ds-service \
        /usr/share/fonts \
        /usr/share/fonts
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs \
        /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/DocService \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/DocService
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/FileConverter \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/FileConverter
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/AdminPanel/server \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/AdminPanel/server
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/server/AdminPanel/client \
        /client
    #COPY --from=ds-service \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/server/info \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/server/info
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/web-apps \
        /var/www/$COMPANY_NAME_LOW/documentserver/web-apps
    COPY --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver/document-templates/new \
        /var/www/$COMPANY_NAME_LOW/documentserver/document-templates/new
    #COPY --from=ds-service \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/document-formats \
    #    /var/www/$COMPANY_NAME_LOW/documentserver/document-formats
    COPY --chown=ds:ds --from=ds-service \
        /var/www/$COMPANY_NAME_LOW/documentserver-example/welcome \
        /var/www/$COMPANY_NAME_LOW/documentserver-example/welcome
    COPY build/scripts/orchestrated/docker-entrypoint.sh build/scripts/orchestrated/proxy-docker-entrypoint.sh /usr/local/bin/
    COPY build/scripts/orchestrated/init-docker-entrypoint.sh /init/
    RUN sed 's|\(application\/zip.*\)|\1\n    application\/wasm wasm;|' \
            -i /etc/nginx/mime.types && \
        sed 's,\(listen.\+:\)\([0-9]\+\)\(.*;\),'"\18888\3"',' \
            -i /etc/nginx/conf.d/ds.conf && \
        sed '/access_log.*/d' -i /etc/nginx/includes/ds-common.conf && \
        sed '/error_log.*/d' -i /etc/nginx/includes/ds-common.conf && \
        echo -e "\ngzip_proxied \$NGINX_GZIP_PROXIED;\n" >> /etc/nginx/includes/ds-common.conf && \
        sed 's/#*\s*\(gzip_static\).*/\1 on;/g' -i /etc/nginx/includes/ds-docservice.conf && \
        sed -i 's/etc\/nginx/tmp\/proxy_nginx/g' /etc/nginx/nginx.conf && \
        sed -i 's/etc\/nginx/tmp\/proxy_nginx/g' /etc/nginx/conf.d/ds.conf && \
        sed 's/\(X-Forwarded-For\).*/\1 example.com;/' -i /etc/nginx/includes/ds-example.conf && \
        sed 's/\(index\).*/\1 k8s.html;/' -i /etc/nginx/includes/ds-example.conf && \
        chmod 755 /var/log/nginx && \
        ln -sf /dev/stdout /var/log/nginx/access.log && \
        ln -sf /dev/stderr /var/log/nginx/error.log && \
        mkdir -p \
            /var/lib/$COMPANY_NAME_LOW/documentserver/App_Data/cache/files \
            /var/www/$COMPANY_NAME_LOW/config \
            /var/lib/$COMPANY_NAME_LOW/documentserver/App_Data/docbuilder && \
        chown -R ds:ds /var/lib/$COMPANY_NAME_LOW/documentserver /var/www/$COMPANY_NAME_LOW/config && \
        find \
            /var/www/$COMPANY_NAME_LOW/documentserver/fonts \
            -type f ! \
            -name "*.*" \
            -exec sh -c 'gzip -cf9 $0 > $0.gz && chown ds:ds $0.gz' {} \; && \
        find \
            /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs \
            /var/www/$COMPANY_NAME_LOW/documentserver/sdkjs-plugins \
            /var/www/$COMPANY_NAME_LOW/documentserver/web-apps \
            /var/www/$COMPANY_NAME_LOW/documentserver-example/welcome \
            -type f \
            \( -name *.js -o -name *.json -o -name *.htm -o -name *.html -o -name *.css \) \
            -exec sh -c 'gzip -cf9 $0 > $0.gz && chown ds:ds $0.gz' {} \;
    VOLUME /var/lib/$COMPANY_NAME_LOW
    USER ds

    # --------------------------------------------------------------------
    # Default entrypoint for Docs services
    # Do NOT override this for DocService/Converter/Adminpanel; only provide `args`
    # --------------------------------------------------------------------
    ENTRYPOINT ["dumb-init", "--", "docker-entrypoint.sh"]

    # --------------------------------------------------------------------
    # Default execution mode for the image.
    # Kubernetes `args` override this value:
    #   - DocService Deployment:
    #       args: ["docservice", ...]
    #   - Converter Deployment:
    #       args: ["converter", ...]
    #   - Adminpanel Deployment:
    #       args: ["adminpanel"]
    #
    # Proxy Deployment should override `command` instead:
    #   command: ["proxy-docker-entrypoint.sh"]
    #   args: [...]
    # --------------------------------------------------------------------
    CMD ["docservice"]


FROM node:22-alpine3.19 AS example
    LABEL maintainer Euro-Office

    ENV LANG=en_US.UTF-8 \
        LANGUAGE=en_US:en \
        LC_ALL=en_US.UTF-8 \
        NODE_ENV=production-linux \
        NODE_CONFIG_DIR=/etc/euro-office/documentserver-example/

    WORKDIR /var/www/euro-office/documentserver-example/

    COPY document-server-integration ./document-server-integration

    RUN apk update && \
        apk add git && \
        #git clone \
        #--depth 1 \
        #--recurse-submodules \
        #https://github.com/Euro-Office/document-server-integration.git && \
        mkdir -p /var/www/euro-office/documentserver-example && \
        cp -r ./document-server-integration/web/documentserver-example/nodejs/. \
        /var/www/euro-office/documentserver-example/ && \
        rm -rf ./document-server-integration && \
        addgroup -S -g 1001 ds && \
        adduser \
        -S \
        -G ds \
        -D \
        -h /var/www/euro-office/documentserver-example \
        -s /sbin/nologin \
        -u 1001 ds && \
        chown -R ds:ds /var/www/euro-office/documentserver-example/ && \
        mkdir -p /var/lib/euro-office/documentserver-example/ && \
        chown -R ds:ds /var/lib/euro-office/ && \
        mv files /var/lib/euro-office/documentserver-example/ && \
        mkdir -p /etc/euro-office/documentserver-example/ && \
        chown -R ds:ds /etc/euro-office/ && \
        mv config/* /etc/euro-office/documentserver-example/ && \
        rmdir config && \
        ln -sf /etc/euro-office/documentserver-example \
            /var/www/euro-office/documentserver-example/config && \
        npm install

    EXPOSE 3000

    USER ds

    ENTRYPOINT ["/var/www/euro-office/documentserver-example/docker-entrypoint.sh", "npm", "start"]

FROM python:3.11-bookworm AS builder
    RUN pip install redis psycopg2  PyMySQL pika python-qpid-proton func_timeout requests kubernetes flask


FROM python:3.11-slim-bookworm AS utils
    ARG TARGETARCH
    ARG DS_VERSION_HASH
    ENV DS_VERSION_HASH=$DS_VERSION_HASH
    COPY --from=ds-base /usr/local/bin/dumb-init /usr/local/bin/dumb-init
    COPY --from=ds-base /opt/oracle/instantclient_23_7 /oracle/instantclient
    COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
    RUN apt update && \
        apt-get install -y curl wget gnupg2 lsb-release jq xxd procps libaio1 unzip && \
        echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
        curl -sSL https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc && \
        echo "deb [arch=${TARGETARCH}] https://packages.microsoft.com/debian/$(lsb_release -rs)/prod $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/mssql.list && \
        apt-get update && \
        ACCEPT_EULA=Y apt install -y postgresql-client-17 default-mysql-client mssql-tools18 unixodbc-dev && \
        curl -LO \
        https://dl.k8s.io/release/`curl \
        -L -s https://dl.k8s.io/release/stable.txt`/bin/linux/${TARGETARCH}/kubectl && \
        chmod +x ./kubectl && \
        mv ./kubectl /usr/local/bin/kubectl && \
        mkdir /oracle/sqlplus /scripts && \
        wget -O /oracle/sqlplus/sqlplus.zip https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-sqlplus-linux.x64-23.7.0.25.01.zip && \
        unzip -o /oracle/sqlplus/sqlplus.zip -d /oracle/sqlplus && \
        mv /oracle/sqlplus/instantclient_23_7/* /oracle/instantclient/ && \
        rm -rf /oracle/sqlplus && \
        groupadd --system -g 1006 ds && \
        useradd --system -g ds -d /home/ds -s /bin/bash -u 101 ds && \
        chown -R ds:ds /scripts && \
        chmod +x /usr/local/bin/dumb-init && \
        rm -rf /var/lib/apt/lists/*
    COPY build/scripts/orchestrated/sqlplus /usr/bin/sqlplus
    USER ds

FROM statsd/statsd AS metrics
    ARG COMPANY_NAME_LOW=euro-office
    COPY --from=ds-service /var/www/$COMPANY_NAME_LOW/documentserver/server/Metrics/config/config.js /usr/src/app/config.js

FROM postgres:$POSTGRES_VERSION AS db
    ARG COMPANY_NAME_LOW=euro-office
    COPY --from=ds-service /var/www/$COMPANY_NAME_LOW/documentserver/server/schema/postgresql/createdb.sql /docker-entrypoint-initdb.d/

FROM mysql:$MYSQL_VERSION AS mysqldb
    ARG COMPANY_NAME_LOW=euro-office
    COPY --chmod=777 --from=ds-service /var/www/$COMPANY_NAME_LOW/documentserver/server/schema/mysql/createdb.sql /docker-entrypoint-initdb.d/

FROM mariadb:$MARIADB_VERSION AS db-mariadb
    ARG COMPANY_NAME_LOW=euro-office
    COPY --from=ds-service /var/www/$COMPANY_NAME_LOW/documentserver/server/schema/mysql/createdb.sql /docker-entrypoint-initdb.d/