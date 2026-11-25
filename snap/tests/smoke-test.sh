#!/bin/bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Installs the snap on a disposable Ubuntu machine and tests it. Run as root.
#
#   smoke-test.sh <file.snap>
set -euo pipefail

snap_file=$(realpath "$1")
here=$(dirname "$(realpath "$0")")
name=euro-office-documentserver
url=http://127.0.0.1:8480

pass() { echo "ok: $*"; }
fail() {
    echo "::error::$*"
    for app in postgresql rabbitmq docservice converter nginx; do
        snap logs -n 30 "$name.$app" 2>&1 || true
    done
    exit 1
}
wait_healthy() {
    for _ in $(seq 60); do
        [ "$(curl -s --max-time 5 "$1/healthcheck" || true)" = true ] && return
        sleep 2
    done
    fail "not healthy at $1"
}
status() { curl --path-as-is -s -o /dev/null -w '%{http_code}' "$1"; }

snap wait system seed.loaded
snap install --dangerous "$snap_file"
wait_healthy $url
pass "healthy after the installation"

for path in info/info.json internal/cluster/inactive //internal/x 9.3.8-abc/internal/x INTERNAL/x; do
    [ "$(status "$url/$path")" = 403 ] || fail "$path is reachable"
done
pass "/internal and /info are not reachable"

[ "$(status $url/web-apps/apps/api/documents/api.js)" = 200 ] || fail "api.js is missing"
python3 "$here/convert.py" $url "$(snap get $name jwt.secret)" || fail "conversion"

# Only loopback addresses, and no service running as root.
if ss -lntH | awk '{print $4}' | grep -E ':(8000|848[0-4])$' | grep -vE '^(127\.0\.0\.1|\[::1\]):'; then
    fail "listening on a public address"
fi
for app in postgresql rabbitmq docservice converter nginx; do
    pid=$(systemctl show -p MainPID --value "snap.$name.$app.service")
    [ "$(stat -c %U "/proc/$pid")" = _daemon_ ] || fail "$app does not run as _daemon_"
done
[ "$(stat -c '%a %U' /var/snap/$name/common/connection/connection.json)" = "600 root" ] || fail "connection.json permissions"
pass "only loopback, unprivileged, secret is private"

for bad in port=abc workers=0 address=x jwt.secret=short; do
    if snap set $name "$bad" 2>/dev/null; then fail "accepted $bad"; fi
done
snap set $name port=8500
wait_healthy http://127.0.0.1:8500
snap set $name port=8480
wait_healthy $url
pass "options"

secret=$(snap get $name jwt.secret)
snap install --dangerous "$snap_file"
wait_healthy $url
[ "$secret" = "$(snap get $name jwt.secret)" ] || fail "the secret changed on a refresh"
python3 "$here/convert.py" $url "$secret" || fail "conversion after a refresh"
pass "refresh"

# With the plug in the published Nextcloud snap, test the connection too.
snap install nextcloud
if grep -q '^  euro-office:' /snap/nextcloud/current/meta/snap.yaml; then
    nextcloud.manual-install admin smoke-test-password
    nextcloud.occ app:install eurooffice
    snap connect nextcloud:euro-office $name:nextcloud
    for _ in $(seq 30); do
        nextcloud.occ eurooffice:documentserver --check && break
        sleep 3
    done
    nextcloud.occ eurooffice:documentserver --check || fail "Nextcloud cannot use the document server"
    pass "Nextcloud"
else
    echo "::notice::The nextcloud snap has no euro-office plug yet, skipped that test."
fi
