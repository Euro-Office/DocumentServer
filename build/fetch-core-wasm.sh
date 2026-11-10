#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Puts core's prebuilt WebAssembly modules for the core checkout into
# build/core-wasm-prebuilt, laid out like the core-wasm target's image
# (${BUILD_ROOT}/engine, /hash, ...), and prints the context for
# docker-bake.hcl's CORE_WASM_PREBUILT ("./core-wasm-prebuilt"). Prints
# nothing when the build cache has no package for core, or core has local
# changes: then the bake builds core-wasm. Options go to core_package.py
# fetch, e.g. --channels main for release builds.
# EO_CORE_CACHE=off|require works as in core/scripts/core_package.py.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

status=0
python3 "$here/../core/scripts/core_package.py" fetch --core "$here/../core" \
    --platform wasm --product engine \
    --dest "$here/core-wasm-prebuilt${BUILD_ROOT:-/package}" "$@" >&2 || status=$?
case "$status" in
    0) echo "./core-wasm-prebuilt" ;;
    3) ;;
    *) exit "$status" ;;
esac
