import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, expectColorClose } from '../../helpers';
import { cellFillRgb, cellFontRgb, sampleCellPixels } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   TESTING CORE CELL COLOR CORRECTION
  */
  test('automatic cell colors invert in dark mode; explicit colors stay untouched', async ({ page }) => {
    // Covers the four automatic/explicit combinations a cell's fill and text
    // can be in: B2 (both automatic), B3 (fill only), B4 (both explicit),
    // B6 (text only). Measures each before/after toggling dark mode.
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // Assert the light-mode starting point explicitly rather than assume it
    // -- every "before" check below relies on it.
    expect(await editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);

    // WRITE B2/B3/B4/B6

    // B2: left on default/automatic colors -- no fill, no explicit text color.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(1, 1, 1, 1).setValue('lorem');
    });

    // B3: explicit fill only.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(2, 1, 2, 1).setValue('bgOnly');
    });

    // asc_setCellBackgroundColor/asc_setCellTextColor land on the model a
    // tick after the call returns -- poll rather than assume it's synchronous.
    await editorApi(editorPage, (api) => {
      api.asc_findCell('B3');
      api.asc_setCellBackgroundColor(new (window as any).Asc.asc_CColor(200, 100, 50));
    });
    await expect.poll(() => cellFillRgb(editorPage, 2, 1)).not.toBeNull();

    // B4: explicit fill + explicit text color.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(3, 1, 3, 1).setValue('bgAndText');
      api.asc_findCell('B4');
      api.asc_setCellBackgroundColor(new (window as any).Asc.asc_CColor(30, 30, 120));
    });
    await expect.poll(() => cellFillRgb(editorPage, 3, 1)).not.toBeNull();

    await editorApi(editorPage, (api) => {
      api.asc_findCell('B4');
      api.asc_setCellTextColor(new (window as any).Asc.asc_CColor(255, 220, 0));
    });
    await expect.poll(() => cellFontRgb(editorPage, 3, 1)).not.toBeNull();

    // B6: automatic fill (none) + explicit text color only.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(5, 1, 5, 1).setValue('textOnly');
      api.asc_findCell('B6');
      api.asc_setCellTextColor(new (window as any).Asc.asc_CColor(10, 10, 60));
    });
    await expect.poll(() => cellFontRgb(editorPage, 5, 1)).not.toBeNull();

    // MEASURE COLORS IN LIGHT MODE

    const b2Before = await sampleCellPixels(editorPage, 1, 1);
    const b3Before = await sampleCellPixels(editorPage, 2, 1);
    const b4Before = await sampleCellPixels(editorPage, 3, 1);
    const b6Before = await sampleCellPixels(editorPage, 5, 1);

    // B2's automatic text is literal black against the light-mode canvas.
    expectColorClose(b2Before.darkest, [0, 0, 0]);
    // B3's explicit fill renders as set.
    expectColorClose(b3Before.lightest, [200, 100, 50]);
    // B4's explicit fill and explicit text both render as set.
    expectColorClose(b4Before.darkest, [30, 30, 120]);
    expectColorClose(b4Before.lightest, [255, 220, 0]);
    // B6's explicit text renders as set; its automatic (no-fill) background
    // is plain white in light mode.
    expectColorClose(b6Before.darkest, [10, 10, 60]);
    expectColorClose(b6Before.lightest, [255, 255, 255]);

    // SWITCH TO DARK MODE

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));

    // MEASURE COLORS IN DARK MODE

    // Poll rather than sample immediately after the toggle -- draw() may not
    // land within the same tick asc_setContentDarkMode returns in.
    await expect.poll(async () => (await sampleCellPixels(editorPage, 1, 1)).lightest).toEqual([255, 255, 255]);

    const b3After = await sampleCellPixels(editorPage, 2, 1);
    const b4After = await sampleCellPixels(editorPage, 3, 1);
    const b6After = await sampleCellPixels(editorPage, 5, 1);

    // Explicit fill/text colors are exactly unchanged by the dark-mode toggle.
    expectColorClose(b3After.lightest, [200, 100, 50]);
    expectColorClose(b4After.darkest, [30, 30, 120]);
    expectColorClose(b4After.lightest, [255, 220, 0]);
    // KNOWN BUG: B3's automatic text should invert for contrast in dark mode
    // the same way B2's does, but any explicit fill -- light or dark --
    // currently forces it to stay literal black instead. This asserts
    // today's actual (wrong) output on purpose: it starts failing the
    // moment that bug is fixed, which is the signal to update it, not a
    // regression to chase.
    expectColorClose(b3After.darkest, [0, 0, 0]);
    // B6's explicit text is still unchanged; its automatic background is now
    // the dark canvas gray instead of white -- the two swap which slot
    // (darkest/lightest) they land in, since the text color (sum 80) is
    // darker than both the light-mode white background (sum 765) and the
    // dark-mode gray background (sum 114), so it's "darkest" in both modes.
    expectColorClose(b6After.darkest, [10, 10, 60]);
    expectColorClose(b6After.lightest, [38, 38, 38]);
  });
});
