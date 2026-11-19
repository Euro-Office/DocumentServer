// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { selectCell, selectedCellText } from '../helpers';
import { describeOpeningStoredFixture } from '../open-stored-fixture.suite';

// Remit and the reasoning behind it: open-stored-fixture.suite.ts.
describeOpeningStoredFixture({
  label: 'Spreadsheet editor',
  noun: 'spreadsheet',
  ext: 'xlsx',
  tag: '@spreadsheet',
  rowClass: 'cell',
  urlExt: /\.xlsx/,
  editorApp: /spreadsheeteditor/,
  // The fixture's only value is in A1 of its only sheet. Selecting by name box
  // rather than trusting wherever the opening click left the cursor.
  readContent: async (editorPage, frame) => {
    await selectCell(frame, 'A1');
    return selectedCellText(editorPage);
  },
});
