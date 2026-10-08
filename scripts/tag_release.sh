#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found at $VERSION_FILE"
    exit 1
fi

VERSION_FILE_CONTENT="$(cat "$VERSION_FILE" | tr -d '[:space:]')"

# Strip optional suffix (e.g. -rc.1)
VERSION="${VERSION_FILE_CONTENT%%-*}"

# Validate semver format (major.minor.patch)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: VERSION '$VERSION' is not valid semver (expected X.Y.Z)"
    exit 1
fi

# Parse arguments
DRY_RUN=0
PRE_ID=""
PUSH=0

usage() {
    echo "Usage: $0 [-p PRE_ID] [--dry-run] [--push]"
    echo ""
    echo "Tags the main repo and all submodules with vVERSION[-PRE_ID]"
    echo ""
    echo "Options:"
    echo "  -p, --pre-id ID            Pre-release identifier, e.g. rc.1 (default: none)"
    echo "  --dry-run                  Print tags without creating them"
    echo "  --push                     Push tags to remote after creating"
    echo "  -h, --help                 Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pre-id)
            PRE_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --push)
            PUSH=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# vX.Y.Z is a stable release, vX.Y.Z-PRE_ID a pre-release. A broken release
# gets a new patch version instead of a rebuild tag.
if [ -n "$PRE_ID" ]; then
    TAG="v${VERSION}-${PRE_ID}"
else
    TAG="v${VERSION}"
fi

tag_repo() {
    local repo_path="$1"
    local repo_name="$2"
    local tag="$3"

    if git -C "$repo_path" rev-parse "$tag" >/dev/null 2>&1; then
        echo "  SKIP $repo_name — tag $tag already exists"
    else
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [DRY RUN] Would tag $repo_name at $(git -C "$repo_path" rev-parse --short HEAD) as $tag"
        else
            git -C "$repo_path" tag -a "$tag" -m "Release $tag"
            echo "  Tagged $repo_name at $(git -C "$repo_path" rev-parse --short HEAD) as $tag"
        fi
    fi

    if [ "$PUSH" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
        git -C "$repo_path" push origin "$tag"
        echo "  Pushed $tag for $repo_name"
    fi
}

echo "Tagging release: $TAG"
echo ""

# Tag main repository
echo "Main repository:"
tag_repo "$REPO_ROOT" "DocumentServer" "$TAG"
echo ""

# Tag each submodule
echo "Submodules:"
git -C "$REPO_ROOT" submodule foreach --quiet 'echo $sm_path' | while read -r sm_path; do
    sm_full_path="$REPO_ROOT/$sm_path"
    tag_repo "$sm_full_path" "$sm_path" "$TAG"
done

echo ""
echo "Done."