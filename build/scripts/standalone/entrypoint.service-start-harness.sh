#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

# Called only by entrypoint.tests.sh --services in a fresh, disposable container.
[[ -f /.dockerenv && $(id -u) == 0 ]] || {
  echo 'This harness requires a disposable Docker container running as root.' >&2
  exit 1
}

stub_dir=$(mktemp -d)
cat >"$stub_dir/service" <<'EOF'
#!/bin/sh
printf 'service %s\n' "$*" >>"$ENTRYPOINT_CALLS"
EOF
cat >"$stub_dir/handoff" <<'EOF'
#!/bin/sh
printf 'handoff %s\n' "$*" >>"$ENTRYPOINT_CALLS"
EOF
# The installed helper edits the image's application configuration. This test
# only needs the entrypoint's own configuration generation and service choices.
printf '#!/bin/sh\nexit 0\n' >"$stub_dir/documentserver-update-securelink.sh"
chmod +x "$stub_dir/"*
ln -sf "$stub_dir/handoff" /usr/bin/tini
export PATH="$stub_dir:$PATH"

exec bash "$(dirname "$0")/entrypoint.tests.sh" --container-services
