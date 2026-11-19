// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { readDocumentText } from '../helpers';
import { describeOpeningStoredFixture } from '../open-stored-fixture.suite';

// Remit and the reasoning behind it: open-stored-fixture.suite.ts.
describeOpeningStoredFixture({
  label: 'Document editor',
  noun: 'document',
  ext: 'docx',
  tag: '@document',
  rowClass: 'word',
  urlExt: /\.docx/,
  editorApp: /documenteditor/,
  // The fixture is a single paragraph, so Select All reads the whole of it.
  readContent: async (editorPage, frame) => {
    await frame.locator('#editor_sdk').click();
    return readDocumentText(editorPage);
  },
});
