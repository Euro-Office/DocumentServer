#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Runs the tests whose "# Covers:" files changed.
#
#   run-changed.sh all             run every tests/*.test.sh
#   git diff --name-only A B | run-changed.sh
#                                  run the tests that cover a changed file
#
# A test covers the files named in its "# Covers:" header line (repo-relative,
# space-separated), itself, and this runner. Changes to this runner or to the
# workflow that calls it (scripts-test.yml) run every test.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
cd "$root"

runner=".github/scripts/tests/run-changed.sh"
workflow=".github/workflows/scripts-test.yml"

changed=" "
if [[ "${1:-}" == all ]]; then
  changed=all
else
  while IFS= read -r f; do changed+="$f "; done
fi

failed=()
ran=0
for test in "$here"/*.test.sh; do
  rel="${test#"$root"/}"
  covers="$(sed -n 's/^# Covers: *//p' "$test" | head -n 1)"
  run=0
  if [[ "$changed" == all || "$changed" == *" $runner "* || "$changed" == *" $workflow "* ]]; then
    run=1
  else
    for f in $rel $covers; do
      [[ "$changed" == *" $f "* ]] && run=1
    done
  fi
  [[ $run == 1 ]] || continue
  ran=$((ran + 1))
  echo "::group::$rel"
  if bash "$test"; then echo "ok: $rel"; else failed+=("$rel"); fi
  echo "::endgroup::"
done

if [[ $ran == 0 ]]; then
  echo "No test covers the changed files."
fi
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "::error::Failed tests: ${failed[*]}"
  exit 1
fi
