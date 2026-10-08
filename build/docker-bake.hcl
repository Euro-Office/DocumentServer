# docker-bake.hcl


variable "BRANDING_DIR" {
  default = "."
}

variable "COMPANY_NAME" {
  default = "Euro-Office"
}

variable "COMPANY_NAME_LOW" {
  default = regex_replace(lower(COMPANY_NAME), "\\s+", "-")
}

variable "PRODUCT_NAME" {
  default = "DocumentServer"
}

variable "PRODUCT_NAME_LOW" {
  default = regex_replace(lower(PRODUCT_NAME), "\\s+", "-")
}

variable "REGISTRY" {
  default = "ghcr.io/${COMPANY_NAME_LOW}"
}

variable "TAG" {
  default = "latest"
}

variable "PRODUCT_VERSION" {
  default = "9.3.1"
}

variable "BUILD_NUMBER" {
  default = "dev.1"
}

variable "DS_VERSION_HASH" {
  default = "dev001"
}

variable "BUILD_ROOT" {
  default = "/package"
}

variable "PACKAGE_BASE" {
  default = "docsrv-build"
}

variable "NUGET_CACHE" {
  default = "local"
  validation {
    condition     = contains(["local", "remote"], NUGET_CACHE)
    error_message = "NUGET_CACHE must be 'local' or 'remote'."
  }
}

variable "NUGET_SOURCE_PATH" {
  default = "/nuget-cache"
}

variable "CACHE_BUST" {
  default = "2"
}

# Root directory for local BuildKit cache import/export. Override with an
# absolute path on a filesystem with enough space for the full build graph.
variable "CACHE_ROOT" {
  default = "/tmp"
}

# ──────────────────────────────────────────────
# BUILD GROUPS
# ──────────────────────────────────────────────

group "default" {
  targets = ["standalone"]
}

group "cluster" {
  targets = ["cluster-utils", "cluster-example", "cluster-docs"]
}

group "develop" {
  targets = ["develop"]
}

# ──────────────────────────────────────────────
# SHARED ARGS (inherited by all targets)
# ──────────────────────────────────────────────

target "_common" {
  args = {
    PRODUCT_VERSION     = "${PRODUCT_VERSION}"
    BUILD_NUMBER        = "${BUILD_NUMBER}"
    BUILD_ROOT          = "${BUILD_ROOT}"
    DS_VERSION_HASH     = "${DS_VERSION_HASH}"
    NUGET_CACHE         = "${NUGET_CACHE}"
    CACHE_BUST          = "${CACHE_BUST}"
    PACKAGE_BASE        = "${PACKAGE_BASE}"
    BRANDING_DIR        = "${BRANDING_DIR}"
    PRODUCT_NAME        = "${PRODUCT_NAME}"
    PRODUCT_NAME_LOW    = "${PRODUCT_NAME_LOW}"
    COMPANY_NAME        = "${COMPANY_NAME}"
    COMPANY_NAME_LOW    = "${COMPANY_NAME_LOW}"
  }
}

# ──────────────────────────────────────────────
# DEPENDENCY TARGETS
# ──────────────────────────────────────────────

target "brand-icons" {
  ## dummy image that contains no brand,
  ## so default brand is applied implicitly.
  ## needs workdir as scratch is otherwise 
  ## non-existent
  dockerfile-inline = "FROM scratch\nWORKDIR /keep"
}


target "core" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./core/.docker/core.bake.Dockerfile"
  target     = "core"
  tags       = ["${REGISTRY}/core:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/core"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/core,mode=max"]
}

target "core-wasm" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./core/.docker/core-wasm.bake.Dockerfile"
  tags       = ["${REGISTRY}/core-wasm:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/core-wasm"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/core-wasm,mode=max"]
}

target "sdkjs" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./sdkjs/.docker/sdkjs.bake.Dockerfile"
  tags       = ["${REGISTRY}/sdkjs:${TAG}"]
  target     = "sdkjs"
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/sdkjs"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/sdkjs,mode=max"]
  contexts = {
    core-wasm    = "target:core-wasm"
  }
}

target "web-apps" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./web-apps/.docker/web-apps.bake.Dockerfile"
  tags       = ["${REGISTRY}/web-apps:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/web-apps"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/web-apps,mode=max"]
}

target "server" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./server/.docker/server.bake.Dockerfile"
  tags       = ["${REGISTRY}/server:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/server"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/server,mode=max"]
  contexts = {
    brand-icons    = "target:brand-icons"
  }
}

target "example" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./document-server-integration/.docker/example.bake.Dockerfile"
  tags       = ["${REGISTRY}/example:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/example"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/example,mode=max"]
  contexts = {
    brand-icons    = "target:brand-icons"
  }
}

target "bundle" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/bundle.bake.Dockerfile"
  target     = "bundle"
  tags       = ["${REGISTRY}/bundle:${TAG}"]
  contexts = {
    core          = "target:core"
    server        = "target:server"
    sdkjs         = "target:sdkjs"
    web-apps      = "target:web-apps"
    example       = "target:example"
  }
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/bundle"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/bundle,mode=max"]
}

# ──────────────────────────────────────────────
# EXPORT TARGETS
# ──────────────────────────────────────────────

target "packages" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/packages.bake.Dockerfile"
  target     = "packages"       # points to the FROM scratch stage
  tags       = ["${REGISTRY}/packages:${TAG}"]
  contexts = {
    bundle          = "target:bundle"
    brand-icons     = "target:brand-icons"
  }

  # Export the filesystem directly to a local directory instead of an image
  output = ["type=local,dest=./deploy/packages"]

  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/packages"]  # reuses builder cache
}

# ──────────────────────────────────────────────
# BUILD TARGETS
# ──────────────────────────────────────────────

### Orchestrated images

target "cluster-docs" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/orchestrated.bake.Dockerfile"
  target     = "docs"
  tags       = ["${REGISTRY}/cluster-docs:${TAG}"]
  contexts = {
    packages = "target:packages"
  }
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/docs"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/docs,mode=max"]
}

target "cluster-example" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/orchestrated.bake.Dockerfile"
  target     = "example"
  tags       = ["${REGISTRY}/cluster-example:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/example"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/example,mode=max"]
}

target "cluster-utils" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/orchestrated.bake.Dockerfile"
  target     = "utils"
  tags       = ["${REGISTRY}/cluster-utils:${TAG}"]
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/utils"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/utils,mode=max"]
}


### Standalone image

target "standalone" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/standalone.bake.Dockerfile"
  target     = "finalubuntu"
  tags       = ["${REGISTRY}/documentserver:${TAG}"]
  contexts = {
    packages = "target:packages"
  }
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/documentserver"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/documentserver,mode=max"]
}

target "develop" {
  inherits   = ["_common"]
  context    = ".."
  dockerfile = "./build/.docker/develop.bake.Dockerfile"
  target     = "develop"
  tags       = ["${REGISTRY}/documentserver:${TAG}-dev"]
  contexts = {
    finalubuntu    = "target:standalone"
  }
  cache-from = ["type=local,src=${CACHE_ROOT}/${REGISTRY}/develop"]
  cache-to   = ["type=local,dest=${CACHE_ROOT}/${REGISTRY}/develop,mode=max"]
}
