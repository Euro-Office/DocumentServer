#!/bin/bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Points snap/local/release at the latest stable release. Needs gh and GH_REPO.
set -euo pipefail

file=$(dirname "$0")/local/release
# shellcheck source=snap/local/release
. "$file"
latest=$(gh api "repos/$GH_REPO/releases/latest")
tag=$(jq -r .tag_name <<< "$latest")
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]] || { echo "Not a stable release: $tag"; exit 0; }
# The deb version: vX.Y.Z is packaged as X.Y.Z-0, the patch build vX.Y.Z-N as X.Y.Z-N.
version=${tag#v}
[[ "$version" == *-* ]] || version=$version-0
if [ "$(printf '%s\n%s\n' "$RELEASE" "$version" | sort -V | tail -n1)" = "$RELEASE" ]; then
    echo "$RELEASE is up to date"
    exit 0
fi

checksum() {
    jq -er --arg name "euro-office-documentserver_${version}_$1.deb" \
        '.assets[] | select(.name == $name) | .digest | select(startswith("sha256:")) | ltrimstr("sha256:")' <<< "$latest"
}
amd64=$(checksum amd64)
arm64=$(checksum arm64)
sed -i -e "s/^RELEASE=.*/RELEASE=$version/" -e "s/^SNAP_REVISION=.*/SNAP_REVISION=1/" \
    -e "s/^SHA256_AMD64=.*/SHA256_AMD64=$amd64/" -e "s/^SHA256_ARM64=.*/SHA256_ARM64=$arm64/" "$file"
echo "Updated to $version"
