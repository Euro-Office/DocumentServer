// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect, type FrameLocator, type Page } from '@playwright/test';
import {
  FIXTURE_TEXT,
  type FixtureExt,
  cleanUpStoredFiles,
  openStoredEditor,
  storedFileRow,
  uniqueFileName,
  uploadFixtureFile,
} from './helpers';
import { EDITOR_CONTENT_READ } from '../timeouts';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

/**
 * The P1 "open an existing file" scenario, shared by the three open-*.spec.ts
 * files: an uploaded file is listed under its type, opens in the matching
 * editor, and shows the content it was uploaded with.
 *
 * The fixture is the point. Every other spec reads back content the app itself
 * wrote, so a fault that mangled content consistently would sit on both sides
 * of the comparison and stay invisible. These compare against
 * `frontend/fixtures/fixture.{docx,xlsx,pptx}`, which the server never touched.
 *
 * Out of scope (P2/P3): formatting, images, multi-page and multi-sheet
 * fixtures, malformed files, and the PDF form editor.
 */
export function describeOpeningStoredFixture(type: {
  /** Editor name for the describe title, e.g. `Spreadsheet editor`. */
  label: string;
  /** Same thing mid-sentence, e.g. `spreadsheet` in "open a spreadsheet". */
  noun: string;
  /** Fixture extension, which also picks the expected text. */
  ext: FixtureExt;
  /** Row class the file list marks this type with: word, cell, slide. */
  rowClass: string;
  /** Area tag: @document, @spreadsheet or @presentation. */
  tag: string;
  /** Matches the editor tab's URL. */
  urlExt: RegExp;
  /** Matches the editor iframe's src: the app that actually loaded. */
  editorApp: RegExp;
  /** Read the whole of the fixture's content. Polled, so it must be repeatable. */
  readContent: (editorPage: Page, frame: FrameLocator) => Promise<string>;
}) {
  // Removed once the spec is done, so a run against a long-lived server
  // (E2E_BASE_URL) does not accumulate one per run. afterAll, not afterEach —
  // see cleanUpStoredFiles.
  const uploadedFiles: string[] = [];

  // Area tag first, then @regression, as the README's --grep examples assume.
  test.describe(
    `${type.label} - opening an existing file`,
    { tag: [type.tag, '@regression'] },
    () => {
      test.afterAll(({ browser }) => cleanUpStoredFiles(browser, uploadedFiles));

      test(`open an uploaded ${type.noun} and read its content`, async ({ page }) => {
        await page.goto('/example/');
        // A name we chose ourselves, so no parallel worker can be handed it.
        const fileName = await uploadFixtureFile(page, type.ext, uniqueFileName('open', type.ext));
        uploadedFiles.push(fileName);

        await test.step(`the uploaded ${type.noun} is listed as a ${type.noun}`, async () => {
          await page.goto('/example/');
          const row = storedFileRow(page, fileName);
          await expect(row).toHaveCount(1);
          // The row class is the server's own reading of the type.
          await expect(row.locator(`a.stored-edit.${type.rowClass}`)).toHaveCount(1);
        });

        const { editorPage, frame } = await openStoredEditor(page, fileName, type.urlExt);

        await test.step(`it opens in the ${type.noun} editor`, async () => {
          // Parsed, not matched as a URL pattern: generated names contain regex
          // metacharacters.
          expect(new URL(editorPage.url()).searchParams.get('fileName')).toBe(fileName);
          // The URL extension would not catch the wrong editor being handed the
          // file; the iframe src is the app that actually loaded.
          await expect(editorPage.locator(EDITOR_IFRAME)).toHaveAttribute('src', type.editorApp);
        });

        await test.step('the content is what the fixture holds', async () => {
          // toPass: the editor can rebuild its iframe shortly after opening, so
          // focus, select and read are retried as a unit.
          await expect(async () => {
            expect(await type.readContent(editorPage, frame)).toBe(FIXTURE_TEXT[type.ext]);
          }).toPass({ timeout: EDITOR_CONTENT_READ });
        });
      });
    },
  );
}
