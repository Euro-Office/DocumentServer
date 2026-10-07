# Dev images

Build and test Docker images from any combination of submodule commits,
including unmerged feature branches, without touching `main` or the release
images.

A `dev/<feature>` branch in DocumentServer pins each submodule to an exact
commit. Every push to that branch builds and publishes dev images
([`dev-images.yml`](../.github/workflows/dev-images.yml)). After the branch is
deleted, the daily sweep (03:00 UTC) deletes its images and build cache
within 24 hours.

## 1. Create a dev branch

```sh
git fetch origin
git switch -c dev/<feature> origin/main
```

## 2. Pin submodules and push

```sh
scripts/dev-pin.sh --push server=feature/x
scripts/dev-pin.sh --push server=feature/x sdkjs=a1b2c3d web-apps=v9.3.5
```

Each `<submodule>=<ref>` takes a branch, tag or commit SHA. The ref is
resolved in the submodule's GitHub repository, so it must be pushed there
first. All pins land in one commit, for example
`dev: pin server=feature/x@1a2b3c4d, sdkjs=a1b2c3d4`. Without `--push` the
commit stays local.

The script only updates the gitlinks. To get the pinned code locally as well,
run `git submodule update --init <submodule>`.

To see what is pinned and whether each commit is already on the submodule's
default branch, run:

```sh
scripts/dev-pin.sh --list
```

## 3. Find the images

The build runs in the **Dev images** workflow. Its job summary lists the
DocumentServer commit, every pinned submodule commit and the published
images:

| Package | Image |
|---|---|
| `ghcr.io/euro-office/documentserver-dev` | standalone image |
| `ghcr.io/euro-office/cluster-docs-dev` | cluster docs image |
| `ghcr.io/euro-office/cluster-example-dev` | cluster example image |
| `ghcr.io/euro-office/cluster-utils-dev` | cluster utils image |

Each build gets two tags:

- `<slug>-<sha8>`: this exact DocumentServer commit (immutable).
- `<slug>`: the newest build of the branch (moving).

The slug is the branch name without `dev/`, lowercased, with other
characters replaced by `-`, plus a short hash of the full branch name, for
example `dev/Feature_X` becomes `feature-x-b997ba`. Get it with:

```sh
.github/scripts/dev-images.sh slug dev/<feature>
docker pull ghcr.io/euro-office/documentserver-dev:<slug>
```

The images are amd64 only. Their labels record the source commits
(`org.opencontainers.image.revision`, `io.github.euro-office.submodule.<path>`).

## 4. Clean up

Delete the branch when you are done:

```sh
git push origin --delete dev/<feature>
```

The daily sweep (03:00 UTC) then deletes the branch's images and build cache
within 24 hours. For live branches it keeps only the 5 newest commits, and
deletes commit tags older than 30 days unless they are the branch's current
`<slug>` tag.

Optionally, delete them immediately. This needs a token that can delete
packages (`gh auth refresh -s read:packages,delete:packages`) and admin access
to the packages. Try `DRY_RUN=1` first:

```sh
export ORG=euro-office CACHE_PACKAGE=documentserver-build-cache \
  DEV_PACKAGES="documentserver-dev cluster-docs-dev cluster-example-dev cluster-utils-dev"
DRY_RUN=1 .github/scripts/dev-images.sh cleanup dev/<feature>
.github/scripts/dev-images.sh cleanup dev/<feature>
```

## Rules

- **Never open a PR from `dev/*` into `main`.** It would also run the regular
  build, and the **Gitlink guard** check fails any PR whose submodule pins are
  not on the submodules' default branches.
- **Pinned commits must be pushed to the submodule's GitHub repository and
  stay reachable.** If a feature branch is squash-merged and deleted, its
  commits can disappear, and old dev images can no longer be rebuilt.
- **Refresh a long-lived dev branch by merging `origin/main` into it.** Do not
  rebase shared dev branches.
- In the submodule repos, `master`, `develop` and most tags are copies of
  ONLYOFFICE upstream. Euro-Office's own branch is `main`, so use
  `server=main`, not `server=master`.
- Do not use the branch name `develop`; the upstream mirror job writes to it.
- Branch names may only contain letters, digits, `.`, `_`, `-` and `/`.

All submodule repositories are public, so the workflows read them with the
built-in `GITHUB_TOKEN`. If one ever becomes private, they need a GitHub App
token with `contents: read`, not the mirror token.
