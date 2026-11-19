#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Reads `git diff --raw` on stdin and fails unless every entry moves the
# pointer of one of the submodules given as arguments: status M with old and
# new mode 160000. Additions, deletions, type changes, renames and any other
# path fail, and so does an empty diff.
# Usage: git diff --raw --no-abbrev BASE HEAD | pointer-only-diff.sh core sdkjs ...
set -euo pipefail

is_submodule() {
  local p
  for p in "${submodules[@]}"; do [[ "$p" == "$1" ]] && return 0; done
  return 1
}

submodules=("$@")
entries=0
bad=0
while IFS=$'\t' read -r meta path; do
  [[ -n "$meta" ]] || continue
  entries=$((entries + 1))
  read -r old_mode new_mode _ _ status <<<"${meta#:}"
  if [[ "$old_mode $new_mode $status" != "160000 160000 M" ]] || ! is_submodule "$path"; then
    echo "not a submodule pointer update: $old_mode $new_mode $status $path"
    bad=1
  fi
done

if [[ $entries == 0 ]]; then
  echo "empty diff"
  exit 1
fi
exit "$bad"
