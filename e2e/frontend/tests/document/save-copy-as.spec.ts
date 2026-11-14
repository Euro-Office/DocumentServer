// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import { openNewEditor, newFileLink } from '../helpers';

// File > Save Copy As converts the document on the server and hands the
// integrator a URL to the copy through onRequestSaveAs, which the example page
// posts to /example/create. In 9.3.8-rc.1 writing the DOCX copy threw in the
// browser, so no URL was handed over and the editor showed a warning instead
// (DocumentServer#556).
const FORMATS = [
  { ext: 'docx', magic: 'PK' },
  { ext: 'pdf', magic: '%PDF' },
];

type Launch = { Common?: { Controllers?: { LaunchController?: { isScriptLoaded(): boolean } } } };

test.describe('Document editor - save a copy', () => {
  test('Save Copy As hands the integrator a downloadable DOCX and PDF', async ({ page }) => {
    const { editorPage, frame } = await openNewEditor(page, newFileLink('docx'), /\.docx/);

    // The File tab ignores clicks until the editor's deferred scripts are loaded.
    await editorPage
      .frame({ name: 'frameEditor' })!
      .waitForFunction(() =>
        (window as unknown as Launch).Common?.Controllers?.LaunchController?.isScriptLoaded(),
      );

    // Stand in for the integrator: answer /example/create here, so nothing
    // lands in the shared file store and the example's fetch rules don't matter.
    await editorPage.route('**/example/create', (route) => route.fulfill({ json: {} }));

    for (const { ext, magic } of FORMATS) {
      await test.step(`save a copy as ${ext.toUpperCase()}`, async () => {
        const saveAs = editorPage.waitForRequest('**/example/create', { timeout: 30_000 });
        await frame.locator('a[data-tab="file"]').click();
        await frame.locator('#fm-btn-save-copy').click();
        await frame.locator(`#panel-savecopy .btn-doc-format:has(.svg-format-${ext})`).click();

        const { title, url } = (await saveAs).postDataJSON();
        expect(title).toMatch(new RegExp(`\\.${ext}$`));

        const copy = await editorPage.request.get(url);
        expect(copy.status()).toBe(200);
        expect((await copy.body()).subarray(0, magic.length).toString()).toBe(magic);
      });
    }

    await expect(frame.locator('.asc-window.alert')).toHaveCount(0);
  });
});
