// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { readShape } from '../helpers';
import { describeOpeningStoredFixture } from '../open-stored-fixture.suite';

// Remit and the reasoning behind it: open-stored-fixture.suite.ts.
describeOpeningStoredFixture({
  label: 'Presentation editor',
  noun: 'presentation',
  ext: 'pptx',
  tag: '@presentation',
  rowClass: 'slide',
  urlExt: /\.pptx/,
  editorApp: /presentationeditor/,
  // The fixture is one slide whose only shape is the title, so shape 1 holds
  // the whole of its content.
  readContent: async (editorPage, frame) => {
    await frame.locator('#editor_sdk').click();
    return readShape(editorPage, 1);
  },
});
