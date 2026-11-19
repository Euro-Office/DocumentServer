import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval, expectColorClose } from '../../helpers';
import { bottomBorderPixel } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   TESTING CELL BORDER COLOR CORRECTION
  */
  test('automatic cell border color inverts in dark mode; explicit border color stays untouched', async ({ page }) => {
    // C2 gets an automatic-colored bottom border, D2 an explicit one.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // asc_CBorder(style, color) -- omitting color leaves it automatic (null).
    await editorApi(editorPage, (api) => {
      api.asc_findCell('C2');
      const borders: any[] = [];
      borders[(window as any).Asc.c_oAscBorderOptions.Bottom] = new (window as any).Asc.asc_CBorder((window as any).Asc.c_oAscBorderStyles.Thin);
      api.asc_setCellBorders(borders);
    });
    await editorApi(editorPage, (api) => {
      api.asc_findCell('D2');
      const borders: any[] = [];
      borders[(window as any).Asc.c_oAscBorderOptions.Bottom] =
        new (window as any).Asc.asc_CBorder((window as any).Asc.c_oAscBorderStyles.Thin, new (window as any).Asc.asc_CColor(220, 20, 20));
      api.asc_setCellBorders(borders);
    });

    // asc_setCellBorders lands on the model a tick later -- poll rather than
    // assume it's synchronous. Uses frameEval (not editorApi) since row/col
    // need to travel as real args.
    const bottomBorderWidth = (row: number, col: number) =>
      frameEval(editorPage, (win, row: number, col: number) => {
        const b = win.Asc.editor.wb.getWorksheet().model.getRange3(row, col, row, col).getBorderFull();
        return b.b ? b.b.w : 0;
      }, [row, col]);
    await expect.poll(() => bottomBorderWidth(1, 2)).toBeGreaterThan(0);
    await expect.poll(() => bottomBorderWidth(1, 3)).toBeGreaterThan(0);

    // MEASURE BORDER COLOR IN LIGHT MODE

    // C2's automatic border resolves to literal black by default, same as
    // automatic text.
    expectColorClose(await bottomBorderPixel(editorPage, 1, 2), [0, 0, 0]);
    expectColorClose(await bottomBorderPixel(editorPage, 1, 3), [220, 20, 20]);

    // SWITCH TO DARK MODE

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));

    // MEASURE BORDER COLOR IN DARK MODE

    // C2's automatic border inverts for contrast; D2's explicit border is
    // exactly unchanged.
    await expect.poll(() => bottomBorderPixel(editorPage, 1, 2)).toEqual([255, 255, 255]);
    expectColorClose(await bottomBorderPixel(editorPage, 1, 3), [220, 20, 20]);
  });
});
