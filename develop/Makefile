PRODUCT_VERSION ?= $(shell cat ../VERSION)
export PRODUCT_VERSION

EO_JWT_SECRET ?= euro-office-dev-jwt-secret-key-2026
export EO_JWT_SECRET

# Redis topology test-stack settings. These are exported so values supplied
# either from the shell or on the make command line reach Docker Compose.
TYPE ?= STANDALONE
EO_IMAGE ?= ghcr.io/euro-office/documentserver:latest-dev
REDIS_IMAGE ?= redis:7-alpine
REDIS_SERVER_COMMAND ?= redis-server
REDIS_CLI_COMMAND ?= redis-cli
export EO_IMAGE REDIS_IMAGE REDIS_SERVER_COMMAND REDIS_CLI_COMMAND

REDIS_TOPOLOGY_COMPOSE_BASE := docker-compose.redis-base.yml

.PHONY: up down

# Start one Redis topology test stack.
# Examples:
#   make up TYPE=STANDALONE
#   make up TYPE=SENTINEL REDIS_IMAGE=valkey/valkey:8-alpine REDIS_SERVER_COMMAND=valkey-server REDIS_CLI_COMMAND=valkey-cli
#   make up TYPE=CLUSTER
up:
	@topology="$$(printf '%s' "$(TYPE)" | tr '[:upper:]' '[:lower:]')"; \
	case "$$topology" in \
	  standalone|sentinel|cluster) ;; \
	  *) echo "error: TYPE must be STANDALONE, SENTINEL, or CLUSTER (got '$(TYPE)')" >&2; exit 2 ;; \
	esac; \
	docker compose -f "$(REDIS_TOPOLOGY_COMPOSE_BASE)" -f "docker-compose.redis-$$topology.yml" up -d

# Stop one Redis topology test stack. Add PURGE=1 to remove its volumes too.
# Examples:
#   make down TYPE=SENTINEL
#   make down TYPE=CLUSTER PURGE=1
down:
	@topology="$$(printf '%s' "$(TYPE)" | tr '[:upper:]' '[:lower:]')"; \
	case "$$topology" in \
	  standalone|sentinel|cluster) ;; \
	  *) echo "error: TYPE must be STANDALONE, SENTINEL, or CLUSTER (got '$(TYPE)')" >&2; exit 2 ;; \
	esac; \
	flags=""; \
	if [ "$(PURGE)" = "1" ]; then flags="-v"; fi; \
	docker compose -f "$(REDIS_TOPOLOGY_COMPOSE_BASE)" -f "docker-compose.redis-$$topology.yml" down $$flags --remove-orphans

# Detect host LAN IP for phones/emulators/LAN devices. Used by `make mobile`
# and `make refresh-urls`.
ifeq ($(shell uname -s),Darwin)
	DETECTED_HOST_LAN_IP := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
else
	# 1.1.1.1 is a dummy public target — `ip route get` just asks the kernel
	# which local source IP it would use, without actually sending packets.
	DETECTED_HOST_LAN_IP := $(shell ip route get 1.1.1.1 2>/dev/null | awk '{print $$7; exit}')
endif

# Empty by default: `make local` runs on localhost (desktop browser + iOS sim).
# `make mobile` sets this so Android emulators and LAN-connected devices can reach the editor.
HOST_LAN_IP ?=
export HOST_LAN_IP

local:
	@echo ""
	@echo "   ███████╗ ██████╗"
	@echo "   ██╔════╝██╔═══██╗"
	@echo "   █████╗  ██║   ██║"
	@echo "   ██╔══╝  ██║   ██║"
	@echo "   ███████╗╚██████╔╝"
	@echo "   ╚══════╝ ╚═════╝"
	@echo ""
	@echo "   Euro-Office Development Environment"
	@echo ""
ifeq ($(HOST_LAN_IP),)
	@echo "   Mode: localhost (desktop browser + iOS sim)"
	@echo "   For Android / physical device testing: make mobile"
