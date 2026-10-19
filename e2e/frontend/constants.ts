// Single source of truth for the Docker-managed server location.
// playwright.config.ts (evaluated before globalSetup) and global-setup.ts
// both derive from these, so the baseURL fallback can never drift from the
// port the container is published on. Override via env to run several
// instances on one host without colliding.
export const HOST_PORT = Number(process.env.E2E_HOST_PORT ?? 8988);
export const CONTAINER_NAME = process.env.E2E_CONTAINER_NAME ?? 'euro-office-e2e';
export const DEFAULT_BASE_URL = `http://localhost:${HOST_PORT}`;
