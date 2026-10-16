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
  echo -e "\e[0;32m Copying Plugins to the shared buffer, please wait... \e[0m"
  local buffer_dir="/var/lib/$COMPANY_NAME/documentserver/buffer/plugins"
  cleanup_dir "$buffer_dir"
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
