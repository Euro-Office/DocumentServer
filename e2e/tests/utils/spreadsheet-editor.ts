import { Page } from '@playwright/test';
import { frameEval } from '../helpers';

// row/col are passed through frameEval's `args` (real Playwright-serialized
// values, arrived as genuine function parameters), not baked into a string --
// see helpers.ts's frameEval for how that avoids the closure-doesn't-survive-
// serialization problem without writing code as text.
export function cellFillRgb(editorPage: Page, row: number, col: number) {
  return frameEval(editorPage, (win, row: number, col: number) => {
    const fill = win.Asc.editor.wb.getWorksheet().model.getRange3(row, col, row, col).getFill();
    return fill && fill.patternFill && fill.patternFill.fgColor ? fill.patternFill.fgColor.rgb : null;
  }, [row, col]);
}

export function cellFontRgb(editorPage: Page, row: number, col: number) {
  return frameEval(editorPage, (win, row: number, col: number) => {
    const color = win.Asc.editor.wb.getWorksheet().model.getRange3(row, col, row, col).getFont().getColor();
    return color ? color.rgb : null;
  }, [row, col]);
}

// Samples the darkest/lightest pixel within a cell's rendered rect, rather
// than a single fixed coordinate -- robust to exact glyph/font-metric
// position, which a one-shot pixel guess is not.
//
// The scanned region is inset from each edge of the cell's rect by the
// cell's actual border width (read from the model via getBorderFull(),
// which reports 0/1/2/3px for None/Thin/Medium/Thick -- WorkbookElems.js's
// BorderProp.setStyle), or 1px if the cell has no explicit border on that
// side -- the default gridline is hardcoded to exactly 1px in
// WorksheetView.prototype._drawGrid regardless of any cell's own border.
// This isn't a guessed margin: confirmed via browser-loop against two real
// contamination modes at the raw rect boundary -- (1) an unfilled cell's
// own last row/column can literally *be* the gridline pixel, and (2) two
// vertically adjacent cells' paint rects can meet such that the shared
// boundary row reads as the *next* cell's fill rather than this one's --
// and the derived inset value (1px, for a cell with no explicit border)
// clears both exactly as well as an earlier, uninvestigated flat guess did.
// A scenario that specifically wants to measure the gridline/border color
// itself (see TASKS/5-dark-theme-canvas-background/5.8-e2e-dark-mode-coverage,
// scenario 2) needs the opposite: sample at/near the edge on purpose, not
// inset from it.
export function sampleCellPixels(editorPage: Page, row: number, col: number) {
  return frameEval(editorPage, (win, row: number, col: number) => {
    const ws = win.Asc.editor.wb.getWorksheet();
    const range = ws.model.getRange3(row, col, row, col);
    const border = range.getBorderFull();
    const inset = Math.max(1, border.t.w, border.r.w, border.b.w, border.l.w);
    const rect = ws.getCellCoord(col, row);
    const x = Math.round(rect._x) + inset;
    const y = Math.round(rect._y) + inset;
    const w = Math.round(rect._width) - 2 * inset;
    const h = Math.round(rect._height) - 2 * inset;
    const ctx = win.document.getElementById('ws-canvas').getContext('2d');
    const img = ctx.getImageData(x, y, w, h).data;
    let darkest = [255, 255, 255];
    let darkestLum = Infinity;
    let lightest = [0, 0, 0];
    let lightestLum = -Infinity;
    for (let i = 0; i < img.length; i += 4) {
      const lum = img[i] + img[i + 1] + img[i + 2];
      if (lum < darkestLum) { darkestLum = lum; darkest = [img[i], img[i + 1], img[i + 2]]; }
      if (lum > lightestLum) { lightestLum = lum; lightest = [img[i], img[i + 1], img[i + 2]]; }
    }
    return { darkest, lightest };
  }, [row, col]);
}

// Samples the single pixel row a cell's own bottom border renders at.
// Confirmed via browser-loop, not assumed: for a Thin border (the only
// width tested so far), the border occupies exactly one row at
// `rect._y + rect._height - 1`, with plain background on every row above
// and below it -- no inset/tolerance needed the way sampleCellPixels needs
// for fill/text, since there's no adjacent-cell-bleed risk at this specific
// coordinate for a bottom border between two unfilled cells. Only the
// bottom side is implemented -- top/left/right were not verified to sit at
// the equivalent offset (the fill/gridline investigation for
// sampleCellPixels found left/top edges behave differently from
// right/bottom ones, so don't assume symmetry without checking each side
// live first).
export function bottomBorderPixel(editorPage: Page, row: number, col: number) {
  return frameEval(editorPage, (win, row: number, col: number) => {
    const ws = win.Asc.editor.wb.getWorksheet();
    const rect = ws.getCellCoord(col, row);
    const x = Math.round(rect._x) + 5;
    const y = Math.round(rect._y) + Math.round(rect._height) - 1;
    const ctx = win.document.getElementById('ws-canvas').getContext('2d');
    const d = ctx.getImageData(x, y, 1, 1).data;
    return [d[0], d[1], d[2]];
  }, [row, col]);
}

