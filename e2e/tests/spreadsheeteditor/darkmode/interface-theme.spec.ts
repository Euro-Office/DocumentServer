import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval } from '../../helpers';

test.describe('Spreadsheet editor - dark mode', () => {
  /*
   TESTING INTERFACE THEME'S EFFECT ON CONTENT DARK MODE
  */
  test('interface theme forces content dark mode off, then restores it -- not fully independent', async ({ page }) => {
    // Switching interface theme to light unconditionally forces content
    // dark mode off; switching back to dark restores the remembered
    // preference automatically. So it's "remembered, but suspended while
    // the interface is light," not fully independent of interface theme.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-night'));
    await frameEval(editorPage, (win) => win.Common.UI.Themes.setContentTheme('dark'));
    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(true);

    // SWITCH INTERFACE THEME TO LIGHT -- CONTENT DARK MODE FORCED OFF

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-classic-light'));
    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);

    // SWITCH INTERFACE THEME BACK TO DARK -- PREFERENCE IS RESTORED

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-night'));
    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(true);
  });

  /*
   INTERFACE THEME SWITCH MUST NOT CORRUPT CONTENT DARK MODE'S OWN CELL COLORS

   GlobalSkin (the interface skin's live color object) is a direct reference
   into EditorSkins["theme-light"]/["theme-dark"], not an independent copy.
   Content dark mode's cell background/grid colors must stay at their own
   fixed values regardless of which interface skin is active.
  */
  test('switching interface theme does not change content dark mode\'s cell colors', async ({ page }) => {
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    const readCellColors = () =>
      frameEval(editorPage, (win) => {
        const dark = (win as any).AscCommon.EditorSkins['theme-dark'];
        return { background: dark.CellBackground, grid: dark.CellGrid };
      });

    // TODO: uses the same internal-API shortcut as the test above
    // (Common.UI.Themes.setTheme) rather than clicking the actual
    // interface-theme picker in the UI -- verifies the color values
    // themselves stay correct, not that the real UI control reaches this
    // code path. A fuller e2e would drive the actual theme-switcher.
    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-contrast-dark'));

    expect(await readCellColors()).toEqual({ background: '#262626', grid: '#454545' });
  });
});
