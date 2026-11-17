#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests build/scripts/lib/log-dirs.sh against the shipped supervisor confs:
# an empty $EO_LOG (fresh bind mount) must get every program's log directory.
# Run: .github/scripts/tests/entrypoint-log-dirs.test.sh
#
# The sh -c snippet is meant to stay unexpanded.
# shellcheck disable=SC2016
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/../../.."
lib="$root/build/scripts/lib/log-dirs.sh"
confs="$root/build/configs/standalone/supervisor"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
for sh in dash bash; do
  command -v "$sh" >/dev/null || continue
  log="$tmp/$sh/log"
  mkdir -p "$log"
  EO_LOG="$log" "$sh" -c '. "$1"; ensure_log_dirs "$2"' sh "$lib" "$confs"

  for dir in adminpanel converter docservice metrics; do
    [[ -d "$log/$dir" ]] || { echo "FAIL ($sh): $dir not created"; fail=1; }
  done
  # Nothing may be created outside $EO_LOG.
  extra="$(cd "$tmp/$sh" && find . -mindepth 1 -maxdepth 1 ! -name log)"
  [[ -z "$extra" ]] || { echo "FAIL ($sh): created outside EO_LOG: $extra"; fail=1; }
done

[[ $fail -eq 0 ]] && echo "OK: entrypoint-log-dirs"
exit $fail
