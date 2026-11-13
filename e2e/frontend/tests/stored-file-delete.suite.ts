// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import {
  cleanUpStoredFiles,
  storedFileDeleteButton,
  storedFileRow,
  uniqueFileName,
  uploadStoredFile,
} from './helpers';

/**
 * The P1 deletion scenario, shared by the four delete-*.spec.ts files: the bin
 * icon in "Your documents", which fires DELETE /example/file?filename=<name>
 * and drops the row in place. The endpoint is type-agnostic, so each type adds
 * only that its extension is listed under the right row class and removed
 * cleanly — one implementation, one spec file per type so a failure names the
 * editor it came from.
 *
 * Out of scope: "Clear all". It wipes the entire store, and the store is
 * server-side and shared by every spec (keyed by client IP) while spec files
 * run in parallel workers, so clearing it here would delete files other specs
 * are mid-test on. For the same reason nothing below asserts on the size or
 * contents of the list as a whole, only on rows the test created itself.
 *
 * Uploads under a generated name rather than using the create-new route: that
 * route hands out the lowest free name, so deleting `new (3).docx` releases it
 * back to the pool and a parallel worker can recreate it between the delete and
 * the assertion that it is gone. A name we chose ourselves is never reused.
 */
export function describeStoredFileDeletion(type: {
  /** Editor name for the describe title, e.g. `PDF form`. */
  label: string;
  /** Same thing mid-sentence, e.g. `PDF form` in "delete a PDF form". */
  noun: string;
  /** File extension, which also picks the sample document to upload. */
  ext: string;
  /** Row class the file list marks this type with: word, cell, slide, pdf. */
  rowClass: string;
}) {
  // Files the test uploaded, removed once the spec is done so a run against a
  // long-lived server (E2E_BASE_URL) does not accumulate them. Normally the
  // test has already deleted it; this covers a run that failed midway.
  const uploadedFiles: string[] = [];

  test.describe(`${type.label} - deleting a stored file`, () => {
    test.afterAll(({ browser }) => cleanUpStoredFiles(browser, uploadedFiles));

    test(`delete a ${type.noun} from the file list`, async ({ page }) => {
      await page.goto('/example/');
      const fileName = await uploadStoredFile(page, uniqueFileName('delete', type.ext));
      uploadedFiles.push(fileName);

      await page.goto('/example/');
      const row = storedFileRow(page, fileName);

      await test.step(`the ${type.noun} is listed`, async () => {
        await expect(row).toHaveCount(1);
        await expect(row.locator(`a.stored-edit.${type.rowClass}`)).toHaveCount(1);
      });

      await test.step('the row disappears without a reload', async () => {
        await storedFileDeleteButton(page, fileName).click();
        // The handler removes the row in place once the DELETE returns; there
        // is no navigation unless that was the last row in the list.
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
}
