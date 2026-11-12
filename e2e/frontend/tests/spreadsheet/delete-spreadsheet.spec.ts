// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { describeStoredFileDeletion } from '../stored-file-delete.suite';

describeStoredFileDeletion({
  label: 'Spreadsheet',
  noun: 'spreadsheet',
  ext: 'xlsx',
  rowClass: 'cell',
});
