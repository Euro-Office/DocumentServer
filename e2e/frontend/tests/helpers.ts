import { Page, expect, FrameLocator } from '@playwright/test';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

/**
 * The editor types the example page can create, with the selector of their
 * create link and the file-extension URL pattern of their editor route.
 */
export const EDITOR_TYPES = [
  { label: 'Document', selector: 'a.try-editor.word', fileExt: /\.docx/ },
  { label: 'Spreadsheet', selector: 'a.try-editor.cell', fileExt: /\.xlsx/ },
  { label: 'Presentation', selector: 'a.try-editor.slide', fileExt: /\.pptx/ },
  { label: 'PDF', selector: 'a.try-editor.pdf', fileExt: /\.pdf/ },
] as const;

export type EditorLabel = (typeof EDITOR_TYPES)[number]['label'];

/** Look up an editor type by its label, e.g. editorFor('Document'). */
export function editorFor(label: EditorLabel) {
  const editor = EDITOR_TYPES.find((e) => e.label === label);
  if (!editor) throw new Error(`Unknown editor label: ${label}`);
  return editor;
}

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
 * Switch the ribbon to the given tab (its `data-tab` value, e.g. 'home',
 * 'ins', 'view') and wait until it became the active one.
 */
export async function openRibbonTab(frame: FrameLocator, tab: string): Promise<void> {
  await frame.locator(`a[data-tab="${tab}"]`).click();
  await expect(frame.locator(`li.ribtab:has(a[data-tab="${tab}"])`)).toHaveClass(/active/);
}

/** The editor's undo button; its state reflects whether an edit has happened. */
const undoButton = (frame: FrameLocator) => frame.locator('#slot-btn-undo button').first();

/** In a fresh document no edit has happened yet, so undo is disabled. */
export async function expectUndoDisabled(frame: FrameLocator): Promise<void> {
  await expect(undoButton(frame)).toHaveClass(/(^|\s)disabled(\s|$)/);
}

/** Undo becomes enabled as soon as the document received an edit. */
export async function expectUndoEnabled(frame: FrameLocator): Promise<void> {
  await expect(undoButton(frame)).not.toHaveClass(/(^|\s)disabled(\s|$)/);
}

/**
 * Evaluate a function inside the editor iframe and return its result. Unlike
 * `editorApi` this does not require the automation API, so it can reach
 * application globals such as `Common` or query the raw DOM.
 */
export async function editorFrameEvaluateFn<T>(page: Page, fn: () => T): Promise<T> {
  const handle = await page.locator(EDITOR_IFRAME).elementHandle();
  const frame = handle && (await handle.contentFrame());
  if (!frame) throw new Error('editor iframe has no content frame');
  return frame.evaluate(fn);
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
