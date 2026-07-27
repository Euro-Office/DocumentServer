import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval } from '../../helpers';

test.describe('Spreadsheet editor - dark mode', () => {
  /*
   TESTING THE DARK DOCUMENT TOGGLE BUTTON
  */
  test('toggling content dark mode flips the api flag and syncs the toolbar button', async ({ page }) => {
    // The button is locked until the interface theme is dark. This clicks
    // the real button (not the API directly) in both directions and checks
    // its enabled/active state stays in sync with the underlying flag.
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await frame.locator('a[data-tab="view"]').click();

    const darkDocButton = frame.locator('#slot-btn-dark-document button').first();

    // BUTTON STARTS DISABLED IN A FRESH (LIGHT-THEME) DOCUMENT
    await expect(darkDocButton).toHaveClass(/disabled/);
    expect(await editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);

    // SWITCH INTERFACE THEME TO DARK -- BUTTON BECOMES ENABLED
    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-night'));

    await expect(darkDocButton).not.toHaveClass(/disabled/);
    expect(await editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);

    // CLICK THE BUTTON TO ENABLE DARK MODE
    await darkDocButton.click();

    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(true);
    await expect(darkDocButton).toHaveClass(/active/);

    // CLICK AGAIN TO SWITCH BACK TO LIGHT MODE

    // The click handler debounces rapid clicks for 500ms; a second click
    // inside that window is dropped rather than toggling again. This wait
    // is matched to that real, named constant, not a guess at timing.
    await editorPage.waitForTimeout(600);
    await darkDocButton.click();

    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);
    await expect(darkDocButton).not.toHaveClass(/active/);
  });
});
