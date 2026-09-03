<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)

# Euro-Office
**Your sovereign office**

[Learn more.](https://github.com/Euro-Office/)

## Get involved
Get involved! You can file issues, propose pull requests and more. We are looking forward to make the digital sovereign office space better than ever before!

### Try out
We currently provide a docker image for testing and integration purposes. We are going to publish deb/rpm packages shortly.

```
docker pull ghcr.io/euro-office/documentserver:latest
docker run -i -t -d -p 8080:80 --restart=always -e EXAMPLE_ENABLED=true -e JWT_SECRET=my_long_jwt_secret_at_least_32_chars ghcr.io/euro-office/documentserver:latest
```

### Building

Our build steps and processes are documented in https://github.com/Euro-Office/DocumentServer/tree/main/build. For development there are more detailed steps to build and run individual components in https://github.com/Euro-Office/DocumentServer/tree/main/develop 


# Document Server — Debian/Ubuntu Installation Guide

This guide describes how to install the Document Server `.deb` package on a
standalone Ubuntu host. The steps mirror our official Docker image, with the
container-only pieces removed (see [Differences from the Docker image](#differences-from-the-docker-image)).

## System requirements

- **OS:** minimum Ubuntu 22.04 LTS, Debian 12
- **Architecture:** `amd64` or `arm64` — download the build matching your host.
  Check yours with `dpkg --print-architecture`.
- **Privileges:** root / `sudo` access.

The package depends on a PostgreSQL database, a Redis cache, and a RabbitMQ
message broker. In this guide they all run locally on the same host; you can
point the package at remote instances by changing the connection values in
[Step 3](#step-3-pre-seed-the-database-configuration).

## Step 1: Install dependencies

Install the runtime services and the utilities the package's scripts rely on:

```bash
sudo apt-get update
ACCEPT_EULA=Y sudo apt-get install -y \
    postgresql postgresql-client redis-server rabbitmq-server \
    nginx nginx-extras sudo gdb jq util-linux \
    netcat-openbsd xxd openssl
```

On a standard systemd-based Ubuntu install, PostgreSQL, Redis, RabbitMQ, and
Nginx are started automatically once installed. Confirm they are running before
continuing:

```bash
sudo systemctl status postgresql redis-server rabbitmq-server nginx
```

## Step 2: Create the PostgreSQL user and database

The package connects to PostgreSQL using the credentials you supply in the next
step. Create the matching role and database first:

```bash
sudo -u postgres psql -c "CREATE USER eurooffice WITH PASSWORD 'eurooffice';"
sudo -u postgres psql -c "CREATE DATABASE eurooffice OWNER eurooffice;"
```

> **Production note:** `eurooffice` / `eurooffice` are the defaults used by our
> ephemeral Docker image. For a real deployment, choose a strong password and
> use it consistently here and in Step 3.

## Step 3: Pre-seed the database configuration

Installing the package triggers a debconf prompt for the database connection.
You can answer it interactively, or pre-seed the answers for an unattended
install. Set `PKG_NAME` to the **Debian package name** (the `Package:` field of
the `.deb`, not the filename):

```bash
PKG_NAME="documentserver"   # replace with the actual package name

echo "$PKG_NAME ds/db-type string postgres"    | sudo debconf-set-selections
echo "$PKG_NAME ds/db-host string localhost"   | sudo debconf-set-selections
echo "$PKG_NAME ds/db-port string 5432"        | sudo debconf-set-selections
echo "$PKG_NAME ds/db-user string eurooffice"  | sudo debconf-set-selections
echo "$PKG_NAME ds/db-pwd password eurooffice" | sudo debconf-set-selections
echo "$PKG_NAME ds/db-name string eurooffice"  | sudo debconf-set-selections
```

If you skip this step, `apt` will prompt you for the same six values during
installation.

## Step 4: Download the package

Download the build that matches your version, build number, and architecture:

```bash
wget https://github.com/Euro-Office/DocumentServer/releases/download/v{version}-{build}/euro-office-documentserver_{version}-{build}_{platform}.deb -O documentserver.rpm
```

Replace `version` and `build` and `platform` with the release you are installing.

## Step 5: Install the package

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ./documentserver.deb
```

`apt-get install` (rather than `dpkg -i`) is used so any remaining package
dependencies are resolved automatically. During installation the package's
post-install scripts initialize the database schema and configure the local
services.

> Do **not** set `DS_DOCKER_INSTALLATION=true` for a standalone install. That
> flag is only for our Docker build, where service start-up and schema setup are
> handled by the container instead of the package.

## Step 6: Enable and start the Document Server services

The package's services are not enabled or started automatically. Enable and
start them (`--now` does both):

```bash
sudo systemctl enable --now ds-docservice.service ds-example.service
```

List all units the package provides in case there are others to enable
(e.g. a converter or metrics service):

```bash
systemctl list-unit-files 'ds-*'
```

> This service enable/start step is required on **Debian/Ubuntu** too — the
> `.deb` package likewise does not start these services for you.

## Step 7: Flush the cache

After installation, clear any stale cache so the server starts cleanly:

```bash
sudo documentserver-flush-cache.sh -r false
```

## Verify the installation

Nginx serves the Document Server once installation completes. Browse to the
host (for example `http://<server-ip>/`) to confirm the welcome/example page
loads. You can also tail the logs under `/var/log/<company>/<product>/`.

## Troubleshooting

**Database schema was not created.** If the post-install step did not populate
the schema, run it manually with the same credentials from Step 3:

```bash
sudo -u postgres PGPASSWORD=eurooffice \
    psql -h localhost -U eurooffice -d eurooffice \
    -f /var/www/<company>/<product>/server/schema/postgresql/createdb.sql
```

Replace `<company>/<product>` with your install root (the package installs
under `/var/www/<company>/<product>`).

**Connection failures.** Verify PostgreSQL, Redis, and RabbitMQ are running and
reachable on `localhost` (Step 1), and that the debconf values from Step 3 match
the role and database created in Step 2.

## Differences from the Docker image

If you are comparing this guide to our `Dockerfile`, the following container-only
steps are intentionally omitted for a standalone install:

- **`DS_DOCKER_INSTALLATION=true`** — set only in the image so the package skips
  container-managed setup. Leave it unset here.
- **Supervisor configs and `entrypoint.sh`** — the image runs processes under
  supervisor via a custom entrypoint. On a standard host, the package's own
  service configuration manages the processes; you do not copy these files.
- **Manual `service ... start` calls** — needed in the image because Docker has
  no init system. On systemd-based Ubuntu the services start automatically.

# Document Server — RHEL/RPM Installation Guide

This guide describes how to install the Document Server `.rpm` package on a
standalone RHEL-family host. It covers the same components as the Debian/Ubuntu
guide, adapted to the RPM ecosystem, and reflects steps verified on Fedora.
Where the two diverge meaningfully, see
[Differences from the Debian install](#differences-from-the-debian-install).

> Unlike Debian, RPM packages have no debconf prompt. The database and service
> connections are configured after install with the bundled
> **`documentserver-configure.sh`** script (Step 7) — see that step for details.

## System requirements

- **OS:** RHEL 9 family — Rocky Linux 9, AlmaLinux 9, CentOS Stream 9 — or Fedora.
- **Architecture:** `x86_64` or `aarch64`. Check yours with `uname -m`.
- **Privileges:** root / `sudo` access.

The package depends on a PostgreSQL database, a Redis cache, and a RabbitMQ
message broker. This guide runs all three locally; point the package at remote
instances when you run the configuration script in Step 7.

## Step 1: Enable EPEL

Several dependencies (RabbitMQ, Supervisor, and on some releases `jq`) live in
the EPEL repository, which is not enabled by default on RHEL-family systems:

```bash
sudo dnf install -y epel-release
sudo dnf update -y
```

On RHEL proper (not Rocky/Alma/Fedora), also enable the CodeReady Builder repo
that EPEL depends on:

```bash
sudo subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
```

## Step 2: Install dependencies

Package names differ from Debian/Ubuntu. The mapping:

| Purpose                | Debian/Ubuntu     | RHEL/RPM                          |
| ---------------------- | ----------------- | --------------------------------- |
| Database server        | `postgresql`      | `postgresql-server`               |
| Database client/libs   | `postgresql-client` | `postgresql`                    |
| Cache                  | `redis-server`    | `redis`                           |
| Message broker         | `rabbitmq-server` | `rabbitmq-server` (EPEL)          |
| Web server             | `nginx`           | `nginx`                           |
| Extra nginx modules    | `nginx-extras`    | *(no direct equivalent — see note)* |
| Netcat                 | `netcat-openbsd`  | `nmap-ncat`                       |
| `xxd` hex dump         | *(base)*          | `vim-common`                      |
| Other tools            | `sudo gdb jq util-linux openssl` | same names         |

Install them:

```bash
sudo dnf install -y \
    postgresql-server postgresql postgresql-contrib \
    redis rabbitmq-server \
    nginx \
    sudo gdb jq util-linux nmap-ncat vim-common openssl
```

> **`nginx-extras` has no RPM equivalent.** On Debian it bundles extra nginx
> modules into one package; on RHEL the base `nginx` is used, with any required
> modules added individually as `nginx-mod-*`. Most deployments only need base
> `nginx`.
>
> **PostgreSQL version:** the default RHEL 9 module stream may be older than the
> PostgreSQL 16 used on Ubuntu 24.04. If your package requires a specific
> version, add the official PGDG repository instead of the base module.

## Step 3: Install the Microsoft core fonts

Document Server renders documents using Microsoft TrueType core fonts, so they
must be present **before** you install the package. On RPM systems these come
from the `msttcore-fonts-installer`, which needs a few helper tools first:

```bash
sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig
sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
```

This is the RPM equivalent of Debian's `ttf-mscorefonts-installer`. The fonts
installer carries a EULA — this is what the Dockerfile's `ACCEPT_EULA=Y` is for.

## Step 4: Initialize and prepare PostgreSQL

Unlike Debian, RHEL does **not** initialize a database cluster or start the
service on install. Do both explicitly:

```bash
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
```

The default `pg_hba.conf` uses `ident` authentication for TCP connections, which
rejects the password login the server uses. Switch the `localhost` lines to
`scram-sha-256`. Note that `localhost` resolves to IPv6 (`::1`) first on Fedora,
so **both** the `127.0.0.1/32` and `::1/128` lines must be changed:

```bash
HBA=$(sudo -u postgres psql -tAc "SHOW hba_file;")
sudo -u postgres sed -i -E '/^(host|hostssl|hostnossl)/ s/\bident\b/scram-sha-256/g' "$HBA"
sudo -u postgres psql -c "SELECT pg_reload_conf();"
```

Confirm the change took (every host line should read `scram-sha-256`):

```bash
sudo -u postgres psql -c "SELECT line_number, address, auth_method \
FROM pg_hba_file_rules WHERE type IN ('host','hostssl','hostnossl') ORDER BY line_number;"
```

Create the role and database the server will connect to:

```bash
sudo -u postgres psql -c "CREATE USER eurooffice WITH PASSWORD 'eurooffice';"
sudo -u postgres psql -c "CREATE DATABASE eurooffice OWNER eurooffice;"
```

Then enable and start the remaining services (also not auto-started on RHEL):

```bash
sudo systemctl enable --now redis rabbitmq-server nginx
```

> **Production note:** `eurooffice` / `eurooffice` are the defaults from our
> ephemeral Docker image. Use a strong password for a real deployment, and reuse
> it in Step 7.

## Step 5: Download the package

Download the build matching your version, build number, and architecture. RPM
uses `x86_64`/`aarch64`, not the `amd64`/`arm64` names used for `.deb`:

```bash
wget https://github.com/Euro-Office/DocumentServer/releases/download/v{version}-{build}/euro-office-documentserver_{version}-{build}_{platform}.deb -O documentserver.rpm
```

Replace `version` and `build` and `platform` with the release you are installing.

## Step 6: Install the package

```bash
sudo dnf install -y ./documentserver.rpm
```

Using `dnf install` (rather than `rpm -i`) resolves any remaining dependencies
automatically. Do **not** set `DS_DOCKER_INSTALLATION=true` — that flag is only
for our Docker build.

## Step 7: Configure the Document Server

Run the bundled configuration script. This is the recommended way to set the
database, Redis, and RabbitMQ connections — much easier and less error-prone
than editing the config files by hand:

```bash
sudo documentserver-configure.sh
```

It prompts interactively for the connection details, writes the configuration,
and initializes the database schema. Supply the values from Step 4 (PostgreSQL
host `localhost`, port `5432`, database/user/password `eurooffice`).

> **Manual alternative.** If you need an unattended setup instead of the
> interactive script, you can edit the config file directly under your config
> root (`EO_CONF`, i.e. `/etc/<company>/<product>/local.json`):
>
> ```json
> {
>   "services": { "CoAuthoring": { "sql": {
>     "type": "postgres", "dbHost": "localhost", "dbPort": "5432",
>     "dbName": "eurooffice", "dbUser": "eurooffice", "dbPass": "eurooffice"
>   } } }
> }
> ```

## Step 8: Resolve the nginx port conflict (Fedora)

On Fedora, the stock `nginx` ships its own `server` block on port 80 in
`/etc/nginx/nginx.conf`, which conflicts with the Document Server's nginx config
(it can shadow or override the package's site). The simplest fix is to change
the Document Server's `listen` port to a free one.

Find which files nginx actually loads, and which blocks claim which port:

```bash
sudo nginx -T 2>/dev/null | grep -E "configuration file|listen|server_name"
```

Locate the Document Server's nginx config from the `# configuration file`
headers, change its `listen` directive to a free port (or resolve the
`default_server` conflict — only one `default_server` per port is allowed),
then validate and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Step 9: Enable and start the Document Server services

The package's services are not enabled or started automatically. Enable and
start them (`--now` does both):

```bash
sudo systemctl enable --now ds-docservice.service ds-example.service
```

List all units the package provides in case there are others to enable
(e.g. a converter or metrics service):

```bash
systemctl list-unit-files 'ds-*'
```

> This service enable/start step is required on **Debian/Ubuntu** too — the
> `.deb` package likewise does not start these services for you.

## Step 10: Flush the cache

```bash
sudo documentserver-flush-cache.sh -r false
```

## Verify the installation

Browse to the host on the port set in Step 8 (for example
`http://<server-ip>:<port>/`) to confirm the welcome/example page loads, and
check the logs under `/var/log/<company>/<product>/`.

## Troubleshooting

**Page returns 403 or 502 (SELinux).** RHEL/Fedora ship with SELinux enforcing,
which blocks nginx from reaching its upstream by default. Allow it:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

**Page unreachable (firewall).** Open the port you set in Step 8 in firewalld,
e.g. for HTTP/HTTPS:

```bash
sudo firewall-cmd --add-service=http --add-service=https --permanent
sudo firewall-cmd --reload
```

**`Ident authentication failed` for the database.** The `pg_hba.conf` change in
Step 4 did not take. Re-run the `pg_hba_file_rules` query there to confirm every
host line reads `scram-sha-256`, and that `pg_reload_conf()` was run. Remember
both the `127.0.0.1/32` and `::1/128` lines must be changed.

**Services won't start.** Check `journalctl -u ds-docservice.service` and verify
Step 7 completed — the services need a valid database configuration to start.

## Differences from the Debian install

- **No debconf — use `documentserver-configure.sh`.** RPM has no install-time
  prompt; the configuration script (Step 7) sets the connections instead. (The
  same script also exists on Debian and can be used there.)
- **Microsoft fonts** come from the SourceForge `msttcore-fonts-installer`
  (Step 3), not Debian's `ttf-mscorefonts-installer`.
- **EPEL required** for RabbitMQ, Supervisor, and sometimes `jq` (Step 1).
- **PostgreSQL is not auto-set-up.** RHEL needs `postgresql-setup --initdb`, an
  explicit start, and the `pg_hba.conf` change (Step 4).
- **Services start disabled** — Redis/RabbitMQ/Nginx and the `ds-*` units must
  be enabled and started explicitly. (Enabling the `ds-*` units is needed on
  Debian too.)
- **No `nginx-extras`**, and Fedora's stock nginx server block conflicts on
  port 80 (Step 8).
- **Different package names and architecture labels** (`nmap-ncat` vs
  `netcat-openbsd`, `x86_64`/`aarch64` vs `amd64`/`arm64`).
- **SELinux and firewalld** are active by default and may need the adjustments
  in Troubleshooting.

As with the Debian guide, the Docker-only pieces — `DS_DOCKER_INSTALLATION`,
the supervisor configs, and the custom entrypoint — are not used in a standalone
install.