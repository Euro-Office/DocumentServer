#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Covers: .github/scripts/check-fallback-cache.sh
#
# Tests check-fallback-cache.sh with a stubbed docker command.
# Run: .github/scripts/tests/check-fallback-cache.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../check-fallback-cache.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# docker: `buildx imagetools inspect <ref>` succeeds if the ref is listed in $TMP/refs.
cat >"$tmp/bin/docker" <<'E2'
#!/usr/bin/env bash
[[ "$1 $2 $3" == "buildx imagetools inspect" ]] || { echo "unexpected docker call: $*" >&2; exit 1; }
grep -qxF "$4" "$TMP/refs"
E2
chmod +x "$tmp/bin/docker"

fail=0
expect() { # expect <description> <got> <want>
  [[ "$2" == "$3" ]] || { echo "FAIL: $1: got '$2', want '$3'"; fail=1; }
}

run() { # run [env...]; sets $out_ref and $log, returns the script's status
  local rc=0
  : >"$tmp/out"
  log="$(env PATH="$tmp/bin:$PATH" TMP="$tmp" GITHUB_OUTPUT="$tmp/out" \
    FALLBACK_REF='reg/cache:main-{target}-buildcache-amd64' "$@" "$script" 2>&1)" || rc=$?
  out_ref="$(sed -n 's/^ref=//p' "$tmp/out")"
  return "$rc"
}

# The probe target (core by default) decides; the template is passed on unchanged.
echo 'reg/cache:main-core-buildcache-amd64' >"$tmp/refs"
run
expect "existing cache" "$out_ref" 'reg/cache:main-{target}-buildcache-amd64'
grep -q '^::notice::Fallback cache' <<<"$log" || { echo "FAIL: no notice"; fail=1; }

# A missing cache is a warning with an empty ref and success.
: >"$tmp/refs"
run
expect "missing cache" "$out_ref" ""
grep -q '^::warning::' <<<"$log" || { echo "FAIL: no warning"; fail=1; }

# Another probe target.
echo 'reg/cache:main-sdkjs-buildcache-amd64' >"$tmp/refs"
run PROBE_TARGET=sdkjs
expect "probe target" "$out_ref" 'reg/cache:main-{target}-buildcache-amd64'

# Bad input is an error.
if run FALLBACK_REF='reg/cache:x;rm -rf /' 2>/dev/null; then echo "FAIL: invalid ref accepted"; fail=1; fi

[[ $fail == 0 ]] && echo "check-fallback-cache tests passed"
exit "$fail"
