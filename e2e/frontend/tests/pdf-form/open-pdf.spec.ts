// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { expect } from '@playwright/test';
import { editorApi, readPdfPageText } from '../helpers';
import { describeOpeningStoredFixture } from '../open-stored-fixture.suite';
import { EDITOR_CONTENT_READ } from '../../timeouts';

// Remit and the reasoning behind it: open-stored-fixture.suite.ts. Named
// open-pdf, not open-pdf-form like its neighbours: the fixture is a plain PDF
// with no form fields.
describeOpeningStoredFixture({
  label: 'PDF editor',
  noun: 'PDF',
  ext: 'pdf',
  tag: '@pdf',
  rowClass: 'pdf',
  urlExt: /\.pdf/,
  // No bundle to match on, so the editor is asked instead. The other three
  // editors answer false. Polled like the content read, and for the same
  // reason: the editor can rebuild its iframe shortly after opening, and
  // editorApi throws while window.Asc.editor is missing. The message is
  // returned rather than swallowed, so a failure says which of the two it was.
  assertEditorApp: async (editorPage) => {
    await expect
      .poll(
        () =>
          editorApi<boolean>(editorPage, (api) => api.isPdfEditor()).catch(
            (e: Error) => `error: ${e.message}`,
          ),
        { timeout: EDITOR_CONTENT_READ },
      )
      .toBe(true);
  },
  // The fixture is one page holding one line of text.
  readContent: readPdfPageText,
});
