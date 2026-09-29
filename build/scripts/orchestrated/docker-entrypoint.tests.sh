#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/docker-entrypoint.sh"
TRACE=$(mktemp)
trap 'rm -f "$TRACE"' EXIT

set +e
env -i \
  PATH="$PATH" \
  COMPANY_NAME=euro-office \
  JWT_ENABLED=false \
  EDITOR_DATA_STORAGE=editorDataRedis \
  EDITOR_STAT_STORAGE=editorDataRedis \
  REDIS_SENTINEL_NODES='sentinel-a:26379 sentinel-b:26380' \
  REDIS_CLUSTER_NODES='cluster-a:7000 cluster-b:7001' \
  bash -x "$ENTRYPOINT" docservice >"$TRACE" 2>&1
status=$?
set -e

# The test image is not present here, so the final docservice exec is expected
# to fail. The xtrace above still contains the NODE_CONFIG assembled by the
# entrypoint, which is the part under test.
if [[ $status -eq 0 ]]; then
  echo "orchestrated entrypoint unexpectedly succeeded without docservice" >&2
  exit 1
fi

for expected in \
  'sentinel-a", "port": 26379' \
  'sentinel-b", "port": 26380' \
  'redis://cluster-a:7000' \
  'redis://cluster-b:7001' \
  'editorDataStorage": "editorDataRedis' \
  'editorStatStorage": "editorDataRedis'; do
  if ! grep -Fq "$expected" "$TRACE"; then
    echo "missing Redis configuration in orchestrated entrypoint output: $expected" >&2
    cat "$TRACE" >&2
    exit 1
  fi
done

set +e
env -i \
  PATH="$PATH" \
  COMPANY_NAME=euro-office \
  JWT_ENABLED=false \
  EDITOR_DATA_STORAGE='../not-a-module' \
  bash "$ENTRYPOINT" docservice >"$TRACE" 2>&1
status=$?
set -e

if [[ $status -eq 0 ]] || ! grep -Fq 'EDITOR_DATA_STORAGE must be a plain module name' "$TRACE"; then
  echo "invalid editor-data storage name was not rejected" >&2
  cat "$TRACE" >&2
  exit 1
fi

echo "orchestrated entrypoint Redis and editor-data configuration: PASS"