else
	@echo "   Mode: mobile / LAN"
	@echo "   Nextcloud:     http://$(HOST_LAN_IP):8081/"
	@echo "   On IP change:  make refresh-urls"
endif
	@echo "   Volume:    nc_data_$${NC_VERSION:-latest}  (wipe with: make wipe-nc NC_VERSION=$${NC_VERSION:-latest})"
	@echo ""
	docker compose up -d
	@if [ "$$(docker inspect --format '{{.State.Status}}' nextcloud 2>/dev/null)" != "running" ]; then \
	  if docker compose logs nextcloud 2>&1 | grep -q "version of the data"; then \
	    echo ""; \
	    echo "   WARNING: Nextcloud failed to start — your local nextcloud:$${NC_VERSION:-latest} image is"; \
	    echo "   behind the data volume. Pull the latest image and retry:"; \
	    echo ""; \
	    echo "      docker pull nextcloud:$${NC_VERSION:-latest} && make"; \
	    echo ""; \
	    exit 1; \
	  fi; \
	fi
	@$(MAKE) --no-print-directory refresh-urls
	@$(MAKE) --no-print-directory print-nc-version
	@docker compose exec eo bash || true

# Like `make local`, but injects the detected HOST_LAN_IP so that Nextcloud
# returns a DocumentServerUrl mobile/LAN clients can actually reach.
mobile:
	@HOST_LAN_IP="$(DETECTED_HOST_LAN_IP)" $(MAKE) local

# Run against a future Nextcloud version (master / stable33 / stable34) using the
# nextcloud-docker-dev source-clone image. Each NC_BRANCH gets its own named volume,
# so switching branches preserves each branch's installed state.
#
#   make next                       — master (current NC dev trunk)
#   make next NC_BRANCH=stable33    — pin to NC33 stable
#   make next NC_BRANCH=stable34    — pin to NC34 stable (once cut)
#
# `make local` follows nextcloud:latest from Docker Hub (current stable) — use that
# for day-to-day work; reach for `make next` only when testing against unreleased
# or non-current NC.
next:
	@echo ""
	@echo "   Euro-Office — Next NC testing"
	@echo "   NC branch: $${NC_BRANCH:-master}"
	@echo "   Volume:    nc_data_$${NC_BRANCH:-master}  (preserved across switches)"
	@echo ""
	NC_BRANCH=$${NC_BRANCH:-master} docker compose -f docker-compose.yml -f docker-compose.next.yml up -d
	@$(MAKE) --no-print-directory refresh-urls
	@$(MAKE) --no-print-directory print-nc-version
	@docker compose exec eo bash || true

# Like `make next`, but injects the detected HOST_LAN_IP for Android emulator / LAN device testing.
next-mobile:
	@NC_BRANCH="$${NC_BRANCH:-master}" HOST_LAN_IP="$(DETECTED_HOST_LAN_IP)" $(MAKE) next

pull:
	docker compose pull && docker compose up -d && docker compose exec eo bash || true

# Remove the Nextcloud data volume for the current NC_VERSION (default: latest).
# Use this when you want a clean NC install, e.g. after a major version bump.
#   make wipe-nc                  — wipes nc_data_latest
#   make wipe-nc NC_VERSION=33    — wipes nc_data_33
wipe-nc:
	@docker compose stop nextcloud 2>/dev/null || true
	@echo "Removing volume nc_data_$${NC_VERSION:-latest}..."
	@docker volume rm nc_data_$${NC_VERSION:-latest} 2>/dev/null && echo "Done." || echo "Volume not found — nothing to remove."

# Remove the Nextcloud data volume for the given NC_BRANCH (default: master).
#   make wipe-next                      — wipes nc_data_master
#   make wipe-next NC_BRANCH=stable33   — wipes nc_data_stable33
wipe-next:
	@docker compose stop nextcloud 2>/dev/null || true
	@echo "Removing volume nc_data_$${NC_BRANCH:-master}..."
	@docker volume rm nc_data_$${NC_BRANCH:-master} 2>/dev/null && echo "Done." || echo "Volume not found — nothing to remove."

