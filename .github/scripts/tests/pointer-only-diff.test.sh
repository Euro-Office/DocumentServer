#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests which `git diff --raw` outputs pointer-only-diff.sh accepts.
# Run: .github/scripts/tests/pointer-only-diff.test.sh
set -euo pipefail

check="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pointer-only-diff.sh"
a=1111111111111111111111111111111111111111
b=2222222222222222222222222222222222222222
z=0000000000000000000000000000000000000000
fail=0

expect() {
  local want="$1" name="$2" diff="$3" got=0
  printf '%b' "$diff" | "$check" core sdkjs >/dev/null || got=1
  [[ "$got" == "$want" ]] || { echo "FAIL: $name (exit $got, expected $want)"; fail=1; }
}

expect 0 "pointer updates" ":160000 160000 $a $b M\tcore\n:160000 160000 $a $b M\tsdkjs\n"
expect 1 "submodule deleted" ":160000 000000 $a $z D\tcore\n"
expect 1 "submodule added" ":000000 160000 $z $b A\tcore\n"
expect 1 "submodule replaced by a file" ":160000 100644 $a $b T\tcore\n"
expect 1 "gitlink outside .gitmodules" ":160000 160000 $a $b M\tvendor/x\n"
expect 1 "regular file" ":160000 160000 $a $b M\tcore\n:100644 100644 $a $b M\t.gitmodules\n"
expect 1 "empty diff" ""

[[ $fail == 0 ]] && echo "pointer-only-diff tests passed"
exit "$fail"
