#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests that float-submodules.sh moves a shallow, pinned submodule to the head
# of its default branch, as after actions/checkout with submodules.
# Run: .github/scripts/tests/float-submodules.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
  GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=test \
  GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com

commit() { git -C "$1" commit -q --allow-empty -m "$2"; }

git init -q -b main "$tmp/leaf"
commit "$tmp/leaf" leaf-old
git init -q -b main "$tmp/sub"
git -C "$tmp/sub" submodule add -q "file://$tmp/leaf" leaf
commit "$tmp/sub" pinned
git init -q -b main "$tmp/super"
git -C "$tmp/super" submodule add -q "file://$tmp/sub" sub
commit "$tmp/super" "add sub"

# sub's main moves on and bumps its nested leaf; leaf's main moves on further.
commit "$tmp/leaf" leaf-pinned-by-sub
expected_leaf="$(git -C "$tmp/leaf" rev-parse main)"
git -C "$tmp/sub/leaf" pull -q
git -C "$tmp/sub" add leaf
commit "$tmp/sub" merged-later
commit "$tmp/leaf" leaf-not-pinned
expected="$(git -C "$tmp/sub" rev-parse main)"
git -C "$tmp/sub" switch -q -c feature
commit "$tmp/sub" not-merged
git -C "$tmp/sub" switch -q main

git clone -q "file://$tmp/super" "$tmp/ci"
git -C "$tmp/ci" submodule update -q --init --recursive --depth=1
(cd "$tmp/ci" && "$here/../float-submodules.sh" >/dev/null)

fail=0
actual="$(git -C "$tmp/ci/sub" rev-parse HEAD)"
[[ "$actual" == "$expected" ]] || { echo "FAIL: sub is at $actual, expected the head of main $expected"; fail=1; }
actual_leaf="$(git -C "$tmp/ci/sub/leaf" rev-parse HEAD)"
[[ "$actual_leaf" == "$expected_leaf" ]] || { echo "FAIL: sub/leaf is at $actual_leaf, expected sub's pin $expected_leaf"; fail=1; }

[[ $fail == 0 ]] && echo "float-submodules tests passed"
exit "$fail"
