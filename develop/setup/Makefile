SHELL := /bin/bash

all: web-apps sdkjs core server #core/wasm


# ARM64 platform accommodations
IS_ARM64      := $(filter aarch64,$(shell uname -m))
CC_PLATFORM   ?= $(if $(IS_ARM64),java,$(shell $(EO_DEV)/sdkjs/build/node_modules/google-closure-compiler-linux/compiler --version >/dev/null 2>&1 && echo "native,java" || echo "java"))
CORE_FLAGS    := -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS_DEBUG="-g -O0" -DCMAKE_C_FLAGS_DEBUG="-g -O0"
SERVER_FLAGS  :=
SDKJS_FLAGS   :=
SDKJS_OPTS    := --compiled
WEBAPPS_FLAGS :=

# Must match the DocumentServer version reported by the SDK (asc_getBuildVersion).
# onServerVersion() blocks asc_LoadDocument() when there is a mismatch, causing
# a permanent skeleton UI.  Override on the command line when upgrading the container:
#   PRODUCT_VERSION=9.4.0 make web-apps-dev
PRODUCT_VERSION ?= $(shell cat $(EO_DEV)/VERSION)

# Pass SKIP_MOBILE=1 to skip framework7-react mobile builds (~50s saved).
# Useful when iterating on desktop editor JS/CSS only.
#   SKIP_MOBILE=1 make web-apps-dev
SKIP_MOBILE ?= 0

CHECK_WEBAPPS_DEPS = @test -d $(EO_DEV)/web-apps/build/node_modules || { echo "Run 'make web-apps' first to install dependencies"; exit 1; }

# Dev-friendly cache flush: regenerate nginx cache tag and reload, without
# the production-only api.js.tpl copy and ds:ds chown from the upstream script.
define FLUSH_CACHE
	@HASH=$$(date +'%Y.%m.%d-%H%M' | openssl md5 | awk '{print $$2}'); \
	echo "set \$$cache_tag \"$$HASH\";" > /etc/nginx/includes/ds-cache.conf; \
	service nginx reload
endef

sdkjs:    DEBUG_FLAGS = $(SDKJS_FLAGS)


web-apps: DEBUG_FLAGS = $(WEBAPPS_FLAGS)

core/%:   DEBUG_FLAGS = $(CORE_FLAGS)
core:     DEBUG_FLAGS = $(CORE_FLAGS)

server/%: DEBUG_FLAGS = $(SERVER_FLAGS)
server:   DEBUG_FLAGS = $(SERVER_FLAGS)


# The flags will only be populated if DEBUG=1 is passed
ifeq ($(DEBUG), 1)
    CFLAGS += $(DEBUG_FLAGS)
endif


## -----------------
## WEB-APPS BUILD
## -----------------

web-apps:
	@echo "Building web-apps"
	cd $(EO_DEV)/web-apps/translation && \
	python3 merge_and_check.py && \
	cd $(EO_DEV)/web-apps/build && \
	npm ci && \
	BUILD_ROOT=$(EO_ROOT) PRODUCT_VERSION=$(PRODUCT_VERSION) THEME=euro-office \
	SKIP_MOBILE=$(SKIP_MOBILE) \
	node scripts/build-pipeline.js
	$(FLUSH_CACHE)

web-apps-dev:
	$(CHECK_WEBAPPS_DEPS)
	cd $(EO_DEV)/web-apps/translation && \
	python3 merge_and_check.py && \
	cd $(EO_DEV)/web-apps/build && \
	BUILD_ROOT=$(EO_ROOT) PRODUCT_VERSION=$(PRODUCT_VERSION) THEME=euro-office \
	SKIP_MOBILE=$(SKIP_MOBILE) \
	node scripts/build-pipeline.js
	$(FLUSH_CACHE)

## -----------------
## SDKJS BUILD
## -----------------

sdkjs:
	@echo "Building sdkjs with flags $(CFLAGS)"
	cd $(EO_DEV)/sdkjs/build && \
	npm install && \
	CC_PLATFORM=$(CC_PLATFORM) BUILD_ROOT=$(EO_ROOT) grunt $(SDKJS_OPTS) $(CFLAGS) develop && \
	/usr/bin/documentserver-generate-allfonts.sh

## -----------------
## CORE BUILD
## -----------------

BUILD_FLAGS     := -DEO_CORE_OUTPUT_DIR=$(EO_ROOT)/server/FileConverter/bin -DEO_CORE_TOOLS_DIR=$(EO_ROOT)/server/tools -DEO_CORE_3RD_PARTY_DIR=/build/3rdParty

define build_core
	@echo "Building $(1) with flags $(CFLAGS)"
	mkdir -p $(1)
	cd $(1) && \
	cmake -GNinja $(BUILD_FLAGS) $(CFLAGS) $(2) && \
	cmake --build .
