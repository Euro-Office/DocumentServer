import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval } from '../../helpers';
import { sampleCellPixels } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   TESTING MID-EDIT DARK-MODE TOGGLE BEHAVIOR (ACCEPTED, NOT A BUG)
  */
  test('a cell actively being edited does not live-update on a mid-edit dark-mode toggle', async ({ page }) => {
    // Neither the cell editor's text nor its background updates live if
    // dark mode is toggled mid-edit -- both are one-time snapshots taken
    // when editing starts. This is intentional (a live-refresh fix was
    // prototyped and deliberately reverted as not worth it for this narrow,
    // self-correcting gap), so this pins the current behavior as a
    // regression guard, not a gap to fix.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await editorPage.keyboard.press('Control+Home');
    await editorPage.keyboard.type('hello');

    const ceColors = () =>
      frameEval(editorPage, (win) => {
        const canvas = win.document.getElementById('ce-canvas') as HTMLCanvasElement;
        const ctx = canvas.getContext('2d')!;
        const img = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        const set = new Set<string>();
        for (let i = 0; i < img.length; i += 4) set.add(img[i] + ',' + img[i + 1] + ',' + img[i + 2]);
        return Array.from(set).sort();
      });

    const before = await ceColors();

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));
    // Confirm the toggle is genuinely in effect elsewhere (the main grid),
    // so a lack of change in ce-canvas below can't be mistaken for the
    // toggle simply not having landed yet.
    await expect.poll(() => sampleCellPixels(editorPage, 5, 5).then((s) => s.darkest)).not.toEqual([255, 255, 255]);

    const after = await ceColors();
    expect(after).toEqual(before);

    // ENDING THE EDIT AND STARTING A NEW ONE DOES PICK UP THE NEW THEME
    await editorPage.keyboard.press('Escape');
    await editorPage.keyboard.press('Control+Home');
    await editorPage.keyboard.type('world');
    await expect.poll(async () => (await ceColors()).includes('38,38,38')).toBe(true);
  });
});
