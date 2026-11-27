#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cert_dir="$script_dir/.redis-tls"

if [ -s "$cert_dir/server.key" ] &&
  openssl x509 -in "$cert_dir/server.crt" -checkend 86400 -noout >/dev/null 2>&1 &&
  openssl verify -CAfile "$cert_dir/ca.crt" "$cert_dir/server.crt" >/dev/null 2>&1; then
  exit 0
fi

umask 077
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
  -subj '/CN=Euro-Office Redis test CA' \
  -keyout "$temp_dir/ca.key" -out "$temp_dir/ca.crt" 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=redis' \
  -keyout "$temp_dir/server.key" -out "$temp_dir/server.csr" 2>/dev/null

cat > "$temp_dir/extensions.cnf" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@hosts
[hosts]
DNS.1=localhost
DNS.2=redis
DNS.3=redis-primary
DNS.4=redis-replica
DNS.5=redis-sentinel-1
DNS.6=redis-sentinel-2
DNS.7=redis-sentinel-3
DNS.8=redis-cluster-1
DNS.9=redis-cluster-2
DNS.10=redis-cluster-3
DNS.11=redis-cluster-4
DNS.12=redis-cluster-5
DNS.13=redis-cluster-6
IP.1=127.0.0.1
IP.2=::1
EOF

openssl x509 -req -in "$temp_dir/server.csr" -CA "$temp_dir/ca.crt" \
  -CAkey "$temp_dir/ca.key" -CAcreateserial -days 365 -sha256 \
  -extfile "$temp_dir/extensions.cnf" -out "$temp_dir/server.crt" 2>/dev/null

mkdir -p "$cert_dir"
# These test credentials must be readable by the containers' Redis/Valkey users.
# The CA private key stays in the temporary directory and is removed on exit.
chmod 755 "$cert_dir"
for file in ca.crt server.crt server.key; do
  cp "$temp_dir/$file" "$cert_dir/$file"
  chmod 644 "$cert_dir/$file"
done
echo "Generated Redis/Valkey test TLS certificates in $cert_dir"
