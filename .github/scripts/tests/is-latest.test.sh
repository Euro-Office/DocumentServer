#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests .github/scripts/is-latest.sh.
# Run: .github/scripts/tests/is-latest.test.sh
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../is-latest.sh"
fail=0

# check <tag> <existing tags, space separated> <expected>
check() {
  local got
  got="$(tr ' ' '\n' <<<"$2" | "$script" "$1")"
  if [[ "$got" != "$3" ]]; then
    echo "FAIL: $1 with [$2]: got $got, want $3"
    fail=1
  fi
}

check v9.3.9      "v9.3.8 v9.3.9"                      true
check v9.3.10     "v9.3.9 v9.4.0 v9.3.10"              false
check v9.3.10     "v9.3.9 v9.3.10 v9.4.0-rc.1"         true
check v9.4.0      "v9.3.10 v9.4.0"                     true
check v9.3.9-1    "v9.3.9 v9.3.9-1"                    true
check v9.3.9      "v9.3.9 v9.3.9-1"                    false
check v9.3.9-10   "v9.3.9-2 v9.3.9-10"                 true
check v9.4.0-rc.1 "v9.3.9 v9.4.0-rc.1"                 false
check v9.3.9      "v9.3.9 v9.3.10-hotfix.1"            true
check v9.3.9      ""                                   true

[[ $fail -eq 0 ]] && echo "is-latest: all tests passed"
exit "$fail"
