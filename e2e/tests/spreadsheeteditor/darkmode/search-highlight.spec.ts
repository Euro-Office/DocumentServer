import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi } from '../../helpers';
import { sampleCellPixels } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   TESTING SEARCH-HIGHLIGHT TEXT CONTRAST IN DARK MODE
  */
  test('search-highlighted cell text stays readable in dark mode', async ({ page }) => {
    // Automatic text on a search-highlighted cell must stay dark/readable
    // against the highlight's own light yellow fill, in both light and dark
    // mode -- not inverted to light just because dark mode is on.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // Short text that stays within one cell's width -- longer text overflows
    // into the empty neighbor cell, leaving no glyph ink to sample within
    // this cell's own bounds.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(1, 1, 1, 1).setValue('hi');
    });

    await editorApi(editorPage, (api) => {
      const options = new (window as any).Asc.asc_CFindOptions();
      options.asc_setFindWhat('hi');
      options.asc_setScanForward(true);
      options.asc_setIsMatchCase(false);
      options.asc_setIsWholeCell(false);
      options.asc_setScanOnOnlySheet((window as any).Asc.c_oAscSearchBy.Sheet);
      options.asc_setScanByRows(true);
      options.asc_setLookIn((window as any).Asc.c_oAscFindLookIn.Value);
      api.asc_findText(options);
      api.asc_selectSearchingResults(true);
      // Unlike a plain setValue(), the search calls don't trigger their own
      // repaint -- without this, the cell samples as a uniform fill color
      // with no glyph ink at all.
      const ws = api.wb.getWorksheet();
      ws._cleanCellsTextMetricsCache();
      ws.draw();
    });

    // Poll for the highlight to actually be showing rather than assume it
    // landed synchronously.
    const luminanceSum = (rgb: number[]) => rgb[0] + rgb[1] + rgb[2];
    await expect.poll(async () => luminanceSum((await sampleCellPixels(editorPage, 1, 1)).lightest)).toBeGreaterThan(400);

    // MEASURE TEXT/HIGHLIGHT CONTRAST IN LIGHT MODE

    const before = await sampleCellPixels(editorPage, 1, 1);
    expect(luminanceSum(before.darkest)).toBeLessThan(100);
    expect(luminanceSum(before.lightest)).toBeGreaterThan(400);

    // SWITCH TO DARK MODE

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));

    // MEASURE TEXT/HIGHLIGHT CONTRAST IN DARK MODE

    // Text must stay dark/readable; the highlight fill stays a light color
    // too (shifted to a muted yellow, not inverted to a dark canvas gray).
    await expect.poll(async () => luminanceSum((await sampleCellPixels(editorPage, 1, 1)).darkest)).toBeLessThan(100);
    const after = await sampleCellPixels(editorPage, 1, 1);
    expect(luminanceSum(after.darkest)).toBeLessThan(100);
    expect(luminanceSum(after.lightest)).toBeGreaterThan(300);
  });
});
