// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect } from '@playwright/test';
import {
  cleanUpStoredFiles,
  clickUserInUsersMenu,
  editorApi,
  openUsersMenu,
  openCoAuthorEditor,
  openStoredEditor,
  uniqueFileName,
  uploadStoredFile,
} from '../helpers';
import { USERS_MENU_JOIN_TEST_TIMEOUT, USERS_MENU_TEST_TIMEOUT } from '../../timeouts';

const DOCX = /\.docx/;

// Remit: the users menu in the header of a co-edited document. A click on a
// co-author moves the view to that co-author's cursor and shows the name label
// at the cursor, also for a co-author whose cursor did not move after the own
// editor opened.

const createdFiles: string[] = [];

test.describe('Document editor - users menu', { tag: ['@document', '@regression'] }, () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  test("a click on a co-author shows the co-author's cursor", async ({ page, browser }) => {
    // So that a loaded server reports the slow step instead of a generic test timeout.
    test.setTimeout(USERS_MENU_TEST_TIMEOUT);
    const fileName = await uploadStoredFile(page, uniqueFileName('users-menu', 'docx'));
    createdFiles.push(fileName);

    // John Smith (uid-1) here, Mark Pottato (uid-2) in a second browser context.
    const { editorPage: john, frame } = await openStoredEditor(page, fileName, DOCX, 'uid-1');
    const { context, editorPage: mark } = await openCoAuthorEditor(
      browser,
      fileName,
      DOCX,
      'uid-2',
    );
    try {
      const markPage = await test.step('Mark moves his cursor to a later page', async () => {
        // Page breaks at the end: the cursor ends on a page John does not see,
        // whatever the length of the sample document. One break at a time: in
        // co-editing a change waits for its lock, and the editor refuses the
        // next change until then.
        await mark.keyboard.press('Control+End');
        await expect(async () => {
          if ((await editorApi(mark, (api) => api.getCurrentPage())) < 2) {
            await editorApi(mark, (api) => api.put_AddPageBreak());
          }
          expect(await editorApi(mark, (api) => api.getCurrentPage())).toBeGreaterThanOrEqual(2);
        }).toPass({ intervals: [1_000], timeout: 30_000 });
        const pageIndex: number = await editorApi(mark, (api) => api.getCurrentPage());
        // Positive control: John does not see Mark's page yet.
        expect(await editorApi(john, (api) => api.GetCurrentVisiblePages())).not.toContain(
          pageIndex,
        );
        return pageIndex;
      });

      await test.step("John clicks Mark in the users menu and sees Mark's cursor", async () => {
        const label = frame.locator('.username-tip', { hasText: 'Mark Pottato' });
        // Mark's typing shows his label for a moment. Wait until it is gone, so
        // that the label below comes from the click.
        await expect(label).toHaveCount(0);

        // A co-author in the menu looks clickable, and is highlighted under the
        // mouse as the items of the other menus are.
        const entry = await openUsersMenu(frame, 'Mark Pottato');
        // The whole item, with its gap, takes the click.
        for (const part of [entry, entry.locator('.user-name')]) {
          expect(await part.evaluate((e) => getComputedStyle(e).cursor)).toBe('pointer');
        }
        // The mouse is on the title of the menu, not on an item, before the hover.
        await frame.locator('#tlb-users-menu-descr').hover();
        const background = await entry.evaluate((e) => getComputedStyle(e).backgroundColor);
        await entry.hover();
        await expect
          .poll(() => entry.evaluate((e) => getComputedStyle(e).backgroundColor))
          .not.toBe(background);
        // The item takes the corner radius of the toolbar buttons of the theme, and has the
        // same gap on all sides of the user.
        const buttonRadius = await frame
          .locator('#id-toolbar-btn-bold')
          .first()
          .evaluate((e) => getComputedStyle(e).borderTopLeftRadius);
        // Positive control: the theme of the test rounds its buttons.
        expect(buttonRadius).not.toBe('0px');
        expect(await entry.evaluate((e) => getComputedStyle(e).borderTopLeftRadius)).toBe(
          buttonRadius,
        );
        const gap = await entry.evaluate((e) => {
          const style = getComputedStyle(e);
          return [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft];
        });
        expect(parseFloat(gap[3])).toBeGreaterThan(0);
        expect(gap).toEqual([gap[3], gap[3], gap[3], gap[3]]);

        // Mark's changes and cursor reach John a moment after the move: retry
        // the click until John sees Mark's page.
        await expect(async () => {
          await clickUserInUsersMenu(frame, 'Mark Pottato');
          await expect(label).toBeVisible({ timeout: 1_000 });
          expect(await editorApi(john, (api) => api.GetCurrentVisiblePages())).toContain(markPage);

          // The label, at Mark's cursor, stands in the middle half of the view.
          const view = await frame.locator('#editor_sdk').boundingBox();
          const tip = await label.boundingBox();
          expect(view && tip).toBeTruthy();
          expect(tip!.y).toBeGreaterThan(view!.y + view!.height * 0.25);
          expect(tip!.y).toBeLessThan(view!.y + view!.height * 0.75);
        }).toPass({ timeout: 30_000 });
      });
    } finally {
      await context.close();
    }
  });

  test('a co-author who opens the document later sees where the others are', async ({
    page,
    browser,
  }) => {
    // So that a loaded server reports the slow step instead of a generic test timeout.
    test.setTimeout(USERS_MENU_JOIN_TEST_TIMEOUT);
    const fileName = await uploadStoredFile(page, uniqueFileName('users-menu-join', 'docx'));
    createdFiles.push(fileName);

    // Adds page breaks at the end until the cursor of the editor is on page `atLeast` or later,
    // one at a time: in co-editing a change waits for its lock, and the editor refuses the next
    // change until then. Returns the page of the cursor.
    async function goToLaterPage(editor: typeof page, atLeast: number): Promise<number> {
      await editor.keyboard.press('Control+End');
      await expect(async () => {
        if ((await editorApi(editor, (api) => api.getCurrentPage())) < atLeast) {
          await editorApi(editor, (api) => api.put_AddPageBreak());
        }
        expect(await editorApi(editor, (api) => api.getCurrentPage())).toBeGreaterThanOrEqual(
          atLeast,
        );
      }).toPass({ intervals: [1_000], timeout: 30_000 });
      return editorApi(editor, (api) => api.getCurrentPage());
    }

    // John Smith (uid-1) opens the document and goes to a later page.
    const { editorPage: john } = await openStoredEditor(page, fileName, DOCX, 'uid-1');
    const johnPage = await goToLaterPage(john, 2);

    // Then Mark Pottato (uid-2) opens it. John's cursor does not move again.
    const {
      context,
      editorPage: mark,
      frame: markFrame,
    } = await openCoAuthorEditor(browser, fileName, DOCX, 'uid-2');
    const hamishOpen: { context?: typeof context } = {};
    try {
      // Positive control: Mark does not see John's page yet.
      expect(await editorApi(mark, (api) => api.GetCurrentVisiblePages())).not.toContain(johnPage);

      await test.step("Mark clicks John in the users menu and sees John's page", async () => {
        await expect(async () => {
          await clickUserInUsersMenu(markFrame, 'John Smith');
          expect(await editorApi(mark, (api) => api.GetCurrentVisiblePages())).toContain(johnPage);
        }).toPass({ timeout: 30_000 });
      });

      // Mark goes to a page after John's. His changes reached the server once John has them.
      const markPage = await goToLaterPage(mark, johnPage + 2);
      await expect
        .poll(() => editorApi(john, (api) => api.getCountPages()))
        .toBeGreaterThan(markPage);

      // Then Hamish Mitchell (uid-3) opens it. He may see the users of Group2, as
      // Mark. Mark's cursor does not move again, and Mark co-edits already, so
      // only a new send of his cursor tells Hamish where he is.
      const hamishEditor = await openCoAuthorEditor(browser, fileName, DOCX, 'uid-3');
      hamishOpen.context = hamishEditor.context;
      const { editorPage: hamish, frame: hamishFrame } = hamishEditor;
      // Positive control: Hamish does not see Mark's page yet.
      expect(await editorApi(hamish, (api) => api.GetCurrentVisiblePages())).not.toContain(
        markPage,
      );

      await test.step("Hamish clicks Mark in the users menu and sees Mark's page", async () => {
        await expect(async () => {
          await clickUserInUsersMenu(hamishFrame, 'Mark Pottato');
          expect(await editorApi(hamish, (api) => api.GetCurrentVisiblePages())).toContain(
            markPage,
          );
        }).toPass({ timeout: 30_000 });
      });
    } finally {
      await hamishOpen.context?.close();
      await context.close();
    }
  });
});
