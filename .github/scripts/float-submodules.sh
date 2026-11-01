#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Checks out every submodule at the head of its default branch instead of the
# committed gitlink. build.yml runs it for main and PRs into main, so they build
# what is merged in the submodules. Releases pin their own commits (release.sh).
set -euo pipefail

git submodule update --init --remote --depth=1
# Nested submodules follow the gitlinks of the floated commit, they don't float.
git submodule foreach --quiet 'git submodule update --init --recursive'
git submodule status
