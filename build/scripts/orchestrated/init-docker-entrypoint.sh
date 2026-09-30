#!/usr/bin/env bash
set -e

WORK_DIR="/var/www/$COMPANY_NAME/documentserver"
BUILD_FONTS=false
BUILD_PLUGINS=false
BUILD_DICTIONARIES=false

OPTIND=1
while getopts ":fpd" opt; do
  case "$opt" in
    f) BUILD_FONTS=true ;;
    p) BUILD_PLUGINS=true ;;
    d) BUILD_DICTIONARIES=true ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      exit 2
      ;;
  esac
done
shift $((OPTIND-1))

# Normalize boolean env vars: accept True/TRUE/yes/on/1 (as written by e.g.
# Ansible or compose files) and canonicalize to lowercase true/false. The
# values end up raw inside JSON, where anything else is invalid. Empty values
# are left untouched so the ${VAR:-default} fallbacks still apply.
#
# normalize_bool: an unrecognized value warns and becomes false.
# require_bool:   an unrecognized value aborts startup. Use it for
#                 security-relevant flags (JWT), where silently falling back
#                 to false would disable authentication.
_normalize_bool() {
  local mode="$1" var val
  shift
  for var in "$@"; do
    val="${!var:-}"
    case "${val,,}" in
      "") ;;
      true|yes|y|on|1)  printf -v "$var" '%s' true ;;
      false|no|n|off|0) printf -v "$var" '%s' false ;;
      *)
        if [[ "$mode" == "strict" ]]; then
          echo "ERROR: ${var}='${val}' is not a recognized boolean (use true or false). Refusing to start rather than guess." >&2
          exit 1
        fi
        echo "WARNING: ${var}='${val}' is not a recognized boolean (use true/false); treating it as false" >&2
        printf -v "$var" '%s' false
        ;;
    esac
  done
}
normalize_bool() { _normalize_bool lenient "$@"; }
require_bool()   { _normalize_bool strict "$@"; }

normalize_bool PLUGINS_MARKET_DISABLED

cleanup_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    chmod 755 -R "$dir"
    rm -rf "$dir"
  fi
}

build_fonts() {
  [[ "$BUILD_FONTS" != "true" ]] && return
  echo -e "\e[0;32m The build of new Fonts is running, please wait... \e[0m"
  local buffer_dir="/var/lib/$COMPANY_NAME/documentserver/buffer/fonts"
  cleanup_dir "$buffer_dir"
  chmod 755 "$WORK_DIR/sdkjs/common"
  chmod 755 "$WORK_DIR/sdkjs/common/Images"
  chmod 755 "$WORK_DIR/sdkjs/slide/themes"
  chmod 755 "$WORK_DIR/server/FileConverter/bin"
  /usr/local/bin/documentserver-generate-allfonts.sh true true
  mkdir -p "$buffer_dir/bin"
  cp -ra "$WORK_DIR/sdkjs/common/Images/" "$buffer_dir/"
  cp -ra "$WORK_DIR/sdkjs/slide/themes/" "$buffer_dir/"
  cp -ra "$WORK_DIR/fonts" "$buffer_dir/"
  cp -ra "$WORK_DIR/core-fonts/custom-k8s" "$buffer_dir/"
  cp -a "$WORK_DIR/sdkjs/common/AllFonts.js" "$buffer_dir/"
  cp -a \
    "$WORK_DIR/server/FileConverter/bin/AllFonts.js" \
    "$WORK_DIR/server/FileConverter/bin/font_selection.bin" \
    "$WORK_DIR/server/FileConverter/bin/fonts.log" \
    "$buffer_dir/bin/"
  echo -e "\e[0;32m Changed files have been added successfully \e[0m"
}

build_plugins() {
  [[ "$BUILD_PLUGINS" != "true" ]] && return
  echo -e "\e[0;32m The build of new Plugins is running, please wait... \e[0m"
  local buffer_dir="/var/lib/$COMPANY_NAME/documentserver/buffer/plugins"
  cleanup_dir "$buffer_dir"
  chmod 755 "$WORK_DIR/sdkjs-plugins"
  if [[ -n "$PLUGINS_LIST_DEFAULT" ]]; then
    find "$WORK_DIR/sdkjs-plugins" -mindepth 1 -maxdepth 1 -name '{*' -exec rm -rf -- {} +
  fi
  if [[ "${PLUGINS_MARKET_DISABLED}" == "true" ]]; then
    chmod 755 -R "$WORK_DIR/sdkjs-plugins/marketplace"
    rm -rf "$WORK_DIR/sdkjs-plugins/marketplace"
  fi
  /usr/local/bin/documentserver-pluginsmanager.sh -r false -k true --update=\"/var/www/$COMPANY_NAME/documentserver/sdkjs-plugins/plugin-list-default.json\"
  mkdir -p "$buffer_dir"
  cp -ra "$WORK_DIR/sdkjs-plugins" "$buffer_dir/"
  echo -e "\e[0;32m Changed files have been added successfully \e[0m"
}

build_dictionaries() {
  [[ "$BUILD_DICTIONARIES" != "true" ]] && return
  echo -e "\e[0;32m The build of new Dictionaries is running, please wait... \e[0m"
  local buffer_dir="/var/lib/$COMPANY_NAME/documentserver/buffer/dictionaries"
  cleanup_dir "$buffer_dir"
  ( find "$WORK_DIR/sdkjs/cell" "$WORK_DIR/sdkjs/word" "$WORK_DIR/sdkjs/slide" "$WORK_DIR/sdkjs/visio" -maxdepth 1 -type f \( -name '*.js' -o -name '*.bin' \)
    echo "$WORK_DIR/sdkjs/common/spell/spell/spell.js" ) | while read -r file; do
      chmod 755 "$(dirname "$file")"
      chmod 740 "$file"
  done
  chmod 755 "$WORK_DIR/dictionaries"
  python3 "$WORK_DIR/server/dictionaries/update.py"
  mkdir -p "$buffer_dir/spell"
  ( find "$WORK_DIR/sdkjs/cell" "$WORK_DIR/sdkjs/word" "$WORK_DIR/sdkjs/slide" "$WORK_DIR/sdkjs/visio" -maxdepth 1 -type f \( -name '*.js' -o -name '*.bin' \)
    echo "$WORK_DIR/sdkjs/common/spell/spell/spell.js" ) | while read -r file; do
      dir=$(basename "$(dirname "$file")")
      mkdir -p "$buffer_dir/$dir"
      cp -a "$file" "$buffer_dir/$dir/"
  done
  cp -ra "$WORK_DIR/dictionaries" "$buffer_dir/"
  echo -e "\e[0;32m Changed files have been added successfully \e[0m"
}

build_fonts
build_plugins
build_dictionaries
