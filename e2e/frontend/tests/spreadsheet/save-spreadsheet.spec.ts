import { test, expect, Page } from '@playwright/test';
import { openNewEditor, editorApi } from '../helpers';

// What each cell holds as text.
const CELLS: [cell: string, text: string][] = [
  ['A1', 'Euro-Office'],
  ['A2', '42'],
];

// Returns an "error: ..." string instead of throwing while the editor iframe is
// being (re)built, so expect.poll retries and a final failure shows the cause.
const cellText = (editorPage: Page) =>
  editorApi(editorPage, (api) => {
    const info = api.asc_getCellInfo();
    return info && info.asc_getText ? info.asc_getText() : null;
  }).catch((e: Error) => `error: ${e.message}`);

test.describe('Spreadsheet - add data and save', () => {
  test('entered cells are saved and survive a reload', async ({ page }) => {
    // Reloading can need several attempts, so allow more than the default 60s.
    test.setTimeout(120_000);

    // 1. Open the example page, click "Spreadsheet" (it has no id, so it is
    //    found by its title) and wait until the new .xlsx editor has finished
    //    loading.
    const { editorPage, frame } = await openNewEditor(
      page,
      'a[title="Create new spreadsheet"]',
      /\.xlsx/,
    );

    // The name box selects a cell; it is an id, so it is the stable handle.
    const selectCell = async (cell: string) => {
      const nameBox = frame.locator('#ce-cell-name');
      await nameBox.fill(cell);
      await nameBox.press('Enter');
    };

    await test.step('add data to the spreadsheet', async () => {
      // 2. Ctrl+Home guarantees the grid has keyboard focus at A1.
      await editorPage.keyboard.press('Control+Home');

      // 3. Type each value and press Enter to move down to the next cell.
      for (const [, text] of CELLS) {
        await editorPage.keyboard.type(text);
        await editorPage.keyboard.press('Enter');
      }

      // 4. The edit registered: the undo button is no longer disabled.
      await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);

      // 5. Read each cell back through the automation API.
      for (const [cell, text] of CELLS) {
        await selectCell(cell);
        await expect.poll(() => cellText(editorPage)).toBe(text);
      }
    });

    // 6. Press Ctrl+Home again to put keyboard focus back on the grid (selecting
    //    cells through the name box moved it), save explicitly with Ctrl+S (not
    //    relying on autosave), then wait until the changes are saved. The
    //    example page prefixes document.title with "*" while there are unsaved
    //    changes and removes it once they are saved.
    await test.step('save the spreadsheet with Ctrl+S', async () => {
      await editorPage.keyboard.press('Control+Home');
      await editorPage.keyboard.press('Control+S');
      await expect(editorPage).not.toHaveTitle(/^\*/, { timeout: 30_000 });
    });

    await test.step('saved data is still there after reload', async () => {
      // 7. Reload the editor and check every cell. After a reload the editor
      //    page can come back blank, and a blank page does not recover by
      //    itself, so the whole reload-and-check is retried as a unit.
      await expect(async () => {
        await editorPage.reload();
        await editorPage.waitForLoadState('domcontentloaded');

        // 8. Wait until the editor has finished loading again. The loading
        //    mask is not enough: it counts as hidden while it does not exist
        //    yet, and the name box shows before the document is loaded.
        //    Selecting a cell too early makes the editor throw in
        //    asc_findCell ("reading 'getWorksheet'") and break, so wait for
        //    the editor's own isDocumentLoadComplete flag.
        await expect(editorPage.locator('iframe[name="frameEditor"]')).toBeAttached({
          timeout: 15_000,
        });
        await expect(frame.locator('#ce-cell-name')).toBeVisible({ timeout: 15_000 });
        await expect
          .poll(
            () =>
              editorApi(editorPage, (api) => api.isDocumentLoadComplete === true).catch(
                () => false,
              ),
            { timeout: 30_000 },
          )
          .toBe(true);

        // 9. Each cell still holds the typed text.
        for (const [cell, text] of CELLS) {
          await selectCell(cell);
          await expect.poll(() => cellText(editorPage), { timeout: 10_000 }).toBe(text);
        }
      }).toPass({ timeout: 80_000, intervals: [2_000, 5_000] });
    });
  });
});
