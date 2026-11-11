# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=sh
#
# Boolean env var normalization, sourced by the standalone and orchestrated
# entrypoints. POSIX sh, so it runs the same under dash and bash.
#
# Tools such as Ansible write YAML booleans as "True"/"False", and compose
# files often use "1"/"yes". The entrypoints compare against the literal
# "true" or paste the value raw into JSON, so canonicalize first.
#
# Accepted (case-insensitive, surrounding whitespace ignored):
#   true, yes, y, on, 1   -> true
#   false, no, n, off, 0  -> false
# Empty values stay empty, so ${VAR:-default} fallbacks still apply.
#
# normalize_bool VAR...: an unrecognized value warns and is cleared, so the
#                        variable's own default applies.
# require_bool VAR...:   an unrecognized value aborts startup. Use it for
#                        security-relevant flags (JWT), where guessing could
#                        disable authentication.

normalize_bool() { _normalize_bool lenient "$@"; }
require_bool()   { _normalize_bool strict "$@"; }

_normalize_bool() {
  _nb_mode=$1
  shift
  for _nb_var in "$@"; do
    eval "_nb_val=\${$_nb_var-}"
    # Trim leading and trailing whitespace, including newlines.
    _nb_val=${_nb_val#"${_nb_val%%[![:space:]]*}"}
    _nb_val=${_nb_val%"${_nb_val##*[![:space:]]}"}
    case "$_nb_val" in
      "") eval "$_nb_var=" ;;
      [Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Yy]|[Oo][Nn]|1)     eval "$_nb_var=true" ;;
      [Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]|[Nn]|[Oo][Ff][Ff]|0) eval "$_nb_var=false" ;;
      *)
        if [ "$_nb_mode" = "strict" ]; then
          echo "ERROR: ${_nb_var}='${_nb_val}' is not a recognized boolean (use true or false). Refusing to start rather than guess." >&2
          exit 1
        fi
        echo "WARNING: ${_nb_var}='${_nb_val}' is not a recognized boolean (use true or false); ignoring it and using the default" >&2
        eval "$_nb_var="
        ;;
    esac
  done
}
