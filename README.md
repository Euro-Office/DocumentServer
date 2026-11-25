<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

# W4 Office Server

W4 Office Server brings browser-based document, spreadsheet, presentation and
PDF editors to a file platform such as Nextcloud. The server runs the editing
and conversion services. The connected platform stores the documents.

The editor interface lives in [W4 Office WebApps](https://github.com/W4MEX/W4-Office-WebApps).
For the standalone Windows application and portable USB edition, visit
[W4 Office Desktop Releases](https://github.com/W4MEX/W4-OfficeDesktop/releases).

## Try the development server

Docker and Docker Compose are required. Clone the orchestrator with its pinned
submodules and start the document server service:

```sh
git clone --recurse-submodules https://github.com/W4MEX/W4-OfficeServer.git
cd W4-OfficeServer/develop
docker compose pull eo
docker compose up -d eo
```

When the service is ready, open the demo at `http://localhost:8080/example/`.
See the [development guide](develop/README.md) for the health check, logs and
Nextcloud integration. Use test documents with the development setup.

The development Compose file uses a prebuilt Euro-Office image. Its interface
can show the upstream branding. The W4 editor theme lives in WebApps and needs
to be included in the WebApps revision pinned here and selected when building
the editor interface.

## Build from source

From the repository root, initialize the submodules if they were skipped
during cloning:

```sh
git submodule update --init --recursive
cd build
docker buildx bake
```

See the [build requirements](build/BUILD_REQUISITES.md) and the
[build guide](build/README.md) for image targets and cache settings. The
[development guide](develop/README.md) explains how to rebuild a component
inside the test container.

## Contribute

Report problems or suggest improvements in
[W4 Office Server Issues](https://github.com/W4MEX/W4-OfficeServer/issues).
Include the version or commit, the affected component and the steps to reproduce.
See the [contribution guidelines](CONTRIBUTING.md) before submitting a change.

## License and credits

See [LICENSE](LICENSE) and [ATTRIBUTION](ATTRIBUTION) for the license and
credits for inherited components.
