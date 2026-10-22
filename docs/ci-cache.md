<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# CI build cache

The image builds (`build.yml` and `dev-images.yml`) take about two hours when the
C++ `core` compile is not served from cache, and well under an hour when it is.
They keep BuildKit's layer cache in the registry, in the package
`ghcr.io/euro-office/documentserver-build-cache`, one tag per bake target and
architecture.

## Names

| Workflow | Cache tag it writes | Cache tags it reads |
|---|---|---|
| `build.yml` | `<ref>-<brand prefix><target>-buildcache-<arch>` | its own, then `main-<brand prefix><target>-buildcache-<arch>` |
| `dev-images.yml` | `dev-<slug>-<target>-<arch>` | its own, then `main-<target>-buildcache-<arch>` |

- `<ref>` is the branch, PR or tag name with `/` and `+` replaced by `-`, for
  example `main`, `458-merge` or `v9.3.6-rc.1`.
- `<brand prefix>` is empty for euro-office and `nextcloud-office-` for that brand.
- `<slug>` is the dev branch name as built by `.github/scripts/dev-images.sh slug`.
- `<arch>` is `amd64` or `arm64`.

So `main-core-buildcache-amd64` is the cache of the `core` target of the last build
of `main`, and `dev-feature-x-b997ba-core-amd64` the one of a dev branch.

The names are written by the workflows. `bake-overrides.sh` only turns a name
template (`CACHE_REF`, with `{target}` in it) into the `cache-from` and `cache-to`
lines of every target.

### Targets

The cached targets are not listed anywhere. `bake-overrides.sh` asks
`docker buildx bake --print` which targets `build/docker-bake.hcl` has, so a new
target is cached without touching the scripts. The only exception is kept in
`.github/scripts/cache-lib.sh` (`CACHE_SKIP_TARGETS`, the dummy `brand-icons` base).
`.github/scripts/tests/bake-overrides.test.sh` fails if a target of the bake file
gets no cache override.

## Who reads and writes what

| Build | Writes | Reads |
|---|---|---|
| push to `main` | `main-*` | `main-*` |
| pull request or tag | `<ref>-*` | `<ref>-*`, then `main-*` |
| `dev/<feature>` branch | `dev-<slug>-*` | `dev-<slug>-*`, then `main-*` |

`main-*` is only ever written by `main` builds. Every other build adds it as a second
`cache-from` and never as a `cache-to`, so no branch can change a cache that others
rely on.

## No commit sha in the name

A name with the commit in it can only be read by a rebuild of the same commit, so a
new push never finds the cache of the one before. A branch, PR or tag therefore uses
one stable name: the next push imports what the last push exported, and only the
steps whose input changed run again. Tags do not need a per-commit key either:
a release tag is never moved, and a content change gets a new tag.

A stable name means the newest export wins. `dev-images.yml` cancels an older run of
the same branch, so two runs do not write the same tag. For `main` it also means a
failed or partial export can replace a good cache. If a layer from an old run is
suspect, run `build.yml` again with `no_cache` or put `[no-cache]` in the PR title:
it ignores every `cache-from` and rewrites the cache.

## Fallback from main in dev builds

The first push of a new dev branch has no cache of its own. After the registry login,
`.github/scripts/check-fallback-cache.sh` checks that `main-core-buildcache-<arch>`
exists, and `bake-overrides.sh` then adds `main-<target>-buildcache-<arch>` as a
second, read-only `cache-from` for every target. If the cache is missing the step
only warns, the build runs without it and the job summary says so. The cache report
shows each import as found or not found.

How much that saves depends on how close the branch is to the last `main` build.
BuildKit only reuses a layer if everything that went into it is identical, and the
longest step, the `core` compile (about 90 minutes), depends on the source of the
`core` submodule:

- If `core` is pinned to the same commit as in the last build of `main`, the compile
  is a cache hit. A dev build measured on 21 October 2026 took 42 minutes instead of
  2 hours 13 minutes this way.
- If `main` has moved to another `core` commit, the compile runs again. The other
  steps that did not change are still hits.

A dev branch that pins other submodule commits than `main` rebuilds the targets that
depend on them. The cache report lists per target which steps were cached.

## Why a wrong cache cannot give a wrong image

A cache tag only chooses which layers BuildKit may try to reuse. Whether a layer is
reused is decided by BuildKit's own cache key: the instruction, the key of the layer
below, the content of the files it copies and the build arguments it uses. A cache
from another branch, commit or architecture therefore either matches exactly or is
ignored.

That holds for inputs BuildKit can see. Two inputs are not content-addressed:

- a floating base image (`FROM ubuntu:22.04`) changes without any change to the
  Dockerfile, and
- `RUN git clone https://github.com/microsoft/vcpkg.git` is cached by its command
  line, not by what the clone fetched.

Both can make a cached layer older than what a cold build would produce. Pinning
the base images by digest and the vcpkg checkout to a commit in the Dockerfiles of
the submodules is planned; until then a cached layer can be older than a cold build.

## Cleanup

Deleting a `dev/*` branch runs `dev-images-cleanup.yml`, which deletes every tag
with the prefix `dev-<slug>-` in the cache package, whatever target and
architecture follow, so it does not need to know the targets. `main-*` and the
`<ref>-*` tags of `build.yml` are not touched by it. To start a branch cold on
purpose, for example to test the fallback, delete and push the branch again, or
delete its `dev-<slug>-*` tags by hand
(`.github/scripts/dev-images.sh cleanup dev/<feature>` also deletes its images).
