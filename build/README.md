# Euro-Office Document Server

Docker image where we are experimenting with building the Euro-Office Document Server.

## Building the Image

First, clone the repositories for the core-fonts, sdkjs, web-apps, and server components:

```sh
git clone --recurse-submodules https://github.com/Euro-Office/DocumentServer.git
```

If the repo was cloned without --recurse-submodules, initialize and download the submodules with:
```sh
git submodule update --init --recursive
```

Then, you can build the full image by running:

```sh
cd DocumentServer/build
make build-image
```

or the development image with:

```sh
cd DocumentServer/build
make build
```

If you only want to build one of the components, you can specify the respective target:

```sh
make docker-target TARGET=sdkjs
```

## Running the Container

After building the image, you can run it with a simple `docker run` or with:

```sh
make run
```

If the docker build stockes because of broken content in cache, for example with error:
```sh
> Skipping ICU (done already).
> Skipping OpenSSL (done already).
> cannot change to '/build-cache1/third_party/workdir/icu/icu': No such file or directory
```
pruning the docker build cache might help:
```sh
docker builder prune -a
```

## Building packages

Packages are built inside Docker using a multi-stage build. The `packages` stage
extends the `finalubuntu` image (or a custom base via `PACKAGE_BASE`), then runs
`build/scripts/build-packages.sh` which invokes the upstream `document-server-package`
Makefile to produce `.deb` and `.rpm` packages.

The version is read from the `VERSION` file at the repo root. An optional
`BUILD_NUMBER` (defaults to `0`) is appended to the package version string (e.g.
`9.2.1-0`).

### Basic build

```sh
cd DocumentServer/build
make packages
```

Packages are written to `build/deploy/packages/`.

### Custom version or build number

```sh
make packages PRODUCT_VERSION=9.2.1 BUILD_NUMBER=42
```

### Build from a pre-built base image

By default the `packages` stage rebuilds on top of `finalubuntu`. If you have
already built and tagged the final image locally you can skip rebuilding it:

```sh
make packages PACKAGE_BASE=euro-office/documentserver:latest
```

### Testing packages with Vagrant

Vagrant VMs are available to install and smoke-test the produced packages on real
OS environments. The packages in `deploy/packages/` are automatically shared into
each VM.

```sh
# Bring up all VMs (Ubuntu 24.04, Debian 12, Rocky Linux 9)
make vagrant-up

# Or bring up a single VM
make vagrant-up-ubuntu
make vagrant-up-debian
make vagrant-up-rocky

# SSH into a VM
make vagrant-ssh VM=ubuntu2404

# Destroy all VMs
make vagrant-destroy
```
