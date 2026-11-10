// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import {
  cleanUpStoredFiles,
  storedFileDeleteButton,
  storedFileRow,
  uniqueFileName,
  uploadStoredFile,
} from '../helpers';

// Remit: P1 deletion of a document from the "Your documents" list — the bin
// icon, which fires DELETE /example/file?filename=<name> and drops the row in
// place.
//
// Out of scope: "Clear all". It wipes the entire store, and the store is
// server-side and shared by every spec (keyed by client IP) while spec files
// run in parallel workers, so clearing it here would delete files other specs
// are mid-test on. For the same reason nothing below asserts on the size or
// contents of the list as a whole, only on rows this test created itself.

// Files these tests uploaded. Most are gone by the end — deleting them is the
// point — but the isolation test keeps one on purpose, and a test that fails
// midway leaves its own behind. Removed after each test so a run against a
// long-lived server (E2E_BASE_URL) does not accumulate them.
const uploadedFiles: string[] = [];

test.describe('Document - deleting a stored file', () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, uploadedFiles));

  test('delete a document from the file list', async ({ page }) => {
    await page.goto('/example/');
    const fileName = await uploadStoredFile(page, uniqueFileName('delete', 'docx'));
    uploadedFiles.push(fileName);

    await page.goto('/example/');
    const row = storedFileRow(page, fileName);

    await test.step('the document is listed', async () => {
      await expect(row).toHaveCount(1);
      // The list types each row; a document links through .stored-edit.word.
      await expect(row.locator('a.stored-edit.word')).toHaveCount(1);
    });

    await test.step('the row disappears without a reload', async () => {
      await storedFileDeleteButton(page, fileName).click();
      // The handler removes the row in place once the DELETE returns; there is
      // no navigation unless that was the last row in the list.
      await expect(row).toHaveCount(0);
    });

    await test.step('it is gone server-side, not merely hidden', async () => {
      // The list is re-rendered from the real file store on each request, so
      // reloading is a genuine server-side check rather than a DOM one.
      // downloadStoredFile is deliberately not used as a second oracle: it
      // resolves a file through this very list, so for a deleted file it can
      // only report what the list already says.
      await page.reload();
      await expect(row).toHaveCount(0);
    });
  });

  test('deleting one document leaves the others in place', async ({ page }) => {
    await page.goto('/example/');
    const keptFile = await uploadStoredFile(page, uniqueFileName('keep', 'docx'));
    const deletedFile = await uploadStoredFile(page, uniqueFileName('remove', 'docx'));
    uploadedFiles.push(keptFile, deletedFile);

    await page.goto('/example/');
    await expect(storedFileRow(page, keptFile)).toHaveCount(1);
    await expect(storedFileRow(page, deletedFile)).toHaveCount(1);

    await storedFileDeleteButton(page, deletedFile).click();

    // Only the targeted row goes. Without this, a delete that wiped the whole
    // store would still pass the single-file test above.
    await expect(storedFileRow(page, deletedFile)).toHaveCount(0);
    await expect(storedFileRow(page, keptFile)).toHaveCount(1);

    await page.reload();
    await expect(storedFileRow(page, keptFile)).toHaveCount(1);
  });
});
