// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { expect } from '@playwright/test';
import { editorApi, readPdfPageText } from '../helpers';
import { describeOpeningStoredFixture } from '../open-stored-fixture.suite';

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
  // editors answer false.
  assertEditorApp: async (editorPage) => {
    expect(await editorApi<boolean>(editorPage, (api) => api.isPdfEditor())).toBe(true);
  },
  // The fixture is one page holding one line of text.
  readContent: readPdfPageText,
});
