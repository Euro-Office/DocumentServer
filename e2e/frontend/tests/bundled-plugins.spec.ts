import { test, expect, Page } from '@playwright/test';
import { openNewEditor } from './helpers';

// Plugins shipped in the image by plugins/scripts/bundle.sh (bundle.txt)
const BUNDLED = ['highlightcode', 'photoeditor', 'mendeley'];

/** Records requests to the upstream plugin host and errors raised by plugin code. */
function watch(page: Page) {
  const upstream: string[] = [];
  const errors: string[] = [];
  page.context().on('request', (req) => {
    if (new URL(req.url()).hostname === 'onlyoffice.github.io') upstream.push(req.url());
  });
  page.context().on('response', (res) => {
    if (res.url().includes('/sdkjs-plugins/') && res.status() >= 400)
      errors.push(`${res.status()} ${res.url()}`);
  });
  page.context().on('page', (p) => {
    p.on('console', (msg) => {
      if (msg.type() === 'error' && msg.location().url.includes('/sdkjs-plugins/'))
        errors.push(`${msg.location().url}: ${msg.text()}`);
    });
    p.on('pageerror', (err) => {
      if (err.stack?.includes('/sdkjs-plugins/')) errors.push(err.stack);
    });
  });
  return { upstream, errors };
}

test.describe('Bundled plugins', () => {
  test('/plugins.json lists the bundled plugins', async ({ request }) => {
    const res = await request.get('/plugins.json');
    expect(res.ok()).toBe(true);
    const { pluginsData } = await res.json();
    for (const name of BUNDLED) {
      expect(pluginsData).toContainEqual(
        expect.stringMatching(`/sdkjs-plugins/${name}/config.json$`),
      );
    }
  });

  for (const name of BUNDLED) {
    test(`${name} opens without errors or upstream requests`, async ({ page, request }) => {
      const config = await request.get(`/sdkjs-plugins/${name}/config.json`);
      expect(config.ok()).toBe(true);
      const { guid } = await config.json();

      const { upstream, errors } = watch(page);
      const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.word', /\.docx/);

      await frame.locator('a[data-tab="plugins"]').click();
      await frame
        .locator(`[data-plugin-guid="${guid}"]`)
        .locator('xpath=descendant-or-self::button')
        .first()
        .click();

      // The plugin iframe loads its page and the v1/ helpers from the image
      const pluginFrame = () =>
        editorPage.frames().find((f) => f.url().includes(`/sdkjs-plugins/${name}/`));
      await expect.poll(() => Boolean(pluginFrame())).toBe(true);
      await pluginFrame()!.waitForLoadState('load');

      expect(errors).toEqual([]);
      expect(upstream).toEqual([]);
    });
  }
});
