import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, expectColorClose } from '../../helpers';
import { resizeColumnGuideColor } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   TESTING COLUMN RESIZE GUIDE VISIBILITY IN DARK MODE
  */
  test('column resize guide is visible against the dark canvas, not near-black-on-black', async ({ page }) => {
    // The resize-drag guide line was hardcoded to black, invisible against a
    // dark canvas. This confirms it now uses a theme-aware color instead.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // Select a cell in a different column first: drawing the guide also
    // repaints the current selection marquee, which would otherwise
    // contaminate the sampled column if selection were nearby.
    await editorApi(editorPage, (api) => api.asc_findCell('H2'));

    // MEASURE GUIDE COLOR IN LIGHT MODE
    expectColorClose((await resizeColumnGuideColor(editorPage, 1))!, [0, 0, 0]);

    // SWITCH TO DARK MODE
    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));

    // MEASURE GUIDE COLOR IN DARK MODE
    await expect.poll(() => resizeColumnGuideColor(editorPage, 1)).toEqual([204, 204, 204]);
  });

  // TODO: row resize (drawRowGuides) not covered here -- only the column
  // guide (drawColumnGuides) was verified. The two are structurally
  // near-identical in source, but that symmetry hasn't actually been
  // checked live per this file's own working principle (don't assume
  // symmetry between sides/axes without verifying each one).
});
