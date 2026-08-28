import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi } from './helpers';

const cellText = (editorPage: import('@playwright/test').Page) =>
  editorApi(editorPage, (api) => {
    const info = api.asc_getCellInfo();
    return info && info.asc_getText ? info.asc_getText() : null;
  });

test.describe('Spreadsheet editor - numbers and formulas', () => {
  test('enter numbers and a formula', async ({ page }) => {
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);
    const nameBox = frame.locator('#ce-cell-name');
    const select = async (cell: string) => {
      await nameBox.fill(cell);
      await nameBox.press('Enter');
    };

    // Ctrl+Home guarantees the grid has keyboard focus at A1 (the helper's
    // canvas click can leave an arbitrary cell selected).
    await editorPage.keyboard.press('Control+Home');
    await editorPage.keyboard.type('5');
    await editorPage.keyboard.press('Enter');
    await editorPage.keyboard.type('10');
    await editorPage.keyboard.press('Enter');
    await editorPage.keyboard.type('=A1+A2');
    await editorPage.keyboard.press('Enter');

    // Operands landed in A1/A2. nameBox.press('Enter') resolves on key dispatch,
    // not once asc_getCellInfo() reflects the new selection, so read with
    // expect.poll() rather than a one-shot read — same async-value race the
    // presentation test already guards against for slide count.
    await select('A1');
    await expect.poll(() => cellText(editorPage)).toBe('5');
    await select('A2');
    await expect.poll(() => cellText(editorPage)).toBe('10');

    // The formula was accepted into A3. asc_getText() returns the formula
    // string, not the computed value.
    await select('A3');
    await expect.poll(() => cellText(editorPage)).toBe('=A1+A2');

    // TODO: verify the *computed* value (15). asc_getCellInfo().asc_getText()
    // returns the formula, and pluginMethod_GetSelectedText() returns "" for
    // cell selections, so neither reflects the result. The clipboard route
    // (select A3 -> Ctrl+C -> navigator.clipboard.readText() === '15') works
    // but needs clipboard-read/write permissions wired into the project config.
  });
});
