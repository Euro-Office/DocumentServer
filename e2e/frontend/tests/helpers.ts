import { createHash, randomUUID } from 'crypto';
import { APIRequestContext, Browser, Page, expect } from '@playwright/test';
import { DEFAULT_BASE_URL } from '../constants';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

/**
 * Wait until a freshly opened editor tab has reached the editor route and the
 * document inside the iframe has finished loading, then focus the editing
 * surface. Returns a frameLocator scoped to the editor iframe.
 */
async function waitForEditorReady(editorPage: Page, urlExt: RegExp) {
  await editorPage.waitForURL(/\/example\/editor/);
  await editorPage.waitForLoadState('domcontentloaded');
  await expect(editorPage).toHaveURL(urlExt);

  const editorIframe = editorPage.locator(EDITOR_IFRAME);
  await expect(editorIframe).toBeAttached({ timeout: 15_000 });

  const frame = editorPage.frameLocator(EDITOR_IFRAME);
  await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

  await frame.locator('#editor_sdk').click();
  return frame;
}

/**
 * Open the example page, click a link that opens an editor in a new tab, and
 * wait until that editor is ready. Returns the editor tab and a frameLocator
 * scoped to the editor iframe.
 */
async function openEditorFromLink(page: Page, selector: string, urlExt: RegExp) {
  await expect(page).toHaveTitle(/ONLYOFFICE|euro-office/i);

  const newPagePromise = page.context().waitForEvent('page');
  await page.locator(selector).click();
  const editorPage = await newPagePromise;

  const frame = await waitForEditorReady(editorPage, urlExt);
  return { editorPage, frame };
}

/**
 * Open the example page, create a new document of the requested type, and wait
 * until the editor iframe has finished loading. Returns the editor tab (a new
 * page) and a frameLocator scoped to the editor iframe.
 */
export async function openNewEditor(page: Page, selector: string, urlExt: RegExp) {
  await page.goto('/example/');
  return openEditorFromLink(page, selector, urlExt);
}

/**
 * Open a file that is already in the "Your documents" list, by name, and wait
 * until the editor is ready. This is the stored-file route (`?fileName=`), as
 * opposed to the create-new route (`?fileExt=`) that openNewEditor takes.
 */
export async function openStoredEditor(page: Page, fileName: string, urlExt: RegExp) {
  await page.goto('/example/');
  return openEditorFromLink(page, storedFileLinkSelector(fileName), urlExt);
}

/**
 * Create a new file of the requested type and return the name the example app
 * generated for it (e.g. `new (3).docx`), leaving no editor tab open.
 *
 * The app names new files itself and redirects the editor tab to
 * `?fileName=<generated name>`, so reading it back off the URL is the only way
 * a test can know which file is its own: the store is server-side and shared by
 * every test (it is keyed by client IP), and spec files run in parallel
 * workers. Tests must therefore scope their assertions to the names they
 * created here and never to the state of the list as a whole.
 */
export async function createStoredFile(
  page: Page,
  selector: string,
  urlExt: RegExp,
): Promise<string> {
  const { editorPage } = await openNewEditor(page, selector, urlExt);
  // searchParams already percent-decodes; do not decode a second time.
  const fileName = new URL(editorPage.url()).searchParams.get('fileName');
  if (!fileName) {
    throw new Error(`Editor URL carries no fileName parameter: ${editorPage.url()}`);
  }
  await editorPage.close();
  return fileName;
}

/**
 * Selector for a "Create new" link on the example page, by file extension.
 * Matched on href rather than on the link text or its styling class: the href
 * is what decides which file type gets created, so neither a reworded title
 * nor a restyled theme can move it.
 */
export const newFileLink = (ext: string) => `a[href*="fileExt=${ext}"]`;

/** A name no parallel worker can be handed. See uploadStoredFile. */
export const uniqueFileName = (label: string, ext: string) => `e2e-${label}-${randomUUID()}.${ext}`;

