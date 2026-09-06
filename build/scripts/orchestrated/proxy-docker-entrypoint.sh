#!/usr/bin/env bash
set -e

# Fail closed on an insecure default secure-link secret. This value signs the
# internal cache/file URLs and MUST be identical to the one the Docs replicas
# use (see docker-entrypoint.sh), so it cannot be generated per-pod — it has to
# be supplied explicitly (e.g. via a Kubernetes Secret). Refuse to start with
# the known upstream placeholder rather than serve forgeable signed URLs.
if [ -z "${SECURE_LINK_SECRET:-}" ]; then
  echo "ERROR: SECURE_LINK_SECRET is not set. Provide a strong shared value matching the Docs replicas (e.g. via a Kubernetes Secret). Refusing to start with an insecure default." >&2
  exit 1
fi

if ! [ -d /tmp/proxy_nginx ]; then
  mkdir /tmp/proxy_nginx
fi

cp -r /etc/nginx/* /tmp/proxy_nginx/
sed 's|\(worker_connections\) [[:digit:]]*;|\1 '$NGINX_WORKER_CONNECTIONS';|g' -i /tmp/proxy_nginx/nginx.conf
sed "s/\(worker_processes\).*/\1 $NGINX_WORKER_PROCESSES;/" -i /tmp/proxy_nginx/nginx.conf

if [[ -n "$NGINX_LOG_FORMAT" ]]; then
  sed "s/\(log_format  main\).*/\1 '$NGINX_LOG_FORMAT';/" -i /tmp/proxy_nginx/nginx.conf
fi

if [[ "$NGINX_ACCESS_LOG" != "off" ]]; then
  sed 's|#*\(\s*access_log\).*;|\1 /var/log/nginx/access.log '$NGINX_ACCESS_LOG';|g' -i /tmp/proxy_nginx/nginx.conf
fi

envsubst < /tmp/proxy_nginx/includes/http-upstream.conf > /tmp/http-upstream.conf
envsubst < /etc/nginx/includes/ds-common.conf | tee /tmp/proxy_nginx/includes/ds-common.conf > /dev/null
sed "s,\(set \+\$secure_link_secret\).*,\1 "${SECURE_LINK_SECRET}";," -i /tmp/proxy_nginx/conf.d/ds.conf
sed "s/\(client_max_body_size\).*/\1 $NGINX_CLIENT_MAX_BODY_SIZE;/" -i /tmp/proxy_nginx/includes/ds-common.conf

if [[ ! -f "/proc/net/if_inet6" ]]; then
  sed '/listen\s\+\[::[0-9]*\].\+/d' -i /tmp/proxy_nginx/conf.d/ds.conf
fi

WELCOME_PATH="/var/www/$COMPANY_NAME/documentserver-example/welcome"
WELCOME_PAGE="$WELCOME_PATH/k8s.html"
ADMIN_PANEL_DISABLED_PAGE="$WELCOME_PATH/admin-disabled.html"
EXAMPLE_DISABLED_PAGE="$WELCOME_PATH/example-disabled.html"
if [[ -n "$DOCS_SHARDS" ]]; then
  sed -i 's/\(Kubernetes-Docs\)\(-Shards\)\?/\1-Shards/g' "$WELCOME_PAGE"
  sed -Ei 's|<pre>sudo systemctl start ds-(adminpanel\|example).*</pre>|<pre>\helm upgrade documentserver onlyoffice/docs-shards --set \1.enabled=true</pre>|g' "$ADMIN_PANEL_DISABLED_PAGE" "$EXAMPLE_DISABLED_PAGE"
else
  sed -Ei 's|<pre>sudo systemctl start ds-(adminpanel\|example).*</pre>|<pre>\helm upgrade documentserver onlyoffice/docs --set \1.enabled=true</pre>|g' "$ADMIN_PANEL_DISABLED_PAGE" "$EXAMPLE_DISABLED_PAGE"
fi

for page in \
  "$WELCOME_PAGE" \
  "$ADMIN_PANEL_DISABLED_PAGE" \
  "$EXAMPLE_DISABLED_PAGE"
do
  gzip -cf9 "$page" > "$page.gz"
done

if [[ -n "$INFO_ALLOWED_IP" ]]; then
  declare -a IP_ALL=($INFO_ALLOWED_IP)
  for ip in "${IP_ALL[@]}"; do
    sed -i '/(info)/a\  allow '$ip'\;' /tmp/proxy_nginx/includes/ds-docservice.conf
  done
fi

if [[ -n "$INFO_ALLOWED_USER" ]]; then
  if [[ -z "${INFO_ALLOWED_PASSWORD:-}" ]]; then
    echo "ERROR: INFO_ALLOWED_USER is set but INFO_ALLOWED_PASSWORD is empty. Refusing to expose /info behind a default password." >&2
    exit 1
  fi
  htpasswd -c -b /tmp/auth "${INFO_ALLOWED_USER}" "${INFO_ALLOWED_PASSWORD}"
  sed -i '/(info)/a\  auth_basic \"Authentication Required\"\;' /tmp/proxy_nginx/includes/ds-docservice.conf
  sed -i '/auth_basic/a\  auth_basic_user_file \/tmp\/auth\;' /tmp/proxy_nginx/includes/ds-docservice.conf
