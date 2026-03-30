# Fully isolated Docker build process


The docker compose environment in this directory allows to run document server built from our code base. It runs a container called develop, which just adds the development (i.e., build) tooling to the finalubuntu container. This lets you build pieces on the fly directly inside the container, saving build time when developing:

- Follow the repo cloning steps in the build readme
- In DocumentServer/develop, start the containers and get into eo bash with either: 
  - `make` to use the image that is currently available locally
  - `make pull` to use the latest image from github
  - `make build` to build the image locally from scratch
  
  You may need to generate a PAT first, as described in https://github.com/Euro-Office/DocumentServer/pkgs/container/documentserver
- In docker-compose.yml, for the eo service, ensure that `target` is set to `develop`

#### Using the image:

- It's exposed at `http://localhost:8081/`
- Nextclouds onlyoffice app should be installed and configured automatically. If not follow the next steps
    - Install the onlyoffice app with the UI, or via `docker compose exec nextcloud bash` -> `php occ app:install onlyoffice`
    - Configure your instance at `http://localhost:8081/settings/admin/onlyoffice`:
        - Docs address `http://localhost:8080/`
        - Server address for internal requests from ONLYOFFICE Docs `http://nextcloud/`
        - Docs address for internal requests from Nextcloud `http://eo/`
        - Secret key: `secret`
    - Navigate to Files `http://localhost:8081/apps/files/`, create a document, and try to open it

#### Building changes:

- Enter the container with `docker compose exec eo bash`
- Run the build steps for your component. All builds get deployed immediately and the component restarted if necessary. Supported commands:
    - web-apps:
        - `make web-apps`: full web-apps build
    - sdkjs:
        - `make sdkjs`: full sdkjs build
    - core
        - `make core`: full core build
        - `make core/allthemesgen`
        - `make core/allfontsgen`
        - `make core/allthemesgen`
        - `make core/x2t`
        - `make core/docbuilder`
    - server
        - `make server`: full server build
        - `make server/common`
        - `make server/docservice`
        - `make server/converter`
        - `make server/metrics`
        - `make server/adminp`
        - `make server/adminp/srv`
        - `make server/adminp/cli`
- you can add custom flags in the Makefile by changing the corresponding environment variable at the top of the Makefile:

    - CORE_FLAGS
    - SERVER_FLAGS
    - SDKJS_FLAGS
    - WEBAPPS_FLAGS

  then build with DEBUG=1, e.g. make sdkjs DEBUG=1

#### ARM64 support (Apple Silicon / Graviton)

The Docker image and dev Makefile handle ARM64 automatically:

- **core**: Uses pre-built upstream binaries on arm64 (V8's bundled clang is x86_64-only)
- **sdkjs**: Closure Compiler falls back to Java mode (`CC_PLATFORM=java`) since the native binary is x86_64-only
- **web-apps**: Skips imagemin on arm64 (native binaries are x86_64-only)
- **server**: `pkg` builds native arm64 binaries

No GHCR arm64 image is available yet, so ARM64 users must build locally with `make build`.

## Development Builds

Once inside the container (`docker exec -it eo bash`), the following make targets are available:

### web-apps


#### Full web-apps build

includes npm ci, **run this first**

```sh
make web-apps
```

#### Quick rebuild
without npm ci, imagemin, or babel. Runs with the Euro Office theme.

```sh
make web-apps-dev
```

#### Custom build
Use `CFLAGS` to pass additional flags

```sh
THEME=euro-office make web-apps-dev CFLAGS="--skip-imagemin"
````
> The make build commands clear the cache, this does not.
> Therefore you must run `/usr/bin/documentserver-flush-cache.sh`

### Maintenance

#### Strip Section 7(b) trademark clause

After upstream merges, the AGPL Section 7(b) trademark clause may be re-introduced. A GitHub Actions workflow automatically strips it. Run it from **Actions > Strip Section 7(b) trademark clause** and select which project to process (or "all").

The commit message and PR body templates live in `scripts/strip-logo-clause-commit.txt` and `scripts/strip-logo-clause-pr-body.txt`.

### sdkjs

#### Full sdkjs build
includes npm install + closure compiler + allfontsgen
```shell
make sdkjs
````
