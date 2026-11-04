import { test, expect, Page } from '@playwright/test';
import { openNewEditor, editorApi } from '../helpers';

const TEXT = 'Euro-Office e2e save test';

// Ctrl+A also selects the paragraph end, so the editor appends a line break.
const documentText = (editorPage: Page) =>
  editorApi(editorPage, (api) => api.asc_GetSelectedText())
    .then((text) => String(text).trim())
    .catch((e: Error) => `error: ${e.message}`);

test.describe('PDF form editor - add data and save', () => {
  test('typed text is saved and survives a reload', async ({ page }) => {
    test.setTimeout(120_000);

    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=pdf"]', /\.pdf/);

    await test.step('add data to the PDF form', async () => {
      await editorPage.keyboard.type(TEXT);

      // The edit registered: the undo button is no longer disabled.
      await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);

      await editorPage.keyboard.press('Control+A');
      await expect.poll(() => documentText(editorPage)).toBe(TEXT);
    });

    // Save explicitly with Ctrl+S (not relying on autosave). The example page
    // prefixes document.title with "*" while there are unsaved changes.
    await test.step('save the PDF form', async () => {
      await editorPage.keyboard.press('Control+S');
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
    });

    await test.step('saved data is still there after reload', async () => {
      await editorPage.reload();
      await editorPage.waitForLoadState('domcontentloaded');
      await expect(editorPage.locator('iframe[name="frameEditor"]')).toBeAttached({
        timeout: 15_000,
      });
      await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

      // The editor can rebuild its iframe shortly after a reload, so the whole
      // focus-select-read sequence is retried as a unit.
      await expect(async () => {
        await frame.locator('#editor_sdk').click();
        await editorPage.keyboard.press('Control+A');
        expect(await documentText(editorPage)).toBe(TEXT);
      }).toPass({ timeout: 30_000 });
    });
  });
});
