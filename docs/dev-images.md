# Dev images

Build and test Docker images from any combination of submodule commits,
including unmerged feature branches, without touching `main` or the release images.

A `dev/<feature>` branch in DocumentServer pins each submodule to an exact
commit. Every push to that branch builds and publishes dev images
([`dev-images.yml`](../.github/workflows/dev-images.yml)); deleting the
branch deletes them.

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

This deletes the branch's images and build cache. A daily sweep also deletes
images of branches that no longer exist. It keeps only the 5 newest commits
per branch, and deletes commit tags older than 30 days unless they are the
branch's current `<slug>` tag.

## Rules

- **Never open a PR from `dev/*` into `main`.** It would also run the regular
  build, and the **Gitlink guard** check fails any PR whose submodule pins are
  not on the submodules' default branches.
- **Pinned commits must be pushed to the submodule's GitHub repository and
  stay reachable.** If a feature branch is squash-merged and deleted, its
  commits can disappear, and old dev images can no longer be rebuilt.
- **Refresh a long-lived dev branch by merging `origin/main` into it.** Do not
  rebase shared dev branches.
- Do not use the branch name `develop`; the upstream mirror job writes to it.
- Branch names may only contain letters, digits, `.`, `_`, `-` and `/`.
