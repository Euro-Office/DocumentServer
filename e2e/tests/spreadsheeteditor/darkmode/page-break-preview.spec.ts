import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval, expectColorClose } from '../../helpers';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   PAGE BREAK PREVIEW, DARK MODE: OUTSIDE-PRINT-AREA OVERLAY MUST MATCH THE GRID-LINE COLOR

   Page Break Preview shades the area outside the print range using
   cells.defaultState.border -- the same theme-resolved color every ordinary
   grid line already uses (drawn via setStrokeStyle, never dark-mode
   corrected). The overlay itself is painted through drawFillCell instead,
   which re-applies getDarkModeCorrectedColor unless bIsExplicitFill says
   otherwise. Before the fix, that flag came out false in the main
   _drawRowBG loop, and wasn't passed at all for merged-cell sub-rectangles
   -- so the already-resolved border color got corrected a second time,
   landing a near-white overlay next to dark-grey grid lines in dark mode.
   See TASKS/10-build-pr-endsession-sanitizer for the diagnosis.
  */
  test('page-break-preview overlay color matches the grid-line border color in dark mode', async ({ page }) => {
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // A single filled cell defines the print area (A1:B2) -- every other
    // visible cell lands outside the print area once Page Break Preview is
    // on, which is exactly the overlay this test targets.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(1, 1, 1, 1).setValue('hi');
    });

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));
    await editorApi(editorPage, (api) =>
      api.asc_SetSheetViewType((window as any).Asc.c_oAscESheetViewType.pageBreakPreview),
    );

    const sample = () =>
      frameEval(editorPage, (win) => {
        const ws = win.Asc.editor.wb.getWorksheet();
        // J20 -- well outside the A1:B2 print range, still on-screen at
        // the default zoom/window size.
        const col = 9;
        const row = 19;
        const rect = ws.getCellCoord(col, row);
        const ctx = win.document.getElementById('ws-canvas').getContext('2d');
        const d = ctx.getImageData(Math.round(rect._x) + 3, Math.round(rect._y) + 3, 1, 1).data;
        const border = ws.settings.cells.defaultState.border;
        return {
          outsideAreaPixel: [d[0], d[1], d[2]],
          expectedBorder: [border.getR(), border.getG(), border.getB()],
          isOutsidePrintArea: ws.pagesModeDataContains(col, row) === false,
        };
      });

    // Poll: the print-page layout is computed lazily on the first grid
    // draw after switching view type, not synchronously on the API call.
    await expect.poll(async () => (await sample()).isOutsidePrintArea).toBe(true);

    const { outsideAreaPixel, expectedBorder } = await sample();
    expectColorClose(outsideAreaPixel, expectedBorder);
  });
});
