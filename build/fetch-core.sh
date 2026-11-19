#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Puts the prebuilt core for the core checkout into build/core-prebuilt, laid
# out like the core target's image (${BUILD_ROOT}/bin and /tools), and prints
# the context for docker-bake.hcl's CORE_PREBUILT ("./core-prebuilt"). Prints
# nothing when the build cache has no package for core, or core has local
# changes: then the bake builds core. Options go to core_package.py fetch,
# e.g. --channels main for release builds.
# EO_CORE_CACHE=off|require works as in core/scripts/core_package.py.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(uname -m)" in
    x86_64)  platform=linux-amd64 ;;
    aarch64) platform=linux-arm64 ;;
    *)       echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

status=0
python3 "$here/../core/scripts/core_package.py" fetch --core "$here/../core" \
    --platform "$platform" --product server \
    --dest "$here/core-prebuilt${BUILD_ROOT:-/package}" "$@" >&2 || status=$?
case "$status" in
    0) echo "./core-prebuilt" ;;
    3) ;;
    *) exit "$status" ;;
esac
