// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi } from '../helpers';

// The built-in table and pivot table styles ship inside sdkjs as a zip, which
// the editor unpacks with the zip engine in fonts.wasm. A wasm build without
// deflate support left both lists empty (Euro-Office/DesktopEditors#311).
test.describe('Spreadsheet editor - table styles', () => {
  test('the built-in table and pivot table styles are offered', async ({ page }) => {
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.cell', /\.xlsx/);

    // Excel's 60 table styles (Light 1-21, Medium 1-28, Dark 1-11) and 84 pivot
    // table styles; a new workbook has no custom ones
    const tableStyles = await editorApi(
      editorPage,
      (api) =>
        api.asc_getTablePictures(api.asc_getCellInfo().asc_getFormatTableInfo(), false).length,
    );
    expect(tableStyles).toBe(60);
    const pivotStyles = await editorApi(
      editorPage,
      (api) =>
        api.asc_getTablePictures(api.asc_getCellInfo().asc_getFormatTableInfo(), true).length,
    );
    expect(pivotStyles).toBe(84);

    // The Home tab's "Format as table template" gallery shows them
    await frame.locator('#slot-btn-table-tpl button').first().click();
    await expect(frame.locator('#id-toolbar-menu-table-templates .item-template')).toHaveCount(60);
  });
});
