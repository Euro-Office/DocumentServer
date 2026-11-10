import { test, expect, Page } from '@playwright/test';
import { openNewEditor, editorApi, downloadStoredFile, saveAndReopen } from '../helpers';

const TITLE = 'Euro-Office e2e title';
const SUBTITLE = 'Euro-Office e2e subtitle';

// A new presentation opens on a Title slide: shape 1 is the title placeholder,
// shape 2 the subtitle placeholder. Tab moves the selection through the shapes.
async function focusShape(editorPage: Page, shapeNumber: number) {
  // Escape twice: leave text editing, then deselect, so Tab starts from the
  // first shape.
  await editorPage.keyboard.press('Escape');
  await editorPage.keyboard.press('Escape');
  for (let i = 0; i < shapeNumber; i++) {
    await editorPage.keyboard.press('Tab');
  }
}

async function fillShape(editorPage: Page, shapeNumber: number, text: string) {
  await focusShape(editorPage, shapeNumber);
  await editorPage.keyboard.press('Enter'); // start editing the selected shape
  await editorPage.keyboard.type(text);
}

async function readShape(editorPage: Page, shapeNumber: number) {
  await focusShape(editorPage, shapeNumber);
  await editorPage.keyboard.press('Enter');
  await editorPage.keyboard.press('Control+A');
  // Ctrl+A also selects the paragraph end, so the editor can append a line
  // break; trim it before comparing.
  const text = await editorApi(editorPage, (api) => api.asc_GetSelectedText());
  return String(text).trim();
}

test.describe('Presentation - add title and subtitle and save', () => {
  test('title and subtitle are saved and survive closing and reopening', async ({ page }) => {
    // 1. Open the example page, click "Presentation" (it has no id, so it is
    //    found by its title) and wait until the new .pptx editor has finished
    //    loading.
    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=pptx"]', /\.pptx/);

    // Storage holds the blank template until a save really reaches it.
    const blank = await downloadStoredFile(page, editorPage.url());

    await test.step('add title and subtitle', async () => {
      // 2. Type the title and the subtitle into their placeholders.
      await fillShape(editorPage, 1, TITLE);
      await fillShape(editorPage, 2, SUBTITLE);

      // 3. The edit registered: the undo button is no longer disabled.
      await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);

      // 4. Read both placeholders back through the automation API.
      await expect.poll(() => readShape(editorPage, 1)).toBe(TITLE);
      await expect.poll(() => readShape(editorPage, 2)).toBe(SUBTITLE);
    });

    // 5. Leave text editing, save explicitly with Ctrl+S (not relying on
    //    autosave), then wait until the changes are saved. The example page
    //    prefixes document.title with "*" while there are unsaved changes and
    //    removes it once they are saved.
    const saved = await test.step('save the presentation with Ctrl+S', async () => {
      await editorPage.keyboard.press('Escape');
      await editorPage.keyboard.press('Escape');
      await editorPage.keyboard.press('Control+S');
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
      // The title only reflects the editor's own state. Close the editor so
      // docservice writes the file back, wait for storage to change, and reopen
      // the saved file in a new tab (a reload would be served from cache).
      return saveAndReopen(page, editorPage, blank);
    });

    await test.step('saved title and subtitle are still there after reopening', async () => {
      // 8. Focus the editor surface so the keyboard shortcuts reach it, then
      //    check both placeholders still hold the typed text. The editor can
      //    rebuild its iframe shortly after a reload, so the whole sequence is
      //    retried as a unit.
      await expect(async () => {
        await saved.frame.locator('#editor_sdk').click();
        expect(await readShape(saved.editorPage, 1)).toBe(TITLE);
        expect(await readShape(saved.editorPage, 2)).toBe(SUBTITLE);
      }).toPass({ timeout: 30_000 });
    });
  });
});
