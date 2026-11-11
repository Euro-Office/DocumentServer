import { test, expect, Page } from '@playwright/test';
import { openNewEditor, editorApi, downloadStoredFile, saveAndReopen } from '../helpers';

const TEXT = 'Euro-Office e2e save test';

// Ctrl+A also selects the paragraph end, so the editor appends a line break.
const documentText = (editorPage: Page) =>
  editorApi(editorPage, (api) => api.asc_GetSelectedText())
    .then((text) => String(text).trim())
    .catch((e: Error) => `error: ${e.message}`);

test.describe('PDF form editor - add data and save', () => {
  test('typed text is saved and survives closing and reopening', async ({ page }) => {
    test.setTimeout(120_000);

    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=pdf"]', /\.pdf/);

    // Storage holds the blank template until a save really reaches it.
    const blank = await downloadStoredFile(page, editorPage.url());

    await test.step('add data to the PDF form', async () => {
      await editorPage.keyboard.type(TEXT);

      // The edit registered: the undo button is no longer disabled.
      await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);

      await editorPage.keyboard.press('Control+A');
      await expect.poll(() => documentText(editorPage)).toBe(TEXT);
    });

    // Save explicitly with Ctrl+S (not relying on autosave). The example page
    // prefixes document.title with "*" while there are unsaved changes.
    const saved = await test.step('save the PDF form', async () => {
      await editorPage.keyboard.press('Control+S');
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
      // The title only reflects the editor's own state. Close the editor so
      // docservice writes the file back, wait for storage to change, and reopen
      // the saved file in a new tab (a reload would be served from cache).
      return saveAndReopen(page, editorPage, blank);
    });

    await test.step('saved data is still there after reopening', async () => {
      // The editor can rebuild its iframe shortly after opening, so the whole
      // focus-select-read sequence is retried as a unit.
      await expect(async () => {
        await saved.frame.locator('#editor_sdk').click();
        await saved.editorPage.keyboard.press('Control+A');
        expect(await documentText(saved.editorPage)).toBe(TEXT);
      }).toPass({ timeout: 30_000 });
    });
  });
});
