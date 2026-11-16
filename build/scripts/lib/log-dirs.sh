# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=sh
#
# Sourced by the standalone entrypoint. POSIX sh.
#
# ensure_log_dirs CONF_DIR: create the parent directory of every
# stdout_logfile/stderr_logfile in CONF_DIR/*.conf. supervisord refuses to
# start a program whose log directory is missing, which is the case when an
# empty bind mount covers $EO_LOG. %(ENV_EO_LOG)s expands to $EO_LOG.

ensure_log_dirs() {
  sed -n 's/^std[a-z]*_logfile[[:space:]]*=[[:space:]]*//p' "$1"/*.conf 2>/dev/null \
    | sed "s|%(ENV_EO_LOG)s|${EO_LOG}|g" \
    | while IFS= read -r _ld_file; do
        case "$_ld_file" in
          /*) mkdir -p "${_ld_file%/*}" ;;
        esac
      done
}
