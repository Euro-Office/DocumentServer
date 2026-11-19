#!/usr/bin/env bash
# Pin submodules on a dev/* branch to exact commits for the dev image pipeline.
#
#   scripts/dev-pin.sh [--push] <submodule>=<branch|tag|sha> [...]
#   scripts/dev-pin.sh --list
#
# Each ref is resolved against the submodule's remote repository (URL from
# .gitmodules), the gitlink is updated in the index (no submodule checkout
# needed) and all pins are recorded in a single commit. See docs/dev-images.md.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/dev-pin.sh [--push] <submodule>=<branch|tag|sha> [...]
  scripts/dev-pin.sh --list

Pins each <submodule> to the commit that <branch|tag|sha> resolves to in the
submodule's remote repository and commits all pins in one commit. Must be run
on a clean dev/* branch.

Options:
  --push   push the branch to origin after committing
  --list   print every submodule, its pinned SHA and whether that SHA is on
           the submodule's default branch
  -h       show this help
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$top"
[[ -f .gitmodules ]] || die "no .gitmodules in $top"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Prints the submodule name whose path is $1, or nothing.
submodule_name() {
  local key path
  while read -r key path; do
    if [[ "$path" == "$1" ]]; then
      key="${key#submodule.}"
      printf '%s\n' "${key%.path}"
      return
    fi
  done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')
}

submodule_url() {
  git config -f .gitmodules --get "submodule.$1.url"
}

# Prints the gitlink SHA recorded in HEAD for path $1, or nothing.
pinned_sha() {
  git ls-tree HEAD -- "$1" | awk '$1 == "160000" { print $3 }'
}

# Commit-only bare clone of a submodule repo (cached per run).
# Extra arguments are passed to git clone.
meta_clone() {
  local path="$1" url="$2"
  shift 2
  local dir="$tmp/${path//\//_}.git"
  if [[ ! -d "$dir" ]]; then
    git clone --quiet --bare --no-tags --filter=tree:0 "$@" "$url" "$dir" >&2 \
      || die "cannot clone $url"
  fi
  printf '%s\n' "$dir"
}

list_pins() {
  local path name url sha meta branch status
  printf '%-30s %-40s %s\n' SUBMODULE PINNED ON-DEFAULT-BRANCH
  while read -r _ path; do
    name="$(submodule_name "$path")"
    url="$(submodule_url "$name")"
    sha="$(pinned_sha "$path")"
    if [[ -z "$sha" ]]; then
      printf '%-30s %-40s %s\n' "$path" "-" "no gitlink in HEAD"
      continue
    fi
    meta="$(meta_clone "$path" "$url" --single-branch)"
    branch="$(git -C "$meta" symbolic-ref --short HEAD)"
    if git -C "$meta" cat-file -e "$sha^{commit}" 2>/dev/null \
      && git -C "$meta" merge-base --is-ancestor "$sha" HEAD; then
      status="yes ($branch)"
    else
      status="NO (not on $branch)"
    fi
    printf '%-30s %-40s %s\n' "$path" "$sha" "$status"
  done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')
}

# Resolves $3 in the remote repo $2 (submodule path $1) to a full commit SHA.
resolve_ref() {
  local path="$1" url="$2" ref="$3" out sha meta
  out="$(git ls-remote "$url" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}")" \
    || die "cannot reach $url"
  # Prefer the peeled commit of an annotated tag, then the branch, then the tag.
  sha="$(awk -v r="refs/tags/$ref^{}" '$2 == r { print $1 }' <<<"$out")"
  [[ -n "$sha" ]] || sha="$(awk -v r="refs/heads/$ref" '$2 == r { print $1 }' <<<"$out")"
  [[ -n "$sha" ]] || sha="$(awk -v r="refs/tags/$ref" '$2 == r { print $1 }' <<<"$out")"
  if [[ -n "$sha" ]]; then
    printf '%s\n' "$sha"
    return
  fi
  if [[ "$ref" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
    # A SHA counts only if it is reachable from a branch or tag on the remote.
    meta="$(meta_clone "$path" "$url")"
    git -C "$meta" fetch --quiet --filter=tree:0 origin 'refs/tags/*:refs/tags/*' >&2 \
      || die "cannot fetch tags from $url"
    if sha="$(git -C "$meta" rev-parse -q --verify "$ref^{commit}")"; then
      printf '%s\n' "$sha"
      return
    fi
  fi
  die "$path: '$ref' is not a branch, tag or commit reachable on $url (local-only commits cannot be built in CI; push them first)"
}

push=false
list=false
pins=()
for arg in "$@"; do
  case "$arg" in
    --push) push=true ;;
    --list) list=true ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option $arg" ;;
    *=*) pins+=("$arg") ;;
    *) usage >&2; die "expected <submodule>=<ref>, got '$arg'" ;;
  esac
done

if [[ "$list" == true ]]; then
  [[ ${#pins[@]} -eq 0 && "$push" == false ]] || die "--list takes no other arguments"
  list_pins
  exit 0
fi

[[ ${#pins[@]} -gt 0 ]] || { usage >&2; exit 1; }

branch="$(git symbolic-ref --short -q HEAD || true)"
[[ "$branch" == dev/* ]] || die "current branch '${branch:-detached HEAD}' is not a dev/* branch"
# Submodule checkouts lagging behind their gitlink are not "dirty": this
# script never touches them. Anything staged (including gitlinks) is.
if [[ -n "$(git status --porcelain --ignore-submodules=all)" ]] \
  || ! git diff --cached --quiet --ignore-submodules=none; then
  die "working tree is not clean; commit or stash your changes first"
fi

summary=()
for pin in "${pins[@]}"; do
  path="${pin%%=*}"
  ref="${pin#*=}"
  path="${path%/}"
  [[ -n "$path" && -n "$ref" ]] || die "invalid pin '$pin'"
  name="$(submodule_name "$path")"
  [[ -n "$name" ]] || die "'$path' is not a submodule listed in .gitmodules"
  url="$(submodule_url "$name")"
  [[ -n "$url" ]] || die "no url for submodule '$name' in .gitmodules"

  sha="$(resolve_ref "$path" "$url" "$ref")"
  old="$(pinned_sha "$path")"
  if [[ "$sha" == "$old" ]]; then
    printf '%s: already pinned to %s\n' "$path" "$sha"
    continue
  fi
  git update-index --cacheinfo "160000,$sha,$path"
  printf '%s: %s -> %s (%s)\n' "$path" "${old:-none}" "$sha" "$ref"
  if [[ "$sha" == "$ref"* ]]; then
    summary+=("$path=${sha:0:8}")
  else
    summary+=("$path=$ref@${sha:0:8}")
  fi
done

if [[ ${#summary[@]} -eq 0 ]]; then
  echo "Nothing to commit."
else
  msg="dev: pin $(printf '%s, ' "${summary[@]}")"
  git commit --quiet -m "${msg%, }"
  git log -1 --format='Committed %h: %s'
fi

if [[ "$push" == true ]]; then
  git push -u origin "$branch"
fi
