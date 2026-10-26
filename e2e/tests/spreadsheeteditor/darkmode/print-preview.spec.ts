import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval, expectColorClose } from '../../helpers';

test.describe('Spreadsheet editor - dark mode print', () => {
  /*
   TESTING PRINT PREVIEW STAYS LIGHT REGARDLESS OF CONTENT DARK MODE
  */
  test('print preview stays in light mode regardless of content dark mode', async ({ page }) => {
    // Print already renders through a rendering context with dark mode
    // forced off. This confirms the print-preview canvas background stays
    // white even with content dark mode on, using a cell whose text
    // overflows across several empty neighboring cells -- a layout that
    // once leaked dark-theme colors into print at the cell boundaries.
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(1, 2, 1, 2).setValue('automatic borders colors here overflowing text');
    });

    // SWITCH TO DARK MODE
    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));
    await expect.poll(() => editorApi(editorPage, (api) => api.isDarkMode)).toBe(true);

    // OPEN PRINT PREVIEW (FILE TAB -> "PRINT WITH PREVIEW")

    // Drives the real UI, not asc_initPrintPreview directly -- the panel's
    // container element that the API call needs only exists via this flow.
    await frame.locator('a[data-tab="file"]').click();
    await frame.locator('#fm-btn-print-with-preview').click();

    // The preview canvas is created lazily once the panel shows -- wait for
    // it rather than assume it's there immediately after the click.
    const previewCanvas = frame.locator('#print-preview-canvas');
    await expect(previewCanvas).toBeAttached({ timeout: 10_000 });

    // MEASURE PRINT PREVIEW BACKGROUND

    const corners = await frameEval(editorPage, (win) => {
      const canvas = win.document.getElementById('print-preview-canvas') as HTMLCanvasElement;
      const ctx = canvas.getContext('2d')!;
      const px = (x: number, y: number) => Array.from(ctx.getImageData(x, y, 1, 1).data.slice(0, 3));
      return { topLeft: px(2, 2), bottomRight: px(canvas.width - 3, canvas.height - 3) };
    });

    expectColorClose(corners.topLeft, [255, 255, 255]);
    expectColorClose(corners.bottomRight, [255, 255, 255]);

    // TODO: this only checks the page background stays light, not that the
    // specific black-bars artifact 5.2 fixed is absent at the cell-boundary
    // lines the overflowing text crosses. A full regression guard for that
    // would need to know the exact print-preview pixel coordinates of each
    // cell boundary within the overflowing row, not yet worked out.
  });
});
