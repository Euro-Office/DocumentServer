#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Tests bake-overrides.sh: every cached target of build/docker-bake.hcl gets
# cache overrides, and nothing else does, without any target list in the
# scripts. Needs docker buildx (no daemon access) and jq.
# Run: .github/scripts/tests/bake-overrides.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/../../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { echo "FAIL: $1"; fail=1; }

run_overrides() { # run_overrides <env assignments...>; prints the "set" lines
  : >"$tmp/out"
  env GITHUB_OUTPUT="$tmp/out" CACHE_REF='reg/pkg:scope-{target}-amd64' "$@" "$here/../bake-overrides.sh"
  sed '1d;$d' "$tmp/out"
}

# Independent of cache-lib.sh: the targets are the `target "x"` blocks of the
# HCL, minus the dummy base image and abstract `_` templates.
mapfile -t expected < <(grep -oE '^target "[^"]+"' "$root/build/docker-bake.hcl" | cut -d'"' -f2 \
  | grep -vx -e brand-icons -e "_.*" | sort)
[[ ${#expected[@]} -gt 0 ]] || { echo "FAIL: no targets in the HCL"; exit 1; }

lines="$(run_overrides PUBLISHED=standalone SKIP=develop)"

for t in "${expected[@]}"; do
  if [[ "$t" == develop ]]; then
    grep -q "^develop\." <<<"$lines" && ok "skipped target develop has overrides"
    continue
  fi
  grep -qxF "${t}.cache-from=type=registry,ref=reg/pkg:scope-${t}-amd64" <<<"$lines" || ok "no cache-from for $t"
  grep -qxF "${t}.cache-to=type=registry,ref=reg/pkg:scope-${t}-amd64,mode=max" <<<"$lines" || ok "no cache-to for $t"
done

# Nothing for targets that are not in the HCL.
while IFS= read -r t; do
  [[ " ${expected[*]} " == *" $t "* ]] || ok "overrides for unknown target $t"
done < <(grep -oE '^[a-z0-9-]+\.' <<<"$lines" | tr -d . | sort -u)

# The caller sets tags and output of published targets; all others get empty tags.
grep -qx 'standalone.tags=' <<<"$lines" && ok "published target got empty tags"
grep -qx 'core.tags=' <<<"$lines" || ok "unpublished target has no empty tags"
grep -qx '\*.context=..' <<<"$lines" || ok "context override missing"

# A new target in a bake file is picked up without touching the scripts.
sed 's/^target "standalone" {/target "brand-new" {\n  dockerfile-inline = "FROM scratch"\n}\n\ntarget "standalone" {/' \
  "$root/build/docker-bake.hcl" >"$tmp/extra.hcl"
grep -qx 'brand-new.cache-to=.*' <<<"$(run_overrides BAKE_FILE="$tmp/extra.hcl" SKIP=develop)" \
  || ok "new target in the bake file was not picked up"

[[ $fail == 0 ]] && echo "bake-overrides tests passed"
exit "$fail"
