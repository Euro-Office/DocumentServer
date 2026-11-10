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

const PDF = /\.pdf/;
const TEXT = 'Euro-Office e2e edit test';

// Remit: P1 editing of a PDF form that already exists on the server — the
// `?fileName=` route. create-pdf-form and save-pdf-form cover create-new.
//
// This reads much like edit-document, and that is the point rather than an
// oversight: `fileExt=pdf` loads a different editor bundle, so the same user
// gesture has to be proven against that surface too. See edit-document.spec.ts
// for why persistence is asserted against storage rather than a reload.

// Files these tests created, removed once the spec is done.
// See edit-document.spec.ts.
const createdFiles: string[] = [];

test.describe('PDF form editor - editing a stored file', () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  test('type text into a PDF form reopened from the file list', async ({ page }) => {
    const fileName = await createStoredFile(page, newFileLink('pdf'), PDF);
    createdFiles.push(fileName);
    const { editorPage, frame } = await openStoredEditor(page, fileName, PDF);

    await test.step('the editor opened our stored file', async () => {
      expect(new URL(editorPage.url()).searchParams.get('fileName')).toBe(fileName);
      expect(await readDocumentText(editorPage)).toBe('');
    });

    await test.step('typed text reaches the form', async () => {
      await editorPage.keyboard.type(TEXT);
      expect(await readDocumentText(editorPage)).toBe(TEXT);
      await expect(undoButton(frame)).not.toHaveClass(/disabled/);
    });
  });

  test('an edit survives closing and reopening the PDF form', async ({ page }) => {
    test.setTimeout(120_000); // the save callback only fires once the tab closes
    const fileName = await createStoredFile(page, newFileLink('pdf'), PDF);
    createdFiles.push(fileName);
    const { editorPage } = await openStoredEditor(page, fileName, PDF);
    const before = await downloadStoredFile(page, editorPage.url());

    const saved = await test.step('edit the stored PDF form and close it', async () => {
      await editorPage.keyboard.type(TEXT);
      expect(await readDocumentText(editorPage)).toBe(TEXT);

      await editorPage.keyboard.press('Control+s');
      // The title loses its "*" when the editor finishes its own save step.
      // That is a browser-side flag, not a server acknowledgement, so it is a
      // step along the way and never the assertion.
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
      return saveAndReopen(page, editorPage, before);
    });

    await test.step('reopening shows the edited content', async () => {
      await expect(async () => {
        await saved.frame.locator('#editor_sdk').click();
        expect(await readDocumentText(saved.editorPage)).toBe(TEXT);
      }).toPass({ timeout: 30_000 });
    });
  });
});
