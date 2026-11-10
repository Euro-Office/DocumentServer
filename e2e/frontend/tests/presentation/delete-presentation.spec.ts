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

// Remit: P1 deletion of a presentation from the "Your documents" list. The
// delete endpoint is type-agnostic, so what this adds over delete-document is
// that a .pptx is listed as a presentation row and removed cleanly. See
// delete-document.spec.ts for why "Clear all" is out of scope and why nothing
// here asserts on the list as a whole.

// Files this test uploaded, removed once the spec is done so a run against a
// long-lived server (E2E_BASE_URL) does not accumulate them. Normally the test
// has already deleted it; this covers a run that failed midway.
const uploadedFiles: string[] = [];

test.describe('Presentation - deleting a stored file', () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, uploadedFiles));

  test('delete a presentation from the file list', async ({ page }) => {
    await page.goto('/example/');
    const fileName = await uploadStoredFile(page, uniqueFileName('delete', 'pptx'));
    uploadedFiles.push(fileName);

    await page.goto('/example/');
    const row = storedFileRow(page, fileName);

    await test.step('the presentation is listed', async () => {
      await expect(row).toHaveCount(1);
      // The list types each row; a presentation links through .stored-edit.slide.
      await expect(row.locator('a.stored-edit.slide')).toHaveCount(1);
    });

    await test.step('the row disappears without a reload', async () => {
      await storedFileDeleteButton(page, fileName).click();
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
});
