#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Run this before committing any change under e2e/.
#
#   ./make.sh          format, lint and type-check (default)
#   ./make.sh check    same as above, but only report problems (does not modify files)
#   ./make.sh test     run the Playwright tests
#   ./make.sh fix      explicit form of the default: apply formatting and lint fixes, then type-check

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -d node_modules ]; then
  npm install
fi

case "${1:-fix}" in
  fix)
    npm run format
    npm run lint:fix
    npx tsc --noEmit
    ;;
  check)
    npm run format:check
    npm run lint
    npx tsc --noEmit
    ;;
  test)
    npm test
    ;;
  *)
    echo "Usage: $0 [fix|check|test]" >&2
    exit 1
    ;;
esac