// Documents the server ships with, used as upload payloads below so the helper
// does not depend on fixture files in this repo. Keys are the extensions the
// example app can create.
const SAMPLE_MIME: Record<string, string> = {
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  pdf: 'application/pdf',
};

/**
 * Upload a copy of the server's own sample document under a name of the
 * caller's choosing, and return the name it was stored as.
 *
 * Any test that deletes a file needs this rather than createStoredFile. The
 * create-new route names files itself and always hands out the lowest free
 * index, so deleting `new (3).docx` releases that name back to the pool — a
 * spec in a parallel worker can then recreate it in the window between the
 * delete and the assertion that it is gone, and the assertion fails on a file
 * that is not the one it deleted. A name we chose ourselves is never handed to
 * anybody else.
 *
 * The upload goes over page.request rather than the `#fileupload` input on
 * purpose: this is fixture setup for the deletion tests, and driving the upload
 * UI would make them fail for reasons that have nothing to do with deleting.
 */
export async function uploadStoredFile(page: Page, fileName: string): Promise<string> {
  const ext = fileName.split('.').pop() ?? '';
  const mimeType = SAMPLE_MIME[ext];
  if (!mimeType) {
    throw new Error(
      `No sample document for ".${ext}" — expected one of ${Object.keys(SAMPLE_MIME)}`,
    );
  }

  const samplePath = `/example/assets/document-templates/sample/sample.${ext}`;
  const sample = await page.request.get(samplePath);
  expect(sample.ok(), `could not read the sample document at ${samplePath}`).toBe(true);

  const response = await page.request.post('/example/upload', {
    multipart: {
      uploadedFile: { name: fileName, mimeType, buffer: await sample.body() },
    },
  });
  expect(response.ok(), `upload of ${fileName} failed`).toBe(true);

  // The app echoes back the name it actually stored, which is the one the file
  // list will be keyed by.
  const { filename } = (await response.json()) as { filename: string };
  return filename;
}

// The file list carries the percent-encoded name in `data` and `href`
// (`new (3).docx` renders as `data="new%20(3).docx"`), so every selector below
// has to encode before matching.
const storedFileLinkSelector = (fileName: string) =>
  `a.stored-edit[href="editor?fileName=${encodeURIComponent(fileName)}"]`;

const deleteButtonSelector = (fileName: string) =>
  `a.delete-file[data="${encodeURIComponent(fileName)}"]`;

/** The "Your documents" row for a given file. Empty locator once it is gone. */
export const storedFileRow = (page: Page, fileName: string) =>
  page.locator(`tr.tableRow:has(${deleteButtonSelector(fileName)})`);

/** The bin icon in that row. */
export const storedFileDeleteButton = (page: Page, fileName: string) =>
  page.locator(deleteButtonSelector(fileName));

/**
 * Remove a stored file. Hits the same endpoint the bin icon does, rather than
 * driving the UI, so it is usable for cleanup with no page on screen.
 *
 * Best effort on purpose: a cleanup failure must not fail an otherwise green
 * test, and the file may already be gone (a delete spec removed it, or the
 * server is being torn down). Returns whether the file was removed.
 */
