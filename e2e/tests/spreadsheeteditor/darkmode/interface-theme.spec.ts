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
});
