#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Checks that the fallback cache exists before it is used as a read-only
# cache-from (FALLBACK_REF of bake-overrides.sh). Writes "ref" to $GITHUB_OUTPUT:
# the template unchanged if the cache of $PROBE_TARGET is in the registry, empty
# otherwise. A missing cache is a warning, never a failure, and the build then
# runs without a fallback.
#
# Environment:
#   FALLBACK_REF   cache ref template, "{target}" is replaced by the target name
#   PROBE_TARGET   target whose cache must exist, default core
#   The registry of the ref must be logged in.
set -euo pipefail

: "${FALLBACK_REF:?}" "${GITHUB_OUTPUT:?}"
PROBE_TARGET="${PROBE_TARGET:-core}"

[[ "$FALLBACK_REF" =~ ^[A-Za-z0-9._/:{}-]+$ ]] || { echo "::error::Invalid FALLBACK_REF." >&2; exit 1; }
[[ "$PROBE_TARGET" =~ ^[a-z0-9-]+$ ]] || { echo "::error::Invalid PROBE_TARGET." >&2; exit 1; }

summary() { [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "$1" >>"$GITHUB_STEP_SUMMARY"; }

probe="${FALLBACK_REF//\{target\}/$PROBE_TARGET}"
if docker buildx imagetools inspect "$probe" >/dev/null 2>&1; then
  echo "ref=$FALLBACK_REF" >>"$GITHUB_OUTPUT"
  echo "::notice::Fallback cache: $probe (and the same cache of the other targets)."
  summary "Fallback cache: \`$probe\` and the same cache of the other targets."
else
  echo "ref=" >>"$GITHUB_OUTPUT"
  echo "::warning::Fallback cache $probe not found; building without it."
  summary "Fallback cache \`$probe\` not found; built without it."
fi
