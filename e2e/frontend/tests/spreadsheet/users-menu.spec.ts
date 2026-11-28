// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import {
  cleanUpStoredFiles,
  clickUserInUsersMenu,
  editorApi,
  openCoAuthorEditor,
  openStoredEditor,
  uniqueFileName,
  uploadStoredFile,
} from '../helpers';
import { USERS_MENU_TEST_TIMEOUT } from '../../timeouts';

const XLSX = /\.xlsx/;

// Remit: the users menu in the header of a co-edited spreadsheet. A click on a
// co-author goes to the sheet of that co-author's selection, scrolls it into
// view and shows the name label at it.
//
// The file is uploaded under a unique name, not created: the create-new route
// can hand the same name to a parallel worker, and its editors would then
// co-edit this spreadsheet too.

const createdFiles: string[] = [];

test.describe('Spreadsheet editor - users menu', { tag: ['@spreadsheet', '@regression'] }, () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  test("a click on a co-author shows the co-author's selection", async ({ page, browser }) => {
    // So that a loaded server reports the slow step instead of a generic test timeout.
    test.setTimeout(USERS_MENU_TEST_TIMEOUT);
    const fileName = await uploadStoredFile(page, uniqueFileName('users-menu', 'xlsx'));
    createdFiles.push(fileName);

    // John Smith (uid-1) here, Mark Pottato (uid-2) in a second browser context.
    const { editorPage: john, frame } = await openStoredEditor(page, fileName, XLSX, 'uid-1');
    const { context, editorPage: mark } = await openCoAuthorEditor(
      browser,
      fileName,
      XLSX,
      'uid-2',
    );
    try {
      await test.step('Mark selects a cell far away on a second sheet', async () => {
        // One add, then wait until John has the sheet: the change reached the
        // server, so no late add can move the sheets after this.
        await editorApi(mark, (api) => api.asc_addWorksheet('Mark'));
        await expect.poll(() => editorApi(john, (api) => api.asc_getWorksheetsCount())).toBe(2);
        await editorApi(mark, (api) => api.asc_showWorksheet(1));
        await editorApi(mark, (api) => api.asc_findCell('AB300'));

        // Positive control: John has the second sheet, but looks at the first.
        expect(await editorApi(john, (api) => api.asc_getActiveWorksheetIndex())).toBe(0);
      });

      await test.step("John clicks Mark in the users menu and sees Mark's selection", async () => {
        const label = frame.locator('.username-tip', { hasText: 'Mark Pottato' });

        // Mark's selection reaches John a moment after the change, and an
        // earlier selection of Mark can come first: retry the click until John
        // sees Mark's cell.
        await expect(async () => {
          await clickUserInUsersMenu(frame, 'Mark Pottato');
          expect(await editorApi(john, (api) => api.asc_getActiveWorksheetIndex())).toBe(1);
          await expect(label).toBeVisible({ timeout: 1_000 });

          // Mark's cell AB300 (column 27, row 299) is in the cells John sees.
          // The label is no proof of this: for a cell out of view, the editor
          // draws it at the edge of the view. The API has no getter for the
          // visible cells, so this reads the worksheet view.
          const visible = await editorApi(john, (api) => {
            const range = api.wb.getWorksheet().visibleRange;
            return { c1: range.c1, c2: range.c2, r1: range.r1, r2: range.r2 };
          });
          expect(visible.c1).toBeLessThanOrEqual(27);
          expect(visible.c2).toBeGreaterThanOrEqual(27);
          expect(visible.r1).toBeLessThanOrEqual(299);
          expect(visible.r2).toBeGreaterThanOrEqual(299);
        }).toPass({ timeout: 30_000 });
      });
    } finally {
      await context.close();
    }
  });
});