endef


.PHONY: core

core:
	$(call build_core,/build/core,$(EO_DEV)/core)

core/allfontsgen:
	$(call build_core,/build/allfontsgen,$(EO_DEV)/core/DesktopEditor/AllFontsGen)

core/allthemesgen:
	$(call build_core,/build/allthemesgen,$(EO_DEV)/core/DesktopEditor/allthemesgen)

core/pluginsmanager:
	$(call build_core,/build/pluginsmanager,$(EO_DEV)/core/DesktopEditor/pluginsmanager)

core/x2t:
	$(call build_core,/build/x2t,$(EO_DEV)/core/X2tConverter/build/cmake)

core/docbuilder:
	$(call build_core,/build/docbuilder,$(EO_DEV)/core/DesktopEditor/doctrenderer/app_builder)


## -----------------
## CORE WASM BUILD
## -----------------

define build_wasm
	@echo "Building $(1) with flags $(CFLAGS)"
	mkdir -p $(1)
	cd $(1) && \
	source /opt/emsdk/emsdk_env.sh && \
	emcmake cmake -DEO_CORE_3RD_PARTY_DIR=/build/wasm/3rdParty -DEO_CORE_OUTPUT_DIR=$(2) $(3) && \
	cmake --build .
endef

build-font:
	$(call build_wasm,/build/wasm/font,$(EO_DEV)/sdkjs/common,$(EO_DEV)/core/DesktopEditor/fontengine/js)

build-spell:
	$(call build_wasm,/build/wasm/spell,$(EO_DEV)/sdkjs/common,$(EO_DEV)/core/Common/3dParty/hunspell)

build-zlib:
	$(call build_wasm,/build/wasm/zlib,$(EO_DEV)/sdkjs/common,$(EO_DEV)/core/OfficeUtils/js)

build-hash:
	$(call build_wasm,/build/wasm/hash,$(EO_DEV)/sdkjs/common,$(EO_DEV)/core/DesktopEditor/xmlsec/src/wasm/hash)

build-draw:
	$(call build_wasm,/build/wasm/draw,$(EO_DEV)/sdkjs/pdf/src,$(EO_DEV)/core/DesktopEditor/graphics/pro/js)

build-oform:
	$(call build_wasm,/build/wasm/oform,$(EO_DEV)/core/DesktopEditor/xmlsec/src/wasm/oform_plugin/module/deploy,$(EO_DEV)/core/DesktopEditor/xmlsec/src/wasm/oform_plugin/module)

core/wasm/font: build-font
	@$(MAKE) sdkjs

core/wasm/spell: build-spell
	@$(MAKE) sdkjs

core/wasm/zlib: build-zlib
	@$(MAKE) sdkjs

core/wasm/hash: build-hash
	@$(MAKE) sdkjs

core/wasm/draw: build-draw
	@$(MAKE) sdkjs

core/wasm/oform: build-oform

core/wasm: build-font build-spell build-zlib build-hash build-draw
	@echo "All WASM modules built. Running sdkjs..."
	@$(MAKE) sdkjs

## -----------------
## SERVER BUILD
## -----------------

define build_server
	@echo "Building $(1) with flags $(CFLAGS)"
	cd $(1) && \
	npm install && \
	pkg . -t linux-x64 --node-options="--max_old_space_size=4096" $(CFLAGS) -o $(2) && \
	supervisorctl restart $(3)
endef


server: server/common server/docservice server/converter server/metrics server/adminp

server/common:
	cd $(EO_DEV)/server/Common && \
	npm install && \
	sed "s|\(const buildVersion = \).*|\1'${PRODUCT_VERSION}';|" -i sources/commondefines.js

server/docservice: server/common
	$(call build_server,$(EO_DEV)/server/DocService,${EO_ROOT}/server/DocService/docservice, docservice)

server/converter: server/common
	$(call build_server,$(EO_DEV)/server/FileConverter,${EO_ROOT}/server/FileConverter/converter, converter)

server/metrics: server/common
	$(call build_server,$(EO_DEV)/server/Metrics,${EO_ROOT}/server/Metrics/metrics, metrics)

server/adminp: server/common server/adminp/cli server/adminp/srv

server/adminp/srv: server/common
	$(call build_server,$(EO_DEV)/server/AdminPanel/server,${EO_ROOT}/server/AdminPanel/server/adminpanel, adminpanel)

server/adminp/cli: server/common
	@echo "Building server/adminpanel/client with flags $(CFLAGS)"
	cd $(EO_DEV)/server/AdminPanel/client && \
	npm install && \
	BUILD_ROOT=$(EO_ROOT)/server/AdminPanel/client npm run build $(CFLAGS)
