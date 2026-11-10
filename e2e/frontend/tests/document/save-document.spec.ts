import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, downloadStoredFile, saveAndReopen } from '../helpers';

// The text typed into the document and expected back after reopening.
const TEXT = 'Euro-Office e2e save test';

test.describe('Document editor - add data and save', () => {
  test('typed text is saved and survives closing and reopening', async ({ page }) => {
    // 1. Open the example page, click "Document" (it has no id, so it is found
    //    by its title) and wait until the new .docx editor has finished loading.
    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=docx"]', /\.docx/);

    // Storage holds the blank template until a save really reaches it.
    const blank = await downloadStoredFile(page, editorPage.url());

    await test.step('add data to the document', async () => {
      // 2. Type the text into the document.
      await editorPage.keyboard.type(TEXT);

      // 3. The edit registered: the undo button is no longer disabled.
      await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);
    });

    // 4. Save explicitly with Ctrl+S (not relying on autosave), then wait until
    //    the changes are saved. The example page prefixes document.title with
    //    "*" while there are unsaved changes and removes it once they are saved.
    const saved = await test.step('save the document with Ctrl+S', async () => {
      await editorPage.keyboard.press('Control+S');
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
      // The title only reflects the editor's own state. Close the editor so
      // docservice writes the file back, wait for storage to change, and reopen
      // the saved file in a new tab (a reload would be served from cache).
      return saveAndReopen(page, editorPage, blank);
    });

    await test.step('saved data is still there after reopening', async () => {
      // 7. Select everything and read it back through the automation API to
      //    verify the typed text survived the save. The editor can rebuild its
      //    iframe shortly after a reload, so the whole focus-select-read
      //    sequence is retried as a unit.
      await expect(async () => {
        await saved.frame.locator('#editor_sdk').click();
        await saved.editorPage.keyboard.press('Control+A');
        const text = await editorApi(saved.editorPage, (api) => api.asc_GetSelectedText());
        expect(text).toContain(TEXT);
      }).toPass({ timeout: 30_000 });
    });
  });
});
