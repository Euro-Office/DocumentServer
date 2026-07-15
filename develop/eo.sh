#!/usr/bin/env bash
#
# eo.sh — run multiple isolated Euro-Office test servers in parallel.
#
# Each instance is a single self-contained container (its own Postgres, Redis,
# RabbitMQ, Nginx and supervisord) built from the prebuilt multi-arch dev image
# ghcr.io/euro-office/documentserver:latest-dev. No full docker build required.
#
# The current git working tree is mounted at /develop so the in-container `make`
# targets (web-apps-dev, sdkjs, server/docservice, core/x2t, …) rebuild your
# local changes in place. Run each building instance from its own worktree so
# parallel builds don't clobber each other's node_modules.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EO_IMAGE="${EO_IMAGE:-ghcr.io/euro-office/documentserver:latest-dev}"
# Shared, predictable JWT secret. The bundled example app always runs with JWT
# enabled, so the document server must sign its requests with the same secret —
# otherwise /download is rejected (403) and documents won't open. Override via env.
EO_JWT_SECRET="${EO_JWT_SECRET:-euro-office-dev-jwt-secret-key-2026}"
LABEL="eo.test=1"
PREFIX="eo-"

die() { echo "error: $*" >&2; exit 1; }

cname() { printf '%s%s' "$PREFIX" "$1"; }

# Docker container names must match [a-zA-Z0-9][a-zA-Z0-9_.-]*.
valid_name() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; }

repo_root() {
  git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null \
    || die "not inside a git repository (run from within the DocumentServer checkout)"
}

host_port() {
  # Resolve the host port mapped to container :80 (handles 0.0.0.0:PORT / [::]:PORT).
  docker port "$(cname "$1")" 80 2>/dev/null | head -n1 | sed 's/.*://'
}

require_name() { [ -n "${1:-}" ] || die "$2"; }

ensure_exists() {
  docker inspect "$(cname "$1")" >/dev/null 2>&1 || die "no such instance '$1' (see: eo.sh ls)"
}

ensure_running() {
  ensure_exists "$1"
  [ "$(docker inspect -f '{{.State.Status}}' "$(cname "$1")" 2>/dev/null)" = "running" ] \
    || die "instance '$1' is not running (see: eo.sh ls)"
}

# Host path bind-mounted to /develop in the given container (empty if none).
mount_src() {
  docker inspect -f '{{range .Mounts}}{{if eq .Destination "/develop"}}{{.Source}}{{end}}{{end}}' "$1" 2>/dev/null
}

cmd_up() {
  local force=0
  if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--force" ]; then force=1; shift; fi
  local name="${1:-}" port="${2:-}"
  require_name "$name" "usage: eo.sh up [--force] <name> [port]"
  valid_name "$name" || die "invalid name '$name' (allowed: letters, digits, '_', '.', '-')"
  [ -z "$port" ] || [[ "$port" =~ ^[0-9]+$ ]] || die "port must be numeric, got '$port'"
  local container; container="$(cname "$name")"

  if docker inspect "$container" >/dev/null 2>&1; then
    if [ "$force" -eq 1 ]; then
      echo "Recreating $container (--force)"
      docker rm -f "$container" >/dev/null
    else
      die "instance '$name' already exists (use 'eo.sh up --force $name' to recreate, or 'eo.sh down $name')"
    fi
  fi

  local publish
  if [ -n "$port" ]; then publish="${port}:80"; else publish="0:80"; fi

  local root; root="$(repo_root)"
  echo "Starting $container from $EO_IMAGE"
  echo "  mount: $root -> /develop"
  # A fresh `git worktree` doesn't populate submodules; warn before in-container
  # builds fail confusingly on an empty source tree.
  [ -d "$root/web-apps/build" ] || \
    echo "  warning: $root/web-apps looks uninitialized — run 'git submodule update --init --recursive' here before 'eo.sh build'" >&2

  if ! docker run -d \
    --name "$container" \
    --label "$LABEL" \
    -p "$publish" \
    -e EXAMPLE_ENABLED=true \
    -e WOPI_ENABLED=true \
    -e JWT_SECRET="$EO_JWT_SECRET" \
    -e USE_UNAUTHORIZED_STORAGE=true \
    -e ALLOW_PRIVATE_IP_ADDRESS=true \
    -e THEME=euro-office \
    -v "$root:/develop" \
    -v "$SCRIPT_DIR/setup/Makefile:/Makefile" \
    "$EO_IMAGE" >/dev/null; then
    # Failed start (e.g. port already allocated) leaves a Created container that
    # would block the next 'up' — remove it so re-running is clean.
    docker rm -f "$container" >/dev/null 2>&1 || true
    die "failed to start $container (is the port in use?)"
  fi

  printf 'Waiting for %s to become healthy' "$container"
  local _
  for _ in $(seq 1 150); do
    if docker exec "$container" curl -sf http://localhost/healthcheck >/dev/null 2>&1; then
      local hp; hp="$(host_port "$name")"
      echo " ready"
      echo
      local base="http://localhost:${hp}"
      echo "  $container  ->  ${base}/"
      echo "  example app ->  ${base}/example/"
      echo "  new document     ${base}/example/editor?fileExt=docx"
      echo "  new spreadsheet  ${base}/example/editor?fileExt=xlsx"
      echo "  new presentation ${base}/example/editor?fileExt=pptx"
      echo "  new pdf form     ${base}/example/editor?fileExt=pdf"
      echo
      echo "  build:  ./eo.sh build $name web-apps-dev"
      echo "  shell:  ./eo.sh exec  $name"
      echo "  stop:   ./eo.sh down  $name"
      return 0
    fi
    if [ "$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)" != "running" ]; then
      echo " failed"
      die "container exited — check: ./eo.sh logs $name"
    fi
    printf '.'
    sleep 2
  done
  echo " timeout"
  die "healthcheck did not pass — check: ./eo.sh logs $name"
}

