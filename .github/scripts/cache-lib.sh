#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Shared helpers for the registry build cache. Source it, do not run it.
# build/docker-bake.hcl is the single source of the target list; this file only
# holds the exceptions.

# Targets that never get a registry cache: a dummy base image.
CACHE_SKIP_TARGETS="brand-icons"

# Prints every bake target of $1 (a bake file) that gets a registry cache ref,
# one per line. Groups are not targets and are not listed.
cache_targets() {
  local file="${1:?bake file required}" names target
  names="$(docker buildx bake -f "$file" --list targets 2>/dev/null | awk -F'\t' 'NR > 1 { print $1 }' | sort -u)"
  [[ -n "$names" ]] || { echo "no targets found in $file" >&2; return 1; }
  # shellcheck disable=SC2086 # names are bake identifiers, split on purpose
  docker buildx bake -f "$file" --print $names 2>/dev/null | jq -r '.target | keys[]' | while read -r target; do
    [[ " $CACHE_SKIP_TARGETS " == *" $target "* ]] || echo "$target"
  done
}
