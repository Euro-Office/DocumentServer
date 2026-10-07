#!/usr/bin/env bash
# Helpers for .github/workflows/dev-images.yml.
#
#   dev-images.sh slug <branch>      print the image tag slug of a dev/* branch
#   dev-images.sh cleanup <branch>   delete the images and caches of a branch
#                                    now (manual use only, not called by the
#                                    workflow; the sweep catches deleted branches)
#   dev-images.sh sweep              apply the retention rules to all dev images
#
# cleanup/sweep use the gh CLI (GH_TOKEN) and read ORG, DEV_PACKAGES,
# CACHE_PACKAGE and, for sweep, REPO, KEEP_VERSIONS, MAX_AGE_DAYS and
# UNTAGGED_MIN_AGE_HOURS from the environment. DRY_RUN=1 only prints what
# would be deleted.
#
# Tags written by the build job:
#   <dev package>:<slug>                  moving pointer to the newest build
#   <dev package>:<slug>-<sha8>           one per DocumentServer commit
#   <CACHE_PACKAGE>:dev-<slug>-<target>-<arch>

# Single-quoted strings below are jq programs; their $vars are jq variables.
# shellcheck disable=SC2016

set -euo pipefail
export LC_ALL=C

# Bake targets that get a registry cache ref (see dev-images.yml).
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

# Prints one JSON object {id, created_at, tags} per version of package $1.
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
    --jq '.[] | {id, created_at, tags: (.metadata.container.tags // [])}'
}

skip_missing() {
  echo "::notice::Package $1 not found (not pushed yet, or no access for this repository); skipping."
}

# Reads "<id>\t<reason>" lines on stdin and deletes those versions of $1.
# A "-" id passes a message through. Failures are reported as warnings; the
# next sweep retries them.
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
  def created: .created_at | fromdateiso8601;
  def dev_tag($s): . == $s or (startswith($s + "-") and (ltrimstr($s + "-") | test("^[0-9a-f]{8}$")));
  def cache_re: "^dev-(?<s>.+-[0-9a-f]{6})-(" + $targets + ")-(" + $arches + ")$";
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

# Immediate cleanup of one branch, for manual use (see docs/dev-images.md).
# The workflow does not call this; the daily sweep removes images of deleted
# branches.
cleanup() {
  local s pkg rc out
  s="$(slug "$1")"
  echo "Cleaning up images of $1 (slug $s)"
  for pkg in $DEV_PACKAGES; do
    rc=0; out="$(versions "$pkg")" || rc=$?
    [[ $rc -eq 3 ]] && { skip_missing "$pkg"; continue; }
    [[ $rc -eq 0 ]] || return "$rc"
    select_versions '.[] | select(any(.tags[]; dev_tag($s))) | emit(dev_tag($s); $reason)' \
      --arg s "$s" --arg reason "cleanup of $1" <<<"$out" | delete_versions "$pkg"
  done
  rc=0; out="$(versions "$CACHE_PACKAGE")" || rc=$?
  [[ $rc -eq 3 ]] && { skip_missing "$CACHE_PACKAGE"; return 0; }
  [[ $rc -eq 0 ]] || return "$rc"
  select_versions '.[] | select(any(.tags[]; cache_tag_of($s))) | emit(cache_tag_of($s); $reason)' \
    --arg s "$s" --arg reason "cleanup of $1" <<<"$out" | delete_versions "$CACHE_PACKAGE"
}

sweep() {
  local live listed_at pkg rc out
  : "${KEEP_VERSIONS:?}" "${MAX_AGE_DAYS:?}" "${UNTAGGED_MIN_AGE_HOURS:?}" "${REPO:?}"
  # Slugs of all dev/* branches that still exist. Versions created after
  # listed_at - 1h may belong to a branch created since and are never
  # treated as orphaned.
  listed_at="$(date +%s)"
  live="$(gh api --paginate "/repos/$REPO/git/matching-refs/heads/dev/" --jq '.[].ref' \
    | while read -r ref; do slug "$ref"; done | jq -Rsc 'split("\n") | map(select(. != ""))')"
  echo "Live dev branch slugs: $live"

  for pkg in $DEV_PACKAGES; do
    rc=0; out="$(versions "$pkg")" || rc=$?
    [[ $rc -eq 3 ]] && { skip_missing "$pkg"; continue; }
    [[ $rc -eq 0 ]] || return "$rc"
    # Each version belongs to the slug parsed from its tags. Per slug, versions
    # are ranked newest first; the version carrying the moving <slug> tag is
    # always kept while its branch exists. Untagged versions are leftovers of
    # rebuilds: dev images are single manifests (attestations disabled, checked
    # by the build job), so they are never children of a live image.
    select_versions '
      def parse:
        if test("^.+-[0-9a-f]{6}-[0-9a-f]{8}$") then {slug: sub("-[0-9a-f]{8}$"; ""), moving: false}
        elif test("^.+-[0-9a-f]{6}$") then {slug: ., moving: true}
        else empty end;
      (.[] | select((.tags | length) == 0 and created < $now - $untagged_hours * 3600)
        | "\(.id)\tuntagged for more than \($untagged_hours) hours"),
      ([ .[] | ([.tags[] | parse]) as $p | select($p | length > 0)
         | {id, created_at, slug: $p[0].slug, moving: any($p[]; .moving)} ]
       | group_by(.slug)
       | map(sort_by(.created_at) | reverse | to_entries | map(.value + {rank: .key}))
       | flatten[]
       | . as $v
       | (if any($live[]; . == $v.slug) | not then
            (if ($v | created) < $listed_at - 3600 then "branch of \($v.slug) no longer exists" else empty end)
          elif $v.moving then empty
          elif $v.rank >= $keep then "\($v.slug): beyond newest \($keep)"
          elif ($v | created) < $now - $days * 86400 then "\($v.slug): older than \($days) days"
          else empty end) as $reason
       | "\($v.id)\t\($reason)")' \
      --argjson live "$live" --argjson listed_at "$listed_at" --argjson now "$(date +%s)" \
      --argjson keep "$KEEP_VERSIONS" --argjson days "$MAX_AGE_DAYS" \
      --argjson untagged_hours "$UNTAGGED_MIN_AGE_HOURS" <<<"$out" | delete_versions "$pkg"
  done

  # Build caches of deleted dev/* branches. Untagged cache versions are left
  # alone: the package is shared with build.yml, whose images have untagged
  # child manifests.
  rc=0; out="$(versions "$CACHE_PACKAGE")" || rc=$?
  [[ $rc -eq 3 ]] && { skip_missing "$CACHE_PACKAGE"; return 0; }
  [[ $rc -eq 0 ]] || return "$rc"
  select_versions '
    .[] | select(created < $listed_at - 3600
      and any(.tags[]; test(cache_re) and (capture(cache_re).s as $s | any($live[]; . == $s) | not)))
    | emit(test(cache_re); "branch no longer exists")' \
    --argjson live "$live" --argjson listed_at "$listed_at" <<<"$out" | delete_versions "$CACHE_PACKAGE"
}

cmd="${1:-}"
case "$cmd" in
  slug) slug "${2:?branch required}" ;;
  cleanup) cleanup "${2:?branch required}" ;;
  sweep) sweep ;;
  *) echo "usage: $0 slug|cleanup <branch> | sweep" >&2; exit 2 ;;
esac