cmd_build() {
  local name="${1:-}"; shift || true
  require_name "$name" "usage: eo.sh build <name> <make-target> [more targets…]"
  [ "$#" -gt 0 ] || die "usage: eo.sh build <name> <make-target> [more targets…]"
  ensure_running "$name"
  docker exec "$(cname "$name")" make "$@"
}

cmd_exec() {
  local name="${1:-}"; shift || true
  require_name "$name" "usage: eo.sh exec <name> [command…]"
  ensure_running "$name"
  # Allocate a TTY only when attached to one, so non-interactive callers
  # (agents, pipes) don't hit "the input device is not a TTY".
  local flags=(-i); [ -t 0 ] && [ -t 1 ] && flags=(-i -t)
  if [ "$#" -eq 0 ]; then
    docker exec "${flags[@]}" "$(cname "$name")" bash
  else
    docker exec "${flags[@]}" "$(cname "$name")" "$@"
  fi
}

cmd_logs() {
  local name="${1:-}"
  require_name "$name" "usage: eo.sh logs <name>"
  ensure_exists "$name"
  docker logs -f "$(cname "$name")"
}

cmd_ls() {
  # -a so stopped/half-started instances are visible (they still block 'up').
  local ids; ids="$(docker ps -aq --filter "label=$LABEL")"
  if [ -z "$ids" ]; then echo "no eo.test instances"; return 0; fi
  printf '%-16s %-9s %-7s %-26s %s\n' "INSTANCE" "STATUS" "PORT" "URL" "MOUNT"
  local id name status hp url mnt
  for id in $ids; do
    name="$(docker inspect -f '{{.Name}}' "$id" | sed "s|^/${PREFIX}||")"
    status="$(docker inspect -f '{{.State.Status}}' "$id")"
    mnt="$(mount_src "$id")"; [ -n "$mnt" ] || mnt="-"
    if [ "$status" = "running" ]; then
      hp="$(host_port "$name")"; url="http://localhost:${hp}/"
    else
      hp="-"; url="-"
    fi
    printf '%-16s %-9s %-7s %-26s %s\n' "$name" "$status" "$hp" "$url" "$mnt"
  done
}

cmd_down() {
  [ "$#" -gt 0 ] || die "usage: eo.sh down <name>... | --all"
  if [ "$1" = "--all" ]; then
    local ids; ids="$(docker ps -aq --filter "label=$LABEL")"
    if [ -n "$ids" ]; then
      echo "$ids" | xargs docker rm -f >/dev/null && echo "removed all eo.test instances"
    else
      echo "nothing to remove"
    fi
    return 0
  fi
  local name
  for name in "$@"; do
    docker rm -f "$(cname "$name")" >/dev/null && echo "removed $(cname "$name")"
  done
}

usage() {
  cat <<'EOF'
eo.sh — run multiple isolated Euro-Office test servers in parallel.

Usage:
  eo.sh up [--force] <name> [port]
                                Start instance eo-<name>. Auto-assigns a free host
                                port unless one is given. Waits for /healthcheck,
                                then prints the URL. --force recreates an existing one.
  eo.sh build <name> <target>   Run an in-container make target against the mounted
                                source, e.g.: web-apps-dev | sdkjs | server/docservice
                                | server/converter | core/x2t | core/docbuilder
  eo.sh exec <name> [cmd…]      Run a command (default: bash) inside the container.
  eo.sh logs <name>             Follow container logs.
  eo.sh ls                      List running instances with their host ports.
  eo.sh down <name>… | --all    Stop and remove instance(s).

Env:
  EO_IMAGE        Override the image (default ghcr.io/euro-office/documentserver:latest-dev).
                  Must be a *-dev image — the production :latest lacks the build toolchain.
  EO_JWT_SECRET   Shared JWT secret for the document server and the bundled example app
                  (default: euro-office-dev-jwt-secret-key-2026). Use this when signing
                  API requests directly.

Notes:
  - The current git working tree is mounted at /develop. Run each *building* instance
    from its own git worktree so parallel builds don't share node_modules.
  - JWT is ENABLED with a shared dev secret so the example app's /download works and
    documents open. These are local test servers — do not expose them publicly.
    EXAMPLE_ENABLED and WOPI_ENABLED are on by default.
EOF
}

main() {
  command -v docker >/dev/null 2>&1 || die "docker not found in PATH"
  local sub="${1:-}"; shift || true
  case "$sub" in
    up)    cmd_up    "$@" ;;
    build) cmd_build "$@" ;;
    exec)  cmd_exec  "$@" ;;
    logs)  cmd_logs  "$@" ;;
    ls)    cmd_ls    "$@" ;;
    down)  cmd_down  "$@" ;;
    ""|-h|--help|help) usage ;;
    *) die "unknown command '$sub' (see: eo.sh --help)" ;;
  esac
}

main "$@"
