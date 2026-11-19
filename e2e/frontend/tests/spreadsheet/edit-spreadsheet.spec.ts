// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import {
  cleanUpStoredFiles,
  createStoredFile,
  downloadStoredFile,
  newFileLink,
  openStoredEditor,
  saveAndReopen,
  selectCell,
  selectedCellText,
  undoButton,
} from '../helpers';

const XLSX = /\.xlsx/;
const VALUE = 'Euro-Office e2e';

// Remit: P1 editing of a spreadsheet that already exists on the server — the
// `?fileName=` route. create-spreadsheet and save-spreadsheet cover create-new;
// spreadsheet-formula covers formula entry. See edit-document.spec.ts for why
// persistence is asserted against storage rather than a reload.

// Files these tests created, removed once the spec is done.
// See edit-document.spec.ts.
const createdFiles: string[] = [];

test.describe(
  'Spreadsheet editor - editing a stored file',
  { tag: ['@spreadsheet', '@regression'] },
  () => {
    test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

    // Editor state only; persistence is the next test. See edit-document.spec.ts.
    test('enter a value into a spreadsheet reopened from the file list', async ({ page }) => {
      const fileName = await createStoredFile(page, newFileLink('xlsx'), XLSX);
      createdFiles.push(fileName);
      const { editorPage, frame } = await openStoredEditor(page, fileName, XLSX);

      await test.step('the editor opened our stored file', async () => {
        expect(new URL(editorPage.url()).searchParams.get('fileName')).toBe(fileName);
      });

      await test.step('the typed value lands in A1', async () => {
        // Ctrl+Home guarantees the grid has keyboard focus at A1; the helper's
        // canvas click can leave an arbitrary cell selected.
        await editorPage.keyboard.press('Control+Home');
        await editorPage.keyboard.type(VALUE);
        await editorPage.keyboard.press('Enter');

        // nameBox.press('Enter') resolves on key dispatch, not once
        // asc_getCellInfo() reflects the new selection, so read with poll.
        await selectCell(frame, 'A1');
        await expect.poll(() => selectedCellText(editorPage)).toBe(VALUE);

        await expect(undoButton(frame)).not.toHaveClass(/disabled/);
      });
    });

    test('an edit survives closing and reopening the spreadsheet', async ({ page }) => {
      // Sized from the step timeouts inside, not the run time; see
      // edit-document.spec.ts.
      test.setTimeout(360_000);
      const fileName = await createStoredFile(page, newFileLink('xlsx'), XLSX);
      createdFiles.push(fileName);
      const { editorPage, frame } = await openStoredEditor(page, fileName, XLSX);
      const before = await downloadStoredFile(page, editorPage.url());

      const saved = await test.step('edit the stored spreadsheet and close it', async () => {
        await editorPage.keyboard.press('Control+Home');
        await editorPage.keyboard.type(VALUE);
        await editorPage.keyboard.press('Enter');
        await selectCell(frame, 'A1');
        await expect.poll(() => selectedCellText(editorPage)).toBe(VALUE);

        await editorPage.keyboard.press('Control+s');
        // The title loses its "*" when the editor finishes its own save step.
        // That is a browser-side flag, not a server acknowledgement, so it is a
        // step along the way and never the assertion.
        await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
        return saveAndReopen(page, editorPage, before);
      });

      await test.step('reopening shows the edited content', async () => {
        await saved.frame.locator('#editor_sdk').click();
        await selectCell(saved.frame, 'A1');
        await expect.poll(() => selectedCellText(saved.editorPage)).toBe(VALUE);
      });
    });
  },
);
