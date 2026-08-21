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
    await editorPage.waitForTimeout(500+250);
    await darkDocButton.click();

    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);
    await expect(darkDocButton).not.toHaveClass(/active/);
  });

  /*
   INLIGHTTHEME LOCK RE-ENGAGES WHEN SWITCHING BACK TO A LIGHT INTERFACE THEME
  */
  test('dark document button re-locks when interface theme switches back to light', async ({ page }) => {
    // toggle-button.spec.ts's other test only checks the unlock direction
    // (light -> dark). This covers the inverse: the button must go back to
    // disabled once the interface theme is light again, not stay enabled.
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await frame.locator('a[data-tab="view"]').click();
    const darkDocButton = frame.locator('#slot-btn-dark-document button').first();

    await expect(darkDocButton).toHaveClass(/disabled/);

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-night'));
    await expect(darkDocButton).not.toHaveClass(/disabled/);

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-classic-light'));
    await expect(darkDocButton).toHaveClass(/disabled/);
  });

  /*
   RAPID DOUBLE-TOGGLE WITHIN THE 500MS DEBOUNCE WINDOW
  */
  test('a second click inside the 500ms debounce window is dropped, not toggled back', async ({ page }) => {
    // Unlike the first test above (which waits past the debounce window
    // before clicking again), this clicks twice back-to-back to exercise
    // the debounce guard itself: onChangeDarkMode's second call within the
    // window re-syncs the button to the current state instead of flipping
    // it again.
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await frame.locator('a[data-tab="view"]').click();
    const darkDocButton = frame.locator('#slot-btn-dark-document button').first();

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-night'));

    await darkDocButton.click();
    await darkDocButton.click();

    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(true);
    await expect(darkDocButton).toHaveClass(/active/);
  });

  /*
   LOSTCONNECT LOCK DISABLES THE BUTTON ON A DROPPED COLLABORATIVE CONNECTION
  */
  test('dark document button is disabled after the api reports a lost connection', async ({ page }) => {
    // 'api:disconnect' is what asc_onCoAuthoringDisconnect ultimately triggers
    // in the real disconnect path, so firing it directly is a faithful
    // simulation, not a proxy for a different event.
    //
    // This only covers the lock direction, not recovery. Note this is
    // specific to the lostConnect cause set here (permanent coauthoring
    // disconnect) -- it's distinct from the app's transient reconnect flow
    // (Asc.c_oAscAsyncAction.Disconnect / DisableToolbar's menuFileOpen
    // mask), which does recover. lostConnect itself is only ever set to
    // true across the whole toolbar (grepped every reference in
    // view/Toolbar.js), never reset to false, so there's nothing to
    // simulate on the reconnect side for this specific lock.
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await frame.locator('a[data-tab="view"]').click();
    const darkDocButton = frame.locator('#slot-btn-dark-document button').first();

    await frameEval(editorPage, (win) => win.Common.UI.Themes.setTheme('theme-night'));
    await expect(darkDocButton).not.toHaveClass(/disabled/);

    await frameEval(editorPage, (win) => win.Common.NotificationCenter.trigger('api:disconnect'));
    await expect(darkDocButton).toHaveClass(/disabled/);
  });
});
