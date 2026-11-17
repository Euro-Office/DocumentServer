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

// Defined here rather than imported, as in the three create-* specs: the
// iframe is the thing under test in the "right editor" assertion below, so it
// stays visible in the file that asserts on it.
const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

/**
 * The P1 "open an existing file" scenario, shared by the three open-*.spec.ts
 * files: a file that arrived on the server from outside is listed, opens in the
 * editor that matches its type, and shows the content it was uploaded with.
 *
 * This is the other half of the stored-file route (`?fileName=`) from
 * edit-*.spec.ts. Those create an *empty* file through the app's own create-new
 * route and then type into it, so they never exercise reading real content off
 * a file the app did not write. Here the file comes from
 * `frontend/fixtures/fixture.{docx,xlsx,pptx}` — raw OOXML built by
 * `make-fixtures.py`, holding one known string each — so the content the editor
 * shows can be compared against a value no part of the server produced. A fault
 * that corrupted every save would leave the edit-* specs green and fail these.
 *
 * Out of scope (P2/P3): formatting, images, multi-page and multi-sheet
 * fixtures, malformed files, and the PDF form editor — the acceptance criteria
 * name docx, xlsx and pptx.
 *
 * Uploads under a generated unique name rather than using the create-new route,
 * which hands out the lowest free name and can therefore collide with a spec in
 * a parallel worker. Nothing here asserts on the list as a whole, only on the
 * row it created: the store is server-side and shared by every spec.
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
  /** Area tag for this editor: @document, @spreadsheet or @presentation. */
  tag: string;
  /** Matches the editor tab's URL, confirming the file kept its type. */
  urlExt: RegExp;
  /** Matches the editor iframe's src: the app that actually loaded. */
  editorApp: RegExp;
  /**
   * Read back the whole of the fixture's content, as that editor exposes it.
   * Called once the editor is ready; may press keys. Polled by the caller, so
   * it must tolerate being run more than once.
   */
  readContent: (editorPage: Page, frame: FrameLocator) => Promise<string>;
}) {
  // Files the test uploaded, removed once the spec is done so a run against a
  // long-lived server (E2E_BASE_URL) does not accumulate one per run. afterAll
  // rather than afterEach — see cleanUpStoredFiles.
  const uploadedFiles: string[] = [];

  test.describe(`${type.label} - opening an existing file`, { tag: ['@regression'] }, () => {
    test.afterAll(({ browser }) => cleanUpStoredFiles(browser, uploadedFiles));

    // Not @smoke: the smoke set is capped at one or two tests per area and the
    // create-new tests already hold those slots, and this is a multi-step flow
    // (upload, list, open, read) rather than the quick load check smoke wants.
    // eslint-disable-next-line playwright/valid-test-tags -- tag is passed in by each caller
    test(
      `open an uploaded ${type.noun} and read its content`,
      { tag: type.tag },
      async ({ page }) => {
        await page.goto('/example/');
        const fileName = await uploadFixtureFile(page, type.ext, uniqueFileName('open', type.ext));
        uploadedFiles.push(fileName);

        await test.step(`the uploaded ${type.noun} is listed as a ${type.noun}`, async () => {
          await page.goto('/example/');
          const row = storedFileRow(page, fileName);
          await expect(row).toHaveCount(1);
          // The row class is how the list reports the type it detected, so this
          // is the server's own reading of the file we sent.
          await expect(row.locator(`a.stored-edit.${type.rowClass}`)).toHaveCount(1);
        });

        const { editorPage, frame } = await openStoredEditor(page, fileName, type.urlExt);

        await test.step(`it opens in the ${type.noun} editor`, async () => {
          // Compared as a parsed parameter rather than a URL pattern: generated
          // names contain regex metacharacters.
          expect(new URL(editorPage.url()).searchParams.get('fileName')).toBe(fileName);
          // The URL extension alone would not catch the wrong editor being
          // handed the file; the iframe src is the app that actually loaded.
          await expect(editorPage.locator(EDITOR_IFRAME)).toHaveAttribute('src', type.editorApp);
        });

        await test.step('the content is what the fixture holds', async () => {
          // toPass, not a bare assertion: the editor can rebuild its iframe
          // shortly after opening, so the focus-select-read sequence is retried
          // as a unit. Equality, not a substring — the fixture's string is the
          // whole of its content, so a truncated or padded read must fail.
          await expect(async () => {
            expect(await type.readContent(editorPage, frame)).toBe(FIXTURE_TEXT[type.ext]);
          }).toPass({ timeout: 30_000 });
        });
      },
    );
  });
}
