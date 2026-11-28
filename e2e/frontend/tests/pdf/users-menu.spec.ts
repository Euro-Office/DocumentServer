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

const PDF = /\.pdf/;

// Remit: the users menu in the header of a co-edited PDF. A click on a
// co-author moves the view to what that co-author edits and shows the name
// label there. Only the path of a selected object is tested here, not the one
// of a text cursor.

/**
 * A PDF of `pageCount` pages with one line of text each. The sample PDF of the
 * server is a form, which opens in the document editor; a PDF without form
 * fields opens in the PDF editor.
 */
function plainPdf(pageCount: number): Buffer {
  const kids = Array.from({ length: pageCount }, (_, i) => `${4 + 2 * i} 0 R`).join(' ');
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    `<< /Type /Pages /Count ${pageCount} /Kids [${kids}] >>`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (let i = 0; i < pageCount; i++) {
    const text = `BT /F1 24 Tf 72 720 Td (Page ${i + 1}) Tj ET`;
    objects.push(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' +
        `/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + 2 * i} 0 R >>`,
    );
    objects.push(`<< /Length ${text.length} >>\nstream\n${text}\nendstream`);
  }
  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [];
  objects.forEach((body, i) => {
    offsets.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  pdf += offsets.map((offset) => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

const createdFiles: string[] = [];

test.describe('PDF editor - users menu', { tag: ['@pdf', '@regression'] }, () => {
  test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

  test('a click on a co-author shows what the co-author edits', async ({ page, browser }) => {
    // So that a loaded server reports the slow step instead of a generic test timeout.
    test.setTimeout(USERS_MENU_TEST_TIMEOUT);
    const fileName = await uploadStoredFile(page, uniqueFileName('users-menu', 'pdf'), plainPdf(4));
    createdFiles.push(fileName);

    // John Smith (uid-1) here, Mark Pottato (uid-2) in a second browser context.
    const { editorPage: john, frame } = await openStoredEditor(page, fileName, PDF, 'uid-1');
    const { context, editorPage: mark } = await openCoAuthorEditor(browser, fileName, PDF, 'uid-2');
    try {
      // The PDF editor starts in strict co-editing unless the user chose fast
      // (File > Advanced settings); only fast co-editing sends cursors.
      for (const editor of [john, mark]) {
        await editorApi(editor, (api) => api.asc_SetFastCollaborative(true));
      }

      await test.step('Mark adds a text annotation on the last page', async () => {
        await editorApi(mark, (api) => api.goToPage(3));
        await expect.poll(() => editorApi(mark, (api) => api.getCurrentPage())).toBe(3);
        // In co-editing the new annotation waits for its lock: retry until it is there.
        await expect(async () => {
          if (
            (await editorApi(mark, (api) => api.getPDFDoc().GetPageInfo(3).annots.length)) === 0
          ) {
            await editorApi(mark, (api) => api.AddFreeTextAnnot(0));
          }
          expect(await editorApi(mark, (api) => api.getPDFDoc().GetPageInfo(3).annots.length)).toBe(
            1,
          );
        }).toPass({ intervals: [1_000], timeout: 30_000 });

        // Positive control: John is on the first page.
        expect(await editorApi(john, (api) => api.getCurrentPage())).toBe(0);
      });

      await test.step('John clicks Mark in the users menu and sees his annotation', async () => {
        const label = frame.locator('.username-tip', { hasText: 'Mark Pottato' });
        // The new annotation is selected for Mark, and his selection reaches
        // John a moment later: retry the click.
        await expect(async () => {
          await clickUserInUsersMenu(frame, 'Mark Pottato');
          expect(await editorApi(john, (api) => api.getCurrentPage())).toBe(3);
          await expect(label).toBeVisible({ timeout: 1_000 });

          // The label stands in the middle half of the view.
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
});
