#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests build/scripts/lib/bool.sh, the boolean normalization shared by the
# standalone (dash) and orchestrated (bash) entrypoints. Every value must
# give the same result under each shell.
# Run: .github/scripts/tests/entrypoint-bool.test.sh
#
# The sh -c snippets and some test values are meant to stay unexpanded.
# shellcheck disable=SC2016
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/../../../build/scripts/lib/bool.sh"

fail=0
ok() { echo "FAIL: $1"; fail=1; }

shells=()
for sh in dash bash "bash --posix"; do
  command -v "${sh%% *}" >/dev/null && shells+=("$sh")
done
[[ ${#shells[@]} -ge 2 ]] || { echo "FAIL: need dash and bash"; exit 1; }

nl=$'\n'

# run <shell> <mode> <value>: prints "<exit code>|<resulting value>|<stderr>"
run() {
  local out err rc=0 cmd
  read -ra cmd <<<"$1"
  err="$(mktemp)"
  out="$(V="$3" "${cmd[@]}" -c '. "$1"; '"$2"' V; printf "%s" "$V"' sh "$lib" 2>"$err")" || rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$err")"
  rm -f "$err"
}

# check <mode> <value> <expected value | "exit"> [<warns>]
check() {
  local mode="$1" val="$2" want="$3" warns="${4:-}" sh got rc rest out stderr
  for sh in "${shells[@]}"; do
    got="$(run "$sh" "$mode" "$val")"
    rc="${got%%|*}"; rest="${got#*|}"; out="${rest%%|*}"; stderr="${rest#*|}"
    if [[ "$want" == exit ]]; then
      [[ "$rc" != 0 ]] || ok "$sh $mode '$val': expected exit, got '$out'"
      [[ "$stderr" == ERROR:* ]] || ok "$sh $mode '$val': no error message"
      continue
    fi
    [[ "$rc" == 0 ]] || { ok "$sh $mode '$val': exited $rc"; continue; }
    [[ "$out" == "$want" ]] || ok "$sh $mode '$val': expected '$want', got '$out'"
    if [[ -n "$warns" ]]; then
      [[ "$stderr" == WARNING:* ]] || ok "$sh $mode '$val': no warning"
    else
      [[ -z "$stderr" ]] || ok "$sh $mode '$val': unexpected output '$stderr'"
    fi
  done
}

for mode in normalize_bool require_bool; do
  for v in true True TRUE yes YES y Y on ON On 1; do
    check "$mode" "$v" true
  done
  for v in false False FALSE no NO n N off OFF 0; do
    check "$mode" "$v" false
  done
  # Surrounding whitespace, as left by env files and secrets with a newline.
  for v in " true" "true " "	true	" "true$nl" "${nl}true$nl" "true"$'\r\n'; do
    check "$mode" "$v" true
  done
  for v in " false " "false$nl"; do
    check "$mode" "$v" false
  done
  # Empty and blank values stay empty so ${VAR:-default} applies.
  for v in "" " " "$nl"; do
    check "$mode" "$v" ""
  done
done

# Unrecognized: lenient clears the value with a warning, strict refuses.
for v in enabled tru "t rue" 2 "true false" '$(echo true)' "'true'" '"true"'; do
  check normalize_bool "$v" "" warns
  check require_bool "$v" exit
done

# An unset variable stays unset-or-empty and does not warn.
for sh in "${shells[@]}"; do
  read -ra cmd <<<"$sh"
  got="$(env -u V "${cmd[@]}" -c '. "$1"; normalize_bool V; printf "%s" "${V-unset}"' sh "$lib" 2>&1)"
  [[ "$got" == "" || "$got" == unset ]] || ok "$sh: unset variable gave '$got'"
done

[[ $fail == 0 ]] && echo "OK: entrypoint-bool"
exit "$fail"
