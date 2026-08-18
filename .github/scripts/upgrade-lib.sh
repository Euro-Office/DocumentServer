#!/bin/sh
# Helpers for the upgrade-path job in build.yml. Sourced, not executed: the two
# steps that boot a container run in separate shells and both need `boot`.
#
# Expects VOLUME_DB, VOLUME_DATA and BOOT_TIMEOUT from the job env.

# boot <image> <container-name> — start the standalone image on the shared
# volumes and block until /healthcheck answers true. Fails fast if the
# container exits instead of waiting out the timeout on a crash loop.
boot() {
  image="$1"
  name="$2"

  echo "Booting ${name} from ${image}"
  docker run -d --name "$name" \
    -v "${VOLUME_DB}:/var/lib/postgresql" \
    -v "${VOLUME_DATA}:/var/www/euro-office/Data" \
    "$image" >/dev/null

  deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  until [ "$(docker exec "$name" curl -sf http://localhost/healthcheck 2>/dev/null)" = "true" ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
      echo "::error::${name} exited with code $(docker inspect -f '{{.State.ExitCode}}' "$name")"
      docker logs "$name" 2>&1 | tail -40
      return 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "::error::${name} did not report healthy within ${BOOT_TIMEOUT}s"
      docker logs "$name" 2>&1 | tail -40
      return 1
    fi
    sleep 5
  done

  echo "${name} is healthy"
}
