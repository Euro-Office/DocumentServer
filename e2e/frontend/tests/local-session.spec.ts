import { test, expect, Page } from '@playwright/test';
import { readFileSync } from 'fs';
import path from 'path';
import { editorApi } from './helpers';

// Client-only ("local") session: the host page hands the editor the file bytes,
// x2t.wasm converts them in the browser, and no Document Server session is
// opened. See docs/client-only-editor.md.

const HOST_PATH = '/e2e-local-session.html';
const FIXTURE = path.join(__dirname, '..', 'fixtures', 'local-session.docx');
const FIXTURE_TEXT = 'Opened in a local session';

const HOST_PAGE = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <script src="/web-apps/apps/api/documents/api.js"></script>
  </head>
  <body style="margin: 0">
    <div id="placeholder" style="width: 100vw; height: 100vh"></div>
  </body>
</html>`;

async function openHostPage(page: Page) {
  // Serve the integrator page from the Document Server's own origin, like an
  // integration that embeds api.js.
  await page.route(`**${HOST_PATH}`, (route) =>
    route.fulfill({ contentType: 'text/html', body: HOST_PAGE }),
  );
  await page.goto(HOST_PATH);
  await page.waitForFunction(() => 'DocsAPI' in window);
}

async function supportsLocalSession(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const w = window as unknown as {
      DocsAPI: { DocEditor: { capabilities?: { localSession?: boolean } } };
    };
    return w.DocsAPI.DocEditor.capabilities?.localSession === true;
  });
}

test.describe('Local session', () => {
  test('opens a docx from bytes without a server session', async ({ page }) => {
    await openHostPage(page);
    // Skipped, not failed, while the image is built from a web-apps without
    // local sessions; once it has them, every failure below is real.
    // eslint-disable-next-line playwright/no-skipped-test
    test.skip(
      !(await supportsLocalSession(page)),
      'this build of web-apps has no local session support',
    );

    const wasm = await page.request.get('/x2t/x2t.wasm');
    expect(wasm.status(), 'the image serves /x2t/x2t.wasm').toBe(200);

    const serverSession: string[] = [];
    page.on('request', (req) => {
      if (/\/doc\/[^/]+\/c\//.test(req.url())) serverSession.push(req.url());
    });

    const bytes = Array.from(readFileSync(FIXTURE));
    const result = await page.evaluate((data) => {
      return new Promise<{ ready: boolean; error?: unknown }>((resolve) => {
        const w = window as unknown as {
          DocsAPI: { DocEditor: new (id: string, config: unknown) => unknown };
        };
        new w.DocsAPI.DocEditor('placeholder', {
          documentType: 'word',
          width: '100%',
          height: '100%',
          document: {
            title: 'local-session.docx',
            fileType: 'docx',
            source: { data: new Uint8Array(data) },
          },
          editorConfig: { session: { type: 'local' } },
          events: {
            onDocumentReady: () => resolve({ ready: true }),
            onError: (e: { data: unknown }) => resolve({ ready: false, error: e.data }),
          },
        });
      });
    }, bytes);

    expect(result).toEqual({ ready: true });

    const text = await editorApi(page, (api) => {
      api.WordControl.m_oLogicDocument.SelectAll();
      return api.asc_GetSelectedText();
    });
    expect(text).toContain(FIXTURE_TEXT);

    expect(serverSession).toEqual([]);
  });
});
