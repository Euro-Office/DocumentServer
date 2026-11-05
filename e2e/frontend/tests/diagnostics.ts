import { test as base, expect } from '@playwright/test';

/**
 * Collects console output and uncaught errors of the page and all its frames
 * (the editors run in iframes) and prints them when a test fails, so a CI log
 * shows why an editor did not load instead of only which assertion timed out.
 */
export const test = base.extend<{ browserLog: string[] }>({
  browserLog: [
    async ({ page }, use, testInfo) => {
      const log: string[] = [];
      page.on('console', (message) => {
        const frame = message.location().url.replace(/\?.*$/, '');
        log.push(`[${message.type()}] ${message.text()} (${frame})`);
      });
      page.on('pageerror', (error) => log.push(`[pageerror] ${error.message}`));
      page.on('requestfailed', (request) =>
        log.push(`[requestfailed] ${request.url()} ${request.failure()?.errorText ?? ''}`),
      );

      await use(log);

      if (testInfo.status !== testInfo.expectedStatus && log.length > 0) {
        const text = log.join('\n');
        console.log(`--- browser log of "${testInfo.title}" ---\n${text}\n--- end ---`);
        await testInfo.attach('browser-log', { body: text, contentType: 'text/plain' });
      }
    },
    { auto: true },
  ],
});

export { expect };
