#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Checks that nginx compresses responses behind a reverse proxy: proxies send
# a Via header and nginx skips gzip for those unless gzip_proxied is set.
# Covers the package's ds-common.conf (deb, rpm, standalone image) and the
# orchestrated image, which replaces the directive with $NGINX_GZIP_PROXIED.
# Runs `nginx -t` on both results when nginx is installed.
# Run: .github/scripts/tests/nginx-gzip-proxied.test.sh
# The printf line writes a literal $NGINX_GZIP_PROXIED for envsubst.
# shellcheck disable=SC2016
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/../../.."
template="$root/document-server-package/common/documentserver/nginx/includes/ds-common.conf.m4"
dockerfile="$root/build/.docker/orchestrated.bake.Dockerfile"

[[ -f "$template" ]] || { echo "FAIL: $template missing (git submodule update --init document-server-package)"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
check_one() { # file expected-directive label
  local count
  count="$(grep -cE '^[[:space:]]*gzip_proxied[[:space:]]' "$1" || true)"
  [[ "$count" == 1 ]] || { echo "FAIL ($3): $count gzip_proxied directives, want 1"; fail=1; }
  grep -qE "^[[:space:]]*gzip_proxied $2;" "$1" || { echo "FAIL ($3): no 'gzip_proxied $2;'"; fail=1; }
}

nginx_test() { # ds-common.conf label
  command -v nginx >/dev/null || { echo "SKIP ($2): nginx not installed"; return; }
  mkdir -p "$tmp/n/logs"
  sed "s|^[[:space:]]*error_log.*|error_log $tmp/n/logs/error.log;|" "$1" > "$tmp/n/ds-common.conf"
  printf 'pid %s/n/nginx.pid;\nerror_log %s/n/logs/error.log;\nevents {}\nhttp { include %s/n/ds-common.conf; }\n' \
    "$tmp" "$tmp" "$tmp" > "$tmp/n/nginx.conf"
  nginx -t -q -p "$tmp/n" -c "$tmp/n/nginx.conf" || { echo "FAIL ($2): nginx -t"; fail=1; }
}

package="$tmp/package.conf"
m4 -D M4_NGINX_LOG=/var/log/nginx "$template" > "$package"
check_one "$package" any package
nginx_test "$package" package

# Orchestrated image: the Dockerfile's edit, then the proxy entrypoint's envsubst.
grep -qE '^[[:space:]]*NGINX_GZIP_PROXIED=any[[:space:]]' "$dockerfile" || { echo "FAIL (orchestrated): NGINX_GZIP_PROXIED default is not any"; fail=1; }
grep -qF "sed '/^\\s*gzip_proxied\\b/d' -i /etc/nginx/includes/ds-common.conf" "$dockerfile" \
  || { echo "FAIL (orchestrated): Dockerfile no longer drops the package's gzip_proxied before appending its own"; fail=1; }
orchestrated="$tmp/orchestrated.conf"
sed '/^[[:space:]]*gzip_proxied[[:space:]]/d' "$package" > "$orchestrated"
printf '\ngzip_proxied $NGINX_GZIP_PROXIED;\n' >> "$orchestrated"
NGINX_GZIP_PROXIED=any envsubst < "$orchestrated" > "$orchestrated.env"
check_one "$orchestrated.env" any orchestrated
nginx_test "$orchestrated.env" orchestrated

[[ $fail -eq 0 ]] && echo "OK: nginx-gzip-proxied"
exit $fail
