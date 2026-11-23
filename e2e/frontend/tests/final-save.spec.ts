// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect, type FrameLocator, type Page } from '@playwright/test';
import {
  FIXTURE_TEXT,
  type FixtureExt,
  cleanUpStoredFiles,
  downloadStoredFile,
  focusShape,
  openStoredEditor,
  readDocumentText,
  readShape,
  reopenEditor,
  saveAndReopen,
  saveAndWaitForServer,
  selectCell,
  selectedCellText,
  sha256,
  shortFileName,
  uploadFixtureFile,
  waitForStoredFileChange,
} from './helpers';
import { EDITOR_CONTENT_READ, FINAL_SAVE_TEST_TIMEOUT } from '../timeouts';

// The final save is what docservice does after the last editor disconnects. The
// save and edit specs prove one document saved once; these tests cover closing
// several editors at once, reopening before the save has finished, and a second
// tab that stays open. Each test uploads its own fixture under a short unique
// name and opens only that file. The browser only sees the end result, so these
// catch lost, mixed-up or duplicated content, not callbacks to the integrator.

const DOCX = /\.docx/;
// Typing in a document goes after the fixture's text. In a spreadsheet it goes
// to B1 and in a presentation to the subtitle, which the fixtures leave empty.
const BASE = FIXTURE_TEXT.docx;

const createdFiles: string[] = [];

type OpenEditor = { editorPage: Page; frame: FrameLocator };

/** Upload a fixture document under a short name and open it in an editor. */
async function openOwnDocument(page: Page, label: string) {
  const fileName = await uploadFixtureFile(page, 'docx', shortFileName(label, 'docx'));
  createdFiles.push(fileName);
  return openStoredEditor(page, fileName, DOCX);
}

/** Put the caret after the existing text and type. */
async function typeAtEnd(editorPage: Page, text: string) {
  await editorPage.keyboard.press('Control+End');
  await editorPage.keyboard.type(text);
}

/** The editor can rebuild its iframe after opening, so click, select and read
 * are retried together as one unit. */
async function expectDocumentText({ editorPage, frame }: OpenEditor, expected: string) {
  await expect(async () => {
    await frame.locator('#editor_sdk').click();
    expect(await readDocumentText(editorPage)).toBe(expected);
  }).toPass({ timeout: EDITOR_CONTENT_READ });
}

// How to put text into, and read it back from, each editor's fixture.
interface Driver {
  ext: FixtureExt;
  edit: (editorPage: Page, frame: FrameLocator, text: string) => Promise<void>;
  read: (editorPage: Page, frame: FrameLocator) => Promise<string>;
  expected: (typed: string) => string;
}

const DRIVERS: Driver[] = [
  {
    ext: 'docx',
    edit: async (editorPage, _frame, text) => {
      await typeAtEnd(editorPage, ` ${text}`);
      expect(await readDocumentText(editorPage)).toBe(`${BASE} ${text}`);
    },
    read: (editorPage) => readDocumentText(editorPage),
    expected: (typed) => `${BASE} ${typed}`,
  },
  {
    ext: 'xlsx',
    edit: async (editorPage, frame, text) => {
      // Ctrl+Home puts the grid in focus at A1, which holds the fixture's text;
      // one step right is the empty B1.
      await editorPage.keyboard.press('Control+Home');
      await editorPage.keyboard.press('ArrowRight');
      await editorPage.keyboard.type(text);
      await editorPage.keyboard.press('Enter');
      await selectCell(frame, 'B1');
      await expect.poll(() => selectedCellText(editorPage)).toBe(text);
    },
    read: async (editorPage, frame) => {
      await selectCell(frame, 'B1');
      return String(await selectedCellText(editorPage));
    },
    expected: (typed) => typed,
  },
  {
    ext: 'pptx',
    edit: async (editorPage, _frame, text) => {
      // Shape 2 is the subtitle placeholder; the fixture's text is in the title.
      await focusShape(editorPage, 2);
      await editorPage.keyboard.press('Enter');
      await editorPage.keyboard.type(text);
      await editorPage.keyboard.press('Escape');
      await editorPage.keyboard.press('Escape');
      expect(await readShape(editorPage, 2)).toBe(text);
      await editorPage.keyboard.press('Escape');
      await editorPage.keyboard.press('Escape');
    },
    read: (editorPage) => readShape(editorPage, 2),
    expected: (typed) => typed,
  },
];

test.afterAll(({ browser }) => cleanUpStoredFiles(browser, createdFiles));

