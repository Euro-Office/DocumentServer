import { spawnSync } from 'child_process';
import { CONTAINER_NAME } from './constants';

export default async function globalTeardown(): Promise<void> {
  if (process.env.E2E_DOCKER_MANAGED !== 'true') {
    // Container was not started by us — leave it running
    return;
  }
  console.log(`[global-teardown] Removing container ${CONTAINER_NAME}...`);
  spawnSync('docker', ['rm', '-f', CONTAINER_NAME], { stdio: 'inherit' });
}
