#!/usr/bin/env bash
# provision-rpm.sh — Vagrant provisioner for Rocky Linux 9 (and RHEL-family) VMs.
# Installs prerequisites, the .rpm package from /pkgs, and starts all services.
# The VM is left running for manual inspection.
set -euo pipefail

PKG_DIR="/pkgs"
RPM=$(ls "${PKG_DIR}"/*.rpm 2>/dev/null | head -1 || true)

if [ -z "$RPM" ]; then
  echo "ERROR: No .rpm found in ${PKG_DIR}. Run 'make packages' first." >&2
  exit 1
fi

echo "========================================================"
echo " Installing: $(basename "$RPM")"
echo "========================================================"

# ---------------------------------------------------------------------------
# 1. Enable EPEL (needed for nginx, rabbitmq, and other deps)
# ---------------------------------------------------------------------------
dnf install -y epel-release
dnf install -y dnf-plugins-core

# Enable CRB (CodeReady Builder) for additional dependencies
dnf config-manager --set-enabled crb || true

# ---------------------------------------------------------------------------
# 2. Install prerequisites
# ---------------------------------------------------------------------------
# rabbitmq-server was dropped from EPEL for EL 9 — add the official repo.
if ! dnf repolist enabled | grep -q rabbitmq; then
  cat > /etc/yum.repos.d/rabbitmq-server.repo <<'REPO'
[rabbitmq-server]
name=rabbitmq-server
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/9/$basearch
gpgcheck=0
enabled=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
REPO
fi

dnf install -y \
  postgresql-server postgresql \
  redis rabbitmq-server \
  nginx supervisor \
  curl sudo ca-certificates \
  liberation-mono-fonts \
  logrotate openssl cabextract xdg-utils

# ---------------------------------------------------------------------------
# 3. Initialize and start PostgreSQL
# ---------------------------------------------------------------------------
if [ ! -f /var/lib/pgsql/data/PG_VERSION ]; then
  postgresql-setup --initdb
fi

systemctl enable --now postgresql
sleep 2

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='onlyoffice'" \
  | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER onlyoffice WITH PASSWORD 'onlyoffice';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='onlyoffice'" \
  | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE onlyoffice OWNER onlyoffice;"

# PostgreSQL on RHEL defaults to ident auth; switch to md5 for local TCP
PG_HBA=$(sudo -u postgres psql -tc "SHOW hba_file" | tr -d ' ')
if [ -f "$PG_HBA" ]; then
  sed -i 's/^\(host.*all.*all.*127\.0\.0\.1\/32\s*\)ident/\1md5/' "$PG_HBA"
  sed -i 's/^\(host.*all.*all.*::1\/128\s*\)ident/\1md5/' "$PG_HBA"
  systemctl reload postgresql
fi

# ---------------------------------------------------------------------------
# 4. Start Redis and RabbitMQ
# ---------------------------------------------------------------------------
systemctl enable --now redis
systemctl enable --now rabbitmq-server

# ---------------------------------------------------------------------------
# 5. Install the .rpm package
# ---------------------------------------------------------------------------
# Remove previous installation so this acts as a clean reinstall
PKG_NAME=$(rpm -qp --queryformat '%{NAME}' "$RPM" 2>/dev/null)
if rpm -q "$PKG_NAME" &>/dev/null; then
  echo "Package ${PKG_NAME} already installed — removing before reinstall."
  dnf remove -y "$PKG_NAME" || true
fi

# Use dnf to resolve as many dependencies as possible from repos.
# --nogpgcheck since the package is locally built and unsigned.
dnf install -y --nogpgcheck "$RPM" || {
  echo "WARN: dnf install failed, trying rpm -ivh with --nodeps as fallback..."
  rpm -ivh --nodeps "$RPM"
}

# ---------------------------------------------------------------------------
# 6. Start document server services
# ---------------------------------------------------------------------------
# Flush cache to generate ds-cache.conf for nginx
if command -v documentserver-flush-cache.sh &>/dev/null; then
  documentserver-flush-cache.sh -r false || true
fi

# Enable and start the document server systemd services
for svc in ds-docservice ds-converter ds-metrics; do
  if systemctl list-unit-files "${svc}.service" &>/dev/null; then
    systemctl enable --now "${svc}" || true
  fi
done

# nginx needs the document server config; SELinux may also need port access
setsebool -P httpd_can_network_connect on 2>/dev/null || true
systemctl enable --now nginx
systemctl restart nginx || true
systemctl start ds-example || true

# ---------------------------------------------------------------------------
# 7. Print status
# ---------------------------------------------------------------------------
echo ""
echo "========================================================"
echo " Provisioning complete"
echo "========================================================"
echo ""
echo "Services:"
for svc in postgresql redis rabbitmq-server nginx ds-docservice ds-converter ds-metrics; do
  printf "  %-25s %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo 'unknown')"
done
echo ""
echo "Healthcheck URL (inside VM):  curl -sf http://localhost/healthcheck"
echo "Healthcheck URL (from host):  curl -sf http://localhost:<forwarded-port>/healthcheck"
echo ""
echo "The document server may take a minute to fully initialize (font generation, etc.)."
echo "SSH in with:  vagrant ssh <vm-name>"