// Across editors, so no single area tag; see stored-file-delete.suite.ts.
test.describe('Final save - editors closed together', { tag: ['@regression'] }, () => {
  test('a document, a spreadsheet and a presentation keep their own text', async ({ page }) => {
    test.setTimeout(FINAL_SAVE_TEST_TIMEOUT);

    const open: { driver: Driver; text: string; editorPage: Page; before: Buffer }[] = [];
    for (const driver of DRIVERS) {
      const fileName = await uploadFixtureFile(
        page,
        driver.ext,
        shortFileName(`final-save-${driver.ext}`, driver.ext),
      );
      createdFiles.push(fileName);
      const { editorPage, frame } = await openStoredEditor(
        page,
        fileName,
        new RegExp(`\\.${driver.ext}`),
      );
      const before = await downloadStoredFile(page, editorPage.url());
      const text = `Euro-Office final save ${driver.ext}`;
      await driver.edit(editorPage, frame, text);
      await saveAndWaitForServer(editorPage);
      open.push({ driver, text, editorPage, before });
    }

    // saveAndReopen calls close() before its first await, and this relies on it:
    // the three editors disconnect together, so docservice converts all three at once.
    const reopened = await test.step('save and reopen all three', () =>
      Promise.all(open.map((d) => saveAndReopen(page, d.editorPage, d.before))));

    await test.step('each file holds only its own text', async () => {
      for (const [i, doc] of reopened.entries()) {
        await expect(async () => {
          await doc.frame.locator('#editor_sdk').click();
          expect(await open[i].driver.read(doc.editorPage, doc.frame)).toBe(
            open[i].driver.expected(open[i].text),
          );
        }).toPass({ timeout: EDITOR_CONTENT_READ });
      }
    });
  });
});

test.describe('Document editor - final save', { tag: ['@document', '@regression'] }, () => {
  test('reopened before the save keeps its edit once', async ({ page }) => {
    test.setTimeout(FINAL_SAVE_TEST_TIMEOUT);
    const TEXT = ' reopened early';
    const { editorPage } = await openOwnDocument(page, 'final-save-early');
    const editorUrl = editorPage.url();
    const before = await downloadStoredFile(page, editorUrl);

    await test.step('type and close the editor', async () => {
      await typeAtEnd(editorPage, TEXT);
      expect(await readDocumentText(editorPage)).toBe(BASE + TEXT);
      await saveAndWaitForServer(editorPage);
      await editorPage.close();
    });

    // Not waiting for storage: this reopens within the delay docservice allows
    // before it saves, so the editor attaches to the document the first one left.
    const second = await test.step('reopen straight away', () => reopenEditor(page, editorUrl));

    await test.step('the edit is there exactly once', () =>
      expectDocumentText(second, BASE + TEXT));

    await test.step('the save still reaches storage and survives another reopen', async () => {
      const third = await saveAndReopen(page, second.editorPage, before);
      await expectDocumentText(third, BASE + TEXT);
    });
  });

  test('is saved only after the last of two tabs leaves', async ({ page }) => {
    test.setTimeout(FINAL_SAVE_TEST_TIMEOUT);
    const TEXT_A = ' first tab';
    const TEXT_B = ' second tab';
    const first = await openOwnDocument(page, 'final-save-two-tabs');
    const editorUrl = first.editorPage.url();
    const before = await downloadStoredFile(page, editorUrl);

    // Same browser context, so the same user: the example app does not cope with
    // two different users on one document leaving one after the other.
    const second = await reopenEditor(page, editorUrl);

    await test.step('an edit in the first tab reaches the second', async () => {
      await typeAtEnd(first.editorPage, TEXT_A);
      await expectDocumentText(second, BASE + TEXT_A);
    });

    await test.step('the first tab leaves, the second keeps editing', async () => {
      await saveAndWaitForServer(first.editorPage);
      await first.editorPage.close();

      await second.frame.locator('#editor_sdk').click();
      await typeAtEnd(second.editorPage, TEXT_B);
      expect(await readDocumentText(second.editorPage)).toBe(BASE + TEXT_A + TEXT_B);
    });

    await test.step('the last tab leaves and both edits are saved', async () => {
      await saveAndWaitForServer(second.editorPage);
      // The first tab leaving must not have saved the document: storage only
      // changes once the last editor is gone.
      expect(sha256(await downloadStoredFile(page, editorUrl))).toBe(sha256(before));
      await second.editorPage.close();
      await waitForStoredFileChange(page, editorUrl, before);

      await expectDocumentText(await reopenEditor(page, editorUrl), BASE + TEXT_A + TEXT_B);
    });
  });
});
