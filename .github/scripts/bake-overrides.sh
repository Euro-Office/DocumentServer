#!/usr/bin/env bash
# Prints the docker/bake-action `set` lines that every build workflow needs, as
# a multi-line $GITHUB_OUTPUT value named "set":
#
#   *.context=..                               build context = repo root
#   <target>.cache-from / <target>.cache-to    registry cache per target
#   <target>.tags=                             unless the target is PUBLISHED
#
# Environment:
#   CACHE_REF   cache ref template; "{target}" is replaced by the target name
#   PUBLISHED   space-separated targets whose tags/output the caller sets itself
#   SKIP        space-separated targets the caller does not build
#   BAKE_FILE   bake file the targets are read from (default build/docker-bake.hcl)
set -euo pipefail

: "${CACHE_REF:?}" "${GITHUB_OUTPUT:?}"
PUBLISHED="${PUBLISHED:-}"
SKIP="${SKIP:-}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cache-lib.sh
source "$here/cache-lib.sh"
mapfile -t TARGETS < <(cache_targets "${BAKE_FILE:-$here/../../build/docker-bake.hcl}")
[[ ${#TARGETS[@]} -gt 0 ]] || { echo "::error::No bake targets found." >&2; exit 1; }

in_list() { [[ " $2 " == *" $1 "* ]]; }

delim="EOF_$(openssl rand -hex 8)"
{
  echo "set<<${delim}"
  echo '*.context=..'
  for t in "${TARGETS[@]}"; do
    in_list "$t" "$SKIP" && continue
    ref="${CACHE_REF//\{target\}/$t}"
    echo "${t}.cache-from=type=registry,ref=${ref}"
    echo "${t}.cache-to=type=registry,ref=${ref},mode=max"
    in_list "$t" "$PUBLISHED" || echo "${t}.tags="
  done
  echo "${delim}"
} >> "$GITHUB_OUTPUT"
