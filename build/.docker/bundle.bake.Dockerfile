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


# Plugin runtime helpers (v1/) and the bundled plugins from the plugins submodule
FROM alpine AS plugins
    RUN apk add --no-cache bash
    RUN --mount=type=bind,source=plugins,target=/src \
        bash /src/scripts/bundle.sh /out

FROM alpine AS bundle
    ARG BUILD_ROOT=/package
    ARG PRODUCT_NAME_LOW
    ARG COMPANY_NAME_LOW

    ENV PRODUCT_NAME_LOW=${PRODUCT_NAME_LOW}
    ENV COMPANY_NAME_LOW=${COMPANY_NAME_LOW}
    # --- Copy build files
    RUN mkdir -p /build/documentserver/sdkjs-plugins /build/documentserver/fonts \
                /build/documentserver/server/FileConverter/lib /build/documentserver/server/tools

    # --- Static content from build context (rarely changes) ---
    COPY dictionaries /build/documentserver/dictionaries
    COPY document-templates /build/documentserver/document-templates
    COPY core-fonts /build/documentserver/core-fonts
    # WOPI/discovery format list consumed by services.CoAuthoring.server.documentFormatsFile
    COPY document-formats/onlyoffice-docs-formats.json /build/documentserver/document-formats/onlyoffice-docs-formats.json

    # --- Config files
    COPY build/configs/core/DoctRenderer.config /build/documentserver/server/FileConverter/bin/DoctRenderer.config
    COPY server/Metrics/config/config.js /build/documentserver/server/Metrics/config/config.js


    # --- Build stage outputs (change with code) ---
    COPY --from=sdkjs ${BUILD_ROOT} /build/documentserver/
    COPY --from=web-apps ${BUILD_ROOT} /build/documentserver/
    COPY --from=plugins /out/ /build/documentserver/sdkjs-plugins/

    COPY --from=core ${BUILD_ROOT}/bin/ /build/documentserver/server/FileConverter/bin/
    COPY --from=core ${BUILD_ROOT}/tools/ /build/documentserver/server/tools/

    COPY --from=server ${BUILD_ROOT}/docservice    /build/documentserver/server/DocService/docservice
    COPY --from=server ${BUILD_ROOT}/fileconverter /build/documentserver/server/FileConverter/converter
    COPY --from=server ${BUILD_ROOT}/metrics       /build/documentserver/server/Metrics/metrics
    COPY --from=server ${BUILD_ROOT}/adminpanel    /build/documentserver/server/AdminPanel/server/adminpanel
    COPY --from=server ${BUILD_ROOT}/build         /build/documentserver/server/AdminPanel/client/build


    COPY --from=example /example/example /build/documentserver-example/example
    RUN mkdir -p /build/documentserver-example/files
    COPY --from=example /example/config /build/documentserver-example/config

    RUN find /build/documentserver-example/config/ -type f -name '*.json' \
        -exec sed -i "s/euro-office/${COMPANY_NAME_LOW}/g" {} +
    RUN find /build/documentserver-example/config/ -type f -name '*.json' \
        -exec sed -i "s/documentserver/${PRODUCT_NAME_LOW}/g" {} +

    #COPY document-server-package/common/documentserver-example/welcome /build/documentserver-example/welcome
    #RUN YEAR=$(date +"%Y") && \
    #    sed -i "s|{{OFFICIAL_PRODUCT_NAME}}|Community Edition|g" /build/documentserver-example/welcome/*.html && \
    #    find /build/documentserver-example/welcome -depth -type f \
    #        -exec sed -i "s_{{year}}_${YEAR}_g" {} \; && \
    #    sed -i "s|{{EXAMPLE_DISABLED_COMMANDS}}|sudo systemctl start ds-example|g" \
    #        /build/documentserver-example/welcome/example-disabled.html && \
    #    rm -f /build/documentserver-example/welcome/admin-disabled.html && \
    #    sed -i '/<!-- BEGIN ADMIN PANEL SECTION -->/,/<!-- END ADMIN PANEL SECTION -->/d' \
    #        /build/documentserver-example/welcome/docker.html \
    #        /build/documentserver-example/welcome/linux.html \
    #        /build/documentserver-example/welcome/linux-rpm.html \
    #        /build/documentserver-example/welcome/win.html

    
    RUN mkdir -p /build/documentserver/server/Common/config/log4js

    COPY server/Common/config/. /build/documentserver/server/Common/config/

    RUN find /build/documentserver/server/Common/config/ -type f -name '*.json' \
        -exec sed -i "s/euro-office/${COMPANY_NAME_LOW}/g" {} +
    RUN find /build/documentserver/server/Common/config/ -type f -name '*.json' \
        -exec sed -i "s/documentserver/${PRODUCT_NAME_LOW}/g" {} +

    RUN rm -f /build/documentserver/server/Common/config/runtime.json
    
    COPY server/schema/.       /build/documentserver/server/schema/
    COPY server/license/.      /build/documentserver/server/license/
    COPY server/LICENSE.txt    /build/documentserver/server/
    COPY server/3rd-Party.txt  /build/documentserver/server/