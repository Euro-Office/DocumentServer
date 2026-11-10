// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import {
  cleanUpStoredFiles,
  createStoredFile,
  downloadStoredFile,
  newFileLink,
  openStoredEditor,
  readDocumentText,
  saveAndReopen,
  undoButton,
} from '../helpers';

const DOCX = /\.docx/;
const TEXT = 'Euro-Office e2e edit test';

// Remit: P1 editing of a document that already exists on the server — the
// `?fileName=` route reached by clicking a file in "Your documents".
// create-document and save-document cover the create-new route (`?fileExt=`);
// this file is about reopening a stored file and changing its content.
//
// Persistence is asserted against the bytes in storage (downloadStoredFile /
// saveAndReopen), never through an editor reload: reloading reconnects to the
// same document key and restores from docservice's cache, so it would pass
// whether or not anything was written back.

// Files these tests created, removed once the spec is done (see
// cleanUpStoredFiles for why not after each test). The store is server-side and
// shared by every spec, so a run against a long-lived server (E2E_BASE_URL)
// would otherwise accumulate a file per test per run.
const createdFiles: string[] = [];

test.describe('Document editor - editing a stored file', () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  test('type text into a document reopened from the file list', async ({ page }) => {
    const fileName = await createStoredFile(page, newFileLink('docx'), DOCX);
    createdFiles.push(fileName);
    const { editorPage, frame } = await openStoredEditor(page, fileName, DOCX);

    await test.step('the editor opened our stored file', async () => {
      // Compared as a parsed parameter rather than a URL pattern: generated
      // names contain regex metacharacters (`new (3).docx`).
      expect(new URL(editorPage.url()).searchParams.get('fileName')).toBe(fileName);
      // A newly created file opens empty, so any text below is unambiguously ours.
      expect(await readDocumentText(editorPage)).toBe('');
    });

    await test.step('typed text reaches the document', async () => {
      await editorPage.keyboard.type(TEXT);

      // Read back through the automation API, not off the canvas.
      expect(await readDocumentText(editorPage)).toBe(TEXT);

      // ...and the editor registered it as a change to an existing document.
      await expect(undoButton(frame)).not.toHaveClass(/disabled/);
    });
  });

  test('an edit survives closing and reopening the document', async ({ page }) => {
    test.setTimeout(120_000); // the save callback only fires once the tab closes
    const fileName = await createStoredFile(page, newFileLink('docx'), DOCX);
    createdFiles.push(fileName);
    const { editorPage } = await openStoredEditor(page, fileName, DOCX);
    // What storage holds before the edit: the file as it was created.
    const before = await downloadStoredFile(page, editorPage.url());

    const saved = await test.step('edit the stored document and close it', async () => {
      await editorPage.keyboard.type(TEXT);
      expect(await readDocumentText(editorPage)).toBe(TEXT);

      await editorPage.keyboard.press('Control+s');
      // The title loses its "*" when the editor finishes its own save step.
      // That is a browser-side flag, not a server acknowledgement, so it is a
      // step along the way and never the assertion. saveAndReopen closes the
      // tab — which is what makes docservice hand the file back — waits until
      // the stored bytes change, then opens the file in a fresh tab.
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
      return saveAndReopen(page, editorPage, before);
    });

    await test.step('reopening shows the edited content', async () => {
      // The new tab has a new document key, so this is what storage holds.
      // The editor can rebuild its iframe shortly after opening, so the
      // focus-select-read sequence is retried as a unit.
      await expect(async () => {
        await saved.frame.locator('#editor_sdk').click();
        expect(await readDocumentText(saved.editorPage)).toBe(TEXT);
      }).toPass({ timeout: 30_000 });
    });
  });
});