// Same darkest/lightest-in-rect technique as sampleCellPixels, but across a
// horizontally merged cell's full combined width. getCellCoord itself is not
// merge-aware -- merging via asc_mergeCells changes the model (confirmed via
// browser-loop: ws.model.getMergedByCell reports the merged bbox correctly)
// but getCellCoord(col1, row) still returns only the anchor column's own
// (unmerged) width. The combined rect is computed manually: left edge from
// the anchor cell (col1), right edge from the last cell in the merge
// (col2)'s own right edge -- confirmed live to span the full merged area
// with no leftover internal column-boundary artifact. Only horizontal
// (same-row, multi-column) merges are implemented/verified; vertical merges
// were not tested.
export function sampleMergedCellPixels(editorPage: Page, row: number, col1: number, col2: number) {
  return frameEval(editorPage, (win, row: number, col1: number, col2: number) => {
    const ws = win.Asc.editor.wb.getWorksheet();
    const anchorBorder = ws.model.getRange3(row, col1, row, col1).getBorderFull();
    const inset = Math.max(1, anchorBorder.t.w, anchorBorder.r.w, anchorBorder.b.w, anchorBorder.l.w);
    const rectStart = ws.getCellCoord(col1, row);
    const rectEnd = ws.getCellCoord(col2, row);
    const x = Math.round(rectStart._x) + inset;
    const y = Math.round(rectStart._y) + inset;
    const w = Math.round(rectEnd._x) + Math.round(rectEnd._width) - Math.round(rectStart._x) - 2 * inset;
    const h = Math.round(rectStart._height) - 2 * inset;
    const ctx = win.document.getElementById('ws-canvas').getContext('2d');
    const img = ctx.getImageData(x, y, w, h).data;
    let darkest = [255, 255, 255];
    let darkestLum = Infinity;
    let lightest = [0, 0, 0];
    let lightestLum = -Infinity;
    for (let i = 0; i < img.length; i += 4) {
      const lum = img[i] + img[i + 1] + img[i + 2];
      if (lum < darkestLum) { darkestLum = lum; darkest = [img[i], img[i + 1], img[i + 2]]; }
      if (lum > lightestLum) { lightestLum = lum; lightest = [img[i], img[i + 1], img[i + 2]]; }
    }
    return { darkest, lightest };
  }, [row, col1, col2]);
}

// Draws the column-resize drag guide (WorksheetView.prototype.drawColumnGuides
// -- the dotted vertical line shown while dragging a column border) directly,
// without simulating a real mouse drag, and samples its color. Confirmed via
// browser-loop: the guide draws to the *overlay* canvas (`ws-canvas-overlay`,
// this.overlayCtx in the source), not the main `ws-canvas` every other helper
// in this file samples -- a different canvas entirely. It's a 1px-wide
// dotted vertical line at `colLeft - 1`, dots landing on every odd row (0,
// 2, 4... are transparent gaps) -- scans a tall-enough strip to guarantee
// catching an "on" dot rather than gambling on one row. Calling
// drawColumnGuides also repaints the current selection's marquee as a side
// effect (WorksheetView.prototype._drawSelection, called internally right
// before the guide itself) -- confirmed this can contaminate the scan if the
// active cell's marquee happens to overlap the sampled column, so the caller
// should select a cell in a visibly different column first.
export function resizeColumnGuideColor(editorPage: Page, col: number) {
  return frameEval(editorPage, (win, col: number) => {
    const ws = win.Asc.editor.wb.getWorksheet();
    const colLeft = ws._getColLeft(col);
    ws.drawColumnGuides(col, colLeft, 0, 0);
    const ctx = win.document.getElementById('ws-canvas-overlay').getContext('2d');
    const img = ctx.getImageData(Math.round(colLeft) - 1, 0, 1, 30).data;
    for (let i = 0; i < img.length; i += 4) {
      if (img[i + 3] > 0) return [img[i], img[i + 1], img[i + 2]];
    }
    return null;
  }, [col]);
}
