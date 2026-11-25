<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Snap package

Packages the released deb (`override-pull` in `snapcraft.yaml` pins version and checksums) together with nginx,
PostgreSQL and RabbitMQ. Build it with `snapcraft pack` from the root of the repository.

## Use with the Nextcloud snap

```sh
sudo snap connect nextcloud:euro-office euro-office-documentserver:nextcloud
```

The slot shares one directory, read-only, with a `connection.json` containing the local URL and the JWT secret.

## Use with any other Nextcloud

Put a reverse proxy in front of `127.0.0.1:8480` and take the secret from
`sudo snap get euro-office-documentserver jwt.secret`.

## Options

| Option       | Default     |                                                     |
| ------------ | ----------- | --------------------------------------------------- |
| `port`       | `8480`      | Port to listen on                                   |
| `address`    | `127.0.0.1` | IPv4 address to listen on                           |
| `workers`    | `2`         | Conversion processes, each needs about 120 MB       |
| `jwt.secret` | generated   | At least 32 characters                              |

Ports 8482 to 8484 on the loopback interface are used internally.

## Tests

`sudo snap/tests/smoke-test.sh <file.snap>`, on a disposable machine.

## Releases

| Workflow                | Does                                                                           |
| ----------------------- | ------------------------------------------------------------------------------ |
| `snap-builds`           | Builds and tests both architectures; a new version on `main` goes to candidate |
| `snap-candidate`        | Uploads to candidate and opens the call-for-testing issue (called by others)   |
| `snap-promote`          | Releases to stable after `/promote <revisions> stable [done]` on that issue    |
| `snap-security-rebuild` | Weekly: offers a rebuild if the bundled Ubuntu packages have security fixes    |
| `snap-track-release`    | Weekly: opens a PR for a new document server release                           |

The version is set in `local/release`. Raise `SNAP_REVISION` to publish a change to the packaging only.

Everything that publishes is off by default. To turn it on:

1. Register the name: `snapcraft register euro-office-documentserver`
2. Create credentials limited to this snap:
   `snapcraft export-login --snaps=euro-office-documentserver --acls=package_access,package_push,package_update,package_release --channels=candidate,stable -`
3. Store the output as the repository secret `SNAPCRAFT_STORE_CREDENTIALS`.
4. Create the environment `promote-stable`, with required reviewers if a second approval is wanted.
5. Set the repository variable `SNAP_STORE_PUBLISH` to `true`.
6. Optional: ask the store to allow connecting the slot automatically.

The PRs of `snap-track-release` use `EURO_OFFICE_MIRROR_TOKEN` if it exists.
