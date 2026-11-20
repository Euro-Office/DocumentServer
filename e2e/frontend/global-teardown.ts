import { spawnSync } from 'child_process';
import { mkdirSync, rmSync, writeFileSync } from 'fs';
import { join, resolve } from 'path';
import { CONTAINER_NAME } from './constants';

// Kept next to playwright-report/ so CI can upload it as its own artifact. It is
// what tells a slow server (conversions queued) from a broken one (errors).
const SERVER_LOGS_DIR = resolve(__dirname, '../server-logs');
const CONTAINER_LOGS_DIR = '/var/log/euro-office/documentserver';

// A hung docker daemon must not stall teardown, or `docker rm -f` never runs.
const DOCKER_TIMEOUT_MS = 60_000;

// Best effort: a failure here must never mask the test results.
function saveServerLogs(): void {
  // docker cp merges into an existing folder, so clear leftovers from earlier
  // runs or old and new service logs end up side by side.
  rmSync(SERVER_LOGS_DIR, { recursive: true, force: true });
  mkdirSync(SERVER_LOGS_DIR, { recursive: true });

  const logs = spawnSync('docker', ['logs', CONTAINER_NAME], {
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
    timeout: DOCKER_TIMEOUT_MS,
  });
  const logsSaved = logs.status === 0;
  if (logsSaved) {
    // docker logs writes the container's stdout and stderr to the matching streams.
    writeFileSync(join(SERVER_LOGS_DIR, 'container.log'), `${logs.stdout}${logs.stderr}`);
  } else {
    console.warn(
      `[global-teardown] could not read container logs: ${logs.error?.message ?? logs.stderr}`,
    );
  }

  const copy = spawnSync(
    'docker',
    ['cp', `${CONTAINER_NAME}:${CONTAINER_LOGS_DIR}/.`, SERVER_LOGS_DIR],
    { encoding: 'utf8', timeout: DOCKER_TIMEOUT_MS },
  );
  const copySaved = copy.status === 0;
  if (!copySaved) {
    console.warn(
      `[global-teardown] could not copy server logs: ${copy.error?.message ?? copy.stderr}`,
    );
  }

  if (logsSaved && copySaved) {
    console.log(`[global-teardown] Server logs saved to ${SERVER_LOGS_DIR}`);
  }
}

export default async function globalTeardown(): Promise<void> {
  if (process.env.E2E_DOCKER_MANAGED !== 'true') {
    // Container was not started by us — leave it running
    return;
  }
  try {
    saveServerLogs();
  } catch (error) {
    console.warn(`[global-teardown] could not save server logs: ${String(error)}`);
  }
  console.log(`[global-teardown] Removing container ${CONTAINER_NAME}...`);
  spawnSync('docker', ['rm', '-f', CONTAINER_NAME], { stdio: 'inherit' });
}
