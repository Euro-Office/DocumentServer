import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, expectColorClose } from '../../helpers';
import { sampleMergedCellPixels } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   TESTING MERGED CELL COLOR CORRECTION
  */
  test('merged cell with automatic colors inverts the same way a regular cell does', async ({ page }) => {
    // A merged cell must follow the same automatic/explicit color rules as
    // a regular cell, not some mismatched combination of the two.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // B2:C2 merged, left on automatic colors (no fill, no explicit text).
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(1, 1, 1, 1).setValue('merged text');
      api.asc_findCell('B2:C2');
    });
    await editorApi(editorPage, (api) => api.asc_mergeCells((window as any).Asc.c_oAscMergeOptions.Merge));

    // asc_mergeCells lands on the model a tick later -- poll rather than
    // assume it's synchronous.
    await expect.poll(() =>
      editorApi(editorPage, (api) => {
        const merged = api.wb.getWorksheet().model.getMergedByCell(1, 1);
        return merged ? [merged.r1, merged.c1, merged.r2, merged.c2] : null;
      }),
    ).toEqual([1, 1, 1, 2]);

    // MEASURE COLORS IN LIGHT MODE

    const before = await sampleMergedCellPixels(editorPage, 1, 1, 2);
    expectColorClose(before.darkest, [0, 0, 0]);
    expectColorClose(before.lightest, [255, 255, 255]);

    // SWITCH TO DARK MODE

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));

    // MEASURE COLORS IN DARK MODE

    // Text inverts to white, background inverts to the dark canvas gray --
    // the same pattern a regular automatic cell follows.
    await expect.poll(async () => (await sampleMergedCellPixels(editorPage, 1, 1, 2)).lightest).toEqual([255, 255, 255]);
    const after = await sampleMergedCellPixels(editorPage, 1, 1, 2);
    expectColorClose(after.darkest, [38, 38, 38]);
  });
});