build:
	(cd ../build && docker buildx bake develop) && \
	(docker compose up -d) && \
	(docker compose exec eo bash || true)

# Align Euro-Office URLs and trusted_domains with the current mode.
# - If HOST_LAN_IP is set: mobile/LAN mode (DocumentServerUrl = http://<ip>:8080/, trusted_domains[2] = <ip>).
# - If HOST_LAN_IP is empty: localhost mode (DocumentServerUrl = http://localhost:8080/, trusted_domains[2] cleared).
# Waits for Nextcloud + Euro-Office to finish installing on first boot, then applies idempotently.
refresh-urls:
	@start=$$(date +%s); \
	  while ! docker compose exec -T eo curl -sf http://localhost/healthcheck >/dev/null 2>&1; do \
	    if [ "$$(docker inspect --format '{{.State.Status}}' eo 2>/dev/null)" != "running" ]; then \
	      printf "\r[eo]        failed — check: docker compose logs eo\n"; \
	      exit 1; \
	    fi; \
	    printf "\r[eo]        waiting     (%ds)   " $$(($$(date +%s) - start)); \
	    sleep 2; \
	  done; \
	  printf "\r[eo]        ready        (%ds)        \n" $$(($$(date +%s) - start))
	@start=$$(date +%s); \
	  while ! docker compose exec -T -u www-data nextcloud ./occ config:app:get eurooffice DocumentServerUrl 2>/dev/null | grep -q "http"; do \
	    if [ "$$(docker inspect --format '{{.State.Status}}' nextcloud 2>/dev/null)" != "running" ]; then \
	      printf "\r[nextcloud] failed — check: docker compose logs nextcloud\n"; \
	      exit 1; \
	    fi; \
	    elapsed=$$(($$(date +%s) - start)); \
	    if [ $$elapsed -ge 1000 ]; then \
	      last=$$(docker compose logs --tail=1 nextcloud 2>/dev/null | tr -d '\r'); \
	      printf "\r[nextcloud] still installing (%ds) — %s   " $$elapsed "$$last"; \
	    else \
	      printf "\r[nextcloud] installing  (%ds)   " $$elapsed; \
	    fi; \
	    sleep 2; \
	  done; \
	  printf "\r[nextcloud] ready        (%ds)        \n" $$(($$(date +%s) - start))
	@target="$${HOST_LAN_IP:-localhost}"; \
	  echo "Setting DocumentServerUrl to http://$$target:8080/"; \
	  docker compose exec -T -u www-data nextcloud ./occ config:app:set eurooffice DocumentServerUrl --value="http://$$target:8080/" >/dev/null 2>&1; \
	  if [ "$$target" = "localhost" ]; then \
	    docker compose exec -T -u www-data nextcloud ./occ config:system:delete trusted_domains 2 >/dev/null 2>&1 || true; \
	  else \
	    docker compose exec -T -u www-data nextcloud ./occ config:system:set trusted_domains 2 --value=$$target >/dev/null 2>&1; \
	  fi
	@docker compose exec -T -u www-data nextcloud ./occ config:app:set eurooffice jwt_secret --value="$(EO_JWT_SECRET)" >/dev/null 2>&1; \
	  echo "JWT secret aligned with document server"

# Print the Nextcloud version installed in the running container. Useful after
# `make local` (where it shows the latest stable Docker Hub tag) and `make next`
# (where it resolves the tracked branch — e.g. master → "34.0.0 beta 2").
print-nc-version:
	@v=$$(docker compose exec -T -u www-data nextcloud ./occ -V 2>/dev/null | tr -d '\r'); \
	  if [ -n "$$v" ]; then echo "Running: $$v"; fi
