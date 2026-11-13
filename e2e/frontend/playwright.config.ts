import { defineConfig, devices } from '@playwright/test';
import { DEFAULT_BASE_URL } from './constants';

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  // One document server serves every worker, so the limit is the server, not
  // the machine. At Playwright's default (half the cores, 7 on the dev box)
  // tests time out under the load; 4 is clean over repeated full runs.
  // Override per run with `npm test -- --workers=N`.
  workers: 4,
  retries: 1,
  outputDir: '../test-results',
  reporter: [['list'], ['html', { open: 'never', outputFolder: '../playwright-report' }]],
  globalSetup: require.resolve('./global-setup'),
  globalTeardown: require.resolve('./global-teardown'),
  use: {
    baseURL: process.env.E2E_BASE_URL ?? DEFAULT_BASE_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
