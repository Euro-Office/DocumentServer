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
