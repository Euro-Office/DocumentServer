import { createHash } from 'crypto';
import { Page, expect } from '@playwright/test';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

/**
 * Open the example page, create a new document of the requested type, and wait
 * until the editor iframe has finished loading. Returns the editor tab (a new
 * page) and a frameLocator scoped to the editor iframe.
 */
export async function openNewEditor(page: Page, selector: string, urlExt: RegExp) {
  await page.goto('/example/');
  await expect(page).toHaveTitle(/ONLYOFFICE|euro-office/i);

  const newPagePromise = page.context().waitForEvent('page');
  await page.locator(selector).click();
  const editorPage = await newPagePromise;

  await editorPage.waitForURL(/\/example\/editor/);
  await editorPage.waitForLoadState('domcontentloaded');
  await expect(editorPage).toHaveURL(urlExt);

  const editorIframe = editorPage.locator(EDITOR_IFRAME);
  await expect(editorIframe).toBeAttached({ timeout: 15_000 });

  const frame = editorPage.frameLocator(EDITOR_IFRAME);
  await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

  await frame.locator('#editor_sdk').click();
  return { editorPage, frame };
}

/**
 * Evaluate a function against the editor's automation API (window.Asc.editor)
 * inside the editor iframe. The function is serialized, so it must be
 * self-contained (no closures over test scope).
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function editorApi<T>(editorPage: Page, fn: (api: any) => T): Promise<T> {
  const handle = await editorPage.locator(EDITOR_IFRAME).elementHandle();
  if (!handle) throw new Error('editor iframe not found');
  const frame = await handle.contentFrame();
  if (!frame) throw new Error('editor iframe has no content frame');

  return frame.evaluate((body) => {
    const w = window as unknown as { Asc?: { editor?: unknown } };
    const api = w.Asc?.editor;
    if (!api) throw new Error('window.Asc.editor not available');
    return new Function('api', `return (${body})(api);`)(api);
  }, fn.toString());
}

const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

/**
 * Download the file an editor URL points at straight from the example app's
 * storage. The file list on /example/ links every stored file with a signed
 * /example/download URL, so this works with or without JWT.
 *
 * Storage is the only reliable proof a save worked. Ctrl+S and editorPage.reload()
 * are not: the editor reports "saved" on its own, and a reload reconnects to the
 * same document key, so it is restored from docservice's cache even when the
 * file was never written back.
 */
export async function downloadStoredFile(page: Page, editorUrl: string): Promise<Buffer> {
  const fileName = new URL(editorUrl).searchParams.get('fileName');
  if (!fileName) throw new Error(`no fileName in editor URL: ${editorUrl}`);

  const listRes = await page.request.get('/example/');
  const list = await listRes.text();
  const encoded = encodeURIComponent(fileName).replace(/[()]/g, (c) => `\\${c}`);
  const href = new RegExp(`href="([^"]*download\\?fileName=${encoded}[^"]*)"`).exec(list)?.[1];
  if (!href) throw new Error(`"${fileName}" is not in the example app file list`);

  // Links are absolute with a token under JWT, relative to /example/ without.
  const res = await page.request.get(new URL(href.replace(/&amp;/g, '&'), listRes.url()).href);
  if (!res.ok()) throw new Error(`download of "${fileName}" failed: HTTP ${res.status()}`);
  return res.body();
}

/**
 * Close the editor so docservice writes the document back to storage, wait
 * until the stored file differs from `before` (the blank template, taken right
 * after the editor opened), then open the saved file in a fresh editor tab.
 *
 * docservice only writes back a few seconds after the last editor disconnects;
 * Ctrl+S alone does not reach storage. The new tab has a new document key, so
 * what it shows was loaded from storage, not from cache.
 */
export async function saveAndReopen(page: Page, editorPage: Page, before: Buffer) {
  const editorUrl = editorPage.url();
  await editorPage.close();

  await expect
    .poll(async () => sha256(await downloadStoredFile(page, editorUrl)), {
      message: 'saved file in storage differs from the blank template',
      timeout: 60_000,
    })
    .not.toBe(sha256(before));

  const reopened = await page.context().newPage();
  await reopened.goto(editorUrl);
  await expect(reopened.locator(EDITOR_IFRAME)).toBeAttached({ timeout: 15_000 });
  const frame = reopened.frameLocator(EDITOR_IFRAME);
  await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });
  return { editorPage: reopened, frame };
}
