#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests which cache tags dev-images.sh cleanup selects for a branch.
# Run: .github/scripts/tests/dev-images.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../dev-images.sh
source "$here/../dev-images.sh"

slug_a="foo-abc123"
versions='
{"id":1,"tags":["dev-foo-abc123-core-amd64"]}
{"id":2,"tags":["dev-foo-abc123-brand-new-target-arm64"]}
{"id":3,"tags":["dev-foo-abc123"]}
{"id":4,"tags":["dev-bar-111111-core-amd64"]}
{"id":5,"tags":["main-0123abc-core-buildcache-amd64"]}
{"id":6,"tags":["dev-foo-abc123-core-amd64","latest"]}
'

# shellcheck disable=SC2016 # jq program, $s is a jq variable
out="$(select_versions '.[] | select(any(.tags[]; cache_tag_of($s))) | emit(cache_tag_of($s); "x")' \
  --arg s "$slug_a" <<<"$versions")"

fail=0
deleted="$(grep -v '^-' <<<"$out" | cut -f1 | tr '\n' ' ')"
[[ "$deleted" == "1 2 " ]] || { echo "FAIL: deleted '$deleted', expected '1 2 '"; fail=1; }
grep -q 'Keeping version 6' <<<"$out" || { echo "FAIL: version with another tag must be kept with a warning"; fail=1; }

[[ $fail == 0 ]] && echo "dev-images tests passed"
exit "$fail"
