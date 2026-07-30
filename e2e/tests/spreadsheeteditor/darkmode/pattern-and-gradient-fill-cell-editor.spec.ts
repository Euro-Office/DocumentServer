import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, frameEval } from '../../helpers';
import { cellFillRgb, cellHasGradientFill } from '../../utils/spreadsheet-editor';

test.describe('Spreadsheet editor - dark mode rendering', () => {
  /*
   GRADIENT-FILLED CELL, EDITED IN DARK MODE: TEXT MUST STAY READABLE

   The cell editor never actually renders a gradient/pattern fill behind the
   text being edited (a separate, pre-existing simplification) -- it falls
   back to painting the theme-resolved cells.defaultState.background instead,
   which does track dark mode (white in light mode, #262626 in dark mode).
   Before the fix, the automatic-text-color decision didn't know that
   fallback had happened and kept its grid-path "unknown gradient contrast,
   don't touch the text" exemption regardless -- so the text rendered at its
   literal stored black, unreadable against the now-dark fallback background.
   See TASKS/5-dark-theme-canvas-background/5.10-gradient-fill-editor-black-text.
  */
  test('editing a gradient-filled cell keeps automatic text readable against the editor background', async ({ page }) => {
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    expect(await editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);

    // B2: a value, and a gradient fill with no patternFill at all -- the
    // specific shape that makes Fill.prototype.bg()/getSolidFill() return
    // null (both only ever look at patternFill), which is what leads the
    // editor to fall back to cells.defaultState.background in the first place.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(1, 1, 1, 1).setValue('gradient');
      api.asc_findCell('B2');
    });

    await editorApi(editorPage, (api) => {
      const w = window as any;
      const fill = new w.Asc.asc_CFill2();
      const gradient = new w.Asc.asc_CGradientFill();
      const stop1 = new w.Asc.asc_CGradientStop();
      stop1.asc_setColor(new w.Asc.asc_CColor(80, 80, 200));
      stop1.asc_setPosition(0);
      const stop2 = new w.Asc.asc_CGradientStop();
      stop2.asc_setColor(new w.Asc.asc_CColor(20, 20, 80));
      stop2.asc_setPosition(1);
      gradient.asc_putGradientStops([stop1, stop2]);
      fill.asc_setGradientFill(gradient);
      api.asc_setCellFill(fill);
    });
    await expect.poll(() => cellHasGradientFill(editorPage, 1, 1)).toBe(true);

    const ceColors = () =>
      frameEval(editorPage, (win) => {
        const canvas = win.document.getElementById('ce-canvas') as HTMLCanvasElement;
        const ctx = canvas.getContext('2d')!;
        const img = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        const set = new Set<string>();
        for (let i = 0; i < img.length; i += 4) set.add(img[i] + ',' + img[i + 1] + ',' + img[i + 2]);
        return Array.from(set).sort();
      });

    // START EDITING B2 IN LIGHT MODE -- ALREADY-WORKING BASELINE

    await editorPage.keyboard.press('F2');
    const lightColors = await ceColors();
    // Pre-existing, unrelated limitation: the editor shows a plain white
    // background, not the actual gradient -- confirmed here as the baseline
    // this test builds on, not something this fix changes.
    expect(lightColors).toContain('255,255,255');
    // Automatic text renders black against that white background -- readable.
    expect(lightColors).toContain('0,0,0');
    await editorPage.keyboard.press('Escape');

    // SWITCH TO DARK MODE, START EDITING B2 AGAIN

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));
    await editorApi(editorPage, (api) => api.asc_findCell('B2'));
    await editorPage.keyboard.press('F2');

    const darkColors = await ceColors();
    // The editor's fallback background is cells.defaultState.background's
    // dark-mode value (#262626 = 38,38,38) -- confirms the fallback is in
    // effect, same as the no-fill case already covered by cell-colors.spec.ts.
    expect(darkColors).toContain('38,38,38');
    // Before the fix: automatic text stayed literal black (0,0,0) here,
    // unreadable against the 38,38,38 background. After the fix: the
    // gradient-fallback case is checked against that now-known background
    // like any other, so it gets corrected to a light color instead.
    expect(darkColors).not.toContain('0,0,0');
  });

  /*
   PATTERN-FILLED CELL, EDITED IN DARK MODE: TEXT MUST STAY READABLE

   Unlike a gradient fill, a genuine pattern fill (patternType other than
   None/Solid) makes Fill.prototype.bg() return non-null -- the pattern's
   foreground color -- and that's exactly what the editor paints as a flat
   background (background: bg || defaultState.background), raw, with no
   dark-mode correction of its own. Before the fix, the automatic-text-color
   decision only ever got a resolvedFallbackBg when bg was null, so a
   pattern fill fell into the grid path's "unknown contrast" exemption even
   though the actual painted color was fully known right there -- text
   rendered at its literal stored black regardless of how dark the
   pattern's foreground actually was.
  */
  test('editing a pattern-filled cell keeps automatic text readable against its foreground color', async ({ page }) => {
    const { editorPage } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    expect(await editorApi(editorPage, (api) => api.isDarkMode)).toBe(false);

    // B3: a value, and a dark, genuinely-patterned fill (DarkHorizontal,
    // not Solid) -- the shape that makes getSolidFill() null but bg()
    // non-null, which is the specific mismatch this fix targets.
    await editorApi(editorPage, (api) => {
      api.wb.getWorksheet().model.getRange3(2, 1, 2, 1).setValue('pattern');
      api.asc_findCell('B3');
    });

    await editorApi(editorPage, (api) => {
      const w = window as any;
      const fill = new w.Asc.asc_CFill2();
      const pattern = new w.Asc.asc_CPatternFill();
      pattern.asc_setType(w.Asc.c_oAscPatternType.DarkHorizontal);
      pattern.asc_setFgColor(new w.Asc.asc_CColor(30, 30, 90));
      pattern.asc_setBgColor(new w.Asc.asc_CColor(10, 10, 30));
      fill.asc_setPatternFill(pattern);
      api.asc_setCellFill(fill);
    });
    await expect.poll(() => cellFillRgb(editorPage, 2, 1)).not.toBeNull();

    const ceColors = () =>
      frameEval(editorPage, (win) => {
        const canvas = win.document.getElementById('ce-canvas') as HTMLCanvasElement;
        const ctx = canvas.getContext('2d')!;
        const img = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        const set = new Set<string>();
        for (let i = 0; i < img.length; i += 4) set.add(img[i] + ',' + img[i + 1] + ',' + img[i + 2]);
        return Array.from(set).sort();
      });

    // START EDITING B3 IN LIGHT MODE -- ALREADY-WORKING BASELINE

    await editorPage.keyboard.press('F2');
    const lightColors = await ceColors();
    // The editor paints the pattern's foreground color flat, raw -- not
    // corrected in either mode, confirmed here as the baseline.
    expect(lightColors).toContain('30,30,90');
    expect(lightColors).toContain('0,0,0');
    await editorPage.keyboard.press('Escape');

    // SWITCH TO DARK MODE, START EDITING B3 AGAIN

    await editorApi(editorPage, (api) => api.asc_setContentDarkMode(true));
    await editorApi(editorPage, (api) => api.asc_findCell('B3'));
    await editorPage.keyboard.press('F2');

    const darkColors = await ceColors();
    // Same foreground color as before -- the editor's background paint is
    // mode-independent, unaffected by this fix.
    expect(darkColors).toContain('30,30,90');
    // Before the fix: automatic text stayed literal black here too,
    // unreadable against this dark fill. After the fix: the pattern's
    // actual foreground color is checked like any other known background,
    // so it gets corrected to a light color instead.
    expect(darkColors).not.toContain('0,0,0');
  });
});
