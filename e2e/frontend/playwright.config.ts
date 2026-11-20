import { defineConfig, devices } from '@playwright/test';
import { DEFAULT_BASE_URL } from './constants';
import { TEST_TIMEOUT } from './timeouts';

export default defineConfig({
  testDir: './tests',
  // Derived from the waits a test contains (see timeouts.ts), not from how long
  // a healthy run takes: the stored-file tests open two editors, so a shorter
  // budget expires first on a loaded server and reports a bare "test timeout"
  // instead of naming the wait that was too slow.
  timeout: TEST_TIMEOUT,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  // One document server serves every worker, so the limit is the server, not
  // the machine. At Playwright's default (half the cores, 7 on the dev box)
  // tests time out under the load; 4 is clean over repeated full runs.
  // Override per run with `npm test -- --workers=N`.
  workers: 4,
  retries: 1,
  // Tests tagged @ignore are skipped everywhere. Set E2E_INCLUDE_IGNORED=1 to run them.
  grepInvert: process.env.E2E_INCLUDE_IGNORED ? undefined : /@ignore/,
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
