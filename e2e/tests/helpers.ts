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

/**
 * Evaluate a function against the editor iframe's window, for driving app-level
 * globals (e.g. Common.UI.Themes) rather than just the automation API. The
 * function is serialized, so it must be self-contained (no closures over test
 * scope) -- but real, JSON-serializable values from the test can still be
 * passed in via `args`, which arrive as genuine extra parameters (`fn(win,
 * ...args)`), not string-substituted into the function's source text.
 */
export async function frameEval<T>(
  editorPage: Page,
  fn: (win: any, ...args: any[]) => T,
  args: any[] = [],
): Promise<T> {
  const handle = await editorPage.locator(EDITOR_IFRAME).elementHandle();
  if (!handle) throw new Error('editor iframe not found');
  const frame = await handle.contentFrame();
  if (!frame) throw new Error('editor iframe has no content frame');

  return frame.evaluate(({ body, args }) => {
    // eslint-disable-next-line no-new-func
    return new Function('win', 'args', `return (${body}).apply(null, [win].concat(args));`)(window, args);
  }, { body: fn.toString(), args });
}

/**
 * Asserts an RGB color is within `tolerance` per channel of `expected`, not
 * exactly equal. Anti-aliasing at a fill/glyph edge can shift a scanned
 * pixel by a value or two from the exact color that was set, even when the
 * color itself is correct.
 */
export function expectColorClose(actual: number[], expected: number[], tolerance = 4) {
  expect(actual.length).toBe(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(Math.abs(actual[i] - expected[i])).toBeLessThanOrEqual(tolerance);
  }
}
