# Fully isolated Docker build process


The docker compose environment in this directory allows to run document server built from our code base. It runs a container called develop, which just adds the development (i.e., build) tooling to the finalubuntu container. This lets you build pieces on the fly directly inside the container, saving build time when developing:

Before starting, make sure Docker and your build user are set up: [Build Requisites](../build/BUILD_REQUISITES.md).

- Clone the Euro-Office Nextcloud connector as a sibling of `DocumentServer` (i.e. inside the same `euro-office-public` parent):
  ```sh
  git clone https://github.com/Euro-Office/eurooffice-nextcloud.git ../../eurooffice-nextcloud
  cd ../../eurooffice-nextcloud && git submodule update --init --recursive && npm install && npm run build && composer install --no-dev
  cd ../DocumentServer/develop
  ```
- Follow the repo cloning steps in the build readme
- In DocumentServer/develop, start the containers and get into eo bash. The
  recommended path on all architectures is to **pull the prebuilt dev image** — a
  multi-arch `:latest-dev` (amd64 **and** arm64) is published on every merge to `main`,
  so no local image build is needed, including on Apple Silicon:
  - `make pull` to pull the latest dev image from GitHub and start (recommended first step)
  - `make` to use the image already available locally
  - `make build` to build the dev image locally from scratch — only needed for offline
    work or when changing the image/toolchain itself (this is the long, full build)
  - `make mobile` for Android emulator / physical LAN device testing (see below)

  You may need to generate a PAT first, as described in https://github.com/Euro-Office/DocumentServer/pkgs/container/documentserver
- In docker-compose.yml, for the eo service, ensure that `target` is set to `develop`

#### Using the image:

- It's exposed at `http://localhost:8081/`
- The Euro-Office Nextcloud connector (`eurooffice`) is installed and configured automatically. If not, follow these steps:
    - Install via `docker compose exec nextcloud bash` -> `php occ app:enable eurooffice`
    - Configure your instance at `http://localhost:8081/settings/admin/eurooffice`:
        - Docs address `http://localhost:8080/`
        - Server address for internal requests from Euro-Office Docs `http://nextcloud/`
        - Docs address for internal requests from Nextcloud `http://eo/`
        - Secret key: `euro-office-dev-jwt-secret-key-2026`
    - Navigate to Files `http://localhost:8081/apps/files/`, create a document, and try to open it

#### Testing from mobile devices and emulators

`make local` runs on `localhost` — enough for the desktop browser and iOS simulator. For Android emulators and physical devices on the LAN, use `make mobile` instead — it detects the host's LAN IP, injects it so the editor is reachable from off-desktop clients, and prints the full Nextcloud URL in the banner.

For testing against a `make next` branch from a mobile device, use `make next-mobile` (accepts the same `NC_BRANCH` variable):

```sh
make next-mobile                        # mobile + NC master
make next-mobile NC_BRANCH=stable34     # mobile + NC34 stable
```

| Client | Target | Nextcloud URL |
|---|---|---|
| Desktop browser | `make local` or `make mobile` | `http://localhost:8081/` |
| iOS simulator | `make local` or `make mobile` | `http://localhost:8081/` |
| Android emulator | `make mobile` / `make next-mobile` | `http://10.0.2.2:8081/` |
| Physical LAN device | `make mobile` / `make next-mobile` | `http://<HOST_LAN_IP>:8081/` |

IP detection uses `ipconfig` on macOS and `ip route` on Linux. On native Windows — or any machine where detection fails — pass it explicitly:

```sh
make mobile HOST_LAN_IP=192.168.1.50
```

When your LAN IP changes (new wifi, tethering, etc.), update the running stack without a full rebuild:

```sh
make refresh-urls
```

Switching between `make local` and `make mobile` (or `make next` and `make next-mobile`) on a running stack is supported — both targets re-apply the correct URLs and trusted domains on each run.

#### Pinning the Nextcloud version

`make local` follows `nextcloud:latest` from Docker Hub (current stable) and persists data in a named volume `nc_data_latest`. If `latest` advances to a newer NC major version, the NC entrypoint auto-runs `occ upgrade` on next start — no manual steps needed.

