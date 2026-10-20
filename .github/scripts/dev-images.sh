#!/usr/bin/env bash
# Helpers for .github/workflows/dev-images.yml and dev-images-cleanup.yml.
#
#   dev-images.sh slug <branch>      print the image tag slug of a dev/* branch
#   dev-images.sh cleanup <branch>   delete the images and caches of a branch
#
# cleanup uses the gh CLI (GH_TOKEN) and reads ORG, DEV_PACKAGES and
# CACHE_PACKAGE from the environment. DRY_RUN=1 only prints what would be
# deleted. dev-images-cleanup.yml runs it when a dev/* branch is deleted; it can
# also be run by hand (see docs/dev-images.md).
#
# Tags written by the build job:
#   <dev package>:<slug>                  the newest build of the branch
#   <CACHE_PACKAGE>:dev-<slug>-<target>-<arch>

# Single-quoted strings below are jq programs; their $vars are jq variables.
# shellcheck disable=SC2016

set -euo pipefail
export LC_ALL=C

# Bake targets that get a registry cache ref (see bake-overrides.sh).
CACHE_TARGETS='core|core-wasm|sdkjs|web-apps|server|example|bundle|packages|standalone|cluster-docs|cluster-example|cluster-utils'
CACHE_ARCHES='amd64|arm64'

# dev/Feature_X -> feature-x-<first 6 hex of sha256("dev/Feature_X")>
# The hash keeps slugs of different branches distinct even when their
# sanitised names are equal; the result is at most 40 characters.
slug() {
  local branch="${1#refs/heads/}" base hash
  [[ "$branch" == dev/?* ]] || { echo "not a dev/* branch: $branch" >&2; return 1; }
  base="$(printf '%s' "${branch#dev/}" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9.-]+/-/g; s/-+/-/g')"
  base="${base:0:33}"
  base="$(sed -E 's/^[.-]+//; s/[.-]+$//' <<<"$base")"
  hash="$(printf '%s' "$branch" | sha256sum | cut -c1-6)"
  printf '%s-%s\n' "${base:-x}" "$hash"
}

# Prints one JSON object {id, tags} per version of package $1.
# Returns 3 if the package does not exist or is not accessible to this token.
versions() {
  local pkg="$1" err
  if ! err="$(gh api "/orgs/$ORG/packages/container/$pkg" --silent 2>&1)"; then
    if [[ "$err" == *"HTTP 404"* ]]; then
      return 3
    fi
    echo "$err" >&2
    return 1
  fi
  gh api --paginate "/orgs/$ORG/packages/container/$pkg/versions?per_page=100" \
    --jq '.[] | {id, tags: (.metadata.container.tags // [])}'
}

skip_missing() {
  echo "::notice::Package $1 not found (not pushed yet, or no access for this repository); skipping."
}

# Reads "<id>\t<reason>" lines on stdin and deletes those versions of $1.
# A "-" id passes a message through. A failed delete is reported as a
# warning and does not stop the others.
delete_versions() {
  local pkg="$1" id reason
  while IFS=$'\t' read -r id reason; do
    [[ -n "$id" ]] || continue
    if [[ "$id" == - ]]; then
      echo "$reason"
      continue
    fi
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
      echo "[dry-run] would delete $pkg version $id ($reason)"
      continue
    fi
    echo "Deleting $pkg version $id ($reason)"
    gh api -X DELETE "/orgs/$ORG/packages/container/$pkg/versions/$id" --silent \
      || echo "::warning::Could not delete $pkg version $id ($reason)"
  done
}

# jq definitions shared by all programs below. Shell values are only ever
# passed with --arg/--argjson; $targets and $arches must always be set.
JQ_LIB='
  def cache_tag_of($s): startswith("dev-" + $s + "-")
    and (ltrimstr("dev-" + $s + "-") | test("^(" + $targets + ")-(" + $arches + ")$"));
  # Deletes a version only if all its tags satisfy f; otherwise warns.
  def emit(f; $reason):
    if all(.tags[]; f) then "\(.id)\t\($reason)"
    else "-\t::warning::Keeping version \(.id): it also carries tags \(.tags | join(", "))"
    end;
'

# Runs jq program $1 (appended to JQ_LIB) over the versions on stdin.
select_versions() {
  local program="$1"
  shift
  jq -rs --arg targets "$CACHE_TARGETS" --arg arches "$CACHE_ARCHES" "$@" "$JQ_LIB $program"
}

# Deletes the versions tagged <slug> in the dev packages and the cache tags of
# the branch. Versions that also carry other tags are kept.
cleanup() {
  local s pkg rc out
  s="$(slug "$1")"
  echo "Cleaning up images of $1 (slug $s)"
  for pkg in $DEV_PACKAGES; do
    rc=0; out="$(versions "$pkg")" || rc=$?
    [[ $rc -eq 3 ]] && { skip_missing "$pkg"; continue; }
    [[ $rc -eq 0 ]] || return "$rc"
    select_versions '.[] | select(any(.tags[]; . == $s)) | emit(. == $s; $reason)' \
      --arg s "$s" --arg reason "cleanup of $1" <<<"$out" | delete_versions "$pkg"
  done
  rc=0; out="$(versions "$CACHE_PACKAGE")" || rc=$?
  [[ $rc -eq 3 ]] && { skip_missing "$CACHE_PACKAGE"; return 0; }
  [[ $rc -eq 0 ]] || return "$rc"
  select_versions '.[] | select(any(.tags[]; cache_tag_of($s))) | emit(cache_tag_of($s); $reason)' \
    --arg s "$s" --arg reason "cleanup of $1" <<<"$out" | delete_versions "$CACHE_PACKAGE"
}

cmd="${1:-}"
case "$cmd" in
  slug) slug "${2:?branch required}" ;;
  cleanup) cleanup "${2:?branch required}" ;;
  *) echo "usage: $0 slug|cleanup <branch>" >&2; exit 2 ;;
esac
