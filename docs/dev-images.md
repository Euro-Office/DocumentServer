# Dev images

Build and test Docker images from any combination of submodule commits,
including unmerged feature branches, without touching `main` or the release images.

A `dev/<feature>` branch in DocumentServer pins each submodule to an exact
commit. Every push to that branch builds and publishes dev images
([`dev-images.yml`](../.github/workflows/dev-images.yml)). Deleting the branch
deletes its images and build caches right away
([`dev-images-cleanup.yml`](../.github/workflows/dev-images-cleanup.yml)).

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

In the submodule repositories use `main`. `master`, `develop` and most tags are
copies of the ONLYOFFICE upstream.

## 3. Find the images

The build runs in the **Dev images** workflow on every push. Its job summary
lists the DocumentServer commit, every pinned submodule commit, and the digest
of each published image:

| Package | Image |
|---|---|
| `ghcr.io/euro-office/documentserver-dev` | standalone image |
| `ghcr.io/euro-office/cluster-docs-dev` | cluster docs image |
| `ghcr.io/euro-office/cluster-example-dev` | cluster example image |
| `ghcr.io/euro-office/cluster-utils-dev` | cluster utils image |

Each image has one tag, `<slug>`, which always points to the newest build of
the branch. The slug is the branch name without `dev/`, lowercased, with other
characters replaced by `-`, plus a short hash of the full branch name, for
example `dev/Feature_X` becomes `feature-x-b997ba`. Get it with:

```sh
.github/scripts/dev-images.sh slug dev/<feature>
docker pull ghcr.io/euro-office/documentserver-dev:<slug>
```

Because the tag moves, read the exact commits from the image labels:

```sh
docker inspect ghcr.io/euro-office/documentserver-dev:<slug> \
  --format '{{json .Config.Labels}}' | jq
```

`org.opencontainers.image.revision` is the DocumentServer commit and
`io.github.euro-office.submodule.<path>` the commit of each submodule.

The editor's About dialog shows the DocumentServer and submodule commits the
image was built from.

The images are amd64 only.

## 4. Clean up

Delete the branch when you are done:

```sh
git push origin --delete dev/<feature>
```

This triggers **Dev images cleanup**, which deletes the branch's images in the
four `*-dev` packages and its build caches (`dev-<slug>-<target>-<arch>` in
`documentserver-build-cache`). Versions that also carry other tags are kept,
with a warning. Because `delete` workflows run from the default branch, this
only takes effect once `dev-images-cleanup.yml` is on `main`.

While the branch exists, each build removes the previous builds of the branch:
the new image takes over the `<slug>` tag, and the now untagged older versions
of the four `*-dev` packages are deleted at the end of the build job. The shared
`documentserver-build-cache` package is never pruned this way.

The workflows use the built-in `GITHUB_TOKEN`, not a personal access token. If
the token has no access to a package (for example one created outside this
repository), the cleanup skips it with a notice instead of failing.

### Manual cleanup

To remove a branch's images by hand, for example if the cleanup workflow did not
run, use a token that can delete packages in the organization:

```sh
export ORG=euro-office CACHE_PACKAGE=documentserver-build-cache \
  DEV_PACKAGES="documentserver-dev cluster-docs-dev cluster-example-dev cluster-utils-dev"
DRY_RUN=1 .github/scripts/dev-images.sh cleanup dev/<feature>   # only print
.github/scripts/dev-images.sh cleanup dev/<feature>
```

## Rules

- **Never open a PR from `dev/*` into `main`.** It would also run the regular
  build, and the **Gitlink guard** check fails any PR whose submodule pins are
  not on the submodules' default branches. Gitlink guard skips draft PRs, so a
  draft that bumps gitlinks to feature branches to get test images stays green;
  it runs when the PR is marked ready for review.
- **Pinned commits must be pushed to the submodule's GitHub repository and
  stay reachable.** If a feature branch is squash-merged and deleted, its
  commits can disappear, and old dev images can no longer be rebuilt.
- **Refresh a long-lived dev branch by merging `origin/main` into it.** Do not
  rebase shared dev branches.
- Do not use the branch name `develop`; the upstream mirror job writes to it.
- Branch names may only contain letters, digits, `.`, `_`, `-` and `/`.
- All submodule repositories are public, so the built-in token can read them.
  If one becomes private, use a GitHub App token with `contents: read`, not the
  mirror token.