To pin to a specific version, pass `NC_VERSION`:

```sh
NC_VERSION=33 make local    # pin to NC33, data in nc_data_33
NC_VERSION=34 make local    # pin to NC34, data in nc_data_34
```

Each `NC_VERSION` gets its own named volume, so switching between pinned versions preserves each one's state.

> Note: if your local `nextcloud:latest` image is behind the data volume (e.g. you pulled latest when it was NC33 but now the volume has NC34 data), `make` will detect this and print a pull command. This can happen if `docker pull nextcloud:latest` was not run after a major NC release.

To wipe the data for the current version and start fresh:

```sh
make wipe-nc                  # wipes nc_data_latest
make wipe-nc NC_VERSION=33    # wipes nc_data_33
```

#### Testing against a future Nextcloud version

Use `make next` when you specifically need to test against an unreleased or non-current NC: `master`, `stable33`, `stable34`, etc.

Run from `DocumentServer/develop/`:

```sh
make next                           # master (current NC dev trunk)
make next NC_BRANCH=stable33        # NC33 stable
make next NC_BRANCH=stable34        # NC34 stable (once cut)
```

`make next` swaps the official image for the source-clone dev image (`nextcloud-docker-dev`) via `docker-compose.next.yml`, and gives each NC branch its own named volume — switching between branches preserves each branch's installed state (eurooffice config, files, sessions). Compose detects the volume mount change and recreates the container automatically; no manual stop/rm.

First boot per branch will be several minutes while NC clones and installs into the empty volume; subsequent switches reattach to the warm volume in seconds. During a long first boot the banner shows a live log line after 1000s so you can confirm progress is still happening.

Wipe a single branch with:

```sh
make wipe-next                        # wipes nc_data_master
make wipe-next NC_BRANCH=stable33     # wipes nc_data_stable33
```

> Note: tracking `master` means NC's code moves between sessions. If you see `Nextcloud or one of the apps require upgrade` in `make next` output, run `docker compose exec -u www-data nextcloud ./occ upgrade` (or wipe the volume and then run `make next`).

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

A multi-arch `:latest-dev` image (amd64 + arm64) is published to GHCR on every merge to `main`, so ARM64 users can `make pull` like everyone else — `make build` is only needed for offline work or to rebuild the image itself.

## Parallel test servers (`eo.sh`)

The `make` workflow above runs a single Nextcloud-integrated stack with fixed
container names and ports — use it for interactive, integration-style testing.

When you instead need **several throwaway document servers at once** — e.g. a coding
agent spinning one up per branch/worktree to verify a change and run build steps —
use `./eo.sh`. Each instance is a single, fully self-contained container (its own
Postgres, Redis, RabbitMQ, Nginx, supervisord) from the same `:latest-dev` image, so
there is no shared state and no full build:

```sh
./eo.sh up <name> [port]        # start eo-<name>; auto host port if omitted; waits for /healthcheck, prints URL
./eo.sh build <name> <target>   # run an in-container make target: web-apps-dev | sdkjs | server/docservice | core/x2t | …
./eo.sh exec <name> [cmd…]      # shell (default) or command inside the container
./eo.sh logs <name>             # follow logs
./eo.sh ls                      # list running instances with host ports
./eo.sh down <name>… | --all    # stop and remove instance(s)
```

Each instance mounts the **current git working tree** at `/develop`, so the build
targets operate on your local changes. Run each *building* instance from its own git
worktree so parallel builds don't share (and clobber) `node_modules`.

Instances start with `EXAMPLE_ENABLED=true` (test editor at `/example/`) and
`WOPI_ENABLED=true`. JWT is **enabled** with a shared dev secret
(`EO_JWT_SECRET`, default `euro-office-dev-jwt-secret-key-2026`) — the bundled example
app always requires JWT, so this is what lets documents actually open. These are local
test servers — **do not expose them publicly**. Override the image with `EO_IMAGE=…`
(must be a `-dev` image; the production `:latest` lacks the build toolchain).

To create and open a document, use the example app's **Create new → Document** (which
hits `editor?fileExt=docx`). Opening `editor?fileName=new.docx` directly will fail —
that form expects an already-existing file.

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
