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

const PPTX = /\.pptx/;

// Remit: the users menu in the header of a co-edited presentation. A click on a
// co-author goes to the slide with that co-author's text cursor. In the slide
// master view there is no slide to go to, and the view does not change.
//
// The file is uploaded under a unique name, not created: the create-new route
// can hand the same name to a parallel worker, and its editors would then
// co-edit this presentation too.

const createdFiles: string[] = [];

test.describe('Presentation editor - users menu', { tag: ['@presentation', '@regression'] }, () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  test("a click on a co-author shows the co-author's slide", async ({ page, browser }) => {
    // So that a loaded server reports the slow step instead of a generic test timeout.
    test.setTimeout(USERS_MENU_TEST_TIMEOUT);
    const fileName = await uploadStoredFile(page, uniqueFileName('users-menu', 'pptx'));
    createdFiles.push(fileName);

    // John Smith (uid-1) here, Mark Pottato (uid-2) in a second browser context.
    const { editorPage: john, frame } = await openStoredEditor(page, fileName, PPTX, 'uid-1');
    const { context, editorPage: mark } = await openCoAuthorEditor(
      browser,
      fileName,
      PPTX,
      'uid-2',
    );
    try {
      const markSlide = await test.step('Mark types on a new slide at the end', async () => {
        const slides: number = await editorApi(john, (api) => api.getCountPages());
        // A new slide after the last one of the sample, with empty placeholders
        // for text. Wait until John has it: the change then reached the server.
        await editorApi(mark, (api) => api.goToPage(api.getCountPages() - 1));
        await editorApi(mark, (api) => api.AddSlide());
        await expect.poll(() => editorApi(john, (api) => api.getCountPages())).toBe(slides + 1);
        await editorApi(mark, (api) => api.goToPage(api.getCountPages() - 1));
        await expect.poll(() => editorApi(mark, (api) => api.getCurrentPage())).toBe(slides);

        // The text cursor of Mark, in the first shape of his slide.
        await mark.keyboard.press('Escape');
        await mark.keyboard.press('Escape');
        await mark.keyboard.press('Tab');
        await mark.keyboard.press('Enter');
        await mark.keyboard.type('Mark');

        // Positive control: John is on the first slide.
        expect(await editorApi(john, (api) => api.getCurrentPage())).toBe(0);
        return slides;
      });

      await test.step("John clicks Mark in the users menu and sees Mark's slide", async () => {
        // Mark's cursor reaches John a moment after the typing: retry the click.
        await expect(async () => {
          await clickUserInUsersMenu(frame, 'Mark Pottato');
          expect(await editorApi(john, (api) => api.getCurrentPage())).toBe(markSlide);
        }).toPass({ timeout: 30_000 });
      });

      await test.step('In the slide master view, a jump to Mark changes nothing', async () => {
        // The view lists the masters and layouts, so a slide number names one of them.
        await editorApi(john, (api) => {
          const w = window as unknown as {
            Asc: { c_oAscPresentationViewMode: { masterSlide: number } };
          };
          api.asc_changePresentationViewMode(w.Asc.c_oAscPresentationViewMode.masterSlide);
          api.goToPage(0);
        });
        await expect.poll(() => editorApi(john, (api) => api.asc_IsMasterMode())).toBe(true);
        const result = await editorApi(john, (api) => {
          // Mark is the only co-author whose cursor John knows.
          const w = window as unknown as {
            AscCommon: { CollaborativeEditing: { m_aForeignCursors: Record<string, unknown> } };
          };
          const ids = Object.keys(w.AscCommon.CollaborativeEditing.m_aForeignCursors);
          return {
            ids: ids.length,
            moved: api.asc_moveToUserCursor(ids[0]),
            page: api.getCurrentPage(),
          };
        });
        // Positive control: John knows Mark's cursor, as for the jump above.
        expect(result).toEqual({ ids: 1, moved: false, page: 0 });
      });
    } finally {
      await context.close();
    }
  });
});
