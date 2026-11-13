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
import { describeStoredFileDeletion } from '../stored-file-delete.suite';

describeStoredFileDeletion({
  label: 'Document',
  noun: 'document',
  ext: 'docx',
  rowClass: 'word',
});

// Files this test uploaded. It keeps one on purpose, so cleanup is not
// redundant here. See stored-file-delete.suite.ts for the rest of the remit.
const uploadedFiles: string[] = [];

test.describe('Document - deleting one of several stored files', () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, uploadedFiles));

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
    // store would still pass the single-file test.
    await expect(storedFileRow(page, deletedFile)).toHaveCount(0);
    await expect(storedFileRow(page, keptFile)).toHaveCount(1);

    await page.reload();
    await expect(storedFileRow(page, keptFile)).toHaveCount(1);
  });
});
