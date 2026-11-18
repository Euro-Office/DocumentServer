import { defineConfig, devices } from '@playwright/test';
import { DEFAULT_BASE_URL } from './constants';

export default defineConfig({
  testDir: './tests',
  // Sized from the waits a test contains, not from how long a healthy run
  // takes. One editor open is iframe attach 15 s + document load 60 s, and the
  // stored-file tests open two — create the file, then reopen it from the list
  // — so 60 s was less than the test's own internal budget and expired first on
  // a loaded server, reporting a bare "test timeout" instead of naming the wait
  // that was too slow.
  timeout: 180_000,
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