fi

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
shift $((OPTIND - 1))

if [[ "${BUILD_FONTS}" == "true" ]]; then
  if [ "$(find "$WORK_DIR/fonts" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo -e "\e[0;32m Fonts have already been added, preparatory steps, please wait... \e[0m"
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/AllFonts.js $WORK_DIR/sdkjs/common/
    gzip -cf9 "$WORK_DIR/sdkjs/common/AllFonts.js" > "$WORK_DIR/sdkjs/common/AllFonts.js.gz" && chown ds:ds "$WORK_DIR/sdkjs/common/AllFonts.js.gz"
    echo -e "\e[0;32m Completed \e[0m"
  else
    echo -e "\e[0;32m Run Fonts adding, please wait... \e[0m"
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/Images/* $WORK_DIR/sdkjs/common/Images/
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/themes/* $WORK_DIR/sdkjs/slide/themes/
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/fonts/* $WORK_DIR/fonts/
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/custom-k8s/* $WORK_DIR/core-fonts/custom-k8s/
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/fonts/AllFonts.js $WORK_DIR/sdkjs/common/
    find $WORK_DIR/fonts \
      -type f ! \
      -name "*.*" \
      -exec sh -c 'gzip -cf9 $0 > $0.gz && chown ds:ds $0.gz' {} \;
    chmod 755 $WORK_DIR/sdkjs/common/Images/cursors/
    find $WORK_DIR/sdkjs/common \
      $WORK_DIR/sdkjs/slide/themes \
      -type f \
      \( -name '*.js' -o -name '*.json' -o -name '*.htm' -o -name '*.html' -o -name '*.css' \) \
      -exec sh -c 'gzip -cf9 $0 > $0.gz && chown ds:ds $0.gz' {} \;
    chmod 555 $WORK_DIR/sdkjs/common/Images/cursors/
    echo -e "\e[0;32m Fonts have been added successfully \e[0m"
  fi
fi

if [[ "${BUILD_PLUGINS}" == "true" ]]; then
  if [ "$(find "$WORK_DIR/sdkjs-plugins" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo -e "\e[0;32m Plugins have already been added... \e[0m"
  else
    echo -e "\e[0;32m Run Plugins adding, please wait... \e[0m"
    cp -a /var/lib/$COMPANY_NAME/documentserver/buffer/plugins/sdkjs-plugins/* $WORK_DIR/sdkjs-plugins/
    find $WORK_DIR/sdkjs-plugins/* -type d -exec chmod u+w {} \;
    find $WORK_DIR/sdkjs-plugins \
      -type f \
      \( -name '*.js' -o -name '*.json' -o -name '*.htm' -o -name '*.html' -o -name '*.css' \) \
      -exec sh -c 'gzip -cf9 $0 > $0.gz && chown ds:ds $0.gz' {} \;
    echo -e "\e[0;32m Plugins have been added successfully \e[0m"
  fi
fi

if [[ "${BUILD_DICTIONARIES}" == "true" ]]; then
  echo -e "\e[0;32m Run Dictionaries adding, please wait... \e[0m"
  ( find $WORK_DIR/sdkjs/cell $WORK_DIR/sdkjs/word $WORK_DIR/sdkjs/slide $WORK_DIR/sdkjs/visio -maxdepth 1 -type f -name '*.js'
    echo "$WORK_DIR/sdkjs/common/spell/spell/spell.js" ) | while read -r file; do
      chmod 740 "$file"
      dir=$(basename "$(dirname "$file")")
      base_file=$(basename "$file")
      if [[ "${base_file}" == "spell.js" ]]; then
        target_dir="$WORK_DIR/sdkjs/common/spell/$dir"
      else
        target_dir="$WORK_DIR/sdkjs/$dir"
      fi
      cp -a "/var/lib/$COMPANY_NAME/documentserver/buffer/dictionaries/$dir/$base_file" "$target_dir/"
      gzip -cf9 "$target_dir/$base_file" > "$target_dir/$base_file.gz"
      chmod 440 "$target_dir/$base_file"
  done
  if [ "$(find "$WORK_DIR/dictionaries" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo -e "\e[0;32m Completed \e[0m"
  else
    cp -ra /var/lib/$COMPANY_NAME/documentserver/buffer/dictionaries/dictionaries/* $WORK_DIR/dictionaries/
    echo -e "\e[0;32m Dictionaries have been added successfully \e[0m"
  fi
fi

if [[ "$BUILD_FONTS" == "true" || "$BUILD_PLUGINS" == "true" || "$BUILD_DICTIONARIES" == "true" ]]; then
  echo "set \$cache_tag \"$DS_VERSION_HASH\";" > /tmp/proxy_nginx/includes/ds-cache.conf
  API_PATH="$WORK_DIR/web-apps/apps/api/documents/api.js"
  chmod 755 $(dirname "$API_PATH")
  cp -f ${API_PATH}.tpl ${API_PATH}
  sed -i "s/{{HASH_POSTFIX}}/${DS_VERSION_HASH}/g" ${API_PATH}
  rm -f ${API_PATH}.gz
  gzip -cf9 "$API_PATH" > "$API_PATH.gz"
  chmod 555 $(dirname "$API_PATH")
fi

exec nginx -c /tmp/proxy_nginx/nginx.conf -g 'daemon off;'