export async function deleteStoredFile(
  request: APIRequestContext,
  fileName: string,
): Promise<boolean> {
  try {
    const response = await request.delete(`/example/file?filename=${encodeURIComponent(fileName)}`);
    return response.ok();
  } catch {
    return false;
  }
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// How long a stored file has to stop changing before cleanup will delete it,
// and how long to wait for that. See waitForStoredFileToSettle.
const SETTLE_STABLE_MS = 3_000;
const SETTLE_TIMEOUT_MS = 20_000;
const SETTLE_POLL_MS = 500;

/**
 * Wait until a stored file stops changing, i.e. until docservice has finished
 * writing back the editor tab this spec just closed.
 *
 * Deleting a file releases its name, and the create-new route hands the lowest
 * free name straight to whoever asks next — a spec in a parallel worker. If our
 * write-back is still in flight when that happens, it lands on *their* file and
 * fails their test on content it never typed. Waiting for quiet first keeps the
 * write and the delete in that order.
 *
 * Stability is a mitigation, not a proof: a write-back that has not started yet
 * reads as quiet. The window is sized well past the few seconds docservice
 * takes after the last disconnect, and cleanup only runs once a whole spec is
 * done, so in practice the write has long since begun. Treats "not listed" and
 * "download refused" as quiet — there is nothing left to wait for either way.
 */
async function waitForStoredFileToSettle(
  request: APIRequestContext,
  fileName: string,
): Promise<void> {
  const hash = async () => {
    try {
      return sha256(await storedFileBytes(request, fileName));
    } catch {
      return null;
    }
  };

  const deadline = Date.now() + SETTLE_TIMEOUT_MS;
  let previous = await hash();
  let quietSince = Date.now();

  while (Date.now() < deadline) {
    await sleep(SETTLE_POLL_MS);
    const current = await hash();
    if (current !== previous) {
      previous = current;
      quietSince = Date.now();
    } else if (Date.now() - quietSince >= SETTLE_STABLE_MS) {
      return;
    }
  }
}

/**
 * Remove the files a spec created, and empty the list. Call from afterAll:
 *
 *     test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));
 *
 * afterAll rather than afterEach, which looks like the obvious home for this.
 * The create-new route always hands out the lowest free name, so deleting
 * `new (3).docx` puts that name straight back in the pool. Delete between two
 * tests of the same spec and the second is handed the name the first just
 * released — while docservice is still writing the first one back a few
 * seconds after its tab closed. That write then lands on the second test's
 * file and the test fails on content it never typed. Waiting until the whole
 * spec is done leaves no sibling to hand the name to; waiting for the file to
 * settle first keeps the same from happening to a parallel worker.
 *
 * Needs its own context because test fixtures (`page`, `request`) are not
 * available in afterAll; it takes the same baseURL playwright.config.ts does.
 */
export async function cleanUpStoredFiles(browser: Browser, fileNames: string[]): Promise<void> {
  const names = fileNames.splice(0);
  if (names.length === 0) return;

  const context = await browser.newContext({
    baseURL: process.env.E2E_BASE_URL ?? DEFAULT_BASE_URL,
  });
  try {
    await Promise.all(
      names.map(async (name) => {
        await waitForStoredFileToSettle(context.request, name);
        await deleteStoredFile(context.request, name);
      }),
    );
  } finally {
    await context.close();
  }
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
  return storedFileBytes(page.request, fileName);
}

/** The bytes of a stored file, by name. Takes a request context so cleanup can
 * use it with no page open. */
async function storedFileBytes(request: APIRequestContext, fileName: string): Promise<Buffer> {
  const listRes = await request.get('/example/');
  const list = await listRes.text();
  const encoded = encodeURIComponent(fileName).replace(/[()]/g, (c) => `\\${c}`);
  const href = new RegExp(`href="([^"]*download\\?fileName=${encoded}[^"]*)"`).exec(list)?.[1];
  if (!href) throw new Error(`"${fileName}" is not in the example app file list`);

  // Links are absolute with a token under JWT, relative to /example/ without.
  const res = await request.get(new URL(href.replace(/&amp;/g, '&'), listRes.url()).href);
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

/** The undo toolbar button, present in every desktop editor. */
export const undoButton = (frame: ReturnType<Page['frameLocator']>) =>
  frame.locator('#slot-btn-undo button').first();

/**
 * Read the whole text of the open document: Select All, ask the automation API
 * for the selection, then collapse it again so the caller keeps a usable caret.
 *
 * asc_GetSelectedText() includes the trailing paragraph mark, so the result is
 * trimmed — an empty document reads back as `''` rather than `'\r\n'`.
 */
export async function readDocumentText(editorPage: Page): Promise<string> {
  await editorPage.keyboard.press('Control+A');
  const text = await editorApi<string>(editorPage, (api) => api.asc_GetSelectedText());
  await editorPage.keyboard.press('ArrowRight');
  return text.trim();
}
