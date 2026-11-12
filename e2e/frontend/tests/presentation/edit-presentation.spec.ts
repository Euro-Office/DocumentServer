// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect, type Page } from '@playwright/test';
import {
  cleanUpStoredFiles,
  createStoredFile,
  downloadStoredFile,
  editorApi,
  newFileLink,
  openStoredEditor,
  saveAndReopen,
  undoButton,
} from '../helpers';

const PPTX = /\.pptx/;
const TITLE = 'Euro-Office e2e title';

// Remit: P1 editing of a presentation that already exists on the server — the
// `?fileName=` route. create-presentation and save-presentation cover
// create-new; presentation-slides covers adding slides. See
// edit-document.spec.ts for why persistence is asserted against storage
// rather than a reload.

// Files these tests created, removed once the spec is done.
// See edit-document.spec.ts.
const createdFiles: string[] = [];

// A new presentation opens on a Title slide: shape 1 is the title placeholder,
// shape 2 the subtitle. Tab walks the selection through the shapes. (Same
// navigation save-presentation.spec.ts uses.)
async function focusShape(editorPage: Page, shapeNumber: number) {
  // Escape twice: leave text editing, then deselect, so Tab starts from the
  // first shape whatever state the previous step left behind.
  await editorPage.keyboard.press('Escape');
  await editorPage.keyboard.press('Escape');
  for (let i = 0; i < shapeNumber; i++) {
    await editorPage.keyboard.press('Tab');
  }
}

async function typeIntoShape(editorPage: Page, shapeNumber: number, text: string) {
  await focusShape(editorPage, shapeNumber);
  await editorPage.keyboard.press('Enter'); // start editing the selected shape
  await editorPage.keyboard.type(text);
}

/**
 * Put the caret in a shape and select all of its text. Key presses, so it
 * changes editor state: call it once, never from inside expect.poll.
 */
async function selectShapeText(editorPage: Page, shapeNumber: number) {
  await focusShape(editorPage, shapeNumber);
  await editorPage.keyboard.press('Enter');
  await editorPage.keyboard.press('Control+A');
}

/**
 * The current selection, as the editor reports it. Read-only, so this is the
 * half that is safe to poll. Returns an "error: ..." string rather than
 * throwing while the iframe is still settling, so a poll retries.
 * Ctrl+A also selects the paragraph end, so the editor appends a line break.
 */
const selectedText = (editorPage: Page) =>
  editorApi(editorPage, (api) => api.asc_GetSelectedText())
    .then((text) => String(text).trim())
    .catch((e: Error) => `error: ${e.message}`);

/** One-shot read of a shape's text: select, then read. */
async function readShape(editorPage: Page, shapeNumber: number) {
  await selectShapeText(editorPage, shapeNumber);
  return selectedText(editorPage);
}

test.describe('Presentation editor - editing a stored file', () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  // Editor state only; persistence is the next test. See edit-document.spec.ts.
  test('type a title into a presentation reopened from the file list', async ({ page }) => {
    const fileName = await createStoredFile(page, newFileLink('pptx'), PPTX);
    createdFiles.push(fileName);
    const { editorPage, frame } = await openStoredEditor(page, fileName, PPTX);

    await test.step('the editor opened our stored file', async () => {
      expect(new URL(editorPage.url()).searchParams.get('fileName')).toBe(fileName);
      // A newly created deck is one empty Title slide.
      await expect.poll(() => editorApi(editorPage, (api) => api.getCountPages())).toBe(1);
      expect(await readShape(editorPage, 1)).toBe('');
    });

    await test.step('the title placeholder holds the typed text', async () => {
      await typeIntoShape(editorPage, 1, TITLE);
      // Select once, then poll the read: polling the navigation too would press
      // keys on every retry and change the state it is reading.
      await selectShapeText(editorPage, 1);
      await expect.poll(() => selectedText(editorPage)).toBe(TITLE);
      await expect(undoButton(frame)).not.toHaveClass(/disabled/);
    });
  });

  test('an edit survives closing and reopening the presentation', async ({ page }) => {
    // Sized from the step timeouts inside, not the run time; see
    // edit-document.spec.ts.
    test.setTimeout(270_000);
    const fileName = await createStoredFile(page, newFileLink('pptx'), PPTX);
    createdFiles.push(fileName);
    const { editorPage } = await openStoredEditor(page, fileName, PPTX);
    const before = await downloadStoredFile(page, editorPage.url());

    const saved = await test.step('edit the stored presentation and close it', async () => {
      await typeIntoShape(editorPage, 1, TITLE);
      await selectShapeText(editorPage, 1);
      await expect.poll(() => selectedText(editorPage)).toBe(TITLE);
      await editorPage.keyboard.press('Escape');
      await editorPage.keyboard.press('Escape');

      await editorPage.keyboard.press('Control+s');
      // The title loses its "*" when the editor finishes its own save step.
      // That is a browser-side flag, not a server acknowledgement, so it is a
      // step along the way and never the assertion.
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
      return saveAndReopen(page, editorPage, before);
    });

    await test.step('reopening shows the edited content', async () => {
      // toPass, not expect.poll: the editor can rebuild its iframe shortly
      // after opening, so click, select and read are retried together as one
      // unit rather than the read alone.
      await expect(async () => {
        await saved.frame.locator('#editor_sdk').click();
        expect(await readShape(saved.editorPage, 1)).toBe(TITLE);
      }).toPass({ timeout: 30_000 });
    });
  });
});
