# ==============================================================================
# MODULE DOCKERFILE
# This file is not meant to be built standalone. It is consumed by the 
# docker-bake.hcl files in the parent monorepos.
#
# REQUIRED CONTEXTS:
# - bundle: bundled builds 
# ==============================================================================

#### PACKAGE ####

FROM ubuntu:24.04 AS package

    ARG COMPANY_NAME
    ARG COMPANY_NAME_LOW
    ARG PRODUCT_NAME
    ARG BRANDING_DIR
    ARG PRODUCT_VERSION
    ARG BUILD_NUMBER=0
    ARG OUT_BASE="/build/package/out"
    ARG BUNDLE_BASE="/build/bundle"
    ARG OUT_DIR="${BUNDLE_BASE}/${COMPANY_NAME_LOW}/documentserver"
    ARG EXAMPLE_OUT="${BUNDLE_BASE}/${COMPANY_NAME_LOW}/documentserver-example"
    # Avoid interactive prompts during package install
    ARG DEBIAN_FRONTEND=noninteractive

    ENV PRODUCT_VERSION=${PRODUCT_VERSION}
    ENV COMPANY_NAME=${COMPANY_NAME}
    ENV PRODUCT_NAME=${PRODUCT_NAME}
    ENV BUILD_NUMBER=${BUILD_NUMBER}
    ENV OUT_BASE=${OUT_BASE}
    ENV BUNDLE_BASE=${BUNDLE_BASE}
    ENV OUT_DIR=${OUT_DIR}
    ENV EXAMPLE_OUT=${EXAMPLE_OUT}

    RUN apt-get update && \
        apt-get install -yq --no-install-recommends \
            devscripts dpkg-dev build-essential fakeroot debhelper \
            rpm m4 curl ca-certificates gnupg symlinks && \
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get install -yq --no-install-recommends nodejs && \
        npm install -g @yao-pkg/pkg && \
        rm -rf /var/lib/apt/lists/*

    #Build files
    COPY --from=bundle /build/documentserver ${OUT_DIR}/
    COPY --from=bundle /build/documentserver-example ${EXAMPLE_OUT}/

    # Upstream packaging repo
    COPY document-server-package/ /document-server-package/

    ### Branding
    COPY --from=brand-icons /[d]ocument-server-package /document-server-package/

    RUN cd document-server-package && \
        mkdir -p ${OUT_BASE} && \
        ln -s ${BUNDLE_BASE} ${OUT_BASE}/linux_64  && \
        ln -s ${BUNDLE_BASE} ${OUT_BASE}/linux_arm64 && \
        make deb rpm \
            BRANDING_DIR="." \
            BUILD_OUTPUT_DIR="${OUT_BASE}" \
            PRODUCT_VERSION="${PRODUCT_VERSION}" \
            BUILD_NUMBER="${BUILD_NUMBER}"

    RUN mkdir -p /packages && \
        find /document-server-package/deb          -name "*.deb" -exec cp -v {} /packages/ \;  && \
        find /document-server-package/rpm/builddir -name "*.rpm" -exec cp -v {} /packages/ \;

#### PACKAGES OUTPUT ####
# Scratch stage so `docker build --target packages -o <dir>` extracts only
# the finished .deb and .rpm files.
FROM scratch AS packages
    COPY --from=package /packages/ /