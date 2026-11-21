#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Prints true if <tag> is the highest stable release among the tags on
# stdin, otherwise false. Stable is vX.Y.Z or its patch build vX.Y.Z-N;
# prereleases (v9.3.5-rc.1) are never latest. Only the latest release
# moves :latest and the GitHub "latest" flag, so a 9.3.x patch tagged
# from stable-9.3 after 9.4.0 does not take them over.
# Usage: git tag -l 'v*' | is-latest.sh <tag>
set -euo pipefail

tag="$1"
stable='^v[0-9]+\.[0-9]+\.[0-9]+(-[1-9][0-9]*)?$'

if [[ ! "$tag" =~ $stable ]]; then
  echo false
  exit 0
fi

highest="$({ grep -E "$stable" || true; echo "$tag"; } | sort -V | tail -n 1)"
if [[ "$highest" == "$tag" ]]; then echo true; else echo false; fi
