# ==============================================================================
# MODULE DOCKERFILE
# This file is not meant to be built standalone. It is consumed by the 
# docker-bake.hcl files in the parent monorepos.
#
# REQUIRED CONTEXTS:
# - docker: the final docker image of documentserver
# ==============================================================================

FROM finalubuntu AS develop
    ARG PRODUCT_VERSION
    # Avoid interactive prompts during package install
    ARG DEBIAN_FRONTEND=noninteractive
    ENV TZ=Etc/UTC

    RUN apt-get update && \
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get install -yq --no-install-recommends nodejs openjdk-21-jdk wget zip brotli && \
        npm install -g @yao-pkg/pkg grunt-cli && \
        rm -rf /var/lib/apt/lists/*

    RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
        apt-get update && \
        apt-get upgrade -y && \
        apt-get install -yq --no-install-recommends \
                    git \
                    curl \
                    sudo \
                    wget \
                    ssh \
                    build-essential \
                    make \
                    cmake \
                    ninja-build \
                    pkg-config \
                    libglib2.0-dev \
                    python3 \
                    python-is-python3 \
                    lsb-release \
                    libboost-all-dev \
                    tar \
                    xz-utils \
                    libtool-bin \
                    autoconf \
                    python3-dev \
                    && \
        rm -rf /var/lib/apt/lists/*

    ## Install Emscripten
    RUN wget -qO emsdk.tar.gz https://github.com/emscripten-core/emsdk/archive/main.tar.gz && \
        mkdir /opt/emsdk && \
        tar xf emsdk.tar.gz --strip-components=1 -C /opt/emsdk && \
        /opt/emsdk/emsdk install latest && \
        /opt/emsdk/emsdk activate latest && \
        chmod +x /opt/emsdk/emsdk_env.sh && \
        rm -rf emsdk.tar.gz

    ENV PRODUCT_VERSION=${PRODUCT_VERSION}
    ENV EO_DEV=/develop
    ENV THEME=euro-office