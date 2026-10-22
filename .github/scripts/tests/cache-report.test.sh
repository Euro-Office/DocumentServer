#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Covers: .github/scripts/cache-report.sh
#
# Tests the render step of cache-report.sh against a canned build record.
# Run: .github/scripts/tests/cache-report.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../cache-report.sh"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/logs"

# `docker buildx history ls --format json`, one record per bake target.
cat >"$dir/records.jsonl" <<'E'
{"cached_steps":2,"completed_at":"2026-10-21T10:30:05.5Z","completed_steps":9,"created_at":"2026-10-21T10:00:00.25Z","name":"core","ref":"builder/builder0/aaa","status":"Completed","total_steps":9}
{"cached_steps":0,"completed_at":"2026-10-21T10:00:42Z","completed_steps":4,"created_at":"2026-10-21T10:00:00Z","name":"web-apps","ref":"builder/builder0/bbb","status":"Completed","total_steps":4}
E

# `docker buildx history logs --progress plain`, in the line formats of a real
# dev/redis run (steps are prefixed with [target] in bake output).
cat >"$dir/logs/1.log" <<'E'
#1 [internal] load build definition from core.bake.Dockerfile
#1 DONE 0.1s

#55 [core] importing cache manifest from ghcr.io/euro-office/documentserver-build-cache:dev-redis-e75cf5-core-amd64
#55 ERROR: failed to configure registry cache importer: ghcr.io/euro-office/documentserver-build-cache:dev-redis-e75cf5-core-amd64: not found

#56 [core] importing cache manifest from ghcr.io/euro-office/documentserver-build-cache:dev-x-1a2b3c-core-amd64
#56 inferred cache manifest type: application/vnd.oci.image.manifest.v1+json done
#56 DONE 1.2s

#60 [core] [builder 2/4] RUN apt-get update
#60 CACHED

#63 [core] [builder 5/5] RUN echo "<b>a|b</b>"
#63 DONE 2.0s

#61 [core] [builder 3/4] RUN git clone https://github.com/microsoft/vcpkg.git
#61 DONE 12.5s

#62 [core] [builder 4/4] RUN ./build.sh
#62 DONE 5700.0s

#232 [core] exporting cache to registry
#232 preparing build cache for export 360.6s done
#232 DONE 231.1s
E
cat >"$dir/logs/2.log" <<'E'
#3 [1/2] RUN npm ci
#3 CACHED

#4 [2/2] RUN npm run build
#4 DONE 61.0s
E

out="$dir/summary.md"
GITHUB_STEP_SUMMARY="$out" TITLE=amd64 "$script" render "$dir"
json="$dir/cache-report.json"

fail=0
check() { # check <description> <jq filter> <expected>
  local got
  got="$(jq -c "$2" "$json")"
  if [[ "$got" != "$3" ]]; then
    echo "FAIL: $1: got $got, expected $3"
    fail=1
  fi
}
has() { # has <description> <fixed string in summary>
  grep -qF -- "$2" "$out" || { echo "FAIL: summary lacks: $1 ($2)"; fail=1; }
}

check "core steps" '.targets[] | select(.target == "core") | [.cached, .executed, .failed]' '[1,3,0]'
check "web-apps steps (record name when no [target] prefix)" \
  '.targets[] | select(.target == "web-apps") | [.cached, .executed]' '[1,1]'
check "internal steps are not build steps" '[.targets[].target]' '["core","web-apps"]'
check "import results" '[.imports[] | .found]' '[false,true]'
check "import tag" '.imports[0].tag' '"dev-redis-e75cf5-core-amd64"'
check "export duration comes from DONE" '.exports[0].seconds' '231.1'
# tenths, because jq 1.6 and 1.7 print whole floats differently
check "slowest is sorted" '[.slowest[].seconds * 10 | round]' '[57000,610,125,20]'
check "build duration" '[.builds[].duration_s]' '[1805,42]'

has "heading" '### Build cache report (amd64)'
# shellcheck disable=SC2016 # the backticks are literal markdown
has "not found import" '| core | `dev-redis-e75cf5-core-amd64` | not found | - |'
has "found import" '| found | 1.2s |'
has "export row" '| core | done | 3m 51s |'
has "build duration" '| 30m 5s |'
# Step names come from Dockerfiles: markup must be neutralised.
if grep -qF '<b>' "$out"; then echo "FAIL: raw HTML in summary"; fail=1; fi
has "escaped pipe" 'a\|b'
has "escaped html" '&lt;b&gt;a'

# Lists are capped.
for i in $(seq 1 40); do
  echo "#$((100 + i)) [t$i] [1/1] RUN step $i"
  echo "#$((100 + i)) DONE $i.0s"
done >"$dir/logs/2.log"
: >"$out"
GITHUB_STEP_SUMMARY="$out" "$script" render "$dir"
# header + MAX_SLOWEST (15) rows; the separator line starts with "|-"
rows="$(awk '/^#### Slowest steps/{f=1;next} f&&/^\| /{n++} END{print n}' "$out")"
[[ "$rows" == 16 ]] || { echo "FAIL: slowest rows (header + rows) = $rows, expected 16"; fail=1; }
has "cap note" 'more (see cache-report.json)'

[[ $fail == 0 ]] && echo "cache-report tests passed"
exit "$fail"
