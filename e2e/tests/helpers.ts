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
  await page.click(selector);
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
export async function editorApi<T>(editorPage: Page, fn: (api: any) => T): Promise<T> {
  const handle = await editorPage.locator(EDITOR_IFRAME).elementHandle();
  if (!handle) throw new Error('editor iframe not found');
  const frame = await handle.contentFrame();
  if (!frame) throw new Error('editor iframe has no content frame');

  return frame.evaluate((body) => {
    const w = window as unknown as { Asc?: { editor?: unknown } };
    const api = w.Asc?.editor;
    if (!api) throw new Error('window.Asc.editor not available');
    // eslint-disable-next-line no-new-func
    return new Function('api', `return (${body})(api);`)(api);
  }, fn.toString());
}
