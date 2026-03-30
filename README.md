<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)
[![Docker Pulls](https://img.shields.io/github/actions/workflow/status/Euro-Office/DocumentServer/build.yml?branch=main&style=flat)](https://github.com/Euro-Office/DocumentServer/actions)

# Euro-Office DocumentServer

**Your sovereign office suite** — A free, open-source document editing platform for collaborative editing of documents, spreadsheets, presentations, and PDFs.

## Quick Start

Try it with Docker:

```sh
docker pull ghcr.io/euro-office/documentserver:latest
docker run -i -t -d -p 8080:80 --restart=always \
  -e EXAMPLE_ENABLED=true \
  -e JWT_SECRET=my_jwt_secret \
  ghcr.io/euro-office/documentserver:latest
```

Open `http://localhost:8080` to access the editor.

## What Is This?

Euro-Office DocumentServer is the deployment and integration repository for the Euro-Office project. It orchestrates these components into a single deployable service:

| Component | Repository | Purpose |
|-----------|-----------|---------|
| **core** | [Euro-Office/core](https://github.com/Euro-Office/core) | C++ document rendering engine (OOXML, ODF, PDF conversion) |
| **sdkjs** | [Euro-Office/sdkjs](https://github.com/Euro-Office/sdkjs) | JavaScript SDK for the document editor |
| **web-apps** | [Euro-Office/web-apps](https://github.com/Euro-Office/web-apps) | HTML/JS UI for document, spreadsheet, and presentation editors |
| **server** | [Euro-Office/server](https://github.com/Euro-Office/server) | Node.js backend (document service, converter, metrics, admin panel) |
| **sdkjs-forms** | [Euro-Office/sdkjs-forms](https://github.com/Euro-Office/sdkjs-forms) | Forms plugin for the JavaScript SDK |
| **core-fonts** | [Euro-Office/core-fonts](https://github.com/Euro-Office/core-fonts) | Font packages for document rendering |
| **dictionaries** | [Euro-Office/dictionaries](https://github.com/Euro-Office/dictionaries) | Spell-check dictionaries |

## Documentation

- **Build the Docker image**: [build/README.md](build/README.md)
- **Development environment**: [develop/README.md](develop/README.md)
- **Contributing guide**: [CONTRIBUTING.md](https://github.com/Euro-Office/.github/blob/main/CONTRIBUTING.md)
- **Project roadmap**: [ROADMAP.md](https://github.com/Euro-Office/.github/blob/main/ROADMAP.md)
- **Integration examples**: [document-server-integration](https://github.com/Euro-Office/document-server-integration)

## Building from Source

See [build/README.md](build/README.md) for full instructions. Quick summary:

```sh
git clone --recurse-submodules https://github.com/Euro-Office/DocumentServer.git
cd DocumentServer/build
make build-image
```

For development with live rebuilds, see [develop/README.md](develop/README.md).

## Packages

Debian and RPM packages can be built from the Docker image:

```sh
cd DocumentServer/build
make packages
```

Packages are written to `build/deploy/packages/`. See the [build/README.md](build/README.md) for more options including custom versions and Vagrant VM testing.

## Running Tests

```sh
cd DocumentServer/build
docker compose -f develop/docker-compose.yml up -d
docker compose exec eo bash
# Run tests from inside the container
```

## Get Involved

- **File issues**: [github.com/Euro-Office/DocumentServer/issues](https://github.com/Euro-Office/DocumentServer/issues)
- **Submit PRs**: See the [contributing guide](https://github.com/Euro-Office/.github/blob/main/CONTRIBUTING.md)
- **Join the discussion**: Check the [organization profile](https://github.com/Euro-Office) for community channels

## License

Euro-Office is licensed under the [GNU AGPLv3](https://www.gnu.org/licenses/agpl-3.0.en.html).

## Project Links

- **Organization**: [github.com/Euro-Office](https://github.com/Euro-Office)
- **Roadmap**: [ROADMAP.md](https://github.com/Euro-Office/.github/blob/main/ROADMAP.md)
- **Contributing**: [CONTRIBUTING.md](https://github.com/Euro-Office/.github/blob/main/CONTRIBUTING.md)
- **Security**: [SECURITY.md](https://github.com/Euro-Office/.github/blob/main/SECURITY.md)
