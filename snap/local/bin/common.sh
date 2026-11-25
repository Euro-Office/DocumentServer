# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=sh

CONFIG=$SNAP_DATA/config
RUN=$SNAP_COMMON/run
export PATH="$SNAP/usr/lib/postgresql/16/bin:$PATH"

# Confined root cannot access directories of other users, so only the leaf
# directories the services write to belong to _daemon_.
service_dir() {
    (umask 022 && mkdir -p "$(dirname "$1")")
    [ -d "$1" ] || mkdir "$1"
    chown _daemon_:_daemon_ "$1"
}

as_daemon() {
    exec setpriv --clear-groups --reuid _daemon_ --regid _daemon_ "$@"
}

run_node() {
    cd "/var/www/euro-office/documentserver/server/$1" || exit 1
    export HOME="$SNAP_DATA/home" PKG_CACHE_PATH="$SNAP_DATA/home/.cache"
    export NODE_ENV=production-linux NODE_DISABLE_COLORS=1 APPLICATION_NAME=euro-office
    export NODE_CONFIG_DIR="/etc/euro-office/documentserver:$CONFIG"
    export TMPDIR=/var/lib/euro-office/documentserver/tmp
    until pg_isready -q -h "$RUN" -U _daemon_ -d documentserver; do sleep 1; done
    exec "./$2"
}
