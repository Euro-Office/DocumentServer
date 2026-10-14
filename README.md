<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)

# Euro-Office
**Your sovereign office**

[Learn more.](https://github.com/Euro-Office/)

## Install

The Document Server is not a standalone application and needs a platform such as Nextcloud that stores the files.

* **Nextcloud Office**: signed builds for production use, with APT and DNF package repositories, available on [nextcloud-releases/Office-DocumentServer](https://github.com/nextcloud-releases/Office-DocumentServer/releases)
* **Euro-Office**: community builds for testing and contributing, available as deb/rpm on the [releases](https://github.com/Euro-Office/DocumentServer/releases/latest) page and as the `ghcr.io/euro-office/documentserver` container image

See the [installation guide](https://euro-office.github.io/documentation/installation/) in the [official documentation](https://euro-office.github.io/documentation/) for step-by-step instructions.

## Get involved
Get involved! You can file issues, propose pull requests and more. We are looking forward to make the digital sovereign office space better than ever before!

### Try out
We currently provide a docker image for testing and integration purposes. Check the [releases](https://github.com/Euro-Office/DocumentServer/releases) for deb/rpm packages.

```
docker pull ghcr.io/euro-office/documentserver:latest
docker run -i -t -d -p 8080:80 --restart=always -e EXAMPLE_ENABLED=true -e JWT_SECRET=my_long_jwt_secret_at_least_32_chars ghcr.io/euro-office/documentserver:latest
```

### Building

Our build steps and processes are documented in https://github.com/Euro-Office/DocumentServer/tree/main/build. For development there are more detailed steps to build and run individual components in https://github.com/Euro-Office/DocumentServer/tree/main/develop 
